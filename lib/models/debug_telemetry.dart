// Debug Telemetry v2 — the app's read-only mirror of the nRF firmware
// snapshots (watch `…001D`, anchor `…0020`).
//
// These classes are pure data: no Flutter, no I/O. The wire contract is
// `/tmp/impulse-briefs/nrf/contract_draft.md` §4 as amended by
// `contract_amendments.md` (the amendments win). Byte for byte:
//
//   * offset 0 is the version (= 2) and the payload is rejected outright for any
//     other version — no device serves v1 any more, so guessing would only
//     produce garbage that looks like telemetry;
//   * offset 1 is `header_len`, 2 is `record_count`, 3 is `record_len`; records
//     begin at `header_len` and are `record_len` apart, so a later version may
//     widen the header without moving the records in this decoder's head;
//   * every multi-byte field is little-endian except IPv4, which is four octets
//     in network order;
//   * documented sentinels map to Dart `null` (0xFFFF age/distance, 0xFFFFFFFF
//     timestamp, 0xFF "none / not applicable", all-zero UUID, all-FF address);
//   * a byte inside an enum's range is a typed value; a byte outside it is
//     `unknown`, which keeps the raw number instead of inventing a verdict.
//
// The notify characteristic is NOT a payload: §4.5 defines an 8-byte change
// hint. [WatchDebugTelemetry.isHint] / [AnchorDebugTelemetry.isHint] recognise
// it so the transport can do one guarded full read; [looksTruncated] answers
// the narrower question "is this a v2 value cut short of its own header?".
//
// Arrival time is deliberately not part of the model: the same bytes can be
// decoded by a test or a log viewer, and a decoder that stamped the clock would
// make "how old is this snapshot?" meaningless. The reader stamps it.

import 'dart:typed_data';

// ── Wire enums ──────────────────────────────────────────────────────────────
// A Dart `enum` cannot carry the byte a value came from, and the contract wants
// both the typed value and an `unknown(raw)` fallback. These classes give the
// strong type without losing the raw byte.

/// One decoded enum value. [name] is a human label; [known] is false for a byte
/// this app does not understand, in which case [raw] is the only evidence.
abstract class WireEnum {
  final int raw;
  final String name;
  final bool known;

  const WireEnum(this.raw, this.name, {this.known = true});

  String get label => name;

  @override
  bool operator ==(Object other) =>
      other is WireEnum && other.runtimeType == runtimeType && other.raw == raw;

  @override
  int get hashCode => Object.hash(runtimeType, raw);

  @override
  String toString() => known ? name : '$name($raw)';
}

/// Watch `activity_state` (§4.1 offset 5). Note this is the DEBUG enum, whose
/// wire order deliberately differs from the Watch Status characteristic
/// `…0016` (§1.2 trap).
class DebugActivityState extends WireEnum {
  const DebugActivityState._(super.raw, super.name, {super.known});

  static const unpaired = DebugActivityState._(0, 'UNPAIRED');
  static const dormant = DebugActivityState._(1, 'DORMANT');
  static const dormantSleep = DebugActivityState._(2, 'DORMANT_SLEEP');
  static const enforcement = DebugActivityState._(3, 'ENFORCEMENT');

  static const values = [unpaired, dormant, dormantSleep, enforcement];

  static DebugActivityState fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return DebugActivityState._(raw, 'UNKNOWN', known: false);
  }
}

/// Event criterion (`criteria`, 0…4; 0xFF = no active event → null).
class DebugCriteria extends WireEnum {
  const DebugCriteria._(super.raw, super.name, {super.known});

  static const getAway = DebugCriteria._(0, 'GET_AWAY');
  static const stayNear = DebugCriteria._(1, 'STAY_NEAR');
  static const getOffWifi = DebugCriteria._(2, 'GET_OFF_WIFI');
  static const getOnWifi = DebugCriteria._(3, 'GET_ON_WIFI');
  static const phoneAway = DebugCriteria._(4, 'PHONE_AWAY');

  static const values = [getAway, stayNear, getOffWifi, getOnWifi, phoneAway];

  static DebugCriteria? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : DebugCriteria._(raw, 'UNKNOWN', known: false);
  }

  /// Wording for the checklist (the firmware name in parentheses where the
  /// two differ).
  String get humanLabel {
    switch (raw) {
      case 0: return 'Get away';
      case 1: return 'Stay near';
      case 2: return 'Get off WiFi';
      case 3: return 'Get on WiFi';
      case 4: return 'Phone away';
    }
    return 'Unknown criterion ($raw)';
  }
}

/// Enforcement profile (`profile`, 0…8; 0xFF = none → null). §3.1 guard 4:
/// 0…2 motor-only, 3…5 motor + buzzer, 6…8 buzzer-only.
class WatchProfile extends WireEnum {
  const WatchProfile._(super.raw, super.name, {super.known});

  static const motorOnlyStrict = WatchProfile._(0, 'strict · vibrate only');
  static const motorOnlyNormal = WatchProfile._(1, 'normal · vibrate only');
  static const motorOnlyLoose = WatchProfile._(2, 'loose · vibrate only');
  static const bothStrict = WatchProfile._(3, 'strict · buzz+vibrate');
  static const bothNormal = WatchProfile._(4, 'normal · buzz+vibrate');
  static const bothLoose = WatchProfile._(5, 'loose · buzz+vibrate');
  static const buzzerOnlyStrict = WatchProfile._(6, 'strict · buzz only');
  static const buzzerOnlyNormal = WatchProfile._(7, 'normal · buzz only');
  static const buzzerOnlyLoose = WatchProfile._(8, 'loose · buzz only');

  static const values = [
    motorOnlyStrict,
    motorOnlyNormal,
    motorOnlyLoose,
    bothStrict,
    bothNormal,
    bothLoose,
    buzzerOnlyStrict,
    buzzerOnlyNormal,
    buzzerOnlyLoose,
  ];

  static WatchProfile? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : WatchProfile._(raw, 'UNKNOWN', known: false);
  }

  /// The profile's mode includes the motor (0…5).
  bool get includesMotor => raw <= 5;

  /// The profile's mode includes the buzzer (3…8).
  bool get includesBuzzer => raw >= 3 && raw <= 8;
}

/// Which worn detector is compiled in (`worn_source`, offset 12).
class WornSource extends WireEnum {
  const WornSource._(super.raw, super.name, {super.known});

  static const infraRed = WornSource._(0, 'IR reflectance');
  static const imu = WornSource._(1, 'IMU stillness');

  static const values = [infraRed, imu];

  static WornSource fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return WornSource._(raw, 'UNKNOWN', known: false);
  }
}

/// The LED-ring look currently displayed (`ring_state`, 0…14; 0xFF → null).
class RingState extends WireEnum {
  const RingState._(super.raw, super.name, {super.known});

  static const off = RingState._(0, 'off');
  static const greenSolid = RingState._(1, 'green solid (met, measured)');
  static const greenBlink = RingState._(2, 'green blink (met, fail-safe)');
  static const redSolid = RingState._(3, 'red solid (unmet, measured)');
  static const redBlink = RingState._(4, 'red blink (unmet, fail-safe/lost link)');
  static const yellowSolid = RingState._(5, 'yellow solid (no verdict yet)');
  static const yellowBlink = RingState._(6, 'yellow blink (donning grace)');
  static const blueBlink = RingState._(7, 'blue blink (worn, WATCH_WORN unsent)');
  static const blueSolid = RingState._(8, 'blue solid (removed, waiting for BLE)');
  static const cyanSolid = RingState._(9, 'cyan solid (removed, WiFi join/DHCP)');
  static const cyanBlink = RingState._(10, 'cyan blink (removed, sending, no ACK)');
  static const magentaSolid = RingState._(11, 'magenta solid (anchor told)');
  static const magentaBlink = RingState._(12, 'magenta blink (anchor refused)');
  static const whiteSolid = RingState._(13, 'white solid (removed, no beep anchors)');
  static const whiteBlink = RingState._(14, 'white blink (gave up)');

  static const values = [
    off,
    greenSolid,
    greenBlink,
    redSolid,
    redBlink,
    yellowSolid,
    yellowBlink,
    blueBlink,
    blueSolid,
    cyanSolid,
    cyanBlink,
    magentaSolid,
    magentaBlink,
    whiteSolid,
    whiteBlink,
  ];

  static RingState? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : RingState._(raw, 'UNKNOWN', known: false);
  }
}

/// Escalation command (`esc_pending_cmd` / `esc_last_delivered_cmd`). 0 is a
/// real value ("none"), not a sentinel.
class EscalationCmd extends WireEnum {
  const EscalationCmd._(super.raw, super.name, {super.known});

  static const none = EscalationCmd._(0, 'none');
  static const watchRemoved = EscalationCmd._(1, 'WATCH_REMOVED');
  static const watchWorn = EscalationCmd._(2, 'WATCH_WORN');

  static const values = [none, watchRemoved, watchWorn];

  static EscalationCmd fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return EscalationCmd._(raw, 'UNKNOWN', known: false);
  }
}

/// Where a device's clock came from (`clock_source`, R7). 0xFF → null.
///
/// This is the field that explains a silent anchor: "time_valid = 1 but 9
/// hours slow" is indistinguishable from correct without knowing where the
/// value came from (contract §1.1, §2.1). The anchor has no clock source of
/// its own, so most of its clocks are flash, retained RAM or a bench command.
class ClockSource extends WireEnum {
  const ClockSource._(super.raw, super.name, {super.known});

  static const never = ClockSource._(0, 'never set');
  static const flash = ClockSource._(1, 'restored from flash');
  static const retainedRam = ClockSource._(2, 'restored from retained RAM (warm reset)');
  static const setThisBoot = ClockSource._(3, 'set this boot');

  static const values = [never, flash, retainedRam, setThisBoot];

  static ClockSource? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : ClockSource._(raw, 'UNKNOWN', known: false);
  }
}

/// `esc_last_ack_result`: the §4.6.1 result byte from the anchor that answered
/// (0xFF = none → null).
class EscalationAck extends WireEnum {
  const EscalationAck._(super.raw, super.name, {super.known});

  static const applied = EscalationAck._(0, 'applied');
  static const heardNotMine = EscalationAck._(1, 'heard, but not mine');

  static const values = [applied, heardNotMine];

  static EscalationAck? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : EscalationAck._(raw, 'UNKNOWN', known: false);
  }
}

/// Why a channel-sounding measurement produced no distance (§1.8).
class CsAbstainReason extends WireEnum {
  const CsAbstainReason._(super.raw, super.name, {super.known});

