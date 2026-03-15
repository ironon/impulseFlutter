import 'package:flutter/material.dart';

enum RecurrenceType {
  once,
  daily,
  weekly,
}

enum Criteria {
  getAway,
  stayNear,
}

enum Importance {
  low,
  medium,
  high,
}

class Automation {
  final String id;
  final DateTime date; // For 'once' type, the specific date. For recurring, the reference date
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final RecurrenceType recurrenceType;
  final int? dayOfWeek; // 1-7 for Monday-Sunday, only used for weekly recurrence
  final String deviceId;
  final Criteria criteria;
  final Color color;
  final bool strictMode;
  final Importance importance;

  Automation({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.recurrenceType,
    this.dayOfWeek,
    required this.deviceId,
    required this.criteria,
    required this.color,
    required this.strictMode,
    required this.importance,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'startTimeHour': startTime.hour,
      'startTimeMinute': startTime.minute,
      'endTimeHour': endTime.hour,
      'endTimeMinute': endTime.minute,
      'recurrenceType': recurrenceType.name,
      'dayOfWeek': dayOfWeek,
      'deviceId': deviceId,
      'criteria': criteria.name,
      'colorValue': color.toARGB32(),
      'strictMode': strictMode,
      'importance': importance.name,
    };
  }

  // Create from JSON
  factory Automation.fromJson(Map<String, dynamic> json) {
    return Automation(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: TimeOfDay(
        hour: json['startTimeHour'] as int,
        minute: json['startTimeMinute'] as int,
      ),
      endTime: TimeOfDay(
        hour: json['endTimeHour'] as int,
        minute: json['endTimeMinute'] as int,
      ),
      recurrenceType: RecurrenceType.values.firstWhere(
        (e) => e.name == json['recurrenceType'],
      ),
      dayOfWeek: json['dayOfWeek'] as int?,
      deviceId: json['deviceId'] as String,
      criteria: Criteria.values.firstWhere(
        (e) => e.name == json['criteria'],
      ),
      color: Color(json['colorValue'] as int),
      strictMode: json['strictMode'] as bool,
      importance: Importance.values.firstWhere(
        (e) => e.name == json['importance'],
      ),
    );
  }

  // Create a copy with updated values
  Automation copyWith({
    String? id,
    DateTime? date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    RecurrenceType? recurrenceType,
    int? dayOfWeek,
    String? deviceId,
    Criteria? criteria,
    Color? color,
    bool? strictMode,
    Importance? importance,
  }) {
    return Automation(
      id: id ?? this.id,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      deviceId: deviceId ?? this.deviceId,
      criteria: criteria ?? this.criteria,
      color: color ?? this.color,
      strictMode: strictMode ?? this.strictMode,
      importance: importance ?? this.importance,
    );
  }

  // Check if this automation should appear on a given date
  bool appearsOnDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedAutomationDate = DateTime(
      this.date.year,
      this.date.month,
      this.date.day,
    );

    switch (recurrenceType) {
      case RecurrenceType.once:
        return normalizedDate == normalizedAutomationDate;
      case RecurrenceType.daily:
        // Appears on all dates on or after the start date
        return normalizedDate.isAfter(normalizedAutomationDate) ||
            normalizedDate == normalizedAutomationDate;
      case RecurrenceType.weekly:
        if (dayOfWeek == null) return false;
        // Check if the date is on the correct day of week and after/on start date
        return date.weekday == dayOfWeek &&
            (normalizedDate.isAfter(normalizedAutomationDate) ||
                normalizedDate == normalizedAutomationDate);
    }
  }

  // Get start time in minutes since midnight
  int get startMinutes => startTime.hour * 60 + startTime.minute;

  // Get end time in minutes since midnight
  int get endMinutes => endTime.hour * 60 + endTime.minute;

  // Get duration in minutes
  int get durationMinutes => endMinutes - startMinutes;
}
