// Pure-condition tests for the Proximity debug tab (firmware §5.4/§5.6,
// §4.6/§4.11.1). No Flutter, no BLE: these exercise exactly the decision logic
// the tab renders.

import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/debug_telemetry.dart';
import 'package:impulse_app/services/beep_conditions.dart';

const _anchorId = 'anchor-a';
const _eventId = 'event-1';

WatchAnchorRecord _watchAnchor({
  bool inBeepList = true,
  bool isEventAnchor = true,
}) =>
    WatchAnchorRecord(
      uuid: _anchorId,
      rssi: -66,
      sinceSeenS: 10,
      lastScore: 150,
      bleMacValid: true,
      ipKnown: true,
      isEventAnchor: isEventAnchor,
      inBeepList: inBeepList,
      rssiFresh: true,
      reserved: 0,
    );

/// A healthy, mid-enforcement watch snapshot. Each test overrides one fact.
WatchDebugTelemetry _watch({
  bool worn = false,
  bool btConnected = true,
  bool wifiConnected = true,
  bool timeValid = true,
  bool graceActive = false,
  bool profileActive = true,
  bool conditionMet = false,
  bool v0Stub = false,
  bool motorOn = true,
  bool buzzerOn = true,
  bool phoneUndockLatched = false,
  bool shouldEnforce = true,
  DebugActivityState activityState = DebugActivityState.enforcement,
  int utcNow = 1767225600,
  int tzOffsetMin = 390,
  String activeEventId = _eventId,
  DebugCriteria? criteria = DebugCriteria.stayNear,
  int startMin = 390,
  int endMin = 435,
  int graceRemainingS = 0,
  int lastPollMet = 0,
  DebugProxPath proxPath = DebugProxPath.score,
  ProxVerdict verdictFinal = ProxVerdict.away,
  ProxVerdict verdictV08 = ProxVerdict.away,
  ProxVerdict verdictV2 = ProxVerdict.ambiguous,
  int score = 150,
  int nearThr = 170,
  DebugMotionState motionState = DebugMotionState.still,
  int dock = 0xFF,
  bool gateArmed = true,
  int gateHits = 3,
  int gateArmHits = 5,
  bool gateAdmits = true,
  int stillForS = 12,
  int livenessS = 30,
  int phoneNearForS = 120,
  int phoneToleranceS = 120,
  WatchRemovedResult removedResult = WatchRemovedResult.sentToStoredIp,
  int sinceRemovedS = 7,
  int ssidMatch = 0xFF,
  List<WatchAnchorRecord>? anchors,
}) =>
    WatchDebugTelemetry(
      worn: worn,
      btConnected: btConnected,
      wifiConnected: wifiConnected,
      timeValid: timeValid,
      graceActive: graceActive,
      profileActive: profileActive,
      conditionMet: conditionMet,
      v0Stub: v0Stub,
      motorOn: motorOn,
      buzzerOn: buzzerOn,
      proxV2Authoritative: true,
      phoneUndockLatched: phoneUndockLatched,
      calibActive: false,
      shouldEnforce: shouldEnforce,
      disconnectedIsDormant: true,
      awayIsDormant: true,
      activityState: activityState,
      utcNow: utcNow,
      tzOffsetMin: tzOffsetMin,
      uptimeMs: 1,
      activeEventId: activeEventId,
      criteria: criteria,
      profile: 4,
      startMin: startMin,
      endMin: endMin,
      eventAnchorId: _anchorId,
      beepAnchorCount: 1,
      donningGraceS: 300,
      graceRemainingS: graceRemainingS,
      stepIdx: 1,
      cycleCount: 2,
      pollIntervalS: 30,
      sinceLastPollS: 10,
      lastPollMet: lastPollMet,
      proxPath: proxPath,
      sinceLastQueryS: 10,
      verdictFinal: verdictFinal,
      verdictV08: verdictV08,
      verdictV2: verdictV2,
      score: score,
      nearThr: nearThr,
      nearThrSource: 1,
      scoreFlags: 0,
      emitQ8: -512,
      lambdaQ8: -1234,
      pNearU8: 12,
      motionState: motionState,
      pdrRateU8: 0xFF,
      pdrCovered: 0,
      pdrLlr: 0,
      dock: dock,
      gateArmed: gateArmed,
      gateHits: gateHits,
      gateArmHits: gateArmHits,
      gateAdmits: gateAdmits,
      stillForS: stillForS,
      livenessS: livenessS,
      phoneNearForS: phoneNearForS,
      phoneToleranceS: phoneToleranceS,
      farRssiThr: -75,
      removedResult: removedResult,
      sinceRemovedS: sinceRemovedS,
      ssidMatch: ssidMatch,
      anchors: anchors ?? [_watchAnchor()],
    );

