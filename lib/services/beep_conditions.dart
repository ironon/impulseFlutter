// Beep-condition checklists and proximity-interpretation sentences — pure
// functions over the Debug Telemetry v2 models.
//
// WHY THIS IS PURE
// The whole point of the Debug screen is to answer "why is nothing beeping?".
// That answer is decision logic, not painting: it must be unit-testable without
// a phone, a watch or an anchor. So this file imports no Flutter, no BLE and no
// app state — only the decoded wire models.
//
// Each condition is marked from the owner's point of view: `met` means "this
// guard allows the output", `unmet` means "this guard is what is stopping it",
// `unknown` means "the snapshot cannot tell us". A group's verdict is therefore
// the first unmet condition, or `unknown` when nothing has failed but something
// has not been observed. `informational: true` rows are outcomes and
// advisories: displayed, never allowed to drive a group's verdict, because a
// silent anchor whose guards all pass must not report "first failing: beeping
// now".
//
// The three groups mirror the three ways Impulse makes noise on the nRF build
// (contract §3):
//   A. the watch's own motor/buzzer (§3.1, `main.c` / enforcement.c /
//      proximity.c / profiles.c),
//   B. an anchor beeping because the watch was removed, over BLE (§3.2) or over
//      WiFi/UDP (§3.3) — the anchor re-checks every guard itself, so this group
//      combines the watch's evidence with the anchor's,
//   C. an anchor beeping because the phone left its dock — which the nRF
//      firmware has no subsystem for at all (§2.7, §3.4). It is rendered as one
//      honest row, not as a wall of unknowns.

import '../models/debug_telemetry.dart';

// ── Result types ────────────────────────────────────────────────────────────

/// Whether a single guard permits the output.
enum ConditionState { met, unmet, unknown }

extension ConditionStateLabel on ConditionState {
  String get symbol {
    switch (this) {
      case ConditionState.met:     return '✓';
      case ConditionState.unmet:   return '✗';
      case ConditionState.unknown: return '?';
    }
  }

  String get label {
    switch (this) {
      case ConditionState.met:     return 'met';
      case ConditionState.unmet:   return 'not met';
      case ConditionState.unknown: return 'unknown';
    }
  }
}

/// One checklist row: what is required, whether it holds, and one line of why.
class BeepCondition {
  final String label;
  final ConditionState state;
  final String detail;

  /// A status/outcome row ("beeping now", "last command", clock skew): shown in
  /// the checklist but excluded from the group verdict. Without this a silent
  /// anchor whose guards all pass would report "first failing: beeping now",
  /// which is the question restated, not an answer.
  final bool informational;

  const BeepCondition(this.label, this.state, this.detail,
      {this.informational = false});

  BeepCondition asInformational() =>
      BeepCondition(label, state, detail, informational: true);
}

/// A related set of guards plus its overall verdict.
class BeepConditionGroup {
  final String title;
  final String subtitle;
  final List<BeepCondition> conditions;

  const BeepConditionGroup({
    required this.title,
    required this.subtitle,
    required this.conditions,
  });

  /// First failing guard, if any.
  BeepCondition? get firstUnmet {
    for (final c in conditions) {
      if (!c.informational && c.state == ConditionState.unmet) return c;
    }
    return null;
  }

  bool get hasUnknown => conditions
      .any((c) => !c.informational && c.state == ConditionState.unknown);

  /// "would beep now" / "would not, first failing: <label>" / "unknown".
  String get verdict {
    final failed = firstUnmet;
    if (failed != null) {
      return 'would not, first failing: ${failed.label}';
    }
    if (hasUnknown) return 'unknown';
    return 'would beep now';
  }

  ConditionState get state {
    if (firstUnmet != null) return ConditionState.unmet;
    if (hasUnknown) return ConditionState.unknown;
    return ConditionState.met;
  }
}

/// The full report consumed by the Proximity tab.
class BeepReport {
  final List<BeepConditionGroup> groups;

  /// As-of time the report was built (callers pass `now` so tests are stable).
  final DateTime asOf;

  /// Loud, one-line warning that changes the meaning of everything else on the
  /// page. Today that is the identity conflict: the watch is ranging one anchor
  /// while the event names another, so every distance below is about the wrong
  /// box.
  final String? warning;

  const BeepReport({
    required this.groups,
    required this.asOf,
    this.warning,
  });

  BeepConditionGroup get watchGroup => groups[0];
  BeepConditionGroup get anchorRemovedGroup => groups[1];
  BeepConditionGroup get anchorDockGroup => groups[2];
}

// ── Public entry point ──────────────────────────────────────────────────────

/// Evaluate every beep condition for the given snapshots.
///
/// [anchorId] selects which watch AnchorRecord the anchor groups refer to
/// (normally the active event's `anchorId`). Null or missing snapshots never
/// throw: the affected checks become `unknown` with a "not read yet" detail.
BeepReport evaluateBeepConditions({
  WatchDebugTelemetry? watch,
  AnchorDebugTelemetry? anchor,
  String? anchorId,
  DateTime? now,
}) {
  final asOf = now ?? DateTime.now();
  return BeepReport(
    groups: [
      _watchGroup(watch),
      _anchorRemovedGroup(watch, anchor, anchorId),
      _anchorDockGroup(watch, anchor),
    ],
    asOf: asOf,
    warning: _identityWarning(watch),
  );
}

/// The loudest thing this page can say: the distance on screen belongs to a
/// different anchor than the event names (§1.7, §6.2).
String? _identityWarning(WatchDebugTelemetry? w) {
  if (w == null) return null;
  if (w.identityConflict || w.linkPeerKind == LinkPeerKind.otherAnchor) {
    return 'THE WATCH IS RANGING A DIFFERENT ANCHOR THAN THE EVENT NAMES. '
        'Event anchor ${_shortOrNone(w.eventAnchorId)}, ranging peer '
        '${_shortOrNone(w.linkPeerUuid)} — every distance below is about the '
        'wrong box, so the verdict is not evidence.';
  }
  return null;
}

