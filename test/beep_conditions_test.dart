// Pure-condition tests for the Proximity debug tab (contract §3.1/§3.2/§3.3,
// §2.7). No Flutter, no BLE: these exercise exactly the decision logic the tab
// renders.
//
// The scenarios named in the brief are covered by name in the test titles:
// Sunrise Lock worn+NEAR, worn+AWAY, abstaining fail-open, unworn → removed
// over BLE accepted, rejected outside window with a 9 h slow anchor clock,
// refused over UDP, buzzer compiled out, dock unsupported and identity conflict.

import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/debug_telemetry.dart';
import 'package:impulse_app/services/beep_conditions.dart';

const _anchorId = '75757575-7575-7575-7575-757575757575';
const _otherAnchorId = '9e1c0d21-4c2b-4e8a-9b51-0a1b2c3d4e5f';
const _eventId = '11111111-1111-1111-1111-111111111111';

WatchAnchorRecord _record({
  String uuid = _anchorId,
  int? distanceCm = 142,
  int? ifftCm = 142,
  int? phaseSlopeCm = 155,
  int? rttCm = 190,
  int? ageS = 2,
  int sampleCount = 10,
  ProxVerdict verdict = ProxVerdict.near,
  CsAbstainReason? abstainReason = CsAbstainReason.ok,
  bool isEventAnchor = true,
  bool inBeepList = true,
  bool isLinkPeer = true,
  bool identityConflict = false,
  bool ranged = true,
}) =>
    WatchAnchorRecord(
      anchorUuid: uuid,
      distanceCm: distanceCm,
      ifftCm: ifftCm,
      phaseSlopeCm: phaseSlopeCm,
      rttCm: rttCm,
      ageS: ageS,
      sampleCount: sampleCount,
      verdict: verdict,
      abstainReason: abstainReason,
      isEventAnchor: isEventAnchor,
      inBeepList: inBeepList,
      isLinkPeer: isLinkPeer,
      identityConflict: identityConflict,
      ipKnown: false,
      ranged: ranged,
      quality: null,
    );

