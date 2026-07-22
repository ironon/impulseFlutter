import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../models/device_sync_state.dart';
import '../utils/schedule_encoder.dart';
import '../services/anchor_distribution_service.dart';
import '../services/anchor_service.dart';
import '../services/automation_service.dart';
import '../services/bluetooth_service.dart';
import '../services/commitment_policy_service.dart';
import '../services/integrity_store.dart';
import '../services/notification_service.dart';
import '../services/saved_networks_store.dart';
import '../services/settle_state_store.dart';
import '../services/sync_state_store.dart';
import '../services/watch_service.dart';
import '../services/self_binding_policy.dart';
import '../templates/template_registry.dart';

/// App modes (§2A). Normal is the default friendly template layer; Advanced is
/// the raw-block power-user surface with the debug menu.
enum AppMode { normal, advanced }

/// A saved-but-unfinished template setup (§8.1 deferral): an onboarder input
/// the user couldn't answer on the spot. Local-only; never pushed to devices.
class TemplateDraft {
  final String id;
  final String templateId;
  final Map<String, dynamic> params;
  final DateTime createdAt;
  final String note;

  const TemplateDraft({
    required this.id,
    required this.templateId,
    required this.params,
    required this.createdAt,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'params': params,
        'createdAt': createdAt.toIso8601String(),
        'note': note,
      };

  factory TemplateDraft.fromJson(Map<String, dynamic> json) => TemplateDraft(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        params: (json['params'] as Map<String, dynamic>?) ?? const {},
        createdAt: DateTime.parse(json['createdAt'] as String),
        note: (json['note'] as String?) ?? '',
      );
}

/// What happened when a commitment change was saved: the gate verdict plus the
/// watch push result (null when the watch wasn't reachable).
class CommitmentSaveResult {
  final EditOutcome outcome;
  final ScheduleEndResult? pushResult;
  const CommitmentSaveResult(this.outcome, this.pushResult);

  bool get queued => outcome.queued;
}

/// The single reactive state layer (§2) and schedule coordinator. Screens
/// `watch`/`select` this rather than polling services. All commitment edits
/// route through here so the §8.9 policy can never be bypassed by a screen.
class AppState extends ChangeNotifier {
  AppState({
    required IntegrityStore integrityStore,
    WatchService? watchService,
    AutomationService? automationService,
  })  : _integrity = integrityStore,
        _watch = watchService ?? WatchService(),
        _automations = automationService ?? AutomationService();

  final IntegrityStore _integrity;
  final WatchService _watch;
  final AutomationService _automations;

  /// Registry-driven templates (§2A) — the Normal-mode UI + onboarding gallery
  /// are generated from this.
  final TemplateRegistry registry = TemplateRegistry.seeded();

  /// Interim per-event settle state (§8.9).
  final SettleStateStore settleStore = SettleStateStore();

  /// Saved WiFi networks (§8.15) — the single credential source for the watch
  /// push, anchor provisioning (§8.14), and watch repair (firmware §5.5.3).
  final SavedNetworksStore savedNetworks = SavedNetworksStore.instance();

  /// Per-payload sync/stale tracking (§8.16). Revision-vs-acked, plus the
  /// schedule CRC cross-check. Distinct from liveness (§8.7) and pending
  /// changes (§8.9).
  final SyncStateStore syncStore = SyncStateStore();

  /// CRC32 of the effective schedule the app currently authors (the schedule the
  /// devices *should* be running — current rule + promoted + immediate
  /// tightenings, NOT withheld loosenings, §8.16). Compared against each
  /// device's reported schedule_crc to confirm sync.
  int? _effectiveScheduleCrc;
  int? get effectiveScheduleCrc => _effectiveScheduleCrc;

  /// Device ids with a sync attempt in flight → show a spinner, not yellow.
  final Set<String> _syncingDevices = {};

  /// True once the empty-networks startup warning has been dismissed for THIS
  /// launch (§8.15 — "Ignore" is per-launch, never suppressed permanently).
  bool emptyNetworksWarningDismissed = false;

  CommitmentPolicyService? _policy;
  CommitmentPolicyService get policy => _policy!;

  IntegrityStore get integrity => _integrity;
  WatchService get watch => _watch;

  StreamSubscription<WatchStatus>? _statusSub;
  StreamSubscription<List<PendingChangeRow>>? _pendingSub;

  // ── Live watch state ──
  WatchStatus? _status;
  WatchStatus? get status => _status;
  bool get watchConnected => _watch.isConnected;

  // ── Pending-changes state (§8.9 item 5) ──
  List<PendingChangeRow> _pendingRows = const [];
  List<PendingChangeRow> get pendingRows => _pendingRows;

  /// The watch's authoritative …001A queue, when the characteristic exists.
  /// Null ⇒ not probed / absent; render the app-side interim queue instead.
  List<PendingChangeEntry>? _watchPendingEntries;
  List<PendingChangeEntry>? get watchPendingEntries => _watchPendingEntries;

  /// Event UUIDs with an unpromoted pending loosening — drives per-commitment
  /// pending badges. Union of the app queue and the watch queue when present.
  Set<String> get pendingEventIds => {
        for (final r in _pendingRows) r.eventUuid,
        ...?_watchPendingEntries?.map((e) => e.eventUuid),
      }..removeWhere((id) => id.startsWith('settings:'));

  // ── Mode ──
  AppMode _mode = AppMode.normal;
  AppMode get mode => _mode;
  bool get advancedMode => _mode == AppMode.advanced;