// ── Group A: the watch itself (§3.1) ────────────────────────────────────────

/// Which outputs this build can actually produce for the profile in force.
/// EITHER requested output is enough: a --buzzer build with the motor disabled
/// still buzzes (contract §3.1 guard 1).
({bool motor, bool buzzer, bool any}) _outputs(WatchDebugTelemetry w) {
  final profile = w.profile;
  final needsMotor = profile?.includesMotor ?? true;
  final needsBuzzer = profile?.includesBuzzer ?? true;
  final motor = needsMotor && !w.motorCompiledOut;
  final buzzer = needsBuzzer && !w.buzzerCompiledOut;
  return (motor: motor, buzzer: buzzer, any: motor || buzzer);
}

BeepConditionGroup _watchGroup(WatchDebugTelemetry? w) {
  const title = 'Watch buzzes / vibrates';
  const subtitle = 'Every guard below must hold for motor/buzzer output '
      '(contract §3.1).';
  if (w == null) {
    return _unknownGroup(title, subtitle, const [
      'build can produce this output',
      'a window is being enforced',
      'an event is active with a known criterion',
      'the profile\'s mode includes an output',
      'not in donning grace',
      'a poll has concluded',
      'the criterion is not met',
      'output is not silenced by the lost-link grace',
    ]);
  }

  final profile = w.profile;
  final outputs = _outputs(w);
  final needsMotor = profile?.includesMotor ?? true;
  final needsBuzzer = profile?.includesBuzzer ?? true;
  final outputAvailable = outputs.any;
  final motorBlocks = needsMotor && w.motorCompiledOut && !outputs.buzzer;
  final buzzerBlocks = needsBuzzer && w.buzzerCompiledOut && !outputs.motor;

  final reading = readCriterion(w);
  final polled = w.lastPollMet != null;

  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      BeepCondition(
        'build can produce this output',
        outputAvailable ? ConditionState.met : ConditionState.unmet,
        _buildDetail(w, needsMotor, needsBuzzer),
      ),
      BeepCondition(
        'buzzer compiled out',
        w.buzzerCompiledOut ? ConditionState.unmet : ConditionState.met,
        w.buzzerCompiledOut
            ? 'CONFIG_IMPULSE_BUZZER_DISABLED=y — the default on both roles, '
                'so this build cannot beep at all'
            : 'buzzer is compiled in',
        informational: !buzzerBlocks,
      ),
      BeepCondition(
        'motor compiled out',
        w.motorCompiledOut ? ConditionState.unmet : ConditionState.met,
        w.motorCompiledOut
            ? 'CONFIG_IMPULSE_MOTOR_DISABLED=y — bench-only build, it cannot '
                'vibrate'
            : 'motor is compiled in',
        informational: !motorBlocks,
      ),
      BeepCondition(
        'a window is being enforced',
        w.activityState == DebugActivityState.enforcement
            ? ConditionState.met
            : ConditionState.unmet,
        'activity_state = ${w.activityState.label}',
      ),
      BeepCondition(
        'an event is active with a known criterion',
        w.criteria != null ? ConditionState.met : ConditionState.unmet,
        w.criteria == null
            ? 'no active event (criteria = none)'
            : '${w.criteria!.label} ${_fmtMinute(w.eventStartMin)}–'
                '${_fmtMinute(w.eventEndMin)} · profile ${w.profileLabel}',
      ),
      BeepCondition(
        'the profile\'s mode includes an output',
        profile == null
            ? ConditionState.unknown
            : ConditionState.met,
        profile == null
            ? 'no profile in force'
            : 'profile ${profile.label} → '
                '${[
                  if (profile.includesMotor) 'motor',
                  if (profile.includesBuzzer) 'buzzer',
                ].join(' + ')}',
      ),
      BeepCondition(
        'not in donning grace',
        w.graceActive ? ConditionState.unmet : ConditionState.met,
        w.graceActive
            ? 'grace active · ${w.graceRemainingS}s remaining '
                '(grace short-circuits every criterion to met)'
            : 'no grace (donning_grace_s = ${w.donningGraceS}s)',
      ),
      BeepCondition(
        'a poll has concluded',
        !polled
            ? ConditionState.unknown
            : ConditionState.met,
        !polled
            ? 'no poll since window entry — the first one runs on the next '
                'loop pass (~100 ms), and until it does condition_met is the '
                'optimistic startup value, not a verdict'
            : 'last poll ${_fmtAge(w.sinceLastPollS)} · cadence '
                '${w.pollIntervalS}s · result ${w.lastPollMet!.label}',
      ),
      BeepCondition(
        'the criterion is not met',
        !polled
            ? ConditionState.unknown
            : (w.conditionMet ? ConditionState.unmet : ConditionState.met),
        '${w.conditionMet ? 'condition_met = 1 (compliant)' : 'condition_met = 0 (evaluating as violated)'}'
        ' · ${reading.explanation}',
      ),
      BeepCondition(
        'verdict path (last_decision)',
        informational: true,
        w.lastDecision == null
            ? ConditionState.unknown
            : (w.lastDecision!.met == true
                ? ConditionState.met
                : ConditionState.unmet),
        w.lastDecision == null
            ? 'no decision recorded yet'
            : w.lastDecision!.label,
      ),
      BeepCondition(
        'abstention fail-safe',
        informational: true,
        w.failsafe ? ConditionState.met : ConditionState.unmet,
        w.failsafe
            ? 'failsafe set: ${w.abstainRun} consecutive abstentions > 5 — '
                'STAY_NEAR fails closed (not met), GET_AWAY fails open (met). '
                'The verdict is a rule now, not evidence'
            : '${w.abstainRun} consecutive abstention(s); fail-safe fires above 5',
      ),
      BeepCondition(
        'lost link concluded AWAY',
        informational: true,
        w.verdictFromLostLink ? ConditionState.met : ConditionState.unmet,
        w.verdictFromLostLink
            ? 'AWAY was concluded by silence, not by a measurement'
            : 'the verdict comes from measurements',
      ),
      BeepCondition(
        'output is not silenced by the lost-link grace',
        w.outputSilenced ? ConditionState.unmet : ConditionState.met,
        w.outputSilenced
            ? 'output_silenced: the pins are gated off even though '
                'condition_met is ${w.conditionMet ? '1' : '0'}'
                '${w.graceIsLostLink ? ' (lost-link grace)' : ''}'
            : 'outputs are live',
      ),
      BeepCondition(
        'profile is in an "on" phase',
        informational: true,
        (w.motorOn || w.buzzerOn)
            ? ConditionState.met
            : ConditionState.unmet,
        'motor ${_onOff(w.motorOn)} · buzzer ${_onOff(w.buzzerOn)} right now '
        '· profile_active=${w.profileActive} — profiles alternate on/off '
        'steps, so "off right now" is normal mid-profile',
      ),
      BeepCondition(
        'ring state',
        informational: true,
        w.ringState == null ? ConditionState.unknown : ConditionState.met,
        w.ringState?.label ?? 'unknown',
      ),
    ],
  );
}

