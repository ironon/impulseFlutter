// Debug Telemetry — the app's read-only mirror of the firmware snapshots
// (firmware §5.6 watch `…001D`, §4.4 anchor `…0020`).
//
// These classes are pure data: no Flutter, no I/O. The wire contract is the
// firmware spec (v0.18) and is implemented byte for byte:
//
//   * every multi-byte field is little-endian except IPv4, which is four octets
//     in network order;
//   * "saturating" ages of 0xFFFF mean *never*;
//   * the payload is append-only. A decoder rejects a version it does not know
//     and ignores bytes past the fields it knows, but a payload that is too
//     short for the header + declared record count is a hard failure
//     ([FormatException]) rather than a silently half-filled snapshot.
//
// `receivedAt` is deliberately NOT set by [WatchDebugTelemetry.decode] /
// [AnchorDebugTelemetry.decode]: the same bytes can be decoded by a test or a
// log viewer, and a decoder that stamps the clock would make "how old is this
// snapshot?" meaningless. The service that reads the characteristic stamps it
// (see `copyWithReceivedAt`).

import 'dart:typed_data';

// ── Enums (wire values are the declaration order; see the spec tables) ──────

/// Watch `ActivityState` byte (firmware §5.1).
enum DebugActivityState { unpaired, dormant, dormantSleep, enforcement }

extension DebugActivityStateLabel on DebugActivityState {
  String get label {
    switch (this) {
      case DebugActivityState.unpaired:       return 'UNPAIRED';
      case DebugActivityState.dormant:        return 'DORMANT';
      case DebugActivityState.dormantSleep:   return 'DORMANT_SLEEP';
      case DebugActivityState.enforcement:    return 'ENFORCEMENT';
    }
  }
}

/// Event criterion. The wire values match the firmware `Criteria` enum and the
/// app's [Criteria] declaration order.
enum DebugCriteria { getAway, stayNear, getOffWifi, getOnWifi, phoneAway }

extension DebugCriteriaLabel on DebugCriteria {
  String get label {
    switch (this) {
      case DebugCriteria.getAway:    return 'GET_AWAY';
      case DebugCriteria.stayNear:   return 'STAY_NEAR';
      case DebugCriteria.getOffWifi: return 'GET_OFF_WIFI';
      case DebugCriteria.getOnWifi:  return 'GET_ON_WIFI';
      case DebugCriteria.phoneAway:  return 'PHONE_AWAY';
    }
  }

  /// Human wording for the beep checklist (the firmware name in parentheses).
  String get humanLabel {
    switch (this) {
      case DebugCriteria.getAway:    return 'Get away';
      case DebugCriteria.stayNear:   return 'Stay near';
      case DebugCriteria.getOffWifi: return 'Get off WiFi';
      case DebugCriteria.getOnWifi:  return 'Get on WiFi';
      case DebugCriteria.phoneAway:  return 'Phone away';
    }
  }
}

/// `ProxProximity`: what the proximity engine (or the v0.8 threshold) returned.
enum ProxVerdict { near, away, ambiguous }

extension ProxVerdictLabel on ProxVerdict {
  String get label {
    switch (this) {
      case ProxVerdict.near:      return 'NEAR';
      case ProxVerdict.away:      return 'AWAY';
      case ProxVerdict.ambiguous: return 'AMBIGUOUS';
    }
  }
}

/// How the last `query_anchor_proximity()` ended.
enum DebugProxPath { never, score, connectFailed, macUnknown, v0Stub }

extension DebugProxPathLabel on DebugProxPath {
  String get label {
    switch (this) {
      case DebugProxPath.never:         return 'never queried';
      case DebugProxPath.score:         return 'score (anchor answered)';
      case DebugProxPath.connectFailed: return 'connect failed';
      case DebugProxPath.macUnknown:    return 'MAC unknown';
      case DebugProxPath.v0Stub:        return 'v0 stub';
    }
  }
}

/// Outcome of the last `WATCH_REMOVED` UDP send attempt.
enum WatchRemovedResult {
  never,
  sentToStoredIp,
  sentByBroadcast,
  notSentNoWifi,
  sendFailed,
}

extension WatchRemovedResultLabel on WatchRemovedResult {
  String get label {
    switch (this) {
      case WatchRemovedResult.never:           return 'never attempted';
      case WatchRemovedResult.sentToStoredIp:  return 'sent to stored IP';
      case WatchRemovedResult.sentByBroadcast: return 'sent by broadcast';
      case WatchRemovedResult.notSentNoWifi:   return 'not sent (no WiFi)';
      case WatchRemovedResult.sendFailed:      return 'send failed';
    }
  }

