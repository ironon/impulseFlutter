import 'package:drift/drift.dart';

import '../data/app_database.dart';

/// Mirrors the firmware `change_type` byte of a pending-queue entry
/// (firmware §9.5): 0 = delete, 1 = loosen-modify, 2 = negate-day,
/// 3 = setting change. **Order matches the wire — do not reorder.**
enum PendingChangeType { eventDelete, eventModify, negateDay, setting }

/// Transactional wrapper over the drift trust stores (§2, §9, §13): the
/// pending-changes queue, the emergency-pass ledger and the audit trail.
///
/// All three are timestamped and migration-safe. The watch remains the root of
/// trust; this is the interim-enforcement + permanent-preview/audit mirror.
class IntegrityStore {
  IntegrityStore(this._db);

  final AppDatabase _db;

  // ── Pending changes queue (§8.9) ──────────────────────────────────────────

  /// Queue a quarantined loosening. Returns the row id. Also writes an audit
  /// entry, in a single transaction (the queue and its audit never diverge).
  Future<int> queueLoosening({
    required String eventUuid,
    required PendingChangeType changeType,
    required String proposedStateJson,
    required String description,
    required DateTime now,
    required Duration delay,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.pendingChanges).insert(
            PendingChangesCompanion.insert(
              eventUuid: eventUuid,
              changeType: changeType.index,
              proposedStateJson: Value(proposedStateJson),
              description: Value(description),
              createdAt: now,
              applyAfter: now.add(delay),
            ),
          );
      await _audit(
        category: 'loosening_queued',
        eventUuid: eventUuid,
        detail: description,
        now: now,
      );
      return id;
    });
  }

  Future<List<PendingChangeRow>> pendingChanges() {
    return (_db.select(_db.pendingChanges)
          ..where((t) => t.promoted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.applyAfter)]))
        .get();
  }

  Stream<List<PendingChangeRow>> watchPendingChanges() {
    return (_db.select(_db.pendingChanges)
          ..where((t) => t.promoted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.applyAfter)]))
        .watch();
  }

  /// Entries whose delay has elapsed and can be pushed at the next opportunity.
  Future<List<PendingChangeRow>> duePromotions(DateTime now) {
    return (_db.select(_db.pendingChanges)
          ..where((t) =>
              t.promoted.equals(false) &
              t.applyAfter.isSmallerOrEqualValue(now)))
        .get();
  }

  Future<void> markPromoted(int id, DateTime now) {
    return _db.transaction(() async {
      final row = await (_db.select(_db.pendingChanges)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      await (_db.update(_db.pendingChanges)..where((t) => t.id.equals(id)))
          .write(const PendingChangesCompanion(promoted: Value(true)));
      await _audit(
        category: 'loosening_promoted',
        eventUuid: row?.eventUuid,
        detail: row?.description ?? '',
        now: now,
      );
    });
  }

  /// A newer accepted edit to an event cancels its pending loosenings (§9.3):
  /// the newer intent wins; re-requesting the loosening restarts its delay.
  Future<int> cancelPendingForEvent(String eventUuid, DateTime now,
      {String reason = 'superseded by a newer edit'}) {
    return _db.transaction(() async {
      final rows = await (_db.select(_db.pendingChanges)
            ..where((t) => t.eventUuid.equals(eventUuid) & t.promoted.equals(false)))
          .get();
      if (rows.isEmpty) return 0;
      final n = await (_db.delete(_db.pendingChanges)
            ..where((t) => t.eventUuid.equals(eventUuid) & t.promoted.equals(false)))
          .go();
      await _audit(
        category: 'loosening_cancelled',
        eventUuid: eventUuid,
        detail: reason,
        now: now,
      );
      return n;
    });
  }

  /// Drop pending entries whose effect has already expired (e.g. a negate-day
  /// whose date has passed) — dropped, not applied (firmware §9.4).
  Future<void> deletePending(int id) {
    return (_db.delete(_db.pendingChanges)..where((t) => t.id.equals(id))).go();
  }

  // ── Emergency-pass ledger (§8.10) ─────────────────────────────────────────

  /// Spends within the rolling window ending at [now].
  Future<int> passesSpentInWindow(DateTime now,
      {Duration window = const Duration(days: 7)}) async {
    final cutoff = now.subtract(window);
    final rows = await (_db.select(_db.emergencyPassSpends)
          ..where((t) => t.spentAt.isBiggerOrEqualValue(cutoff)))
        .get();
    return rows.length;
  }

  /// Record a spent pass. Caller checks allowance first. Writes ledger + audit
  /// atomically. Returns the spend row id.
  Future<int> recordPassSpend({
    required String eventUuid,
    required int forDateYyyymmdd,
    required DateTime now,
    bool pushed = false,
  }) {
    return _db.transaction(() async {
      final id = await _db.into(_db.emergencyPassSpends).insert(
            EmergencyPassSpendsCompanion.insert(
              eventUuid: eventUuid,
              forDate: forDateYyyymmdd,
              spentAt: now,
              pushed: Value(pushed),
            ),
          );
      await _audit(
        category: 'pass_spent',
        eventUuid: eventUuid,
        detail: 'Emergency pass spent for $forDateYyyymmdd',
        now: now,
      );
      return id;
    });
  }

  Future<void> markPassPushed(int id) {
    return (_db.update(_db.emergencyPassSpends)..where((t) => t.id.equals(id)))
        .write(const EmergencyPassSpendsCompanion(pushed: Value(true)));
  }

  /// Spends whose one-day negate has NOT yet been confirmed by the watch
  /// (`pushed == false`) — the pending-spend retry queue (§8.10). Held when the
  /// watch was unreachable at spend time; completed on reconnect.
  Future<List<EmergencyPassSpendRow>> pendingPassSpends() {
    return (_db.select(_db.emergencyPassSpends)
          ..where((t) => t.pushed.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.spentAt)]))
        .get();
  }

  /// An existing *pending* spend for this exact commitment+day, or null. Used to
  /// avoid double-charging when the user retries a spend the watch hasn't yet
  /// confirmed (§8.10).
  Future<EmergencyPassSpendRow?> pendingSpendFor(
      String eventUuid, int forDateYyyymmdd) {
    return (_db.select(_db.emergencyPassSpends)
          ..where((t) =>
              t.eventUuid.equals(eventUuid) &
              t.forDate.equals(forDateYyyymmdd) &
              t.pushed.equals(false))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Drop a spend row entirely — used when the watch reports its own ledger is
  /// exhausted (`…001B` `0x02`), so a locally-held pending spend is voided
  /// rather than left to retry forever (§8.10).
  Future<void> deletePassSpend(int id) {
    return (_db.delete(_db.emergencyPassSpends)..where((t) => t.id.equals(id)))
        .go();
  }

  Future<List<EmergencyPassSpendRow>> passHistory() {
    return (_db.select(_db.emergencyPassSpends)
          ..orderBy([
            (t) => OrderingTerm(expression: t.spentAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// The moment the oldest in-window spend ages out, freeing a pass — for the
  /// "next pass regenerates [when]" copy. Null when nothing is in-window.
  Future<DateTime?> nextPassRegeneratesAt(DateTime now,
      {Duration window = const Duration(days: 7)}) async {
    final cutoff = now.subtract(window);
    final oldest = await (_db.select(_db.emergencyPassSpends)
          ..where((t) => t.spentAt.isBiggerOrEqualValue(cutoff))
          ..orderBy([(t) => OrderingTerm(expression: t.spentAt)])
          ..limit(1))
        .getSingleOrNull();
    if (oldest == null) return null;
    return oldest.spentAt.add(window);
  }

  // ── Audit trail (§8.10 / §13) ─────────────────────────────────────────────

  Future<void> _audit({
    required String category,
    String? eventUuid,
    required String detail,
    required DateTime now,
  }) async {
    await _db.into(_db.auditTrail).insert(
          AuditTrailCompanion.insert(
            timestamp: now,
            category: category,
            eventUuid: Value(eventUuid),
            detail: Value(detail),
          ),
        );
  }

  /// Public audit hook for callers (e.g. allowance changes, tightening applies).
  Future<void> audit({
    required String category,
    String? eventUuid,
    required String detail,
    DateTime? now,
  }) =>
      _audit(
        category: category,
        eventUuid: eventUuid,
        detail: detail,
        now: now ?? DateTime.now(),
      );

  Future<List<AuditEntryRow>> auditEntries({int limit = 200}) {
    return (_db.select(_db.auditTrail)
          ..orderBy([
            (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .get();
  }
}
