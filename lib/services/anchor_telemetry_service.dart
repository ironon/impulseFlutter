import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../utils/ble_constants.dart';
import 'debug_log_service.dart';

/// One live Prox Score reading (anchor `…0009`): `[score u8][flags u8]`.
class ProxScoreReading {
  final int score; // 0 = away … 255 = here
  final bool fingerprintActive; // flags bit0
  final bool lowDeviceCount; // flags bit1
  const ProxScoreReading({
    required this.score,
    required this.fingerprintActive,
    required this.lowDeviceCount,
  });
}

/// One live Dock Status reading (anchor `…000D`): `[docked u8][rssi+128 u8]`.
class DockStatusReading {
  final bool docked;
  final int rssi;
  const DockStatusReading({required this.docked, required this.rssi});
}

/// A read-only telemetry session against one anchor: subscribes to the Prox
/// Score and Dock Status characteristics for the debug meters (§8.13). Keep
/// sessions short-lived — the anchor's connection budget is limited (§9).
class AnchorTelemetrySession {
  AnchorTelemetrySession(this.bleRemoteId);

  final String bleRemoteId;
  fbp.BluetoothDevice? _device;
  StreamSubscription<List<int>>? _proxSub;
  StreamSubscription<List<int>>? _dockSub;

  final _proxController = StreamController<ProxScoreReading>.broadcast();
  final _dockController = StreamController<DockStatusReading>.broadcast();

  Stream<ProxScoreReading> get proxStream => _proxController.stream;
  Stream<DockStatusReading> get dockStream => _dockController.stream;

  bool get connected => _device?.isConnected ?? false;

  Future<bool> connect() async {
    final dbg = DebugLogService();
    try {
      final device = fbp.BluetoothDevice.fromId(bleRemoteId);
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.serviceUuid.str.toLowerCase() !=
            BleConstants.anchorServiceUuid) {
          continue;
        }
        for (final c in svc.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == BleConstants.anchorProxScoreCharUuid) {
            await c.setNotifyValue(true);
            _proxSub = c.onValueReceived.listen((bytes) {
              if (bytes.isEmpty) return;
              final flags = bytes.length > 1 ? bytes[1] : 0;
              final reading = ProxScoreReading(
                score: bytes[0],
                fingerprintActive: (flags & 0x01) != 0,
                lowDeviceCount: (flags & 0x02) != 0,
              );
              _proxController.add(reading);
              dbg.log('prox_score',
                  'score=${reading.score} fp=${reading.fingerprintActive} lowN=${reading.lowDeviceCount}',
                  bytes);
            });
            try {
              final v = await c.read();
              if (v.isNotEmpty) {
                _proxController.add(ProxScoreReading(
                  score: v[0],
                  fingerprintActive:
                      v.length > 1 && (v[1] & 0x01) != 0,
                  lowDeviceCount: v.length > 1 && (v[1] & 0x02) != 0,
                ));
              }
            } catch (_) {}
          }
          if (uuid == BleConstants.anchorDockStatusCharUuid) {
            await c.setNotifyValue(true);
            _dockSub = c.onValueReceived.listen((bytes) {
              if (bytes.length < 2) return;
              final reading = DockStatusReading(
                docked: bytes[0] != 0,
                rssi: bytes[1] - 128,
              );
              _dockController.add(reading);
              dbg.log('dock_status',
                  'docked=${reading.docked} rssi=${reading.rssi}', bytes);
            });
            try {
              final v = await c.read();
              if (v.length >= 2) {
                _dockController.add(
                    DockStatusReading(docked: v[0] != 0, rssi: v[1] - 128));
              }
            } catch (_) {}
          }
        }
      }
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _proxSub?.cancel();
    await _dockSub?.cancel();
    _proxSub = null;
    _dockSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }

  void dispose() {
    disconnect();
    _proxController.close();
    _dockController.close();
  }
}
