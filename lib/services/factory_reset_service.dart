import 'package:shared_preferences/shared_preferences.dart';

import 'anchor_distribution_service.dart';
import 'automation_service.dart';
import 'bluetooth_service.dart';
import 'calibration_store.dart';
import 'dock_session_service.dart';
import 'integrity_store.dart';
import 'notification_service.dart';
import 'saved_networks_store.dart';
import 'settle_state_store.dart';
import 'sync_state_store.dart';
import 'watch_service.dart';

/// Erase everything this app has stored and return it to a first-launch state.
///
/// ── What this is NOT ────────────────────────────────────────────────────────
///
/// It is not a system reset. **The watch is the root of trust** (firmware §9):
/// it holds its own schedule, its own pass ledger and its own pairing, and it
/// keeps enforcing them whether or not this app remembers anything. Anchors
/// likewise keep their own schedule, WiFi credentials and calibration in NVS.
/// Nothing here reaches any of that — there is no app-triggerable device wipe in
/// the firmware at all (the anchor's is a physical pin; the watch has none).
///
/// So the honest description is "reset the app", and the confirmation dialog
/// must say so. A user who resets expecting their commitments to stop will
/// instead find a watch that still alarms and an app that no longer recognises
/// it. Telling them up front is the difference between a tool and a trap.
///
/// ── Why it lives in one place ───────────────────────────────────────────────
///
/// The app persists across three backends — `shared_preferences`, the drift
/// SQLite trust stores, and the platform Keychain/Keystore — plus a set of
/// long-lived singletons that cache all three in memory. A reset that misses
/// any one of them leaves the app in a state no normal code path can produce.
/// Putting the whole sequence here means there is exactly one list to keep
/// current when a new store is added.
class FactoryResetService {
  FactoryResetService({
    required IntegrityStore integrity,
    required SettleStateStore settleStore,
    required SyncStateStore syncStore,
    required SavedNetworksStore savedNetworks,
    CalibrationStore? calibrationStore,
    WatchService? watchService,
    AutomationService? automationService,
    BluetoothService? bluetoothService,
  })  : _integrity = integrity,
        _settleStore = settleStore,
        _syncStore = syncStore,
        _savedNetworks = savedNetworks,
        _calibration = calibrationStore ?? CalibrationStore(),
        _watch = watchService ?? WatchService(),
        _automations = automationService ?? AutomationService(),
        _bt = bluetoothService ?? BluetoothService();

  final IntegrityStore _integrity;
  final SettleStateStore _settleStore;
  final SyncStateStore _syncStore;
  final SavedNetworksStore _savedNetworks;
  final CalibrationStore _calibration;
  final WatchService _watch;
  final AutomationService _automations;
  final BluetoothService _bt;

  /// Run the wipe. Ordering is load-bearing — see the numbered steps.
  ///
  /// Best-effort per step: a failure in one backend must not abandon the others
  /// half-way, because a partial reset is worse than either outcome. Anything
  /// that failed comes back in the returned list so the caller can say so
  /// instead of reporting a clean success it cannot vouch for.
  Future<List<String>> run() async {
    final failures = <String>[];

    Future<void> step(String what, Future<void> Function() body) async {
      try {
        await body();
      } catch (e) {
        failures.add('$what ($e)');
      }
    }

    // 1. QUIESCE FIRST. Everything below writes to stores that live BLE traffic
    //    also writes to: a connected watch pushes status, which triggers CRC
    //    confirmation, which writes sync revisions. Wiping underneath that race
    //    means a "reset" app that already has rows in it again by the time the
    //    dialog closes. Cutting the link first is what makes the rest atomic
    //    enough to be believed.
    await step('end dock session',
        () => DockSessionService().endSession(notify: false));
    await step('disconnect watch', () => _watch.disconnect());

    // 2. Cancel every scheduled local notification. These live in the OS, not in
    //    app storage, so a prefs wipe does not touch them — miss this and the
    //    phone keeps firing dock reminders for commitments that no longer exist,
    //    with no app state left to explain them. Rescheduling an empty schedule
    //    is the existing cancel-then-schedule path with nothing to schedule.
    await step('cancel notifications',
        () => NotificationService().rescheduleWindowNotices(const []));

    // 3. Trust stores (drift/SQLite): pending changes, pass ledger, audit trail.
    await step('clear integrity database', () => _integrity.wipeAll());

    // 4. Secure storage: WiFi passwords. Done before the prefs clear, because
    //    the SSID list that names the password keys lives in prefs — wipe that
    //    first and the passwords are orphaned in the Keychain forever, with
    //    nothing left to enumerate them by.
    await step('clear saved networks', () => _savedNetworks.clearAll());

    // 5. The named stores, each dropping its own key AND its in-memory cache.
    //    Several load() methods only assign when their key exists, so "wipe
    //    prefs then re-initialize" would silently keep the pre-reset data in
    //    memory. That is why these are explicit rather than a reload.
    await step('clear schedule', () => _automations.clearAll());
    await step('clear settle state', () => _settleStore.clearAll());
    await step('clear calibration cache', () => _calibration.clearAll());
    await step('clear anchor push history',
        () => AnchorDistributionService().clearAll());
    // Device ids must be read BEFORE the device list is cleared: the per-device
    // acked keys are named after them, and once the list is gone there is
    // nothing left to enumerate the keys by.
    final deviceIds = _bt.deviceHistory.map((d) => d.id).toList();
    await step('clear sync state', () => _syncStore.clearAll(deviceIds));
    await step('forget devices', () => _bt.clearAll());

    // 6. Sweep. The steps above remove what they know about by name; this
    //    catches everything else the app has ever written — mode, onboarding
    //    flags, drafts, watch settings, policy values — including keys written
    //    by code that predates this service or is added after it.
    await step('clear preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    return failures;
  }
}