  /// True only when a datagram actually left the watch.
  bool get wasSent =>
      this == WatchRemovedResult.sentToStoredIp ||
      this == WatchRemovedResult.sentByBroadcast;
}

/// Movement classification the getAway gate consumes.
enum DebugMotionState { still, fidget, loco, unknown }

extension DebugMotionStateLabel on DebugMotionState {
  String get label {
    switch (this) {
      case DebugMotionState.still:   return 'STILL';
      case DebugMotionState.fidget:  return 'FIDGET';
      case DebugMotionState.loco:    return 'LOCO';
      case DebugMotionState.unknown: return 'UNKNOWN';
    }
  }
}

/// Result code of the last UDP datagram the anchor parsed (§4.4 `…0020`).
enum AnchorUdpResult {
  none,
  started,
  alreadyBeeping,
  rejectedNoSchedule,
  rejectedUnknownEvent,
  rejectedNegated,
  rejectedNotInBeepList,
  rejectedOutsideWindow,
  rejectedNoAnchorProfile,
  stoppedByWorn,
  wornNoMatch,
  badPacket,
  other,
}

extension AnchorUdpResultLabel on AnchorUdpResult {
  String get label {
    switch (this) {
      case AnchorUdpResult.none:
        return 'no datagram yet';
      case AnchorUdpResult.started:
        return 'started beeping';
      case AnchorUdpResult.alreadyBeeping:
        return 'already beeping (idempotent)';
      case AnchorUdpResult.rejectedNoSchedule:
        return 'rejected: no schedule stored';
      case AnchorUdpResult.rejectedUnknownEvent:
        return 'rejected: event not in anchor schedule';
      case AnchorUdpResult.rejectedNegated:
        return 'rejected: event negated today';
      case AnchorUdpResult.rejectedNotInBeepList:
        return 'rejected: anchor not in beepAnchors';
      case AnchorUdpResult.rejectedOutsideWindow:
        return 'rejected: outside window (anchor clock)';
      case AnchorUdpResult.rejectedNoAnchorProfile:
        return 'rejected: event has no anchorProfile';
      case AnchorUdpResult.stoppedByWorn:
        return 'stopped by WATCH_WORN';
      case AnchorUdpResult.wornNoMatch:
        return 'WATCH_WORN ignored: no matching alarm';
      case AnchorUdpResult.badPacket:
        return 'bad packet';
      case AnchorUdpResult.other:
        return 'other (see serial log)';
    }
  }
}

// ── Watch records ───────────────────────────────────────────────────────────

/// One entry of the watch's `AnchorRecord` tail (`…001D`).
class WatchAnchorRecord {
  /// 16-byte anchor UUID in printed order, canonical lowercase.
  final String uuid;

  /// Last advertisement RSSI; 127 means never seen.
  final int rssi;

  /// Seconds since `lastSeen`; 0xFFFF means never.
  final int sinceSeenS;

  /// Last proximity score this anchor returned (0 = none yet).
  final int lastScore;

  final bool bleMacValid;
  final bool ipKnown;
  final bool isEventAnchor;
  final bool inBeepList;
  final bool rssiFresh;

  /// Reserved byte, always 0 today.
  final int reserved;

  const WatchAnchorRecord({
    required this.uuid,
    required this.rssi,
    required this.sinceSeenS,
    required this.lastScore,
    required this.bleMacValid,
    required this.ipKnown,
    required this.isEventAnchor,
    required this.inBeepList,
    required this.rssiFresh,
    required this.reserved,
  });

  bool get everSeen => rssi != 127 && sinceSeenS != 0xFFFF;
}

