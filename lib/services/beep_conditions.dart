// Beep-condition checklists and proximity-interpretation sentences — pure
// functions over the Debug Telemetry models (firmware §5.6 watch, §4.4 anchor).
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
// has not been observed.
//
// The three groups mirror the three ways Impulse makes noise:
//   A. the watch's own motor/buzzer (enforcement poll → condition not met),
//   B. an anchor beeping because the watch was removed (WATCH_REMOVED over UDP),
//   C. an anchor beeping because the phone left its dock (phoneAway, §4.11.1).

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

  /// A status/outcome row ("beeping now", "last UDP accepted", clock skew):
  /// shown in the checklist but excluded from the group verdict. Without this
  /// a silent anchor whose guards all pass would report "first failing:
  /// beeping now", which is the question restated, not an answer.
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

  /// Loud, one-line warning when the watch is a V0_ENABLED test build. In that
  /// build every verdict is forced noncompliant, so the checklists describe a
  /// deliberately broken engine, not the user's situation.
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
/// [anchorId] selects which watch AnchorRecord and anchor event record the
/// anchor groups refer to (normally the active event's `anchorId`). Null or
/// missing snapshots never throw: the affected checks become `unknown` with a
/// "not read yet" detail.
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
    warning: watch?.v0Stub == true
        ? 'V0 STUB build (V0_ENABLED): every proximity verdict is forced '
            'noncompliant. These checklists do not describe real behaviour.'
        : null,
  );
}

// ── Group A: the watch itself ───────────────────────────────────────────────

BeepConditionGroup _watchGroup(WatchDebugTelemetry? w) {
  const title = 'Watch buzzes / vibrates';
  const subtitle = 'Every guard below must hold for motor/buzzer output.';
  if (w == null) {
    return _unknownGroup(title, subtitle, const [
      'paired',
      'clock valid',
      'window active',
      'connectivity gate',
      'not in donning grace',
      'criterion not met',
      'enforcement profile playing',
    ]);
  }

  final reading = readCriterion(w);
  final lastPoll = w.lastPollMet;
  final ConditionState criterionState;
  final String lastPollText;
  if (lastPoll == 0xFF) {
    criterionState = ConditionState.unknown;
    lastPollText = 'last poll: never';
  } else if (lastPoll == 0) {
    criterionState = ConditionState.met;
    lastPollText = 'last poll: not met (enforcing)';
  } else {
    criterionState = ConditionState.unmet;
    lastPollText = 'last poll: met (compliant)';
  }

  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      BeepCondition(
        'paired',
        w.activityState == DebugActivityState.unpaired
            ? ConditionState.unmet
            : ConditionState.met,
        'activity_state = ${w.activityState.label}',
      ),
      BeepCondition(
        'clock valid',
        w.timeValid ? ConditionState.met : ConditionState.unmet,
        w.timeValid
            ? 'time() is set${w.watchLocalTime == null ? '' : ' · '
                '${_fmtClock(w.watchLocalTime!)}'}'
            : 'time() has not been set — windows cannot be evaluated',
      ),
      BeepCondition(
        'window active',
        w.hasActiveEvent ? ConditionState.met : ConditionState.unmet,
        w.criteria == null
            ? 'no active event (criteria = 0xFF)'
            : '${w.criteria!.label} ${_fmtMinute(w.startMin)}–'
                '${_fmtMinute(w.endMin)} · profile ${w.profileLabel}',
      ),
      BeepCondition(
        'connectivity gate',
        w.shouldEnforce ? ConditionState.met : ConditionState.unmet,
        'should_enforce=${w.shouldEnforce} (bt=${w.btConnected}, '
            'wifi=${w.wifiConnected}, disconnected_is_dormant='
            '${w.disconnectedIsDormant}, away_is_dormant=${w.awayIsDormant})',
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
        'criterion not met',
        criterionState,
        '$lastPollText · ${reading.explanation}',
      ),
      BeepCondition(
        'enforcement profile playing',
        informational: true,
        w.profileActive ? ConditionState.met : ConditionState.unmet,
        'profile_active=${w.profileActive} · step ${w.stepIdx}, '
            'cycle ${w.cycleCount} · motor ${_onOff(w.motorOn)}, '
            'buzzer ${_onOff(w.buzzerOn)} right now — profiles alternate '
            'on/off steps, so "off right now" is normal mid-profile',
      ),
    ],
  );
}

