// Read-only anchor telemetry for the Debug screen's Meters tab (spec §8.13) and
// for dock positioning (§8.6, via DockSessionService's own link — this class is
// not used there).
//
// A session is one BLE connection that subscribes to Prox Score `…0009`, Dock
// Status `…000D` and Debug Telemetry `…0020`. The anchor's connection budget is
// small (firmware §4.3: phone + watch + repair), so callers must keep sessions
// short and must call [dispose]. Decoding is intentionally inline and minimal:
// score is 0..255 score-space, RSSI is biased +128, flags are bit0
// fingerprint-active / bit1 low-device-count. The Debug Telemetry payload has
// its own model ([AnchorDebugTelemetry], firmware §4.4).

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

  /// Decoded `…0020` snapshots. Notify is a change hint only (the payload is
  /// longer than an ATT MTU), so a truncated notification triggers a full
  /// read (see the listener in [connect]).
  Stream<AnchorDebugTelemetry> get debugStream => _debugController.stream;

  bool get connected => _device?.isConnected ?? false;

  /// Read + decode the anchor Debug Telemetry snapshot once. Null when this
  /// firmware does not expose `…0020` or the read/decode fails.
  Future<AnchorDebugTelemetry?> readDebugTelemetry() async {
    final ch = _debugChar;
    if (ch == null) return null;
    return _readDebug(ch);
  }

  Future<AnchorDebugTelemetry?> _readDebug(
      fbp.BluetoothCharacteristic ch) async {
    try {
      final bytes = await ch.read();
      final t = AnchorDebugTelemetry.decode(bytes)
          .copyWithReceivedAt(DateTime.now());
      DebugLogService().log(
        'anchor_debug',
        'wifi=${t.wifiConnected} clock=${t.timeValid} '
        'beeping=${t.beeping}${t.dockAlarm ? ' (dock)' : ''} '
        'udp=${t.lastUdpCmdLabel}→${t.lastUdpResult.label} '
        'events=${t.relevantEvents.length}',
        bytes,
      );
      return t;
    } catch (e) {
      DebugLogService()
          .log('anchor_debug', 'read/decode failed: $e', const []);
      return null;
    }
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
          if (uuid == BleConstants.anchorDebugCharUuid) {
            // Notify is only a change hint (payload > MTU), so read on every
            // notification and once up front, exactly like the watch side.
            _debugChar = c;
            //
            // flutter_blue_plus's onValueReceived fires for read() results as
            // well as notifications, so "read on every value" would loop
            // forever. Instead decode what arrived: a complete value (a read
            // result, or a notification that fit the MTU) is emitted as is;
            // only a truncated notification fails to decode, and that
            // triggers one read whose result comes back through this same
            // listener complete.
            try {
              await c.setNotifyValue(true);
            } catch (_) {}
            _debugSub = c.onValueReceived.listen((bytes) {
              try {
                _debugController.add(AnchorDebugTelemetry.decode(bytes)
                    .copyWithReceivedAt(DateTime.now()));
              } on FormatException {
                // Re-read only a genuinely truncated v1 value; an unknown
                // version or malformed value would just fail again.
                if (_debugReadInFlight || !AnchorDebugTelemetry.looksTruncated(bytes)) return;
                _debugReadInFlight = true;
                c.read().catchError((_) => <int>[]).whenComplete(
                    () => _debugReadInFlight = false);
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