  static const ok = CsAbstainReason._(0, 'measurement OK');
  static const noFreshBurst = CsAbstainReason._(1, 'no fresh burst');
  static const failQuality = CsAbstainReason._(2, 'burst FAIL_QUALITY');
  static const failProcedure = CsAbstainReason._(3, 'burst FAIL_PROCEDURE');
  static const failConnect = CsAbstainReason._(4, 'FAIL_CONNECT (link)');
  static const failDisagree = CsAbstainReason._(5, 'FAIL_DISAGREE (PBR vs RTT)');
  static const rangingOff = CsAbstainReason._(6, 'ranging is off');
  static const radioBlindByChoice = CsAbstainReason._(7, 'radio blind by choice');

  static const values = [
    ok,
    noFreshBurst,
    failQuality,
    failProcedure,
    failConnect,
    failDisagree,
    rangingOff,
    radioBlindByChoice,
  ];

  static CsAbstainReason? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : CsAbstainReason._(raw, 'UNKNOWN', known: false);
  }
}

/// `enum impulse_cs_result` of the last measurement fed to the state machine
/// (0xFF = never → null).
class ProxResult extends WireEnum {
  const ProxResult._(super.raw, super.name, {super.known});

  static const ok = ProxResult._(0, 'OK');
  static const failQuality = ProxResult._(1, 'FAIL_QUALITY');
  static const failProcedure = ProxResult._(2, 'FAIL_PROCEDURE');
  static const failConnect = ProxResult._(3, 'FAIL_CONNECT');
  static const failDisagree = ProxResult._(4, 'FAIL_DISAGREE');

  static const values = [ok, failQuality, failProcedure, failConnect, failDisagree];

  static ProxResult? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : ProxResult._(raw, 'UNKNOWN', known: false);
  }
}

/// `last_poll_met` (0 not met, 1 met, 0xFF never → null).
class PollMet extends WireEnum {
  const PollMet._(super.raw, super.name, {super.known});

  static const notMet = PollMet._(0, 'not met');
  static const met = PollMet._(1, 'met');

  static const values = [notMet, met];

  static PollMet? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : PollMet._(raw, 'UNKNOWN', known: false);
  }
}

/// `last_decision` — which branch of `impulse_enforcement_check_condition()`
/// produced the verdict (§1.3). This is the enum the whole page exists for:
/// without it the app can show *that* nothing beeped but not *why*.
class WatchDecision extends WireEnum {
  const WatchDecision._(super.raw, super.name, {super.known});

  static const notEvaluated = WatchDecision._(0, 'not evaluated since window entry');
  static const noEvent = WatchDecision._(1, 'no active event → met');
  static const grace = WatchDecision._(2, 'donning grace → met');
  static const stayNearNear = WatchDecision._(3, 'STAY_NEAR + NEAR → met');
  static const stayNearAway = WatchDecision._(4, 'STAY_NEAR + AWAY → not met');
  static const stayNearAbstain = WatchDecision._(5, 'STAY_NEAR abstention fail-safe → not met');
  static const getAwayAway = WatchDecision._(6, 'GET_AWAY + AWAY → met');
  static const getAwayNear = WatchDecision._(7, 'GET_AWAY + NEAR → not met');
  static const getAwayAbstain = WatchDecision._(8, 'GET_AWAY abstention fail-safe → met');
  static const onWifiMet = WatchDecision._(9, 'GET_ON_WIFI associated → met');
  static const onWifiUnmet = WatchDecision._(10, 'GET_ON_WIFI not associated → not met');
  static const offWifiMet = WatchDecision._(11, 'GET_OFF_WIFI not on the SSID → met');
  static const offWifiUnmet = WatchDecision._(12, 'GET_OFF_WIFI on the SSID → not met');
  static const phoneAwayAbstain = WatchDecision._(13, 'PHONE_AWAY abstention fail-safe → met');
  static const phoneAwayNoVerdict = WatchDecision._(14, 'PHONE_AWAY no verdict yet → met');
  static const phoneAwayMet = WatchDecision._(15, 'PHONE_AWAY phone with user / inside 60 s → met');
  static const phoneAwayUnmet = WatchDecision._(16, 'PHONE_AWAY phone with user past 60 s → not met');
  static const unknownCriterion = WatchDecision._(17, 'unknown criterion → met (fail open)');
  static const lostLinkAway = WatchDecision._(18, 'AWAY concluded by the lost link');

  static const values = [
    notEvaluated,
    noEvent,
    grace,
    stayNearNear,
    stayNearAway,
    stayNearAbstain,
    getAwayAway,
    getAwayNear,
    getAwayAbstain,
    onWifiMet,
    onWifiUnmet,
    offWifiMet,
    offWifiUnmet,
    phoneAwayAbstain,
    phoneAwayNoVerdict,
    phoneAwayMet,
    phoneAwayUnmet,
    unknownCriterion,
    lostLinkAway,
  ];

  static WatchDecision? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : WatchDecision._(raw, 'UNKNOWN', known: false);
  }

  /// Whether this branch concluded the commitment is satisfied. Null where the
  /// branch says nothing on its own (not evaluated yet; lost-link AWAY, whose
  /// outcome depends on the criterion).
  bool? get met {
    switch (raw) {
      case 1: case 2: case 3: case 6: case 8: case 9:
      case 11: case 13: case 14: case 15: case 17:
        return true;
      case 4: case 5: case 7: case 10: case 12: case 16:
        return false;
    }
    return null;
  }
}

/// `link_peer_kind` — the identity verdict the page exists for (§1.7). 0 is a
/// real value: "the watch cannot tell which anchor it is ranging".
class LinkPeerKind extends WireEnum {
  const LinkPeerKind._(super.raw, super.name, {super.known});

  static const unknown = LinkPeerKind._(0, 'unknown');
  static const eventAnchor = LinkPeerKind._(1, "the active event's anchor");
  static const otherAnchor = LinkPeerKind._(2, 'a different anchor');

  static const values = [unknown, eventAnchor, otherAnchor];

  static LinkPeerKind fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return LinkPeerKind._(raw, 'UNKNOWN', known: false);
  }
}

/// `link_peer_addr_type` (0xFF = unknown → null).
class LinkPeerAddrType extends WireEnum {
  const LinkPeerAddrType._(super.raw, super.name, {super.known});

  static const publicAddress = LinkPeerAddrType._(0, 'public');
  static const randomStatic = LinkPeerAddrType._(1, 'random static');
  static const rpa = LinkPeerAddrType._(2, 'RPA');

  static const values = [publicAddress, randomStatic, rpa];

  static LinkPeerAddrType? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF
        ? null
        : LinkPeerAddrType._(raw, 'UNKNOWN', known: false);
  }
}

/// Per-record verdict (§4.2 offset 28): 0 NEAR, 1 AWAY, 2 ABSTAIN, 0xFF
/// NOT_RANGED. All four are real states — NOT_RANGED is the honest answer for
/// an anchor the schedule names but the watch has never ranged.
class ProxVerdict extends WireEnum {
  const ProxVerdict._(super.raw, super.name, {super.known});

  static const near = ProxVerdict._(0, 'NEAR');
  static const away = ProxVerdict._(1, 'AWAY');
  static const abstain = ProxVerdict._(2, 'ABSTAIN');
  static const notRanged = ProxVerdict._(0xFF, 'NOT_RANGED');

  static const values = [near, away, abstain, notRanged];

  static ProxVerdict fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return ProxVerdict._(raw, 'UNKNOWN', known: false);
  }

  bool get ranged => this != notRanged;
}

/// Which radio may be on the air (`radio_phase`).
class RadioPhase extends WireEnum {
  const RadioPhase._(super.raw, super.name, {super.known});

  static const ble = RadioPhase._(0, 'BLE');
  static const wifi = RadioPhase._(1, 'WiFi');

  static const values = [ble, wifi];

  static RadioPhase fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return RadioPhase._(raw, 'UNKNOWN', known: false);
  }
}

// ── Anchor enums ────────────────────────────────────────────────────────────

/// The anchor's beep profile (`beep_profile`, 0…2; 0xFF = not beeping → null).
class BeepProfile extends WireEnum {
  const BeepProfile._(super.raw, super.name, {super.known});

  static const light = BeepProfile._(0, 'light (3000/60000 ms)');
  static const medium = BeepProfile._(1, 'medium (3000/30000 ms)');
  static const hard = BeepProfile._(2, 'hard (4000/10000 ms)');

  static const values = [light, medium, hard];

  static BeepProfile? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : BeepProfile._(raw, 'UNKNOWN', known: false);
  }
}

/// `last_cmd` (0 none, 1 WATCH_REMOVED, 2 WATCH_WORN, 0xFF other).
class AnchorCmd extends WireEnum {
  const AnchorCmd._(super.raw, super.name, {super.known});

  static const none = AnchorCmd._(0, 'none');
  static const watchRemoved = AnchorCmd._(1, 'WATCH_REMOVED');
  static const watchWorn = AnchorCmd._(2, 'WATCH_WORN');
  static const other = AnchorCmd._(0xFF, 'other');

  static const values = [none, watchRemoved, watchWorn, other];

  static AnchorCmd fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return AnchorCmd._(raw, 'UNKNOWN', known: false);
  }
}

/// `last_cmd_result`: the §4.6.1 result byte (0xFF = none / no command → null).
class AnchorCmdResult extends WireEnum {
  const AnchorCmdResult._(super.raw, super.name, {super.known});

  static const applied = AnchorCmdResult._(0, 'applied');
  static const notMine = AnchorCmdResult._(1, 'not mine');
  static const malformed = AnchorCmdResult._(2, 'malformed');

  static const values = [applied, notMine, malformed];

  static AnchorCmdResult? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF
        ? null
        : AnchorCmdResult._(raw, 'UNKNOWN', known: false);
  }
}

/// `last_cmd_reason` — the fine-grained branch that produced the result
/// (§2.4), including the three causes the result byte collapses into
/// "not mine". (0xFF = none since boot → null.)
class AnchorCmdReason extends WireEnum {
  const AnchorCmdReason._(super.raw, super.name, {super.known});