/// The criterion-specific explanation of *why* the watch is or is not
/// complaining. Public so the tab (and tests) can show the same sentence the
/// checklist uses.
class CriterionReading {
  /// True when the criterion is failing, i.e. the watch should be beeping.
  /// Null when the snapshot cannot decide (e.g. no active event).
  final bool? notMet;

  /// One line of evidence.
  final String explanation;

  const CriterionReading(this.notMet, this.explanation);
}

/// Interpret the last proximity decision according to the criterion the
/// firmware actually consumes (firmware §5.4/§5.6 interpretation notes).
CriterionReading readCriterion(WatchDebugTelemetry w) {
  final c = w.criteria;
  if (c == null) {
    return const CriterionReading(null, 'no active criterion');
  }
  switch (c) {
    case DebugCriteria.stayNear:
      // AMBIGUOUS resolves to NEAR (fail-safe toward the compliant outcome).
      if (w.verdictFinal == ProxVerdict.near) {
        return const CriterionReading(
            false, 'final NEAR → STAY_NEAR met');
      }
      if (w.verdictFinal == ProxVerdict.ambiguous) {
        return const CriterionReading(false,
            'final AMBIGUOUS is treated as NEAR (fail-safe) → STAY_NEAR met');
      }
      return const CriterionReading(true, 'final AWAY → STAY_NEAR not met');

    case DebugCriteria.getAway:
      // Firmware: a NEAR verdict returns not-met outright (no amount of
      // walking makes "in the room" compliant); anything else is met only
      // once the locomotion gate admits. AMBIGUOUS is NOT compliant here,
      // unlike STAY_NEAR: on getAway the user benefits from looking far.
      if (w.verdictFinal == ProxVerdict.near) {
        return const CriterionReading(
            true, 'final NEAR → GET_AWAY not met (still at the anchor)');
      }
      if (w.gateAdmits) {
        return CriterionReading(
            false,
            'final ${w.verdictFinal.label} and the locomotion gate admits '
            '(hits ${w.gateHits}/${w.gateArmHits}, armed '
            '${w.gateArmed ? 'yes' : 'no'}, still ${w.stillForS}s vs '
            'liveness ${w.livenessS}s, motion ${w.motionState.label}) '
            '→ GET_AWAY met');
      }
      return CriterionReading(
          true,
          'final ${w.verdictFinal.label} but the locomotion gate does not '
          'admit (hits ${w.gateHits}/${w.gateArmHits}, armed '
          '${w.gateArmed ? 'yes' : 'no'}, still ${w.stillForS}s vs '
          'liveness ${w.livenessS}s, motion ${w.motionState.label}) '
          '→ GET_AWAY not met (needs ${w.gateArmHits} locomotion hits; '
          'stillness past liveness revokes it)');

    case DebugCriteria.phoneAway:
      final withUser = w.dock == 0 ||
          w.phoneUndockLatched ||
          w.verdictFinal == ProxVerdict.near;
      final enforcing =
          withUser && w.phoneNearForS >= w.phoneToleranceS;
      final reason = w.dock == 0
          ? 'dock read says undocked'
          : w.phoneUndockLatched
              ? 'undock latch set'
              : w.verdictFinal == ProxVerdict.near
                  ? 'final NEAR'
                  : 'phone away from the user';
      return CriterionReading(
        enforcing,
        'phone ${withUser ? 'with the user' : 'away from the user'} '
        '($reason; dock=${_dockLabel(w.dock)}), '
        '${w.phoneNearForS}s / ${w.phoneToleranceS}s tolerance '
        '→ PHONE_AWAY ${enforcing ? 'not met' : 'met'}',
      );

    case DebugCriteria.getOnWifi:
      final compliant = w.wifiConnected && w.ssidMatch == 1;
      return CriterionReading(
        !compliant,
        'wifi=${w.wifiConnected}, ssid_match=${_ssidLabel(w.ssidMatch)} '
        '→ GET_ON_WIFI ${compliant ? 'met' : 'not met'}',
      );

    case DebugCriteria.getOffWifi:
      final onTarget = w.wifiConnected && w.ssidMatch == 1;
      return CriterionReading(
        onTarget,
        'wifi=${w.wifiConnected}, ssid_match=${_ssidLabel(w.ssidMatch)} '
        '→ GET_OFF_WIFI ${onTarget ? 'not met' : 'met'}',
      );
  }
}