String _buildDetail(WatchDebugTelemetry w, bool needsMotor, bool needsBuzzer) {
  final needs = <String>[
    if (needsMotor) 'motor',
    if (needsBuzzer) 'buzzer',
  ];
  final missing = <String>[
    if (needsMotor && w.motorCompiledOut) 'motor',
    if (needsBuzzer && w.buzzerCompiledOut) 'buzzer',
  ];
  if (needs.isEmpty) return 'no output is requested by the profile in force';
  if (missing.isEmpty) return '${needs.join(' + ')} compiled in';
  if (missing.length == needs.length) {
    return 'this build asks for ${needs.join(' + ')} but '
        '${missing.join(' and ')} ${missing.length == 1 ? 'is' : 'are'} '
        'compiled out';
  }
  return '${missing.join(' and ')} compiled out, but the profile also asks '
      'for ${needs.where((n) => !missing.contains(n)).join(' + ')}, which is '
      'compiled in';
}

/// The criterion-specific explanation of *why* the watch is or is not
/// complaining. Public so the tab (and tests) can show the same sentence the
/// checklist uses.
class CriterionReading {
  /// True when the criterion is failing, i.e. the watch should be beeping.
  /// Null when the snapshot cannot decide (no active event, or no poll yet).
  final bool? notMet;

  /// One line of evidence.
  final String explanation;

  const CriterionReading(this.notMet, this.explanation);
}

/// Interpret the current enforcement decision from `last_decision` and the
/// ranging evidence the firmware actually consumed (contract §1.3).
CriterionReading readCriterion(WatchDebugTelemetry w) {
  final c = w.criteria;
  if (c == null) {
    return const CriterionReading(null, 'no active criterion');
  }
  final decision = w.lastDecision;
  if (decision == null || decision == WatchDecision.notEvaluated) {
    return CriterionReading(
      null,
      '${c.label}: ${decision?.label ?? 'no decision recorded yet'}'
      '${w.sinceLastPollS == null ? '' : ' (last poll ${w.sinceLastPollS}s ago)'}',
    );
  }

  // `condition_met` is what settle() wrote and what gates the pins. The branch
  // only says which path produced it; for the lost-link branch the outcome is
  // criterion-dependent, so fall back to condition_met there.
  final met = decision.met ?? w.conditionMet;
  final evidence = _rangingEvidence(w, c);
  final extras = <String>[
    if (w.failsafe)
      'abstain_run ${w.abstainRun} > 5 → fail-safe '
          '(${c == DebugCriteria.stayNear ? 'STAY_NEAR fails closed' : 'GET_AWAY fails open'})',
    if (w.verdictFromLostLink) 'AWAY concluded by the lost link',
    if (w.graceIsLostLink) 'lost-link grace is silencing the output',
  ];
  final suffix = extras.isEmpty ? '' : ' · ${extras.join(' · ')}';
  return CriterionReading(
    !met,
    '${c.label}: $evidence → ${decision.label} → '
    '${met ? 'met' : 'not met'}$suffix',
  );
}

/// "anchor 75b2… measured 1.42 m (NEAR, 2 bursts ≥ near threshold 2.00 m)",
/// or the honest no-measurement equivalent.
String _rangingEvidence(WatchDebugTelemetry w, DebugCriteria c) {
  final r = w.anchorRecord(w.eventAnchorId) ?? w.liveRangedRecord;
  if (r == null) {
    return w.anchors.isEmpty
        ? 'no anchor record in this snapshot'
        : 'no anchor has been ranged';
  }
  final sb = StringBuffer('anchor ${_short(r.anchorUuid)} ');
  final d = r.distanceM;
  if (d != null) {
    sb.write('measured ${d.toStringAsFixed(2)} m (${r.verdict.label}');
    if (r.verdict == ProxVerdict.near && w.nearEnterCm > 0) {
      sb.write(', ${w.nearRun} bursts ≥ near threshold ${_metres(w.nearEnterCm)}');
    } else if (r.verdict == ProxVerdict.away && w.awayEnterCm > 0) {
      sb.write(', ${w.awayRun} bursts ≥ away threshold ${_metres(w.awayEnterCm)}');
    }
    sb.write(')');
  } else {
    sb.write(r.verdict.label);
    if (r.abstainReason != null) sb.write(' (${r.abstainReason!.label})');
  }
  return sb.toString();
}

