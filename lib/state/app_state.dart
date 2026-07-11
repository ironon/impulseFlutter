import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../services/commitment_policy_service.dart';
import '../services/integrity_store.dart';
import '../services/settle_state_store.dart';
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
      notifyListeners();
    });
    _pendingSub = _integrity.watchPendingChanges().listen((rows) {
      _pendingRows = rows;
      notifyListeners();
    });

    // Startup is a push opportunity: settle due events, promote due loosenings.
    await settleStore.settleDue(
        schedule, DateTime.now(), policy.config.settleWindow);
    await promoteDuePending(pushAfter: false);

    notifyListeners();
  }

  /// Call after any BLE connection state change so widgets re-render. Also a
  /// reconcile point with the watch's authoritative queue.
  void connectionChanged() {
    notifyListeners();
    if (_watch.isConnected) {
      refreshWatchPending();
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
  Future<PassSpendResult> spendPass(Automation event, DateTime date) async {
    if (_watch.isConnected && _watch.hasEmergencyPassCharacteristic) {
      final yyyymmdd = date.year * 10000 + date.month * 100 + date.day;
      final resp = await _watch.spendEmergencyPass(event.id, yyyymmdd);
      if (resp != null) {
        final ok = resp.resp == 0x01;
        if (ok) {
          // Mirror into the app ledger for the audit/history view.
          await _integrity.recordPassSpend(
            eventUuid: event.id,
            forDateYyyymmdd: yyyymmdd,
            now: DateTime.now(),
            pushed: true,
          );
        }
        notifyListeners();
        return PassSpendResult(
            success: ok,
            remaining: resp.remaining ?? await policy.remainingPasses());
      }
    }
    final result = await policy.spendPass(event, date);
    if (result.success) {
      await pushScheduleToWatch();
    }
    notifyListeners();
    return result;
  }

  Future<int> changePassAllowance(int allowance) async {
    final v = await policy.changeAllowance(allowance);
    await _persistPolicyValues();
    notifyListeners();
    return v;
  }

  Future<void> changeSettleWindow(int minutes) async {
    await policy.changeSettleWindow(minutes);
    await _persistPolicyValues();
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
    if (!_watch.isConnected) return null;
    try {
      final result = await _watch.pushSchedule(await scheduleForPush());
      if (result == ScheduleEndResult.partialQuarantine ||
          result == ScheduleEndResult.rejected) {
        // The watch quarantined/rejected parts — its queue is the truth now.
        await refreshWatchPending();
      }
      return result;
    } catch (_) {
      return ScheduleEndResult.failed;
    }
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
    }
    if (changed && pushAfter) {
      await pushScheduleToWatch();
    }
    if (due.isNotEmpty) notifyListeners();
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