// ── Group B: an anchor beeping on WATCH_REMOVED ─────────────────────────────

BeepConditionGroup _anchorRemovedGroup(
  WatchDebugTelemetry? w,
  AnchorDebugTelemetry? a,
  String? anchorId,
) {
  const title = 'Anchor beeps: watch removed';
  const subtitle = 'The watch escalates over UDP; the anchor re-checks every '
      'guard itself.';
  const labels = [
    'watch in a window',
    'anchor in event beep list (watch side)',
    'watch unworn',
    'not in donning grace',
    'watch WiFi connected',
    'WATCH_REMOVED was sent',
    'anchor WiFi connected',
    'anchor clock valid',
    'anchor schedule loaded',
    'event known to anchor',
    'not negated today',
    'anchor in event beep list (anchor side)',
    'anchor profile present',
    'window open (anchor clock)',
    'last UDP accepted',
    'beeping now',
    'clocks agree (≤ 1 min)',
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

  return BeepConditionGroup(
    title: title,
    subtitle: subtitle,
    conditions: [
      BeepCondition(
        'watch in a window',
        w.hasActiveEvent ? ConditionState.met : ConditionState.unmet,
        w.criteria == null
            ? 'no active event'
            : '${w.criteria!.label} ${_fmtMinute(w.startMin)}–'
                '${_fmtMinute(w.endMin)} · activity ${w.activityState.label}',
      ),
      _fromWatchRecord(
        'anchor in event beep list (watch side)',
        record,
        anchorId,
        (r) => r.inBeepList,
        (r) => r.inBeepList
            ? 'this anchor is in the active event\'s beepAnchors'
            : 'this anchor is NOT in the active event\'s beepAnchors',
      ),
      BeepCondition(
        'watch unworn',
        w.worn ? ConditionState.unmet : ConditionState.met,
        w.worn ? 'worn — the watch enforces itself' : 'unworn (removed)',
      ),
      BeepCondition(
        'not in donning grace',
        w.graceActive ? ConditionState.unmet : ConditionState.met,
        w.graceActive
            ? 'grace active · ${w.graceRemainingS}s remaining'
            : 'no grace',
      ),
      BeepCondition(
        'watch WiFi connected',
        w.wifiConnected ? ConditionState.met : ConditionState.unmet,
        w.wifiConnected
            ? 'connected — UDP escalation is possible'
            : 'no WiFi — WATCH_REMOVED cannot leave the watch',
      ),
      _removedResultCondition(w.removedResult, w.sinceRemovedS),
      _fromAnchor(
        'anchor WiFi connected',
        a,
        (x) => x.wifiConnected,
        (x) => x.wifiConnected ? 'connected' : 'no WiFi',
      ),
      _fromAnchor(
        'anchor clock valid',
        a,
        (x) => x.timeValid,
        (x) => x.timeValid
            ? 'SNTP clock set · local ${_fmtMinute(x.localMinute)}'
            : 'no SNTP clock: the anchor\'s ONLY clock is SNTP, so every '
                'WATCH_REMOVED is rejected as outside the window',
      ),
      _fromAnchor(
        'anchor schedule loaded',
        a,
        (x) => x.scheduleLoaded,
        (x) => x.scheduleLoaded
            ? '${x.todayEventCount} event(s) today'
            : 'no schedule in NVS — the anchor ignores all beeps (§4.7)',
      ),
      _anchorEventKnown(eventId, a),
      _fromAnchorEvent(
        'not negated today',
        anchorEvent,
        (e) => !e.negatedToday,
        (e) => e.negatedToday
            ? 'event is negated today (emergency pass / edit)'
            : 'event is not negated',
      ),
      _fromAnchorEvent(
        'anchor in event beep list (anchor side)',
        anchorEvent,
        (e) => e.inBeepList,
        (e) => e.inBeepList
            ? 'anchor sees itself in beepAnchors'
            : 'anchor does NOT see itself in beepAnchors',
      ),
      _fromAnchorEvent(
        'anchor profile present',
        anchorEvent,
        (e) => e.hasAnchorProfile,
        (e) => e.hasAnchorProfile
            ? 'anchorProfile present'
            : 'event has no anchorProfile — start_beeping() refuses',
      ),
      _fromAnchorEvent(
        'window open (anchor clock)',
        anchorEvent,
        (e) => e.windowOpenNow,
        (e) => e.windowOpenNow
            ? 'inside ${_fmtMinute(e.startMin)}–${_fmtMinute(e.endMin)} '
                'by the anchor\'s clock'
            : 'outside ${_fmtMinute(e.startMin)}–${_fmtMinute(e.endMin)} '
                'by the anchor\'s clock',
      ),
      _lastUdpCondition(a).asInformational(),
      _beepingCondition(a).asInformational(),
      _clockSkewCondition(w, a).asInformational(),
    ],
  );
}

// ── Group C: an anchor beeping on a dock violation ──────────────────────────

BeepConditionGroup _anchorDockGroup(
  WatchDebugTelemetry? w,
  AnchorDebugTelemetry? a,
) {
  const title = 'Anchor beeps: phone left dock';
  const subtitle = 'phoneAway only: the anchor acts on its own evidence '
      '(§4.11.1).';
  const labels = [
    'anchor clock valid',
    'dock window open',
    'phone was docked this window',
    'phone currently undocked',
    'violation flagged (adv_undocked)',
    'dock alarm sounding',
  ];
  if (a == null) {
    return _unknownGroup(
      title,
      subtitle,
      labels,
      detail: 'anchor telemetry not read yet',
    );
  }

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
            ? 'SNTP clock set · local ${_fmtMinute(a.localMinute)}'
            : 'no SNTP clock — the dock window cannot be evaluated',
      ),
      if (dockEvent == null)
        const BeepCondition(
          'dock window open',
          ConditionState.unmet,
          'no phoneAway event names this anchor today, so it has no dock '
              'alarm to sound',
        )
      else
        BeepCondition(
          'dock window open',
          windowOpen ? ConditionState.met : ConditionState.unmet,
          '${_fmtMinute(dockEvent.startMin)}–${_fmtMinute(dockEvent.endMin)}'
          '${dockEvent.negatedToday ? ' · negated today' : ''} · '
          'window_open_now=${dockEvent.windowOpenNow}',
        ),
      BeepCondition(
        'phone was docked this window',
        a.dockSeenThisWindow ? ConditionState.met : ConditionState.unmet,
        a.dockSeenThisWindow
            ? 'the phone has been on the dock in this window'
            : 'the phone has NOT been seen on the dock this window — '
                '"not docked" is not yet a violation',
      ),
      BeepCondition(
        'phone currently undocked',
        a.docked ? ConditionState.unmet : ConditionState.met,
        'docked=${a.docked} · last RSSI ${a.dockLastRssi} dBm vs threshold '
        '${a.dockRssiThr} dBm · undock streak ${a.undockStreak}/'
        '${a.undockConfirm}',
      ),
      BeepCondition(
        'violation flagged (adv_undocked)',
        informational: true,
        a.advUndocked ? ConditionState.met : ConditionState.unmet,
        a.advUndocked
            ? 'advertisement carries the undocked flag'
            : 'advertisement does not carry the undocked flag',
      ),
      BeepCondition(
        'dock alarm sounding',
        informational: true,
        a.beeping && a.dockAlarm ? ConditionState.met : ConditionState.unmet,
        a.beeping
            ? (a.dockAlarm
                ? 'dock alarm on · ${a.beepingForS}s of '
                    '${a.maxBeepMinutes * 60}s cap'
                : 'the active alarm is a WATCH_REMOVED alarm, not the dock '
                    'alarm (${a.beepingForS}s)')
            : 'not beeping',
      ),
    ],
  );
}

