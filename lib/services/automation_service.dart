import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/automation_model.dart';

class AutomationService {
  static final AutomationService _instance = AutomationService._internal();
  factory AutomationService() => _instance;
  AutomationService._internal();

  static const String _automationsKey = 'automations_v2';
  List<Automation> _automations = [];

  List<Automation> get automations => _automations;

  Future<void> initialize() async => _loadAutomations();

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

class AutomationLayout {
  final int columnIndex;
  final int totalColumns;
  const AutomationLayout({required this.columnIndex, required this.totalColumns});
}