AnchorEventRecord _event({
  String eventId = _eventId,
  int startMin = 390,
  int endMin = 435,
  DebugCriteria? criteria = DebugCriteria.phoneAway,
  bool negatedToday = false,
  bool inBeepList = true,
  bool isDockEvent = true,
  bool hasAnchorProfile = true,
  bool windowOpenNow = true,
}) =>
    AnchorEventRecord(
      eventId: eventId,
      startMin: startMin,
      endMin: endMin,
      criteria: criteria,
      negatedToday: negatedToday,
      inBeepList: inBeepList,
      isDockEvent: isDockEvent,
      hasAnchorProfile: hasAnchorProfile,
      windowOpenNow: windowOpenNow,
    );

/// A healthy anchor that is currently beeping on WATCH_REMOVED.
AnchorDebugTelemetry _anchor({
  bool wifiConnected = true,
  bool timeValid = true,
  bool scheduleLoaded = true,
  bool beeping = true,
  bool beepPhaseOn = true,
  bool dockAlarm = false,
  bool docked = false,
  bool dockSeenThisWindow = true,
  bool advUndocked = true,
  int localMinute = 390,
  int beepingForS = 12,
  int maxBeepMinutes = 30,
  int lastUdpCmd = 0x01,
  AnchorUdpResult lastUdpResult = AnchorUdpResult.started,
  int sinceLastUdpS = 5,
  int dockLastRssi = -72,
  int dockRssiThr = -60,
  int undockStreak = 2,
  int undockConfirm = 3,
  List<AnchorEventRecord>? events,
}) =>
    AnchorDebugTelemetry(
      wifiConnected: wifiConnected,
      timeValid: timeValid,
      scheduleLoaded: scheduleLoaded,
      beeping: beeping,
      beepPhaseOn: beepPhaseOn,
      dockAlarm: dockAlarm,
      identifyActive: false,
      docked: docked,
      dockPhoneConnected: true,
      dockSeenThisWindow: dockSeenThisWindow,
      advUndocked: advUndocked,
      debugMode: false,
      utcNow: 1767225600,
      tzOffsetMin: 0,
      uptimeMs: 1,
      localMinute: localMinute,
      ip: '192.168.1.42',
      maxBeepMinutes: maxBeepMinutes,
      todayEventCount: 1,
      beepProfile: 1,
      alarmEventId: _eventId,
      beepingForS: beepingForS,
      dockLastRssi: dockLastRssi,
      dockRssiThr: dockRssiThr,
      undockStreak: undockStreak,
      undockConfirm: undockConfirm,
      lastUdpCmd: lastUdpCmd,
      lastUdpResult: lastUdpResult,
      sinceLastUdpS: sinceLastUdpS,
      lastUdpEventId: _eventId,
      relevantEvents: events ?? [_event()],
    );

BeepCondition _check(BeepConditionGroup group, String label) =>
    group.conditions.firstWhere((c) => c.label == label);