// ── Group B: an anchor beeping on WATCH_REMOVED (§3.2 / §3.3) ───────────────

BeepConditionGroup _anchorRemovedGroup(
  WatchDebugTelemetry? w,
  AnchorDebugTelemetry? a,
  String? anchorId,
) {
  const title = 'Anchor beeps: watch removed';
  const subtitle = 'WATCH_REMOVED over BLE first, then over WiFi/UDP. The '
      'anchor re-checks every guard itself with the same validator, so the '
      'watch can deliver and still be refused (contract §3.2/§3.3).';
  const labels = [
    'watch unworn',
    'watch is enforcing a window',
    'event has at least one beep anchor',
    'not in donning grace',
    'WATCH_REMOVED was delivered',
    'anchor clock valid',
    'anchor has a schedule',
    'event is in the anchor\'s day plan',
    'window is open by the anchor clock',
    'not negated today',
    'this anchor is in beepAnchors',
    'anchor profile present (a missing one is defaulted)',
    'anchor buzzer is compiled in',
    'alarm was accepted',
    'alarm is inside its cap',
  ];
  if (w == null) {
    return _unknownGroup(
      title,
      subtitle,
      labels,
      detail: 'watch telemetry not read yet',
    );
  }

  final record = w.anchorRecord(anchorId);
  final eventId = w.activeEventId;
  final anchorEvent = a?.eventRecord(eventId);
  final reason = a?.lastCmdReason;

  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      BeepCondition(
        'watch unworn',
        w.worn ? ConditionState.unmet : ConditionState.met,
        w.worn ? 'worn — the watch enforces itself' : 'unworn (removed)',
      ),
      BeepCondition(
        'watch is enforcing a window',
        w.activityState == DebugActivityState.enforcement
            ? ConditionState.met
            : ConditionState.unmet,
        'activity_state = ${w.activityState.label}'
        '${w.criteria == null ? ' · no active event' : ' · ${w.criteria!.label}'}',
      ),
      BeepCondition(
        'event has at least one beep anchor',
        w.beepAnchorCount > 0 ? ConditionState.met : ConditionState.unmet,
        w.beepAnchorCount > 0
            ? '${w.beepAnchorCount} anchor(s) asked to beep'
            : 'beep_anchor_count = 0 — escalation returns without recording '
                'anything',
      ),
      BeepCondition(
        'not in donning grace',
        w.graceActive ? ConditionState.unmet : ConditionState.met,
        w.graceActive
            ? 'grace active · ${w.graceRemainingS}s remaining'
            : 'no grace',
      ),
      _deliveryCondition(w, a),
      _fromAnchor(
        'anchor clock valid',
        a,
        (x) => x.timeValid,
        (x) => x.timeValid
            ? 'anchor clock ${_fmtMinute(x.localMinute)} local · '
                '${x.clockSourceLabel}'
            : 'the anchor\'s clock is invalid (it has no clock source of its '
                'own: nothing has set it since boot), so every window check is '
                'wrong and every WATCH_REMOVED is refused as outside the window',
      ),
      _fromAnchor(
        'anchor has a schedule',
        a,
        (x) => x.scheduleLoaded,
        (x) => x.scheduleLoaded
            ? '${x.scheduleEventCount} event(s) stored, ${x.todayEventCount} today'
            : 'no schedule in RAM — the anchor ignores every command',
      ),
      _anchorDayPlanCondition(eventId, a, anchorEvent, reason),
      _anchorWindowCondition(a, anchorEvent, reason),
      _anchorNegatedCondition(a, anchorEvent, reason),
      _anchorBeepListCondition(a, anchorEvent, reason),
      _anchorProfileCondition(a, anchorEvent, reason),
      _fromAnchor(
        'anchor buzzer is compiled in',
        a,
        (x) => !x.buzzerCompiledOut,
        (x) => x.buzzerCompiledOut
            ? 'CONFIG_IMPULSE_BUZZER_DISABLED=y — the alarm runs with '
                'beeping = 1 and makes no sound; rebuild with --buzzer'
            : 'buzzer is compiled in',
      ),
      _alarmAcceptedCondition(a),
      _alarmCapCondition(a),
      _commandReasonCondition(a),
      _bleCarrierCondition(w),
      _udpCarrierCondition(w, a),
      _clockAgreementCondition(w, a),
      _beepingNowCondition(a),
      if (record != null)
        BeepCondition(
          'watch\'s record for this anchor',
          informational: true,
          record.inBeepList ? ConditionState.met : ConditionState.unmet,
          '${record.distanceLabel} · ${record.verdict.label} · '
          '${record.inBeepList ? 'in the event\'s beepAnchors' : 'NOT in the event\'s beepAnchors'}'
          '${record.isEventAnchor ? ' · is the event anchor' : ''}',
        ),
    ],
  );
}

