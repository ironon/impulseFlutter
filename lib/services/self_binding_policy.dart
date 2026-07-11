import '../models/automation_model.dart';

/// Tunables for the self-binding delay (§8.9 / firmware §9.10). The settle
/// window is user-configurable within [30, 240] minutes (clamped); the 24h
/// values are fixed documented defaults.
class SelfBindingConfig {
  final Duration settleWindow;
  final Duration loosenDelay;
  final Duration loosenFreeHorizon;

  const SelfBindingConfig({
    this.settleWindow = const Duration(minutes: 120),
    this.loosenDelay = const Duration(hours: 24),
    this.loosenFreeHorizon = const Duration(hours: 24),
  });

  static const int settleFloorMin = 30;
  static const int settleCeilMin = 240;

  SelfBindingConfig withSettleMinutes(int minutes) => SelfBindingConfig(
        settleWindow:
            Duration(minutes: minutes.clamp(settleFloorMin, settleCeilMin)),
        loosenDelay: loosenDelay,
        loosenFreeHorizon: loosenFreeHorizon,
      );
}

/// Canonical three-way classification (firmware §9.1). Non-comparable is
/// treated as loosening for gating (conservative), but preserved for previews.
enum ChangeClassification { noChange, tightening, loosening, nonComparable }

extension ChangeClassificationX on ChangeClassification {
  /// The binary gating verdict: only a pure tightening applies immediately.
  bool get bindsAtLeastAsHard =>
      this == ChangeClassification.tightening ||
      this == ChangeClassification.noChange;
}

/// What the diff gate decides for a single changed event.
enum GateDecision { applyImmediately, quarantine }

/// Partial-order comparison result for one dimension.
enum PartialCmp { greater, less, equal, incomparable }

/// Per-event settle state (mirror of firmware §9.2: `last_edit` + baseline).
class SettleState {
  /// Wall-clock time of the last accepted edit to this event.
  final DateTime lastEdit;

  /// Snapshot taken at the most recent settle; null if never settled.
  final Automation? settledBaseline;

  const SettleState({required this.lastEdit, this.settledBaseline});

  /// True once [settleWindow] has elapsed since the last edit.
  bool isSettled(DateTime now, Duration settleWindow) =>
      !now.isBefore(lastEdit.add(settleWindow));
}

/// Interim enforcement + permanent preview mirror of the on-watch diff gate
/// (§8.9, firmware §9). Pure, deterministic, and identical to the firmware
/// classification so app previews match the watch's verdicts.
class SelfBindingPolicy {
  const SelfBindingPolicy(this.config);
  final SelfBindingConfig config;

  // ── EnforcementProfile partial order (firmware §9.1) ──────────────────────

  /// Strictness rank: strict > normal > loose.
  static int _strictnessRank(EnforcementProfile p) {
    switch (p) {
      case EnforcementProfile.strictSilent:
      case EnforcementProfile.strictBuzz:
      case EnforcementProfile.strictBoth:
        return 2;
      case EnforcementProfile.normalSilent:
      case EnforcementProfile.normalBuzz:
      case EnforcementProfile.normalBoth:
        return 1;
      case EnforcementProfile.looseSilent:
      case EnforcementProfile.looseBuzz:
      case EnforcementProfile.looseBoth:
        return 0;
    }
  }

  /// Output channel: 0 = silent, 1 = buzz, 2 = both. `both` dominates buzz and
  /// silent; buzz vs silent are non-comparable.
  static int _outputKind(EnforcementProfile p) {
    switch (p) {
      case EnforcementProfile.strictSilent:
      case EnforcementProfile.normalSilent:
      case EnforcementProfile.looseSilent:
        return 0; // silent
      case EnforcementProfile.strictBuzz:
      case EnforcementProfile.normalBuzz:
      case EnforcementProfile.looseBuzz:
        return 1; // buzz
      case EnforcementProfile.strictBoth:
      case EnforcementProfile.normalBoth:
      case EnforcementProfile.looseBoth:
        return 2; // both
    }
  }

  static PartialCmp _outputCmp(EnforcementProfile a, EnforcementProfile b) {
    final oa = _outputKind(a), ob = _outputKind(b);
    if (oa == ob) return PartialCmp.equal;
    if (oa == 2) return PartialCmp.greater; // both dominates
    if (ob == 2) return PartialCmp.less;
    return PartialCmp.incomparable; // buzz vs silent
  }

