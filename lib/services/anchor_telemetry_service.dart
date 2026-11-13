// Read-only anchor telemetry for the Debug screen's Meters tab (spec §8.13) and
// for dock positioning (§8.6, via DockSessionService's own link — this class is
// not used there).
//
// A session is one BLE connection that subscribes to Prox Score `…0009`, Dock
// Status `…000D` and Debug Telemetry `…0020`. On the nRF anchor the first two are
// dead ends: v3 §4.8 deleted the proximity/fingerprint block (`…0008`–`…000b`)
// and `…000D` returns a literal {0x00,0x00}, so only the `…0020` half of this
// session produces real telemetry. The anchor holds two links (this phone and the
// ranging watch, CONFIG_BT_MAX_CONN=2), so callers must keep sessions short and
// must call [dispose]. Decoding is intentionally inline and minimal: score is
// 0..255 score-space, RSSI is biased +128, flags are bit0 fingerprint-active /
// bit1 low-device-count. The Debug Telemetry payload has its own model
// ([AnchorDebugTelemetry], contract §4.3/§4.4, version 2).

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/debug_telemetry.dart';
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
  StreamSubscription<List<int>>? _debugSub;
  fbp.BluetoothCharacteristic? _debugChar;
  bool _debugReadInFlight = false;

  final _proxController = StreamController<ProxScoreReading>.broadcast();
  final _dockController = StreamController<DockStatusReading>.broadcast();
  final _debugController = StreamController<AnchorDebugTelemetry>.broadcast();

  Stream<ProxScoreReading> get proxStream => _proxController.stream;
  Stream<DockStatusReading> get dockStream => _dockController.stream;

  /// Decoded `…0020` snapshots (v2, contract §4.3). Notify is an 8-byte change
  /// hint only, so a hint — or a truncated value — triggers one guarded full
  /// read (see the listener in [connect]).
  Stream<AnchorDebugTelemetry> get debugStream => _debugController.stream;

  bool get connected => _device?.isConnected ?? false;

  /// Read + decode the anchor Debug Telemetry snapshot once (`…0020`, v2 —
  /// contract §4.3/§4.4). Null when this firmware does not expose `…0020` or
  /// the read/decode fails.
  Future<AnchorDebugTelemetry?> readDebugTelemetry() async {
    final ch = _debugChar;
    if (ch == null) return null;
    return _readDebug(ch);
  }

  Future<AnchorDebugTelemetry?> _readDebug(
      fbp.BluetoothCharacteristic ch) async {
    try {
      final bytes = await ch.read();
      final t = AnchorDebugTelemetry.decode(bytes);
      DebugLogService().log(
        'anchor_debug',
        'wifi=${t.wifiConnected} clock=${t.timeValid} '
        'beeping=${t.beeping}${t.beepProfile == null ? '' : ' (${t.beepProfileLabel})'} '
        'last=${t.lastCmd.label}→${t.lastCmdReason?.label ?? 'none'} '
        'transport=${t.lastCmdTransport?.label ?? 'none'} '
        'dock_supported=${t.dockSupported} events=${t.events.length}',
        bytes,
      );
      return t;
    } catch (e) {
      DebugLogService()
          .log('anchor_debug', 'read/decode failed: $e', const []);
      return null;
    }
  }

  /// One guarded full read after a change hint or a truncated value. Same
  /// reasoning as the watch side: flutter_blue_plus emits `read()` results on
  /// this stream too, so the guard is what stops the loop, and the read's own
  /// result is what the listener decodes.
  void _readDebugOnce(fbp.BluetoothCharacteristic ch) {
    if (_debugReadInFlight) return;
    _debugReadInFlight = true;
    ch.read()
        .catchError((_) => <int>[])
        .whenComplete(() => _debugReadInFlight = false);
  }

  /// Connect and subscribe. Returns false on any failure, having already torn
  /// down whatever half-open state was created. On success the caller owns the
  /// session and must call [dispose].
  ///
  /// Both characteristics are also read once, because subscribing to a value the
  /// anchor only notifies on change would otherwise leave the meters blank until
  /// the next transition.
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
          if (uuid == BleConstants.anchorDebugTelemetryV2CharUuid) {
            // v2 (§4.3/§4.5): notify is the 8-byte change hint, never the
            // payload. A hint or a truncated value triggers one guarded full
            // read; the read's own result comes back through this listener.
            _debugChar = c;
            try {
              await c.setNotifyValue(true);
            } catch (_) {}
            _debugSub = c.onValueReceived.listen((bytes) {
              if (AnchorDebugTelemetry.isHint(bytes)) {
                _readDebugOnce(c);
                return;
              }
              try {
                _debugController.add(AnchorDebugTelemetry.decode(bytes));
              } on FormatException catch (e) {
                if (!AnchorDebugTelemetry.looksTruncated(bytes)) {
                  dbg.log('anchor_debug', 'decode failed: $e', bytes);
                  return;
                }
                _readDebugOnce(c);
              }
            });
            // The initial read's value is emitted by the listener above.
            await _readDebug(c);
          }
        }
      }
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  /// Release the link and cancel subscriptions. Safe to call repeatedly.
  Future<void> disconnect() async {
    await _proxSub?.cancel();
    await _dockSub?.cancel();
    await _debugSub?.cancel();
    _proxSub = null;
    _dockSub = null;
    _debugSub = null;
    _debugChar = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }

  void dispose() {
    disconnect();
    _proxController.close();
    _dockController.close();
    _debugController.close();
  }
}
