import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The app's trust machinery (MOBILE_APP_SPEC §2, §9, §13): the pending-changes
// queue, the emergency-pass ledger, and the audit trail. These are the only
// stores that MUST be transactional, timestamped and migration-safe, so they
// live in drift rather than shared_preferences.
//
// The watch is the root of trust (firmware §9). Where the watch exposes the
// authoritative Pending Changes (`…001A`) / Emergency Pass (`…001B`)
// characteristics these tables act as the interim enforcement layer and the
// permanent preview/audit mirror; where it does not, they are the only
// enforcement of §8.9/§8.10 until that firmware phase ships.
// ─────────────────────────────────────────────────────────────────────────────

/// App-side mirror of the watch's pending-loosening queue (§8.9, firmware §9.5).
/// A quarantined loosening waits [LOOSEN_DELAY_H] hours before it may promote.
@DataClassName('PendingChangeRow')
class PendingChanges extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// UUID of the event whose loosening is queued (UUID stability, §8.9 item 3).
  TextColumn get eventUuid => text()();

  /// Mirrors the firmware `change_type` byte (§9.5). See [PendingChangeType].
  IntColumn get changeType => integer()();

  /// Full proposed post-change state so promotion needs no re-derivation:
  /// a serialized Automation, a deletion marker, a negate-date, or a setting.
  TextColumn get proposedStateJson => text().withDefault(const Constant('{}'))();

  /// Short human summary for the pending-changes UI ("gym SSID change").
  TextColumn get description => text().withDefault(const Constant(''))();

  /// When the loosening was requested (wall clock, for display).
  DateTimeColumn get createdAt => dateTime()();

  /// Earliest wall-clock moment the change may take effect. The UI phrases this
  /// as "takes effect no earlier than [when]" — promotion is never earlier.
  DateTimeColumn get applyAfter => dateTime()();

  /// True once the app has actually re-pushed the promoted state to devices.
  BoolColumn get promoted => boolean().withDefault(const Constant(false))();
}

/// Rolling emergency-pass spend ledger (§8.10, firmware §9.6). Each row is one
/// spent pass; the rolling budget counts rows within [PASS_WINDOW_DAYS].
@DataClassName('EmergencyPassSpendRow')
class EmergencyPassSpends extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The commitment the pass was spent on.
  TextColumn get eventUuid => text()();

  /// The single day skipped, as YYYYMMDD (matches the `…001B` wire format).
  IntColumn get forDate => integer()();

  /// When the pass was spent (wall clock; also the rolling-window aging basis).
  DateTimeColumn get spentAt => dateTime()();

  /// True once the resulting one-off negate has been pushed to devices (a spend
  /// on an active window re-pushes the schedule immediately, §8.10).
  BoolColumn get pushed => boolean().withDefault(const Constant(false))();
}

/// Append-only audit trail (§8.10, §13): every integrity-relevant event, kept
/// for display even after the watch becomes the authoritative ledger.
@DataClassName('AuditEntryRow')
class AuditTrail extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();

  /// e.g. `pass_spent`, `pass_allowance_changed`, `loosening_queued`,
  /// `loosening_promoted`, `loosening_cancelled`, `tightening_applied`.
  TextColumn get category => text()();

  TextColumn get eventUuid => text().nullable()();

  /// Human-readable detail line, voice-guide compliant.
  TextColumn get detail => text().withDefault(const Constant(''))();
}

@DriftDatabase(tables: [PendingChanges, EmergencyPassSpends, AuditTrail])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory instance for tests.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'impulse_integrity.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