  bool _advancedIntroSeen = false;
  bool get advancedIntroSeen => _advancedIntroSeen;

  bool _onboardingDone = false;
  bool get onboardingDone => _onboardingDone;

  // ── Drafts (§8.1 deferral) ──
  List<TemplateDraft> _drafts = [];
  List<TemplateDraft> get drafts => List.unmodifiable(_drafts);

  List<Automation> get schedule => _automations.automations;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    await _automations.initialize();
    await settleStore.load();
    await savedNetworks.load();
    await syncStore.loadCurrent();
    for (final d in BluetoothService().deviceHistory) {
      await syncStore.loadDevice(d.id);
    }

    final prefs = await SharedPreferences.getInstance();
    _mode = (prefs.getString('app_mode') == 'advanced')
        ? AppMode.advanced
        : AppMode.normal;
    _advancedIntroSeen = prefs.getBool('advanced_intro_seen') ?? false;
    _onboardingDone = prefs.getBool('onboarding_done') ?? false;
    _drafts = (prefs.getStringList('template_drafts') ?? [])
        .map((s) =>
            TemplateDraft.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    _policy = CommitmentPolicyService(
      integrity: _integrity,
      settleStore: settleStore,
    )..restore(
        passAllowance: prefs.getInt('pass_allowance'),
        settleWindowMin: prefs.getInt('settle_window_min'),
      );

    _statusSub = _watch.statusStream.listen((s) {
      _status = s;
      // Confirm-vs-infer the watch's schedule from its reported CRC (§8.16).
      unawaited(_confirmWatchScheduleCrc(s));
      notifyListeners();
    });

    // Seed the effective-schedule CRC so staleness has a baseline before the
    // first edit (a reinstall reads everything stale until confirmed).
    await _refreshScheduleRevision();
    _pendingSub = _integrity.watchPendingChanges().listen((rows) {
      _pendingRows = rows;
      notifyListeners();
    });

    // Startup is a push opportunity: settle due events, promote due loosenings.
    await settleStore.settleDue(
        schedule, DateTime.now(), policy.config.settleWindow);
    await promoteDuePending(pushAfter: false);

    // Local notifications (§8.6 step 1): dock reminders + window notices for
    // the coming 48 h, rescheduled on every schedule change and foreground.
    await NotificationService().init();
    unawaited(
        NotificationService().rescheduleWindowNotices(await scheduleForPush()));

    notifyListeners();
  }

  /// Call after any BLE connection state change so widgets re-render. Also a
  /// reconcile point with the watch's authoritative queue.
  void connectionChanged() {
    notifyListeners();
    if (_watch.isConnected) {
      refreshWatchPending();
      // Opportunistic convergence (§8.16): a watch coming into range clears its
      // own yellow by re-pushing whatever it's behind on — no user action.
      unawaited(attemptWatchSync(allowScan: false));
      // Complete any pass spends that were held pending while out of range
      // (§8.10) — the spend applies the moment the watch is back.
      unawaited(completePendingPassSpends());
    } else {
      _watchPendingEntries = null;
      notifyListeners();
    }
  }

  /// Probe + read the watch's authoritative Pending Changes queue (…001A).
  /// Degrades to the interim app-side queue when the characteristic is absent.
  Future<void> refreshWatchPending() async {
    if (!_watch.isConnected || !_watch.hasPendingChangesCharacteristic) {
      _watchPendingEntries = null;
      notifyListeners();
      return;
    }
    try {
      _watchPendingEntries = await _watch.readPendingChanges();
    } catch (_) {
      _watchPendingEntries = null;
    }
    notifyListeners();
  }

  // ── Mode & prefs ──────────────────────────────────────────────────────────

  Future<void> setMode(AppMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_mode', mode.name);
    notifyListeners();
  }

  Future<void> markAdvancedIntroSeen() async {
    _advancedIntroSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('advanced_intro_seen', true);
  }

  Future<void> markOnboardingDone() async {
    _onboardingDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    notifyListeners();
  }

  Future<void> _persistPolicyValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pass_allowance', policy.passAllowance);
    await prefs.setInt(
        'settle_window_min', policy.config.settleWindow.inMinutes);
  }

  // ── Drafts ────────────────────────────────────────────────────────────────

  Future<void> addDraft(TemplateDraft draft) async {
    _drafts.add(draft);
    await _saveDrafts();
    notifyListeners();
  }

  Future<void> removeDraft(String id) async {
    _drafts.removeWhere((d) => d.id == id);
    await _saveDrafts();
    notifyListeners();
  }

  Future<void> _saveDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'template_drafts',
      _drafts.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  // ── Commitment edits (ALL edits route through here — §8.9) ───────────────

  /// Save a new or edited commitment through the diff gate. When the edit is
  /// quarantined the pre-edit state stays active (and enforcing) until the
  /// pending change promotes.
  Future<CommitmentSaveResult> saveCommitment({
    Automation? previous,
    required Automation updated,
  }) async {
    EditOutcome outcome;
    if (previous == null) {
      await policy.applyCreate(updated);
      await _automations.addAutomation(updated);
      outcome = const EditOutcome(
          GateDecision.applyImmediately, ChangeClassification.tightening);
    } else {
      outcome = await policy.applyEdit(previous, updated);
      if (outcome.decision == GateDecision.applyImmediately) {
        await _automations.updateAutomation(updated);
      }
      // Quarantined: keep the pre-edit rule active; the queue holds the intent.
    }
    final push = await pushScheduleToWatch();
    notifyListeners();
    return CommitmentSaveResult(outcome, push);
  }