/// Decoded `WATCH_DEBUG_CHAR_UUID` (`…001D`, firmware §5.6). Header 104 bytes,
/// then `anchor_count` × 22-byte [WatchAnchorRecord].
class WatchDebugTelemetry {
  /// True when [bytes] is a version-1 value cut short of its own header plus
  /// declared records, i.e. a notification truncated to MTU−3. Callers use it
  /// to decide whether a failed decode is worth a full read.
  static bool looksTruncated(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] != 1) return false;
    if (bytes.length < 104) return true;
    return bytes.length < 104 + 22 * bytes[103];
  }

  static const int headerSize = 104;
  static const int anchorRecordSize = 22;
  static const int maxAnchorRecords = 16;
  static const int wireVersion = 1;

  // Header flags0
  final bool worn;
  final bool btConnected;
  final bool wifiConnected;
  final bool timeValid;
  final bool graceActive;
  final bool profileActive;
  final bool conditionMet;

  /// V0_ENABLED test build: every verdict is forced noncompliant.
  final bool v0Stub;

  // Header flags1
  final bool motorOn;
  final bool buzzerOn;
  final bool proxV2Authoritative;
  final bool phoneUndockLatched;
  final bool calibActive;
  final bool shouldEnforce;
  final bool disconnectedIsDormant;
  final bool awayIsDormant;

  final DebugActivityState activityState;

  /// Unix seconds the watch believes it is.
  final int utcNow;
  final int tzOffsetMin;

  /// `millis()` when the snapshot was built.
  final int uptimeMs;

  /// Active event UUID, or '' when there is none.
  final String activeEventId;

  /// Active criterion, or null for 0xFF / an unknown value.
  final DebugCriteria? criteria;

  /// `EnforcementProfile` raw value (0…8), 0xFF when no event.
  final int profile;

  final int startMin;
  final int endMin;

  /// Active event's `anchorId`, or '' when unset.
  final String eventAnchorId;

  final int beepAnchorCount;
  final int donningGraceS;
  final int graceRemainingS;
  final int stepIdx;
  final int cycleCount;
  final int pollIntervalS;
  final int sinceLastPollS;

  /// `is_enforcement_condition_met()` result: 0/1, 0xFF = never polled.
  final int lastPollMet;

  final DebugProxPath proxPath;
  final int sinceLastQueryS;

  final ProxVerdict verdictFinal;
  final ProxVerdict verdictV08;
  final ProxVerdict verdictV2;

  final int score;
  final int nearThr;

  /// 0 = global default, 1 = anchor-calibrated.
  final int nearThrSource;
  final int scoreFlags;

  /// HMM emission in Q8; 0 = in the dead zone.
  final int emitQ8;
  final int lambdaQ8;
  final int pNearU8;

  final DebugMotionState motionState;

  /// 0xFF means PDR abstained.
  final int pdrRateU8;
  final int pdrCovered;
  final int pdrLlr;

  /// Last connected dock read: 0 undocked, 1 docked, 0xFF unknown.
  final int dock;

  final bool gateArmed;
  final int gateHits;
  final int gateArmHits;
  final bool gateAdmits;
  final int stillForS;
  final int livenessS;
  final int phoneNearForS;
  final int phoneToleranceS;

  final int farRssiThr;

  final WatchRemovedResult removedResult;
  final int sinceRemovedS;

  /// 1 = connected SSID matches the event, 0 = no, 0xFF = not applicable.
  final int ssidMatch;

  final List<WatchAnchorRecord> anchors;

  /// When the app read these bytes. Null when decoded away from a live read.
  final DateTime? receivedAt;

  const WatchDebugTelemetry({
    required this.worn,
    required this.btConnected,
    required this.wifiConnected,
    required this.timeValid,
    required this.graceActive,
    required this.profileActive,
    required this.conditionMet,
    required this.v0Stub,
    required this.motorOn,
    required this.buzzerOn,
    required this.proxV2Authoritative,
    required this.phoneUndockLatched,
    required this.calibActive,
    required this.shouldEnforce,
    required this.disconnectedIsDormant,
    required this.awayIsDormant,
    required this.activityState,
    required this.utcNow,
    required this.tzOffsetMin,
    required this.uptimeMs,
    required this.activeEventId,
    required this.criteria,
    required this.profile,
    required this.startMin,
    required this.endMin,
    required this.eventAnchorId,
    required this.beepAnchorCount,
    required this.donningGraceS,
    required this.graceRemainingS,
    required this.stepIdx,
    required this.cycleCount,
    required this.pollIntervalS,
    required this.sinceLastPollS,
    required this.lastPollMet,
    required this.proxPath,
    required this.sinceLastQueryS,
    required this.verdictFinal,
    required this.verdictV08,
    required this.verdictV2,
    required this.score,
    required this.nearThr,
    required this.nearThrSource,
    required this.scoreFlags,
    required this.emitQ8,
    required this.lambdaQ8,
    required this.pNearU8,
    required this.motionState,
    required this.pdrRateU8,
    required this.pdrCovered,
    required this.pdrLlr,
    required this.dock,
    required this.gateArmed,
    required this.gateHits,
    required this.gateArmHits,
    required this.gateAdmits,
    required this.stillForS,
    required this.livenessS,
    required this.phoneNearForS,
    required this.phoneToleranceS,
    required this.farRssiThr,
    required this.removedResult,
    required this.sinceRemovedS,
    required this.ssidMatch,
    required this.anchors,
    this.receivedAt,
  });

  /// True when a window is active and the watch knows its criterion.
  bool get hasActiveEvent =>
      activityState == DebugActivityState.enforcement && criteria != null;

  /// Local wall-clock minute of the watch (0…1439), or 0xFFFF when the clock is
  /// not valid.
  int get localMinute {
    if (!timeValid) return 0xFFFF;
    return _minuteOfDay(utcNow, tzOffsetMin);
  }

  /// The watch's local wall time as a DateTime (UTC-labelled; only the fields
  /// are meaningful).
  DateTime? get watchLocalTime {
    if (!timeValid) return null;
    return DateTime.fromMillisecondsSinceEpoch(utcNow * 1000, isUtc: true)
        .add(Duration(minutes: tzOffsetMin));
  }

  bool get pdrAbstained => pdrRateU8 == 0xFF;

  /// `ssid_match` for the WiFi criteria; null when the firmware says n/a.
  bool? get ssidMatches => ssidMatch == 0xFF ? null : ssidMatch != 0;

  /// The anchor record for [uuid], or null when the watch did not report it.
  WatchAnchorRecord? anchorRecord(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    for (final a in anchors) {
      if (a.uuid == uuid) return a;
    }
    return null;
  }

  /// `EnforcementProfile` names in wire order (matches the app's enum; kept
  /// local so this model stays Flutter-free).
  String get profileLabel {
    const names = [
      'strict · vibrate only',
      'normal · vibrate only',
      'loose · vibrate only',
      'strict · buzz+vibrate',
      'normal · buzz+vibrate',
      'loose · buzz+vibrate',
      'strict · buzz only',
      'normal · buzz only',
      'loose · buzz only',
    ];
    if (profile < names.length) return names[profile];
    if (profile == 0xFF) return 'none';
    return 'unknown ($profile)';
  }

  /// A copy with the decode-site timestamp attached.
  WatchDebugTelemetry copyWithReceivedAt(DateTime at) => WatchDebugTelemetry(
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
        proxV2Authoritative: proxV2Authoritative,
        phoneUndockLatched: phoneUndockLatched,
        calibActive: calibActive,
        shouldEnforce: shouldEnforce,
        disconnectedIsDormant: disconnectedIsDormant,
        awayIsDormant: awayIsDormant,
        activityState: activityState,
        utcNow: utcNow,
        tzOffsetMin: tzOffsetMin,
        uptimeMs: uptimeMs,
        activeEventId: activeEventId,
        criteria: criteria,
        profile: profile,
        startMin: startMin,
        endMin: endMin,
        eventAnchorId: eventAnchorId,
        beepAnchorCount: beepAnchorCount,
        donningGraceS: donningGraceS,
        graceRemainingS: graceRemainingS,
        stepIdx: stepIdx,
        cycleCount: cycleCount,
        pollIntervalS: pollIntervalS,
        sinceLastPollS: sinceLastPollS,
        lastPollMet: lastPollMet,
        proxPath: proxPath,
        sinceLastQueryS: sinceLastQueryS,
        verdictFinal: verdictFinal,
        verdictV08: verdictV08,
        verdictV2: verdictV2,
        score: score,
        nearThr: nearThr,
        nearThrSource: nearThrSource,
        scoreFlags: scoreFlags,
        emitQ8: emitQ8,
        lambdaQ8: lambdaQ8,
        pNearU8: pNearU8,
        motionState: motionState,
        pdrRateU8: pdrRateU8,
        pdrCovered: pdrCovered,
        pdrLlr: pdrLlr,
        dock: dock,
        gateArmed: gateArmed,
        gateHits: gateHits,
        gateArmHits: gateArmHits,
        gateAdmits: gateAdmits,
        stillForS: stillForS,
        livenessS: livenessS,
        phoneNearForS: phoneNearForS,
        phoneToleranceS: phoneToleranceS,
        farRssiThr: farRssiThr,
        removedResult: removedResult,
        sinceRemovedS: sinceRemovedS,
        ssidMatch: ssidMatch,
        anchors: anchors,
        receivedAt: at,
      );

  /// Decode a `…001D` snapshot. Throws [FormatException] when the payload is
  /// shorter than its header, shorter than the header plus the declared record
  /// count, or carries an unknown version. Bytes past the known fields are
  /// ignored (append-only contract).
  static WatchDebugTelemetry decode(List<int> bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
          'watch debug telemetry: ${bytes.length} bytes < $headerSize');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final version = data.getUint8(0);
    if (version != wireVersion) {
      throw FormatException('watch debug telemetry: version $version');
    }
    final anchorCount = data.getUint8(103);
    if (anchorCount > maxAnchorRecords) {
      throw FormatException(
          'watch debug telemetry: $anchorCount anchor records > '
          '$maxAnchorRecords');
    }
    final need = headerSize + anchorCount * anchorRecordSize;
    if (bytes.length < need) {
      throw FormatException(
          'watch debug telemetry: ${bytes.length} bytes < $need '
          '($anchorCount records)');
    }

    final flags0 = data.getUint8(2);
    final flags1 = data.getUint8(3);
    final recordStart = headerSize;
    final anchors = <WatchAnchorRecord>[];
    for (int i = 0; i < anchorCount; i++) {
      final o = recordStart + i * anchorRecordSize;
      final flags = data.getUint8(o + 20);
      anchors.add(WatchAnchorRecord(
        uuid: _uuidAt(data, o),
        rssi: data.getInt8(o + 16),
        sinceSeenS: data.getUint16(o + 17, Endian.little),
        lastScore: data.getUint8(o + 19),
        bleMacValid: (flags & 0x01) != 0,
        ipKnown: (flags & 0x02) != 0,
        isEventAnchor: (flags & 0x04) != 0,
        inBeepList: (flags & 0x08) != 0,
        rssiFresh: (flags & 0x10) != 0,
        reserved: data.getUint8(o + 21),
      ));
    }

    return WatchDebugTelemetry(
      worn: (flags0 & 0x01) != 0,
      btConnected: (flags0 & 0x02) != 0,
      wifiConnected: (flags0 & 0x04) != 0,
      timeValid: (flags0 & 0x08) != 0,
      graceActive: (flags0 & 0x10) != 0,
      profileActive: (flags0 & 0x20) != 0,
      conditionMet: (flags0 & 0x40) != 0,
      v0Stub: (flags0 & 0x80) != 0,
      motorOn: (flags1 & 0x01) != 0,
      buzzerOn: (flags1 & 0x02) != 0,
      proxV2Authoritative: (flags1 & 0x04) != 0,
      phoneUndockLatched: (flags1 & 0x08) != 0,
      calibActive: (flags1 & 0x10) != 0,
      shouldEnforce: (flags1 & 0x20) != 0,
      disconnectedIsDormant: (flags1 & 0x40) != 0,
      awayIsDormant: (flags1 & 0x80) != 0,
      activityState: _activityState(data.getUint8(1)),
      utcNow: data.getUint32(4, Endian.little),
      tzOffsetMin: data.getInt16(8, Endian.little),
      uptimeMs: data.getUint32(10, Endian.little),
      activeEventId: _uuidOrEmpty(data, 14),
      criteria: _criteria(data.getUint8(30)),
      profile: data.getUint8(31),
      startMin: data.getUint16(32, Endian.little),
      endMin: data.getUint16(34, Endian.little),
      eventAnchorId: _uuidOrEmpty(data, 36),
      beepAnchorCount: data.getUint8(52),
      donningGraceS: data.getUint16(53, Endian.little),
      graceRemainingS: data.getUint16(55, Endian.little),
      stepIdx: data.getUint8(57),
      cycleCount: data.getUint16(58, Endian.little),
      pollIntervalS: data.getUint16(60, Endian.little),
      sinceLastPollS: data.getUint16(62, Endian.little),
      lastPollMet: data.getUint8(64),
      proxPath: _proxPath(data.getUint8(65)),
      sinceLastQueryS: data.getUint16(66, Endian.little),
      verdictFinal: _verdict(data.getUint8(68)),
      verdictV08: _verdict(data.getUint8(69)),
      verdictV2: _verdict(data.getUint8(70)),
      score: data.getUint8(71),
      nearThr: data.getUint8(72),
      nearThrSource: data.getUint8(73),
      scoreFlags: data.getUint8(74),
      emitQ8: data.getInt16(75, Endian.little),
      lambdaQ8: data.getInt16(77, Endian.little),
      pNearU8: data.getUint8(79),
      motionState: _motion(data.getUint8(80)),
      pdrRateU8: data.getUint8(81),
      pdrCovered: data.getUint8(82),
      pdrLlr: data.getInt16(83, Endian.little),
      dock: data.getUint8(85),
      gateArmed: data.getUint8(86) != 0,
      gateHits: data.getUint8(87),
      gateArmHits: data.getUint8(88),
      gateAdmits: data.getUint8(89) != 0,
      stillForS: data.getUint16(90, Endian.little),
      livenessS: data.getUint16(92, Endian.little),
      phoneNearForS: data.getUint16(94, Endian.little),
      phoneToleranceS: data.getUint16(96, Endian.little),
      farRssiThr: data.getInt8(98),
      removedResult: _removedResult(data.getUint8(99)),
      sinceRemovedS: data.getUint16(100, Endian.little),
      ssidMatch: data.getUint8(102),
      anchors: List.unmodifiable(anchors),
    );
  }
}

