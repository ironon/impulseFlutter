// Debug Telemetry v2 decoder tests (contract §4.1–§4.4, watch `…001D` and
// anchor `…0020`).
//
// Every payload here is built by hand, field by field, from the contract's
// offset tables — deliberately NOT by reusing an encoder (there is none) or the
// decoder. If an offset, width or endianness drifts, these tests fail rather
// than agreeing with the mistake.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/debug_telemetry.dart';

const int _watchHeader = 180; // R7: 176 + still/motion thresholds
const int _watchRecord = 32;
const int _anchorHeader = 160;
const int _anchorRecord = 24;

/// A UUID in printed order: sixteen copies of [fill].
List<int> _uuid(int fill) => List<int>.filled(16, fill & 0xFF);

/// Little-endian writers. These are the only shared helpers: they encode the
/// contract's rules (LE, and nothing else), not any field's position.
class _Bytes {
  final Uint8List b;
  _Bytes(int length) : b = Uint8List(length);

  void u8(int off, int v) => b[off] = v & 0xFF;

  void u16(int off, int v) {
    b[off] = v & 0xFF;
    b[off + 1] = (v >> 8) & 0xFF;
  }

  void i16(int off, int v) => u16(off, v & 0xFFFF);

  void u32(int off, int v) {
    for (int i = 0; i < 4; i++) {
      b[off + i] = (v >> (8 * i)) & 0xFF;
    }
  }

  void raw(int off, List<int> v) {
    for (int i = 0; i < v.length; i++) {
      b[off + i] = v[i] & 0xFF;
    }
  }

  Uint8List get bytes => b;
}

class _AnchorRec {
  final int uuidFill;
  final int distanceCm;
  final int ifftCm;
  final int phaseSlopeCm;
  final int rttCm;
  final int ageS;
  final int sampleCount;
  final int verdict;
  final int abstainReason;
  final int flags;
  final int quality;

  const _AnchorRec({
    this.uuidFill = 0x75,
    this.distanceCm = 142,
    this.ifftCm = 142,
    this.phaseSlopeCm = 155,
    this.rttCm = 190,
    this.ageS = 2,
    this.sampleCount = 10,
    this.verdict = 0,
    this.abstainReason = 0,
    this.flags = 0x27,
    this.quality = 0xFF,
  });
}

