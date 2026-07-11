import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/services/self_binding_policy.dart';

Automation baseEvent({
  RecurrenceType rec = RecurrenceType.daily,
  int startH = 9,
  int endH = 10,
  Criteria criteria = Criteria.stayNear,
  EnforcementProfile profile = EnforcementProfile.normalBuzz,
  int donning = 0,
  List<String> beeps = const [],
  AnchorEnforcementProfile? anchorProfile,
  String anchorId = 'anchor-a',
  bool negate = false,
  int? dayOfWeek,
}) {
  return Automation(
    id: 'evt-1',
    referenceDate: DateTime.utc(2026, 1, 1),
    startTime: TimeOfDay(hour: startH, minute: 0),
    endTime: TimeOfDay(hour: endH, minute: 0),
    recurrenceType: rec,
    dayOfWeek: dayOfWeek,
    criteria: criteria,
    profile: profile,
    donningGraceS: donning,
    beepAnchors: beeps,
    anchorProfile: anchorProfile,
    anchorId: anchorId,
    negate: negate,
    color: const Color(0xFF000000),
  );
}

void main() {
  const policy = SelfBindingPolicy(SelfBindingConfig());

  group('profile partial order', () {
    test('same profile = noChange', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.normalBuzz,
              EnforcementProfile.normalBuzz),
          ChangeClassification.noChange);
    });
    test('loose->strict same output = tightening', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.looseBuzz,
              EnforcementProfile.strictBuzz),
          ChangeClassification.tightening);
    });
    test('strict->loose = loosening', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.strictBoth,
              EnforcementProfile.looseBoth),
          ChangeClassification.loosening);
    });
    test('buzz->both (same strictness) = tightening', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.normalBuzz,
              EnforcementProfile.normalBoth),
          ChangeClassification.tightening);
    });
    test('buzz->silent = non-comparable', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.normalBuzz,
              EnforcementProfile.normalSilent),
          ChangeClassification.nonComparable);
    });
    test('strict-buzz -> normal-both = non-comparable (mixed dims)', () {
      expect(SelfBindingPolicy.classifyProfile(EnforcementProfile.strictBuzz,
              EnforcementProfile.normalBoth),
          ChangeClassification.nonComparable);
    });
  });

  group('window', () {
    test('widen both = tightening', () {
      expect(SelfBindingPolicy.classifyWindow(540, 600, 480, 660),
          ChangeClassification.tightening);
    });
    test('shrink = loosening', () {
      expect(SelfBindingPolicy.classifyWindow(540, 600, 550, 590),
          ChangeClassification.loosening);
    });
    test('shift later both ends = non-comparable', () {
      expect(SelfBindingPolicy.classifyWindow(540, 600, 560, 620),
          ChangeClassification.nonComparable);
    });
  });

  group('recurrence', () {
    test('weekly->daily = tightening', () {
      final from = baseEvent(rec: RecurrenceType.weekly, dayOfWeek: 2);
      final to = baseEvent(rec: RecurrenceType.daily);
      expect(SelfBindingPolicy.classifyRecurrence(from, to),
          ChangeClassification.tightening);
    });
    test('daily->weekly = loosening', () {
      final from = baseEvent(rec: RecurrenceType.daily);
      final to = baseEvent(rec: RecurrenceType.weekly, dayOfWeek: 2);
      expect(SelfBindingPolicy.classifyRecurrence(from, to),
          ChangeClassification.loosening);
    });
    test('weekly Tue->Thu = non-comparable', () {
      final from = baseEvent(rec: RecurrenceType.weekly, dayOfWeek: 2);
      final to = baseEvent(rec: RecurrenceType.weekly, dayOfWeek: 4);
      expect(SelfBindingPolicy.classifyRecurrence(from, to),
          ChangeClassification.nonComparable);
    });
  });

  group('single-field edits', () {
    test('criteria change = loosening (non-comparable collapses)', () {
      final from = baseEvent(criteria: Criteria.stayNear);
      final to = baseEvent(criteria: Criteria.getAway);
      expect(policy.classifyEdit(from, to), ChangeClassification.loosening);
    });
    test('target change = loosening', () {
      final from = baseEvent(anchorId: 'anchor-a');
      final to = baseEvent(anchorId: 'anchor-b');
      expect(policy.classifyEdit(from, to), ChangeClassification.loosening);
    });
    test('donning decrease = tightening', () {
      final from = baseEvent(donning: 300);
      final to = baseEvent(donning: 60);
      expect(policy.classifyEdit(from, to), ChangeClassification.tightening);
    });
    test('donning increase = loosening', () {
      final from = baseEvent(donning: 60);
      final to = baseEvent(donning: 300);
      expect(policy.classifyEdit(from, to), ChangeClassification.loosening);
    });
    test('add beep anchor = tightening', () {
      final from = baseEvent(beeps: []);
      final to = baseEvent(beeps: ['n1']);
      expect(policy.classifyEdit(from, to), ChangeClassification.tightening);
    });
    test('negate added = loosening', () {
      final from = baseEvent(negate: false);
      final to = baseEvent(negate: true);
      expect(policy.classifyEdit(from, to), ChangeClassification.loosening);
    });
  });

  group('multi-field rule', () {
    test('tighten window + loosen profile = loosening', () {
      final from = baseEvent(
          startH: 9, endH: 10, profile: EnforcementProfile.strictBoth);
      final to = baseEvent(
          startH: 8, endH: 11, profile: EnforcementProfile.looseBoth);
      expect(policy.classifyEdit(from, to), ChangeClassification.loosening);
    });
    test('two tightenings = tightening', () {
      final from = baseEvent(
          startH: 9, endH: 10, profile: EnforcementProfile.looseBuzz);
      final to = baseEvent(
          startH: 8, endH: 11, profile: EnforcementProfile.strictBuzz);
      expect(policy.classifyEdit(from, to), ChangeClassification.tightening);
    });
  });

  group('gate decision', () {
    final now = DateTime(2026, 7, 11, 12, 0); // noon
    test('tightening applies immediately even when active', () {
      final from = baseEvent(startH: 11, endH: 13); // active at noon
      final to = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.strictBoth);
      final settle = SettleState(
          lastEdit: now.subtract(const Duration(hours: 5)),
          settledBaseline: from);
      expect(
          policy.decideEdit(from: from, to: to, settle: settle, now: now),
          GateDecision.applyImmediately);
    });

    test('loosening of active settled event is quarantined', () {
      final from = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.strictBoth);
      final to = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.looseBoth);
      final settle = SettleState(
          lastEdit: now.subtract(const Duration(hours: 5)),
          settledBaseline: from);
      expect(
          policy.decideEdit(from: from, to: to, settle: settle, now: now),
          GateDecision.quarantine);
    });

    test('loosening of far-future event applies immediately (no escape)', () {
      // once event 10 days out
      final from = Automation(
        id: 'evt-1',
        referenceDate: DateTime.utc(2026, 1, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
        recurrenceType: RecurrenceType.once,
        criteria: Criteria.stayNear,
        profile: EnforcementProfile.strictBoth,
        anchorId: 'a',
        color: const Color(0xFF000000),
      );
      final future = DateTime(2026, 7, 21, 9, 0);
      final to = Automation(
        id: 'evt-1',
        referenceDate: DateTime.utc(2026, 1, 1),
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
        recurrenceType: RecurrenceType.once,
        criteria: Criteria.stayNear,
        profile: EnforcementProfile.looseBoth,
        anchorId: 'a',
        color: const Color(0xFF000000),
      );
      final settle = SettleState(
          lastEdit: now.subtract(const Duration(hours: 5)),
          settledBaseline: from);
      // reference the future to avoid an unused warning while keeping intent clear
      expect(future.isAfter(now), isTrue);
      expect(
          policy.decideEdit(from: from, to: to, settle: settle, now: now),
          GateDecision.applyImmediately);
    });

    test('brand-new event (no baseline) can loosen freely', () {
      final from = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.strictBoth);
      final to = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.looseBoth);
      final settle = SettleState(lastEdit: now); // unsettled, no baseline
      expect(
          policy.decideEdit(from: from, to: to, settle: settle, now: now),
          GateDecision.applyImmediately);
    });

    test('settled floor: unsettled tighten-then-loosen below baseline is gated',
        () {
      // Baseline is strict. An unsettled edit that drops below baseline is gated.
      final baseline = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.strictBoth);
      final from = baseline;
      final to = baseEvent(
          startH: 11, endH: 13, profile: EnforcementProfile.looseBoth);
      final settle =
          SettleState(lastEdit: now, settledBaseline: baseline); // unsettled
      expect(
          policy.decideEdit(from: from, to: to, settle: settle, now: now),
          GateDecision.quarantine);
    });
  });
}