// ── Anchor records ──────────────────────────────────────────────────────────

/// One of the anchor's `relevant_count` event records (`…0020`).
class AnchorEventRecord {
  /// 16-byte event UUID in printed order, canonical lowercase.
  final String eventId;
  final int startMin;
  final int endMin;
  final DebugCriteria? criteria;

  final bool negatedToday;
  final bool inBeepList;

  /// `PHONE_AWAY && anchorId == this anchor`.
  final bool isDockEvent;
  final bool hasAnchorProfile;

  /// `time valid && start <= local_minute < end`, by the anchor's own clock.
  final bool windowOpenNow;

  const AnchorEventRecord({
    required this.eventId,
    required this.startMin,
    required this.endMin,
    required this.criteria,
    required this.negatedToday,
    required this.inBeepList,
    required this.isDockEvent,
    required this.hasAnchorProfile,
    required this.windowOpenNow,
  });
}

/// Decoded `ANCHOR_DEBUG_CHAR_UUID` (`…0020`, firmware §4.4). Header 66 bytes,
/// then `relevant_count` × 22-byte [AnchorEventRecord].
class AnchorDebugTelemetry {
  /// True when [bytes] is a version-1 value cut short of its own header plus
  /// declared records, i.e. a notification truncated to MTU−3. Callers use it
  /// to decide whether a failed decode is worth a full read.
  static bool looksTruncated(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] != 1) return false;
    if (bytes.length < 66) return true;
    return bytes.length < 66 + 22 * bytes[65];
  }

  static const int headerSize = 66;
  static const int eventRecordSize = 22;
  static const int maxEventRecords = 8;
  static const int wireVersion = 1;

  // flags0
  final bool wifiConnected;
  final bool timeValid;
  final bool scheduleLoaded;
  final bool beeping;
  final bool beepPhaseOn;
  final bool dockAlarm;
  final bool identifyActive;
  final bool docked;

  // flags1
  final bool dockPhoneConnected;
  final bool dockSeenThisWindow;
  final bool advUndocked;
  final bool debugMode;

  final int utcNow;
  final int tzOffsetMin;
  final int uptimeMs;

  /// Minutes since local midnight; 0xFFFF when the clock is not valid.
  final int localMinute;

  /// Current IPv4 in dotted-quad form, or null when there is no address.
  final String? ip;

  final int maxBeepMinutes;

  /// `g_event_count` — today's events in the anchor's own list.
  final int todayEventCount;

  /// `AnchorEnforcementProfile` 0…2 while beeping, 0xFF otherwise.
  final int beepProfile;

  /// Event UUID the alarm belongs to, or '' when not beeping.
  final String alarmEventId;

  final int beepingForS;

  final int dockLastRssi;
  final int dockRssiThr;
  final int undockStreak;
  final int undockConfirm;

  /// 0 = none yet, 0x01 WATCH_REMOVED, 0x02 WATCH_WORN, …
  final int lastUdpCmd;

  final AnchorUdpResult lastUdpResult;

  /// Seconds since that datagram; 0xFFFF = never.
  final int sinceLastUdpS;

  /// Event UUID carried by that datagram, or '' when none.
  final String lastUdpEventId;

  final List<AnchorEventRecord> relevantEvents;

  /// When the app read these bytes. Null when decoded away from a live read.
  final DateTime? receivedAt;

  const AnchorDebugTelemetry({
    required this.wifiConnected,
    required this.timeValid,
    required this.scheduleLoaded,
    required this.beeping,
    required this.beepPhaseOn,
    required this.dockAlarm,
    required this.identifyActive,
    required this.docked,
    required this.dockPhoneConnected,
    required this.dockSeenThisWindow,
    required this.advUndocked,
    required this.debugMode,
    required this.utcNow,
    required this.tzOffsetMin,
    required this.uptimeMs,
    required this.localMinute,
    required this.ip,
    required this.maxBeepMinutes,
    required this.todayEventCount,
    required this.beepProfile,
    required this.alarmEventId,
    required this.beepingForS,
    required this.dockLastRssi,
    required this.dockRssiThr,
    required this.undockStreak,
    required this.undockConfirm,
    required this.lastUdpCmd,
    required this.lastUdpResult,
    required this.sinceLastUdpS,
    required this.lastUdpEventId,
    required this.relevantEvents,
    this.receivedAt,
  });

  bool get ipKnown => ip != null;

  /// True when the beep cap has expired (`update_beeping` would stop).
  bool get beepCapExpired =>
      beeping && beepingForS >= maxBeepMinutes * 60;

  /// Local wall time from SNTP, or null when the clock is not valid.
  DateTime? get anchorLocalTime {
    if (!timeValid || utcNow == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(utcNow * 1000, isUtc: true)
        .add(Duration(minutes: tzOffsetMin));
  }

  /// The dock event record for [eventId], else the first dock event.
  AnchorEventRecord? dockEventRecord(String? eventId) {
    AnchorEventRecord? fallback;
    for (final e in relevantEvents) {
      if (!e.isDockEvent) continue;
      if (eventId != null && eventId.isNotEmpty && e.eventId == eventId) {
        return e;
      }
      fallback ??= e;
    }
    return fallback;
  }

  /// The record for [eventId], or null.
  AnchorEventRecord? eventRecord(String? eventId) {
    if (eventId == null || eventId.isEmpty) return null;
    for (final e in relevantEvents) {
      if (e.eventId == eventId) return e;
    }
    return null;
  }

  /// `AnchorEnforcementProfile` name for [beepProfile].
  String get beepProfileLabel {
    const names = ['light', 'medium', 'hard'];
    if (beepProfile < names.length) return names[beepProfile];
    if (beepProfile == 0xFF) return 'none';
    return 'unknown ($beepProfile)';
  }

  /// `last_udp_cmd` in words.
  String get lastUdpCmdLabel {
    switch (lastUdpCmd) {
      case 0x00: return 'none';
      case 0x01: return 'WATCH_REMOVED';
      case 0x02: return 'WATCH_WORN';
      default:   return 'cmd 0x${lastUdpCmd.toRadixString(16).padLeft(2, '0')}';
    }
  }

  /// A copy with the decode-site timestamp attached.
  AnchorDebugTelemetry copyWithReceivedAt(DateTime at) => AnchorDebugTelemetry(
        wifiConnected: wifiConnected,
        timeValid: timeValid,
        scheduleLoaded: scheduleLoaded,
        beeping: beeping,
        beepPhaseOn: beepPhaseOn,
        dockAlarm: dockAlarm,
        identifyActive: identifyActive,
        docked: docked,
        dockPhoneConnected: dockPhoneConnected,
        dockSeenThisWindow: dockSeenThisWindow,
        advUndocked: advUndocked,
        debugMode: debugMode,
        utcNow: utcNow,
        tzOffsetMin: tzOffsetMin,
        uptimeMs: uptimeMs,
        localMinute: localMinute,
        ip: ip,
        maxBeepMinutes: maxBeepMinutes,
        todayEventCount: todayEventCount,
        beepProfile: beepProfile,
        alarmEventId: alarmEventId,
        beepingForS: beepingForS,
        dockLastRssi: dockLastRssi,
        dockRssiThr: dockRssiThr,
        undockStreak: undockStreak,
        undockConfirm: undockConfirm,
        lastUdpCmd: lastUdpCmd,
        lastUdpResult: lastUdpResult,
        sinceLastUdpS: sinceLastUdpS,
        lastUdpEventId: lastUdpEventId,
        relevantEvents: relevantEvents,
        receivedAt: at,
      );

  /// Decode an `…0020` snapshot. Same rules as the watch decoder: reject short
  /// input and unknown versions, ignore trailing bytes.
  static AnchorDebugTelemetry decode(List<int> bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
          'anchor debug telemetry: ${bytes.length} bytes < $headerSize');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final version = data.getUint8(0);
    if (version != wireVersion) {
      throw FormatException('anchor debug telemetry: version $version');
    }
    final relevantCount = data.getUint8(65);
    if (relevantCount > maxEventRecords) {
      throw FormatException(
          'anchor debug telemetry: $relevantCount event records > '
          '$maxEventRecords');
    }
    final need = headerSize + relevantCount * eventRecordSize;
    if (bytes.length < need) {
      throw FormatException(
          'anchor debug telemetry: ${bytes.length} bytes < $need '
          '($relevantCount records)');
    }

    final flags0 = data.getUint8(1);
    final flags1 = data.getUint8(2);
    final ipRaw = data.getUint32(15, Endian.little);
    final events = <AnchorEventRecord>[];
    for (int i = 0; i < relevantCount; i++) {
      final o = headerSize + i * eventRecordSize;
      final flags = data.getUint8(o + 21);
      events.add(AnchorEventRecord(
        eventId: _uuidAt(data, o),
        startMin: data.getUint16(o + 16, Endian.little),
        endMin: data.getUint16(o + 18, Endian.little),
        criteria: _criteria(data.getUint8(o + 20)),
        negatedToday: (flags & 0x01) != 0,
        inBeepList: (flags & 0x02) != 0,
        isDockEvent: (flags & 0x04) != 0,
        hasAnchorProfile: (flags & 0x08) != 0,
        windowOpenNow: (flags & 0x10) != 0,
      ));
    }

    return AnchorDebugTelemetry(
      wifiConnected: (flags0 & 0x01) != 0,
      timeValid: (flags0 & 0x02) != 0,
      scheduleLoaded: (flags0 & 0x04) != 0,
      beeping: (flags0 & 0x08) != 0,
      beepPhaseOn: (flags0 & 0x10) != 0,
      dockAlarm: (flags0 & 0x20) != 0,
      identifyActive: (flags0 & 0x40) != 0,
      docked: (flags0 & 0x80) != 0,
      dockPhoneConnected: (flags1 & 0x01) != 0,
      dockSeenThisWindow: (flags1 & 0x02) != 0,
      advUndocked: (flags1 & 0x04) != 0,
      debugMode: (flags1 & 0x08) != 0,
      utcNow: data.getUint32(3, Endian.little),
      tzOffsetMin: data.getInt16(7, Endian.little),
      uptimeMs: data.getUint32(9, Endian.little),
      localMinute: data.getUint16(13, Endian.little),
      ip: ipRaw == 0 ? null : _ipv4(data, 15),
      maxBeepMinutes: data.getUint16(19, Endian.little),
      todayEventCount: data.getUint8(21),
      beepProfile: data.getUint8(22),
      alarmEventId: _uuidOrEmpty(data, 23),
      beepingForS: data.getUint16(39, Endian.little),
      dockLastRssi: data.getInt8(41),
      dockRssiThr: data.getInt8(42),
      undockStreak: data.getUint8(43),
      undockConfirm: data.getUint8(44),
      lastUdpCmd: data.getUint8(45),
      lastUdpResult: _udpResult(data.getUint8(46)),
      sinceLastUdpS: data.getUint16(47, Endian.little),
      lastUdpEventId: _uuidOrEmpty(data, 49),
      relevantEvents: List.unmodifiable(events),
    );
  }
}

