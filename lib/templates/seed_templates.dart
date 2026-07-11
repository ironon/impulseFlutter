import 'package:flutter/material.dart';

import '../models/automation_model.dart';
import 'template.dart';

AnchorEnforcementProfile _anchorFromFirmness(EnforcementProfile p) {
  switch (p) {
    case EnforcementProfile.strictSilent:
    case EnforcementProfile.strictBuzz:
    case EnforcementProfile.strictBoth:
      return AnchorEnforcementProfile.hard;
    case EnforcementProfile.normalSilent:
    case EnforcementProfile.normalBuzz:
    case EnforcementProfile.normalBoth:
      return AnchorEnforcementProfile.medium;
    case EnforcementProfile.looseSilent:
    case EnforcementProfile.looseBuzz:
    case EnforcementProfile.looseBoth:
      return AnchorEnforcementProfile.light;
  }
}

int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
TimeOfDay _addMinutes(TimeOfDay t, int m) {
  final total = (_minutes(t) + m).clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// Sunrise Lock (§8.8): getAway from the bedroom anchor over the wake window,
/// beeping the nightstand anchor, with a post-donning grace (donningGraceS).
class SunriseLockTemplate extends Template with TemplateHelpers {
  @override
  String get id => 'sunrise_lock';
  @override
  TemplateOrigin get origin => TemplateOrigin.sunriseLock;
  @override
  String get displayName => 'Sunrise Lock';
  @override
  String get description =>
      'The alarm you can\'t snooze — the whole room gets you up.';
  @override
  IconData get icon => Icons.wb_sunny_outlined;

  @override
  List<TemplateParam> get params => const [
        TemplateParam(
            key: 'wakeTime',
            label: 'Wake time',
            kind: ParamKind.time,
            defaultValue: {'hour': 6, 'minute': 30},
            inQuickForm: true),
        TemplateParam(
            key: 'graceSeconds',
            label: 'Grace after you put the watch on',
            kind: ParamKind.durationSeconds,
            defaultValue: 300,
            inQuickForm: true),
        TemplateParam(
            key: 'firmness',
            label: 'How hard should it push?',
            kind: ParamKind.firmness,
            defaultValue: 'strictBoth'),
        TemplateParam(
            key: 'bedroomAnchor',
            label: 'Bedroom anchor',
            kind: ParamKind.anchorRole,
            anchorRole: 'bedroom',
            inQuickForm: true),
        TemplateParam(
            key: 'nightstandAnchor',
            label: 'Nightstand anchor',
            kind: ParamKind.anchorRole,
            anchorRole: 'nightstand'),
      ];

  @override
  OnboarderInfo get onboarder => const OnboarderInfo(
        problemStatement: 'I can\'t get out of bed.',
        heroIcon: Icons.bed_outlined,
        requiredAnchors: [
          AnchorRoleRequirement(
              role: 'bedroom',
              label: 'Bedroom anchor',
              placementCopy:
                  'Place this where you sleep — it\'s what you have to leave.'),
          AnchorRoleRequirement(
              role: 'nightstand',
              label: 'Nightstand anchor',
              placementCopy:
                  'This one goes on your nightstand — it\'s what gets you up.'),
        ],
      );

  @override
  List<Automation> expand(
    Map<String, dynamic> params, {
    required String instanceId,
    required String Function() newUuid,
    Map<String, String> slotUuids = const {},
  }) {
    final wake = timeFrom(params['wakeTime'], const TimeOfDay(hour: 6, minute: 30));
    final grace = (params['graceSeconds'] as int?) ?? 300;
    final firmness = firmnessFrom(params['firmness'], EnforcementProfile.strictBoth);
    final bedroom = params['bedroomAnchor'] as String?;
    final nightstand = params['nightstandAnchor'] as String?;

    return [
      Automation(
        id: slotUuids['primary'] ?? newUuid(),
        referenceDate: DateTime.now().toUtc(),
        startTime: wake,
        endTime: _addMinutes(wake, 60),
        recurrenceType: RecurrenceType.daily,
        criteria: Criteria.getAway,
        profile: firmness,
        donningGraceS: grace.clamp(0, 1800),
        anchorId: bedroom,
        beepAnchors: nightstand == null ? const [] : [nightstand],
        anchorProfile:
            nightstand == null ? null : _anchorFromFirmness(firmness),
        origin: origin,
        templateInstanceId: instanceId,
        templateParams: params,
        color: const Color(0xFFFFB74D),
      ),
    ];
  }

  @override
  Map<String, dynamic> reparse(List<Automation> blocks) {
    if (blocks.isEmpty) return defaultParams;
    final b = blocks.first;
    return {
      ...b.templateParams,
      'wakeTime': timeToMap(b.startTime),
      'graceSeconds': b.donningGraceS,
      'firmness': b.profile.name,
      'bedroomAnchor': b.anchorId,
      'nightstandAnchor': b.beepAnchors.isEmpty ? null : b.beepAnchors.first,
    };
  }
}

/// Study Time (§2A.2): stayNear(desk anchor) over a window.
class StudyTimeTemplate extends Template with TemplateHelpers {
  @override
  String get id => 'study_time';
  @override
  TemplateOrigin get origin => TemplateOrigin.studyTime;
  @override
  String get displayName => 'Study Time';
  @override
  String get description => 'Stay at your desk while the work gets done.';
  @override
  IconData get icon => Icons.menu_book_outlined;

  @override
  List<TemplateParam> get params => const [
        TemplateParam(
            key: 'startTime',
            label: 'Start',
            kind: ParamKind.time,
            defaultValue: {'hour': 9, 'minute': 0},
            inQuickForm: true),
        TemplateParam(
            key: 'endTime',
            label: 'End',
            kind: ParamKind.time,
            defaultValue: {'hour': 11, 'minute': 0},
            inQuickForm: true),
        TemplateParam(
            key: 'deskAnchor',
            label: 'Desk anchor',
            kind: ParamKind.anchorRole,
            anchorRole: 'desk',
            inQuickForm: true),
        TemplateParam(
            key: 'firmness',
            label: 'Firmness',
            kind: ParamKind.firmness,
            defaultValue: 'normalBuzz'),
      ];

  @override
  OnboarderInfo get onboarder => const OnboarderInfo(
        problemStatement: 'I can\'t make myself sit down and focus.',
        heroIcon: Icons.school_outlined,
        requiredAnchors: [
          AnchorRoleRequirement(
              role: 'desk',
              label: 'Desk anchor',
              placementCopy: 'Put this where you work — it keeps you there.'),
        ],
      );

  @override
  List<Automation> expand(
    Map<String, dynamic> params, {
    required String instanceId,
    required String Function() newUuid,
    Map<String, String> slotUuids = const {},
  }) {
    final start = timeFrom(params['startTime'], const TimeOfDay(hour: 9, minute: 0));
    final end = timeFrom(params['endTime'], const TimeOfDay(hour: 11, minute: 0));
    final firmness = firmnessFrom(params['firmness'], EnforcementProfile.normalBuzz);
    return [
      Automation(
        id: slotUuids['primary'] ?? newUuid(),
        referenceDate: DateTime.now().toUtc(),
        startTime: start,
        endTime: end,
        recurrenceType: RecurrenceType.daily,
        criteria: Criteria.stayNear,
        profile: firmness,
        anchorId: params['deskAnchor'] as String?,
        origin: origin,
        templateInstanceId: instanceId,
        templateParams: params,
        color: const Color(0xFF64B5F6),
      ),
    ];
  }

  @override
  Map<String, dynamic> reparse(List<Automation> blocks) {
    if (blocks.isEmpty) return defaultParams;
    final b = blocks.first;
    return {
      ...b.templateParams,
      'startTime': timeToMap(b.startTime),
      'endTime': timeToMap(b.endTime),
      'deskAnchor': b.anchorId,
      'firmness': b.profile.name,
    };
  }
}

/// Gym Time (§2A.2): getOnWifi(gym SSID) over a window.
class GymTimeTemplate extends Template with TemplateHelpers {
  @override
  String get id => 'gym_time';
  @override
  TemplateOrigin get origin => TemplateOrigin.gymTime;
  @override
  String get displayName => 'Gym Time';
  @override
  String get description => 'Your gym\'s WiFi confirms you actually made it.';
  @override
  IconData get icon => Icons.fitness_center_outlined;

  @override
  List<TemplateParam> get params => const [
        TemplateParam(
            key: 'startTime',
            label: 'Start',
            kind: ParamKind.time,
            defaultValue: {'hour': 17, 'minute': 30},
            inQuickForm: true),
        TemplateParam(
            key: 'endTime',
            label: 'End',
            kind: ParamKind.time,
            defaultValue: {'hour': 18, 'minute': 30},
            inQuickForm: true),
        TemplateParam(
            key: 'gymSsid',
            label: 'Gym WiFi name',
            kind: ParamKind.wifiSsid,
            inQuickForm: true),
        TemplateParam(
            key: 'firmness',
            label: 'Firmness',
            kind: ParamKind.firmness,
            defaultValue: 'normalBuzz'),
      ];

  @override
  OnboarderInfo get onboarder => const OnboarderInfo(
        problemStatement: 'I keep skipping the gym.',
        heroIcon: Icons.directions_run_outlined,
        requiredAnchors: [],
      );

  @override
  List<Automation> expand(
    Map<String, dynamic> params, {
    required String instanceId,
    required String Function() newUuid,
    Map<String, String> slotUuids = const {},
  }) {
    final start = timeFrom(params['startTime'], const TimeOfDay(hour: 17, minute: 30));
    final end = timeFrom(params['endTime'], const TimeOfDay(hour: 18, minute: 30));
    final firmness = firmnessFrom(params['firmness'], EnforcementProfile.normalBuzz);
    return [
      Automation(
        id: slotUuids['primary'] ?? newUuid(),
        referenceDate: DateTime.now().toUtc(),
        startTime: start,
        endTime: end,
        recurrenceType: RecurrenceType.daily,
        criteria: Criteria.getOnWifi,
        profile: firmness,
        wifiSSID: params['gymSsid'] as String?,
        origin: origin,
        templateInstanceId: instanceId,
        templateParams: params,
        color: const Color(0xFF81C784),
      ),
    ];
  }

  @override
  Map<String, dynamic> reparse(List<Automation> blocks) {
    if (blocks.isEmpty) return defaultParams;
    final b = blocks.first;
    return {
      ...b.templateParams,
      'startTime': timeToMap(b.startTime),
      'endTime': timeToMap(b.endTime),
      'gymSsid': b.wifiSSID,
      'firmness': b.profile.name,
    };
  }
}

/// Phone-Free (§2A.2): phoneAway(docking anchor) — the Mode B docking flow.
class PhoneFreeTemplate extends Template with TemplateHelpers {
  @override
  String get id => 'phone_free';
  @override
  TemplateOrigin get origin => TemplateOrigin.phoneFree;
  @override
  String get displayName => 'Phone-Free Block';
  @override
  String get description => 'Dock the phone and get the time back.';
  @override
  IconData get icon => Icons.phonelink_erase_outlined;

  @override
  List<TemplateParam> get params => const [
        TemplateParam(
            key: 'startTime',
            label: 'Start',
            kind: ParamKind.time,
            defaultValue: {'hour': 21, 'minute': 0},
            inQuickForm: true),
        TemplateParam(
            key: 'endTime',
            label: 'End',
            kind: ParamKind.time,
            defaultValue: {'hour': 22, 'minute': 0},
            inQuickForm: true),
        TemplateParam(
            key: 'dockAnchor',
            label: 'Docking anchor',
            kind: ParamKind.anchorRole,
            anchorRole: 'phone dock',
            inQuickForm: true),
        TemplateParam(
            key: 'firmness',
            label: 'Firmness',
            kind: ParamKind.firmness,
            defaultValue: 'normalBuzz'),
      ];

  @override
  OnboarderInfo get onboarder => const OnboarderInfo(
        problemStatement: 'My evenings disappear into my phone.',
        heroIcon: Icons.nightlight_outlined,
        requiredAnchors: [
          AnchorRoleRequirement(
              role: 'phone dock',
              label: 'Docking anchor',
              placementCopy:
                  'Put this where the phone should live during the block.'),
        ],
      );

  @override
  List<Automation> expand(
    Map<String, dynamic> params, {
    required String instanceId,
    required String Function() newUuid,
    Map<String, String> slotUuids = const {},
  }) {
    final start = timeFrom(params['startTime'], const TimeOfDay(hour: 21, minute: 0));
    final end = timeFrom(params['endTime'], const TimeOfDay(hour: 22, minute: 0));
    final firmness = firmnessFrom(params['firmness'], EnforcementProfile.normalBuzz);
    return [
      Automation(
        id: slotUuids['primary'] ?? newUuid(),
        referenceDate: DateTime.now().toUtc(),
        startTime: start,
        endTime: end,
        recurrenceType: RecurrenceType.daily,
        criteria: Criteria.phoneAway,
        profile: firmness,
        anchorId: params['dockAnchor'] as String?, // docking anchor (required)
        origin: origin,
        templateInstanceId: instanceId,
        templateParams: params,
        color: const Color(0xFFBA68C8),
      ),
    ];
  }

  @override
  Map<String, dynamic> reparse(List<Automation> blocks) {
    if (blocks.isEmpty) return defaultParams;
    final b = blocks.first;
    return {
      ...b.templateParams,
      'startTime': timeToMap(b.startTime),
      'endTime': timeToMap(b.endTime),
      'dockAnchor': b.anchorId,
      'firmness': b.profile.name,
    };
  }
}
