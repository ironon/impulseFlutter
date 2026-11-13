// Debug Telemetry decoder tests (firmware §5.6 `…001D`, §4.4 `…0020`).
//
// Every payload here is built by hand, field by field, from the spec tables —
// deliberately NOT by reusing the production encoder (there is none) or the
// decoder. If a field offset or endianness drifts, these tests fail rather than
// agreeing with the mistake.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/debug_telemetry.dart';

/// 16 bytes in printed order for a UUID whose last group is [suffix].
List<int> _uuid(int suffix) => [
      ...List<int>.filled(15, 0),
      suffix & 0xFF,
    ];

class _AnchorRecordFixture {
  final int rssi;
  final int sinceSeenS;
  final int lastScore;
  final int flags;
  final int reserved;
  const _AnchorRecordFixture({
    this.rssi = 127,
    this.sinceSeenS = 0xFFFF,
    this.lastScore = 0,
    this.flags = 0,
    this.reserved = 0,
  });
}

/// Builds a `…001D` payload exactly from the §5.6 table (104-byte header).
Uint8List _watchPayload({
  int version = 1,
  int activityState = 3,
  int flags0 = 0x7F,
  int flags1 = 0xFF,
  int utcNow = 1767225600, // 2026-01-01T00:00:00Z
  int tzOffsetMin = -300,
  int uptimeMs = 123456,
  List<int> activeEventId = const [],
  int criteria = 1,
  int profile = 4,
  int startMin = 6 * 60 + 30,
  int endMin = 7 * 60 + 15,
  List<int> eventAnchorId = const [],
  int beepAnchorCount = 0,
  int donningGraceS = 300,
  int graceRemainingS = 0,
  int stepIdx = 2,
  int cycleCount = 9,
  int pollIntervalS = 180,
  int sinceLastPollS = 42,
  int lastPollMet = 0,
  int proxPath = 1,
  int sinceLastQueryS = 41,
  int verdictFinal = 1,
  int verdictV08 = 1,
  int verdictV2 = 2,
  int score = 150,
  int nearThr = 170,
  int nearThrSource = 1,
  int scoreFlags = 0x03,
  int emitQ8 = -512,
  int lambdaQ8 = -1234,
  int pNearU8 = 12,
  int motionState = 0,
  int pdrRateU8 = 0xFF,
  int pdrCovered = 4,
  int pdrLlr = -300,
  int dock = 0xFF,
  int gateArmed = 1,
  int gateHits = 3,
  int gateArmHits = 5,
  int gateAdmits = 1,
  int stillForS = 12,
  int livenessS = 30,
  int phoneNearForS = 0,
  int phoneToleranceS = 120,
  int farRssiThr = -75,
  int removedResult = 1,
  int sinceRemovedS = 7,
  int ssidMatch = 0xFF,
  List<_AnchorRecordFixture> anchors = const [],
}) {
  final b = ByteData(104 + anchors.length * 22);
  b.setUint8(0, version);
  b.setUint8(1, activityState);
  b.setUint8(2, flags0);
  b.setUint8(3, flags1);
  b.setUint32(4, utcNow, Endian.little);
  b.setInt16(8, tzOffsetMin, Endian.little);
  b.setUint32(10, uptimeMs, Endian.little);
  for (int i = 0; i < 16; i++) {
    b.setUint8(14 + i, i < activeEventId.length ? activeEventId[i] : 0);
  }
  b.setUint8(30, criteria);
  b.setUint8(31, profile);
  b.setUint16(32, startMin, Endian.little);
  b.setUint16(34, endMin, Endian.little);
  for (int i = 0; i < 16; i++) {
    b.setUint8(36 + i, i < eventAnchorId.length ? eventAnchorId[i] : 0);
  }
  b.setUint8(52, beepAnchorCount);
  b.setUint16(53, donningGraceS, Endian.little);
  b.setUint16(55, graceRemainingS, Endian.little);
  b.setUint8(57, stepIdx);
  b.setUint16(58, cycleCount, Endian.little);
  b.setUint16(60, pollIntervalS, Endian.little);
  b.setUint16(62, sinceLastPollS, Endian.little);
  b.setUint8(64, lastPollMet);
  b.setUint8(65, proxPath);
  b.setUint16(66, sinceLastQueryS, Endian.little);
  b.setUint8(68, verdictFinal);
  b.setUint8(69, verdictV08);
  b.setUint8(70, verdictV2);
  b.setUint8(71, score);
  b.setUint8(72, nearThr);
  b.setUint8(73, nearThrSource);
  b.setUint8(74, scoreFlags);
  b.setInt16(75, emitQ8, Endian.little);
  b.setInt16(77, lambdaQ8, Endian.little);
  b.setUint8(79, pNearU8);
  b.setUint8(80, motionState);
  b.setUint8(81, pdrRateU8);
  b.setUint8(82, pdrCovered);
  b.setInt16(83, pdrLlr, Endian.little);
  b.setUint8(85, dock);
  b.setUint8(86, gateArmed);
  b.setUint8(87, gateHits);
  b.setUint8(88, gateArmHits);
  b.setUint8(89, gateAdmits);
  b.setUint16(90, stillForS, Endian.little);
  b.setUint16(92, livenessS, Endian.little);
  b.setUint16(94, phoneNearForS, Endian.little);
  b.setUint16(96, phoneToleranceS, Endian.little);
  b.setInt8(98, farRssiThr);
  b.setUint8(99, removedResult);
  b.setUint16(100, sinceRemovedS, Endian.little);
  b.setUint8(102, ssidMatch);
  b.setUint8(103, anchors.length);
  for (int i = 0; i < anchors.length; i++) {
    final o = 104 + i * 22;
    final r = anchors[i];
    for (int j = 0; j < 15; j++) {
      b.setUint8(o + j, 0);
    }
    b.setUint8(o + 15, 0xA0 + i);
    b.setInt8(o + 16, r.rssi);
    b.setUint16(o + 17, r.sinceSeenS, Endian.little);
    b.setUint8(o + 19, r.lastScore);
    b.setUint8(o + 20, r.flags);
    b.setUint8(o + 21, r.reserved);
  }
  return b.buffer.asUint8List();
}

