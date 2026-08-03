import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/services/automation_service.dart';
import 'package:impulse_app/services/calibration_store.dart';
import 'package:impulse_app/services/factory_reset_service.dart';
import 'package:impulse_app/services/integrity_store.dart';
import 'package:impulse_app/services/saved_networks_store.dart';
import 'package:impulse_app/services/settle_state_store.dart';
import 'package:impulse_app/services/sync_state_store.dart';

Automation evt(String id) => Automation(
      id: id,
      referenceDate: DateTime.utc(2026, 1, 1),
      startTime: const TimeOfDay(hour: 6, minute: 0),
      endTime: const TimeOfDay(hour: 7, minute: 0),
      recurrenceType: RecurrenceType.daily,
      criteria: Criteria.stayNear,
      profile: EnforcementProfile.strictBoth,
      anchorId: 'anchor-a',
      color: const Color(0xFF000000),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late IntegrityStore integrity;
  late SettleStateStore settle;
  late SyncStateStore sync;
  late SavedNetworksStore networks;
  late CalibrationStore calibration;
  late AutomationService automations;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    db = AppDatabase.forTesting(NativeDatabase.memory());
    integrity = IntegrityStore(db);
    settle = SettleStateStore();
    sync = SyncStateStore();
    // Not the .instance() singleton: this one gets the mocked secure storage,
    // and each test starts from a clean object rather than the last one's state.
    networks = SavedNetworksStore();
    calibration = CalibrationStore();

    // AutomationService IS a singleton, so drain anything a previous test left.
    automations = AutomationService();
    await automations.clearAll();
  });

  tearDown(() async => db.close());

  FactoryResetService svc() => FactoryResetService(
        integrity: integrity,
        settleStore: settle,
        syncStore: sync,
        savedNetworks: networks,
        calibrationStore: calibration,
        automationService: automations,
      );

  test('erases every store it owns', () async {
    // ── Seed each backend ────────────────────────────────────────────────
    await automations.addAutomation(evt('evt-1'));

    await integrity.queueLoosening(
      eventUuid: 'evt-1',
      changeType: PendingChangeType.eventModify,
      proposedStateJson: '{}',
      description: 'shorter window',
      now: DateTime(2026, 8, 1),
      delay: const Duration(hours: 24),
    );
    await integrity.recordPassSpend(
      eventUuid: 'evt-1',
      forDateYyyymmdd: 20260801,
      now: DateTime(2026, 8, 1),
    );

    await networks.load();
    expect(await networks.addOrUpdate('home-wifi', 'hunter2'), isTrue);

    await sync.bump('schedule');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', 'advanced');
    await prefs.setBool('onboarding_done', true);

    // Confirm the seed actually landed, so a passing assertion after the wipe
    // means something was removed rather than never having been there.
    expect(automations.automations, hasLength(1));
    expect(await integrity.pendingChanges(), hasLength(1));
    expect(networks.networks, hasLength(1));
    expect(sync.current('schedule'), 1);
    expect(prefs.getString('app_mode'), 'advanced');

    // ── Wipe ─────────────────────────────────────────────────────────────
    await svc().run();

    // ── Every backend, including the in-memory caches ────────────────────
    expect(automations.automations, isEmpty);
    expect(await integrity.pendingChanges(), isEmpty);
    expect(await integrity.passHistory(), isEmpty);
    expect(await integrity.auditEntries(), isEmpty);
    expect(networks.networks, isEmpty);
    expect(sync.current('schedule'), 0);

    final after = await SharedPreferences.getInstance();
    expect(after.getString('app_mode'), isNull);
    expect(after.getBool('onboarding_done'), isNull);
    expect(after.getKeys(), isEmpty);
  });

  test('wiped stores stay empty when reloaded from disk', () async {
    // The regression this guards: several load() methods only assign when their
    // key is present, so "clear prefs then re-initialize" leaves the pre-reset
    // data sitting in memory looking like it survived the wipe.
    await automations.addAutomation(evt('evt-1'));
    await networks.load();
    await networks.addOrUpdate('home-wifi', 'hunter2');

    await svc().run();

    await automations.initialize();
    await networks.load();
    await settle.load();
    await calibration.load();
    await sync.loadCurrent();

    expect(automations.automations, isEmpty);
    expect(networks.networks, isEmpty);
    expect(sync.current('schedule'), 0);
  });

  test('deletes the stored password, not just the network name', () async {
    // A password orphaned in the Keychain would be invisible to the app but
    // still on the device, and would be silently re-adopted by the next network
    // saved under the same SSID.
    await networks.load();
    await networks.addOrUpdate('home-wifi', 'hunter2');

    await svc().run();

    // Re-add the same SSID with no password: if the old secret were still in
    // the Keychain under the same key, a fresh load() would read it back.
    await networks.load();
    await networks.addOrUpdate('home-wifi', '');
    final reloaded = SavedNetworksStore();
    await reloaded.load();
    expect(reloaded.bySsid('home-wifi')?.password, '');
  });

  test('a clean wipe reports no failures', () async {
    await automations.addAutomation(evt('evt-1'));
    expect(await svc().run(), isEmpty);
  });

  test('reports a failing step instead of claiming a clean wipe', () async {
    // An unreachable Keystore is the realistic failure here — it is the one
    // backend that can be locked or unavailable at the moment of the wipe.
    await automations.addAutomation(evt('evt-1'));
    await networks.load();
    await networks.addOrUpdate('home-wifi', 'hunter2');

    final broken = SavedNetworksStore(secure: const _UnavailableSecureStorage());
    await broken.load();
    final failures = await FactoryResetService(
      integrity: integrity,
      settleStore: settle,
      syncStore: sync,
      savedNetworks: broken,
      calibrationStore: calibration,
      automationService: automations,
    ).run();

    expect(failures, isNotEmpty);
    expect(failures.any((f) => f.contains('saved networks')), isTrue);
    // Every other step still ran. A reset that stops at the first error leaves
    // a state no normal code path produces, which is worse than either outcome.
    expect(automations.automations, isEmpty);
    expect(await integrity.pendingChanges(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}

/// Stands in for a locked or unavailable Keychain/Keystore.
class _UnavailableSecureStorage extends FlutterSecureStorage {
  const _UnavailableSecureStorage();

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw StateError('keystore unavailable');
}
