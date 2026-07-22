import 'dart:convert';

import '../models/automation_model.dart';
import 'integrity_store.dart';
import 'self_binding_policy.dart';
import 'settle_state_store.dart';

/// The outcome of a proposed edit: what the diff gate decided, why, and — when
/// quarantined — the earliest it may take effect ("no earlier than").
class EditOutcome {
  final GateDecision decision;
  final ChangeClassification classification;
  final DateTime? applyAfter;
  const EditOutcome(this.decision, this.classification, {this.applyAfter});

  bool get queued => decision == GateDecision.quarantine;
}

/// Result of spending an emergency pass (§8.10).
class PassSpendResult {
  final bool success;
  final int remaining;

  /// True when the spend was accepted locally but the watch was unreachable, so
  /// it's **held pending** and will apply the moment the watch is back in range
  /// (§8.10). Enforcement may continue until then — surface this honestly.
  final bool pending;

  const PassSpendResult({
    required this.success,
    required this.remaining,
    this.pending = false,
  });
}

/// Ties the self-binding policy (§8.9) and emergency passes (§8.10) to concrete
/// schedule edits. It is the interim enforcement layer + permanent preview
/// mirror; the watch's verdict (push responses `0x03`/`0x04`, char `…001A`)
/// remains authoritative where present.
class CommitmentPolicyService {
  CommitmentPolicyService({
    required this.integrity,
    required this.settleStore,
    SelfBindingConfig config = const SelfBindingConfig(),
    int passAllowance = 2,
    DateTime Function()? clock,
  })  : _config = config,
        _passAllowance = passAllowance,
        _now = clock ?? DateTime.now;

  final IntegrityStore integrity;
  final SettleStateStore settleStore;
  SelfBindingConfig _config;
  int _passAllowance;
  final DateTime Function() _now;

  SelfBindingConfig get config => _config;
  int get passAllowance => _passAllowance;
  SelfBindingPolicy get _policy => SelfBindingPolicy(_config);

  // ── Previews (no side effects) ────────────────────────────────────────────

  /// Preview an edit without applying it — powers the retarget UX
  /// ("this will queue until Thursday 9am").
  EditOutcome previewEdit(Automation from, Automation to) {
    final now = _now();
    final decision = _policy.decideEdit(
      from: from,
      to: to,
      settle: settleStore.stateFor(from.id),
      now: now,
    );
    final cls = _policy.classifyEdit(from, to);
    return EditOutcome(
      decision,
      cls,
      applyAfter:
          decision == GateDecision.quarantine ? _policy.applyAfter(now) : null,
    );
  }

  EditOutcome previewDelete(Automation event) {
    final now = _now();
    final decision = _policy.decideDelete(
      event: event,
      settle: settleStore.stateFor(event.id),
      now: now,
    );
    return EditOutcome(
      decision,
      ChangeClassification.loosening,
      applyAfter:
          decision == GateDecision.quarantine ? _policy.applyAfter(now) : null,
    );
  }

  // ── Apply (with side effects on the trust stores) ─────────────────────────

  /// Apply an edit. On immediate application, callers should persist [to] as
  /// the active event and push the schedule. On quarantine, callers keep the
  /// pre-edit [from] active and surface the pending state; the queued entry
  /// promotes at the first push opportunity after the delay.
  Future<EditOutcome> applyEdit(Automation from, Automation to) async {
    final now = _now();
    final outcome = previewEdit(from, to);
    if (outcome.decision == GateDecision.applyImmediately) {
      // A newer accepted change cancels any prior pending loosening (§9.3).
      await integrity.cancelPendingForEvent(from.id, now,
          reason: 'a newer edit was applied');
      await settleStore.recordEdit(to.id, now);
      if (outcome.classification == ChangeClassification.tightening) {
        await integrity.audit(
          category: 'tightening_applied',
          eventUuid: to.id,
          detail: 'Tightened immediately',
          now: now,
        );
      }
    } else {
      await integrity.queueLoosening(
        eventUuid: from.id,
        changeType: PendingChangeType.eventModify,
        proposedStateJson: jsonEncode(to.toJson()),
        description: 'Eased "${to.criteria.label}" commitment',
        now: now,
        delay: _config.loosenDelay,
      );
    }
    return outcome;
  }

  /// Register a brand-new commitment (always a tightening — you can always add).
  Future<void> applyCreate(Automation event) async {
    await settleStore.recordCreate(event.id, _now());
  }

  /// Apply a deletion. Immediate deletions remove the event; quarantined ones
  /// queue a deletion marker and keep enforcing until promotion.
  Future<EditOutcome> applyDelete(Automation event) async {
    final now = _now();
    final outcome = previewDelete(event);
    if (outcome.decision == GateDecision.applyImmediately) {
      await integrity.cancelPendingForEvent(event.id, now);
      await settleStore.remove(event.id);
    } else {
      await integrity.queueLoosening(
        eventUuid: event.id,
        changeType: PendingChangeType.eventDelete,
        proposedStateJson: jsonEncode({'deleted': true, 'id': event.id}),
        description: 'Remove commitment',
        now: now,
        delay: _config.loosenDelay,
      );
    }
    return outcome;
  }