class _EventRecordFixture {
  final int eventSuffix;
  final int startMin;
  final int endMin;
  final int criteria;
  final int flags;
  const _EventRecordFixture({
    this.eventSuffix = 1,
    this.startMin = 6 * 60 + 30,
    this.endMin = 7 * 60 + 15,
    this.criteria = 4,
    this.flags = 0,
  });
}

/// Builds a `…0020` payload exactly from the §4.4 table (66-byte header).
Uint8List _anchorPayload({
  int version = 1,
  int flags0 = 0xFF,
  int flags1 = 0x0F,
  int utcNow = 1767225600,
  int tzOffsetMin = 330,
  int uptimeMs = 987654,
  int localMinute = 6 * 60 + 45,
  List<int> ip = const [192, 168, 1, 42],
  int maxBeepMinutes = 30,
  int todayEventCount = 3,
  int beepProfile = 1,
  List<int> alarmEventId = const [],
  int beepingForS = 12,
  int dockLastRssi = -72,
  int dockRssiThr = -60,
  int undockStreak = 2,
  int undockConfirm = 3,
  int lastUdpCmd = 0x01,
  int lastUdpResult = 7,
  int sinceLastUdpS = 15,
  List<int> lastUdpEventId = const [],
  List<_EventRecordFixture> events = const [],
}) {
  final b = ByteData(66 + events.length * 22);
  b.setUint8(0, version);
  b.setUint8(1, flags0);
  b.setUint8(2, flags1);
  b.setUint32(3, utcNow, Endian.little);
  b.setInt16(7, tzOffsetMin, Endian.little);
  b.setUint32(9, uptimeMs, Endian.little);
  b.setUint16(13, localMinute, Endian.little);
  for (int i = 0; i < 4; i++) {
    b.setUint8(15 + i, ip[i]);
  }
  b.setUint16(19, maxBeepMinutes, Endian.little);
  b.setUint8(21, todayEventCount);
  b.setUint8(22, beepProfile);
  for (int i = 0; i < 16; i++) {
    b.setUint8(23 + i, i < alarmEventId.length ? alarmEventId[i] : 0);
  }
  b.setUint16(39, beepingForS, Endian.little);
  b.setInt8(41, dockLastRssi);
  b.setInt8(42, dockRssiThr);
  b.setUint8(43, undockStreak);
  b.setUint8(44, undockConfirm);
  b.setUint8(45, lastUdpCmd);
  b.setUint8(46, lastUdpResult);
  b.setUint16(47, sinceLastUdpS, Endian.little);
  for (int i = 0; i < 16; i++) {
    b.setUint8(49 + i, i < lastUdpEventId.length ? lastUdpEventId[i] : 0);
  }
  b.setUint8(65, events.length);
  for (int i = 0; i < events.length; i++) {
    final o = 66 + i * 22;
    final e = events[i];
    for (int j = 0; j < 15; j++) {
      b.setUint8(o + j, 0);
    }
    b.setUint8(o + 15, e.eventSuffix);
    b.setUint16(o + 16, e.startMin, Endian.little);
    b.setUint16(o + 18, e.endMin, Endian.little);
    b.setUint8(o + 20, e.criteria);
    b.setUint8(o + 21, e.flags);
  }
  return b.buffer.asUint8List();
}