/// A healthy, mid-enforcement Sunrise Lock watch: GET_AWAY, worn, NEAR at
/// 1.42 m, so `condition_met = 0` and the motor and buzzer are driving. Each
/// test overrides one fact.
WatchDebugTelemetry _watch({
  DebugActivityState activityState = DebugActivityState.enforcement,
  DebugCriteria? criteria = DebugCriteria.getAway,
  WatchProfile? profile = WatchProfile.bothNormal,
  bool worn = true,
  bool timeValid = true,
  bool graceActive = false,
  bool profileActive = true,
  bool conditionMet = false,
  bool verdictHave = true,
  bool verdictNear = true,
  bool failsafe = false,
  bool motorOn = true,
  bool buzzerOn = true,
  bool buzzerCompiledOut = false,
  bool motorCompiledOut = false,
  bool outputSilenced = false,
  bool linkUp = true,
  bool linkReady = true,
  bool rangingOn = true,
  bool wifiOnAir = false,
  bool bleQuiesced = false,
  bool escPending = false,
  bool escGaveUp = false,
  bool escOnWifi = false,
  bool wifiConnected = false,
  bool wifiProvisioned = true,
  bool ackRefused = false,
  bool linkPeerKnown = true,
  bool linkPeerIsEventAnchor = true,
  bool identityConflict = false,
  bool verdictFromLostLink = false,
  bool graceIsLostLink = false,
  bool hasEventAnchor = true,
  bool wifiCriteria = false,
  ClockSource? clockSource = ClockSource.flash,
  WornSource wornSource = WornSource.imu,
  RingState? ringState = RingState.redSolid,
  EscalationCmd escPendingCmd = EscalationCmd.none,
  EscalationCmd escLastDeliveredCmd = EscalationCmd.none,
  ProxResult? proxLastResult = ProxResult.ok,
  EscalationAck? escLastAckResult,
  CsAbstainReason? csAbstainReason = CsAbstainReason.ok,
  PollMet? lastPollMet = PollMet.notMet,
  WatchDecision? lastDecision = WatchDecision.getAwayNear,
  int nearRun = 2,
  int awayRun = 0,
  int abstainRun = 0,
  int beepAnchorCount = 2,
  LinkPeerKind linkPeerKind = LinkPeerKind.eventAnchor,
  int? localMinute = 480,
  int? eventStartMin = 420,
  int? eventEndMin = 510,
  int nearEnterCm = 200,
  int awayEnterCm = 350,
  int donningGraceS = 600,
  int graceRemainingS = 0,
  int pollIntervalS = 60,
  int? sinceLastPollS = 12,
  int? sinceLastBurstS = 2,
  int? stillForS = 0,
  int? wornDiag = 980,
  int? stillThresholdS = 300,
  int? motionThresholdMms2 = 400,
  int? eventIndex = 0,
  int? utcNow = 1788091200,
  int tzOffsetMin = -240,
  int uptimeMs = 1234567,
  int? linkConnectedAtMs = 1179567,
  int radioPhaseDwellRemainingS = 0,
  RadioPhase radioPhase = RadioPhase.ble,
  String activeEventId = _eventId,
  String eventAnchorId = _anchorId,
  String linkPeerUuid = _anchorId,
  String? linkPeerAddr = 'D0:30:2F:4C:7E:C5',
  LinkPeerAddrType? linkPeerAddrType = LinkPeerAddrType.randomStatic,
  int linkConnectAttempts = 3,
  int linkConnectFailures = 1,
  int? linkLastDisconnectReason,
  int? escSinceRequestS,
  int escDeliveredBle = 0,
  int escDeliveredUdp = 0,
  int escWifiEntries = 0,
  int escAttempts = 0,
  String? ownIpv4,
  List<WatchAnchorRecord>? anchors,
}) =>
    WatchDebugTelemetry(
      version: 2,
      headerLen: 180,
      recordCount: (anchors ?? [_record()]).length,
      recordLen: 32,
      maxRecords: 10,
      activityState: activityState,
      criteria: criteria,
      profile: profile,
      worn: worn,
      timeValid: timeValid,
      graceActive: graceActive,
      profileActive: profileActive,
      conditionMet: conditionMet,
      verdictHave: verdictHave,
      verdictNear: verdictNear,
      failsafe: failsafe,
      motorOn: motorOn,
      buzzerOn: buzzerOn,
      buzzerCompiledOut: buzzerCompiledOut,
      motorCompiledOut: motorCompiledOut,
      outputSilenced: outputSilenced,
      linkUp: linkUp,
      linkReady: linkReady,
      rangingOn: rangingOn,
      wifiOnAir: wifiOnAir,
      bleQuiesced: bleQuiesced,
      escPending: escPending,
      escGaveUp: escGaveUp,
      escOnWifi: escOnWifi,
      wifiConnected: wifiConnected,
      wifiProvisioned: wifiProvisioned,
      ackRefused: ackRefused,
      linkPeerKnown: linkPeerKnown,
      linkPeerIsEventAnchor: linkPeerIsEventAnchor,
      identityConflict: identityConflict,
      verdictFromLostLink: verdictFromLostLink,
      graceIsLostLink: graceIsLostLink,
      hasEventAnchor: hasEventAnchor,
      anchorProfilePresent: true,
      wifiCriteria: wifiCriteria,
      wornSource: wornSource,
      ringState: ringState,
      escPendingCmd: escPendingCmd,
      escLastDeliveredCmd: escLastDeliveredCmd,
      proxLastResult: proxLastResult,
      escLastAckResult: escLastAckResult,
      csAbstainReason: csAbstainReason,
      lastPollMet: lastPollMet,
      lastDecision: lastDecision,
      nearRun: nearRun,
      awayRun: awayRun,
      abstainRun: abstainRun,
      integrityPendingCount: 0,
      beepAnchorCount: beepAnchorCount,
      csLastQuality: null,
      linkLastDisconnectReason: linkLastDisconnectReason,
      linkPeerKind: linkPeerKind,
      clockSource: clockSource,
      localMinute: localMinute,
      eventStartMin: eventStartMin,
      eventEndMin: eventEndMin,
      nearEnterCm: nearEnterCm,
      awayEnterCm: awayEnterCm,
      donningGraceS: donningGraceS,
      graceRemainingS: graceRemainingS,
      pollIntervalS: pollIntervalS,
      sinceLastPollS: sinceLastPollS,
      sinceLastBurstS: sinceLastBurstS,
      stillForS: stillForS,
      wornDiag: wornDiag,
      stillThresholdS: stillThresholdS,
      motionThresholdMms2: motionThresholdMms2,
      eventIndex: eventIndex,
      bootCount: 37,
      csBurstCount: 11,
      csRejectedRange: 1,
      csRejectedQuality: 0,
      csSuspectRelay: 0,
      csMissingIfft: 0,
      csDistanceCm: 142,
      csIfftCm: 142,
      csPhaseSlopeCm: 155,
      csRttCm: 190,
      linkConnectAttempts: linkConnectAttempts,
      linkConnectFailures: linkConnectFailures,
      escSinceRequestS: escSinceRequestS,
      escDeliveredBle: escDeliveredBle,
      escDeliveredUdp: escDeliveredUdp,
      escWifiEntries: escWifiEntries,
      escAttempts: escAttempts,
      integritySettleWindowMin: 120,
      passAllowance: 4,
      passRemaining: 3,
      utcNow: utcNow,
      tzOffsetMin: tzOffsetMin,
      uptimeMs: uptimeMs,
      linkConnectedAtMs: linkConnectedAtMs,
      radioPhaseSinceMs: null,
      radioPhaseDwellRemainingS: radioPhaseDwellRemainingS,
      radioPhase: radioPhase,
      reserved2: 0,
      activeEventId: activeEventId,
      eventAnchorId: eventAnchorId,
      linkPeerUuid: linkPeerUuid,
      linkPeerAddr: linkPeerAddr,
      linkPeerAddrType: linkPeerAddrType,
      snapshotSeq: 42,
      ownIpv4: ownIpv4,
      anchors: anchors ?? [_record()],
    );

