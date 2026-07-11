import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/services/commitment_policy_service.dart';
import 'package:impulse_app/services/integrity_store.dart';
import 'package:impulse_app/services/self_binding_policy.dart';
import 'package:impulse_app/services/settle_state_store.dart';

Automation evt({
  int startH = 11,
  int endH = 13,
  EnforcementProfile profile = EnforcementProfile.strictBoth,
}) =>
    Automation(
      id: 'evt-1',
      referenceDate: DateTime.utc(2026, 1, 1),
      startTime: TimeOfDay(hour: startH, minute: 0),
      endTime: TimeOfDay(hour: endH, minute: 0),
      recurrenceType: RecurrenceType.daily,
      criteria: Criteria.stayNear,
      profile: profile,
      anchorId: 'a',
      color: const Color(0xFF000000),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CommitmentPolicyService svc;
  final now = DateTime(2026, 7, 11, 12, 0); // noon, inside 11-13 window

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final settle = SettleStateStore();
    await settle.load();
    // Make the event settled with a strict baseline.
    await settle.recordEdit('evt-1', now.subtract(const Duration(hours: 5)));
    await settle.settle('evt-1', evt(), now.subtract(const Duration(hours: 3)));
    svc = CommitmentPolicyService(
      integrity: IntegrityStore(db),
      settleStore: settle,
      config: const SelfBindingConfig(),
      clock: () => now,
    );
  });

  tearDown(() async => db.close());

  test('loosening an active settled commitment queues it', () async {
    final outcome = await svc.applyEdit(
        evt(), evt(profile: EnforcementProfile.looseBoth));
    expect(outcome.queued, isTrue);
    expect(outcome.applyAfter, now.add(const Duration(hours: 24)));
    final pending = await svc.integrity.pendingChanges();
    expect(pending.length, 1);
  });

  test('tightening an active commitment applies immediately', () async {
    final outcome = await svc.applyEdit(
        evt(profile: EnforcementProfile.normalBuzz),
        evt(profile: EnforcementProfile.strictBoth));
    expect(outcome.queued, isFalse);
    expect((await svc.integrity.pendingChanges()).isEmpty, isTrue);
  });

  test('spending a pass decrements remaining', () async {
    expect(await svc.remainingPasses(), 2);
    final r = await svc.spendPass(evt(), now);
    expect(r.success, isTrue);
    expect(r.remaining, 1);
    expect(await svc.remainingPasses(), 1);
  });

  test('raising allowance is quarantined; lowering is immediate', () async {
    final raised = await svc.changeAllowance(5);
    expect(raised, 2); // unchanged immediately
    expect((await svc.integrity.pendingChanges()).length, 1);

    final lowered = await svc.changeAllowance(1);
    expect(lowered, 1); // immediate
  });
}