void main() {
  group('WatchDebugTelemetry.decode', () {
    test('decodes every header field and an anchor record', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(
        activeEventId: _uuid(0x11),
        eventAnchorId: _uuid(0x22),
        beepAnchorCount: 2,
        anchors: const [
          _AnchorRecordFixture(
            rssi: -66,
            sinceSeenS: 12,
            lastScore: 150,
            flags: 0x1F,
            reserved: 0,
          ),
        ],
      ));

      expect(t.activityState, DebugActivityState.enforcement);
      expect(t.worn, isTrue);
      expect(t.btConnected, isTrue);
      expect(t.wifiConnected, isTrue);
      expect(t.timeValid, isTrue);
      expect(t.graceActive, isTrue);
      expect(t.profileActive, isTrue);
      expect(t.conditionMet, isTrue);
      expect(t.v0Stub, isFalse);
      expect(t.motorOn, isTrue);
      expect(t.shouldEnforce, isTrue);
      expect(t.disconnectedIsDormant, isTrue);
      expect(t.awayIsDormant, isTrue);
      expect(t.utcNow, 1767225600);
      expect(t.tzOffsetMin, -300);
      expect(t.uptimeMs, 123456);
      expect(t.activeEventId, endsWith('11'));
      expect(t.criteria, DebugCriteria.stayNear);
      expect(t.profile, 4);
      expect(t.startMin, 390);
      expect(t.endMin, 435);
      expect(t.eventAnchorId, endsWith('22'));
      expect(t.beepAnchorCount, 2);
      expect(t.donningGraceS, 300);
      expect(t.cycleCount, 9);
      expect(t.pollIntervalS, 180);
      expect(t.sinceLastPollS, 42);
      expect(t.lastPollMet, 0);
      expect(t.proxPath, DebugProxPath.score);
      expect(t.verdictFinal, ProxVerdict.away);
      expect(t.verdictV08, ProxVerdict.away);
      expect(t.verdictV2, ProxVerdict.ambiguous);
      expect(t.score, 150);
      expect(t.nearThr, 170);
      expect(t.nearThrSource, 1);
      expect(t.scoreFlags, 3);
      expect(t.emitQ8, -512);
      expect(t.lambdaQ8, -1234);
      expect(t.pNearU8, 12);
      expect(t.motionState, DebugMotionState.still);
      expect(t.pdrAbstained, isTrue);
      expect(t.pdrCovered, 4);
      expect(t.pdrLlr, -300);
      expect(t.dock, 0xFF);
      expect(t.gateAdmits, isTrue);
      expect(t.stillForS, 12);
      expect(t.livenessS, 30);
      expect(t.phoneToleranceS, 120);
      expect(t.farRssiThr, -75);
      expect(t.removedResult, WatchRemovedResult.sentToStoredIp);
      expect(t.sinceRemovedS, 7);
      expect(t.ssidMatch, 0xFF);
      expect(t.ssidMatches, isNull);
      expect(t.receivedAt, isNull);

      expect(t.anchors, hasLength(1));
      final a = t.anchors.single;
      expect(a.uuid, endsWith('a0'));
      expect(a.rssi, -66);
      expect(a.sinceSeenS, 12);
      expect(a.lastScore, 150);
      expect(a.bleMacValid, isTrue);
      expect(a.ipKnown, isTrue);
      expect(a.isEventAnchor, isTrue);
      expect(a.inBeepList, isTrue);
      expect(a.rssiFresh, isTrue);
      expect(a.reserved, 0);
    });

    test('0 records and max 16 records', () {
      final zero = WatchDebugTelemetry.decode(_watchPayload());
      expect(zero.anchors, isEmpty);

      final max = WatchDebugTelemetry.decode(_watchPayload(
        anchors: List.generate(
          16,
          (i) => _AnchorRecordFixture(rssi: -40 - i, sinceSeenS: i),
        ),
      ));
      expect(max.anchors, hasLength(16));
      expect(max.anchors.last.rssi, -55);
      expect(max.anchors.last.sinceSeenS, 15);
    });

    test('unknown version is rejected', () {
      expect(
        () => WatchDebugTelemetry.decode(_watchPayload(version: 2)),
        throwsFormatException,
      );
    });

    test('short header is rejected', () {
      final bytes = _watchPayload().sublist(0, 103);
      expect(() => WatchDebugTelemetry.decode(bytes), throwsFormatException);
    });

    test('truncated declared records are rejected', () {
      // Claims one 22-byte record, supplies only the header.
      final bytes = _watchPayload(anchors: const [_AnchorRecordFixture()])
          .sublist(0, 104);
      expect(() => WatchDebugTelemetry.decode(bytes), throwsFormatException);
    });

    test('trailing bytes are ignored', () {
      final bytes = <int>[
        ..._watchPayload(score: 77),
        0xDE, 0xAD, 0xBE, 0xEF,
      ];
      final t = WatchDebugTelemetry.decode(bytes);
      expect(t.score, 77);
      expect(t.anchors, isEmpty);
    });

    test('copyWithReceivedAt attaches a timestamp without changing data', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(score: 99));
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final stamped = t.copyWithReceivedAt(at);
      expect(stamped.receivedAt, at);
      expect(stamped.score, 99);
      expect(stamped.anchors.length, t.anchors.length);
    });

    test('criteria 0xFF and zero event UUID decode as no active event', () {
      final t = WatchDebugTelemetry.decode(_watchPayload(criteria: 0xFF));
      expect(t.criteria, isNull);
      expect(t.hasActiveEvent, isFalse);
      expect(t.activeEventId, isEmpty);
    });

    test('localMinute applies the tz offset and 0xFFFF means invalid', () {
      // 1767225600 = 2026-01-01 00:00 UTC; -300 min ⇒ 19:00 the previous day.
      final t = WatchDebugTelemetry.decode(_watchPayload(tzOffsetMin: -300));
      expect(t.localMinute, 19 * 60);
      final invalid = WatchDebugTelemetry.decode(_watchPayload(flags0: 0));
      expect(invalid.timeValid, isFalse);
      expect(invalid.localMinute, 0xFFFF);
      expect(invalid.watchLocalTime, isNull);
    });
  });

  group('AnchorDebugTelemetry.decode', () {
    test('decodes header, network-order IPv4 and event records', () {
      final t = AnchorDebugTelemetry.decode(_anchorPayload(
        alarmEventId: _uuid(0x33),
        lastUdpEventId: _uuid(0x44),
        events: const [
          _EventRecordFixture(eventSuffix: 1, flags: 0x1F),
          _EventRecordFixture(
              eventSuffix: 2, criteria: 0, flags: 0x00, startMin: 0,
              endMin: 1440),
        ],
      ));

      expect(t.wifiConnected, isTrue);
      expect(t.timeValid, isTrue);
      expect(t.scheduleLoaded, isTrue);
      expect(t.beeping, isTrue);
      expect(t.beepPhaseOn, isTrue);
      expect(t.dockAlarm, isTrue);
      expect(t.identifyActive, isTrue);
      expect(t.docked, isTrue);
      expect(t.dockPhoneConnected, isTrue);
      expect(t.dockSeenThisWindow, isTrue);
      expect(t.advUndocked, isTrue);
      expect(t.debugMode, isTrue);
      expect(t.utcNow, 1767225600);
      expect(t.tzOffsetMin, 330);
      expect(t.uptimeMs, 987654);
      expect(t.localMinute, 405);
      expect(t.ip, '192.168.1.42');
      expect(t.ipKnown, isTrue);
      expect(t.maxBeepMinutes, 30);
      expect(t.todayEventCount, 3);
      expect(t.beepProfile, 1);
      expect(t.beepProfileLabel, 'medium');
      expect(t.alarmEventId, endsWith('33'));
      expect(t.beepingForS, 12);
      expect(t.dockLastRssi, -72);
      expect(t.dockRssiThr, -60);
      expect(t.undockStreak, 2);
      expect(t.undockConfirm, 3);
      expect(t.lastUdpCmd, 0x01);
      expect(t.lastUdpCmdLabel, 'WATCH_REMOVED');
      expect(t.lastUdpResult, AnchorUdpResult.rejectedOutsideWindow);
      expect(t.lastUdpResult.label, contains('outside window'));
      expect(t.sinceLastUdpS, 15);
      expect(t.lastUdpEventId, endsWith('44'));
      expect(t.receivedAt, isNull);

      expect(t.relevantEvents, hasLength(2));
      final first = t.relevantEvents.first;
      expect(first.eventId, endsWith('01'));
      expect(first.startMin, 390);
      expect(first.endMin, 435);
      expect(first.criteria, DebugCriteria.phoneAway);
      expect(first.negatedToday, isTrue);
      expect(first.inBeepList, isTrue);
      expect(first.isDockEvent, isTrue);
      expect(first.hasAnchorProfile, isTrue);
      expect(first.windowOpenNow, isTrue);
      expect(t.dockEventRecord('x'), isNotNull);
    });

    test('0 and max 8 event records', () {
      expect(AnchorDebugTelemetry.decode(_anchorPayload()).relevantEvents,
          isEmpty);
      final max = AnchorDebugTelemetry.decode(_anchorPayload(
        events: List.generate(
          8,
          (i) => _EventRecordFixture(eventSuffix: i + 1),
        ),
      ));
      expect(max.relevantEvents, hasLength(8));
      expect(max.relevantEvents.last.eventId, endsWith('08'));
    });

    test('unknown version and short payloads are rejected', () {
      expect(() => AnchorDebugTelemetry.decode(_anchorPayload(version: 9)),
          throwsFormatException);
      expect(
        () => AnchorDebugTelemetry.decode(_anchorPayload().sublist(0, 65)),
        throwsFormatException,
      );
      expect(
        () => AnchorDebugTelemetry.decode(
            _anchorPayload(events: const [_EventRecordFixture()])
                .sublist(0, 66)),
        throwsFormatException,
      );
    });

    test('trailing bytes are ignored; 0.0.0.0 means no IP', () {
      final bytes = <int>[..._anchorPayload(ip: const [0, 0, 0, 0]), 1, 2];
      final t = AnchorDebugTelemetry.decode(bytes);
      expect(t.ip, isNull);
      expect(t.ipKnown, isFalse);
      expect(t.relevantEvents, isEmpty);
    });

    test('local_minute 0xFFFF and beep cap', () {
      final t = AnchorDebugTelemetry.decode(
          _anchorPayload(localMinute: 0xFFFF, beepingForS: 1800));
      expect(t.localMinute, 0xFFFF);
      expect(t.beepCapExpired, isTrue);
    });

    test('copyWithReceivedAt attaches a timestamp without changing data', () {
      final t = AnchorDebugTelemetry.decode(_anchorPayload());
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final stamped = t.copyWithReceivedAt(at);
      expect(stamped.receivedAt, at);
      expect(stamped.utcNow, t.utcNow);
      expect(stamped.relevantEvents.length, t.relevantEvents.length);
    });
  });
}