AnchorEventRecord _event({
  String eventId = _eventId,
  int startMin = 420,
  int endMin = 510,
  DebugCriteria? criteria = DebugCriteria.getAway,
  bool negatedToday = false,
  bool inBeepList = true,
  bool isDockEvent = false,
  bool hasAnchorProfile = true,
  bool windowOpenNow = true,
  bool isAnchorIdTarget = false,
  bool clockInvalid = false,
  bool beepListNonempty = true,
  Recurrence recurrence = Recurrence.daily,
  bool supportedCriteria = true,
  bool activeAlarmEvent = true,
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
      isAnchorIdTarget: isAnchorIdTarget,
      clockInvalid: clockInvalid,
      beepListNonempty: beepListNonempty,
      recurrence: recurrence,
      supportedCriteria: supportedCriteria,
      activeAlarmEvent: activeAlarmEvent,
      reserved: 0,
    );

/// A healthy anchor that has just accepted WATCH_REMOVED over BLE and is
/// beeping a medium alarm. Each test overrides one fact.
AnchorDebugTelemetry _anchor({
  bool timeValid = true,
  bool scheduleLoaded = true,
  bool beeping = true,
  bool beepPhaseOn = true,
  bool buzzerCompiledOut = false,
  bool wifiConnected = false,
  bool wifiFallbackArmed = false,
  bool bleQuiesced = false,
  bool bleAdvertising = true,
  bool radioIsWifi = false,
  bool dockSupported = false,
  bool clockRestored = false,
  bool beepCapReached = false,
  ClockSource? clockSource = ClockSource.setThisBoot,
  BeepProfile? beepProfile = BeepProfile.medium,
  AnchorCmd lastCmd = AnchorCmd.watchRemoved,
  AnchorCmdResult? lastCmdResult = AnchorCmdResult.applied,
  AnchorCmdReason? lastCmdReason = AnchorCmdReason.started,
  AnchorCmdTransport? lastCmdTransport = AnchorCmdTransport.ble,
  int? localMinute = 480,
  int? sinceLastCmdS = 12,
  int beepingForS = 12,
  int beepCapRemainingS = 1788,
  int maxBeepMinutes = 30,
  int capStops = 0,
  bool noCommandYet = false,
  bool ackSent = false,
  int rejectUnknownEvent = 0,
  int rejectOutsideWindow = 0,
  int rejectNegated = 0,
  int rejectNotInBeepList = 0,
  int rejectMalformed = 0,
  int acceptedApplied = 1,
  bool rejectionWasClock = false,
  bool profileDefaulted = false,
  int? utcNow = 1788091200,
  int tzOffsetMin = -240,
  int peerLinkCount = 1,
  DockState? dockState,
  int bootCount = 12,
  String activeEventId = _eventId,
  String alarmEventId = _eventId,
  String? lastCmdSrcIp,
  int identifyActive = 0,
  ServoState? servoState = ServoState.closed,
  DebugCriteria? activeEventCriteria = DebugCriteria.getAway,
  BeepProfile? activeEventAnchorProfile = BeepProfile.medium,
  int todayEventCount = 1,
  int scheduleEventCount = 1,
  List<AnchorEventRecord>? events,
}) =>
    AnchorDebugTelemetry(
      version: 2,
      headerLen: 160,
      recordCount: (events ?? [_event()]).length,
      recordLen: 24,
      maxRecords: 8,
      timeValid: timeValid,
      scheduleLoaded: scheduleLoaded,
      beeping: beeping,
      beepPhaseOn: beepPhaseOn,
      buzzerCompiledOut: buzzerCompiledOut,
      motorCompiledOut: false,
      wifiConnected: wifiConnected,
      wifiFallbackArmed: wifiFallbackArmed,
      bleQuiesced: bleQuiesced,
      bleAdvertising: bleAdvertising,
      radioIsWifi: radioIsWifi,
      servoOpen: false,
      dockSupported: dockSupported,
      clockRestored: clockRestored,
      beepCapReached: beepCapReached,
      anchorInActiveEvent: true,
      lastCmdRemoved: lastCmd == AnchorCmd.watchRemoved,
      lastCmdWorn: lastCmd == AnchorCmd.watchWorn,
      lastCmdAccepted: lastCmdResult == AnchorCmdResult.applied,
      lastCmdNotMine: lastCmdResult == AnchorCmdResult.notMine,
      lastCmdMalformed: lastCmdResult == AnchorCmdResult.malformed,
      lastCmdOverBle: lastCmdTransport == AnchorCmdTransport.ble,
      lastCmdOverUdp: lastCmdTransport == AnchorCmdTransport.udp,
      noCommandYet: noCommandYet,
      identifyActiveFlag: identifyActive != 0,
      csReflectorBuilt: true,
      csProceduresActive: true,
      schedulePersisted: true,
      rejectionWasClock: rejectionWasClock,
      profileDefaulted: profileDefaulted,
      alarmWindowClosed: false,
      ackSent: ackSent,
      clockSource: clockSource,
      beepProfile: beepProfile,
      lastCmd: lastCmd,
      lastCmdResult: lastCmdResult,
      lastCmdReason: lastCmdReason,
      lastCmdTransport: lastCmdTransport,
      radioPhase:
          radioIsWifi ? RadioPhase.wifi : RadioPhase.ble,
      csReflectorState: CsReflectorState.procedures,
      bootCount: bootCount,
      maxBeepMinutes: maxBeepMinutes,
      localMinute: localMinute,
      sinceLastCmdS: sinceLastCmdS,
      beepingForS: beepingForS,
      beepCapRemainingS: beepCapRemainingS,
      todayEventCount: todayEventCount,
      scheduleEventCount: scheduleEventCount,
      activeEventIndex: 0,
      activeEventStartMin: 420,
      activeEventEndMin: 510,
      rejectUnknownEvent: rejectUnknownEvent,
      rejectOutsideWindow: rejectOutsideWindow,
      rejectNegated: rejectNegated,
      rejectNotInBeepList: rejectNotInBeepList,
      rejectMalformed: rejectMalformed,
      acceptedApplied: acceptedApplied,
      capStops: capStops,
      beepCycles: 0,
      wifiDwellRemainingS: 0,
      utcNow: utcNow,
      tzOffsetMin: tzOffsetMin,
      peerLinkCount: peerLinkCount,
      dockState: dockState,
      uptimeMs: 7654321,
      ownLastIp: '192.168.1.65',
      beepStartedAtMs: 7640000,
      radioPhaseSinceMs: 7650000,
      scheduleCrc: 0xA1B2C3D4,
      activeEventId: activeEventId,
      alarmEventId: alarmEventId,
      lastCmdEventId: _eventId,
      lastCmdWatchUuid: '3f3f3f3f-3f3f-3f3f-3f3f-3f3f3f3f3f3f',
      lastCmdSrcIp: lastCmdSrcIp,
      identifyActive: identifyActive,
      servoState: servoState,
      activeEventCriteria: activeEventCriteria,
      activeEventAnchorProfile: activeEventAnchorProfile,
      snapshotSeq: 7,
      reserved1: 0,
      events: events ?? [_event()],
    );

BeepCondition _check(BeepConditionGroup group, String label) =>
    group.conditions.firstWhere((c) => c.label == label,
        orElse: () => throw StateError(
            'no row "$label" in "${group.title}" (rows: '
            '${group.conditions.map((c) => c.label).join(' | ')})'));

void main() {
  // ── Group A ───────────────────────────────────────────────────────────────

  group('watch buzzes / vibrates (§3.1)', () {
    test('Sunrise Lock worn+NEAR: the watch is buzzing', () {
      final w = _watch();
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.watchGroup.verdict, 'would beep now');
      expect(report.warning, isNull);

      final criterion = _check(report.watchGroup, 'the criterion is not met');
      expect(criterion.state, ConditionState.met);
      expect(criterion.detail, contains('condition_met = 0'));
      expect(criterion.detail, contains('1.42 m'));
      expect(criterion.detail, contains('NEAR'));
      expect(criterion.detail, contains('2 bursts ≥ near threshold 2.00 m'));
      expect(criterion.detail, contains('GET_AWAY + NEAR → not met'));

      final sentence = buildProximityInterpretation(w);
      expect(sentence, contains('GET_AWAY'));
      expect(sentence, contains('anchor 75757575'));
      expect(sentence, contains('measured 1.42 m'));
      expect(sentence, contains('2 bursts ≥ near threshold 2.00 m'));
      expect(sentence, contains('→ not met → watch is buzzing'));
      expect(sentence, contains("Ranging peer is the event's anchor"));
    });

    test('Sunrise Lock worn+AWAY: the commitment is met', () {
      final w = _watch(
        conditionMet: true,
        verdictNear: false,
        lastDecision: WatchDecision.getAwayAway,
        nearRun: 0,
        awayRun: 4,
        motorOn: false,
        buzzerOn: false,
        profileActive: false,
        anchors: [
          _record(
            distanceCm: 312,
            ifftCm: 312,
            phaseSlopeCm: 330,
            rttCm: 350,
            verdict: ProxVerdict.away,
            abstainReason: null,
          ),
        ],
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.watchGroup.verdict,
          'would not, first failing: the criterion is not met');
      final sentence = buildProximityInterpretation(w);
      expect(sentence, contains('measured 3.12 m'));
      expect(sentence, contains('AWAY'));
      expect(sentence, contains('4 bursts ≥ away threshold 3.50 m'));
      expect(sentence, contains('→ met → watch silent'));
    });

    test('abstaining GET_AWAY fails open (met); STAY_NEAR fails closed', () {
      final getAway = _watch(
        failsafe: true,
        abstainRun: 6,
        conditionMet: true,
        verdictHave: false,
        verdictNear: false,
        lastDecision: WatchDecision.getAwayAbstain,
        anchors: [
          _record(
            distanceCm: null,
            ifftCm: null,
            phaseSlopeCm: null,
            rttCm: null,
            ageS: null,
            sampleCount: 0,
            verdict: ProxVerdict.abstain,
            abstainReason: CsAbstainReason.noFreshBurst,
            ranged: false,
          ),
        ],
      );
      final getAwayRead = readCriterion(getAway);
      expect(getAwayRead.notMet, isFalse);
      expect(getAwayRead.explanation, contains('fail-safe'));
      expect(getAwayRead.explanation, contains('GET_AWAY fails open'));
      expect(getAwayRead.explanation, contains('no fresh burst'));
      final report = evaluateBeepConditions(watch: getAway, anchorId: _anchorId);
      expect(report.watchGroup.verdict,
          'would not, first failing: the criterion is not met');

      final stayNear = _watch(
        criteria: DebugCriteria.stayNear,
        failsafe: true,
        abstainRun: 6,
        conditionMet: false,
        verdictHave: false,
        verdictNear: false,
        lastDecision: WatchDecision.stayNearAbstain,
        anchors: [
          _record(verdict: ProxVerdict.abstain, distanceCm: null),
        ],
      );
      final stayRead = readCriterion(stayNear);
      expect(stayRead.notMet, isTrue);
      expect(stayRead.explanation, contains('STAY_NEAR fails closed'));
      expect(
          evaluateBeepConditions(watch: stayNear, anchorId: _anchorId)
              .watchGroup
              .verdict,
          'would beep now');
    });

    test('"buzzer compiled out" is a first-class unmet condition', () {
      // Buzzer-only profile on a build without the buzzer: nothing can sound.
      final w = _watch(
        profile: WatchProfile.buzzerOnlyNormal,
        buzzerCompiledOut: true,
        motorOn: false,
        buzzerOn: false,
        stillForS: 1450,
        worn: false,
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.watchGroup.verdict,
          'would not, first failing: build can produce this output');
      final row = _check(report.watchGroup, 'buzzer compiled out');
      expect(row.state, ConditionState.unmet);
      expect(row.informational, isFalse);
      expect(row.detail, contains('BUZZER_DISABLED'));
      expect(buildProximityInterpretation(w),
          contains('cannot sound at all'));
    });

    test('a --buzzer build with the motor out still buzzes', () {
      // Both-output profile, buzzer dead, motor alive: the output exists, so
      // the compiled-out buzzer is an advisory, not the blocker.
      final w = _watch(
        profile: WatchProfile.bothNormal,
        motorCompiledOut: true,
        motorOn: false,
        buzzerOn: true,
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.watchGroup.verdict, 'would beep now');
      final row = _check(report.watchGroup, 'motor compiled out');
      expect(row.state, ConditionState.unmet);
      expect(row.informational, isTrue);
      expect(buildProximityInterpretation(w),
          contains('watch is buzzing (motor compiled out)'));
    });

    test('donning grace and the lost-link silencing are the first failures', () {
      final grace = evaluateBeepConditions(
        watch: _watch(graceActive: true, graceRemainingS: 45),
        anchorId: _anchorId,
      );
      expect(grace.watchGroup.verdict,
          'would not, first failing: not in donning grace');
      expect(_check(grace.watchGroup, 'not in donning grace').detail,
          contains('45s remaining'));

      final silenced = evaluateBeepConditions(
        watch: _watch(
          outputSilenced: true,
          graceIsLostLink: true,
          verdictFromLostLink: true,
        ),
        anchorId: _anchorId,
      );
      expect(silenced.watchGroup.verdict,
          'would not, first failing: output is not silenced by the lost-link grace');
      expect(
          _check(silenced.watchGroup,
                  'output is not silenced by the lost-link grace')
              .detail,
          contains('lost-link grace'));
      expect(
          buildProximityInterpretation(
              _watch(outputSilenced: true, conditionMet: false))
              .contains('silenced'),
          isTrue);
    });

    test('before the first poll the criterion verdict is unknown, not wrong',
        () {
      final w = _watch(
        lastPollMet: null,
        lastDecision: WatchDecision.notEvaluated,
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.watchGroup.verdict, 'unknown');
      expect(_check(report.watchGroup, 'a poll has concluded').state,
          ConditionState.unknown);
      expect(_check(report.watchGroup, 'the criterion is not met').state,
          ConditionState.unknown);
      expect(readCriterion(w).notMet, isNull);
    });
  });

  // ── Group B ───────────────────────────────────────────────────────────────

  group('anchor beeps: watch removed (§3.2/§3.3)', () {
    test('unworn watch, alarm accepted over BLE: would beep now', () {
      final report = evaluateBeepConditions(
        watch: _watch(worn: false, escLastDeliveredCmd: EscalationCmd.watchRemoved,
            escDeliveredBle: 1),
        anchor: _anchor(),
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict, 'would beep now');
      final delivery =
          _check(report.anchorRemovedGroup, 'WATCH_REMOVED was delivered');
      expect(delivery.state, ConditionState.met);
      expect(delivery.detail, contains('over BLE'));
      expect(delivery.detail, contains('applied'));
      expect(
          _check(report.anchorRemovedGroup, 'anchor\'s last command').detail,
          contains('applied, alarm started'));
    });

    test('a worn watch never escalates', () {
      final report = evaluateBeepConditions(
        watch: _watch(worn: true),
        anchor: _anchor(beeping: false),
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: watch unworn');
    });

    test('rejected outside window because the anchor clock is 9 h slow', () {
      // Watch 08:00 local; anchor believes 17:03 (543 min out = 9 h 03).
      final a = _anchor(
        beeping: false,
        beepPhaseOn: false,
        beepCapRemainingS: 0,
        localMinute: 480 + 543,
        clockSource: ClockSource.retainedRam,
        lastCmdResult: AnchorCmdResult.notMine,
        lastCmdReason: AnchorCmdReason.outsideWindow,
        rejectionWasClock: true,
      );
      final report = evaluateBeepConditions(
        watch: _watch(worn: false),
        anchor: a,
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: window is open by the anchor clock');
      final window = _check(
          report.anchorRemovedGroup, 'window is open by the anchor clock');
      expect(window.detail, contains('outside the window'));
      expect(window.detail, contains('9 h slow'));
      final clock =
          _check(report.anchorRemovedGroup, 'clocks agree (≤ 1 min)');
      expect(clock.state, ConditionState.unmet);
      expect(clock.detail, contains('9 h 3 min apart'));
      expect(clock.detail, contains('ANCHOR CLOCK INVALID OR DISAGREES'));
      expect(
          _check(report.anchorRemovedGroup, 'anchor\'s last command').detail,
          contains('not mine: window not open on the anchor clock'));
      expect(
          _check(report.anchorRemovedGroup, 'anchor clock valid').detail,
          contains('retained RAM'));
    });

    test('refused over UDP: the anchor heard it and is not in beepAnchors',
        () {
      final w = _watch(
        worn: false,
        radioPhase: RadioPhase.wifi,
        wifiConnected: true,
        ownIpv4: '192.168.1.152',
        escPending: true,
        escPendingCmd: EscalationCmd.watchRemoved,
        escLastAckResult: EscalationAck.heardNotMine,
        ackRefused: true,
        escWifiEntries: 2,
        escAttempts: 19,
        escDeliveredUdp: 0,
        escDeliveredBle: 0,
        escSinceRequestS: 95,
      );
      final a = _anchor(
        beeping: false,
        beepPhaseOn: false,
        beepCapRemainingS: 0,
        wifiConnected: true,
        radioIsWifi: true,
        lastCmdTransport: AnchorCmdTransport.udp,
        lastCmdResult: AnchorCmdResult.notMine,
        lastCmdReason: AnchorCmdReason.notInBeepList,
        lastCmdSrcIp: '192.168.1.152',
        ackSent: true,
        rejectNotInBeepList: 1,
      );
      final report = evaluateBeepConditions(
        watch: w,
        anchor: a,
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: this anchor is in beepAnchors');
      final delivery =
          _check(report.anchorRemovedGroup, 'WATCH_REMOVED was delivered');
      expect(delivery.state, ConditionState.met,
          reason: 'the carrier worked; the validator refused');
      expect(delivery.detail, contains('over UDP'));
      final udp = _check(report.anchorRemovedGroup, 'WiFi/UDP carrier');
      expect(udp.detail, contains('attempts=19'));
      expect(udp.detail, contains('last_ack=heard, but not mine'));
      final command =
          _check(report.anchorRemovedGroup, 'anchor\'s last command');
      expect(command.detail, contains('anchor not in beepAnchors'));
      expect(command.detail, contains('ACK sent'));
      expect(command.detail, contains('from 192.168.1.152'));
    });

    test('an undelivered escalation is named as the first failure', () {
      final report = evaluateBeepConditions(
        watch: _watch(
          worn: false,
          linkUp: false,
          linkReady: false,
          escPending: true,
          escPendingCmd: EscalationCmd.watchRemoved,
          escSinceRequestS: 95,
          escDeliveredBle: 0,
          escDeliveredUdp: 0,
        ),
        anchor: _anchor(
          beeping: false,
          noCommandYet: true,
          lastCmd: AnchorCmd.none,
          lastCmdResult: null,
          lastCmdReason: null,
          lastCmdTransport: null,
          beepCapRemainingS: 0,
        ),
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: WATCH_REMOVED was delivered');
      final row =
          _check(report.anchorRemovedGroup, 'WATCH_REMOVED was delivered');
      expect(row.detail, contains('queued but undelivered'));
      expect(_check(report.anchorRemovedGroup, 'BLE carrier').detail,
          contains('link_ready=false'));
    });

    test('the anchor buzzer compiled out is a first-class unmet condition', () {
      final report = evaluateBeepConditions(
        watch: _watch(worn: false),
        anchor: _anchor(
          buzzerCompiledOut: true,
          beeping: true,
          beepPhaseOn: false,
        ),
        anchorId: _anchorId,
      );
      // The alarm state machine runs, so the first failure is the build.
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: anchor buzzer is compiled in');
      final row =
          _check(report.anchorRemovedGroup, 'anchor buzzer is compiled in');
      expect(row.state, ConditionState.unmet);
      expect(row.detail, contains('BUZZER_DISABLED'));
      expect(row.detail, contains('--buzzer'));
    });

    test('an invalid anchor clock is called out before everything else', () {
      final report = evaluateBeepConditions(
        watch: _watch(worn: false, timeValid: false),
        anchor: _anchor(
          timeValid: false,
          localMinute: null,
          clockSource: ClockSource.never,
          beeping: false,
          beepCapRemainingS: 0,
        ),
        anchorId: _anchorId,
      );
      expect(report.anchorRemovedGroup.verdict,
          'would not, first failing: anchor clock valid');
      final clock = _check(report.anchorRemovedGroup, 'anchor clock valid');
      expect(clock.detail, contains('invalid'));
      expect(clock.detail, contains('no clock source'));
      expect(_check(report.anchorRemovedGroup, 'clocks agree (≤ 1 min)').state,
          ConditionState.unknown);
    });

    test('the beep cap stopping the alarm is not met, and says so', () {
      final report = evaluateBeepConditions(
        watch: _watch(worn: false),
        anchor: _anchor(
          beepingForS: 1800,
          beepCapRemainingS: 0,
          beepCapReached: true,
        ),
        anchorId: _anchorId,
      );
      final cap = _check(report.anchorRemovedGroup, 'alarm is inside its cap');
      expect(cap.state, ConditionState.unmet);
      expect(cap.detail, contains('30-minute cap'));
      expect(cap.detail, contains('NOT persisted'));
    });

    test('no anchor telemetry leaves the anchor guards unknown', () {
      final report = evaluateBeepConditions(
          watch: _watch(worn: false), anchorId: _anchorId);
      expect(report.anchorRemovedGroup.verdict, 'unknown');
      expect(_check(report.anchorRemovedGroup, 'anchor clock valid').detail,
          contains('anchor telemetry not read yet'));
    });
  });

  // ── Group C ───────────────────────────────────────────────────────────────

  group('anchor dock alarm (§2.7/§3.4)', () {
    test('dock unsupported is one honest row, not a wall of unknowns', () {
      final report = evaluateBeepConditions(
        watch: _watch(),
        anchor: _anchor(dockSupported: false, dockState: null),
        anchorId: _anchorId,
      );
      final g = report.anchorDockGroup;
      expect(g.conditions, hasLength(1));
      expect(g.conditions.single.label, 'not supported by this firmware');
      expect(g.conditions.single.state, ConditionState.unmet);
      expect(g.conditions.single.detail, contains('dock_supported = 0'));
      expect(g.conditions.single.detail, contains('PHONE_AWAY'));
      expect(g.verdict, 'would not, first failing: not supported by this firmware');
    });

    test('without anchor telemetry the dock support itself is unknown', () {
      final report = evaluateBeepConditions(watch: _watch(), anchorId: _anchorId);
      expect(report.anchorDockGroup.conditions, hasLength(1));
      expect(report.anchorDockGroup.conditions.single.state,
          ConditionState.unknown);
      expect(report.anchorDockGroup.verdict, 'unknown');
    });
  });

  // ── Identity ──────────────────────────────────────────────────────────────

  group('identity check (§1.7)', () {
    test('ranging a different anchor is loud everywhere', () {
      final w = _watch(
        linkPeerKind: LinkPeerKind.otherAnchor,
        identityConflict: true,
        linkPeerIsEventAnchor: false,
        linkPeerUuid: _otherAnchorId,
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.warning, contains('DIFFERENT ANCHOR'));
      expect(report.warning, contains('75757575'));
      expect(report.warning, contains('9e1c0d21'));
      final sentence = buildProximityInterpretation(w);
      expect(sentence, contains('DIFFERENT ANCHOR THAN THE EVENT NAMES'));
      expect(sentence, contains('the distance is about the wrong box'));
    });

    test('identity unknown is stated, not guessed', () {
      final w = _watch(
        linkPeerKind: LinkPeerKind.unknown,
        linkPeerKnown: false,
        linkPeerUuid: '',
        linkPeerAddr: null,
        linkPeerAddrType: null,
      );
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(report.warning, isNull);
      expect(buildProximityInterpretation(w),
          contains('cannot tell which anchor it is ranging'));
    });
  });

  // ── Degenerate inputs and the informational mechanism ─────────────────────

  group('missing telemetry', () {
    test('every group is unknown with "not read yet"', () {
      final report = evaluateBeepConditions();
      expect(report.groups, hasLength(3));
      expect(report.warning, isNull);
      for (final g in report.groups) {
        expect(g.conditions, isNotEmpty);
        expect(
            g.conditions.every((c) => c.state == ConditionState.unknown),
            isTrue);
        expect(g.conditions.first.detail, contains('not read'));
        expect(g.verdict, 'unknown');
      }
      expect(buildProximityInterpretation(null),
          contains('No watch snapshot'));
    });

    test('a watch with no active window explains the absence', () {
      final w = _watch(criteria: null, activityState: DebugActivityState.dormant);
      final report = evaluateBeepConditions(watch: w, anchorId: _anchorId);
      expect(_check(report.watchGroup, 'an event is active with a known criterion')
          .state, ConditionState.unmet);
      expect(_check(report.watchGroup, 'a window is being enforced').state,
          ConditionState.unmet);
      expect(report.watchGroup.verdict,
          'would not, first failing: a window is being enforced');
      expect(buildProximityInterpretation(w), contains('No active window'));
      expect(readCriterion(w).notMet, isNull);
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

    test('the real group keeps outcome rows out of its verdict', () {
      // Every guard holds, the anchor is simply not beeping *yet*: the verdict
      // must not become "first failing: beeping now".
      final report = evaluateBeepConditions(
        watch: _watch(worn: false),
        anchor: _anchor(beeping: false, beepCapRemainingS: 0),
        anchorId: _anchorId,
      );
      final g = report.anchorRemovedGroup;
      expect(_check(g, 'alarm was accepted').state, ConditionState.unmet);
      expect(g.firstUnmet?.label, 'alarm was accepted');
      expect(_check(g, 'beeping now').informational, isTrue);
    });
  });
}