  static const noReason = AnchorCmdReason._(0, 'no reason recorded');
  static const started = AnchorCmdReason._(1, 'applied, alarm started');
  static const alreadyBeeping = AnchorCmdReason._(2, 'applied, already beeping with this profile');
  static const stoppedByWorn = AnchorCmdReason._(3, 'applied, WATCH_WORN stopped the alarm');
  static const profileDefaulted = AnchorCmdReason._(4, 'applied, anchorProfile missing → MEDIUM assumed');
  static const unknownEvent = AnchorCmdReason._(5, 'not mine: event unknown to this anchor');
  static const outsideWindow = AnchorCmdReason._(6, 'not mine: window not open on the anchor clock');
  static const negated = AnchorCmdReason._(7, 'not mine: event negated today');
  static const notInBeepList = AnchorCmdReason._(8, 'not mine: anchor not in beepAnchors');
  static const malformedLength = AnchorCmdReason._(9, 'malformed: wrong length');
  static const malformedCommand = AnchorCmdReason._(10, 'malformed: unknown command byte');
  static const other = AnchorCmdReason._(11, 'other');

  static const values = [
    noReason,
    started,
    alreadyBeeping,
    stoppedByWorn,
    profileDefaulted,
    unknownEvent,
    outsideWindow,
    negated,
    notInBeepList,
    malformedLength,
    malformedCommand,
    other,
  ];

  static AnchorCmdReason? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF
        ? null
        : AnchorCmdReason._(raw, 'UNKNOWN', known: false);
  }

  /// True for the reasons that mean "the alarm is (or was) running".
  bool get accepted => raw >= 1 && raw <= 4;
}

/// `last_cmd_transport` (0xFF = none → null).
class AnchorCmdTransport extends WireEnum {
  const AnchorCmdTransport._(super.raw, super.name, {super.known});

  static const none = AnchorCmdTransport._(0, 'none');
  static const ble = AnchorCmdTransport._(1, 'BLE');
  static const udp = AnchorCmdTransport._(2, 'UDP');

  static const values = [none, ble, udp];

  static AnchorCmdTransport? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF
        ? null
        : AnchorCmdTransport._(raw, 'UNKNOWN', known: false);
  }
}

/// `cs_reflector_state` (0xFF = not built → null).
class CsReflectorState extends WireEnum {
  const CsReflectorState._(super.raw, super.name, {super.known});

  static const off = CsReflectorState._(0, 'off');
  static const advertising = CsReflectorState._(1, 'advertising RAS');
  static const procedures = CsReflectorState._(2, 'in procedures');

  static const values = [off, advertising, procedures];

  static CsReflectorState? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF
        ? null
        : CsReflectorState._(raw, 'UNKNOWN', known: false);
  }
}

/// `servo_state` (0xFF = unavailable → null). U1 is unpopulated on every board
/// built so far, so this is a firmware belief, not a physical fact.
class ServoState extends WireEnum {
  const ServoState._(super.raw, super.name, {super.known});

  static const closed = ServoState._(0, 'closed');
  static const open = ServoState._(1, 'open');

  static const values = [closed, open];

  static ServoState? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : ServoState._(raw, 'UNKNOWN', known: false);
  }
}

/// `dock_state` (0xFF = not supported → null; nothing produces 0/1 today).
class DockState extends WireEnum {
  const DockState._(super.raw, super.name, {super.known});

  static const undocked = DockState._(0, 'undocked');
  static const docked = DockState._(1, 'docked');

  static const values = [undocked, docked];

  static DockState? fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return raw == 0xFF ? null : DockState._(raw, 'UNKNOWN', known: false);
  }
}

/// Event recurrence (`flags1` bits 0-1 of an anchor event record).
class Recurrence extends WireEnum {
  const Recurrence._(super.raw, super.name, {super.known});

  static const once = Recurrence._(0, 'once');
  static const daily = Recurrence._(1, 'daily');
  static const weekly = Recurrence._(2, 'weekly');
  static const monthly = Recurrence._(3, 'monthly');

  static const values = [once, daily, weekly, monthly];

  static Recurrence fromWire(int raw) {
    for (final v in values) {
      if (v.raw == raw) return v;
    }
    return Recurrence._(raw, 'UNKNOWN', known: false);
  }
}

// ── Watch records ───────────────────────────────────────────────────────────

/// One 32-byte entry of the watch's per-anchor table (§4.2).
///
/// The watch keeps no per-anchor table in RAM: the firmware synthesises these
/// records from the active event plus the one live channel-sounding peer. A
/// record with `distanceCm == null` and `verdict == NOT_RANGED` is therefore
/// normal and honest, not a decoder failure.
class WatchAnchorRecord {
  /// 16-byte anchor UUID in printed order, canonical lowercase.
  final String anchorUuid;

  /// Fused burst median, or null (0xFFFF) when there is no measurement.
  final int? distanceCm;

  /// Median `ifft` estimate — the primary estimator.
  final int? ifftCm;

  /// Median `phase_slope` — the multipath/occlusion cross-check.
  final int? phaseSlopeCm;

  /// Median CS-RTT — the speed-of-light relay bound.
  final int? rttCm;

  /// Seconds since the last completed burst, or null (0xFFFF) = never.
  final int? ageS;

  /// Accepted samples in the last completed burst for the live peer.
  final int sampleCount;

  final ProxVerdict verdict;

  /// Why there is no distance, or null when there is one.
  final CsAbstainReason? abstainReason;

  final bool isEventAnchor;
  final bool inBeepList;
  final bool isLinkPeer;
  final bool identityConflict;
  final bool ipKnown;
  final bool ranged;

  /// Backend quality scale, or null (0xFF) when the backend never fills it.
  final int? quality;

  const WatchAnchorRecord({
    required this.anchorUuid,
    required this.distanceCm,
    required this.ifftCm,
    required this.phaseSlopeCm,
    required this.rttCm,
    required this.ageS,
    required this.sampleCount,
    required this.verdict,
    required this.abstainReason,
    required this.isEventAnchor,
    required this.inBeepList,
    required this.isLinkPeer,
    required this.identityConflict,
    required this.ipKnown,
    required this.ranged,
    required this.quality,
  });

  /// Distance in metres, or null when there is no measurement.
  double? get distanceM =>
      distanceCm == null ? null : distanceCm! / 100.0;

  /// "1.42 m", or "not ranged".
  String get distanceLabel =>
      distanceM == null ? 'not ranged' : '${distanceM!.toStringAsFixed(2)} m';

  Map<String, Object?> toRecordMap() {
    final m = <String, Object?>{
      'anchor_uuid': anchorUuid,
      'distance_cm': distanceCm,
      'ifft_cm': ifftCm,
      'phase_slope_cm': phaseSlopeCm,
      'rtt_cm': rttCm,
      'age_s': ageS,
      'sample_count': sampleCount,
      'verdict': verdict.raw,
      'abstain_reason': abstainReason?.raw,
      'quality': quality,
    };
    final flags = _packBits([
      (0x01, isEventAnchor),
      (0x02, inBeepList),
      (0x04, isLinkPeer),
      (0x08, identityConflict),
      (0x10, ipKnown),
      (0x20, ranged),
    ]);
    _putBits(m, 'flags', flags, const [
      (0x01, 'is_event_anchor'),
      (0x02, 'in_beep_list'),
      (0x04, 'is_link_peer'),
      (0x08, 'identity_conflict'),
      (0x10, 'ip_known'),
      (0x20, 'ranged'),
    ]);
    return m;
  }
}

/// A decoded watch `…001D` snapshot (§4.1 header + §4.2 records).
class WatchDebugTelemetry {
  static const int wireVersion = 2;

  /// R7: 180 bytes (the original 176 plus `still_threshold_s` and
  /// `motion_threshold_mms2`). `header_len` in the payload is authoritative.
  static const int headerSize = 180;
  static const int anchorRecordSize = 32;
  static const int maxAnchorRecords = 10;

  /// §4.5 notify payload: version + snapshot_seq + changed bitmap + utc_now.
  static const int hintSize = 8;

  /// True when [bytes] is the §4.5 change hint rather than a snapshot.
  /// The hint is never a payload — the reader must follow it with one full
  /// read (see `WatchService`).
  static bool isHint(List<int> bytes) =>
      bytes.length == hintSize && bytes[0] == wireVersion;