/// §3.2 guards 5-6 / §3.3 guards 5′-5‴, 6′-6‴: one decision row, because getting
/// the command to the anchor over *either* carrier is enough. The per-carrier
/// evidence is in the two informational rows below it.
///
/// This row is about the CARRIER, not about acceptance: the anchor's shared
/// validator can still refuse a command it received, and that refusal is a
/// different (and much more useful) row. Collapsing the two would make a
/// 9-hour clock error read as "the link never worked".
BeepCondition _deliveryCondition(WatchDebugTelemetry w, AnchorDebugTelemetry? a) {
  const label = 'WATCH_REMOVED was delivered';
  // The anchor's own record of the last command proves the carrier: the shared
  // validator saw those bytes, whichever transport brought them.
  if (a != null && a.lastCmd == AnchorCmd.watchRemoved) {
    final transport = a.lastCmdTransport?.label ?? 'unknown transport';
    final result = a.lastCmdResult?.label ?? 'no result byte';
    final reasonText = a.lastCmdReason?.label ?? 'no reason recorded';
    final age = _fmtAge(a.sinceLastCmdS);
    if (a.lastCmdResult == null) {
      return BeepCondition(
        label,
        ConditionState.unknown,
        'the anchor saw WATCH_REMOVED over $transport, $age, but recorded no '
        'result byte',
      );
    }
    return BeepCondition(
      label,
      ConditionState.met,
      'the anchor received WATCH_REMOVED over $transport, $age → $result · '
      '$reasonText',
    );
  }

  if (w.escLastDeliveredCmd == EscalationCmd.watchRemoved) {
    return BeepCondition(
      label,
      ConditionState.met,
      'the watch handed WATCH_REMOVED to the stack'
      '${w.escDeliveredBle > 0 ? ' (BLE deliveries: ${w.escDeliveredBle})' : ''}'
      '${w.escDeliveredUdp > 0 ? ' (UDP ACKs: ${w.escDeliveredUdp})' : ''}'
      '${a == null ? ' — anchor telemetry not read yet' : ''}',
    );
  }
  if (w.ackRefused && w.escPendingCmd == EscalationCmd.watchRemoved) {
    return BeepCondition(
      label,
      ConditionState.met,
      'the anchor heard WATCH_REMOVED and refused it '
      '(esc_last_ack_result = ${w.escLastAckResult?.label ?? 'unknown'}); '
      'the refusal itself is a guard below',
    );
  }
  if (w.escGaveUp) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'escalation gave up: nothing more will be sent for this window',
    );
  }
  if (w.escPendingCmd == EscalationCmd.watchRemoved) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'WATCH_REMOVED is queued but undelivered'
      '${w.escSinceRequestS == null ? '' : ' for ${w.escSinceRequestS}s'} '
      'and is being re-asserted',
    );
  }
  if (a != null && !a.noCommandYet && a.lastCmd != AnchorCmd.none) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'the anchor\'s last command was ${a.lastCmd.label}, not WATCH_REMOVED',
    );
  }
  return BeepCondition(
    label,
    ConditionState.unknown,
    a == null
        ? 'no delivery evidence yet: the watch has not escalated and anchor '
            'telemetry is not read'
        : 'no delivery evidence yet: the watch has not escalated and the '
            'anchor has seen no command since boot',
  );
}

BeepCondition _bleCarrierCondition(WatchDebugTelemetry w) {
  const label = 'BLE carrier';
  final delivered = w.escLastDeliveredCmd == EscalationCmd.watchRemoved &&
      w.escDeliveredBle > 0;
  final ready = w.linkReady;
  return BeepCondition(
    label,
    informational: true,
    ready || delivered ? ConditionState.met : ConditionState.unmet,
    'link_up=${w.linkUp} link_ready=$ready (ready = link up AND the anchor\'s '
    'watch-state characteristic discovered) · BLE deliveries '
    '${w.escDeliveredBle} · connect attempts ${w.linkConnectAttempts}, '
    'failures ${w.linkConnectFailures}'
    '${w.linkLastDisconnectReason == null ? '' : ' · last disconnect 0x${w.linkLastDisconnectReason!.toRadixString(16).padLeft(2, '0')}'}'
    ' — a BLE write has no per-anchor confirmation, so "delivered" here means '
    'the stack took it',
  );
}

BeepCondition _udpCarrierCondition(WatchDebugTelemetry w, AnchorDebugTelemetry? a) {
  const label = 'WiFi/UDP carrier';
  final carrierUsed = a?.lastCmdTransport == AnchorCmdTransport.udp ||
      w.radioPhase == RadioPhase.wifi;
  final addressed = w.wifiConnected && w.ownIpv4 != null;
  return BeepCondition(
    label,
    informational: true,
    (carrierUsed || addressed) ? ConditionState.met : ConditionState.unmet,
    'radio_phase=${w.radioPhase.label} · wifi_connected=${w.wifiConnected} · '
    'own_ipv4=${w.ownIpv4 ?? 'none'} · wifi_entries=${w.escWifiEntries} · '
    'attempts=${w.escAttempts} · ACKs=${w.escDeliveredUdp} · '
    'last_ack=${w.escLastAckResult?.label ?? 'none'}'
    '${w.escGaveUp ? ' · GAVE UP' : ''}'
    '${a?.lastCmdTransport == AnchorCmdTransport.udp ? ' · the anchor\'s last command came over UDP' : ''}'
    ' — delivery needs an ACK from every anchor in beepAnchors',
  );
}

BeepCondition _alarmAcceptedCondition(AnchorDebugTelemetry? a) {
  const label = 'alarm was accepted';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  final accepted = a.lastCmdAccepted || a.lastCmdResult == AnchorCmdResult.applied;
  if (a.beeping && accepted) {
    return BeepCondition(
      label,
      ConditionState.met,
      'alarm running ${a.beepingForS}s · profile ${a.beepProfileLabel} · '
      'phase ${a.beepPhaseOn ? 'on' : 'off (normal duty-cycle gap)'}',
    );
  }
  if (a.beeping) {
    return BeepCondition(
      label,
      ConditionState.met,
      'an alarm is running (${a.beepingForS}s, profile ${a.beepProfileLabel}) '
      'although the last command was not recorded as accepted',
    );
  }
  return BeepCondition(
    label,
    ConditionState.unmet,
    'not beeping · last result '
    '${a.lastCmdResult?.label ?? 'no command yet'}',
  );
}