  /// Delete a commitment through the gate.
  Future<CommitmentSaveResult> deleteCommitment(Automation event) async {
    final outcome = await policy.applyDelete(event);
    if (outcome.decision == GateDecision.applyImmediately) {
      await _automations.deleteAutomation(event.id);
    }
    final push = await pushScheduleToWatch();
    notifyListeners();
    return CommitmentSaveResult(outcome, push);
  }

  /// Apply a template's regenerated block set (§2A.3 / §8.9 item 3).
  Future<Map<String, EditOutcome>> saveTemplateBlocks(
      List<Automation> oldBlocks, List<Automation> newBlocks) async {
    final outcomes = await policy.applyBlockSet(oldBlocks, newBlocks);
    for (final entry in outcomes.entries) {
      final newBlock = newBlocks.where((b) => b.id == entry.key).firstOrNull;
      final oldBlock = oldBlocks.where((b) => b.id == entry.key).firstOrNull;
      if (entry.value.decision == GateDecision.applyImmediately) {
        if (newBlock == null) {
          await _automations.deleteAutomation(entry.key);
        } else if (oldBlock == null) {
          await _automations.addAutomation(newBlock);
        } else {
          await _automations.updateAutomation(newBlock);
        }
      }
    }
    await pushScheduleToWatch();
    notifyListeners();
    return outcomes;
  }

  // ── Emergency passes (§8.10) ──────────────────────────────────────────────

  /// Spend a pass: immediate, allowed on active windows. Prefers the watch's
  /// on-watch ledger (…001B) when present; otherwise the interim app ledger.
  /// Re-pushes the schedule (with the one-day negate) so an active window
  /// actually stops.
  /// Spend an emergency pass (§8.10). **Ack-before-decrement**: the spend is
  /// only "real" once the watch confirms it — the `…001B` `0x01`, or the interim
  /// schedule END ack. If the watch is unreachable the spend is **held pending**
  /// (a `pushed==false` ledger row so its negate still rides in `scheduleForPush`
  /// and it's tracked for retry), we tell the user honestly, and it completes
  /// automatically on reconnect. A retry reuses the pending row — never double
  /// charged.
  Future<PassSpendResult> spendPass(Automation event, DateTime date) async {
    final yyyymmdd = date.year * 10000 + date.month * 100 + date.day;
    final existing = await _integrity.pendingSpendFor(event.id, yyyymmdd);
    final remaining = await policy.remainingPasses();
    if (existing == null && remaining <= 0) {
      return const PassSpendResult(success: false, remaining: 0);
    }

    // Authoritative on-watch ledger path (…001B), when present + connected.
    if (_watch.isConnected && _watch.hasEmergencyPassCharacteristic) {
      final resp = await _watch.spendEmergencyPass(event.id, yyyymmdd);
      if (resp != null) {
        if (resp.resp == 0x01) {
          if (existing != null) {
            await _integrity.markPassPushed(existing.id);
          } else {
            await _integrity.recordPassSpend(
              eventUuid: event.id,
              forDateYyyymmdd: yyyymmdd,
              now: DateTime.now(),
              pushed: true,
            );
          }
          notifyListeners();
          return PassSpendResult(
              success: true,
              remaining: resp.remaining ?? await policy.remainingPasses());
        }
        if (resp.resp == 0x02) {
          // Watch's own ledger is exhausted — void any local pending, fail.
          if (existing != null) await _integrity.deletePassSpend(existing.id);
          notifyListeners();
          return const PassSpendResult(success: false, remaining: 0);
        }
      }
      // resp == null → write didn't land; fall through to the pending path.
    }

    // Record (or reuse) a pending ledger row so the one-day negate rides in the
    // next schedule push and the spend is tracked for retry (no double-charge).
    final spendId = existing?.id ??
        await _integrity.recordPassSpend(
          eventUuid: event.id,
          forDateYyyymmdd: yyyymmdd,
          now: DateTime.now(),
          pushed: false,
        );

    // Interim confirmation: the spend commits only if the watch acks the re-push
    // (spending on an active window must actually stop enforcement, §8.10).
    final push = await pushScheduleToWatch();
    final confirmed = push == ScheduleEndResult.accepted ||
        push == ScheduleEndResult.partialQuarantine;
    if (confirmed) {
      await _integrity.markPassPushed(spendId);
      notifyListeners();
      return PassSpendResult(
          success: true, remaining: await policy.remainingPasses());
    }

    // Held pending — honest UX; auto-completes on reconnect (same opportunistic
    // path as §8.16). Enforcement may continue until then.
    notifyListeners();
    return PassSpendResult(
        success: true, pending: true, remaining: await policy.remainingPasses());
  }

  /// Complete any pending pass spends now that the watch is reachable (§8.10) —
  /// the reconnect/foreground counterpart to the ack-before-decrement rule.
  Future<void> completePendingPassSpends() async {
    if (!_watch.isConnected) return;
    final pending = await _integrity.pendingPassSpends();
    if (pending.isEmpty) return;
    if (_watch.hasEmergencyPassCharacteristic) {
      for (final p in pending) {
        final resp = await _watch.spendEmergencyPass(p.eventUuid, p.forDate);
        if (resp?.resp == 0x01) {
          await _integrity.markPassPushed(p.id);
        } else if (resp?.resp == 0x02) {
          await _integrity.deletePassSpend(p.id); // watch ledger exhausted
        }
      }
    } else {
      // Interim: a single acked re-push confirms every currently-pending spend
      // (they all ride in the same schedule blob via scheduleForPush).
      final push = await pushScheduleToWatch();
      if (push == ScheduleEndResult.accepted ||
          push == ScheduleEndResult.partialQuarantine) {
        for (final p in pending) {
          await _integrity.markPassPushed(p.id);
        }
      }
    }
    notifyListeners();
  }