// ── Group builders ──────────────────────────────────────────────────────────

BeepCondition _removedResultCondition(
    WatchRemovedResult result, int sinceS) {
  switch (result) {
    case WatchRemovedResult.sentToStoredIp:
    case WatchRemovedResult.sentByBroadcast:
      return BeepCondition('WATCH_REMOVED was sent', ConditionState.met,
          '${result.label}, ${_fmtAge(sinceS)}');
    case WatchRemovedResult.never:
      return BeepCondition('WATCH_REMOVED was sent',
          ConditionState.unknown, 'never attempted');
    case WatchRemovedResult.notSentNoWifi:
    case WatchRemovedResult.sendFailed:
      return BeepCondition('WATCH_REMOVED was sent', ConditionState.unmet,
          '${result.label}, ${_fmtAge(sinceS)}');
  }
}

BeepCondition _anchorEventKnown(
    String? eventId, AnchorDebugTelemetry? a) {
  if (a == null) {
    return const BeepCondition('event known to anchor',
        ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (eventId == null || eventId.isEmpty) {
    return const BeepCondition('event known to anchor',
        ConditionState.unknown, 'no active event on the watch');
  }
  final known = a.eventRecord(eventId) != null;
  return BeepCondition(
    'event known to anchor',
    known ? ConditionState.met : ConditionState.unmet,
    known
        ? 'event ${_short(eventId)} is in the anchor\'s '
            '${a.relevantEvents.length} relevant event(s)'
        : 'event ${_short(eventId)} is NOT in the anchor\'s '
            '${a.relevantEvents.length} relevant event(s). Either a pass '
            'negated it today (the anchor drops negated events from its day '
            'list) or the anchor and watch schedules disagree',
  );
}

BeepCondition _lastUdpCondition(AnchorDebugTelemetry? a) {
  const label = 'last UDP accepted';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  final result = a.lastUdpResult;
  final String detail = '${a.lastUdpCmdLabel} · '
      '${_fmtAge(a.sinceLastUdpS)} → ${result.label}';
  if (result == AnchorUdpResult.none) {
    return BeepCondition(label, ConditionState.unknown, detail);
  }
  if (a.lastUdpCmd == 0x01 &&
      (result == AnchorUdpResult.started ||
          result == AnchorUdpResult.alreadyBeeping)) {
    return BeepCondition(label, ConditionState.met, detail);
  }
  return BeepCondition(label, ConditionState.unmet, detail);
}

BeepCondition _beepingCondition(AnchorDebugTelemetry? a) {
  const label = 'beeping now';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (!a.beeping) {
    return const BeepCondition(label, ConditionState.unmet, 'not beeping');
  }
  final cap = a.maxBeepMinutes * 60;
  if (a.beepingForS >= cap) {
    return BeepCondition(
      label,
      ConditionState.unmet,
      'beeping ${a.beepingForS}s has reached the ${a.maxBeepMinutes}-minute '
      'cap (${cap}s) — update_beeping() will stop it',
    );
  }
  return BeepCondition(
    label,
    ConditionState.met,
    'beeping ${a.beepingForS}s of ${a.maxBeepMinutes}m cap · '
    'profile ${a.beepProfileLabel} · phase '
    '${a.beepPhaseOn ? 'on' : 'off (normal duty-cycle gap)'}',
  );
}

/// Compare the watch's local minute with the anchor's SNTP minute. Two clocks
/// two minutes apart put a WATCH_REMOVED outside its window at the boundary,
/// which looks exactly like "the anchor ignored us".
BeepCondition _clockSkewCondition(
    WatchDebugTelemetry w, AnchorDebugTelemetry? a) {
  const label = 'clocks agree (≤ 1 min)';
  if (a == null) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor telemetry not read yet');
  }
  if (!a.timeValid || a.localMinute == 0xFFFF) {
    return const BeepCondition(
        label, ConditionState.unknown, 'anchor clock is not valid');
  }
  if (!w.timeValid) {
    return const BeepCondition(
        label, ConditionState.unknown, 'watch clock is not valid');
  }
  final watchMinute = w.localMinute;
  final skew = _circularMinuteDiff(watchMinute, a.localMinute);
  return BeepCondition(
    label,
    skew <= 1 ? ConditionState.met : ConditionState.unmet,
    'watch ${_fmtMinute(watchMinute)} vs anchor '
    '${_fmtMinute(a.localMinute)} ($skew min apart)'
    '${skew > 1 ? ' — a WATCH_REMOVED near a window edge can land on the '
        'wrong side' : ''}',
  );
}

