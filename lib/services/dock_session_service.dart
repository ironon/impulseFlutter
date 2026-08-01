import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/automation_model.dart';
import '../utils/ble_constants.dart';
import 'anchor_telemetry_service.dart';
import 'debug_log_service.dart';
import 'watch_service.dart';

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

  /// The link dropped mid-window and we are trying to get it back. Distinct
  /// from [linkLost]: the session is still ours, the window is still running,
  /// and no user action is needed yet.
  reconnecting,

  /// The window finished (or the user released); unregistered cleanly.
  ended,

  /// The link failed and could not be recovered. Phone-distance fails OPEN —
  /// the watch won't alarm on a bad link; the honest state is "the system can't
  /// see the phone".
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

  static const _prefsKey = 'dock_session_v1';

  /// Backoff schedule for reconnect attempts after a mid-window drop. Short at
  /// first (most drops are transient — the phone shifted on the dock), then
  /// easing off so a genuinely absent anchor doesn't burn the battery.
  static const List<Duration> _backoff = [
    Duration(seconds: 2),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  DockPhase _phase = DockPhase.idle;
  DockPhase get phase => _phase;

  Automation? _commitment;
  Automation? get commitment => _commitment;

  DockStatusReading? _lastDock;
  DockStatusReading? get lastDock => _lastDock;

  DateTime? _windowEnd;
  DateTime? get windowEnd => _windowEnd;

  /// How many consecutive reconnect attempts have failed. Surfaced so the UI
  /// can be honest that the block isn't currently holding.
  int _reconnectAttempts = 0;
  int get reconnectAttempts => _reconnectAttempts;

  Duration get remaining => _windowEnd == null
      ? Duration.zero
      : _windowEnd!.difference(DateTime.now()).isNegative
          ? Duration.zero
          : _windowEnd!.difference(DateTime.now());

  fbp.BluetoothDevice? _device;
  String? _anchorRemoteId;
  fbp.BluetoothCharacteristic? _dockRegisterChar;
  fbp.BluetoothCharacteristic? _dockStatusChar;
  StreamSubscription<List<int>>? _dockSub;
  StreamSubscription<fbp.BluetoothConnectionState>? _connSub;
  Timer? _ticker;
  Timer? _retryTimer;

  /// The watch link we stood down for the duration of this session, so it can
  /// be restored afterwards. See [_releaseWatchLink].
  fbp.BluetoothDevice? _standDownWatch;

  bool get docked => _lastDock?.docked ?? false;

  /// The anchor↔phone link RSSI at or above which the anchor calls the phone
  /// docked (`DOCK_RSSI_THRESHOLD_DBM`, AnchorFirmware/src/main.cpp). Mirrored
  /// here only to show the user what they're aiming at; the anchor decides.
  static const int dockThresholdDbm = -60;

  /// True once Dock Register 0x01 has been written, i.e. the anchor is
  /// measuring this link's RSSI.
  ///
  /// This happens as soon as the link opens, NOT when the user taps Start. The
  /// anchor can only report an RSSI for a connection it has been told to
  /// measure — an unregistered link reads back {docked:0, rssi:0}, which the
  /// positioning meter rendered as -128 dBm. That made "Place the phone on the
  /// dock" unwinnable: no matter how close the phone got, the meter sat at zero
  /// and the copy stayed on "Closer — set it right on the anchor", because
  /// nothing was being measured yet. §8.6 puts the meter at step 2 and the
  /// register write at step 4; those two orderings are incompatible, and the
  /// meter is the one users can see.
  bool _measuring = false;

  /// True once the user has started the window. Distinct from [_measuring]:
  /// only a live window is worth chasing a dropped link for.
  bool _windowLive = false;

  // ── Pre-session: connect + position (§8.6 steps 2–3) ─────────────────────

  /// Connect to the docking anchor and start streaming Dock Status so the
  /// user can position the phone. [bleRemoteId] is the anchor's BLE id.
  Future<bool> beginPositioning(
      Automation commitment, String bleRemoteId) async {
    await endSession(notify: false);
    _commitment = commitment;
    _anchorRemoteId = bleRemoteId;
    _setPhase(DockPhase.connecting);

    // The watch must not be holding a peripheral link to this phone while it
    // central-connects to the anchor for its proximity polls: concurrent
    // peripheral+central is the documented NimBLE ble_hs_timer_exp crash
    // (firmware_spec_v2.md §10.1, tests/version_bump.md §6), and a phoneAway
    // window makes the watch do exactly that every poll. Calibration already
    // serialises the two roles this way ("Option A"); a dock session needs the
    // same courtesy. The link is restored in endSession().
    await _releaseWatchLink();

    final ok = await _openLink();
    if (!ok) {
      await _teardownLink();
      _setPhase(DockPhase.linkLost);
      return false;
    }
    _setPhase(DockPhase.positioning);
    return true;
  }

  /// Opens the anchor link and wires up Dock Status. Shared by the initial
  /// connect and every reconnect attempt.
  Future<bool> _openLink() async {
    final id = _anchorRemoteId;
    if (id == null) return false;
    try {
      final device = fbp.BluetoothDevice.fromId(id);
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      _dockRegisterChar = null;
      _dockStatusChar = null;
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
      if (_dockRegisterChar == null || _dockStatusChar == null) return false;

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

      _connSub = device.connectionState.listen((s) {
        if (s == fbp.BluetoothConnectionState.disconnected) _onDropped();
      });

      // Register immediately so the anchor starts measuring this link — the
      // positioning meter is meaningless until it does (see [_measuring]).
      try {
        await _dockRegisterChar!.write([0x01], withoutResponse: false);
        _measuring = true;
        DebugLogService()
            .log('dock', 'registered for measurement', [0x01]);
      } catch (_) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Start (§8.6 step 4): register this connection as the docking phone ───

  Future<bool> start() async {
    if (_phase != DockPhase.positioning || _dockRegisterChar == null) {
      return false;
    }
    try {
      // Already registered in _openLink(); re-assert only if that failed.
      if (!_measuring) {
        await _dockRegisterChar!.write([0x01], withoutResponse: false);
        _measuring = true;
      }
      DebugLogService().log('dock', 'window started', [0x01]);
      _windowLive = true;

      _windowEnd = _computeWindowEnd(_commitment!);
      await _persist();
      await _setWakelock(true);
      _startTicker();
      _setPhase(DockPhase.active);
      return true;
    } catch (_) {
      _setPhase(DockPhase.linkLost);
      return false;
    }
  }

  DateTime _computeWindowEnd(Automation c) {
    final now = DateTime.now();
    var end = DateTime(now.year, now.month, now.day)
        .add(Duration(minutes: c.endMinutes));
    if (end.isBefore(now)) {
      // Window belongs to tomorrow (docked ahead of time near midnight).
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (remaining == Duration.zero) {
        endSession();
      } else {
        notifyListeners(); // countdown tick
      }
    });
  }

  // ── Link loss + recovery ─────────────────────────────────────────────────

  /// Called whenever the anchor link drops. Before Dock Register is written
  /// this is just a failed setup; after it, the window is running and the link
  /// is worth chasing — the watch reads a missing phone as "undocked", which
  /// is the alarming direction, so silent give-up is the wrong default.
  void _onDropped() {
    if (_phase != DockPhase.active &&
        _phase != DockPhase.positioning &&
        _phase != DockPhase.reconnecting) {
      return;
    }
    // A drop during positioning is just a failed setup — the user is standing
    // right there and can retry. Only a live window is chased.
    if (!_windowLive) {
      _setPhase(DockPhase.linkLost);
      return;
    }
    if (remaining == Duration.zero) {
      endSession();
      return;
    }
    _setPhase(DockPhase.reconnecting);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final d = _backoff[
        _reconnectAttempts < _backoff.length ? _reconnectAttempts : _backoff.length - 1];
    _retryTimer = Timer(d, _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (_phase != DockPhase.reconnecting) return;
    if (remaining == Duration.zero) {
      await endSession();
      return;
    }
    _reconnectAttempts++;

    _measuring = false;
    await _teardownLink(disconnect: true);
    // _openLink() re-writes Dock Register 0x01. That re-registration is not
    // optional: the anchor drops its docking-phone handle on disconnect (§4.11),
    // so a reconnect without it leaves the anchor reporting undocked forever
    // over a perfectly healthy link.
    if (await _openLink()) {
      DebugLogService().log('dock', 're-registered after reconnect', [0x01]);
      _reconnectAttempts = 0;
      _startTicker();
      _setPhase(DockPhase.active);
      return;
    }
    _scheduleRetry();
    notifyListeners();
  }

  // ── End of window / release (§8.6 end) ───────────────────────────────────

  /// Unregister (write 0x00) and release the connection. Called at window end
  /// or when the user releases early — releasing doesn't bypass anything: the
  /// watch simply treats an undocked phone as in-hand.
  Future<void> endSession({bool notify = true}) async {
    _ticker?.cancel();
    _ticker = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      if (_dockRegisterChar != null && (_device?.isConnected ?? false)) {
        await _dockRegisterChar!.write([0x00], withoutResponse: false);
        DebugLogService().log('dock', 'unregistered', [0x00]);
      }
    } catch (_) {}
    await _teardownLink(disconnect: true);

    final hadSession = _phase == DockPhase.active ||
        _phase == DockPhase.reconnecting;
    _lastDock = null;
    _windowEnd = null;
    _measuring = false;
    _windowLive = false;
    _reconnectAttempts = 0;
    _anchorRemoteId = null;
    await _setWakelock(false);
    await _clearPersisted();
    await _restoreWatchLink();

    if (notify) {
      _phase = hadSession ? DockPhase.ended : DockPhase.idle;
      notifyListeners();
    } else {
      _phase = DockPhase.idle;
    }
  }

  /// Drops the BLE resources without touching session state, so a reconnect
  /// can rebuild them.
  Future<void> _teardownLink({bool disconnect = false}) async {
    await _dockSub?.cancel();
    await _connSub?.cancel();
    _dockSub = null;
    _connSub = null;
    if (disconnect) {
      try {
        await _device?.disconnect();
      } catch (_) {}
    }
    _device = null;
    _dockRegisterChar = null;
    _dockStatusChar = null;
  }

  /// Back to idle after the "ended"/"linkLost" summary is acknowledged.
  void dismiss() {
    if (_phase == DockPhase.ended || _phase == DockPhase.linkLost) {
      _commitment = null;
      _setPhase(DockPhase.idle);
    }
  }

  // ── Watch-link stand-down (dual-role crash avoidance) ────────────────────

  Future<void> _releaseWatchLink() async {
    final ws = WatchService();
    if (!ws.isConnected) return;
    _standDownWatch = ws.device;
    DebugLogService()
        .log('dock', 'standing down watch link for dock session', const []);
    try {
      await ws.disconnect();
    } catch (_) {}
  }

  Future<void> _restoreWatchLink() async {
    final d = _standDownWatch;
    _standDownWatch = null;
    if (d == null) return;
    try {
      await WatchService().connect(d);
      DebugLogService().log('dock', 'watch link restored', const []);
    } catch (_) {
      // Not fatal: the connection screen reconnects on its own.
    }
  }

  // ── Screen wakelock ──────────────────────────────────────────────────────

  Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // Unsupported platform (e.g. tests) — the session still runs, it just
      // depends on the user keeping the screen alive.
    }
  }

  // ── Persistence across an app restart ────────────────────────────────────

  Future<void> _persist() async {
    final c = _commitment;
    final id = _anchorRemoteId;
    final end = _windowEnd;
    if (c == null || id == null || end == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_prefsKey, [
        c.id,
        id,
        end.millisecondsSinceEpoch.toString(),
      ]);
    } catch (_) {}
  }

  Future<void> _clearPersisted() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsKey);
    } catch (_) {}
  }

  /// Re-establish a session that was running when the app died. Returns true if
  /// a session was resumed. [lookup] resolves the stored commitment id.
  ///
  /// Without this, an app restart mid-window leaves the anchor with no
  /// registered phone — which the watch reads as "undocked", i.e. as the user
  /// having picked the phone up. Losing the app should not look like cheating.
  Future<bool> tryRestore(Automation? Function(String id) lookup) async {
    if (_phase != DockPhase.idle) return false;
    List<String>? saved;
    try {
      final p = await SharedPreferences.getInstance();
      saved = p.getStringList(_prefsKey);
    } catch (_) {
      return false;
    }
    if (saved == null || saved.length < 3) return false;

    final end = DateTime.fromMillisecondsSinceEpoch(int.tryParse(saved[2]) ?? 0);
    if (!end.isAfter(DateTime.now())) {
      await _clearPersisted();
      return false;
    }
    final commitment = lookup(saved[0]);
    if (commitment == null) {
      await _clearPersisted();
      return false;
    }

    _commitment = commitment;
    _anchorRemoteId = saved[1];
    _windowEnd = end;
    _setPhase(DockPhase.connecting);
    await _releaseWatchLink();

    if (await _openLink()) {
      try {
        // _openLink() already registered; this is the window state.
        _windowLive = true;
        _reconnectAttempts = 0;
        await _setWakelock(true);
        _startTicker();
        _setPhase(DockPhase.active);
        DebugLogService().log('dock', 'session restored after restart', [0x01]);
        return true;
      } catch (_) {}
    }
    // Couldn't get back on the dock: keep the session and chase it rather than
    // dropping the user into "nothing is running".
    _windowLive = true;
    _setPhase(DockPhase.reconnecting);
    _scheduleRetry();
    return true;
  }

  void _setPhase(DockPhase p) {
    _phase = p;
    notifyListeners();
  }
}