  /// Diff a template's regenerated block set against the old set (§2A / §8.9
  /// item 3). Blocks that persist reuse their UUIDs (UUID stability); each
  /// change runs through the same gate. Returns per-block outcomes.
  Future<Map<String, EditOutcome>> applyBlockSet(
      List<Automation> oldBlocks, List<Automation> newBlocks) async {
    final result = <String, EditOutcome>{};
    final oldById = {for (final b in oldBlocks) b.id: b};
    final newById = {for (final b in newBlocks) b.id: b};

    for (final entry in newById.entries) {
      final old = oldById[entry.key];
      if (old == null) {
        await applyCreate(entry.value);
        result[entry.key] =
            const EditOutcome(GateDecision.applyImmediately,
                ChangeClassification.tightening);
      } else {
        result[entry.key] = await applyEdit(old, entry.value);
      }
    }
    for (final entry in oldById.entries) {
      if (!newById.containsKey(entry.key)) {
        result[entry.key] = await applyDelete(entry.value);
      }
    }
    return result;
  }

  // ── Emergency passes (§8.10) ──────────────────────────────────────────────

  Future<int> remainingPasses() async {
    final spent = await integrity.passesSpentInWindow(_now());
    final remaining = _passAllowance - spent;
    return remaining < 0 ? 0 : remaining;
  }

  /// Spend a pass on [event] for [date]. Spendable anytime, including active
  /// windows (§8.10). Immediate: a spend on an active window requires the
  /// caller to re-push the one-off negate. Returns success + remaining.
  Future<PassSpendResult> spendPass(Automation event, DateTime date) async {
    final now = _now();
    final remaining = await remainingPasses();
    if (remaining <= 0) {
      return PassSpendResult(success: false, remaining: 0);
    }
    final yyyymmdd = date.year * 10000 + date.month * 100 + date.day;
    await integrity.recordPassSpend(
      eventUuid: event.id,
      forDateYyyymmdd: yyyymmdd,
      now: now,
    );
    return PassSpendResult(success: true, remaining: remaining - 1);
  }

  /// Change the rolling allowance. Raising it is a loosening gated 24h (§8.10);
  /// lowering it applies immediately. Returns the immediately-effective value.
  Future<int> changeAllowance(int newAllowance) async {
    final now = _now();
    if (newAllowance <= _passAllowance) {
      final old = _passAllowance;
      _passAllowance = newAllowance;
      await integrity.audit(
        category: 'pass_allowance_changed',
        detail: 'Allowance lowered $old→$newAllowance (immediate)',
        now: now,
      );
      return _passAllowance;
    }
    // Raise: quarantine as a setting-type loosening; effective value unchanged.
    await integrity.queueLoosening(
      eventUuid: 'settings:pass_allowance',
      changeType: PendingChangeType.setting,
      proposedStateJson: jsonEncode({'pass_allowance': newAllowance}),
      description: 'Raise emergency-pass allowance to $newAllowance',
      now: now,
      delay: _config.loosenDelay,
    );
    return _passAllowance;
  }

  /// Apply a promoted setting-type pending entry (the promotion path calls
  /// this once the delay elapses — not a user-facing setter).
  Future<void> applyPromotedSetting(Map<String, dynamic> proposed) async {
    final now = _now();
    if (proposed.containsKey('pass_allowance')) {
      _passAllowance = proposed['pass_allowance'] as int;
      await integrity.audit(
        category: 'pass_allowance_changed',
        detail: 'Allowance raise to $_passAllowance took effect',
        now: now,
      );
    }
    if (proposed.containsKey('settle_window_min')) {
      _config = _config.withSettleMinutes(proposed['settle_window_min'] as int);
      await integrity.audit(
        category: 'settle_window_changed',
        detail:
            'Free-edit window change to ${_config.settleWindow.inMinutes} min took effect',
        now: now,
      );
    }
  }

  /// Restore persisted values on startup (not gated — they already passed the
  /// gate when first changed).
  void restore({int? passAllowance, int? settleWindowMin}) {
    if (passAllowance != null) _passAllowance = passAllowance;
    if (settleWindowMin != null) {
      _config = _config.withSettleMinutes(settleWindowMin);
    }
  }

  /// Change the settle window. Shrinking is immediate; growing is a loosening
  /// gated 24h (§8.9 item 4). Value clamped to [30, 240].
  Future<SelfBindingConfig> changeSettleWindow(int minutes) async {
    final now = _now();
    final clamped = minutes.clamp(
        SelfBindingConfig.settleFloorMin, SelfBindingConfig.settleCeilMin);
    final current = _config.settleWindow.inMinutes;
    if (clamped <= current) {
      _config = _config.withSettleMinutes(clamped);
      await integrity.audit(
        category: 'settle_window_changed',
        detail: 'Settle window shortened $current→$clamped min (immediate)',
        now: now,
      );
    } else {
      await integrity.queueLoosening(
        eventUuid: 'settings:settle_window',
        changeType: PendingChangeType.setting,
        proposedStateJson: jsonEncode({'settle_window_min': clamped}),
        description: 'Lengthen the free-edit window to $clamped min',
        now: now,
        delay: _config.loosenDelay,
      );
    }
    return _config;
  }
}