  Future<int> changePassAllowance(int allowance) async {
    final v = await policy.changeAllowance(allowance);
    await _persistPolicyValues();
    // Mirror to the on-watch ledger when it exists (…001B SET_ALLOWANCE):
    // the watch applies the same rule — 0x01 lower applied, 0x03 raise
    // quarantined into its own pending queue.
    if (_watch.isConnected && _watch.hasEmergencyPassCharacteristic) {
      final resp = await _watch.setEmergencyPassAllowance(allowance);
      if (resp == 0x03) await refreshWatchPending();
    }
    notifyListeners();
    return v;
  }

  /// Read the on-watch pass ledger for display. Null when absent — the
  /// interim app ledger is then the shown source.
  Future<WatchPassLedger?> readWatchPassLedger() async {
    if (!_watch.isConnected || !_watch.hasEmergencyPassCharacteristic) {
      return null;
    }
    try {
      return await _watch.readEmergencyPassLedger();
    } catch (_) {
      return null;
    }
  }

  Future<void> changeSettleWindow(int minutes) async {
    await policy.changeSettleWindow(minutes);
    await _persistPolicyValues();
    // settle_window_min is part of the watch Settings payload → a sync class
    // change (§8.16). Bump and try to converge.
    await onWatchSettingsEdited(pushedOk: false);
    notifyListeners();
  }

  // ── Schedule push & promotion (push opportunities, §8.9 item 5) ──────────

  /// The event list the devices should run: the authored schedule plus one-day
  /// negates for unexpired emergency-pass spends (interim path).
  Future<List<Automation>> scheduleForPush() async {
    final base = List<Automation>.from(schedule);
    final today = DateTime.now();
    final todayYyyymmdd = today.year * 10000 + today.month * 100 + today.day;
    for (final spend in await _integrity.passHistory()) {
      if (spend.forDate < todayYyyymmdd) continue; // expired: drop, not apply
      final target =
          schedule.where((a) => a.id == spend.eventUuid).firstOrNull;
      if (target == null) continue;
      final y = spend.forDate ~/ 10000;
      final m = (spend.forDate % 10000) ~/ 100;
      final d = spend.forDate % 100;
      base.add(target.copyWith(
        negate: true,
        recurrenceType: RecurrenceType.once,
        referenceDate: DateTime.utc(y, m, d),
        startTime: const TimeOfDay(hour: 0, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 59),
      ));
    }
    return base;
  }

  /// Promote due pending loosenings, then push. Every push is a promotion
  /// opportunity — a queued loosening takes effect no earlier than its delay,
  /// at the first moment the app can actually re-push.
  Future<ScheduleEndResult?> pushScheduleToWatch() async {
    await promoteDuePending(pushAfter: false);
    final events = await scheduleForPush();

    // The effective schedule may have changed → bump the schedule revision so
    // any device that hasn't confirmed the new CRC reads stale (§8.16).
    await _refreshScheduleRevision();

    // Anchors get the same schedule over WiFi/HTTP (§7.3); a 200 advances that
    // anchor's acked schedule revision, anything else leaves it yellow (§8.16).
    unawaited(_pushScheduleToAnchorsTracked(events));

    // The schedule changed: refresh the coming 48 h of local notices.
    unawaited(NotificationService().rescheduleWindowNotices(events));

    if (!_watch.isConnected) return null;
    try {
      final result = await _watch.pushSchedule(events);
      if (result == ScheduleEndResult.partialQuarantine ||
          result == ScheduleEndResult.rejected) {
        // The watch quarantined/rejected parts — its queue is the truth now.
        await refreshWatchPending();
      }
      // Note: the schedule ack is confirmed authoritatively by the watch's
      // reported schedule_crc (§8.16 _confirmWatchScheduleCrc), NOT by the END
      // byte — a 0x03 means the watch's effective blob differs from ours.
      return result;
    } catch (_) {
      return ScheduleEndResult.failed;
    }
  }

  /// HTTP-push the schedule to every known anchor IP, advancing each anchor's
  /// acked schedule revision on a 200 (§8.16). Anchors that don't 200 stay
  /// stale/yellow and retry opportunistically.
  Future<void> _pushScheduleToAnchorsTracked(List<Automation> events) async {
    final dist = AnchorDistributionService();
    final anchors =
        BluetoothService().anchors.where((a) => a.ipAddress != null).toList();
    for (final a in anchors) {
      await syncStore.loadDevice(a.id);
      final ok = await dist.pushToAnchor(a.ipAddress!, events);
      if (ok) {
        await syncStore.setAcked(a.id, SyncClass.schedule);
      }
    }
    notifyListeners();
  }

