import 'package:flutter/material.dart';

// ── Enumerations (match firmware spec exactly) ──────────────────────────────

enum RecurrenceType { once, daily, weekly, monthly }

enum Criteria { getAway, stayNear, getOffWifi, getOnWifi }

enum EnforcementProfile {
  strictSilent,
  normalSilent,
  looseSilent,
  strictBoth,
  normalBoth,
  looseBoth,
  strictBuzz,
  normalBuzz,
  looseBuzz,
}

enum AnchorEnforcementProfile { light, medium, hard }

// Human-readable labels for the UI
extension EnforcementProfileLabel on EnforcementProfile {
  String get label {
    switch (this) {
      case EnforcementProfile.strictSilent: return 'Strict – Vibrate only';
      case EnforcementProfile.normalSilent: return 'Normal – Vibrate only';
      case EnforcementProfile.looseSilent:  return 'Loose – Vibrate only';
      case EnforcementProfile.strictBoth:   return 'Strict – Buzz + Vibrate';
      case EnforcementProfile.normalBoth:   return 'Normal – Buzz + Vibrate';
      case EnforcementProfile.looseBoth:    return 'Loose – Buzz + Vibrate';
      case EnforcementProfile.strictBuzz:   return 'Strict – Buzz only';
      case EnforcementProfile.normalBuzz:   return 'Normal – Buzz only';
      case EnforcementProfile.looseBuzz:    return 'Loose – Buzz only';
    }
  }
}

extension AnchorProfileLabel on AnchorEnforcementProfile {
  String get label {
    switch (this) {
      case AnchorEnforcementProfile.light:  return 'Light (3s beep / 60s pause)';
      case AnchorEnforcementProfile.medium: return 'Medium (3s beep / 30s pause)';
      case AnchorEnforcementProfile.hard:   return 'Hard (4s beep / 10s pause)';
    }
  }
}

// ── Event / Automation model ─────────────────────────────────────────────────

class Automation {
  /// UUID v4 identifying this event.
  final String id;

  /// Reference date (UTC).
  /// For `once`: the specific calendar date.
  /// For recurring: the anchor date from which recurrence is computed.
  final DateTime referenceDate;

  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final RecurrenceType recurrenceType;

  /// 1–7 (Mon–Sun). Non-null only when [recurrenceType] == weekly.
  final int? dayOfWeek;

  /// 1–31. Non-null only when [recurrenceType] == monthly.
  final int? dayOfMonth;

  final Criteria criteria;
  final EnforcementProfile profile;
  final bool negate;

  /// UUID of the target anchor. Non-null for getAway / stayNear.
  final String? anchorId;

  /// Target WiFi network name. Non-null for getOnWifi / getOffWifi.
  final String? wifiSSID;

  /// UUIDs of anchors that should beep when the watch is removed.
  final List<String> beepAnchors;

  /// Required when [beepAnchors] is non-empty.
  final AnchorEnforcementProfile? anchorProfile;

  // ── UI-only ──
  final Color color;

  const Automation({
    required this.id,
    required this.referenceDate,
    required this.startTime,
    required this.endTime,
    required this.recurrenceType,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.criteria,
    required this.profile,
    this.negate = false,
    this.anchorId,
    this.wifiSSID,
    this.beepAnchors = const [],
    this.anchorProfile,
    required this.color,
  });

  // ── JSON serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'referenceDate': referenceDate.toIso8601String(),
        'startTimeHour': startTime.hour,
        'startTimeMinute': startTime.minute,
        'endTimeHour': endTime.hour,
        'endTimeMinute': endTime.minute,
        'recurrenceType': recurrenceType.name,
        'dayOfWeek': dayOfWeek,
        'dayOfMonth': dayOfMonth,
        'criteria': criteria.name,
        'profile': profile.name,
        'negate': negate,
        'anchorId': anchorId,
        'wifiSSID': wifiSSID,
        'beepAnchors': beepAnchors,
        'anchorProfile': anchorProfile?.name,
        'colorValue': color.toARGB32(),
      };

  factory Automation.fromJson(Map<String, dynamic> json) {
    return Automation(
      id: json['id'] as String,
      referenceDate: DateTime.parse(json['referenceDate'] as String),
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
      dayOfMonth: json['dayOfMonth'] as int?,
      criteria: Criteria.values.firstWhere(
        (e) => e.name == json['criteria'],
      ),
      profile: EnforcementProfile.values.firstWhere(
        (e) => e.name == (json['profile'] ?? 'normalSilent'),
      ),
      negate: json['negate'] as bool? ?? false,
      anchorId: json['anchorId'] as String?,
      wifiSSID: json['wifiSSID'] as String?,
      beepAnchors: (json['beepAnchors'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      anchorProfile: json['anchorProfile'] == null
          ? null
          : AnchorEnforcementProfile.values.firstWhere(
              (e) => e.name == json['anchorProfile'],
            ),
      color: Color(json['colorValue'] as int),
    );
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  Automation copyWith({
    String? id,
    DateTime? referenceDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    RecurrenceType? recurrenceType,
    int? dayOfWeek,
    int? dayOfMonth,
    Criteria? criteria,
    EnforcementProfile? profile,
    bool? negate,
    String? anchorId,
    String? wifiSSID,
    List<String>? beepAnchors,
    AnchorEnforcementProfile? anchorProfile,
    Color? color,
  }) {
    return Automation(
      id: id ?? this.id,
      referenceDate: referenceDate ?? this.referenceDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      criteria: criteria ?? this.criteria,
      profile: profile ?? this.profile,
      negate: negate ?? this.negate,
      anchorId: anchorId ?? this.anchorId,
      wifiSSID: wifiSSID ?? this.wifiSSID,
      beepAnchors: beepAnchors ?? this.beepAnchors,
      anchorProfile: anchorProfile ?? this.anchorProfile,
      color: color ?? this.color,
    );
  }

  // ── Date matching ─────────────────────────────────────────────────────────

  bool appearsOnDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final ref = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);

    switch (recurrenceType) {
      case RecurrenceType.once:
        return d == ref;
      case RecurrenceType.daily:
        return !d.isBefore(ref);
      case RecurrenceType.weekly:
        if (dayOfWeek == null) return false;
        return date.weekday == dayOfWeek && !d.isBefore(ref);
      case RecurrenceType.monthly:
        if (dayOfMonth == null) return false;
        return date.day == dayOfMonth && !d.isBefore(ref);
    }
  }

  // ── Computed time helpers ─────────────────────────────────────────────────

  int get startMinutes => startTime.hour * 60 + startTime.minute;
  int get endMinutes   => endTime.hour * 60 + endTime.minute;
  int get durationMinutes => endMinutes - startMinutes;
}