/// Builds a `…001D` payload from the §4.1/§4.2 tables.
Uint8List _watchPayload({
  int version = 2,
  int? headerLen,
  int? recordLen,
  int maxRecords = 10,
  int activityState = 3,
  int criteria = 0,
  int profile = 4,
  int flags0 = 0x00,
  int flags1 = 0x00,
  int flags2 = 0x00,
  int flags3 = 0x00,
  int wornSource = 1,
  int ringState = 3,
  int escPendingCmd = 1,
  int escLastDeliveredCmd = 2,
  int proxLastResult = 2,
  int escLastAckResult = 1,
  int csAbstainReason = 3,
  int lastPollMet = 0,
  int lastDecision = 7,
  int nearRun = 2,
  int awayRun = 1,
  int abstainRun = 4,
  int integrityPendingCount = 3,
  int beepAnchorCount = 2,
  int csLastQuality = 77,
  int linkLastDisconnectReason = 0x13,
  int linkPeerKind = 2,
  int clockSource = 1,
  int localMinute = 480,
  int eventStartMin = 420,
  int eventEndMin = 510,
  int nearEnterCm = 200,
  int awayEnterCm = 350,
  int donningGraceS = 600,
  int graceRemainingS = 0,
  int pollIntervalS = 60,
  int sinceLastPollS = 12,
  int sinceLastBurstS = 2,
  int stillForS = 1450,
  int wornDiag = 980,
  int stillThresholdS = 300,
  int motionThresholdMms2 = 400,
  int eventIndex = 0,
  int bootCount = 37,
  int csBurstCount = 11,
  int csRejectedRange = 1,
  int csRejectedQuality = 0,
  int csSuspectRelay = 0,
  int csMissingIfft = 0,
  int csDistanceCm = 142,
  int csIfftCm = 142,
  int csPhaseSlopeCm = 155,
  int csRttCm = 190,
  int linkConnectAttempts = 3,
  int linkConnectFailures = 1,
  int escSinceRequestS = 0xFFFF,
  int escDeliveredBle = 1,
  int escDeliveredUdp = 2,
  int escWifiEntries = 2,
  int escAttempts = 19,
  int integritySettleWindowMin = 120,
  int passAllowance = 4,
  int passRemaining = 3,
  int utcNow = 1788091200,
  int tzOffsetMin = -240,
  int uptimeMs = 1234567,
  int linkConnectedAtMs = 1179567,
  int radioPhaseSinceMs = 1234000,
  int radioPhaseDwellRemainingS = 42,
  int radioPhase = 1,
  List<int> activeEventId = const [],
  List<int> eventAnchorId = const [],
  List<int> linkPeerUuid = const [],
  List<int> linkPeerAddr = const [0xD0, 0x30, 0x2F, 0x4C, 0x7E, 0xC5],
  int linkPeerAddrType = 1,
  int snapshotSeq = 42,
  List<int> ownIpv4 = const [0, 0, 0, 0],
  List<_AnchorRec> records = const [],
}) {
  final hdr = headerLen ?? _watchHeader;
  final rec = recordLen ?? _watchRecord;
  final d = _Bytes(hdr + records.length * rec);
  d.u8(0, version);
  d.u8(1, hdr);
  d.u8(2, records.length);
  d.u8(3, rec);
  d.u8(4, maxRecords);
  d.u8(5, activityState);
  d.u8(6, criteria);
  d.u8(7, profile);
  d.u8(8, flags0);
  d.u8(9, flags1);
  d.u8(10, flags2);
  d.u8(11, flags3);
  d.u8(12, wornSource);
  d.u8(13, ringState);
  d.u8(14, escPendingCmd);
  d.u8(15, escLastDeliveredCmd);
  d.u8(16, proxLastResult);
  d.u8(17, escLastAckResult);
  d.u8(18, csAbstainReason);
  d.u8(19, lastPollMet);
  d.u8(20, lastDecision);
  d.u8(21, nearRun);
  d.u8(22, awayRun);
  d.u8(23, abstainRun);
  d.u8(24, integrityPendingCount);
  d.u8(25, beepAnchorCount);
  d.u8(26, csLastQuality);
  d.u8(27, linkLastDisconnectReason);
  d.u8(28, linkPeerKind);
  d.u8(29, clockSource); // R7: was reserved0
  d.u16(30, localMinute);
  d.u16(32, eventStartMin);
  d.u16(34, eventEndMin);
  d.u16(36, nearEnterCm);
  d.u16(38, awayEnterCm);
  d.u16(40, donningGraceS);
  d.u16(42, graceRemainingS);
  d.u16(44, pollIntervalS);
  d.u16(46, sinceLastPollS);
  d.u16(48, sinceLastBurstS);
  d.u16(50, stillForS);
  d.i16(52, wornDiag);
  d.u16(54, eventIndex);
  d.u16(56, bootCount);
  d.u16(58, csBurstCount);
  d.u16(60, csRejectedRange);
  d.u16(62, csRejectedQuality);
  d.u16(64, csSuspectRelay);
  d.u16(66, csMissingIfft);
  d.u16(68, csDistanceCm);
  d.u16(70, csIfftCm);
  d.u16(72, csPhaseSlopeCm);
  d.u16(74, csRttCm);
  d.u16(76, linkConnectAttempts);
  d.u16(78, linkConnectFailures);
  d.u16(80, escSinceRequestS);
  d.u16(82, escDeliveredBle);
  d.u16(84, escDeliveredUdp);
  d.u16(86, escWifiEntries);
  d.u16(88, integritySettleWindowMin);
  d.u8(90, passAllowance);
  d.u8(91, passRemaining);
  d.u16(92, escAttempts);
  d.u32(94, utcNow);
  d.i16(98, tzOffsetMin);
  d.u32(100, uptimeMs);
  d.u32(104, linkConnectedAtMs);
  d.u32(108, radioPhaseSinceMs);
  d.u16(112, radioPhaseDwellRemainingS);
  d.u8(114, radioPhase);
  d.u8(115, 0); // reserved2
  d.raw(116, activeEventId.isEmpty
      ? List<int>.filled(16, 0)
      : activeEventId);
  d.raw(132, eventAnchorId.isEmpty
      ? List<int>.filled(16, 0)
      : eventAnchorId);
  d.raw(148, linkPeerUuid.isEmpty
      ? List<int>.filled(16, 0)
      : linkPeerUuid);
  d.raw(164, linkPeerAddr);
  d.u8(170, linkPeerAddrType);
  d.u8(171, snapshotSeq);
  d.raw(172, ownIpv4);
  if (hdr >= 180) {
    d.u16(176, stillThresholdS);   // R7
    d.u16(178, motionThresholdMms2); // R7
  }
  for (int i = 0; i < records.length; i++) {
    final o = hdr + i * rec;
    final r = records[i];
    d.raw(o, _uuid(r.uuidFill));
    d.u16(o + 16, r.distanceCm);
    d.u16(o + 18, r.ifftCm);
    d.u16(o + 20, r.phaseSlopeCm);
    d.u16(o + 22, r.rttCm);
    d.u16(o + 24, r.ageS);
    d.u16(o + 26, r.sampleCount);
    d.u8(o + 28, r.verdict);
    d.u8(o + 29, r.abstainReason);
    d.u8(o + 30, r.flags);
    d.u8(o + 31, r.quality);
  }
  return d.bytes;
}

class _EventRec {
  final int uuidFill;
  final int startMin;
  final int endMin;
  final int criteria;
  final int flags0;
  final int flags1;

  const _EventRec({
    this.uuidFill = 0x7D,
    this.startMin = 420,
    this.endMin = 510,
    this.criteria = 0,
    this.flags0 = 0x00,
    this.flags1 = 0x00,
  });
}

