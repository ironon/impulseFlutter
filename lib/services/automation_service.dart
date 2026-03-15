import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/automation_model.dart';

class AutomationService {
  static final AutomationService _instance = AutomationService._internal();
  factory AutomationService() => _instance;
  AutomationService._internal();

  static const String _automationsKey = 'automations';
  List<Automation> _automations = [];

  List<Automation> get automations => _automations;

  // Initialize and load automations
  Future<void> initialize() async {
    await _loadAutomations();
  }

  // Load automations from shared preferences
  Future<void> _loadAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? automationsJson = prefs.getString(_automationsKey);

    if (automationsJson != null) {
      final List<dynamic> decoded = jsonDecode(automationsJson);
      _automations = decoded
          .map((json) => Automation.fromJson(json))
          .toList();
    }
  }

  // Save automations to shared preferences
  Future<void> _saveAutomations() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      _automations.map((automation) => automation.toJson()).toList(),
    );
    await prefs.setString(_automationsKey, encoded);
  }

  // Add a new automation
  Future<void> addAutomation(Automation automation) async {
    _automations.add(automation);
    await _saveAutomations();
  }

  // Update an existing automation
  Future<void> updateAutomation(Automation automation) async {
    final index = _automations.indexWhere((a) => a.id == automation.id);
    if (index != -1) {
      _automations[index] = automation;
      await _saveAutomations();
    }
  }

  // Delete an automation
  Future<void> deleteAutomation(String automationId) async {
    _automations.removeWhere((a) => a.id == automationId);
    await _saveAutomations();
  }

  // Get automations for a specific date
  List<Automation> getAutomationsForDate(DateTime date) {
    return _automations
        .where((automation) => automation.appearsOnDate(date))
        .toList();
  }

  // Export automations for a specific date to JSON
  String exportAutomationsForDate(DateTime date) {
    final automationsForDate = getAutomationsForDate(date);
    final List<Map<String, dynamic>> jsonList = automationsForDate
        .map((automation) => automation.toJson())
        .toList();

    return jsonEncode({
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'automations': jsonList,
    });
  }

  // Calculate overlapping automations and their layout positions
  // Returns a map of automation ID to their column index and total columns
  Map<String, AutomationLayout> calculateAutomationLayouts(List<Automation> automations) {
    if (automations.isEmpty) return {};

    // Sort by start time, then by duration (longer first)
    final sorted = List<Automation>.from(automations)
      ..sort((a, b) {
        final startCompare = a.startMinutes.compareTo(b.startMinutes);
        if (startCompare != 0) return startCompare;
        return b.durationMinutes.compareTo(a.durationMinutes);
      });

    final Map<String, AutomationLayout> layouts = {};
    final List<List<Automation>> columns = [];

    for (final automation in sorted) {
      bool placed = false;

      // Try to place in existing columns
      for (int i = 0; i < columns.length; i++) {
        if (!_overlapsWithAny(automation, columns[i])) {
          columns[i].add(automation);
          placed = true;
          break;
        }
      }

      // If couldn't place in existing columns, create new column
      if (!placed) {
        columns.add([automation]);
      }
    }

    // Assign layout info to each automation
    for (int colIndex = 0; colIndex < columns.length; colIndex++) {
      for (final automation in columns[colIndex]) {
        layouts[automation.id] = AutomationLayout(
          columnIndex: colIndex,
          totalColumns: columns.length,
        );
      }
    }

    return layouts;
  }

  // Check if an automation overlaps with any in a list
  bool _overlapsWithAny(Automation automation, List<Automation> others) {
    for (final other in others) {
      if (_overlaps(automation, other)) {
        return true;
      }
    }
    return false;
  }

  // Check if two automations overlap in time
  bool _overlaps(Automation a, Automation b) {
    return a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes;
  }
}

// Helper class to store layout information for automations
class AutomationLayout {
  final int columnIndex;
  final int totalColumns;

  AutomationLayout({
    required this.columnIndex,
    required this.totalColumns,
  });
}