// ── Wire helpers ────────────────────────────────────────────────────────────

DebugActivityState _activityState(int v) {
  switch (v) {
    case 0: return DebugActivityState.unpaired;
    case 1: return DebugActivityState.dormant;
    case 2: return DebugActivityState.dormantSleep;
    case 3: return DebugActivityState.enforcement;
    default: return DebugActivityState.unpaired;
  }
}

DebugCriteria? _criteria(int v) {
  if (v >= 0 && v < DebugCriteria.values.length) {
    return DebugCriteria.values[v];
  }
  return null;
}

ProxVerdict _verdict(int v) {
  // Unknown encodings are surfaced as AMBIGUOUS rather than guessed: the
  // firmware treats AMBIGUOUS as "no confident answer", which is the safe
  // rendering of a value this app does not understand.
  if (v >= 0 && v < ProxVerdict.values.length) return ProxVerdict.values[v];
  return ProxVerdict.ambiguous;
}

DebugProxPath _proxPath(int v) {
  if (v >= 0 && v < DebugProxPath.values.length) {
    return DebugProxPath.values[v];
  }
  return DebugProxPath.never;
}

DebugMotionState _motion(int v) {
  if (v >= 0 && v < DebugMotionState.values.length) {
    return DebugMotionState.values[v];
  }
  return DebugMotionState.unknown;
}

