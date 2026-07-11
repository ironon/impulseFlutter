import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/services/integrity_store.dart';

void main() {
  late AppDatabase db;
  late IntegrityStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = IntegrityStore(db);
  });

  tearDown(() async => db.close());

  test('queueing a loosening writes queue + audit atomically', () async {
    final now = DateTime(2026, 7, 11, 12, 0);
    await store.queueLoosening(
      eventUuid: 'evt-1',
      changeType: PendingChangeType.eventModify,
      proposedStateJson: '{}',
      description: 'shorter window',
      now: now,
      delay: const Duration(hours: 24),
    );
    final pending = await store.pendingChanges();
    expect(pending.length, 1);
    expect(pending.first.applyAfter, now.add(const Duration(hours: 24)));

    final audit = await store.auditEntries();
    expect(audit.any((a) => a.category == 'loosening_queued'), isTrue);
  });

  test('duePromotions only returns entries past applyAfter', () async {
    final now = DateTime(2026, 7, 11, 12, 0);
    await store.queueLoosening(
      eventUuid: 'evt-1',
      changeType: PendingChangeType.eventModify,
      proposedStateJson: '{}',
      description: 'x',
      now: now,
      delay: const Duration(hours: 24),
    );
    expect((await store.duePromotions(now)).isEmpty, isTrue);
    final later = now.add(const Duration(hours: 25));
    expect((await store.duePromotions(later)).length, 1);
  });

  test('a newer edit cancels pending entries for the same event', () async {
    final now = DateTime(2026, 7, 11, 12, 0);
    await store.queueLoosening(
      eventUuid: 'evt-1',
      changeType: PendingChangeType.eventModify,
      proposedStateJson: '{}',
      description: 'x',
      now: now,
      delay: const Duration(hours: 24),
    );
    final cancelled = await store.cancelPendingForEvent('evt-1', now);
    expect(cancelled, 1);
    expect((await store.pendingChanges()).isEmpty, isTrue);
  });

  test('rolling pass window counts only spends within 7 days', () async {
    final now = DateTime(2026, 7, 11, 12, 0);
    await store.recordPassSpend(
        eventUuid: 'evt-1', forDateYyyymmdd: 20260711, now: now);
    await store.recordPassSpend(
        eventUuid: 'evt-2',
        forDateYyyymmdd: 20260703,
        now: now.subtract(const Duration(days: 8)));
    expect(await store.passesSpentInWindow(now), 1);
  });

  test('next pass regenerates 7 days after oldest in-window spend', () async {
    final now = DateTime(2026, 7, 11, 12, 0);
    await store.recordPassSpend(
        eventUuid: 'evt-1', forDateYyyymmdd: 20260711, now: now);
    final regen = await store.nextPassRegeneratesAt(now);
    expect(regen, now.add(const Duration(days: 7)));
  });
}