/// Builds a `…0020` payload from the §4.3/§4.4 tables.
Uint8List _anchorPayload({
  int version = 2,
  int? headerLen,
  int? recordLen,
  int maxRecords = 8,
  int flags0 = 0x00,
  int flags1 = 0x00,
  int flags2 = 0x00,
  int flags3 = 0x00,
  int beepProfile = 1,
  int lastCmd = 1,
  int lastCmdResult = 0,
  int lastCmdReason = 1,
  int lastCmdTransport = 1,
  int radioPhase = 0,
  int csReflectorState = 2,
  int bootCount = 12,
  int maxBeepMinutes = 30,
  int localMinute = 480,
  int sinceLastCmdS = 12,
  int beepingForS = 12,
  int beepCapRemainingS = 1788,
  int todayEventCount = 1,
  int scheduleEventCount = 2,
  int activeEventIndex = 0,
  int activeEventStartMin = 420,
  int activeEventEndMin = 510,
  int rejectUnknownEvent = 1,
  int rejectOutsideWindow = 2,
  int rejectNegated = 3,
  int rejectNotInBeepList = 4,
  int rejectMalformed = 5,
  int acceptedApplied = 6,
  int capStops = 0,
  int beepCycles = 7,
  int wifiDwellRemainingS = 55,
  int utcNow = 1788091200,
  int tzOffsetMin = -240,
  int peerLinkCount = 1,
  int dockState = 0xFF,
  int uptimeMs = 7654321,
  List<int> ownLastIp = const [192, 168, 1, 65],
  int beepStartedAtMs = 7640000,
  int radioPhaseSinceMs = 7650000,
  int scheduleCrc = 0xA1B2C3D4,
  List<int> activeEventId = const [],
  List<int> alarmEventId = const [],
  List<int> lastCmdEventId = const [],
  List<int> lastCmdWatchUuid = const [],
  List<int> lastCmdSrcIp = const [0, 0, 0, 0],
  int identifyActive = 0,
  int servoState = 0,
  int clockSource = 1,
  int ackSent = 0,
  int activeEventCriteria = 0,
  int activeEventAnchorProfile = 1,
  int snapshotSeq = 7,
  List<_EventRec> records = const [],
}) {
  final hdr = headerLen ?? _anchorHeader;
  final rec = recordLen ?? _anchorRecord;
  final d = _Bytes(hdr + records.length * rec);
  d.u8(0, version);
  d.u8(1, hdr);
  d.u8(2, records.length);
  d.u8(3, rec);
  d.u8(4, maxRecords);
  d.u8(5, flags0);
  d.u8(6, flags1);
  d.u8(7, flags2);
  d.u8(8, flags3);
  d.u8(9, beepProfile);
  d.u8(10, lastCmd);
  d.u8(11, lastCmdResult);
  d.u8(12, lastCmdReason);
  d.u8(13, lastCmdTransport);
  d.u8(14, radioPhase);
  d.u8(15, csReflectorState);
  d.u16(16, bootCount);
  d.u16(18, maxBeepMinutes);
  d.u16(20, localMinute);
  d.u16(22, sinceLastCmdS);
  d.u16(24, beepingForS);
  d.u16(26, beepCapRemainingS);
  d.u16(28, todayEventCount);
  d.u16(30, scheduleEventCount);
  d.u16(32, activeEventIndex);
  d.u16(34, activeEventStartMin);
  d.u16(36, activeEventEndMin);
  d.u16(38, rejectUnknownEvent);
  d.u16(40, rejectOutsideWindow);
  d.u16(42, rejectNegated);
  d.u16(44, rejectNotInBeepList);
  d.u16(46, rejectMalformed);
  d.u16(48, acceptedApplied);
  d.u16(50, capStops);
  d.u16(52, beepCycles);
  d.u16(54, wifiDwellRemainingS);
  d.u32(56, utcNow);
  d.i16(60, tzOffsetMin);
  d.u8(62, peerLinkCount);
  d.u8(63, dockState);
  d.u32(64, uptimeMs);
  d.raw(68, ownLastIp);
  d.u32(72, beepStartedAtMs);
  d.u32(76, radioPhaseSinceMs);
  d.u32(80, scheduleCrc);
  d.raw(84, activeEventId.isEmpty
      ? List<int>.filled(16, 0)
      : activeEventId);
  d.raw(100, alarmEventId.isEmpty
      ? List<int>.filled(16, 0)
      : alarmEventId);
  d.raw(116, lastCmdEventId.isEmpty
      ? List<int>.filled(16, 0)
      : lastCmdEventId);
  d.raw(132, lastCmdWatchUuid.isEmpty
      ? List<int>.filled(16, 0)
      : lastCmdWatchUuid);
  d.raw(148, lastCmdSrcIp);
  d.u8(152, identifyActive);
  d.u8(153, servoState);
  d.u8(154, clockSource); // R7
  d.u8(155, ackSent & 0x01); // R7 flags4.b0
  d.u8(156, activeEventCriteria);
  d.u8(157, activeEventAnchorProfile);
  d.u8(158, snapshotSeq);
  d.u8(159, 0); // reserved1
  for (int i = 0; i < records.length; i++) {
    final o = hdr + i * rec;
    final r = records[i];
    d.raw(o, _uuid(r.uuidFill));
    d.u16(o + 16, r.startMin);
    d.u16(o + 18, r.endMin);
    d.u8(o + 20, r.criteria);
    d.u8(o + 21, r.flags0);
    d.u8(o + 22, r.flags1);
    d.u8(o + 23, 0); // reserved
  }
  return d.bytes;
}

