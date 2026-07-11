import 'package:flutter/material.dart';

// ── Enumerations (match firmware spec exactly) ──────────────────────────────

enum RecurrenceType { once, daily, weekly, monthly }

enum Criteria { getAway, stayNear, getOffWifi, getOnWifi, phoneAway }

/// App-side-only provenance of a commitment block (§2A.1). Never sent to the
/// firmware; the schedule wire format is unchanged.
enum TemplateOrigin { manual, sunriseLock, studyTime, gymTime, phoneFree }

/// Friendly user-facing labels for commitment criteria.
/// Copy follows the voice guide (impulse_overview.md §7): no "enforcement".
extension CriteriaLabel on Criteria {
  String get label {
    switch (this) {
      case Criteria.getAway:    return 'Get away from anchor';
      case Criteria.stayNear:   return 'Stay near anchor';
      case Criteria.getOffWifi: return 'Get off WiFi';
      case Criteria.getOnWifi:  return 'Get on WiFi';
      case Criteria.phoneAway:  return 'Phone away';
    }
  }
}

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

  /// Seconds of post-donning enforcement grace (firmware §5.4.4). 0 = none.
  /// Clamp 0–1800 in the UI. Serialized into the v2 schedule blob.
  final int donningGraceS;

  // ── App-side-only template metadata (§2A.1) ──
  // Never transmitted to devices; persisted locally alongside the commitment.

  /// Where this block came from: hand-authored (`manual`) or a template kind.
  final TemplateOrigin origin;

  /// Groups the block(s) one template expansion produced. Null for manual
  /// blocks. Designed 1-to-many even though most v1 templates are 1-to-1.
  final String? templateInstanceId;

  /// The friendly template params the user entered, so Normal mode can
  /// re-render/edit the template and regenerate its block(s).
  final Map<String, dynamic> templateParams;

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
    this.donningGraceS = 0,
    this.origin = TemplateOrigin.manual,
    this.templateInstanceId,
    this.templateParams = const {},
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
        'donningGraceS': donningGraceS,
        'origin': origin.name,
        'templateInstanceId': templateInstanceId,
        'templateParams': templateParams,
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
      donningGraceS: (json['donningGraceS'] as int?) ?? 0,
      origin: TemplateOrigin.values.firstWhere(
        (e) => e.name == (json['origin'] ?? 'manual'),
        orElse: () => TemplateOrigin.manual,
      ),
      templateInstanceId: json['templateInstanceId'] as String?,
      templateParams: (json['templateParams'] as Map<String, dynamic>?) ?? const {},
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
    int? donningGraceS,
    TemplateOrigin? origin,
    String? templateInstanceId,
    bool clearTemplateInstanceId = false,
    Map<String, dynamic>? templateParams,
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
      donningGraceS: donningGraceS ?? this.donningGraceS,
      origin: origin ?? this.origin,
      templateInstanceId: clearTemplateInstanceId
          ? null
          : (templateInstanceId ?? this.templateInstanceId),
      templateParams: templateParams ?? this.templateParams,
      anchorId: anchorId ?? this.anchorId,
      wifiSSID: wifiSSID ?? this.wifiSSID,
      beepAnchors: beepAnchors ?? this.beepAnchors,
      anchorProfile: anchorProfile ?? this.anchorProfile,
      color: color ?? this.color,
    );
  }

  /// Detach a template-produced block to manual (§2A.3): flips origin→manual
  /// and clears the template instance grouping, so the Normal-mode card no
  /// longer claims a block the user hand-modified.
  Automation detachToManual() => copyWith(
        origin: TemplateOrigin.manual,
        clearTemplateInstanceId: true,
      );

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