  static ChangeClassification classifyProfile(
      EnforcementProfile from, EnforcementProfile to) {
    if (from == to) return ChangeClassification.noChange;
    final sCmp = _strictnessRank(to).compareTo(_strictnessRank(from));
    final oCmp = _outputCmp(to, from);
    // Tightening: >= in both dimensions, > in at least one.
    final strictnessGe = sCmp >= 0;
    final outputGe = oCmp == PartialCmp.greater || oCmp == PartialCmp.equal;
    final strictnessLe = sCmp <= 0;
    final outputLe = oCmp == PartialCmp.less || oCmp == PartialCmp.equal;
    if (strictnessGe && outputGe) return ChangeClassification.tightening;
    if (strictnessLe && outputLe) return ChangeClassification.loosening;
    return ChangeClassification.nonComparable;
  }

  // ── Window (start/end minutes) ────────────────────────────────────────────

  static ChangeClassification classifyWindow(
      int fromStart, int fromEnd, int toStart, int toEnd) {
    if (fromStart == toStart && fromEnd == toEnd) {
      return ChangeClassification.noChange;
    }
    // new ⊇ old: starts earlier and/or ends later (contains old).
    if (toStart <= fromStart && toEnd >= fromEnd) {
      return ChangeClassification.tightening;
    }
    // new ⊆ old.
    if (toStart >= fromStart && toEnd <= fromEnd) {
      return ChangeClassification.loosening;
    }
    return ChangeClassification.nonComparable; // partial shift
  }

  // ── Recurrence (occurrence set) ───────────────────────────────────────────