BeepCondition _alarmCapCondition(AnchorDebugTelemetry? a) {
  const label = 'alarm is inside its cap';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (!a.beeping) {
    return const BeepCondition(
        label, ConditionState.unmet, 'not beeping, so no cap applies');
  }
  if (a.beepCapExpired) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'beeping ${a.beepingForS}s has reached the ${a.maxBeepMinutes}-minute cap '
      '(${a.maxBeepMinutes * 60}s) — it stops at the cap, which is NOT '
      'persisted across a reboot',
    );
  }
  return BeepCondition(
    label,
    ConditionState.met,
    'beeping ${a.beepingForS}s of the ${a.maxBeepMinutes}m cap · '
    '${a.beepCapRemainingS}s left · stopped by the cap ${a.capStops} time(s) '
    'since boot',
  );
}

/// §2.4: the anchor applies WATCH_WORN unconditionally and tells you exactly why
/// it did anything else.
BeepCondition _commandReasonCondition(AnchorDebugTelemetry? a) {
  const label = 'anchor\'s last command';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (a.noCommandYet || (a.lastCmd == AnchorCmd.none && a.lastCmdReason == null)) {
    return const BeepCondition(
        label, ConditionState.unknown, 'no command since boot');
  }
  final reason = a.lastCmdReason?.label ?? 'no reason recorded';
  final transport = a.lastCmdTransport?.label ?? 'unknown transport';
  final src = a.lastCmdSrcIp == null ? '' : ' from ${a.lastCmdSrcIp}';
  return BeepCondition(
    label,
    informational: true,
    a.lastCmdReason?.accepted == true
        ? ConditionState.met
        : ConditionState.unmet,
    '${a.lastCmd.label} over $transport$src, ${_fmtAge(a.sinceLastCmdS)} → '
    '$reason · result ${a.lastCmdResult?.label ?? 'none'}'
    '${a.ackSent ? ' · ACK sent' : (a.lastCmdTransport == AnchorCmdTransport.udp ? ' · no ACK sent' : '')} · '
    'rejections since boot: unknown event ${a.rejectUnknownEvent}, outside '
    'window ${a.rejectOutsideWindow}, negated ${a.rejectNegated}, not in beep '
    'list ${a.rejectNotInBeepList}, malformed ${a.rejectMalformed} · accepted '
    '${a.acceptedApplied}',
  );
}

/// §3.2 guard 9 / §3.3 guard 9: the event must be in the anchor's OWN day plan.
/// `last_cmd_reason` 5 is the only reason that says it is not.
BeepCondition _anchorDayPlanCondition(
  String? eventId,
  AnchorDebugTelemetry? a,
  AnchorEventRecord? anchorEvent,
  AnchorCmdReason? reason,
) {
  const label = 'event is in the anchor\'s day plan';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (reason == AnchorCmdReason.unknownEvent) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'the anchor does not know event ${_shortOrNone(eventId)} at all — its '
      'schedule differs from the watch\'s (today events: '
      '${a.todayEventCount} of ${a.scheduleEventCount} stored)',
    );
  }
  if (reason == AnchorCmdReason.negated) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'the event is negated today, so it is dropped from the anchor\'s day plan',
    );
  }
  if (anchorEvent != null) {
    return BeepCondition(
      label,
      ConditionState.met,
      'event ${_shortOrNone(eventId)} is one of the anchor\'s '
      '${a.todayEventCount} event(s) today · recurrence '
      '${anchorEvent.recurrence.label}',
    );
  }
  if (eventId == null || eventId.isEmpty) {
    return const BeepCondition(
      label,
      ConditionState.unknown,
      'the watch has no active event to look for',
    );
  }
  // No last-command evidence and the record list is truncated: the event may
  // simply be past the 8-record cap.
  return BeepCondition(
    label,
    ConditionState.unknown,
    'event ${_short(eventId)} is not in the anchor\'s ${a.events.length} '
    'reported event(s); the anchor reports at most 8, so this is not proof',
  );
}

BeepCondition _anchorWindowCondition(
  AnchorDebugTelemetry? a,
  AnchorEventRecord? anchorEvent,
  AnchorCmdReason? reason,
) {
  const label = 'window is open by the anchor clock';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (reason == AnchorCmdReason.outsideWindow) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'the anchor refused it as outside the window on ITS clock'
      '${a.localMinute == null ? '' : ' (local ${_fmtMinute(a.localMinute)}, '
          '${a.timeValid ? 'valid' : 'INVALID'})'} — a clock 9 h slow reads as '
      '"the anchor never beeps"',
    );
  }
  if (anchorEvent != null) {
    return BeepCondition(
      label,
      anchorEvent.windowOpenNow ? ConditionState.met : ConditionState.unmet,
      '${_fmtMinute(anchorEvent.startMin)}–${_fmtMinute(anchorEvent.endMin)} '
      'by the anchor\'s clock${anchorEvent.clockInvalid ? ' · ITS CLOCK WAS INVALID WHEN EVALUATED' : ''}',
    );
  }
  return const BeepCondition(
    label,
    ConditionState.unknown,
    'no per-event evidence from the anchor',
  );
}

BeepCondition _anchorNegatedCondition(
  AnchorDebugTelemetry? a,
  AnchorEventRecord? anchorEvent,
  AnchorCmdReason? reason,
) {
  const label = 'not negated today';
  if (reason == AnchorCmdReason.negated) {
    return const BeepCondition(label, ConditionState.unmet,
        'the event is negated today (emergency pass / edit)');
  }
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (anchorEvent == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'no per-event evidence from the anchor');
  }
  return BeepCondition(
    label,
    anchorEvent.negatedToday ? ConditionState.unmet : ConditionState.met,
    anchorEvent.negatedToday
        ? 'the event is negated today'
        : 'the event is not negated',
  );
}

