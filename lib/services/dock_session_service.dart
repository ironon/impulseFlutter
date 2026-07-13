import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/automation_model.dart';
import '../utils/ble_constants.dart';
import 'anchor_telemetry_service.dart';
import 'debug_log_service.dart';

/// Where a docking session is in its life (§8.6).
enum DockPhase {
  /// No session.
  idle,

  /// Connecting to the docking anchor.
  connecting,

  /// Connected; guiding the phone onto the dock (pre-session).
  positioning,

  /// Dock Register written (0x01); the phone↔anchor link is live and the
  /// window is running.
  active,

  /// The window finished (or the user released); unregistered cleanly.
  ended,

  /// The link failed. Phone-distance fails OPEN — the watch won't alarm on a
  /// bad link; the honest state is "the system can't see the phone".
  linkLost,
}

/// Manages one phone-docking session (§8.6, Mode B): the persistent phone↔
/// anchor BLE connection, the Dock Register handshake, live Dock Status, and
/// the window countdown. Outlives the dock screen so navigating away doesn't
/// drop the link.
///
/// Reliability framing (impulse_overview.md §3.2): enforcement follows link
/// quality. If this link is solid the watch can trust "docked"; if it
/// degrades the system fails open rather than alarm falsely. Keeping the app
/// open, the phone on the dock, and low-power mode off is the user's side of
/// the deal — the UI says so plainly.
class DockSessionService extends ChangeNotifier {
  static final DockSessionService _instance = DockSessionService._internal();
  factory DockSessionService() => _instance;
  DockSessionService._internal();

  DockPhase _phase = DockPhase.idle;
  DockPhase get phase => _phase;

  Automation? _commitment;
  Automation? get commitment => _commitment;

  DockStatusReading? _lastDock;
  DockStatusReading? get lastDock => _lastDock;

  DateTime? _windowEnd;
  DateTime? get windowEnd => _windowEnd;

  Duration get remaining => _windowEnd == null
      ? Duration.zero
      : _windowEnd!.difference(DateTime.now()).isNegative
          ? Duration.zero
          : _windowEnd!.difference(DateTime.now());

  fbp.BluetoothDevice? _device;
  fbp.BluetoothCharacteristic? _dockRegisterChar;
  fbp.BluetoothCharacteristic? _dockStatusChar;
  StreamSubscription<List<int>>? _dockSub;
  StreamSubscription<fbp.BluetoothConnectionState>? _connSub;
  Timer? _ticker;

  bool get docked => _lastDock?.docked ?? false;

  // ── Pre-session: connect + position (§8.6 steps 2–3) ─────────────────────

  /// Connect to the docking anchor and start streaming Dock Status so the
  /// user can position the phone. [bleRemoteId] is the anchor's BLE id.
  Future<bool> beginPositioning(
      Automation commitment, String bleRemoteId) async {
    await endSession(notify: false);
    _commitment = commitment;
    _setPhase(DockPhase.connecting);

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
          if (uuid == BleConstants.anchorDockRegisterCharUuid) {
            _dockRegisterChar = c;
          }
          if (uuid == BleConstants.anchorDockStatusCharUuid) {
            _dockStatusChar = c;
          }
        }
      }
      if (_dockRegisterChar == null || _dockStatusChar == null) {
        await endSession(notify: false);
        _setPhase(DockPhase.linkLost);
        return false;
      }

      await _dockStatusChar!.setNotifyValue(true);
      _dockSub = _dockStatusChar!.onValueReceived.listen((bytes) {
        if (bytes.length < 2) return;
        _lastDock =
            DockStatusReading(docked: bytes[0] != 0, rssi: bytes[1] - 128);
        notifyListeners();
      });
      try {
        final v = await _dockStatusChar!.read();
        if (v.length >= 2) {
          _lastDock = DockStatusReading(docked: v[0] != 0, rssi: v[1] - 128);
        }
      } catch (_) {}

      // Fail-open on drops: report honestly, never pretend the link is fine.
      _connSub = device.connectionState.listen((s) {
        if (s == fbp.BluetoothConnectionState.disconnected &&
            (_phase == DockPhase.active ||
                _phase == DockPhase.positioning)) {
          _setPhase(DockPhase.linkLost);
        }
      });

      _setPhase(DockPhase.positioning);
      return true;
    } catch (_) {
      await endSession(notify: false);
      _setPhase(DockPhase.linkLost);
      return false;
    }
  }

  // ── Start (§8.6 step 4): register this connection as the docking phone ───

  Future<bool> start() async {
    if (_phase != DockPhase.positioning || _dockRegisterChar == null) {
      return false;
    }
    try {
      await _dockRegisterChar!.write([0x01], withoutResponse: false);
      DebugLogService().log('dock', 'registered as docking phone', [0x01]);

      final c = _commitment!;
      final now = DateTime.now();
      _windowEnd = DateTime(now.year, now.month, now.day)
          .add(Duration(minutes: c.endMinutes));
      if (_windowEnd!.isBefore(now)) {
        // Window belongs to tomorrow (docked ahead of time near midnight).
        _windowEnd = _windowEnd!.add(const Duration(days: 1));
      }

      _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
        if (remaining == Duration.zero) {
          endSession();
        } else {
          notifyListeners(); // countdown tick
        }
      });
      _setPhase(DockPhase.active);
      return true;
    } catch (_) {
      _setPhase(DockPhase.linkLost);
      return false;
    }
  }

  // ── End of window / release (§8.6 end) ───────────────────────────────────

  /// Unregister (write 0x00) and release the connection. Called at window end
  /// or when the user releases early — releasing doesn't bypass anything: the
  /// watch simply treats an undocked phone as in-hand.
  Future<void> endSession({bool notify = true}) async {
    _ticker?.cancel();
    _ticker = null;
    try {
      if (_dockRegisterChar != null && (_device?.isConnected ?? false)) {
        await _dockRegisterChar!.write([0x00], withoutResponse: false);
        DebugLogService().log('dock', 'unregistered', [0x00]);
      }
    } catch (_) {}
    await _dockSub?.cancel();
    await _connSub?.cancel();
    _dockSub = null;
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _dockRegisterChar = null;
    _dockStatusChar = null;
    _lastDock = null;
    final hadSession = _phase == DockPhase.active;
    _windowEnd = null;
    if (notify) {
      _phase = hadSession ? DockPhase.ended : DockPhase.idle;
      notifyListeners();
    } else {
      _phase = DockPhase.idle;
    }
  }

  /// Back to idle after the "ended"/"linkLost" summary is acknowledged.
  void dismiss() {
    if (_phase == DockPhase.ended || _phase == DockPhase.linkLost) {
      _commitment = null;
      _setPhase(DockPhase.idle);
    }
  }

  void _setPhase(DockPhase p) {
    _phase = p;
    notifyListeners();
  }
}