void main() {
  group('WatchDebugTelemetry v2 header', () {
    test('decodes every §4.1 field', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(
        flags0: 0xFF,
        flags1: 0xFF,
        flags2: 0xFF,
        flags3: 0xFF,
        activeEventId: _uuid(0x11),
        eventAnchorId: _uuid(0x75),
        linkPeerUuid: _uuid(0x75),
        escSinceRequestS: 95,
        ownIpv4: const [192, 168, 1, 152],
        records: const [_AnchorRec()],
      ));

      expect(t.version, 2);
      expect(t.headerLen, _watchHeader);
      expect(t.recordCount, 1);
      expect(t.recordLen, _watchRecord);
      expect(t.maxRecords, 10);

      expect(t.activityState, DebugActivityState.enforcement);
      expect(t.criteria, DebugCriteria.getAway);
      expect(t.profile, WatchProfile.bothNormal);
      expect(t.profileLabel, contains('buzz+vibrate'));

      // flags0
      expect(t.worn, isTrue);
      expect(t.timeValid, isTrue);
      expect(t.graceActive, isTrue);
      expect(t.profileActive, isTrue);
      expect(t.conditionMet, isTrue);
      expect(t.verdictHave, isTrue);
      expect(t.verdictNear, isTrue);
      expect(t.failsafe, isTrue);

      // flags1
      expect(t.motorOn, isTrue);
      expect(t.buzzerOn, isTrue);
      expect(t.buzzerCompiledOut, isTrue);
      expect(t.motorCompiledOut, isTrue);
      expect(t.outputSilenced, isTrue);
      expect(t.linkUp, isTrue);
      expect(t.linkReady, isTrue);
      expect(t.rangingOn, isTrue);

      // flags2
      expect(t.wifiOnAir, isTrue);
      expect(t.bleQuiesced, isTrue);
      expect(t.escPending, isTrue);
      expect(t.escGaveUp, isTrue);
      expect(t.escOnWifi, isTrue);
      expect(t.wifiConnected, isTrue);
      expect(t.wifiProvisioned, isTrue);
      expect(t.ackRefused, isTrue);

      // flags3
      expect(t.linkPeerKnown, isTrue);
      expect(t.linkPeerIsEventAnchor, isTrue);
      expect(t.identityConflict, isTrue);
      expect(t.verdictFromLostLink, isTrue);
      expect(t.graceIsLostLink, isTrue);
      expect(t.hasEventAnchor, isTrue);
      expect(t.anchorProfilePresent, isTrue);
      expect(t.wifiCriteria, isTrue);

      expect(t.wornSource, WornSource.imu);
      expect(t.ringState, RingState.redSolid);
      expect(t.escPendingCmd, EscalationCmd.watchRemoved);
      expect(t.escLastDeliveredCmd, EscalationCmd.watchWorn);
      expect(t.proxLastResult, ProxResult.failProcedure);
      expect(t.escLastAckResult, EscalationAck.heardNotMine);
      expect(t.csAbstainReason, CsAbstainReason.failProcedure);
      expect(t.lastPollMet, PollMet.notMet);
      expect(t.lastDecision, WatchDecision.getAwayNear);

      expect(t.nearRun, 2);
      expect(t.awayRun, 1);
      expect(t.abstainRun, 4);
      expect(t.integrityPendingCount, 3);
      expect(t.beepAnchorCount, 2);
      expect(t.csLastQuality, 77);
      expect(t.linkLastDisconnectReason, 0x13);
      expect(t.linkPeerKind, LinkPeerKind.otherAnchor);
      expect(t.clockSource, ClockSource.flash);

      expect(t.localMinute, 480);
      expect(t.eventStartMin, 420);
      expect(t.eventEndMin, 510);
      expect(t.nearEnterCm, 200);
      expect(t.awayEnterCm, 350);
      expect(t.donningGraceS, 600);
      expect(t.graceRemainingS, 0);
      expect(t.pollIntervalS, 60);
      expect(t.sinceLastPollS, 12);
      expect(t.sinceLastBurstS, 2);
      expect(t.stillForS, 1450);
      expect(t.wornDiag, 980);
      expect(t.stillThresholdS, 300);
      expect(t.motionThresholdMms2, 400);
      expect(t.eventIndex, 0);
      expect(t.bootCount, 37);

      expect(t.csBurstCount, 11);
      expect(t.csRejectedRange, 1);
      expect(t.csRejectedQuality, 0);
      expect(t.csSuspectRelay, 0);
      expect(t.csMissingIfft, 0);
      expect(t.csDistanceCm, 142);
      expect(t.csIfftCm, 142);
      expect(t.csPhaseSlopeCm, 155);
      expect(t.csRttCm, 190);

      expect(t.linkConnectAttempts, 3);
      expect(t.linkConnectFailures, 1);
      expect(t.escSinceRequestS, 95);
      expect(t.escDeliveredBle, 1);
      expect(t.escDeliveredUdp, 2);
      expect(t.escWifiEntries, 2);
      expect(t.escAttempts, 19);
      expect(t.integritySettleWindowMin, 120);
      expect(t.passAllowance, 4);
      expect(t.passRemaining, 3);

      expect(t.utcNow, 1788091200);
      expect(t.tzOffsetMin, -240);
      expect(t.uptimeMs, 1234567);
      expect(t.linkConnectedAtMs, 1179567);
      expect(t.radioPhaseSinceMs, 1234000);
      expect(t.radioPhaseDwellRemainingS, 42);
      expect(t.radioPhase, RadioPhase.wifi);

      expect(t.activeEventId, '11111111-1111-1111-1111-111111111111');
      expect(t.eventAnchorId, '75757575-7575-7575-7575-757575757575');
      expect(t.linkPeerUuid, t.eventAnchorId);
      expect(t.linkPeerAddr, 'D0:30:2F:4C:7E:C5');
      expect(t.linkPeerAddrType, LinkPeerAddrType.randomStatic);
      expect(t.snapshotSeq, 42);
      expect(t.ownIpv4, '192.168.1.152');
      expect(t.hasActiveEvent, isTrue);
      expect(t.watchLocalTime, isNotNull);
      expect(t.watchLocalTime!.hour, 8); // 12:00Z − 4 h

      expect(t.anchors, hasLength(1));
      final r = t.anchors.single;
      expect(r.anchorUuid, '75757575-7575-7575-7575-757575757575');
      expect(r.distanceCm, 142);
      expect(r.distanceM, closeTo(1.42, 1e-9));
      expect(r.distanceLabel, '1.42 m');
      expect(r.ifftCm, 142);
      expect(r.phaseSlopeCm, 155);
      expect(r.rttCm, 190);
      expect(r.ageS, 2);
      expect(r.sampleCount, 10);
      expect(r.verdict, ProxVerdict.near);
      expect(r.abstainReason, CsAbstainReason.ok);
      expect(r.isEventAnchor, isTrue);
      expect(r.inBeepList, isTrue);
      expect(r.isLinkPeer, isTrue);
      expect(r.identityConflict, isFalse);
      expect(r.ipKnown, isFalse);
      expect(r.ranged, isTrue);
      expect(r.quality, isNull);
      expect(t.liveRangedRecord, same(r));
    });

    test('all-zero flag bytes decode as all-false', () {
      final t = WatchDebugTelemetry.decode(_watchPayload());
      expect(t.worn || t.timeValid || t.graceActive || t.conditionMet, isFalse);
      expect(t.motorOn || t.buzzerOn || t.linkUp || t.rangingOn, isFalse);
      expect(t.wifiConnected || t.escPending || t.ackRefused, isFalse);
      expect(t.identityConflict || t.hasEventAnchor, isFalse);
      expect(t.anchors, isEmpty);
    });

    test('record_count 0 and the 10-record maximum', () {
      expect(WatchDebugTelemetry.decode(_watchPayload()).anchors, isEmpty);

      final max = WatchDebugTelemetry.decode(_watchPayload(
        records: [
          for (int i = 0; i < 10; i++)
            _AnchorRec(uuidFill: 0x10 + i, distanceCm: 100 + i),
        ],
      ));
      expect(max.anchors, hasLength(10));
      expect(max.anchors.last.anchorUuid, startsWith('19191919'));
      expect(max.anchors.last.distanceCm, 109);
    });

    test('records are found from header_len and record_len, not constants',
        () {
      // Widen the header by 4 bytes; the record must move with it.
      final base = _watchPayload(records: const [_AnchorRec(distanceCm: 321)]);
      final padded = <int>[
        ...base.sublist(0, _watchHeader),
        0xAA, 0xBB, 0xCC, 0xDD,
        ...base.sublist(_watchHeader),
      ]..[1] = _watchHeader + 4;
      final t = WatchDebugTelemetry.decode(padded);
      expect(t.headerLen, _watchHeader + 4);
      expect(t.anchors.single.distanceCm, 321);
    });

    test('trailing bytes past the last record are ignored', () {
      final bytes = <int>[
        ..._watchPayload(records: const [_AnchorRec(distanceCm: 99)]),
        0xDE, 0xAD, 0xBE, 0xEF,
      ];
      final t = WatchDebugTelemetry.decode(bytes);
      expect(t.anchors.single.distanceCm, 99);
    });
  });

  group('WatchDebugTelemetry v2 sentinels and enums', () {
    test('0xFFFF names, 0xFFFFFFFF timestamps and 0xFF bytes map to null', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(
        criteria: 0xFF,
        profile: 0xFF,
        ringState: 0xFF,
        proxLastResult: 0xFF,
        escLastAckResult: 0xFF,
        csAbstainReason: 0xFF,
        lastPollMet: 0xFF,
        lastDecision: 0xFF,
        csLastQuality: 0xFF,
        linkLastDisconnectReason: 0xFF,
        localMinute: 0xFFFF,
        eventStartMin: 0xFFFF,
        eventEndMin: 0xFFFF,
        sinceLastPollS: 0xFFFF,
        sinceLastBurstS: 0xFFFF,
        stillForS: 0xFFFF,
        wornDiag: 0x7FFF,
        eventIndex: 0xFFFF,
        csDistanceCm: 0xFFFF,
        csIfftCm: 0xFFFF,
        csPhaseSlopeCm: 0xFFFF,
        csRttCm: 0xFFFF,
        escSinceRequestS: 0xFFFF,
        utcNow: 0xFFFFFFFF,
        linkConnectedAtMs: 0xFFFFFFFF,
        radioPhaseSinceMs: 0xFFFFFFFF,
        linkPeerAddr: const [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
        linkPeerAddrType: 0xFF,
        clockSource: 0xFF,
        stillThresholdS: 0,
        motionThresholdMms2: 0,
      ));
      expect(t.criteria, isNull);
      expect(t.profile, isNull);
      expect(t.profileLabel, 'none');
      expect(t.ringState, isNull);
      expect(t.proxLastResult, isNull);
      expect(t.escLastAckResult, isNull);
      expect(t.csAbstainReason, isNull);
      expect(t.lastPollMet, isNull);
      expect(t.lastDecision, isNull);
      expect(t.csLastQuality, isNull);
      expect(t.linkLastDisconnectReason, isNull);
      expect(t.localMinute, isNull);
      expect(t.eventStartMin, isNull);
      expect(t.eventEndMin, isNull);
      expect(t.sinceLastPollS, isNull);
      expect(t.sinceLastBurstS, isNull);
      expect(t.stillForS, isNull);
      expect(t.wornDiag, isNull);
      expect(t.eventIndex, isNull);
      expect(t.csDistanceCm, isNull);
      expect(t.csIfftCm, isNull);
      expect(t.csPhaseSlopeCm, isNull);
      expect(t.csRttCm, isNull);
      expect(t.escSinceRequestS, isNull);
      expect(t.utcNow, isNull);
      expect(t.linkConnectedAtMs, isNull);
      expect(t.radioPhaseSinceMs, isNull);
      expect(t.linkPeerAddr, isNull);
      expect(t.linkPeerAddrType, isNull);
      expect(t.clockSource, isNull);
      expect(t.stillThresholdS, isNull);
      expect(t.motionThresholdMms2, isNull);
      expect(t.watchLocalTime, isNull);
      expect(t.hasActiveEvent, isFalse);
    });

    test('all-zero UUIDs and 0.0.0.0 map to empty/none', () {
      final t = WatchDebugTelemetry.decode(_watchPayload());
      expect(t.activeEventId, isEmpty);
      expect(t.eventAnchorId, isEmpty);
      expect(t.linkPeerUuid, isEmpty);
      expect(t.ownIpv4, isNull);
    });

    test('a value outside an enum becomes unknown(raw), not a guess', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(
        criteria: 9,
        lastDecision: 40,
        linkPeerKind: 6,
        wornSource: 4,
        radioPhase: 3,
        clockSource: 9,
      ));
      expect(t.criteria, isNotNull);
      expect(t.criteria!.known, isFalse);
      expect(t.criteria!.raw, 9);
      expect(t.criteria!.label, 'UNKNOWN');
      expect(t.lastDecision!.known, isFalse);
      expect(t.lastDecision!.raw, 40);
      expect(t.lastDecision!.met, isNull);
      expect(t.linkPeerKind.known, isFalse);
      expect(t.linkPeerKind.raw, 6);
      expect(t.wornSource.known, isFalse);
      expect(t.radioPhase.known, isFalse);
      expect(t.clockSource!.known, isFalse);
      expect(t.clockSource!.raw, 9);
    });

    test('record verdict 0xFF is NOT_RANGED and its reason 0xFE is not an enum',
        () {
      final t = WatchDebugTelemetry.decode(_watchPayload(records: const [
        _AnchorRec(
          distanceCm: 0xFFFF,
          ifftCm: 0xFFFF,
          phaseSlopeCm: 0xFFFF,
          rttCm: 0xFFFF,
          ageS: 0xFFFF,
          sampleCount: 0,
          verdict: 0xFF,
          abstainReason: 0xFE,
          flags: 0x02,
          quality: 0xFF,
        ),
      ]));
      final r = t.anchors.single;
      expect(r.verdict, ProxVerdict.notRanged);
      expect(r.verdict.ranged, isFalse);
      expect(r.distanceCm, isNull);
      expect(r.distanceLabel, 'not ranged');
      expect(r.ageS, isNull);
      expect(r.abstainReason, isNull);
      expect(r.inBeepList, isTrue);
      expect(r.isLinkPeer, isFalse);
      expect(t.liveRangedRecord, isNull);
    });

    test('decisions carry their own met/unmet answer', () {
      expect(WatchDecision.getAwayNear.met, isFalse);
      expect(WatchDecision.getAwayAway.met, isTrue);
      expect(WatchDecision.getAwayAbstain.met, isTrue);
      expect(WatchDecision.stayNearAbstain.met, isFalse);
      expect(WatchDecision.phoneAwayUnmet.met, isFalse);
      expect(WatchDecision.notEvaluated.met, isNull);
      expect(WatchDecision.lostLinkAway.met, isNull);
    });
  });

  group('WatchDebugTelemetry v2 rejection', () {
    test('an unknown version is a clear error, never garbage', () {
      expect(
        () => WatchDebugTelemetry.decode(_watchPayload(version: 1)),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'unsupported telemetry version 1')),
      );
      expect(
        () => WatchDebugTelemetry.decode(_watchPayload(version: 3)),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'unsupported telemetry version 3')),
      );
    });

    test('short and structurally impossible payloads are rejected', () {
      expect(() => WatchDebugTelemetry.decode(const []), throwsFormatException);
      expect(
          () => WatchDebugTelemetry.decode(const [2, 176, 0]), throwsFormatException);
      expect(
          () => WatchDebugTelemetry.decode(_watchPayload().sublist(0, 175)),
          throwsFormatException);
      expect(
        () => WatchDebugTelemetry.decode(
            Uint8List.fromList(_watchPayload())..[1] = 100),
        throwsFormatException,
        reason: 'header_len smaller than the v2 header cannot be decoded',
      );
      expect(
        () => WatchDebugTelemetry.decode(
            _watchPayload(records: const [_AnchorRec()]).sublist(0, 176)),
        throwsFormatException,
        reason: 'declares a record it does not carry',
      );
      expect(
        () => WatchDebugTelemetry.decode(
            Uint8List.fromList(_watchPayload(records: const [_AnchorRec()]))
              ..[3] = 8),
        throwsFormatException,
        reason: 'record_len narrower than the v2 record cannot be decoded',
      );
      expect(
        () => WatchDebugTelemetry.decode(_watchPayload(
            records: [for (int i = 0; i < 11; i++) const _AnchorRec()])),
        throwsFormatException,
        reason: 'record_count above max_records',
      );
    });
  });

  group('AnchorDebugTelemetry v2 header', () {
    test('decodes every §4.3 field', () {
      final t = AnchorDebugTelemetry.decode(_anchorPayload(
        flags0: 0xFF,
        flags1: 0xFF,
        flags2: 0xFF,
        flags3: 0xFF,
        activeEventId: _uuid(0x7D),
        alarmEventId: _uuid(0x7D),
        lastCmdEventId: _uuid(0x7D),
        lastCmdWatchUuid: _uuid(0x3F),
        lastCmdSrcIp: const [192, 168, 1, 7],
        records: const [_EventRec(
          flags0: 0x1A, flags1: 0x05, criteria: 0, endMin: 510)],
      ));

      expect(t.version, 2);
      expect(t.headerLen, _anchorHeader);
      expect(t.recordCount, 1);
      expect(t.recordLen, _anchorRecord);
      expect(t.maxRecords, 8);

      expect(t.timeValid, isTrue);
      expect(t.scheduleLoaded, isTrue);
      expect(t.beeping, isTrue);
      expect(t.beepPhaseOn, isTrue);
      expect(t.buzzerCompiledOut, isTrue);
      expect(t.motorCompiledOut, isTrue);
      expect(t.wifiConnected, isTrue);
      expect(t.wifiFallbackArmed, isTrue);

      expect(t.bleQuiesced, isTrue);
      expect(t.bleAdvertising, isTrue);
      expect(t.radioIsWifi, isTrue);
      expect(t.servoOpen, isTrue);
      expect(t.dockSupported, isTrue);
      expect(t.clockRestored, isTrue);
      expect(t.beepCapReached, isTrue);
      expect(t.anchorInActiveEvent, isTrue);

      expect(t.lastCmdRemoved, isTrue);
      expect(t.lastCmdWorn, isTrue);
      expect(t.lastCmdAccepted, isTrue);
      expect(t.lastCmdNotMine, isTrue);
      expect(t.lastCmdMalformed, isTrue);
      expect(t.lastCmdOverBle, isTrue);
      expect(t.lastCmdOverUdp, isTrue);
      expect(t.noCommandYet, isTrue);

      expect(t.identifyActiveFlag, isTrue);
      expect(t.csReflectorBuilt, isTrue);
      expect(t.csProceduresActive, isTrue);
      expect(t.schedulePersisted, isTrue);
      expect(t.rejectionWasClock, isTrue);
      expect(t.profileDefaulted, isTrue);
      expect(t.alarmWindowClosed, isTrue);

      expect(t.beepProfile, BeepProfile.medium);
      expect(t.lastCmd, AnchorCmd.watchRemoved);
      expect(t.lastCmdResult, AnchorCmdResult.applied);
      expect(t.lastCmdReason, AnchorCmdReason.started);
      expect(t.lastCmdTransport, AnchorCmdTransport.ble);
      expect(t.radioPhase, RadioPhase.ble);
      expect(t.csReflectorState, CsReflectorState.procedures);

      expect(t.bootCount, 12);
      expect(t.maxBeepMinutes, 30);
      expect(t.localMinute, 480);
      expect(t.sinceLastCmdS, 12);
      expect(t.beepingForS, 12);
      expect(t.beepCapRemainingS, 1788);
      expect(t.todayEventCount, 1);
      expect(t.scheduleEventCount, 2);
      expect(t.activeEventIndex, 0);
      expect(t.activeEventStartMin, 420);
      expect(t.activeEventEndMin, 510);

      expect(t.rejectUnknownEvent, 1);
      expect(t.rejectOutsideWindow, 2);
      expect(t.rejectNegated, 3);
      expect(t.rejectNotInBeepList, 4);
      expect(t.rejectMalformed, 5);
      expect(t.acceptedApplied, 6);
      expect(t.capStops, 0);
      expect(t.beepCycles, 7);
      expect(t.wifiDwellRemainingS, 55);

      expect(t.utcNow, 1788091200);
      expect(t.tzOffsetMin, -240);
      expect(t.peerLinkCount, 1);
      expect(t.dockState, isNull); // 0xFF = not supported
      expect(t.uptimeMs, 7654321);
      expect(t.ownLastIp, '192.168.1.65');
      expect(t.beepStartedAtMs, 7640000);
      expect(t.radioPhaseSinceMs, 7650000);
      expect(t.scheduleCrc, 0xA1B2C3D4);
      expect(t.activeEventId, '7d7d7d7d-7d7d-7d7d-7d7d-7d7d7d7d7d7d');
      expect(t.alarmEventId, t.activeEventId);
      expect(t.lastCmdEventId, t.activeEventId);
      expect(t.lastCmdWatchUuid, '3f3f3f3f-3f3f-3f3f-3f3f-3f3f3f3f3f3f');
      expect(t.lastCmdSrcIp, '192.168.1.7');
      expect(t.identifyActive, 0);
      expect(t.servoState, ServoState.closed);
      expect(t.clockSource, ClockSource.flash);
      expect(t.ackSent, isFalse);
      expect(t.activeEventCriteria, DebugCriteria.getAway);
      expect(t.activeEventAnchorProfile, BeepProfile.medium);
      expect(t.snapshotSeq, 7);
      expect(t.anchorLocalTime, isNotNull);
      expect(t.clockSourceLabel, contains('restored'));
      expect(t.beepCapExpired, isTrue, reason: 'beep_cap_reached is set');

      expect(t.events, hasLength(1));
      final e = t.events.single;
      expect(e.eventId, '7d7d7d7d-7d7d-7d7d-7d7d-7d7d7d7d7d7d');
      expect(e.startMin, 420);
      expect(e.endMin, 510);
      expect(e.criteria, DebugCriteria.getAway);
      expect(e.negatedToday, isFalse); // flags0 0x1A
      expect(e.inBeepList, isTrue);
      expect(e.isDockEvent, isFalse);
      expect(e.hasAnchorProfile, isTrue);
      expect(e.windowOpenNow, isTrue);
      expect(e.isAnchorIdTarget, isFalse);
      expect(e.clockInvalid, isFalse);
      expect(e.beepListNonempty, isFalse);
      expect(e.recurrence, Recurrence.daily); // flags1 0x05 → bits 0-1 = 1
      expect(e.supportedCriteria, isTrue);
      expect(e.activeAlarmEvent, isFalse);
    });

    test('record flags decode one bit each', () {
      final t = AnchorDebugTelemetry.decode(_anchorPayload(records: const [
        _EventRec(flags0: 0xFF),
      ]));
      final e = t.events.single;
      expect(e.negatedToday, isTrue);
      expect(e.inBeepList, isTrue);
      expect(e.isDockEvent, isTrue);
      expect(e.hasAnchorProfile, isTrue);
      expect(e.windowOpenNow, isTrue);
      expect(e.isAnchorIdTarget, isTrue);
      expect(e.clockInvalid, isTrue);
      expect(e.beepListNonempty, isTrue);
    });

    test('0 records and the 8-record maximum', () {
      expect(AnchorDebugTelemetry.decode(_anchorPayload()).events, isEmpty);
      final max = AnchorDebugTelemetry.decode(_anchorPayload(
        records: [
          for (int i = 0; i < 8; i++)
            _EventRec(uuidFill: 0x40 + i, startMin: i * 60),
        ],
      ));
      expect(max.events, hasLength(8));
      expect(max.events.last.startMin, 420);
    });

    test('records are found from header_len', () {
      final base = _anchorPayload(records: const [_EventRec(startMin: 77)]);
      final padded = <int>[
        ...base.sublist(0, _anchorHeader),
        0x01, 0x02,
        ...base.sublist(_anchorHeader),
      ]..[1] = _anchorHeader + 2;
      final t = AnchorDebugTelemetry.decode(padded);
      expect(t.events.single.startMin, 77);
    });
  });

  group('AnchorDebugTelemetry v2 sentinels and rejection', () {
    test('sentinels map to null', () {
      final t = AnchorDebugTelemetry.decode(_anchorPayload(
        beepProfile: 0xFF,
        lastCmdResult: 0xFF,
        lastCmdReason: 0xFF,
        lastCmdTransport: 0xFF,
        csReflectorState: 0xFF,
        localMinute: 0xFFFF,
        sinceLastCmdS: 0xFFFF,
        activeEventIndex: 0xFFFF,
        activeEventStartMin: 0xFFFF,
        activeEventEndMin: 0xFFFF,
        utcNow: 0xFFFFFFFF,
        ownLastIp: const [0, 0, 0, 0],
        beepStartedAtMs: 0,
        scheduleCrc: 0,
        activeEventCriteria: 0xFF,
        activeEventAnchorProfile: 0xFF,
        servoState: 0xFF,
        clockSource: 0xFF,
        lastCmdSrcIp: const [0, 0, 0, 0],
      ));
      expect(t.beepProfile, isNull);
      expect(t.lastCmdResult, isNull);
      expect(t.lastCmdReason, isNull);
      expect(t.lastCmdTransport, isNull);
      expect(t.csReflectorState, isNull);
      expect(t.localMinute, isNull);
      expect(t.sinceLastCmdS, isNull);
      expect(t.activeEventIndex, isNull);
      expect(t.activeEventStartMin, isNull);
      expect(t.activeEventEndMin, isNull);
      expect(t.utcNow, isNull);
      expect(t.ownLastIp, isNull);
      expect(t.beepStartedAtMs, isNull);
      expect(t.scheduleCrc, isNull);
      expect(t.activeEventCriteria, isNull);
      expect(t.activeEventAnchorProfile, isNull);
      expect(t.servoState, isNull);
      expect(t.clockSource, isNull);
      expect(t.lastCmdSrcIp, isNull);
      expect(t.anchorLocalTime, isNull);
      expect(t.clockSourceLabel, contains('invalid'));
    });

    test('an unknown version is a clear error', () {
      expect(
        () => AnchorDebugTelemetry.decode(_anchorPayload(version: 1)),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'unsupported telemetry version 1')),
      );
    });

    test('short and impossible payloads are rejected', () {
      expect(() => AnchorDebugTelemetry.decode(const []), throwsFormatException);
      expect(
          () => AnchorDebugTelemetry.decode(_anchorPayload().sublist(0, 159)),
          throwsFormatException);
      expect(
          () => AnchorDebugTelemetry.decode(
              Uint8List.fromList(_anchorPayload())..[1] = 40),
          throwsFormatException);
      expect(
        () => AnchorDebugTelemetry.decode(
            _anchorPayload(records: const [_EventRec()]).sublist(0, 160)),
        throwsFormatException,
      );
      expect(
        () => AnchorDebugTelemetry.decode(
            Uint8List.fromList(_anchorPayload(records: const [_EventRec()]))
              ..[3] = 12),
        throwsFormatException,
      );
      expect(
        () => AnchorDebugTelemetry.decode(_anchorPayload(
            records: [for (int i = 0; i < 9; i++) const _EventRec()])),
        throwsFormatException,
      );
    });
  });

  group('hint and truncation handling', () {
    test('the 8-byte §4.5 hint is recognised and is not a payload', () {
      final hint = <int>[2, 42, 0x04, 0x00, 0x00, 0x1B, 0x1B, 0x6A];
      expect(WatchDebugTelemetry.isHint(hint), isTrue);
      expect(AnchorDebugTelemetry.isHint(hint), isTrue);
      expect(() => WatchDebugTelemetry.decode(hint), throwsFormatException);
      expect(WatchDebugTelemetry.looksTruncated(hint), isTrue,
          reason: 'a hint is always worth one full read');

      expect(WatchDebugTelemetry.isHint([3, 1, 2, 3, 4, 5, 6, 7]), isFalse);
      expect(WatchDebugTelemetry.isHint([2, 1, 2]), isFalse);
      expect(WatchDebugTelemetry.isHint(const []), isFalse);
    });

    test('looksTruncated uses the v2 header, and rejects other versions', () {
      final full = _watchPayload(records: const [_AnchorRec()]);
      expect(WatchDebugTelemetry.looksTruncated(full), isFalse);
      expect(WatchDebugTelemetry.looksTruncated(full.sublist(0, 100)), isTrue);
      expect(WatchDebugTelemetry.looksTruncated(full.sublist(0, 180)), isTrue);
      expect(WatchDebugTelemetry.looksTruncated(const [2, 176]), isTrue);
      expect(WatchDebugTelemetry.looksTruncated(const []), isFalse);
      expect(
        WatchDebugTelemetry.looksTruncated([3, ...full.skip(1)]),
        isFalse,
        reason: 'an unknown version would fail again on a re-read',
      );

      final anchor = _anchorPayload(
          records: const [_EventRec(), _EventRec(uuidFill: 0x41)]);
      expect(AnchorDebugTelemetry.looksTruncated(anchor), isFalse);
      expect(
          AnchorDebugTelemetry.looksTruncated(anchor.sublist(0, 170)), isTrue);
      expect(AnchorDebugTelemetry.looksTruncated([1, ...anchor.skip(1)]),
          isFalse);
    });
  });

  group('fieldsMap', () {
    test('exposes the §4 names the cross-language vector file uses', () {
      final w = WatchDebugTelemetry.decode(_watchPayload(
        records: const [_AnchorRec()],
        activeEventId: _uuid(0x11),
        ownIpv4: const [10, 0, 0, 2],
      ));
      final f = w.fieldsMap();
      expect(f['version'], 2);
      expect(f['header_len'], 180);
      expect(f['record_count'], 1);
      expect(f['activity_state'], 3);
      expect(f['criteria'], 0);
      expect(f['near_enter_cm'], 200);
      expect(f['utc_now'], 1788091200);
      expect(f['own_ipv4'], '10.0.0.2');
      expect(f['active_event_id'], '11111111-1111-1111-1111-111111111111');
      expect(f['link_peer_addr'], 'D0:30:2F:4C:7E:C5');
      expect(f['worn'], isFalse);
      expect(f['time_valid'], isFalse);
      expect(f['flags0'], 0);

      final r = w.anchors.single.toRecordMap();
      expect(r['anchor_uuid'], '75757575-7575-7575-7575-757575757575');
      expect(r['distance_cm'], 142);
      expect(r['verdict'], 0);
      expect(r['is_link_peer'], isTrue);
      expect(r['flags'], 0x27);

      final a = AnchorDebugTelemetry.decode(_anchorPayload(
        records: const [_EventRec()],
      ));
      final af = a.fieldsMap();
      expect(af['version'], 2);
      expect(af['header_len'], 160);
      expect(af['last_cmd'], 1);
      expect(af['last_cmd_reason'], 1);
      expect(af['local_minute'], 480);
      expect(a.events.single.toRecordMap()['event_id'],
          '7d7d7d7d-7d7d-7d7d-7d7d-7d7d7d7d7d7d');
    });
  });
}