WatchRemovedResult _removedResult(int v) {
  if (v >= 0 && v < WatchRemovedResult.values.length) {
    return WatchRemovedResult.values[v];
  }
  return WatchRemovedResult.sendFailed;
}

AnchorUdpResult _udpResult(int v) {
  if (v >= 0 && v < AnchorUdpResult.values.length) {
    return AnchorUdpResult.values[v];
  }
  return AnchorUdpResult.other;
}

/// 16 bytes at [offset] in printed order → canonical lowercase UUID string.
String _uuidAt(ByteData data, int offset) {
  final b = data.buffer.asUint8List(data.offsetInBytes + offset, 16);
  String h(int s, int e) => b
      .sublist(s, e)
      .map((v) => v.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

String _uuidOrEmpty(ByteData data, int offset) {
  for (int i = 0; i < 16; i++) {
    if (data.getUint8(offset + i) != 0) return _uuidAt(data, offset);
  }
  return '';
}

String _ipv4(ByteData data, int offset) =>
    '${data.getUint8(offset)}.${data.getUint8(offset + 1)}.'
    '${data.getUint8(offset + 2)}.${data.getUint8(offset + 3)}';

/// Minutes since local midnight for a Unix-second clock and a tz offset.
int _minuteOfDay(int utcSeconds, int tzOffsetMin) {
  final localSeconds = utcSeconds + tzOffsetMin * 60;
  final daySeconds = localSeconds % 86400;
  return ((daySeconds < 0 ? daySeconds + 86400 : daySeconds) ~/ 60) % 1440;
}