  /// App-foreground opportunistic work (§7.3/§8.4/§8.11): promote due
  /// loosenings, refresh anchor IPs over mDNS (a newly learned IP triggers a
  /// full anchor push + a watch IP-table refresh), re-push stale anchors
  /// (last success older than ~12h — deliberately no midnight push), and
  /// push time to the watch while connected.
  Future<void> onAppForeground() async {
    await promoteDuePending(pushAfter: false);

    final dist = AnchorDistributionService();
    final events = await scheduleForPush();
    await _refreshScheduleRevision();
    final changed = await dist.refreshAnchorIps();
    if (changed.isNotEmpty) {
      // A new anchor IP is learned → full anchor push + watch IP-table refresh.
      await _pushScheduleToAnchorsTracked(events);
      await syncStore.bump(SyncClass.watchIpTable);
      await _pushAnchorIpTableTracked();
    } else {
      await dist.pushStale(events);
    }

    // Reactive convergence (§8.16): if the watch is behind anything, push it now.
    await attemptWatchSync(allowScan: false);

    // Failure-driven anchor WiFi check-then-offer (§8.14) — piggybacks on this
    // ~12 h foreground sweep, only touching anchors that look stranded.
    await sweepStrandedAnchors();

    // Complete any pending pass spends (§8.10) if the watch is reachable now.
    await completePendingPassSpends();

    if (_watch.isConnected && _watch.hasTimeCharacteristic) {
      try {
        await _watch.pushTime(DateTime.now().toUtc(),
            DateTime.now().timeZoneOffset.inMinutes);
      } catch (_) {}
    }

    // Refresh the coming 48 h of local notices while we're at it.
    unawaited(NotificationService().rescheduleWindowNotices(events));
    notifyListeners();
  }

  /// Apply any app-side pending entries whose delay has elapsed.
  Future<void> promoteDuePending({bool pushAfter = true}) async {
    final now = DateTime.now();
    final due = await _integrity.duePromotions(now);
    var changed = false;
    for (final row in due) {
      final type = PendingChangeType.values[row.changeType];
      final proposed =
          jsonDecode(row.proposedStateJson) as Map<String, dynamic>;
      switch (type) {
        case PendingChangeType.eventModify:
          final a = Automation.fromJson(proposed);
          await _automations.updateAutomation(a);
          await settleStore.recordEdit(a.id, now);
          changed = true;
          break;
        case PendingChangeType.eventDelete:
          await _automations.deleteAutomation(row.eventUuid);
          await settleStore.remove(row.eventUuid);
          changed = true;
          break;
        case PendingChangeType.negateDay:
          // Interim negates ride along in scheduleForPush; nothing to apply.
          break;
        case PendingChangeType.setting:
          await policy.applyPromotedSetting(proposed);
          await _persistPolicyValues();
          break;
      }
      await _integrity.markPromoted(row.id, now);
      // §8.9 item 5: promotions are surfaced, not silent.
      unawaited(NotificationService().notifyPromotion(row.description));
    }
    if (changed && pushAfter) {
      await pushScheduleToWatch();
    }
    if (due.isNotEmpty) notifyListeners();
  }

  // ── Sync state & the stale marker (§8.16) ───────────────────────────────────

  /// The paired watch's device id (stable key for acked revisions), or null.
  String? get watchDeviceId {
    final watches = BluetoothService().watches;
    return watches.isEmpty ? null : watches.first.id;
  }

  /// Recompute the effective-schedule CRC (§8.16 — the schedule the devices
  /// *should* run; withheld loosenings are excluded because they're absent from
  /// `scheduleForPush`). Bumps the schedule revision when the content changes so
  /// unconfirmed devices read stale.
  Future<void> _refreshScheduleRevision() async {
    final events = await scheduleForPush();
    int? crc;
    try {
      crc = ScheduleEncoder.crc32(ScheduleEncoder.encodeBlob(events));
    } catch (_) {
      // If the schedule can't be encoded (shouldn't happen with real UUIDs) we
      // can't compute a CRC — leave the revision untouched rather than crash.
      return;
    }
    if (crc != _effectiveScheduleCrc) {
      _effectiveScheduleCrc = crc;
      await syncStore.bump(SyncClass.schedule);
    }
  }

  /// Confirm-vs-infer the watch's schedule from its reported CRC (§8.16). A
  /// match clears yellow even if we never saw the END ack (e.g. after reinstall);
  /// a mismatch marks it stale even if the app believed it had pushed — catching
  /// a watch that reverted to a stale persisted schedule after a reset.
  Future<void> _confirmWatchScheduleCrc(WatchStatus s) async {
    final id = watchDeviceId;
    if (id == null || _effectiveScheduleCrc == null) return;
    final devCrc = s.scheduleCrc;
    if (devCrc == null) return; // pre-v0.8 / truncated → fall back to rev-vs-ack
    await syncStore.loadDevice(id);
    if (devCrc == _effectiveScheduleCrc) {
      await syncStore.setAcked(id, SyncClass.schedule);
    } else {
      await syncStore.markBehind(id, SyncClass.schedule);
    }
    notifyListeners();
  }

  /// Same CRC cross-check for an anchor (§8.16) — call with the CRC learned from
  /// its `…000E` read or `GET /schedule`.
  Future<void> confirmAnchorScheduleCrc(String anchorId, int? anchorCrc) async {
    if (_effectiveScheduleCrc == null || anchorCrc == null) return;
    await syncStore.loadDevice(anchorId);
    if (anchorCrc == _effectiveScheduleCrc) {
      await syncStore.setAcked(anchorId, SyncClass.schedule);
    } else {
      await syncStore.markBehind(anchorId, SyncClass.schedule);
    }
    notifyListeners();
  }

  bool isDeviceSyncing(String deviceId) => _syncingDevices.contains(deviceId);