BeepCondition _anchorBeepListCondition(
  AnchorDebugTelemetry? a,
  AnchorEventRecord? anchorEvent,
  AnchorCmdReason? reason,
) {
  const label = 'this anchor is in beepAnchors';
  if (reason == AnchorCmdReason.notInBeepList) {
    return const BeepCondition(
      label,
      ConditionState.unmet,
      'the anchor does not find itself in the event\'s beepAnchors — compare '
      'this anchor\'s UUID with the event as the PHONE stored it',
    );
  }
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (anchorEvent == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'no per-event evidence from the anchor');
  }
  return BeepCondition(
    label,
    anchorEvent.inBeepList ? ConditionState.met : ConditionState.unmet,
    anchorEvent.inBeepList
        ? 'the anchor sees itself in beepAnchors'
        : 'the anchor does NOT see itself in beepAnchors',
  );
}

BeepCondition _anchorProfileCondition(
  AnchorDebugTelemetry? a,
  AnchorEventRecord? anchorEvent,
  AnchorCmdReason? reason,
) {
  const label = 'anchor profile present (a missing one is defaulted)';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (reason == AnchorCmdReason.profileDefaulted ||
      a.profileDefaulted ||
      (anchorEvent != null && !anchorEvent.hasAnchorProfile)) {
    return const BeepCondition(
      label,
      ConditionState.met,
      'anchorProfile missing or 0xFF → the anchor defaults to MEDIUM. That is '
      'a default, not a rejection',
    );
  }
  if (anchorEvent == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'no per-event evidence from the anchor');
  }
  return BeepCondition(
    label,
    ConditionState.met,
    'anchorProfile present'
    '${a.activeEventAnchorProfile == null ? '' : ' · ${a.activeEventAnchorProfile!.label}'}',
  );
}

/// Compare the watch's local minute with the anchor's. Two clocks hours apart
/// put a WATCH_REMOVED outside its window at any time of day, which looks
/// exactly like "the anchor ignored us".
BeepCondition _clockAgreementCondition(
    WatchDebugTelemetry w, AnchorDebugTelemetry? a) {
  const label = 'clocks agree (≤ 1 min)';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (!a.timeValid || a.localMinute == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor clock is not valid');
  }
  final watchMinute = w.localMinute;
  if (!w.timeValid || watchMinute == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'watch clock is not valid');
  }
  final skew = _circularMinuteDiff(watchMinute, a.localMinute!);
  final hours = skew ~/ 60;
  final minutes = skew % 60;
  final apart = hours > 0 ? '$hours h $minutes min' : '$minutes min';
  return BeepCondition(
    label,
    informational: true,
    skew <= 1 ? ConditionState.met : ConditionState.unmet,
    'watch ${_fmtMinute(watchMinute)} '
    '(${w.clockSource?.label ?? 'source not reported'}) '
    'vs anchor ${_fmtMinute(a.localMinute)} (${a.clockSourceLabel}) — '
    '${skew == 0 ? 'in sync' : '$apart apart'}'
    '${skew > 1 ? '. ANCHOR CLOCK INVALID OR DISAGREES WITH THE WATCH: a '
        'WATCH_REMOVED can land on the wrong side of the window' : ''}',
  );
}

BeepCondition _beepingNowCondition(AnchorDebugTelemetry? a) {
  const label = 'beeping now';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (!a.beeping) {
    return const BeepCondition(label, ConditionState.unmet, 'not beeping',
        informational: true);
  }
  return BeepCondition(
    label,
    informational: true,
    ConditionState.met,
    'beeping ${a.beepingForS}s · profile ${a.beepProfileLabel} · phase '
    '${a.beepPhaseOn ? 'on' : 'off (normal duty-cycle gap)'}'
    '${a.alarmEventId.isEmpty ? '' : ' · event ${_short(a.alarmEventId)}'}',
  );
}

// ── Group C: an anchor beeping on a dock violation (§2.7 / §3.4) ────────────

BeepConditionGroup _anchorDockGroup(
  WatchDebugTelemetry? w,
  AnchorDebugTelemetry? a,
) {
  const title = 'Anchor beeps: phone left the dock';
  const subtitle = 'phoneAway / dock alarm. This firmware has no dock '
      'subsystem on either role (contract §2.7, §3.4).';
  if (a == null) {
    return const BeepConditionGroup(
      title: title,
      subtitle: subtitle,
      conditions: [
        BeepCondition(
          'not supported by this firmware',
          ConditionState.unknown,
          'anchor telemetry not read yet — dock_supported cannot be checked',
        ),
      ],
    );
  }

  if (!a.dockSupported) {
    return const BeepConditionGroup(
      title: title,
      subtitle: subtitle,
      conditions: [
        BeepCondition(
          'not supported by this firmware',
          ConditionState.unmet,
          'dock_supported = 0: there is no dock state, no dock register poll '
          'and no dock alarm on the nRF anchor — ~000d returns a literal '
          '{0x00, 0x00}. PHONE_AWAY therefore degenerates to the ranging '
          'verdict on the watch (criteria = PHONE_AWAY, last_decision 13-16), '
          'not a dock alarm',
        ),
      ],
    );
  }

  // Unreachable with today's firmware (dock_supported is a constant 0), but
  // written so a future dock subsystem does not silently inherit a wrong page.
  final dockEvent = a.dockEventRecord(w?.activeEventId);
  final windowOpen = dockEvent != null &&
      dockEvent.windowOpenNow &&
      !dockEvent.negatedToday;
  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      BeepCondition(
        'anchor clock valid',
        a.timeValid ? ConditionState.met : ConditionState.unmet,
        a.timeValid
            ? 'anchor clock ${_fmtMinute(a.localMinute)} local · '
                '${a.clockSourceLabel}'
            : 'the anchor clock is invalid — the dock window cannot be '
                'evaluated',
      ),
      dockEvent == null
          ? const BeepCondition(
              'dock window open',
              ConditionState.unmet,
              'no phoneAway event names this anchor today',
            )
          : BeepCondition(
              'dock window open',
              windowOpen ? ConditionState.met : ConditionState.unmet,
              '${_fmtMinute(dockEvent.startMin)}–'
              '${_fmtMinute(dockEvent.endMin)}'
              '${dockEvent.negatedToday ? ' · negated today' : ''} · '
              'window_open_now=${dockEvent.windowOpenNow}',
            ),
      BeepCondition(
        'phone currently undocked',
        a.dockState == DockState.undocked
            ? ConditionState.met
            : (a.dockState == DockState.docked
                ? ConditionState.unmet
                : ConditionState.unknown),
        'dock_state = ${a.dockState?.label ?? 'not supported'}',
      ),
      BeepCondition(
        'dock alarm sounding',
        informational: true,
        a.beeping ? ConditionState.met : ConditionState.unmet,
        a.beeping
            ? 'an alarm is running (${a.beepingForS}s)'
            : 'not beeping',
      ),
    ],
  );
}

