import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The pushable payload classes tracked for sync state (§8.16). Each class has a
/// monotonic **current revision** (the authoring copy) and, per device, a
/// **last-acked revision**. Staleness is *derived* — `current > acked` — never a
/// stored flag (flags rot; §8.16).
class SyncClass {
  // Watch-targeted (global) classes.
  static const schedule = 'schedule'; // watch + all anchors
  static const watchSettings = 'watchSettings';
  static const watchNetworks = 'watchNetworks';
  static const watchIpTable = 'watchIpTable';
  // Anchor-scoped classes (key suffixed with the anchor uuid).
  static const anchorSettings = 'anchorSettings';
  static const anchorWifiCreds = 'anchorWifiCreds';

  /// Per-anchor key: `<class>:<anchorUuid>`.
  static String anchorKey(String cls, String uuid) => '$cls:$uuid';
}

/// Persists current + per-device acked revisions (§8.16). This is *device
/// state*, not integrity-trust machinery, so `shared_preferences` is fine.
///
/// On reinstall the acked maps are absent → every class reads behind → the app
/// re-pushes and converges. Pessimistic by construction.
class SyncStateStore {
  static const _currentKey = 'sync_current_revs';
  static String _ackedKey(String deviceId) => 'sync_acked_$deviceId';

  Map<String, int> _current = {};
  final Map<String, Map<String, int>> _acked = {}; // deviceId -> classKey -> rev

  Future<void> loadCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentKey);
    if (raw != null) {
      _current = (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int));
    }
  }

  /// Load acked revisions for a device (idempotent — safe to call repeatedly).
  Future<void> loadDevice(String deviceId) async {
    if (_acked.containsKey(deviceId)) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ackedKey(deviceId));
    _acked[deviceId] = raw == null
        ? <String, int>{}
        : (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int));
  }

  Future<void> _persistCurrent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentKey, jsonEncode(_current));
  }

  Future<void> _persistDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _ackedKey(deviceId), jsonEncode(_acked[deviceId] ?? {}));
  }

  int current(String classKey) => _current[classKey] ?? 0;
  int acked(String deviceId, String classKey) =>
      _acked[deviceId]?[classKey] ?? 0;

  /// Bump a class's current revision (an authoring edit changed it). Returns the
  /// new revision.
  Future<int> bump(String classKey) async {
    final next = current(classKey) + 1;
    _current[classKey] = next;
    await _persistCurrent();
    return next;
  }

  /// Record that [deviceId] acknowledged [classKey] at [rev] (defaults to the
  /// current revision — a confirmed push). A *sent-but-unacked* update must
  /// NOT call this (optimistic tracking would show green over a dropped write).
  Future<void> setAcked(String deviceId, String classKey, [int? rev]) async {
    final map = _acked.putIfAbsent(deviceId, () => <String, int>{});
    map[classKey] = rev ?? current(classKey);
    await _persistDevice(deviceId);
  }

  /// Force a device's ack for a class *behind* current (e.g. an authoritative
  /// CRC mismatch proved it's out of date even though the app believed it had
  /// pushed). §8.16: "mismatch → stale, even if the app believed it pushed."
  Future<void> markBehind(String deviceId, String classKey) async {
    final cur = current(classKey);
    if (cur == 0) return; // nothing to be behind on
    final map = _acked.putIfAbsent(deviceId, () => <String, int>{});
    if ((map[classKey] ?? 0) >= cur) {
      map[classKey] = cur - 1;
      await _persistDevice(deviceId);
    }
  }

  bool isBehind(String deviceId, String classKey) =>
      current(classKey) > acked(deviceId, classKey);
}