  /// Derived sync state for a device card (§8.16). Yellow only once an attempt
  /// has settled; a spinner while one is in flight.
  DeviceSyncState deviceSyncState(BluetoothDeviceModel device) {
    if (_syncingDevices.contains(device.id)) return DeviceSyncState.syncing;
    final behind = <String>[];
    if (device.deviceType == DeviceType.watch) {
      if (syncStore.isBehind(device.id, SyncClass.schedule)) behind.add('schedule');
      if (syncStore.isBehind(device.id, SyncClass.watchSettings)) behind.add('settings');
      if (syncStore.isBehind(device.id, SyncClass.watchNetworks)) behind.add('networks');
      if (syncStore.isBehind(device.id, SyncClass.watchIpTable)) behind.add('anchor IPs');
    } else if (device.deviceType == DeviceType.anchor) {
      if (syncStore.isBehind(device.id, SyncClass.schedule)) behind.add('schedule');
      if (syncStore.isBehind(
          device.id, SyncClass.anchorKey(SyncClass.anchorSettings, device.id))) {
        behind.add('settings');
      }
      if (syncStore.isBehind(
          device.id, SyncClass.anchorKey(SyncClass.anchorWifiCreds, device.id))) {
        behind.add('WiFi');
      }
    }
    return behind.isEmpty
        ? DeviceSyncState.synced
        : DeviceSyncState(status: SyncStatus.stale, behindClasses: behind);
  }

  /// Attempt to converge the watch (§8.16 auto-sync): push everything it's
  /// behind on. If connected, push now; else if [allowScan], run a bounded
  /// foreground scan → connect → push; else leave it stale/yellow. Guarded so a
  /// burst of edits coalesces into one in-flight attempt.
  Future<void> attemptWatchSync({required bool allowScan}) async {
    final id = watchDeviceId;
    if (id == null) return;
    await syncStore.loadDevice(id);
    final needsSchedule = syncStore.isBehind(id, SyncClass.schedule);
    final needsSettings = syncStore.isBehind(id, SyncClass.watchSettings);
    final needsNetworks = syncStore.isBehind(id, SyncClass.watchNetworks);
    final needsIps = syncStore.isBehind(id, SyncClass.watchIpTable);
    if (!(needsSchedule || needsSettings || needsNetworks || needsIps)) return;
    if (_syncingDevices.contains(id)) return; // already in flight (debounce)

    _syncingDevices.add(id);
    notifyListeners();
    try {
      var connected = _watch.isConnected;
      if (!connected && allowScan) {
        connected = await _scanConnectWatch();
      }
      if (!connected) return; // settled stale — retried opportunistically
      if (needsSchedule) await pushScheduleToWatch();
      if (needsNetworks) await pushSavedNetworksToWatch();
      if (needsIps) await _pushAnchorIpTableTracked();
      // Watch settings are re-pushed from stored prefs.
      if (needsSettings) await pushWatchSettingsFromStored();
    } catch (_) {
      // Leave whatever didn't ack as stale; convergence is reactive.
    } finally {
      _syncingDevices.remove(id);
      notifyListeners();
    }
  }

  /// User-tapped "Sync now" (§8.16) — a fresh attempt including a scan.
  Future<void> syncNow(BluetoothDeviceModel device) async {
    if (device.deviceType == DeviceType.watch) {
      await attemptWatchSync(allowScan: true);
    } else if (device.deviceType == DeviceType.anchor) {
      // Anchor config travels over HTTP (schedule) / directed BLE; re-push the
      // schedule to all anchors, which re-acks reachable ones.
      final events = await scheduleForPush();
      await _pushScheduleToAnchorsTracked(events);
    }
  }