// ── Sentence builder for the Proximity decision card ────────────────────────

/// Plain-English reading of the current enforcement decision, e.g.
/// "GET_AWAY: anchor 75b2… measured 1.42 m (NEAR, 2 bursts ≥ near threshold
/// 2.00 m) → not met → watch is buzzing". Pure so the same sentence can be
/// asserted in tests.
///
/// It always states the identity verdict, because a distance from the wrong
/// anchor is the failure this page exists to expose (§1.7).
String buildProximityInterpretation(WatchDebugTelemetry? w) {
  if (w == null) {
    return 'No watch snapshot yet — connect the watch and read …001D.';
  }
  final identity = _identitySentence(w);
  final c = w.criteria;
  if (c == null) {
    return 'No active window: activity ${w.activityState.label}, no criterion '
        'in force, so the watch has nothing to enforce. $identity';
  }

  final reading = readCriterion(w);
  final met = reading.notMet == null ? null : !reading.notMet!;
  final outcome = _outputSentence(w, met);
  final branch = w.lastDecision == null
      ? ''
      : ' · branch: ${w.lastDecision!.label}';
  return '${reading.explanation} → $outcome$branch. $identity';
}

String _outputSentence(WatchDebugTelemetry w, bool? met) {
  if (w.conditionMet && w.outputSilenced) {
    return 'watch silent (output silenced by the lost-link grace)';
  }
  if (w.conditionMet) return 'watch silent';
  if (w.outputSilenced) return 'watch should sound but the output is silenced';
  if (!_outputs(w).any) {
    return 'watch cannot sound at all — the outputs its profile asks for are '
        'compiled out';
  }
  if (w.motorOn || w.buzzerOn) {
    if (w.buzzerCompiledOut && w.motorOn) {
      return 'watch is vibrating (buzzer compiled out)';
    }
    if (w.motorCompiledOut && w.buzzerOn) {
      return 'watch is buzzing (motor compiled out)';
    }
    return 'watch is buzzing';
  }
  if (met == false) {
    return 'watch should be sounding but the profile is in an off phase';
  }
  return 'watch is not sounding';
}

String _identitySentence(WatchDebugTelemetry w) {
  if (w.identityConflict || w.linkPeerKind == LinkPeerKind.otherAnchor) {
    return 'THE WATCH IS RANGING A DIFFERENT ANCHOR THAN THE EVENT NAMES '
        '(event ${_shortOrNone(w.eventAnchorId)}, ranging peer '
        '${_shortOrNone(w.linkPeerUuid)}) — the distance is about the wrong '
        'box.';
  }
  switch (w.linkPeerKind.raw) {
    case 0:
      return 'The watch cannot tell which anchor it is ranging (identity '
          'unknown), so the peer may not be the event\'s anchor.';
    case 1:
      return 'Ranging peer is the event\'s anchor (${_shortOrNone(w.linkPeerUuid)}).';
  }
  return 'Ranging peer identity is not reported by this build.';
}

// ── Helpers ─────────────────────────────────────────────────────────────────

BeepConditionGroup _unknownGroup(
  String title,
  String subtitle,
  List<String> labels, {
  String detail = 'not read yet',
}) {
  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      for (final label in labels)
        BeepCondition(label, ConditionState.unknown, detail),
    ],
  );
}

BeepCondition _fromAnchor(
  String label,
  AnchorDebugTelemetry? a,
  bool Function(AnchorDebugTelemetry) test,
  String Function(AnchorDebugTelemetry) describe,
) {
  if (a == null) {
    return BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  return BeepCondition(
      label, test(a) ? ConditionState.met : ConditionState.unmet, describe(a));
}

String _fmtMinute(int? m) {
  if (m == null) return 'never';
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

String _fmtAge(int? seconds) =>
    seconds == null ? 'never' : '${seconds}s ago';

String _metres(int cm) => '${(cm / 100).toStringAsFixed(2)} m';

String _short(String uuid) =>
    uuid.length <= 8 ? uuid : uuid.substring(0, 8);

String _shortOrNone(String? uuid) =>
    (uuid == null || uuid.isEmpty) ? 'none' : _short(uuid);

String _onOff(bool on) => on ? 'on' : 'off';

/// Smallest circular distance between two minutes-of-day.
int _circularMinuteDiff(int a, int b) {
  final d = (a - b).abs() % 1440;
  return d > 720 ? 1440 - d : d;
}
