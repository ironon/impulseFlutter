import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/services/automation_service.dart';
import 'package:impulse_app/services/integrity_store.dart';
import 'package:impulse_app/state/app_state.dart';

Automation evt(String id,
        {EnforcementProfile profile = EnforcementProfile.strictBoth}) =>
    Automation(
      id: id,
      referenceDate: DateTime.utc(2026, 1, 1),
      startTime: const TimeOfDay(hour: 0, minute: 1),
      endTime: const TimeOfDay(hour: 23, minute: 58),
      recurrenceType: RecurrenceType.daily,
      criteria: Criteria.stayNear,
      profile: profile,
      anchorId: 'anchor-a',
      color: const Color(0xFF000000),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppState app;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // AutomationService is a singleton — clear leftovers from earlier tests.
    final autoSvc = AutomationService();
    for (final a in List.of(autoSvc.automations)) {
      await autoSvc.deleteAutomation(a.id);
    }
    db = AppDatabase.forTesting(NativeDatabase.memory());
    app = AppState(integrityStore: IntegrityStore(db));
    await app.initialize();
  });

  tearDown(() async {
    app.dispose();
    await db.close();
  });

  test('create then immediate re-edit is free (no baseline yet)', () async {
    final a = evt('e1');
    await app.saveCommitment(updated: a);
    expect(app.schedule.length, 1);

    // Loosening during the fresh setup window applies immediately.
    final res = await app.saveCommitment(
      previous: a,
      updated: evt('e1', profile: EnforcementProfile.looseBuzz),
    );
    expect(res.queued, isFalse);
    expect(app.schedule.single.profile, EnforcementProfile.looseBuzz);
    expect(app.pendingEventIds, isEmpty);
  });

  test('loosening a settled active commitment stays on the old rule', () async {
    final a = evt('e2');
    await app.saveCommitment(updated: a);
    // Force-settle with a strict baseline (all-day active window).
    await app.settleStore.recordEdit(
        'e2', DateTime.now().subtract(const Duration(hours: 5)));
    await app.settleStore.settle('e2', a, DateTime.now());

    final res = await app.saveCommitment(
      previous: a,
      updated: evt('e2', profile: EnforcementProfile.looseBuzz),
    );
    expect(res.queued, isTrue);
    // The pre-edit rule keeps enforcing.
    expect(app.schedule.single.profile, EnforcementProfile.strictBoth);
    // The queue row exists; the reactive badge set follows the drift stream.
    final rows = await app.integrity.pendingChanges();
    expect(rows.map((r) => r.eventUuid), contains('e2'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(app.pendingEventIds, contains('e2'));
  });

  test('scheduleForPush appends a one-day negate for a spent pass', () async {
    final a = evt('e3');
    await app.saveCommitment(updated: a);
    final res = await app.spendPass(a, DateTime.now());
    expect(res.success, isTrue);

    final push = await app.scheduleForPush();
    expect(push.length, 2);
    final negate = push.where((x) => x.negate).single;
    expect(negate.id, 'e3'); // same UUID cancels that day (§5.3.4)
    expect(negate.recurrenceType, RecurrenceType.once);
  });

  test('drafts persist and remove', () async {
    await app.addDraft(TemplateDraft(
      id: 'd1',
      templateId: 'gym_time',
      params: const {'startTime': {'hour': 17, 'minute': 30}},
      createdAt: DateTime.now(),
      note: 'Grab the WiFi name at the gym',
    ));
    expect(app.drafts.length, 1);
    await app.removeDraft('d1');
    expect(app.drafts, isEmpty);
  });
}
