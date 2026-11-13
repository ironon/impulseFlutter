// Cross-check: payloads the firmware implementations produced by hand from
// their own encoders (2026-11-12), decoded by the app. The app's other decoder
// tests encode the spec independently; these pin it against the firmware's
// reading of the same spec. If one breaks, the two sides disagree on the wire.
import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/models/debug_telemetry.dart';

List<int> _hex(String s) {
  final c = s.replaceAll(RegExp(r'\s'), '');
  return [for (var i = 0; i < c.length; i += 2) int.parse(c.substring(i, i + 2), radix: 16)];
}

void main() {
  test('watch firmware vector: STAY_NEAR, score 150 vs 170, one anchor', () {
    final t = WatchDebugTelemetry.decode(_hex('''
      01 03 4f e4 70 b2 f5 6a 00 00 87 d6 12 00 11 11 11 11 22 22 33 33 44 44 55 55 55 55 55 55 01 04
      d0 02 0c 03 aa bb cc dd ee ff 00 11 22 33 44 55 66 77 88 99 00 00 00 00 00 00 00 00 58 02 2a 00
      01 01 07 00 00 02 00 96 aa 00 01 00 00 00 03 d6 00 d2 0e 80 00 ff 00 00 03 00 78 00 2c 01 00 00
      3c 00 ab 00 ff ff ff 01 aa bb cc dd ee ff 00 11 22 33 44 55 66 77 88 99 c2 0c 00 96 17 00'''));
    expect(t.activityState, DebugActivityState.enforcement);
    expect(t.worn, isTrue);
    expect(t.conditionMet, isTrue);
    expect(t.shouldEnforce, isTrue);
    expect(t.criteria, DebugCriteria.stayNear);
    expect(t.startMin, 720);
    expect(t.endMin, 780);
    expect(t.pollIntervalS, 600);
    expect(t.proxPath, DebugProxPath.score);
    expect(t.verdictFinal, ProxVerdict.near);
    expect(t.verdictV08, ProxVerdict.ambiguous);
    expect(t.score, 150);
    expect(t.nearThr, 170);
    expect(t.lambdaQ8, 768);
    expect(t.pNearU8, 214);
    expect(t.pdrLlr, 128);
    expect(t.dock, 0xFF);
    expect(t.livenessS, 300);
    expect(t.phoneToleranceS, 60);
    expect(t.farRssiThr, -85);
    expect(t.anchors, hasLength(1));
    final a = t.anchors.single;
    expect(a.rssi, -62);
    expect(a.sinceSeenS, 12);
    expect(a.lastScore, 150);
    expect(a.bleMacValid && a.ipKnown && a.isEventAnchor && a.rssiFresh, isTrue);
    expect(a.inBeepList, isFalse);
  });

  test('anchor firmware vector: WATCH_REMOVED rejected outside window', () {
    final t = AnchorDebugTelemetry.decode(_hex('''
      01 07 08 68 55 F5 6A 3C 00 87 D6 12 00 A2 01 C0 A8 01 2A 1E 00 01 FF 00 00 00 00 00 00 00 00 00
      00 00 00 00 00 00 00 00 00 00 C4 00 03 01 07 0C 00 8F 14 E4 5F CE EC 4B 7E 9E 3C 1A 2B 3C 4D 5E
      6F 01 8F 14 E4 5F CE EC 4B 7E 9E 3C 1A 2B 3C 4D 5E 6F C2 01 E0 01 00 0A'''));
    expect(t.wifiConnected && t.timeValid && t.scheduleLoaded, isTrue);
    expect(t.beeping, isFalse);
    expect(t.localMinute, 418);
    expect(t.tzOffsetMin, 60);
    expect(t.maxBeepMinutes, 30);
    expect(t.dockRssiThr, -60);
    expect(t.lastUdpResult, AnchorUdpResult.rejectedOutsideWindow);
    expect(t.sinceLastUdpS, 12);
    expect(t.relevantEvents, hasLength(1));
    final e = t.relevantEvents.single;
    expect(e.startMin, 450);
    expect(e.endMin, 480);
    expect(e.inBeepList && e.hasAnchorProfile, isTrue);
    expect(e.windowOpenNow, isFalse);
  });

  test('looksTruncated: only short v1 values are worth a re-read', () {
    final full = List<int>.filled(104 + 22, 0)..[0] = 1..[103] = 1;
    expect(WatchDebugTelemetry.looksTruncated(full), isFalse);
    expect(WatchDebugTelemetry.looksTruncated(full.sublist(0, 100)), isTrue);
    expect(WatchDebugTelemetry.looksTruncated(full.sublist(0, 110)), isTrue);
    expect(WatchDebugTelemetry.looksTruncated([2, ...full.skip(1)]), isFalse,
        reason: 'unknown version: re-reading would just fail again');
    expect(WatchDebugTelemetry.looksTruncated(const []), isFalse);
    final a = List<int>.filled(66, 0)..[0] = 1..[65] = 2;
    expect(AnchorDebugTelemetry.looksTruncated(a), isTrue);
    expect(AnchorDebugTelemetry.looksTruncated([...a, ...List.filled(44, 0)]),
        isFalse);
  });
}