  /// True when [bytes] is a v2 value cut short of its own header plus declared
  /// records — i.e. a notification truncated to MTU−3, or the 8-byte hint.
  /// Callers use it to decide whether a failed decode is worth a full read; an
  /// unknown version or a structurally impossible header is not.
  static bool looksTruncated(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] != wireVersion) return false;
    if (bytes.length == hintSize) return true;
    if (bytes.length < 4) return true;
    final headerLen = bytes[1];
    final recordCount = bytes[2];
    final recordLen = bytes[3];
    return bytes.length < headerLen + recordCount * recordLen;
  }

  final int version;
  final int headerLen;
  final int recordCount;
  final int recordLen;
  final int maxRecords;

  final DebugActivityState activityState;
  final DebugCriteria? criteria;
  final WatchProfile? profile;

  // flags0
  final bool worn;
  final bool timeValid;
  final bool graceActive;
  final bool profileActive;
  final bool conditionMet;
  final bool verdictHave;
  final bool verdictNear;
  final bool failsafe;

  // flags1
  final bool motorOn;
  final bool buzzerOn;
  final bool buzzerCompiledOut;
  final bool motorCompiledOut;
  final bool outputSilenced;
  final bool linkUp;
  final bool linkReady;
  final bool rangingOn;

  // flags2
  final bool wifiOnAir;
  final bool bleQuiesced;
  final bool escPending;
  final bool escGaveUp;
  final bool escOnWifi;
  final bool wifiConnected;
  final bool wifiProvisioned;
  final bool ackRefused;

  // flags3
  final bool linkPeerKnown;
  final bool linkPeerIsEventAnchor;
  final bool identityConflict;
  final bool verdictFromLostLink;
  final bool graceIsLostLink;
  final bool hasEventAnchor;
  final bool anchorProfilePresent;
  final bool wifiCriteria;

  final WornSource wornSource;
  final RingState? ringState;
  final EscalationCmd escPendingCmd;
  final EscalationCmd escLastDeliveredCmd;
  final ProxResult? proxLastResult;
  final EscalationAck? escLastAckResult;
  final CsAbstainReason? csAbstainReason;
  final PollMet? lastPollMet;
  final WatchDecision? lastDecision;

  final int nearRun;
  final int awayRun;
  final int abstainRun;
  final int integrityPendingCount;
  final int beepAnchorCount;

  /// 0xFF = unknown → null.
  final int? csLastQuality;

  /// HCI reason; 0xFF = never → null.
  final int? linkLastDisconnectReason;
  final LinkPeerKind linkPeerKind;

  /// Where the watch's clock came from (R7 offset 29).
  final ClockSource? clockSource;

  /// Minutes since local midnight, or null when the clock is invalid (0xFFFF).
  final int? localMinute;
  final int? eventStartMin;
  final int? eventEndMin;
  final int nearEnterCm;
  final int awayEnterCm;
  final int donningGraceS;
  final int graceRemainingS;
  final int pollIntervalS;
  final int? sinceLastPollS;
  final int? sinceLastBurstS;

  /// Seconds of unbroken stillness, or null (0xFFFF) on an IR build.
  final int? stillForS;

  /// IMU milli-m/s² delta (IMU build) or mV (IR build); null = unavailable.
  final int? wornDiag;

  /// `CONFIG_IMPULSE_WORN_IMU_STILL_S`; null (0) when not applicable (IR build).
  final int? stillThresholdS;

  /// `CONFIG_IMPULSE_WORN_IMU_MOTION_MMS2`; null (0) when not applicable.
  final int? motionThresholdMms2;
  final int? eventIndex;
  final int bootCount;

  final int csBurstCount;
  final int csRejectedRange;
  final int csRejectedQuality;
  final int csSuspectRelay;
  final int csMissingIfft;
  final int? csDistanceCm;
  final int? csIfftCm;
  final int? csPhaseSlopeCm;
  final int? csRttCm;

  final int linkConnectAttempts;
  final int linkConnectFailures;
  final int? escSinceRequestS;
  final int escDeliveredBle;
  final int escDeliveredUdp;
  final int escWifiEntries;
  final int escAttempts;

  final int integritySettleWindowMin;
  final int passAllowance;
  final int passRemaining;

  /// Unix seconds, or null (0xFFFFFFFF) when the clock is unknown.
  final int? utcNow;
  final int tzOffsetMin;

  /// Snapshot build time (`k_uptime_get`), for cross-checking the ages.
  final int uptimeMs;
  final int? linkConnectedAtMs;
  final int? radioPhaseSinceMs;
  final int radioPhaseDwellRemainingS;
  final RadioPhase radioPhase;

  /// §4.1 offset 115: padding, always 0. Decoded so the cross-language vector
  /// check covers the whole table.
  final int reserved2;

  final String activeEventId;
  final String eventAnchorId;
  final String linkPeerUuid;

  /// `AA:BB:CC:DD:EE:FF`, or null when unknown (all-FF address).
  final String? linkPeerAddr;
  final LinkPeerAddrType? linkPeerAddrType;

  /// Free-running mod 256: changes ⇒ a snapshot was rebuilt mid-read.
  final int snapshotSeq;

  /// Dotted quad, or null when there is no address (0.0.0.0).
  final String? ownIpv4;

  final List<WatchAnchorRecord> anchors;

  const WatchDebugTelemetry({
    required this.version,
    required this.headerLen,
    required this.recordCount,
    required this.recordLen,
    required this.maxRecords,
    required this.activityState,
    required this.criteria,
    required this.profile,
    required this.worn,
    required this.timeValid,
    required this.graceActive,
    required this.profileActive,
    required this.conditionMet,
    required this.verdictHave,
    required this.verdictNear,
    required this.failsafe,
    required this.motorOn,
    required this.buzzerOn,
    required this.buzzerCompiledOut,
    required this.motorCompiledOut,
    required this.outputSilenced,
    required this.linkUp,
    required this.linkReady,
    required this.rangingOn,
    required this.wifiOnAir,
    required this.bleQuiesced,
    required this.escPending,
    required this.escGaveUp,
    required this.escOnWifi,
    required this.wifiConnected,
    required this.wifiProvisioned,
    required this.ackRefused,
    required this.linkPeerKnown,
    required this.linkPeerIsEventAnchor,
    required this.identityConflict,
    required this.verdictFromLostLink,
    required this.graceIsLostLink,
    required this.hasEventAnchor,
    required this.anchorProfilePresent,
    required this.wifiCriteria,
    required this.wornSource,
    required this.ringState,
    required this.escPendingCmd,
    required this.escLastDeliveredCmd,
    required this.proxLastResult,
    required this.escLastAckResult,
    required this.csAbstainReason,
    required this.lastPollMet,
    required this.lastDecision,
    required this.nearRun,
    required this.awayRun,
    required this.abstainRun,
    required this.integrityPendingCount,
    required this.beepAnchorCount,
    required this.csLastQuality,
    required this.linkLastDisconnectReason,
    required this.linkPeerKind,
    required this.clockSource,
    required this.localMinute,
    required this.eventStartMin,
    required this.eventEndMin,
    required this.nearEnterCm,
    required this.awayEnterCm,
    required this.donningGraceS,
    required this.graceRemainingS,
    required this.pollIntervalS,
    required this.sinceLastPollS,
    required this.sinceLastBurstS,
    required this.stillForS,
    required this.wornDiag,
    required this.stillThresholdS,
    required this.motionThresholdMms2,
    required this.eventIndex,
    required this.bootCount,
    required this.csBurstCount,
    required this.csRejectedRange,
    required this.csRejectedQuality,
    required this.csSuspectRelay,
    required this.csMissingIfft,
    required this.csDistanceCm,
    required this.csIfftCm,
    required this.csPhaseSlopeCm,
    required this.csRttCm,
    required this.linkConnectAttempts,
    required this.linkConnectFailures,
    required this.escSinceRequestS,
    required this.escDeliveredBle,
    required this.escDeliveredUdp,
    required this.escWifiEntries,
    required this.escAttempts,
    required this.integritySettleWindowMin,
    required this.passAllowance,
    required this.passRemaining,
    required this.utcNow,
    required this.tzOffsetMin,
    required this.uptimeMs,
    required this.linkConnectedAtMs,
    required this.radioPhaseSinceMs,
    required this.radioPhaseDwellRemainingS,
    required this.radioPhase,
    required this.reserved2,
    required this.activeEventId,
    required this.eventAnchorId,
    required this.linkPeerUuid,
    required this.linkPeerAddr,
    required this.linkPeerAddrType,
    required this.snapshotSeq,
    required this.ownIpv4,
    required this.anchors,
  });

  /// True when a window is being enforced and the watch knows its criterion.
  bool get hasActiveEvent =>
      activityState == DebugActivityState.enforcement && criteria != null;

  /// The watch's local wall time, or null when the clock is invalid.
  DateTime? get watchLocalTime {
    final utc = utcNow;
    if (!timeValid || utc == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(utc * 1000, isUtc: true)
        .add(Duration(minutes: tzOffsetMin));
  }

  /// True when the lock-screen reason this snapshot shows is a rule, not
  /// evidence: the abstention fail-safe fires after >5 consecutive misses.
  bool get abstainFailSafe => failsafe;

  /// The record for [uuid], or null when the watch did not report it.
  WatchAnchorRecord? anchorRecord(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    for (final a in anchors) {
      if (a.anchorUuid == uuid) return a;
    }
    return null;
  }

  /// The record that carries real numbers — the one live ranging peer — or
  /// null when nothing in this snapshot has been ranged.
  WatchAnchorRecord? get liveRangedRecord {
    for (final a in anchors) {
      if (a.isLinkPeer && a.ranged) return a;
    }
    for (final a in anchors) {
      if (a.ranged) return a;
    }
    return null;
  }

  String get profileLabel => profile?.label ?? 'none';

  /// Every decoded header field by its §4.1 name. Used by the vector test and
  /// by the log; flags are emitted both as the raw byte and per bit, because
  /// the cross-language vector file may describe them either way.
  Map<String, Object?> fieldsMap() {
    final m = <String, Object?>{
      'version': version,
      'header_len': headerLen,
      'record_count': recordCount,
      'record_len': recordLen,
      'max_records': maxRecords,
      'activity_state': activityState.raw,
      'criteria': criteria?.raw,
      'profile': profile?.raw,
      'worn_source': wornSource.raw,
      'ring_state': ringState?.raw,
      'esc_pending_cmd': escPendingCmd.raw,
      'esc_last_delivered_cmd': escLastDeliveredCmd.raw,
      'prox_last_result': proxLastResult?.raw,
      'esc_last_ack_result': escLastAckResult?.raw,
      'cs_abstain_reason': csAbstainReason?.raw,
      'last_poll_met': lastPollMet?.raw,
      'last_decision': lastDecision?.raw,
      'near_run': nearRun,
      'away_run': awayRun,
      'abstain_run': abstainRun,
      'integrity_pending_count': integrityPendingCount,
      'beep_anchor_count': beepAnchorCount,
      'cs_last_quality': csLastQuality,
      'link_last_disconnect_reason': linkLastDisconnectReason,
      'link_peer_kind': linkPeerKind.raw,
      'clock_source': clockSource?.raw,
      'still_threshold_s': stillThresholdS,
      'motion_threshold_mms2': motionThresholdMms2,
      'local_minute': localMinute,
      'event_start_min': eventStartMin,
      'event_end_min': eventEndMin,
      'near_enter_cm': nearEnterCm,
      'away_enter_cm': awayEnterCm,
      'donning_grace_s': donningGraceS,
      'grace_remaining_s': graceRemainingS,
      'poll_interval_s': pollIntervalS,
      'since_last_poll_s': sinceLastPollS,
      'since_last_burst_s': sinceLastBurstS,
      'still_for_s': stillForS,
      'worn_diag': wornDiag,
      'event_index': eventIndex,
      'boot_count': bootCount,
      'cs_burst_count': csBurstCount,
      'cs_rejected_range': csRejectedRange,
      'cs_rejected_quality': csRejectedQuality,
      'cs_suspect_relay': csSuspectRelay,
      'cs_missing_ifft': csMissingIfft,
      'cs_distance_cm': csDistanceCm,
      'cs_ifft_cm': csIfftCm,
      'cs_phase_slope_cm': csPhaseSlopeCm,
      'cs_rtt_cm': csRttCm,
      'link_connect_attempts': linkConnectAttempts,
      'link_connect_failures': linkConnectFailures,
      'esc_since_request_s': escSinceRequestS,
      'esc_delivered_ble': escDeliveredBle,
      'esc_delivered_udp': escDeliveredUdp,
      'esc_wifi_entries': escWifiEntries,
      'integrity_settle_window_min': integritySettleWindowMin,
      'pass_allowance': passAllowance,
      'pass_remaining': passRemaining,
      'esc_attempts': escAttempts,
      'utc_now': utcNow,
      'tz_offset_min': tzOffsetMin,
      'uptime_ms': uptimeMs,
      'link_connected_at_ms': linkConnectedAtMs,
      'radio_phase_since_ms': radioPhaseSinceMs,
      'radio_phase_dwell_remaining_s': radioPhaseDwellRemainingS,
      'radio_phase': radioPhase.raw,
      'reserved2': reserved2,
      'active_event_id': activeEventId.isEmpty ? null : activeEventId,
      'event_anchor_id': eventAnchorId.isEmpty ? null : eventAnchorId,
      'link_peer_uuid': linkPeerUuid.isEmpty ? null : linkPeerUuid,
      'link_peer_addr': linkPeerAddr,
      'link_peer_addr_type': linkPeerAddrType?.raw,
      'snapshot_seq': snapshotSeq,
      'own_ipv4': ownIpv4,
    };
    _putBits(m, 'flags0', _packBits([
      (0x01, worn),
      (0x02, timeValid),
      (0x04, graceActive),
      (0x08, profileActive),
      (0x10, conditionMet),
      (0x20, verdictHave),
      (0x40, verdictNear),
      (0x80, failsafe),
    ]), const [
      (0x01, 'worn'),
      (0x02, 'time_valid'),
      (0x04, 'grace_active'),
      (0x08, 'profile_active'),
      (0x10, 'condition_met'),
      (0x20, 'verdict_have'),
      (0x40, 'verdict_near'),
      (0x80, 'failsafe'),
    ]);
    _putBits(m, 'flags1', _packBits([
      (0x01, motorOn),
      (0x02, buzzerOn),
      (0x04, buzzerCompiledOut),
      (0x08, motorCompiledOut),
      (0x10, outputSilenced),
      (0x20, linkUp),
      (0x40, linkReady),
      (0x80, rangingOn),
    ]), const [
      (0x01, 'motor_on'),
      (0x02, 'buzzer_on'),
      (0x04, 'buzzer_compiled_out'),
      (0x08, 'motor_compiled_out'),
      (0x10, 'output_silenced'),
      (0x20, 'link_up'),
      (0x40, 'link_ready'),
      (0x80, 'ranging_on'),
    ]);
    _putBits(m, 'flags2', _packBits([
      (0x01, wifiOnAir),
      (0x02, bleQuiesced),
      (0x04, escPending),
      (0x08, escGaveUp),
      (0x10, escOnWifi),
      (0x20, wifiConnected),
      (0x40, wifiProvisioned),
      (0x80, ackRefused),
    ]), const [
      (0x01, 'wifi_on_air'),
      (0x02, 'ble_quiesced'),
      (0x04, 'esc_pending'),
      (0x08, 'esc_gave_up'),
      (0x10, 'esc_on_wifi'),
      (0x20, 'wifi_connected'),
      (0x40, 'wifi_provisioned'),
      (0x80, 'ack_refused'),
    ]);
    _putBits(m, 'flags3', _packBits([
      (0x01, linkPeerKnown),
      (0x02, linkPeerIsEventAnchor),
      (0x04, identityConflict),
      (0x08, verdictFromLostLink),
      (0x10, graceIsLostLink),
      (0x20, hasEventAnchor),
      (0x40, anchorProfilePresent),
      (0x80, wifiCriteria),
    ]), const [
      (0x01, 'link_peer_known'),
      (0x02, 'link_peer_is_event_anchor'),
      (0x04, 'identity_conflict'),
      (0x08, 'verdict_from_lost_link'),
      (0x10, 'grace_is_lost_link'),
      (0x20, 'has_event_anchor'),
      (0x40, 'anchor_profile_present'),
      (0x80, 'wifi_criteria'),
    ]);
    // views over the same bits, so a vector file can name either form
    m['worn'] = worn;
    m['time_valid'] = timeValid;
    m['condition_met'] = conditionMet;
    m['verdict_have'] = verdictHave;
    m['verdict_near'] = verdictNear;
    m['identity_conflict'] = identityConflict;
    return m;
  }

  /// Decode a `…001D` snapshot. Throws [FormatException] when the payload is
  /// too short for its own header, declares more records than the layout
  /// allows, is shorter than the records it declares, or carries a version
  /// this app does not serve. Bytes past the last record are ignored.
  static WatchDebugTelemetry decode(List<int> bytes) {
    if (bytes.length < 4) {
      throw FormatException(
          'watch debug telemetry: ${bytes.length} bytes is shorter than the '
          '4-byte versioned header');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final version = data.getUint8(0);
    if (version != wireVersion) {
      throw FormatException('unsupported telemetry version $version');
    }
    final headerLen = data.getUint8(1);
    final recordCount = data.getUint8(2);
    final recordLen = data.getUint8(3);
    if (headerLen < headerSize) {
      throw FormatException(
          'watch debug telemetry: header_len $headerLen < $headerSize');
    }
    if (bytes.length < headerLen) {
      throw FormatException(
          'watch debug telemetry: ${bytes.length} bytes < header_len '
          '$headerLen');
    }
    if (recordCount > maxAnchorRecords) {
      throw FormatException(
          'watch debug telemetry: $recordCount records > $maxAnchorRecords');
    }
    if (recordLen < anchorRecordSize) {
      throw FormatException(
          'watch debug telemetry: record_len $recordLen < $anchorRecordSize');
    }
    final need = headerLen + recordCount * recordLen;
    if (bytes.length < need) {
      throw FormatException(
          'watch debug telemetry: ${bytes.length} bytes < $need '
          '($recordCount records of $recordLen)');
    }

    final flags0 = data.getUint8(8);
    final flags1 = data.getUint8(9);
    final flags2 = data.getUint8(10);
    final flags3 = data.getUint8(11);

    final anchors = <WatchAnchorRecord>[];
    for (int i = 0; i < recordCount; i++) {
      final o = headerLen + i * recordLen;
      final flags = data.getUint8(o + 30);
      final abstain = data.getUint8(o + 29);
      anchors.add(WatchAnchorRecord(
        anchorUuid: _uuidAt(data, o),
        distanceCm: _u16OrNull(data, o + 16),
        ifftCm: _u16OrNull(data, o + 18),
        phaseSlopeCm: _u16OrNull(data, o + 20),
        rttCm: _u16OrNull(data, o + 22),
        ageS: _u16OrNull(data, o + 24),
        sampleCount: data.getUint16(o + 26, Endian.little),
        verdict: ProxVerdict.fromWire(data.getUint8(o + 28)),
        // 0xFE is the record's own "not ranged" marker (§4.2), not an
        // abstention reason: it belongs to the verdict, not this field.
        abstainReason: abstain == 0xFE ? null : CsAbstainReason.fromWire(abstain),
        isEventAnchor: (flags & 0x01) != 0,
        inBeepList: (flags & 0x02) != 0,
        isLinkPeer: (flags & 0x04) != 0,
        identityConflict: (flags & 0x08) != 0,
        ipKnown: (flags & 0x10) != 0,
        ranged: (flags & 0x20) != 0,
        quality: _u8OrNull(data.getUint8(o + 31)),
      ));
    }

    return WatchDebugTelemetry(
      version: version,
      headerLen: headerLen,
      recordCount: recordCount,
      recordLen: recordLen,
      maxRecords: data.getUint8(4),
      activityState: DebugActivityState.fromWire(data.getUint8(5)),
      criteria: DebugCriteria.fromWire(data.getUint8(6)),
      profile: WatchProfile.fromWire(data.getUint8(7)),
      worn: (flags0 & 0x01) != 0,
      timeValid: (flags0 & 0x02) != 0,
      graceActive: (flags0 & 0x04) != 0,
      profileActive: (flags0 & 0x08) != 0,
      conditionMet: (flags0 & 0x10) != 0,
      verdictHave: (flags0 & 0x20) != 0,
      verdictNear: (flags0 & 0x40) != 0,
      failsafe: (flags0 & 0x80) != 0,
      motorOn: (flags1 & 0x01) != 0,
      buzzerOn: (flags1 & 0x02) != 0,
      buzzerCompiledOut: (flags1 & 0x04) != 0,
      motorCompiledOut: (flags1 & 0x08) != 0,
      outputSilenced: (flags1 & 0x10) != 0,
      linkUp: (flags1 & 0x20) != 0,
      linkReady: (flags1 & 0x40) != 0,
      rangingOn: (flags1 & 0x80) != 0,
      wifiOnAir: (flags2 & 0x01) != 0,
      bleQuiesced: (flags2 & 0x02) != 0,
      escPending: (flags2 & 0x04) != 0,
      escGaveUp: (flags2 & 0x08) != 0,
      escOnWifi: (flags2 & 0x10) != 0,
      wifiConnected: (flags2 & 0x20) != 0,
      wifiProvisioned: (flags2 & 0x40) != 0,
      ackRefused: (flags2 & 0x80) != 0,
      linkPeerKnown: (flags3 & 0x01) != 0,
      linkPeerIsEventAnchor: (flags3 & 0x02) != 0,
      identityConflict: (flags3 & 0x04) != 0,
      verdictFromLostLink: (flags3 & 0x08) != 0,
      graceIsLostLink: (flags3 & 0x10) != 0,
      hasEventAnchor: (flags3 & 0x20) != 0,
      anchorProfilePresent: (flags3 & 0x40) != 0,
      wifiCriteria: (flags3 & 0x80) != 0,
      wornSource: WornSource.fromWire(data.getUint8(12)),
      ringState: RingState.fromWire(data.getUint8(13)),
      escPendingCmd: EscalationCmd.fromWire(data.getUint8(14)),
      escLastDeliveredCmd: EscalationCmd.fromWire(data.getUint8(15)),
      proxLastResult: ProxResult.fromWire(data.getUint8(16)),
      escLastAckResult: EscalationAck.fromWire(data.getUint8(17)),
      csAbstainReason: CsAbstainReason.fromWire(data.getUint8(18)),
      lastPollMet: PollMet.fromWire(data.getUint8(19)),
      lastDecision: WatchDecision.fromWire(data.getUint8(20)),
      nearRun: data.getUint8(21),
      awayRun: data.getUint8(22),
      abstainRun: data.getUint8(23),
      integrityPendingCount: data.getUint8(24),
      beepAnchorCount: data.getUint8(25),
      csLastQuality: _u8OrNull(data.getUint8(26)),
      linkLastDisconnectReason: _u8OrNull(data.getUint8(27)),
      linkPeerKind: LinkPeerKind.fromWire(data.getUint8(28)),
      clockSource: ClockSource.fromWire(data.getUint8(29)),
      localMinute: _u16OrNull(data, 30),
      eventStartMin: _u16OrNull(data, 32),
      eventEndMin: _u16OrNull(data, 34),
      nearEnterCm: data.getUint16(36, Endian.little),
      awayEnterCm: data.getUint16(38, Endian.little),
      donningGraceS: data.getUint16(40, Endian.little),
      graceRemainingS: data.getUint16(42, Endian.little),
      pollIntervalS: data.getUint16(44, Endian.little),
      sinceLastPollS: _u16OrNull(data, 46),
      sinceLastBurstS: _u16OrNull(data, 48),
      stillForS: _u16OrNull(data, 50),
      wornDiag: _i16OrNull(data, 52, 0x7FFF),
      stillThresholdS: _zeroOrNull(data.getUint16(176, Endian.little)),
      motionThresholdMms2: _zeroOrNull(data.getUint16(178, Endian.little)),
      eventIndex: _u16OrNull(data, 54),
      bootCount: data.getUint16(56, Endian.little),
      csBurstCount: data.getUint16(58, Endian.little),
      csRejectedRange: data.getUint16(60, Endian.little),
      csRejectedQuality: data.getUint16(62, Endian.little),
      csSuspectRelay: data.getUint16(64, Endian.little),
      csMissingIfft: data.getUint16(66, Endian.little),
      csDistanceCm: _u16OrNull(data, 68),
      csIfftCm: _u16OrNull(data, 70),
      csPhaseSlopeCm: _u16OrNull(data, 72),
      csRttCm: _u16OrNull(data, 74),
      linkConnectAttempts: data.getUint16(76, Endian.little),
      linkConnectFailures: data.getUint16(78, Endian.little),
      escSinceRequestS: _u16OrNull(data, 80),
      escDeliveredBle: data.getUint16(82, Endian.little),
      escDeliveredUdp: data.getUint16(84, Endian.little),
      escWifiEntries: data.getUint16(86, Endian.little),
      integritySettleWindowMin: data.getUint16(88, Endian.little),
      passAllowance: data.getUint8(90),
      passRemaining: data.getUint8(91),
      escAttempts: data.getUint16(92, Endian.little),
      utcNow: _u32OrNull(data, 94),
      tzOffsetMin: data.getInt16(98, Endian.little),
      uptimeMs: data.getUint32(100, Endian.little),
      linkConnectedAtMs: _u32OrNull(data, 104),
      radioPhaseSinceMs: _u32OrNull(data, 108),
      radioPhaseDwellRemainingS: data.getUint16(112, Endian.little),
      radioPhase: RadioPhase.fromWire(data.getUint8(114)),
      reserved2: data.getUint8(115),
      activeEventId: _uuidOrEmpty(data, 116),
      eventAnchorId: _uuidOrEmpty(data, 132),
      linkPeerUuid: _uuidOrEmpty(data, 148),
      linkPeerAddr: _addrOrNull(data, 164),
      linkPeerAddrType: LinkPeerAddrType.fromWire(data.getUint8(170)),
      snapshotSeq: data.getUint8(171),
      ownIpv4: _ipv4OrNull(data, 172),
      anchors: List.unmodifiable(anchors),
    );
  }
}

// ── Anchor records ──────────────────────────────────────────────────────────

/// One 24-byte entry of the anchor's event table (§4.4): today's events that
/// name this anchor.
class AnchorEventRecord {
  /// 16-byte event UUID in printed order, canonical lowercase.
  final String eventId;
  final int startMin;

  /// Exclusive.
  final int endMin;
  final DebugCriteria? criteria;

  final bool negatedToday;
  final bool inBeepList;

  /// `PHONE_AWAY && anchorId == this anchor` — a dock event, which this
  /// firmware cannot act on (§2.7). Cross-check `dockSupported`.
  final bool isDockEvent;
  final bool hasAnchorProfile;
  final bool windowOpenNow;

  /// The event names this anchor as `anchorId` (as opposed to `beepAnchors`).
  final bool isAnchorIdTarget;

  /// The anchor's clock was invalid when the window was evaluated.
  final bool clockInvalid;

  final bool beepListNonempty;
  final Recurrence recurrence;

  /// `flags1` bit 2 — the event's criterion is one this firmware implements.
  final bool supportedCriteria;

  /// This record's event is the one the running alarm belongs to.
  final bool activeAlarmEvent;

  /// §4.4 offset 23: padding, always 0.
  final int reserved;

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
    required this.isAnchorIdTarget,
    required this.clockInvalid,
    required this.beepListNonempty,
    required this.recurrence,
    required this.supportedCriteria,
    required this.activeAlarmEvent,
    required this.reserved,
  });

  Map<String, Object?> toRecordMap() {
    final m = <String, Object?>{
      'event_id': eventId,
      'start_min': startMin,
      'end_min': endMin,
      'criteria': criteria?.raw,
      'recurrence': recurrence.raw,
      'reserved': reserved,
    };
    final flags0 = _packBits([
      (0x01, negatedToday),
      (0x02, inBeepList),
      (0x04, isDockEvent),
      (0x08, hasAnchorProfile),
      (0x10, windowOpenNow),
      (0x20, isAnchorIdTarget),
      (0x40, clockInvalid),
      (0x80, beepListNonempty),
    ]);
    _putBits(m, 'flags0', flags0, const [
      (0x01, 'negated_today'),
      (0x02, 'in_beep_list'),
      (0x04, 'is_dock_event'),
      (0x08, 'has_anchor_profile'),
      (0x10, 'window_open_now'),
      (0x20, 'is_anchor_id_target'),
      (0x40, 'clock_invalid'),
      (0x80, 'beep_list_nonempty'),
    ]);
    final flags1 = _packBits([
      (0x04, supportedCriteria),
      (0x08, activeAlarmEvent),
    ]) | recurrence.raw;
    _putBits(m, 'flags1', flags1, const [
      (0x04, 'supported_criteria'),
      (0x08, 'active_alarm_event'),
    ]);
    return m;
  }
}

