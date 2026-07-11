import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_model.dart';
import 'self_binding_policy.dart';

/// Interim app-side persistence of per-event settle state (§8.9 / firmware
/// §9.2: `last_edit` + `settled_baseline`). The authoritative copy lives on the
/// watch; this drives previews and interim enforcement until that phase ships.
///
/// Kept in `shared_preferences` (simple per-event record), not drift: the drift
/// stores are reserved for the pending queue, pass ledger and audit trail (§2).
class SettleStateStore {
  static const _key = 'settle_state_v1';

  final Map<String, _Entry> _entries = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _entries.clear();
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((id, v) {
      _entries[id] = _Entry.fromJson(v as Map<String, dynamic>);
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  SettleState? stateFor(String eventId) {
    final e = _entries[eventId];
    if (e == null) return null;
    return SettleState(
      lastEdit: e.lastEdit,
      settledBaseline: e.baseline,
    );
  }

  /// Record that an event was edited/accepted now, resetting its settle timer.
  Future<void> recordEdit(String eventId, DateTime now) async {
    final existing = _entries[eventId];
    _entries[eventId] = _Entry(lastEdit: now, baseline: existing?.baseline);
    await _save();
  }

  /// Called when an event first appears (creation): no baseline yet.
  Future<void> recordCreate(String eventId, DateTime now) async {
    _entries[eventId] = _Entry(lastEdit: now, baseline: null);
    await _save();
  }

  /// Snapshot the current state as the settled baseline (called once the
  /// settle window elapses with no edit).
  Future<void> settle(String eventId, Automation current, DateTime now) async {
    _entries[eventId] = _Entry(
      lastEdit: _entries[eventId]?.lastEdit ?? now,
      baseline: current,
    );
    await _save();
  }

  Future<void> remove(String eventId) async {
    _entries.remove(eventId);
    await _save();
  }

  /// Promote any events whose settle window has elapsed into a settled baseline.
  Future<void> settleDue(
      List<Automation> current, DateTime now, Duration settleWindow) async {
    var changed = false;
    for (final e in current) {
      final entry = _entries[e.id];
      if (entry == null) continue;
      final settled = !now.isBefore(entry.lastEdit.add(settleWindow));
      if (settled && entry.baseline == null) {
        _entries[e.id] = _Entry(lastEdit: entry.lastEdit, baseline: e);
        changed = true;
      }
    }
    if (changed) await _save();
  }
}

class _Entry {
  final DateTime lastEdit;
  final Automation? baseline;
  _Entry({required this.lastEdit, this.baseline});

  Map<String, dynamic> toJson() => {
        'lastEdit': lastEdit.toIso8601String(),
        'baseline': baseline?.toJson(),
      };

  factory _Entry.fromJson(Map<String, dynamic> json) => _Entry(
        lastEdit: DateTime.parse(json['lastEdit'] as String),
        baseline: json['baseline'] == null
            ? null
            : Automation.fromJson(json['baseline'] as Map<String, dynamic>),
      );
}
