// The authored schedule: commitments (`Automation`) and their persistence.
//
// Backed by `automations_v2` in shared_preferences — plain JSON, no drift, because
// the schedule is the app's authoring copy rather than trust machinery (the
// integrity stores are in drift; see services/integrity_store.dart). The watch
// holds the enforced copy.
//
// Also home of the day-calendar overlap layout used by the Advanced blocks screen:
// events are packed into columns so overlapping blocks sit side by side.
//
// Mutation is via the three CRUD methods only; AppState is the only caller that
// should write (all edits must pass the self-binding gate first).

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/automation_model.dart';

/// Persistence + day queries for the authored schedule.
///
/// Only `AppState` should mutate this (every edit must pass the §8.9 gate first);
/// screens read `automations`/`getAutomationsForDate` through AppState or directly
/// for layout.
class AutomationService {
  static final AutomationService _instance = AutomationService._internal();
  factory AutomationService() => _instance;
  AutomationService._internal();

  static const String _automationsKey = 'automations_v2';
  List<Automation> _automations = [];

  List<Automation> get automations => _automations;

  Future<void> initialize() async => _loadAutomations();

  /// Drop every stored automation and the in-memory list (factory reset).
  ///
  /// Explicit rather than "wipe prefs then re-initialize": _loadAutomations()
  /// only assigns when the key is present, so re-initializing after a prefs
  /// clear would leave the previous list sitting in memory.
  Future<void> clearAll() async {
    _automations = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_automationsKey);
  }

  Future<void> _loadAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString(_automationsKey);
    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        _automations =
            decoded.map((j) => Automation.fromJson(j as Map<String, dynamic>)).toList();
      } catch (_) {
        _automations = [];
      }
    }
  }

  Future<void> _saveAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _automationsKey,
      jsonEncode(_automations.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> addAutomation(Automation a) async {
    _automations.add(a);
    await _saveAutomations();
  }

  Future<void> updateAutomation(Automation a) async {
    final idx = _automations.indexWhere((e) => e.id == a.id);
    if (idx != -1) {
      _automations[idx] = a;
      await _saveAutomations();
    }
  }

  Future<void> deleteAutomation(String id) async {
    _automations.removeWhere((a) => a.id == id);
    await _saveAutomations();
  }

  List<Automation> getAutomationsForDate(DateTime date) =>
      _automations.where((a) => a.appearsOnDate(date)).toList();

  // ── Layout helpers ────────────────────────────────────────────────────────
  // Greedy interval packing, not an optimal one: sort by start (longer first on a
  // tie), then place each event in the first column whose events it does not
  // overlap. `totalColumns` is global, so every block is drawn at the same width
  // (1/N of the grid) even where fewer columns are in use — that is what keeps the
  // Advanced day view readable at a glance.

  Map<String, AutomationLayout> calculateAutomationLayouts(
      List<Automation> automations) {
    if (automations.isEmpty) return {};

    final sorted = List<Automation>.from(automations)
      ..sort((a, b) {
        final sc = a.startMinutes.compareTo(b.startMinutes);
        return sc != 0 ? sc : b.durationMinutes.compareTo(a.durationMinutes);
      });

    final List<List<Automation>> columns = [];
    for (final automation in sorted) {
      bool placed = false;
      for (final col in columns) {
        if (!_overlapsAny(automation, col)) {
          col.add(automation);
          placed = true;
          break;
        }
      }
      if (!placed) columns.add([automation]);
    }

    final Map<String, AutomationLayout> layouts = {};
    for (int ci = 0; ci < columns.length; ci++) {
      for (final a in columns[ci]) {
        layouts[a.id] = AutomationLayout(columnIndex: ci, totalColumns: columns.length);
      }
    }
    return layouts;
  }

  bool _overlapsAny(Automation a, List<Automation> others) =>
      others.any((o) => a.startMinutes < o.endMinutes && o.startMinutes < a.endMinutes);
}

/// Where one event was placed by [AutomationService.calculateAutomationLayouts]:
/// which column it occupies and how many columns exist that day. `totalColumns` is
/// global to the day, so a block's width can shrink even when it has no neighbour in
/// its own column.
class AutomationLayout {
  final int columnIndex;
  final int totalColumns;
  const AutomationLayout({required this.columnIndex, required this.totalColumns});
}