  static ChangeClassification classifyRecurrence(Automation from, Automation to) {
    final same = from.recurrenceType == to.recurrenceType &&
        from.dayOfWeek == to.dayOfWeek &&
        from.dayOfMonth == to.dayOfMonth &&
        (from.recurrenceType != RecurrenceType.once ||
            _sameDate(from.referenceDate, to.referenceDate));
    if (same) return ChangeClassification.noChange;

    final fD = from.recurrenceType == RecurrenceType.daily;
    final tD = to.recurrenceType == RecurrenceType.daily;
    if (tD && !fD) return ChangeClassification.tightening; // →daily ⊇ old
    if (fD && !tD) return ChangeClassification.loosening; // daily→ ⊆ old
    // Same non-daily type but different day, or cross-type: not comparable.
    return ChangeClassification.nonComparable;
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Set fields (beepAnchors) ──────────────────────────────────────────────

  static ChangeClassification _classifySet(List<String> from, List<String> to) {
    final f = from.toSet(), t = to.toSet();
    if (f.length == t.length && f.containsAll(t)) {
      return ChangeClassification.noChange;
    }
    if (t.containsAll(f)) return ChangeClassification.tightening; // superset
    if (f.containsAll(t)) return ChangeClassification.loosening; // subset
    return ChangeClassification.nonComparable; // overlapping-but-different
  }

  static int _anchorProfileRank(AnchorEnforcementProfile? p) {
    switch (p) {
      case AnchorEnforcementProfile.hard:
        return 2;
      case AnchorEnforcementProfile.medium:
        return 1;
      case AnchorEnforcementProfile.light:
        return 0;
      case null:
        return -1;
    }
  }

  // ── Per-field classifications for a same-UUID edit ────────────────────────

  /// Returns the classification of each changed field. Absent fields = no change.
  Map<String, ChangeClassification> classifyFields(
      Automation from, Automation to) {
    final out = <String, ChangeClassification>{};

    final w = classifyWindow(
        from.startMinutes, from.endMinutes, to.startMinutes, to.endMinutes);
    if (w != ChangeClassification.noChange) out['window'] = w;

    final r = classifyRecurrence(from, to);
    if (r != ChangeClassification.noChange) out['recurrence'] = r;

    final pf = classifyProfile(from.profile, to.profile);
    if (pf != ChangeClassification.noChange) out['profile'] = pf;

    // criteria: any change is non-comparable.
    if (from.criteria != to.criteria) {
      out['criteria'] = ChangeClassification.nonComparable;
    }

    // anchorId / wifiSSID target: any change is non-comparable.
    if (from.anchorId != to.anchorId || from.wifiSSID != to.wifiSSID) {
      out['target'] = ChangeClassification.nonComparable;
    }

    final b = _classifySet(from.beepAnchors, to.beepAnchors);
    if (b != ChangeClassification.noChange) out['beepAnchors'] = b;

    if (from.anchorProfile != to.anchorProfile) {
      final rank = _anchorProfileRank(to.anchorProfile)
          .compareTo(_anchorProfileRank(from.anchorProfile));
      out['anchorProfile'] = rank > 0
          ? ChangeClassification.tightening
          : ChangeClassification.loosening;
    }

    // donningGraceS: decrease = tightening, increase = loosening.
    if (from.donningGraceS != to.donningGraceS) {
      out['donningGraceS'] = to.donningGraceS < from.donningGraceS
          ? ChangeClassification.tightening
          : ChangeClassification.loosening;
    }

    // negate: adding a one-off cancel is loosening; removing it is tightening.
    if (from.negate != to.negate) {
      out['negate'] = to.negate
          ? ChangeClassification.loosening
          : ChangeClassification.tightening;
    }

    return out;
  }

  /// Multi-field rule (firmware §9.1): an edit is tightening only if EVERY
  /// changed field is tightening; a single loosening or non-comparable field
  /// makes the whole change a loosening.
  ChangeClassification classifyEdit(Automation from, Automation to) {
    final fields = classifyFields(from, to);
    if (fields.isEmpty) return ChangeClassification.noChange;
    final allTightening = fields.values
        .every((c) => c == ChangeClassification.tightening);
    return allTightening
        ? ChangeClassification.tightening
        : ChangeClassification.loosening;
  }

  /// True when [candidate] binds at least as hard as [baseline] (the settled
  /// floor, §8.9 item 1): the baseline→candidate edit is a tightening/no-change.
  bool bindsAtLeastAsHard(Automation candidate, Automation baseline) {
    return classifyEdit(baseline, candidate).bindsAtLeastAsHard;
  }

  // ── Activity / horizon helpers ────────────────────────────────────────────

  /// Whether [e] is enforcing right now.
  static bool isActiveNow(Automation e, DateTime now) {
    if (e.negate) return false;
    if (!e.appearsOnDate(now)) return false;
    final mins = now.hour * 60 + now.minute;
    return mins >= e.startMinutes && mins < e.endMinutes;
  }

  /// The next start instant of [e] at or after [now], or null within a horizon.
  static DateTime? nextStart(Automation e, DateTime now,
      {int searchDays = 400}) {
    for (int d = 0; d <= searchDays; d++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
      if (e.appearsOnDate(day)) {
        final start = DateTime(day.year, day.month, day.day)
            .add(Duration(minutes: e.startMinutes));
        if (!start.isBefore(now)) return start;
      }
    }
    return null;
  }

  /// The no-escape exception (firmware §9.3): a loosening of an event that is
  /// NOT active and whose next occurrence is beyond the free horizon applies
  /// immediately; otherwise it is quarantined.
  bool withinProtectedHorizon(Automation e, DateTime now) {
    if (isActiveNow(e, now)) return true;
    final start = nextStart(e, now);
    if (start == null) return false; // never fires again → no escape possible
    return start.difference(now) <= config.loosenFreeHorizon;
  }

  // ── The decision for a single changed event ───────────────────────────────

  /// Decide whether an edit to an existing event applies now or is quarantined.
  /// [settle] is the event's current settle state (null ⇒ brand-new event with
  /// no baseline: fully free).
  GateDecision decideEdit({
    required Automation from,
    required Automation to,
    required SettleState? settle,
    required DateTime now,
  }) {
    final cls = classifyEdit(from, to);
    // Tightenings and no-ops always apply immediately.
    if (cls == ChangeClassification.tightening ||
        cls == ChangeClassification.noChange) {
      return GateDecision.applyImmediately;
    }

    // Unsettled-window handling with the settled-baseline floor.
    final settled = settle == null
        ? false
        : settle.isSettled(now, config.settleWindow);
    if (!settled) {
      final baseline = settle?.settledBaseline;
      if (baseline == null) {
        // Newly created / never settled: everything is free this window.
        return GateDecision.applyImmediately;
      }
      // Free only while still ≥ the settled baseline.
      if (bindsAtLeastAsHard(to, baseline)) {
        return GateDecision.applyImmediately;
      }
      // Below baseline ⇒ fall through to the item-2 delayed-loosening rules.
    }

    // Settled (or below-baseline unsettled) loosening: immediate only if the
    // event is neither active nor starting within the free horizon.
    return withinProtectedHorizon(to, now)
        ? GateDecision.quarantine
        : GateDecision.applyImmediately;
  }

  /// Decide for a brand-new event (always a tightening — you can always add a
  /// commitment) or a deletion (always a loosening).
  GateDecision decideAdd() => GateDecision.applyImmediately;

  GateDecision decideDelete({
    required Automation event,
    required SettleState? settle,
    required DateTime now,
  }) {
    // Deleting a never-settled brand-new event is free.
    final settled =
        settle != null && settle.isSettled(now, config.settleWindow);
    if (!settled && settle?.settledBaseline == null) {
      return GateDecision.applyImmediately;
    }
    return withinProtectedHorizon(event, now)
        ? GateDecision.quarantine
        : GateDecision.applyImmediately;
  }

  /// When a quarantined change may take effect — phrased "no earlier than".
  DateTime applyAfter(DateTime now) => now.add(config.loosenDelay);
}