/// A decoded anchor `…0020` snapshot (§4.3 header + §4.4 records).
class AnchorDebugTelemetry {
  static const int wireVersion = 2;
  static const int headerSize = 160;
  static const int eventRecordSize = 24;
  static const int maxEventRecords = 8;
  static const int hintSize = 8;

  /// True when [bytes] is the §4.5 change hint rather than a snapshot.
  static bool isHint(List<int> bytes) =>
      bytes.length == hintSize && bytes[0] == wireVersion;

  /// True when [bytes] is a v2 value cut short of its own header plus declared
  /// records. Same contract as the watch-side helper.
  static bool looksTruncated(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] != wireVersion) return false;
    if (bytes.length == hintSize) return true;
    if (bytes.length < 4) return true;
    final headerLen = bytes[1];
    final recordCount = bytes[2];
    final recordLen = bytes[3];
    return bytes.length < headerLen + recordCount * recordLen;
  }

  final int version;
  final int headerLen;
  final int recordCount;
  final int recordLen;
  final int maxRecords;

  // flags0
  final bool timeValid;
  final bool scheduleLoaded;
  final bool beeping;
  final bool beepPhaseOn;
  final bool buzzerCompiledOut;
  final bool motorCompiledOut;
  final bool wifiConnected;
  final bool wifiFallbackArmed;

  // flags1
  final bool bleQuiesced;
  final bool bleAdvertising;
  final bool radioIsWifi;
  final bool servoOpen;
  final bool dockSupported;
  final bool clockRestored;
  final bool beepCapReached;
  final bool anchorInActiveEvent;

  // flags2
  final bool lastCmdRemoved;
  final bool lastCmdWorn;
  final bool lastCmdAccepted;
  final bool lastCmdNotMine;
  final bool lastCmdMalformed;
  final bool lastCmdOverBle;
  final bool lastCmdOverUdp;
  final bool noCommandYet;

  // flags3
  final bool identifyActiveFlag;
  final bool csReflectorBuilt;
  final bool csProceduresActive;
  final bool schedulePersisted;
  final bool rejectionWasClock;
  final bool profileDefaulted;
  final bool alarmWindowClosed;

  /// `flags4` bit 0: a §4.6.1 reply was sent for the last command. Always 0
  /// for a BLE carrier (the write is without response).
  final bool ackSent;

  /// Where the anchor's clock came from (R7 offset 154) — the #1 reason an
  /// anchor stays silent.
  final ClockSource? clockSource;

  final BeepProfile? beepProfile;
  final AnchorCmd lastCmd;
  final AnchorCmdResult? lastCmdResult;
  final AnchorCmdReason? lastCmdReason;
  final AnchorCmdTransport? lastCmdTransport;
  final RadioPhase radioPhase;
  final CsReflectorState? csReflectorState;

  final int bootCount;

  /// The device-level cap; 0 = no cap.
  final int maxBeepMinutes;
  final int? localMinute;
  final int? sinceLastCmdS;
  final int beepingForS;
  final int beepCapRemainingS;
  final int todayEventCount;
  final int scheduleEventCount;
  final int? activeEventIndex;
  final int? activeEventStartMin;
  final int? activeEventEndMin;

  final int rejectUnknownEvent;
  final int rejectOutsideWindow;
  final int rejectNegated;
  final int rejectNotInBeepList;
  final int rejectMalformed;
  final int acceptedApplied;
  final int capStops;
  final int beepCycles;
  final int wifiDwellRemainingS;

  /// Unix seconds, or null (0xFFFFFFFF) when the clock is unknown.
  final int? utcNow;
  final int tzOffsetMin;
  final int peerLinkCount;
  final DockState? dockState;
  final int uptimeMs;

  /// Dotted quad of the last known address, or null (0.0.0.0) when none.
  final String? ownLastIp;

  /// Uptime ms this alarm started, or null (0) when it never started.
  final int? beepStartedAtMs;
  final int radioPhaseSinceMs;

  /// CRC32 of the schedule blob; null (0) when none is held.
  final int? scheduleCrc;

  final String activeEventId;
  final String alarmEventId;
  final String lastCmdEventId;
  final String lastCmdWatchUuid;

  /// Dotted quad, or null (0.0.0.0) for a BLE carrier / no command.
  final String? lastCmdSrcIp;

  final int identifyActive;
  final ServoState? servoState;
  final DebugCriteria? activeEventCriteria;
  final BeepProfile? activeEventAnchorProfile;
  final int snapshotSeq;

  /// §4.3 offset 159: padding, always 0.
  final int reserved1;

  final List<AnchorEventRecord> events;

  const AnchorDebugTelemetry({
    required this.version,
    required this.headerLen,
    required this.recordCount,
    required this.recordLen,
    required this.maxRecords,
    required this.timeValid,
    required this.scheduleLoaded,
    required this.beeping,
    required this.beepPhaseOn,
    required this.buzzerCompiledOut,
    required this.motorCompiledOut,
    required this.wifiConnected,
    required this.wifiFallbackArmed,
    required this.bleQuiesced,
    required this.bleAdvertising,
    required this.radioIsWifi,
    required this.servoOpen,
    required this.dockSupported,
    required this.clockRestored,
    required this.beepCapReached,
    required this.anchorInActiveEvent,
    required this.lastCmdRemoved,
    required this.lastCmdWorn,
    required this.lastCmdAccepted,
    required this.lastCmdNotMine,
    required this.lastCmdMalformed,
    required this.lastCmdOverBle,
    required this.lastCmdOverUdp,
    required this.noCommandYet,
    required this.identifyActiveFlag,
    required this.csReflectorBuilt,
    required this.csProceduresActive,
    required this.schedulePersisted,
    required this.rejectionWasClock,
    required this.profileDefaulted,
    required this.alarmWindowClosed,
    required this.ackSent,
    required this.clockSource,
    required this.beepProfile,
    required this.lastCmd,
    required this.lastCmdResult,
    required this.lastCmdReason,
    required this.lastCmdTransport,
    required this.radioPhase,
    required this.csReflectorState,
    required this.bootCount,
    required this.maxBeepMinutes,
    required this.localMinute,
    required this.sinceLastCmdS,
    required this.beepingForS,
    required this.beepCapRemainingS,
    required this.todayEventCount,
    required this.scheduleEventCount,
    required this.activeEventIndex,
    required this.activeEventStartMin,
    required this.activeEventEndMin,
    required this.rejectUnknownEvent,
    required this.rejectOutsideWindow,
    required this.rejectNegated,
    required this.rejectNotInBeepList,
    required this.rejectMalformed,
    required this.acceptedApplied,
    required this.capStops,
    required this.beepCycles,
    required this.wifiDwellRemainingS,
    required this.utcNow,
    required this.tzOffsetMin,
    required this.peerLinkCount,
    required this.dockState,
    required this.uptimeMs,
    required this.ownLastIp,
    required this.beepStartedAtMs,
    required this.radioPhaseSinceMs,
    required this.scheduleCrc,
    required this.activeEventId,
    required this.alarmEventId,
    required this.lastCmdEventId,
    required this.lastCmdWatchUuid,
    required this.lastCmdSrcIp,
    required this.identifyActive,
    required this.servoState,
    required this.activeEventCriteria,
    required this.activeEventAnchorProfile,
    required this.snapshotSeq,
    required this.reserved1,
    required this.events,
  });

  /// True when the alarm has reached `max_beep_minutes` (and will stop, per
  /// §2.3). `beep_cap_reached` is the stored fact; the age comparison is the
  /// fallback for a snapshot that predates it.
  bool get beepCapExpired {
    if (!beeping) return false;
    if (beepCapReached) return true;
    if (maxBeepMinutes == 0) return false;
    return beepingForS >= maxBeepMinutes * 60;
  }

  /// Local wall time on the anchor's clock, or null when it is not valid.
  DateTime? get anchorLocalTime {
    final utc = utcNow;
    if (!timeValid || utc == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(utc * 1000, isUtc: true)
        .add(Duration(minutes: tzOffsetMin));
  }

  /// Clock provenance: where the anchor's time came from, per §2.1/R7.
  String get clockSourceLabel {
    if (!timeValid) {
      return clockSource == null
          ? 'invalid (never set)'
          : 'invalid (${clockSource!.label})';
    }
    if (clockSource != null) return clockSource!.label;
    return clockRestored ? 'restored (flash or retained RAM)' : 'set this boot';
  }

  /// The event record for [eventId], or null.
  AnchorEventRecord? eventRecord(String? eventId) {
    if (eventId == null || eventId.isEmpty) return null;
    for (final e in events) {
      if (e.eventId == eventId) return e;
    }
    return null;
  }

  /// The dock event record for [eventId], else the first dock event.
  AnchorEventRecord? dockEventRecord(String? eventId) {
    AnchorEventRecord? fallback;
    for (final e in events) {
      if (!e.isDockEvent) continue;
      if (eventId != null && eventId.isNotEmpty && e.eventId == eventId) {
        return e;
      }
      fallback ??= e;
    }
    return fallback;
  }

  String get beepProfileLabel => beepProfile?.label ?? 'none';

  /// Every decoded header field by its §4.3 name, for the vector test and the
  /// log. Flags are emitted raw and per bit.
  Map<String, Object?> fieldsMap() {
    final m = <String, Object?>{
      'version': version,
      'header_len': headerLen,
      'record_count': recordCount,
      'record_len': recordLen,
      'max_records': maxRecords,
      'beep_profile': beepProfile?.raw,
      'last_cmd': lastCmd.raw,
      'last_cmd_result': lastCmdResult?.raw,
      'last_cmd_reason': lastCmdReason?.raw,
      'last_cmd_transport': lastCmdTransport?.raw,
      'radio_phase': radioPhase.raw,
      'cs_reflector_state': csReflectorState?.raw,
      'boot_count': bootCount,
      'max_beep_minutes': maxBeepMinutes,
      'local_minute': localMinute,
      'since_last_cmd_s': sinceLastCmdS,
      'beeping_for_s': beepingForS,
      'beep_cap_remaining_s': beepCapRemainingS,
      'today_event_count': todayEventCount,
      'schedule_event_count': scheduleEventCount,
      'active_event_index': activeEventIndex,
      'active_event_start_min': activeEventStartMin,
      'active_event_end_min': activeEventEndMin,
      'reject_unknown_event': rejectUnknownEvent,
      'reject_outside_window': rejectOutsideWindow,
      'reject_negated': rejectNegated,
      'reject_not_in_beep_list': rejectNotInBeepList,
      'reject_malformed': rejectMalformed,
      'accepted_applied': acceptedApplied,
      'cap_stops': capStops,
      'beep_cycles': beepCycles,
      'wifi_dwell_remaining_s': wifiDwellRemainingS,
      'utc_now': utcNow,
      'tz_offset_min': tzOffsetMin,
      'peer_link_count': peerLinkCount,
      'dock_state': dockState?.raw,
      'uptime_ms': uptimeMs,
      'own_last_ip': ownLastIp,
      'beep_started_at_ms': beepStartedAtMs,
      'radio_phase_since_ms': radioPhaseSinceMs,
      'schedule_crc': scheduleCrc,
      'active_event_id': activeEventId.isEmpty ? null : activeEventId,
      'alarm_event_id': alarmEventId.isEmpty ? null : alarmEventId,
      'last_cmd_event_id': lastCmdEventId.isEmpty ? null : lastCmdEventId,
      'last_cmd_watch_uuid': lastCmdWatchUuid.isEmpty ? null : lastCmdWatchUuid,
      'last_cmd_src_ip': lastCmdSrcIp,
      'identify_active': identifyActive != 0,
      'clock_source': clockSource?.raw,
      'ack_sent': ackSent,
      'servo_state': servoState?.raw,
      'active_event_criteria': activeEventCriteria?.raw,
      'active_event_anchor_profile': activeEventAnchorProfile?.raw,
      'snapshot_seq': snapshotSeq,
      'reserved1': reserved1,
    };
    _putBits(m, 'flags0', _packBits([
      (0x01, timeValid),
      (0x02, scheduleLoaded),
      (0x04, beeping),
      (0x08, beepPhaseOn),
      (0x10, buzzerCompiledOut),
      (0x20, motorCompiledOut),
      (0x40, wifiConnected),
      (0x80, wifiFallbackArmed),
    ]), const [
      (0x01, 'time_valid'),
      (0x02, 'schedule_loaded'),
      (0x04, 'beeping'),
      (0x08, 'beep_phase_on'),
      (0x10, 'buzzer_compiled_out'),
      (0x20, 'motor_compiled_out'),
      (0x40, 'wifi_connected'),
      (0x80, 'wifi_fallback_armed'),
    ]);
    _putBits(m, 'flags1', _packBits([
      (0x01, bleQuiesced),
      (0x02, bleAdvertising),
      (0x04, radioIsWifi),
      (0x08, servoOpen),
      (0x10, dockSupported),
      (0x20, clockRestored),
      (0x40, beepCapReached),
      (0x80, anchorInActiveEvent),
    ]), const [
      (0x01, 'ble_quiesced'),
      (0x02, 'ble_advertising'),
      (0x04, 'radio_is_wifi'),
      (0x08, 'servo_open'),
      (0x10, 'dock_supported'),
      (0x20, 'clock_restored'),
      (0x40, 'beep_cap_reached'),
      (0x80, 'anchor_in_active_event'),
    ]);
    _putBits(m, 'flags2', _packBits([
      (0x01, lastCmdRemoved),
      (0x02, lastCmdWorn),
      (0x04, lastCmdAccepted),
      (0x08, lastCmdNotMine),
      (0x10, lastCmdMalformed),
      (0x20, lastCmdOverBle),
      (0x40, lastCmdOverUdp),
      (0x80, noCommandYet),
    ]), const [
      (0x01, 'last_cmd_removed'),
      (0x02, 'last_cmd_worn'),
      (0x04, 'last_cmd_accepted'),
      (0x08, 'last_cmd_not_mine'),
      (0x10, 'last_cmd_malformed'),
      (0x20, 'last_cmd_over_ble'),
      (0x40, 'last_cmd_over_udp'),
      (0x80, 'no_command_yet'),
    ]);
    _putBits(m, 'flags3', _packBits([
      (0x01, identifyActiveFlag),
      (0x02, csReflectorBuilt),
      (0x04, csProceduresActive),
      (0x08, schedulePersisted),
      (0x10, rejectionWasClock),
      (0x20, profileDefaulted),
      (0x40, alarmWindowClosed),
    ]), const [
      (0x01, 'identify_active_flag'),
      (0x02, 'cs_reflector_built'),
      (0x04, 'cs_procedures_active'),
      (0x08, 'schedule_persisted'),
      (0x10, 'rejection_was_clock'),
      (0x20, 'profile_defaulted'),
      (0x40, 'alarm_window_closed'),
    ]);
    _putBits(m, 'flags4', _packBits([
      (0x01, ackSent),
    ]), const [
      (0x01, 'ack_sent'),
    ]);
    m['time_valid'] = timeValid;
    m['schedule_loaded'] = scheduleLoaded;
    m['beeping'] = beeping;
    m['dock_supported'] = dockSupported;
    return m;
  }

  /// Decode an `…0020` snapshot. Same rules as the watch decoder.
  static AnchorDebugTelemetry decode(List<int> bytes) {
    if (bytes.length < 4) {
      throw FormatException(
          'anchor debug telemetry: ${bytes.length} bytes is shorter than the '
          '4-byte versioned header');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final version = data.getUint8(0);
    if (version != wireVersion) {
      throw FormatException('unsupported telemetry version $version');
    }
    final headerLen = data.getUint8(1);
    final recordCount = data.getUint8(2);
    final recordLen = data.getUint8(3);
    if (headerLen < headerSize) {
      throw FormatException(
          'anchor debug telemetry: header_len $headerLen < $headerSize');
    }
    if (bytes.length < headerLen) {
      throw FormatException(
          'anchor debug telemetry: ${bytes.length} bytes < header_len '
          '$headerLen');
    }
    if (recordCount > maxEventRecords) {
      throw FormatException(
          'anchor debug telemetry: $recordCount records > $maxEventRecords');
    }
    if (recordLen < eventRecordSize) {
      throw FormatException(
          'anchor debug telemetry: record_len $recordLen < $eventRecordSize');
    }
    final need = headerLen + recordCount * recordLen;
    if (bytes.length < need) {
      throw FormatException(
          'anchor debug telemetry: ${bytes.length} bytes < $need '
          '($recordCount records of $recordLen)');
    }

    final flags0 = data.getUint8(5);
    final flags1 = data.getUint8(6);
    final flags2 = data.getUint8(7);
    final flags3 = data.getUint8(8);

    final events = <AnchorEventRecord>[];
    for (int i = 0; i < recordCount; i++) {
      final o = headerLen + i * recordLen;
      final f0 = data.getUint8(o + 21);
      final f1 = data.getUint8(o + 22);
      events.add(AnchorEventRecord(
        eventId: _uuidAt(data, o),
        startMin: data.getUint16(o + 16, Endian.little),
        endMin: data.getUint16(o + 18, Endian.little),
        criteria: DebugCriteria.fromWire(data.getUint8(o + 20)),
        negatedToday: (f0 & 0x01) != 0,
        inBeepList: (f0 & 0x02) != 0,
        isDockEvent: (f0 & 0x04) != 0,
        hasAnchorProfile: (f0 & 0x08) != 0,
        windowOpenNow: (f0 & 0x10) != 0,
        isAnchorIdTarget: (f0 & 0x20) != 0,
        clockInvalid: (f0 & 0x40) != 0,
        beepListNonempty: (f0 & 0x80) != 0,
        recurrence: Recurrence.fromWire(f1 & 0x03),
        supportedCriteria: (f1 & 0x04) != 0,
        activeAlarmEvent: (f1 & 0x08) != 0,
        reserved: data.getUint8(o + 23),
      ));
    }

    return AnchorDebugTelemetry(
      version: version,
      headerLen: headerLen,
      recordCount: recordCount,
      recordLen: recordLen,
      maxRecords: data.getUint8(4),
      timeValid: (flags0 & 0x01) != 0,
      scheduleLoaded: (flags0 & 0x02) != 0,
      beeping: (flags0 & 0x04) != 0,
      beepPhaseOn: (flags0 & 0x08) != 0,
      buzzerCompiledOut: (flags0 & 0x10) != 0,
      motorCompiledOut: (flags0 & 0x20) != 0,
      wifiConnected: (flags0 & 0x40) != 0,
      wifiFallbackArmed: (flags0 & 0x80) != 0,
      bleQuiesced: (flags1 & 0x01) != 0,
      bleAdvertising: (flags1 & 0x02) != 0,
      radioIsWifi: (flags1 & 0x04) != 0,
      servoOpen: (flags1 & 0x08) != 0,
      dockSupported: (flags1 & 0x10) != 0,
      clockRestored: (flags1 & 0x20) != 0,
      beepCapReached: (flags1 & 0x40) != 0,
      anchorInActiveEvent: (flags1 & 0x80) != 0,
      lastCmdRemoved: (flags2 & 0x01) != 0,
      lastCmdWorn: (flags2 & 0x02) != 0,
      lastCmdAccepted: (flags2 & 0x04) != 0,
      lastCmdNotMine: (flags2 & 0x08) != 0,
      lastCmdMalformed: (flags2 & 0x10) != 0,
      lastCmdOverBle: (flags2 & 0x20) != 0,
      lastCmdOverUdp: (flags2 & 0x40) != 0,
      noCommandYet: (flags2 & 0x80) != 0,
      identifyActiveFlag: (flags3 & 0x01) != 0,
      ackSent: (data.getUint8(155) & 0x01) != 0,
      clockSource: ClockSource.fromWire(data.getUint8(154)),
      csReflectorBuilt: (flags3 & 0x02) != 0,
      csProceduresActive: (flags3 & 0x04) != 0,
      schedulePersisted: (flags3 & 0x08) != 0,
      rejectionWasClock: (flags3 & 0x10) != 0,
      profileDefaulted: (flags3 & 0x20) != 0,
      alarmWindowClosed: (flags3 & 0x40) != 0,
      beepProfile: BeepProfile.fromWire(data.getUint8(9)),
      lastCmd: AnchorCmd.fromWire(data.getUint8(10)),
      lastCmdResult: AnchorCmdResult.fromWire(data.getUint8(11)),
      lastCmdReason: AnchorCmdReason.fromWire(data.getUint8(12)),
      lastCmdTransport: AnchorCmdTransport.fromWire(data.getUint8(13)),
      radioPhase: RadioPhase.fromWire(data.getUint8(14)),
      csReflectorState: CsReflectorState.fromWire(data.getUint8(15)),
      bootCount: data.getUint16(16, Endian.little),
      maxBeepMinutes: data.getUint16(18, Endian.little),
      localMinute: _u16OrNull(data, 20),
      sinceLastCmdS: _u16OrNull(data, 22),
      beepingForS: data.getUint16(24, Endian.little),
      beepCapRemainingS: data.getUint16(26, Endian.little),
      todayEventCount: data.getUint16(28, Endian.little),
      scheduleEventCount: data.getUint16(30, Endian.little),
      activeEventIndex: _u16OrNull(data, 32),
      activeEventStartMin: _u16OrNull(data, 34),
      activeEventEndMin: _u16OrNull(data, 36),
      rejectUnknownEvent: data.getUint16(38, Endian.little),
      rejectOutsideWindow: data.getUint16(40, Endian.little),
      rejectNegated: data.getUint16(42, Endian.little),
      rejectNotInBeepList: data.getUint16(44, Endian.little),
      rejectMalformed: data.getUint16(46, Endian.little),
      acceptedApplied: data.getUint16(48, Endian.little),
      capStops: data.getUint16(50, Endian.little),
      beepCycles: data.getUint16(52, Endian.little),
      wifiDwellRemainingS: data.getUint16(54, Endian.little),
      utcNow: _u32OrNull(data, 56),
      tzOffsetMin: data.getInt16(60, Endian.little),
      peerLinkCount: data.getUint8(62),
      dockState: DockState.fromWire(data.getUint8(63)),
      uptimeMs: data.getUint32(64, Endian.little),
      ownLastIp: _ipv4OrNull(data, 68),
      // 0 = never (A28), not 0xFFFFFFFF.
      beepStartedAtMs: _zeroOrNull(data.getUint32(72, Endian.little)),
      radioPhaseSinceMs: data.getUint32(76, Endian.little),
      // 0 = no schedule (A12), not 0xFFFFFFFF.
      scheduleCrc: _zeroOrNull(data.getUint32(80, Endian.little)),
      activeEventId: _uuidOrEmpty(data, 84),
      alarmEventId: _uuidOrEmpty(data, 100),
      lastCmdEventId: _uuidOrEmpty(data, 116),
      lastCmdWatchUuid: _uuidOrEmpty(data, 132),
      lastCmdSrcIp: _ipv4OrNull(data, 148),
      identifyActive: data.getUint8(152),
      servoState: ServoState.fromWire(data.getUint8(153)),
      activeEventCriteria: DebugCriteria.fromWire(data.getUint8(156)),
      activeEventAnchorProfile: BeepProfile.fromWire(data.getUint8(157)),
      snapshotSeq: data.getUint8(158),
      reserved1: data.getUint8(159),
      events: List.unmodifiable(events),
    );
  }
}

// ── Wire helpers ────────────────────────────────────────────────────────────

/// Record a flag byte under [prefix] plus one boolean per named bit. A vector
/// file may describe flags either way, so both are exposed.
void _putBits(Map<String, Object?> m, String prefix, int byte,
    List<(int, String)> bits) {
  for (final (bit, name) in bits) {
    m[name] = (byte & bit) != 0;
  }
  m[prefix] = byte;
}

/// Pack named bits into their byte, so a record can rebuild its flags from the
/// decoded booleans it stores.
int _packBits(List<(int, bool)> bits) {
  int byte = 0;
  for (final (bit, on) in bits) {
    if (on) byte |= bit;
  }
  return byte;
}

int? _u8OrNull(int v) => v == 0xFF ? null : v;

/// A configuration value where 0 means "not applicable" (R7: `still_threshold_s`
/// and `motion_threshold_mms2` are 0 on an IR build).
int? _zeroOrNull(int v) => v == 0 ? null : v;

int? _u16OrNull(ByteData d, int offset) {
  final v = d.getUint16(offset, Endian.little);
  return v == 0xFFFF ? null : v;
}

int? _i16OrNull(ByteData d, int offset, int sentinel) {
  final v = d.getInt16(offset, Endian.little);
  return v == sentinel ? null : v;
}

int? _u32OrNull(ByteData d, int offset) {
  final v = d.getUint32(offset, Endian.little);
  return v == 0xFFFFFFFF ? null : v;
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

/// Six bytes in printed order → `AA:BB:CC:DD:EE:FF`; all-FF means unknown.
String? _addrOrNull(ByteData data, int offset) {
  final parts = <String>[];
  var allFf = true;
  for (int i = 0; i < 6; i++) {
    final b = data.getUint8(offset + i);
    if (b != 0xFF) allFf = false;
    parts.add(b.toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return allFf ? null : parts.join(':');
}

/// Four octets in network order → dotted quad; 0.0.0.0 means none.
String? _ipv4OrNull(ByteData data, int offset) {
  final a = data.getUint8(offset);
  final b = data.getUint8(offset + 1);
  final c = data.getUint8(offset + 2);
  final d = data.getUint8(offset + 3);
  if (a == 0 && b == 0 && c == 0 && d == 0) return null;
  return '$a.$b.$c.$d';
}