void main() {
  group('watch group (A)', () {
    test('a failing stayNear criterion is "would beep now"', () {
      final report = evaluateBeepConditions(
          watch: _watch(), anchorId: _anchorId);
      final g = report.watchGroup;
      expect(g.verdict, 'would beep now');
      expect(_check(g, 'criterion not met').state, ConditionState.met);
      expect(_check(g, 'criterion not met').detail,
          contains('final AWAY → STAY_NEAR not met'));
    });

    test('last_poll_met drives the criterion state; 0xFF is unknown', () {
      final compliant = evaluateBeepConditions(
          watch: _watch(lastPollMet: 1), anchorId: _anchorId);
      expect(_check(compliant.watchGroup, 'criterion not met').state,
          ConditionState.unmet);
      expect(compliant.watchGroup.verdict,
          'would not, first failing: criterion not met');

      final never = evaluateBeepConditions(
          watch: _watch(lastPollMet: 0xFF), anchorId: _anchorId);
      expect(_check(never.watchGroup, 'criterion not met').state,
          ConditionState.unknown);
      expect(never.watchGroup.verdict, 'unknown');
    });

    test('grace short-circuits with a countdown and is the first failure', () {
      final report = evaluateBeepConditions(
          watch: _watch(graceActive: true, graceRemainingS: 45),
          anchorId: _anchorId);
      final grace = _check(report.watchGroup, 'not in donning grace');
      expect(grace.state, ConditionState.unmet);
      expect(grace.detail, contains('45s remaining'));
      expect(report.watchGroup.verdict,
          'would not, first failing: not in donning grace');
    });

    test('profile detail explains that off-now is normal mid-profile', () {
      final report = evaluateBeepConditions(
          watch: _watch(profileActive: false, motorOn: false, buzzerOn: false),
          anchorId: _anchorId);
      final p = _check(report.watchGroup, 'enforcement profile playing');
      expect(p.state, ConditionState.unmet);
      expect(p.detail, contains('motor off'));
      expect(p.detail, contains('normal mid-profile'));
    });

    test('v0 stub is flagged loudly', () {
      final report = evaluateBeepConditions(
          watch: _watch(v0Stub: true), anchorId: _anchorId);
      expect(report.warning, contains('V0 STUB'));
      expect(report.warning, contains('forced'));
    });
  });

  group('readCriterion branches', () {
    test('STAY_NEAR: NEAR and AMBIGUOUS are met, AWAY is not', () {
      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.stayNear,
                  verdictFinal: ProxVerdict.near))
              .notMet,
          isFalse);
      final ambiguous = readCriterion(_watch(
          criteria: DebugCriteria.stayNear,
          verdictFinal: ProxVerdict.ambiguous));
      expect(ambiguous.notMet, isFalse);
      expect(ambiguous.explanation, contains('fail-safe'));
      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.stayNear,
                  verdictFinal: ProxVerdict.away))
              .notMet,
          isTrue);
    });

    // Mirrors firmware is_enforcement_condition_met() GET_AWAY: NEAR returns
    // not-met outright; anything else is met only once the gate admits.
    test('GET_AWAY: NEAR is not met; otherwise met only when the gate admits',
        () {
      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.getAway,
                  verdictFinal: ProxVerdict.near))
              .notMet,
          isTrue);

      final admitted = readCriterion(_watch(
          criteria: DebugCriteria.getAway,
          verdictFinal: ProxVerdict.away,
          gateAdmits: true));
      expect(admitted.notMet, isFalse);
      expect(admitted.explanation, contains('hits 3/5'));
      expect(admitted.explanation, contains('armed yes'));
      expect(admitted.explanation, contains('still 12s vs liveness 30s'));
      expect(admitted.explanation, contains('motion STILL'));

      final refused = readCriterion(_watch(
          criteria: DebugCriteria.getAway,
          verdictFinal: ProxVerdict.ambiguous,
          gateAdmits: false,
          gateArmed: false,
          gateHits: 0));
      // AMBIGUOUS is not compliant on getAway (unlike STAY_NEAR).
      expect(refused.notMet, isTrue);
      expect(refused.explanation, contains('does not admit'));
    });

    test('PHONE_AWAY: dock 0, latch or final NEAR make the phone "with user"',
        () {
      final undocked = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway, dock: 0));
      expect(undocked.notMet, isTrue);
      expect(undocked.explanation, contains('dock read says undocked'));

      final latched = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway,
          dock: 0xFF,
          phoneUndockLatched: true));
      expect(latched.notMet, isTrue);
      expect(latched.explanation, contains('undock latch'));

      final near = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway,
          dock: 0xFF,
          verdictFinal: ProxVerdict.near));
      expect(near.notMet, isTrue);
      expect(near.explanation, contains('final NEAR'));

      final dockedAway = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway,
          dock: 1,
          verdictFinal: ProxVerdict.away));
      expect(dockedAway.notMet, isFalse);
    });

    test('PHONE_AWAY: enforces only after the tolerance', () {
      final inside = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway,
          dock: 0,
          phoneNearForS: 119,
          phoneToleranceS: 120));
      expect(inside.notMet, isFalse);
      expect(inside.explanation, contains('119s / 120s'));

      final past = readCriterion(_watch(
          criteria: DebugCriteria.phoneAway,
          dock: 0,
          phoneNearForS: 120,
          phoneToleranceS: 120));
      expect(past.notMet, isTrue);
    });

    test('WiFi criteria use wifi_connected + ssid_match', () {
      final onMet = readCriterion(_watch(
          criteria: DebugCriteria.getOnWifi,
          wifiConnected: true,
          ssidMatch: 1));
      expect(onMet.notMet, isFalse);

      final onWrong = readCriterion(_watch(
          criteria: DebugCriteria.getOnWifi,
          wifiConnected: true,
          ssidMatch: 0));
      expect(onWrong.notMet, isTrue);

      final onOffline = readCriterion(_watch(
          criteria: DebugCriteria.getOnWifi,
          wifiConnected: false,
          ssidMatch: 0xFF));
      expect(onOffline.notMet, isTrue);

      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.getOffWifi,
                  wifiConnected: true,
                  ssidMatch: 1))
              .notMet,
          isTrue);
      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.getOffWifi,
                  wifiConnected: true,
                  ssidMatch: 0))
              .notMet,
          isFalse);
      expect(
          readCriterion(_watch(
                  criteria: DebugCriteria.getOffWifi,
                  wifiConnected: false,
                  ssidMatch: 0xFF))
              .notMet,
          isFalse);
    });

    test('no active criterion is undecided', () {
      final r = readCriterion(_watch(criteria: null));
      expect(r.notMet, isNull);
      expect(r.explanation, contains('no active criterion'));
    });
  });

  group('null telemetry', () {
    test('every group is unknown with "not read yet"', () {
      final report = evaluateBeepConditions();
      expect(report.groups, hasLength(3));
      for (final g in report.groups) {
        expect(g.conditions, isNotEmpty);
        expect(g.conditions.every((c) => c.state == ConditionState.unknown),
            isTrue);
        expect(g.conditions.first.detail, contains('not read yet'));
        expect(g.verdict, 'unknown');
      }
    });

    test('only the anchor groups stay unknown without anchor telemetry', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false), anchorId: _anchorId);
      expect(report.watchGroup.state, ConditionState.met);
      expect(_check(report.anchorRemovedGroup, 'anchor WiFi connected').detail,
          contains('anchor telemetry not read yet'));
      expect(report.anchorRemovedGroup.verdict, 'unknown');
      expect(report.anchorDockGroup.verdict, 'unknown');
    });
  });

  group('anchor WATCH_REMOVED group (B)', () {
    test('healthy unworn watch + healthy anchor is "would beep now"', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false),
          anchor: _anchor(),
          anchorId: _anchorId);
      expect(report.anchorRemovedGroup.verdict, 'would beep now');
    });

    test('missing anchor clock is called out (SNTP-only, outside window)', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false),
          anchor: _anchor(
              timeValid: false,
              lastUdpResult: AnchorUdpResult.rejectedOutsideWindow),
          anchorId: _anchorId);
      final clock = _check(report.anchorRemovedGroup, 'anchor clock valid');
      expect(clock.state, ConditionState.unmet);
      expect(clock.detail, contains('ONLY clock is SNTP'));
      expect(clock.detail, contains('outside the window'));
      expect(
          report.anchorRemovedGroup.verdict,
          'would not, first failing: anchor clock valid');
    });

    test('clock skew over one minute is flagged', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false, tzOffsetMin: 390),
          anchor: _anchor(localMinute: 393),
          anchorId: _anchorId);
      final skew = _check(report.anchorRemovedGroup, 'clocks agree (≤ 1 min)');
      expect(skew.state, ConditionState.unmet);
      expect(skew.detail, contains('3 min apart'));
      expect(skew.detail, contains('window edge'));
    });

    test('skew of exactly one minute passes', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false, tzOffsetMin: 390),
          anchor: _anchor(localMinute: 391),
          anchorId: _anchorId);
      expect(_check(report.anchorRemovedGroup, 'clocks agree (≤ 1 min)').state,
          ConditionState.met);
    });

    test('UDP result is decoded into words', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false),
          anchor: _anchor(lastUdpResult: AnchorUdpResult.rejectedNegated),
          anchorId: _anchorId);
      final udp = _check(report.anchorRemovedGroup, 'last UDP accepted');
      expect(udp.state, ConditionState.unmet);
      expect(udp.detail, contains('negated today'));
      expect(udp.detail, contains('WATCH_REMOVED'));
    });

    test('watch-side beep-list flag and no WiFi are reported', () {
      final report = evaluateBeepConditions(
          watch: _watch(
              worn: false,
              wifiConnected: false,
              anchors: [_watchAnchor(inBeepList: false)]),
          anchor: _anchor(),
          anchorId: _anchorId);
      expect(
          _check(report.anchorRemovedGroup,
                  'anchor in event beep list (watch side)')
              .state,
          ConditionState.unmet);
      expect(_check(report.anchorRemovedGroup, 'watch WiFi connected').detail,
          contains('cannot leave the watch'));
      expect(
          report.anchorRemovedGroup.verdict,
          'would not, first failing: anchor in event beep list (watch side)');
    });

    test('beep cap expiry is not met', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false),
          anchor: _anchor(beepingForS: 1800, maxBeepMinutes: 30),
          anchorId: _anchorId);
      final beep = _check(report.anchorRemovedGroup, 'beeping now');
      expect(beep.state, ConditionState.unmet);
      expect(beep.detail, contains('30-minute cap'));
    });
  });

  group('anchor dock group (C)', () {
    AnchorDebugTelemetry dockAnchor({
      bool dockAlarm = true,
      bool docked = false,
      bool dockSeen = true,
      bool windowOpen = true,
      bool negated = false,
      bool dockAlarmBeeping = true,
    }) =>
        _anchor(
          dockAlarm: dockAlarm,
          beeping: dockAlarmBeeping,
          docked: docked,
          dockSeenThisWindow: dockSeen,
          events: [_event(windowOpenNow: windowOpen, negatedToday: negated)],
        );

    test('the violation transition is "would beep now"', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(),
          anchorId: _anchorId);
      expect(report.anchorDockGroup.verdict, 'would beep now');
    });

    test('phone still docked is the first failure', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(docked: true),
          anchorId: _anchorId);
      final c = _check(report.anchorDockGroup, 'phone currently undocked');
      expect(c.state, ConditionState.unmet);
      expect(c.detail, contains('-72 dBm vs threshold -60 dBm'));
      expect(c.detail, contains('2/3'));
    });

    test('never docked this window suppresses the alarm', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(dockSeen: false),
          anchorId: _anchorId);
      final c = _check(report.anchorDockGroup, 'phone was docked this window');
      expect(c.state, ConditionState.unmet);
      expect(c.detail, contains('not yet a violation'));
    });

    test('no dock event naming this anchor means no dock alarm (not met)', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: _anchor(dockAlarm: true, events: [
            _event(eventId: 'other-event', isDockEvent: false),
          ]),
          anchorId: _anchorId);
      expect(_check(report.anchorDockGroup, 'dock window open').state,
          ConditionState.unmet);
      expect(report.anchorDockGroup.verdict,
          'would not, first failing: dock window open');
    });

    test('window closed / negated is not met', () {
      final closed = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(windowOpen: false),
          anchorId: _anchorId);
      expect(_check(closed.anchorDockGroup, 'dock window open').state,
          ConditionState.unmet);

      final negated = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(negated: true),
          anchorId: _anchorId);
      expect(_check(negated.anchorDockGroup, 'dock window open').detail,
          contains('negated today'));
    });

    test('a non-dock alarm is not the dock alarm', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: true),
          anchor: dockAnchor(dockAlarm: false),
          anchorId: _anchorId);
      final c = _check(report.anchorDockGroup, 'dock alarm sounding');
      expect(c.state, ConditionState.unmet);
      expect(c.detail, contains('WATCH_REMOVED alarm'));
    });
  });

  group('interpretation sentence', () {
    test('names the score, threshold, both verdicts and the criterion', () {
      final sentence = buildProximityInterpretation(_watch(
        criteria: DebugCriteria.stayNear,
        score: 150,
        nearThr: 170,
        verdictV08: ProxVerdict.away,
        verdictV2: ProxVerdict.ambiguous,
        verdictFinal: ProxVerdict.away,
      ));
      expect(sentence, contains('Score 150 < threshold 170'));
      expect(sentence, contains('v0.8 says AWAY'));
      expect(sentence, contains('HMM AMBIGUOUS'));
      expect(sentence, contains('final AWAY → STAY_NEAR not met'));
    });

    test('notes a non-score query path and the v0 stub', () {
      final sentence = buildProximityInterpretation(_watch(
        proxPath: DebugProxPath.connectFailed,
        v0Stub: true,
      ));
      expect(sentence, contains('connect failed'));
      expect(sentence, contains('V0 STUB'));
    });

    test('explains a missing snapshot and a never-polled watch', () {
      expect(buildProximityInterpretation(null), contains('No watch snapshot'));
      expect(
          buildProximityInterpretation(
              _watch(proxPath: DebugProxPath.never)),
          contains('No anchor query yet'));
    });
  });

  group('informational rows', () {
    test('a silent anchor with every guard met does not blame "beeping now"',
        () {
      const g = BeepConditionGroup(title: 't', subtitle: 's', conditions: [
        BeepCondition('guard', ConditionState.met, ''),
        BeepCondition('beeping now', ConditionState.unmet, 'not beeping',
            informational: true),
        BeepCondition('clocks agree (≤ 1 min)', ConditionState.unknown, '',
            informational: true),
      ]);
      expect(g.firstUnmet, isNull);
      expect(g.hasUnknown, isFalse);
      expect(g.verdict, 'would beep now');
    });
  });
}