  /// Bounded foreground scan for the watch service, then connect (§8.16 step 1).
  /// Returns true once connected. Never a background scan (iOS forbids it).
  Future<bool> _scanConnectWatch() async {
    final bt = BluetoothService();
    try {
      final completer = Completer<fbp.BluetoothDevice?>();
      late StreamSubscription sub;
      sub = bt.startScan().listen((results) {
        for (final r in results) {
          if (bt.classifyDevice(r) == DeviceType.watch) {
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });
      final device = await completer.future
          .timeout(const Duration(seconds: 12), onTimeout: () => null);
      await sub.cancel();
      await bt.stopScan();
      if (device == null) return false;
      await _watch.connect(device);
      connectionChanged();
      return _watch.isConnected;
    } catch (_) {
      try { await bt.stopScan(); } catch (_) {}
      return false;
    }
  }

  /// Push watch settings from the persisted values (§8.16 re-sync path). Acks
  /// the watchSettings class on a `0x01`.
  Future<void> pushWatchSettingsFromStored() async {
    if (!_watch.isConnected) return;
    final prefs = await SharedPreferences.getInstance();
    final disc = prefs.getBool('setting_disc_dorm') ?? true;
    final away = prefs.getBool('setting_away_dorm') ?? true;
    final tz = prefs.getInt('setting_tz') ?? DateTime.now().timeZoneOffset.inMinutes;
    try {
      final resp = await _watch.pushSettings(
        disconnectedIsDormant: disc,
        awayIsDormant: away,
        tzOffsetMinutes: tz,
        settleWindowMin: policy.config.settleWindow.inMinutes,
      );
      final id = watchDeviceId;
      // 0x01 full apply, or 0x03 (some loosening quarantined) still means the
      // non-quarantined fields landed — either way the write reached the watch.
      if (id != null && (resp == 0x01 || resp == 0x03)) {
        await syncStore.setAcked(id, SyncClass.watchSettings);
      }
    } catch (_) {}
  }

  /// Record that the user edited watch settings (§8.16): bump the revision, then
  /// ack if the accompanying push succeeded, else kick a sync attempt.
  Future<void> onWatchSettingsEdited({required bool pushedOk}) async {
    await syncStore.bump(SyncClass.watchSettings);
    final id = watchDeviceId;
    if (pushedOk && id != null) {
      await syncStore.setAcked(id, SyncClass.watchSettings);
    } else {
      await attemptWatchSync(allowScan: true);
    }
    notifyListeners();
  }

  /// Push the anchor IP table to the watch, acking watchIpTable on `0x01`.
  Future<void> _pushAnchorIpTableTracked() async {
    if (!_watch.isConnected) return;
    try {
      final ok = await _watch.pushAnchorIpTable(BluetoothService().anchors);
      final id = watchDeviceId;
      if (ok && id != null) await syncStore.setAcked(id, SyncClass.watchIpTable);
    } catch (_) {}
  }

  // ── Anchor WiFi re-provisioning (§8.14) ─────────────────────────────────────

  T? _firstOrNull<T>(Iterable<T> it) {
    for (final e in it) {
      return e;
    }
    return null;
  }

  /// Fold a fresh `…000E` read into the anchor record (§4.4): real state, ssid,
  /// slots, learned IP, and check timestamp. Clears the distress-notified flag
  /// once the anchor is no longer in distress.
  BluetoothDeviceModel _applyWifiStatus(
      BluetoothDeviceModel anchor, AnchorWifiStatus s) {
    return anchor.copyWith(
      lastWifiState: s.state.index,
      lastWifiSsid: s.ssid,
      lastWifiCheckAt: DateTime.now(),
      slotsUsed: s.slotsUsed,
      // Learn the IP over BLE (§8.14) — a genuine HTTP-push fallback when mDNS
      // is unavailable.
      ipAddress: s.ipv4 ?? anchor.ipAddress,
      clearDistressNotified: !s.state.isDistress,
    );
  }

  /// Offer a saved network to an anchor over `…0003` and fold the outcome back
  /// into the record (§8.14). Records the SSID as offered so a failing pair is
  /// not re-offered every sweep.
  Future<void> _offerToAnchor(
      BluetoothDeviceModel anchor, dynamic net) async {
    if (anchor.bleRemoteId == null) return;
    final res = await AnchorService().sendWifiCredentials(
      anchor.bleRemoteId!,
      ssid: net.ssid as String,
      password: net.password as String,
    );
    final offered = List<String>.from(anchor.offeredSsids);
    if (!offered.contains(net.ssid)) offered.add(net.ssid as String);
    var updated = anchor.copyWith(offeredSsids: offered);
    if (res.statusAfter != null) {
      updated = _applyWifiStatus(updated, res.statusAfter!);
    }
    await BluetoothService().addOrUpdateDevice(updated);
    if (res.statusAfter != null) {
      await confirmAnchorScheduleCrc(anchor.id, res.statusAfter!.scheduleCrc);
    }
    notifyListeners();
  }

  /// Check-then-offer for one anchor (§8.14). A cheap BLE **read** of `…000E`
  /// decides whether a write is warranted — never a blind periodic overwrite.
  /// Returns the observed status (null if BLE-unreachable or the char is absent
  /// on older firmware — degrade gracefully). [allowHealthyOffer] gates the
  /// additive-resilience offer to a *connected* anchor (the app may; the watch
  /// may not, firmware §5.5.3).
  Future<AnchorWifiStatus?> checkAndOfferAnchor(
    BluetoothDeviceModel anchor, {
    bool allowHealthyOffer = true,
  }) async {
    if (anchor.bleRemoteId == null) return null;
    final status = await AnchorService().readWifiStatus(anchor.bleRemoteId!);
    if (status == null) return null; // BLE unreachable / pre-v0.8 anchor

    var updated = _applyWifiStatus(anchor, status);
    await BluetoothService().addOrUpdateDevice(updated);
    await confirmAnchorScheduleCrc(anchor.id, status.scheduleCrc);
    notifyListeners();

    final saved = savedNetworks.networks;

    switch (status.state) {
      case AnchorWifiState.connecting:
      case AnchorWifiState.unknown:
        return status; // wait; re-check next sweep
      case AnchorWifiState.connected:
        // Additive resilience: offer a saved network the anchor isn't on and we
        // haven't offered — non-destructive thanks to the 4-slot store (§4.4).
        if (allowHealthyOffer) {
          final cand = _firstOrNull(saved.where((n) =>
              n.ssid != status.ssid && !updated.offeredSsids.contains(n.ssid)));
          if (cand != null) await _offerToAnchor(updated, cand);
        }
        return status;
      case AnchorWifiState.neverProvisioned:
        final cand = _firstOrNull(saved
                .where((n) => !updated.offeredSsids.contains(n.ssid))) ??
            _firstOrNull(saved);
        if (cand != null) await _offerToAnchor(updated, cand);
        return status;
      case AnchorWifiState.authFailed:
      case AnchorWifiState.apNotFound:
        // Offer a saved network matching the anchor's stored SSID whose password
        // we haven't already offered (covers a since-added / corrected password).
        final match = _firstOrNull(saved.where((n) =>
            n.ssid == status.ssid && !updated.offeredSsids.contains(n.ssid)));
        if (match != null) {
          await _offerToAnchor(updated, match);
        } else if (saved.isNotEmpty &&
            updated.distressNotifiedState != status.state.index) {
          // Distress we can't fix from saved creds → notify once per episode
          // (reset when state changes). Empty-list is covered by the §8.15
          // startup warning instead, so we only notify with a populated list.
          await NotificationService()
              .notifyAnchorDistress(updated.name, status.ssid);
          await BluetoothService().addOrUpdateDevice(
              updated.copyWith(distressNotifiedState: status.state.index));
          notifyListeners();
        }
        return status;
    }
  }

  /// "Re-send WiFi" (§8.2): offer a specific saved network to an anchor on
  /// demand. Safe to expose unconditionally now that anchor creds are slot-based
  /// and non-destructive (§8.14).
  Future<AnchorWifiOfferResult?> offerSavedNetworkToAnchor(
      BluetoothDeviceModel anchor, String ssid) async {
    if (anchor.bleRemoteId == null) return null;
    final net = savedNetworks.bySsid(ssid);
    if (net == null) return null;
    await _offerToAnchor(anchor, net);
    // Re-read to reflect the outcome the offer produced.
    return AnchorWifiOfferResult(
      accepted: true,
      connectionError: false,
      statusAfter: await AnchorService().readWifiStatus(anchor.bleRemoteId!),
    );
  }

  /// Failure-driven sweep (§8.14): after a foreground push, run the cheap
  /// `…000E` check on anchors that look stranded — BLE-reachable but with no
  /// learned IP or a schedule that isn't confirmed synced. Reuses the ~12 h
  /// staleness cadence (no new timer); one staleness concept for the user.
  Future<void> sweepStrandedAnchors() async {
    for (final a in BluetoothService().anchors) {
      if (a.bleRemoteId == null) continue;
      await syncStore.loadDevice(a.id);
      final looksStranded =
          a.ipAddress == null || syncStore.isBehind(a.id, SyncClass.schedule);
      if (looksStranded) {
        await checkAndOfferAnchor(a);
      }
    }
  }

  /// When a saved network's password is edited, forget that SSID from every
  /// anchor's offered-list so the corrected credentials get re-offered — the
  /// user-facing fix for a rotated router password (§8.14/§8.15).
  Future<void> _clearOfferedSsidAcrossAnchors(String ssid) async {
    for (final a in BluetoothService().anchors) {
      if (a.offeredSsids.contains(ssid)) {
        final offered = List<String>.from(a.offeredSsids)..remove(ssid);
        await BluetoothService()
            .addOrUpdateDevice(a.copyWith(offeredSsids: offered));
      }
    }
  }

  // ── Saved WiFi networks (§8.15) ─────────────────────────────────────────────

  /// True once at least one watch or anchor is paired. The empty-networks
  /// startup warning (§8.15) is gated on this — a "just exploring" user with no
  /// hardware has nothing that needs a network.
  bool get hasHardware => BluetoothService().deviceHistory.isNotEmpty;

  /// Whether to show the empty-list startup warning this launch (§8.15): only
  /// with hardware present, an empty list, and not yet dismissed this launch.
  bool get shouldWarnNoNetworks =>
      hasHardware && savedNetworks.isEmpty && !emptyNetworksWarningDismissed;

  void dismissEmptyNetworksWarning() {
    emptyNetworksWarningDismissed = true;
    notifyListeners();
  }

  /// Push every saved network to the watch over `…0011` (§8.15/§8.16), advancing
  /// the watch's acked networks revision on success. This is also a
  /// *repair-capability* update — the watch can only offer what it holds
  /// (firmware §5.5.3). Best-effort; `…0011` is Write-No-Response, so a
  /// completed write (no exception) is the best ack the transport offers.
  Future<bool> pushSavedNetworksToWatch() async {
    if (!_watch.isConnected) return false;
    try {
      for (final n in savedNetworks.networks) {
        await _watch.pushWifiCredentials(n.ssid, n.password);
      }
      final id = watchDeviceId;
      if (id != null) await syncStore.setAcked(id, SyncClass.watchNetworks);
      return true;
    } catch (_) {
      return false; // leaves the watch stale/yellow; retried opportunistically
    }
  }

  Future<bool> addOrUpdateNetwork(String ssid, String password) async {
    final ok = await savedNetworks.addOrUpdate(ssid, password);
    if (ok) {
      // A corrected/new password for this SSID should be re-offered to any
      // anchor that previously failed on it (§8.14 rotated-password fix).
      await _clearOfferedSsidAcrossAnchors(ssid.trim());
      await syncStore.bump(SyncClass.watchNetworks);
      await attemptWatchSync(allowScan: true);
      notifyListeners();
    }
    return ok;
  }

  Future<bool> renameNetwork(
      String oldSsid, String newSsid, String password) async {
    final ok = await savedNetworks.rename(oldSsid, newSsid, password);
    if (ok) {
      await _clearOfferedSsidAcrossAnchors(oldSsid);
      await _clearOfferedSsidAcrossAnchors(newSsid.trim());
      await syncStore.bump(SyncClass.watchNetworks);
      await attemptWatchSync(allowScan: true);
      notifyListeners();
    }
    return ok;
  }

  Future<void> removeNetwork(String ssid) async {
    await savedNetworks.remove(ssid);
    // Deleting stops the watch offering it going forward; re-push the (shorter)
    // list so the watch's held set reflects the app (§8.15 honest wording — it
    // can't retract creds already stored on a device).
    await syncStore.bump(SyncClass.watchNetworks);
    await attemptWatchSync(allowScan: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}

/// Convenience factory for tests / bootstrap.
Future<AppState> bootstrapAppState({AppDatabase? db}) async {
  final database = db ?? AppDatabase();
  final state = AppState(integrityStore: IntegrityStore(database));
  await state.initialize();
  return state;
}