// ── Sentence builder for the Proximity decision card ────────────────────────

/// Plain-English reading of the proximity snapshot, e.g.
/// "Score 150 < threshold 170 → v0.8 says AWAY; HMM AMBIGUOUS; final AWAY →
/// STAY_NEAR not met". Pure so the same sentence can be asserted in tests.
String buildProximityInterpretation(WatchDebugTelemetry? w) {
  if (w == null) {
    return 'No watch snapshot yet — connect the watch and read …001D.';
  }
  if (w.proxPath == DebugProxPath.never) {
    return 'No anchor query yet: prox_path = never. '
        '${w.hasActiveEvent ? 'Waiting for the first enforcement poll.' : 'No active window.'}';
  }
  final parts = <String>[];
  final comparison = w.score < w.nearThr
      ? '<'
      : (w.score > w.nearThr ? '>' : '=');
  parts.add('Score ${w.score} $comparison threshold ${w.nearThr} '
      '(${w.nearThrSource == 1 ? 'anchor-calibrated' : 'global default'}) '
      '→ v0.8 says ${w.verdictV08.label}');
  parts.add('HMM ${w.verdictV2.label}');
  final reading = readCriterion(w);
  final criterion = w.criteria == null ? 'no criterion' : w.criteria!.label;
  parts.add('final ${w.verdictFinal.label} → $criterion '
      '${reading.notMet == null ? 'undecided' : (reading.notMet! ? 'not met' : 'met')}');

  final tail = StringBuffer(parts.join('; '));
  if (w.proxPath != DebugProxPath.score) {
    tail.write(' (query ended as ${w.proxPath.label}; score is stale)');
  }
  if (w.v0Stub) {
    tail.write(' · V0 STUB forces noncompliant');
  }
  return tail.toString();
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

BeepCondition _fromWatchRecord(
  String label,
  WatchAnchorRecord? record,
  String? anchorId,
  bool Function(WatchAnchorRecord) test,
  String Function(WatchAnchorRecord) describe,
) {
  if (anchorId == null || anchorId.isEmpty) {
    return BeepCondition(
        label, ConditionState.unknown, 'no anchor selected');
  }
  if (record == null) {
    return BeepCondition(
        label, ConditionState.unknown,
        'anchor ${_short(anchorId)} is not in the watch\'s snapshot');
  }
  return BeepCondition(
      label, test(record) ? ConditionState.met : ConditionState.unmet,
      describe(record));
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

BeepCondition _fromAnchorEvent(
  String label,
  AnchorEventRecord? event,
  bool Function(AnchorEventRecord) test,
  String Function(AnchorEventRecord) describe,
) {
  if (event == null) {
    return BeepCondition(
        label, ConditionState.unknown,
        'the active event is not in the anchor\'s relevant list');
  }
  return BeepCondition(
      label, test(event) ? ConditionState.met : ConditionState.unmet,
      describe(event));
}

String _fmtMinute(int m) {
  if (m == 0xFFFF) return 'never';
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

String _fmtClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

String _fmtAge(int seconds) =>
    seconds == 0xFFFF ? 'never' : '${seconds}s ago';

String _short(String uuid) =>
    uuid.length <= 8 ? uuid : uuid.substring(0, 8);

String _onOff(bool on) => on ? 'on' : 'off';

String _dockLabel(int dock) {
  switch (dock) {
    case 0: return 'undocked';
    case 1: return 'docked';
    default: return 'unknown';
  }
}

String _ssidLabel(int ssidMatch) {
  switch (ssidMatch) {
    case 0: return 'no match';
    case 1: return 'match';
    default: return 'n/a';
  }
}

/// Smallest circular distance between two minutes-of-day.
int _circularMinuteDiff(int a, int b) {
  final d = (a - b).abs() % 1440;
  return d > 720 ? 1440 - d : d;
}
