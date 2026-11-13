// Watch-side BLE transport and wire decoders.
//
// One process-wide singleton ([WatchService]) holding at most ONE watch
// connection. It owns the GATT session and every watch characteristic binding;
// it does NOT own app state — it publishes broadcast streams that AppState
// subscribes to (`statusStream`, `seenAnchorsStream`, `calibrationStream`) and
// returns raw verdicts from its writes.
//
// Threading/context: plain Dart on the UI isolate. `flutter_blue_plus` delivers
// notifications on the platform-channel event loop, so every listener here runs
// on the main isolate and may call `notifyListeners()` indirectly — there is no
// background isolate and no ISR-style concern. Writes/reads are async and each
// response-wait is bounded by a 5–10 s timeout so a silent device cannot wedge a
// caller forever.
//
// Characteristic map (UUIDs live in ../utils/ble_constants.dart; wire layouts in
// MOBILE_APP_SPEC.md §6.1). Every one of these is bound in
// `_bindCharacteristics` and, where it has one, decoded by the function named:
//
//   …0011 WiFi Credentials  write no-resp   JSON {ssid,password}  pushWifiCredentials
//   …0012 Schedule Ctrl     write+notify    BEGIN/END frames       pushSchedule, _writeCtrlAwaitByte
//   …0013 Schedule Data     write no-resp   blob chunks           pushSchedule
//   …0014 Settings          write (notify)  6-byte payload        pushSettings
//   …0015 Seen Anchors      read+notify     count + entries       _parseSeenAnchors -> seenAnchorsStream
//   …0016 Watch Status      read+notify     v0.8 layout           WatchStatus.fromBytes -> statusStream
//   …0017 Anchor IP Table   write (notify)  count + entries       pushAnchorIpTable
//   …0018 LED Config        (unused)        format TBD            —
//   …0019 Time              write (notify)  10-byte payload       pushTime        (probed)
//   …001A Pending Changes   read+notify     count + entries       _parsePendingChanges (probed)
//   …001B Emergency Pass    write+read      3 opcodes             spend/allowance/ledger (probed)
//   …001C Calibration Ctrl  write+notify    START/FINALIZE/ABORT  startCalibration etc. (probed)
//   …001D Debug Telemetry   read+notify     v2 snapshot §4.1       readDebugTelemetry -> debugTelemetryStream (probed)
//
// "Probed" means the characteristic may be absent on a given firmware build:
// callers must check the `has*Characteristic` getters first. Layout changes are
// exact-byte lockstep with the firmware — the status parsers deliberately do not
// version-detect (spec §10 item 8).
//
// Where the table says "(notify)" for a characteristic the spec declares as
// Write-with-Response (Settings, Anchor IP Table, Time), the code waits for a
// notification and treats a 5 s silence as failure. That is the shape of the
// current firmware, not the spec; see CODEMAP.md §10 item 5 before changing it.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../models/debug_telemetry.dart';
import '../utils/ble_constants.dart';
import '../utils/schedule_encoder.dart';
import 'debug_log_service.dart';

// ── Calibration progress model (§4.10.7) ─────────────────────────────────────
// Calibration-v2 (CALIBRATION_V2_DESIGN.md §1, §3): the user demonstrates the
// near-zone in an INSIDE burst and an EDGE burst; the anchor then computes a
// per-anchor threshold. The types below are the app's read-only view of that
// process — the phone never writes a threshold. Everything here is decoded from
// the watch's `…001C` progress frame.

/// State of an app-guided calibration burst, reported by the watch on
/// `WATCH_CALIB_CTRL_CHAR_UUID` (firmware §4.10.7 / §5.6).
enum CalibrationState { idle, running, done, aborted, finalized }

/// Calibration-v2 phase the app drives the anchor through (decision 1). INSIDE
/// = roam the near-zone you want counted; EDGE = step just past your tolerance.
enum CalibrationPhase { none, inside, edge }

/// Why a calibration failed to produce a per-anchor threshold. The firmware
/// returns confidence 0 for two very different reasons and the app must not
/// conflate them: telling a user their walk was ambiguous when they in fact
/// demonstrated it perfectly and merely stood still too briefly sends them off
/// to fix the wrong thing.
enum CalibrationFailure {
  /// The demonstration worked; there simply were not enough samples in one leg.
  tooFewSamples,

  /// Enough samples, but the INSIDE and EDGE score distributions overlapped.
  overlap,
}

/// Result of the FINALIZE step: the per-anchor near-zone threshold the anchor
/// computed + persisted, with the demonstrated sample counts and a confidence
/// (0 = low — see [failure] for which of the two causes applies).
class CalibrationResult {
  /// Mirrors PROX_CALIB_MIN_SAMPLES in proximity.h. Below this in either leg the
  /// firmware never reaches the distribution comparison at all — it returns the
  /// global default threshold with confidence 0.
  static const int minSamplesPerLeg = 5;

  final int nearThreshold; // 0..255 score-space cutoff (0 = fell back to global)
  final int insideN;
  final int edgeN;
  final int confidence;    // 0 = low/overlap … 255 = clean separation
  const CalibrationResult({
    required this.nearThreshold,
    required this.insideN,
    required this.edgeN,
    required this.confidence,
  });

  /// True when the demonstration cleanly separated inside from edge.
  bool get isConfident => confidence > 0;

  /// Which leg (if any) came up short of [minSamplesPerLeg].
  bool get insideStarved => insideN < minSamplesPerLeg;
  bool get edgeStarved => edgeN < minSamplesPerLeg;

  /// Null when the calibration succeeded. Sample starvation is checked first
  /// because it short-circuits the firmware's comparison — if a leg is short,
  /// nothing is known about whether the distributions would have separated.
  CalibrationFailure? get failure {
    if (isConfident) return null;
    if (insideStarved || edgeStarved) return CalibrationFailure.tooFewSamples;
    return CalibrationFailure.overlap;
  }
}

/// One progress frame from the watch during a calibration burst. The burst runs
/// on the watch (it authors real-MAC scan vectors the anchor can actually train
/// on — see firmware §4.10.7 for why the phone cannot); this is read-only
/// telemetry the app renders.
class CalibrationProgress {
  /// Session state.
  final CalibrationState state;

  /// Samples the anchor folded into its fingerprint this session — real
  /// learning progress. Drive the UI from this, not elapsed time.
  final int accepted;

  /// Total queries the watch has attempted this session. If this climbs while
  /// [accepted] stays at 0, the watch is querying but not near/unambiguous
  /// enough for the anchor to accept training (e.g. anchor out of range).
  final int queries;

  /// Most recent proximity score (0 = away … 255 = here).
  final int lastScore;

  /// Whether the anchor's fingerprint is contributing to the score (flags bit0).
  final bool fingerprintActive;

  /// Seconds remaining in the session.
  final int remainingS;

  /// FINALIZE result (calibration-v2), present once [state] is
  /// [CalibrationState.finalized] (and the watch reported `have_result`). Null
  /// during INSIDE/EDGE bursts or on a pre-v2 (9-byte) frame.
  final CalibrationResult? result;

  const CalibrationProgress({
    required this.state,
    required this.accepted,
    required this.queries,
    required this.lastScore,
    required this.fingerprintActive,
    required this.remainingS,
    this.result,
  });

  /// Parse the watch progress payload. The calibration-v2 frame is 16 bytes with
  /// a trailing result block; the legacy frame is 9 bytes (no result). Returns
  /// null if malformed.
  static CalibrationProgress? fromBytes(List<int> b) {
    if (b.length < 9) return null;
    CalibrationState st;
    switch (b[0]) {
      case 1:  st = CalibrationState.running;   break;
      case 2:  st = CalibrationState.done;      break;
      case 3:  st = CalibrationState.aborted;   break;
      case 4:  st = CalibrationState.finalized; break;
      default: st = CalibrationState.idle;
    }
    CalibrationResult? res;
    if (b.length >= 16 && b[15] != 0) {
      res = CalibrationResult(
        nearThreshold: b[9],
        insideN: b[10] | (b[11] << 8),
        edgeN: b[12] | (b[13] << 8),
        confidence: b[14],
      );
    }
    return CalibrationProgress(
      state: st,
      accepted: b[1] | (b[2] << 8),
      queries: b[3] | (b[4] << 8),
      lastScore: b[5],
      fingerprintActive: (b[6] & 0x01) != 0,
      remainingS: b[7] | (b[8] << 8),
      result: res,
    );
  }
}

// ── WatchStatus model ────────────────────────────────────────────────────────
// The v0.8 layout, fixed offsets, all little-endian:
//   [0..4]  activity, bt, wifi, worn, battery_pct
//   [5..21] active_event_id (16 bytes, all-zero ⇒ none)
//   [21]    condition_met
//   [22..26] schedule_crc u32
//   [26]    unreachable_count, then per entry [uuid 16][name_len][name][ts u32]
// Consumers: AppState._status -> Home dashboard (§8.7), Devices card, Debug
// screen, and the schedule-CRC confirmation path (§8.16).

/// A queued "couldn't reach this beep-anchor" notification (§8.7).
class UnreachableAnchor {
  final String uuid;
  final String name;
  final DateTime timestamp;
  const UnreachableAnchor({
    required this.uuid,
    required this.name,
    required this.timestamp,
  });
}

/// Decoded Watch Status characteristic (`…0016`, firmware §5.6 / spec §6.1).
class WatchStatus {
  /// 0 = dormant, 1 = enforcement, 2 = dormant_sleep
  final int activityState;
  final bool btConnected;
  final bool wifiConnected;
  final bool worn;
  /// 0xFF = not available
  final int batteryPct;
  /// UUID string of the currently active event, or null.
  final String? activeEventId;

  /// `condition_met` byte (firmware v0.6, lockstep): false ⇒ the watch is
  /// actively alarming; true ⇒ in-window and compliant (or no active window).
  /// Null when the firmware predates the byte (short payload).
  final bool? conditionMet;

  /// `schedule_crc` (firmware v0.8, lockstep): CRC32 of the schedule blob the
  /// watch currently holds, or null on a truncated/pre-v0.8 payload. The app
  /// cross-checks this against `ScheduleEncoder`'s CRC to *confirm* sync rather
  /// than infer it (§8.16). 0 ⇒ the watch holds no schedule.
  final int? scheduleCrc;

  /// Queued unreachable beep-anchor notifications (§8.7).
  final List<UnreachableAnchor> unreachableAnchors;

  const WatchStatus({
    required this.activityState,
    required this.btConnected,
    required this.wifiConnected,
    required this.worn,
    required this.batteryPct,
    this.activeEventId,
    this.conditionMet,
    this.scheduleCrc,
    this.unreachableAnchors = const [],
  });

  String get activityLabel {
    switch (activityState) {
      case 0: return 'Dormant';
      case 1: return 'Enforcement';
      case 2: return 'Sleep';
      default: return 'Unknown';
    }
  }

  /// True when there is an active event and the watch is actively alarming.
  /// `condition_met == null` (short/pre-v0.6 payload) is never treated as
  /// alarming — absence of evidence must not read as a violation.
  bool get isAlarming => activeEventId != null && conditionMet == false;

  /// Decode a `…0016` payload. Offsets are absolute and unversioned; a payload
  /// shorter than 21 bytes (or a pre-v0.8 build) yields a neutral status with
  /// `batteryPct == 0xFF` and null optional fields rather than throwing, because
  /// this is called straight from a notify listener.
  ///
  /// `unreachable` entries are bounds-checked one field at a time and the loop
  /// breaks on a truncated entry, so a partial packet degrades to "fewer
  /// notifications" instead of an exception. Timestamps are seconds-since-epoch
  /// as u32 (good until 2106).

  static WatchStatus fromBytes(List<int> bytes) {
    // Layout (v0.8): activity u8, bt u8, wifi u8, worn u8, battery u8,
    //   active_event_id 16, condition_met u8, schedule_crc u32,
    //   unreachable_count u8, [entries...]. Every device is flashed in the v0.8
    //   lockstep batch, so the app assumes this layout and never version-detects
    //   by length (§10 item 8 — the variable-length tail makes that ambiguous).
    if (bytes.length < 21) {
      return const WatchStatus(
        activityState: 0,
        btConnected: false,
        wifiConnected: false,
        worn: false,
        batteryPct: 0xFF,
      );
    }
    final actState = bytes[0];
    final btConn   = bytes[1] != 0;
    final wifiConn = bytes[2] != 0;
    final worn     = bytes[3] != 0;
    final batt     = bytes[4];

    final eventBytes = bytes.sublist(5, 21);
    final allZero    = eventBytes.every((b) => b == 0);
    final eventId    = allZero ? null : _bytesToUuidStr(eventBytes);

    int pos = 21;
    bool? conditionMet;
    if (pos < bytes.length) {
      conditionMet = bytes[pos] != 0;
      pos += 1;
    }

    // schedule_crc u32 LE (v0.8). Present in the lockstep layout right after
    // condition_met and before the unreachable section.
    int? scheduleCrc;
    if (pos + 4 <= bytes.length) {
      scheduleCrc = ByteData.sublistView(
              Uint8List.fromList(bytes.sublist(pos, pos + 4)))
          .getUint32(0, Endian.little);
      pos += 4;
    }

    final unreachable = <UnreachableAnchor>[];
    if (pos < bytes.length) {
      final count = bytes[pos];
      pos += 1;
      for (int i = 0; i < count; i++) {
        if (pos + 16 > bytes.length) break;
        final uuid = _bytesToUuidStr(bytes.sublist(pos, pos + 16));
        pos += 16;
        if (pos >= bytes.length) break;
        final nameLen = bytes[pos];
        pos += 1;
        if (pos + nameLen > bytes.length) break;
        final name = utf8.decode(bytes.sublist(pos, pos + nameLen),
            allowMalformed: true);
        pos += nameLen;
        if (pos + 4 > bytes.length) break;
        final ts = ByteData.sublistView(
                Uint8List.fromList(bytes.sublist(pos, pos + 4)))
            .getUint32(0, Endian.little);
        pos += 4;
        unreachable.add(UnreachableAnchor(
          uuid: uuid,
          name: name,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        ));
      }
    }

    return WatchStatus(
      activityState: actState,
      btConnected: btConn,
      wifiConnected: wifiConn,
      worn: worn,
      batteryPct: batt,
      activeEventId: eventId,
      conditionMet: conditionMet,
      scheduleCrc: scheduleCrc,
      unreachableAnchors: unreachable,
    );
  }

  static String _bytesToUuidStr(List<int> b) {
    String h(int start, int end) => b
        .sublist(start, end)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${h(0,4)}-${h(4,6)}-${h(6,8)}-${h(8,10)}-${h(10,16)}';
  }
}

/// Watch verdict on a schedule END (firmware §6.2/§9.3, spec §7.1).
/// `partialQuarantine`/`rejected` must never be shown as a full apply.
enum ScheduleEndResult { accepted, partialQuarantine, rejected, failed }

extension ScheduleEndResultX on ScheduleEndResult {
  bool get fullyApplied => this == ScheduleEndResult.accepted;
  String get userMessage {
    switch (this) {
      case ScheduleEndResult.accepted:
        return 'Schedule saved to your watch';
      case ScheduleEndResult.partialQuarantine:
        return 'Saved — but the easing you made will take effect later';
      case ScheduleEndResult.rejected:
        return 'That change can\'t ease a commitment that\'s running right now';
      case ScheduleEndResult.failed:
        return 'Couldn\'t reach the watch — try again';
    }
  }
}

/// The on-watch emergency-pass ledger snapshot (`…001B` Read, firmware §9.6):
/// allowance, passes remaining, and a regen countdown per in-window spend.
class WatchPassLedger {
  final int allowance;
  final int remaining;
  final List<Duration> regenCountdowns;
  const WatchPassLedger({
    required this.allowance,
    required this.remaining,
    required this.regenCountdowns,
  });

  /// The soonest regeneration, or null when nothing is spent.
  Duration? get nextRegen => regenCountdowns.isEmpty
      ? null
      : regenCountdowns.reduce((a, b) => a < b ? a : b);
}

/// One entry from the watch's authoritative Pending Changes queue (`…001A`,
/// firmware §9.5). `secondsUntilApply` is the watch's own countdown.
class PendingChangeEntry {
  final String eventUuid;
  final int changeType;
  final int secondsUntilApply;
  const PendingChangeEntry({
    required this.eventUuid,
    required this.changeType,
    required this.secondsUntilApply,
  });
}

// ── SeenAnchorInfo ───────────────────────────────────────────────────────────
// Decoded `…0015`: anchors the WATCH can currently see, with the RSSI the watch
// measured. Used for §8.12 reachability ("the watch can/cannot see this anchor")
// and in main.dart to learn anchors the phone itself has not scanned — which is
// the only way an anchor discovered through the watch enters the device list.

class SeenAnchorInfo {
  final String uuid;
  final int rssi;
  final DateTime lastSeen;

  const SeenAnchorInfo({
    required this.uuid,
    required this.rssi,
    required this.lastSeen,
  });
}

// ── WatchService ─────────────────────────────────────────────────────────────

/// Manages the BLE GATT connection to the watch.
class WatchService {
  static final WatchService _instance = WatchService._internal();
  factory WatchService() => _instance;
  WatchService._internal();

  fbp.BluetoothDevice? _device;
  // ignore: unused_field
  fbp.BluetoothService? _gattService;

  fbp.BluetoothCharacteristic? _wifiCredChar;
  fbp.BluetoothCharacteristic? _schedCtrlChar;
  fbp.BluetoothCharacteristic? _schedDataChar;
  fbp.BluetoothCharacteristic? _settingsChar;
  fbp.BluetoothCharacteristic? _seenAnchorsChar;
  fbp.BluetoothCharacteristic? _statusChar;
  fbp.BluetoothCharacteristic? _anchorIpChar;
  fbp.BluetoothCharacteristic? _timeChar;
  fbp.BluetoothCharacteristic? _pendingChar;
  fbp.BluetoothCharacteristic? _emergencyPassChar;
  fbp.BluetoothCharacteristic? _calibChar;
  fbp.BluetoothCharacteristic? _debugChar;

  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<List<int>>? _seenAnchorsSub;
  StreamSubscription<List<int>>? _calibSub;
  StreamSubscription<List<int>>? _debugSub;
  bool _debugReadInFlight = false;

  final _statusController       = StreamController<WatchStatus>.broadcast();
  final _seenAnchorsController  = StreamController<List<SeenAnchorInfo>>.broadcast();
  final _calibController        = StreamController<CalibrationProgress>.broadcast();
  final _debugController        = StreamController<WatchDebugTelemetry>.broadcast();

  Stream<WatchStatus>          get statusStream       => _statusController.stream;
  Stream<List<SeenAnchorInfo>> get seenAnchorsStream  => _seenAnchorsController.stream;

  /// Progress frames from an app-guided calibration burst (§4.10.7).
  Stream<CalibrationProgress>  get calibrationStream  => _calibController.stream;

  /// Decoded Debug Telemetry snapshots (`…001D`, contract §4.1). The notify is
  /// only an 8-byte change hint — the payload exceeds the MTU, so every hint
  /// triggers one guarded full read (see [_subscribeNotifications]).
  Stream<WatchDebugTelemetry>  get debugTelemetryStream => _debugController.stream;

  bool get isConnected => _device != null &&
      (_device!.isConnected);

  fbp.BluetoothDevice? get device => _device;

  // ── Connect / disconnect ─────────────────────────────────────────────────
  // One watch at a time: connecting while a device is held tears the old link
  // down first. `connect` discovers services and subscribes to status / seen
  // anchors / calibration before returning, so callers may immediately read
  // characteristic-bound getters. Any failure propagates as an exception — the
  // UI layers wrap this and show an honest message.

  Future<void> connect(fbp.BluetoothDevice device) async {
    if (_device != null) await disconnect();

    await device.connect(timeout: const Duration(seconds: 10));
    _device = device;

    final services = await device.discoverServices();
    _bindCharacteristics(services);
    await _subscribeNotifications();
  }

  Future<void> disconnect() async {
    await _statusSub?.cancel();
    await _seenAnchorsSub?.cancel();
    await _calibSub?.cancel();
    await _debugSub?.cancel();
    _statusSub = null;
    _seenAnchorsSub = null;
    _calibSub = null;
    _debugSub = null;
    await _device?.disconnect();
    _device = null;
    _gattService = null;
    _clearChars();
  }

  void _clearChars() {
    _wifiCredChar    = null;
    _schedCtrlChar   = null;
    _schedDataChar   = null;
    _settingsChar    = null;
    _seenAnchorsChar = null;
    _statusChar      = null;
    _anchorIpChar    = null;
    _timeChar        = null;
    _pendingChar     = null;
    _emergencyPassChar = null;
    _calibChar       = null;
    _debugChar       = null;
  }

  // ── Runtime capability probes (§8.11, §9.5/§9.6) ──────────────────────────
  // Firmware-dependent characteristics may be absent on a given build; degrade
  // gracefully rather than assume they exist.

  bool get hasTimeCharacteristic          => _timeChar != null;
  bool get hasPendingChangesCharacteristic => _pendingChar != null;
  bool get hasEmergencyPassCharacteristic  => _emergencyPassChar != null;
  bool get hasCalibrationCharacteristic    => _calibChar != null;
  bool get hasDebugTelemetryCharacteristic => _debugChar != null;

  /// Set the watch clock over BLE (§8.11): `[utc_epoch int64][tz_offset int16]`.
  /// Returns the response byte (0x01 ok; 0x02 rejected — would end the active
  /// window, §9.7). Returns null if the characteristic is absent.
  Future<int?> pushTime(DateTime utc, int tzOffsetMinutes) async {
    if (_timeChar == null) return null;
    final data = ByteData(10);
    data.setInt64(0, utc.toUtc().millisecondsSinceEpoch ~/ 1000, Endian.little);
    data.setInt16(8, tzOffsetMinutes, Endian.little);

    final completer = Completer<int?>();
    late StreamSubscription sub;
    sub = _timeChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty ? val[0] : null);
        sub.cancel();
      }
    });
    await _timeChar!.setNotifyValue(true);
    await _timeChar!.write(data.buffer.asUint8List(), withoutResponse: false);
    return completer.future.timeout(const Duration(seconds: 5),
        onTimeout: () { sub.cancel(); return null; });
  }

  /// Read the watch's authoritative pending-loosening queue (`…001A`, §9.5).
  /// Returns null if the characteristic is absent (probe before use).
  ///
  /// The returned countdown is the watch's own; the app never adjusts it. This
  /// queue wins over the local app queue wherever both exist (AppState keeps
  /// both and unions the event ids for badges).
  Future<List<PendingChangeEntry>?> readPendingChanges() async {
    if (_pendingChar == null) return null;
    final val = await _pendingChar!.read();
    return _parsePendingChanges(val);
  }

  /// `…001A` layout: [count u8] then per entry [event uuid 16][change_type u8]
  /// [seconds_until_apply u32 LE]. Entries are dropped rather than thrown on if
  /// the payload is short (a read during an update can be truncated).

  List<PendingChangeEntry> _parsePendingChanges(List<int> bytes) {
    if (bytes.isEmpty) return [];
    final count = bytes[0];
    final out = <PendingChangeEntry>[];
    int pos = 1;
    for (int i = 0; i < count; i++) {
      if (pos + 21 > bytes.length) break;
      final uuid = _bytesToUuidStr(bytes.sublist(pos, pos + 16));
      pos += 16;
      final changeType = bytes[pos];
      pos += 1;
      final secs = ByteData.sublistView(
              Uint8List.fromList(bytes.sublist(pos, pos + 4)))
          .getUint32(0, Endian.little);
      pos += 4;
      out.add(PendingChangeEntry(
        eventUuid: uuid,
        changeType: changeType,
        secondsUntilApply: secs,
      ));
    }
    return out;
  }

  /// Read the on-watch pass ledger (`…001B`, firmware §9.6):
  /// `[allowance u8][remaining u8]` then `[seconds_until_regen u32]` per spend
  /// still in the rolling window. Null when the characteristic is absent.
  Future<WatchPassLedger?> readEmergencyPassLedger() async {
    if (_emergencyPassChar == null) return null;
    final bytes = await _emergencyPassChar!.read();
    if (bytes.length < 2) return null;
    final regens = <Duration>[];
    int pos = 2;
    while (pos + 4 <= bytes.length) {
      final secs = ByteData.sublistView(
              Uint8List.fromList(bytes.sublist(pos, pos + 4)))
          .getUint32(0, Endian.little);
      regens.add(Duration(seconds: secs));
      pos += 4;
    }
    return WatchPassLedger(
      allowance: bytes[0],
      remaining: bytes[1],
      regenCountdowns: regens,
    );
  }

  /// Set the pass allowance on the watch (`…001B` SET_ALLOWANCE, §9.6):
  /// `[0x02][allowance u8]`. Response `0x01` = applied (lower/unchanged),
  /// `0x03` = quarantined (a raise is a loosening). Null when absent/timeout.
  Future<int?> setEmergencyPassAllowance(int allowance) async {
    if (_emergencyPassChar == null) return null;
    final completer = Completer<int?>();
    late StreamSubscription sub;
    sub = _emergencyPassChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty ? val[0] : null);
        sub.cancel();
      }
    });
    await _emergencyPassChar!.setNotifyValue(true);
    await _emergencyPassChar!
        .write([0x02, allowance & 0xFF], withoutResponse: false);
    return completer.future.timeout(const Duration(seconds: 5),
        onTimeout: () { sub.cancel(); return null; });
  }

  /// Spend an emergency pass on the watch ledger (`…001B`, §9.6):
  /// `[0x01][event uuid 16][date u32 YYYYMMDD]`. Returns (respByte, remaining).
  /// Response `0x01`+remaining success, `0x02` exhausted, `0x00` malformed.
  /// Returns null if the characteristic is absent (use the interim app ledger).
  Future<({int resp, int? remaining})?> spendEmergencyPass(
      String eventUuid, int dateYyyymmdd) async {
    if (_emergencyPassChar == null) return null;
    final buf = BytesBuilder(copy: false);
    buf.addByte(0x01);
    buf.add(ScheduleEncoder.uuidToBytes(eventUuid));
    final bd = ByteData(4)..setUint32(0, dateYyyymmdd, Endian.little);
    buf.add(bd.buffer.asUint8List());

    final completer = Completer<({int resp, int? remaining})?>();
    late StreamSubscription sub;
    sub = _emergencyPassChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isEmpty
            ? null
            : (resp: val[0], remaining: val.length > 1 ? val[1] : null));
        sub.cancel();
      }
    });
    await _emergencyPassChar!.setNotifyValue(true);
    await _emergencyPassChar!.write(buf.toBytes(), withoutResponse: false);
    return completer.future.timeout(const Duration(seconds: 5),
        onTimeout: () { sub.cancel(); return null; });
  }

  // ── Calibration burst (§4.10.7) ──────────────────────────────────────────

  /// Start an app-guided calibration burst on the watch, targeting [anchorUuid]
  /// (the anchor's 16-byte UUID, as a GUID string). The watch bursts real-MAC
  /// scan vectors at that anchor to fill its fingerprint fast; progress arrives
  /// on [calibrationStream]. [durationS] is clamped by the watch (0 ⇒ default).
  ///
  /// Calibration-v2: [phase] labels the burst — INSIDE (roam the near-zone,
  /// trains + collects) or EDGE (step just past the limit, collects only). The
  /// watch drives the anchor's …000F Calibration Mode to match while bursting.
  /// Throws [StateError] if the watch isn't connected or lacks the feature.
  Future<void> startCalibration(String anchorUuid,
      {int durationS = 0, CalibrationPhase phase = CalibrationPhase.inside}) async {
    if (_calibChar == null) {
      throw StateError('Watch does not support calibration (update firmware)');
    }
    final buf = BytesBuilder(copy: false);
    buf.addByte(0x01);                                   // START
    buf.add(ScheduleEncoder.uuidToBytes(anchorUuid));    // 16-byte target
    buf.add([durationS & 0xFF, (durationS >> 8) & 0xFF]); // uint16 LE
    buf.addByte(_phaseByte(phase));                      // calibration-v2 phase
    await _calibChar!.write(buf.toBytes(), withoutResponse: false);
  }

  /// Convenience alias for switching phase mid-calibration: re-issues START with
  /// a new [phase] (and duration), which the watch treats as a fresh phased burst.
  Future<void> setCalibrationPhase(String anchorUuid, CalibrationPhase phase,
          {int durationS = 0}) =>
      startCalibration(anchorUuid, durationS: durationS, phase: phase);

  /// Request the watch to FINALIZE calibration for [anchorUuid]: the anchor
  /// computes + persists its per-anchor threshold and returns the result frame,
  /// which the watch surfaces on [calibrationStream] as a
  /// [CalibrationState.finalized] progress with a [CalibrationResult]. Because
  /// the watch must reconnect to the anchor (Option A), the caller should
  /// disconnect the phone afterward and reconnect to read the result.
  Future<void> finalizeCalibration(String anchorUuid) async {
    if (_calibChar == null) {
      throw StateError('Watch does not support calibration (update firmware)');
    }
    final buf = BytesBuilder(copy: false);
    buf.addByte(0x02);                                   // FINALIZE
    buf.add(ScheduleEncoder.uuidToBytes(anchorUuid));    // 16-byte target
    await _calibChar!.write(buf.toBytes(), withoutResponse: false);
  }

  /// Abort an in-progress calibration for [anchorUuid]: the anchor discards the
  /// in-progress INSIDE/EDGE stats (keeps any previously persisted threshold).
  Future<void> abortCalibration(String anchorUuid) async {
    if (_calibChar == null) return;
    final buf = BytesBuilder(copy: false);
    buf.addByte(0x03);                                   // ABORT
    buf.add(ScheduleEncoder.uuidToBytes(anchorUuid));    // 16-byte target
    await _calibChar!.write(buf.toBytes(), withoutResponse: false);
  }

  /// Encode [CalibrationPhase] for the START frame. 0 = unphased (legacy),
  /// 1 = INSIDE, 2 = EDGE — the firmware compares against these exact values.
  static int _phaseByte(CalibrationPhase p) {
    switch (p) {
      case CalibrationPhase.inside: return 1;
      case CalibrationPhase.edge:   return 2;
      case CalibrationPhase.none:   return 0;
    }
  }

  /// Stop an in-progress calibration burst. No-op if the feature is absent.
  Future<void> stopCalibration() async {
    if (_calibChar == null) return;
    await _calibChar!.write([0x00], withoutResponse: false);
  }

  /// Read the latest calibration progress frame directly (§8.5 Option A). During
  /// a burst the watch only queries the anchor while the phone is disconnected,
  /// so the app reconnects afterward and reads the final result here rather than
  /// relying on live notifications. Null if the feature is absent or the read
  /// fails.
  Future<CalibrationProgress?> readCalibrationProgress() async {
    if (_calibChar == null) return null;
    try {
      final bytes = await _calibChar!.read();
      return CalibrationProgress.fromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── Debug Telemetry (§5.6) ────────────────────────────────────────────────

  /// Read + decode the watch's Debug Telemetry snapshot (`…001D`, v2 — contract
  /// §4.1/§4.2).
  ///
  /// Returns null when the firmware does not expose the characteristic or the
  /// read/decode fails, so the debug screen can say "not available" instead of
  /// crashing. The payload is longer than a default-MTU notification: callers
  /// must use a read (this method) or the hint-driven read below, never the
  /// notification bytes.
  Future<WatchDebugTelemetry?> readDebugTelemetry() async {
    final c = _debugChar;
    if (c == null) return null;
    try {
      final bytes = await c.read();
      final telemetry = WatchDebugTelemetry.decode(bytes);
      final ranged = telemetry.liveRangedRecord;
      DebugLogService().log(
        'debug_telemetry',
        'activity=${telemetry.activityState.label}  '
        'criteria=${telemetry.criteria?.label ?? 'none'}  '
        'decision=${telemetry.lastDecision?.label ?? 'never'}  '
        'met=${telemetry.conditionMet}  '
        'distance=${ranged?.distanceLabel ?? 'not ranged'}  '
        'peer_kind=${telemetry.linkPeerKind.label}  '
        'records=${telemetry.anchors.length}',
        bytes,
      );
      return telemetry;
    } catch (e) {
      DebugLogService().log('debug_telemetry', 'read/decode failed: $e', const []);
      return null;
    }
  }

  /// One guarded full read after a change hint or a truncated value.
  ///
  /// flutter_blue_plus 1.36.8 delivers `read()` results through the same
  /// `onValueReceived` stream as notifications, so "read on every value" loops
  /// forever. The guard makes the loop terminate: the read's own result comes
  /// back through the listener and decodes cleanly, and only one read can be in
  /// flight at a time.
  void _readDebugOnce(fbp.BluetoothCharacteristic c) {
    if (_debugReadInFlight) return;
    _debugReadInFlight = true;
    c.read()
        .catchError((_) => <int>[])
        .whenComplete(() => _debugReadInFlight = false);
  }

  /// The only place watch characteristic handles are created. Runs once per
  /// connect, after service discovery; the loop stops at the first service whose
  /// UUID matches our watch service, so a device advertising several services
  /// cannot bind a characteristic from the wrong one. A UUID that is absent
  /// simply leaves its field null — that absence IS the feature probe used by
  /// the [hasTimeCharacteristic]-style getters.
  void _bindCharacteristics(List<fbp.BluetoothService> services) {
    for (final svc in services) {
      if (svc.serviceUuid.str.toLowerCase() ==
          BleConstants.watchServiceUuid) {
        _gattService = svc;
        for (final c in svc.characteristics) {
          final uuid = c.characteristicUuid.str.toLowerCase();
          if (uuid == BleConstants.watchWifiCredCharUuid)    _wifiCredChar    = c;
          if (uuid == BleConstants.watchSchedCtrlCharUuid)   _schedCtrlChar   = c;
          if (uuid == BleConstants.watchSchedDataCharUuid)   _schedDataChar   = c;
          if (uuid == BleConstants.watchSettingsCharUuid)    _settingsChar    = c;
          if (uuid == BleConstants.watchSeenAnchorsCharUuid) _seenAnchorsChar = c;
          if (uuid == BleConstants.watchStatusCharUuid)      _statusChar      = c;
          if (uuid == BleConstants.watchAnchorIpCharUuid)    _anchorIpChar    = c;
          if (uuid == BleConstants.watchTimeCharUuid)        _timeChar        = c;
          if (uuid == BleConstants.watchPendingCharUuid)     _pendingChar     = c;
          if (uuid == BleConstants.watchEmergencyPassCharUuid) _emergencyPassChar = c;
          if (uuid == BleConstants.watchCalibCtrlCharUuid)   _calibChar       = c;
          if (uuid == BleConstants.watchDebugTelemetryV2CharUuid)       _debugChar       = c;
        }
        break;
      }
    }
  }

  /// Subscribe to the watch's push characteristics and prime them with one read.
  ///
  /// Every notify is decoded and also written to [DebugLogService] with its raw
  /// bytes — that log is the Debug screen's Log tab and is the only place a
  /// malformed packet can be inspected. Status/seen-anchor reads are wrapped in
  /// try/catch because a device may advertise notify without supporting read.
  ///
  /// Subscriptions are cancelled in [disconnect]; nothing else cancels them.
  Future<void> _subscribeNotifications() async {
    final dbg = DebugLogService();

    if (_statusChar != null) {
      await _statusChar!.setNotifyValue(true);
      _statusSub = _statusChar!.onValueReceived.listen((bytes) {
        final status = WatchStatus.fromBytes(bytes);
        _statusController.add(status);
        dbg.log(
          'status',
          'state=${status.activityLabel}  bt=${status.btConnected}  '
          'wifi=${status.wifiConnected}  worn=${status.worn}  '
          'batt=${status.batteryPct == 0xFF ? "n/a" : "${status.batteryPct}%"}  '
          'event=${status.activeEventId?.substring(0, 8) ?? "none"}',
          bytes,
        );
      });
      try {
        final val = await _statusChar!.read();
        if (val.isNotEmpty) {
          final status = WatchStatus.fromBytes(val);
          _statusController.add(status);
          dbg.log(
            'status (read)',
            'state=${status.activityLabel}  bt=${status.btConnected}  '
            'wifi=${status.wifiConnected}  worn=${status.worn}  '
            'batt=${status.batteryPct == 0xFF ? "n/a" : "${status.batteryPct}%"}  '
            'event=${status.activeEventId?.substring(0, 8) ?? "none"}',
            val,
          );
        }
      } catch (_) {}
    }

    if (_seenAnchorsChar != null) {
      await _seenAnchorsChar!.setNotifyValue(true);
      _seenAnchorsSub = _seenAnchorsChar!.onValueReceived.listen((bytes) {
        final anchors = _parseSeenAnchors(bytes);
        _seenAnchorsController.add(anchors);
        final summary = anchors.isEmpty
            ? 'count=0'
            : anchors.map((a) =>
                '${a.uuid.substring(0, 8)}… rssi=${a.rssi}').join(', ');
        dbg.log('seen_anchors', 'count=${anchors.length}  $summary', bytes);
      });
      try {
        final val = await _seenAnchorsChar!.read();
        if (val.isNotEmpty) {
          final anchors = _parseSeenAnchors(val);
          _seenAnchorsController.add(anchors);
          final summary = anchors.isEmpty
              ? 'count=0'
              : anchors.map((a) =>
                  '${a.uuid.substring(0, 8)}… rssi=${a.rssi}').join(', ');
          dbg.log('seen_anchors (read)', 'count=${anchors.length}  $summary', val);
        }
      } catch (_) {}
    }

    // Calibration burst progress (§4.10.7) — probe: absent on pre-calibration
    // firmware. Only notifies while a burst is running, so subscribing here is
    // idle-cheap.
    if (_calibChar != null) {
      await _calibChar!.setNotifyValue(true);
      _calibSub = _calibChar!.onValueReceived.listen((bytes) {
        final p = CalibrationProgress.fromBytes(bytes);
        if (p == null) return;
        _calibController.add(p);
        dbg.log('calib',
            'state=${p.state.name} accepted=${p.accepted} queries=${p.queries} '
            'score=${p.lastScore} rem=${p.remainingS}s', bytes);
      });
    }

    // Debug Telemetry v2 (`…001D`, contract §4.1/§4.5) — probe: absent on older
    // firmware. Notify carries an 8-byte *change hint*, never the payload: the
    // snapshot is up to 500 bytes over a 23-byte MTU (180-byte header + 10 ×
    // 32-byte records, contract R7). A hint (or a v2 value the
    // stack truncated to MTU−3) triggers exactly one guarded full read; the
    // read's own result comes back through this same listener and decodes.
    if (_debugChar != null) {
      final c = _debugChar!;
      await c.setNotifyValue(true);
      _debugSub = c.onValueReceived.listen((bytes) {
        if (WatchDebugTelemetry.isHint(bytes)) {
          _readDebugOnce(c);
          return;
        }
        try {
          _debugController.add(WatchDebugTelemetry.decode(bytes));
        } on FormatException catch (e) {
          // An unknown version or a structurally impossible header would fail
          // again on a re-read; only a genuine truncation is worth one.
          if (!WatchDebugTelemetry.looksTruncated(bytes)) {
            DebugLogService()
                .log('debug_telemetry', 'decode failed: $e', bytes);
            return;
          }
          _readDebugOnce(c);
        }
      });
      // Seed the first frame; its value is emitted by the listener above.
      await readDebugTelemetry();
    }
  }

  // ── Seen anchors parsing ─────────────────────────────────────────────────
  // `…0015` payload: [count u8] then per entry [uuid 16][rssi+128 u8][ts u32
  // LE]. RSSI is biased by +128 on the wire so it fits a u8. Truncated entries
  // are skipped rather than thrown on.

  List<SeenAnchorInfo> _parseSeenAnchors(List<int> bytes) {
    if (bytes.isEmpty) return [];
    final count = bytes[0];
    final result = <SeenAnchorInfo>[];
    int pos = 1;
    for (int i = 0; i < count; i++) {
      if (pos + 21 > bytes.length) break;
      final uuidBytes = bytes.sublist(pos, pos + 16); pos += 16;
      final rssi      = bytes[pos] - 128;             pos += 1;
      final ts        = ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(pos, pos + 4)))
          .getUint32(0, Endian.little);               pos += 4;
      result.add(SeenAnchorInfo(
        uuid:     _bytesToUuidStr(uuidBytes),
        rssi:     rssi,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
      ));
    }
    return result;
  }

  /// 16 raw bytes -> canonical lowercase UUID string in printed order (NOT
  /// RFC-4122 little-endian). The firmware writes UUIDs in printed order, so the
  /// same conversion appears in BluetoothService, WatchStatus and AnchorService.
  String _bytesToUuidStr(List<int> b) {
    String h(int start, int end) => b
        .sublist(start, end)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${h(0,4)}-${h(4,6)}-${h(6,8)}-${h(8,10)}-${h(10,16)}';
  }

  // ── WiFi credentials ─────────────────────────────────────────────────────
  // `…0011` is Write-No-Response and the payload is JSON, one network per write.
  // No ack exists at the transport level, so "the write completed without an
  // exception" is the strongest confirmation the app can get (§8.16 treats that
  // as the ack for the watchNetworks class).

  Future<void> pushWifiCredentials(String ssid, String password) async {
    if (_wifiCredChar == null) throw StateError('Not connected to watch');
    final json = jsonEncode({'ssid': ssid, 'password': password});
    await _wifiCredChar!.write(
      utf8.encode(json),
      withoutResponse: true,
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  /// Returns true on success (watch responded 0x01).
  /// (Interface note: the signature returns `int?` — the response byte — so the
  /// "true on success" phrasing above is historical; compare against `0x01`.)
  /// Settings payload (v2, 6 bytes — firmware v0.5, lockstep):
  /// `[disconnected_is_dormant u8][away_is_dormant u8][tz_offset int16]
  ///  [settle_window_min u16 (clamped 30–240)]`.
  /// Returns the response byte: `0x01` applied in full; `0x03` loosening
  /// fields quarantined (§9.8); `0x02` tz change rejected because it would
  /// escape the active window (§9.7). Null on timeout — never render `0x03`
  /// or `0x02` as a plain failure or a full apply.
  Future<int?> pushSettings({
    required bool disconnectedIsDormant,
    required bool awayIsDormant,
    required int tzOffsetMinutes,
    int settleWindowMin = 120,
  }) async {
    if (_settingsChar == null) throw StateError('Not connected to watch');

    final data = ByteData(6);
    data.setUint8(0, disconnectedIsDormant ? 1 : 0);
    data.setUint8(1, awayIsDormant         ? 1 : 0);
    data.setInt16(2, tzOffsetMinutes, Endian.little);
    data.setUint16(4, settleWindowMin.clamp(30, 240), Endian.little);

    final completer = Completer<int?>();
    late StreamSubscription sub;
    sub = _settingsChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty ? val[0] : null);
        sub.cancel();
      }
    });

    await _settingsChar!.setNotifyValue(true);
    await _settingsChar!.write(
      data.buffer.asUint8List(),
      withoutResponse: false,
    );

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () { sub.cancel(); return null; },
    );
  }

  // ── Schedule transfer ─────────────────────────────────────────────────────
  // Three-phase transfer (spec §7.1): BEGIN(len) -> DATA chunks -> END(crc). The
  // watch answers BEGIN and END on the Ctrl characteristic; a CRC mismatch makes
  // it discard the whole blob and answer 0x00, which is surfaced as `failed`
  // (there is no automatic retry — the caller decides). The END verdict is the
  // watch's own diff-gate decision and must be rendered as such: 0x01 applied,
  // 0x03 applied with loosening quarantined, 0x04 rejected.

  /// Encodes and sends the full schedule to the watch via the 3-phase BLE
  /// transfer protocol. Returns the watch's END verdict (§7.1) — the app must
  /// never render `0x03`/`0x04` as if the edit fully applied.
  Future<ScheduleEndResult> pushSchedule(List<Automation> automations) async {
    if (_schedCtrlChar == null || _schedDataChar == null) {
      throw StateError('Not connected to watch');
    }

    final blob = ScheduleEncoder.encodeBlob(automations);
    final crc  = ScheduleEncoder.crc32(blob);

    // Subscribe to ctrl notifications so we can read responses.
    await _schedCtrlChar!.setNotifyValue(true);

    // ── Phase 1: BEGIN ──────────────────────────────────────────────────
    final beginPkt = ByteData(5);
    beginPkt.setUint8(0, 0x01);
    beginPkt.setUint32(1, blob.length, Endian.little);

    final beginByte = await _writeCtrlAwaitByte(beginPkt.buffer.asUint8List());
    if (beginByte != 0x01) return ScheduleEndResult.failed;

    // ── Phase 2: DATA (chunks ≤ 20 bytes) ──────────────────────────────
    // 20 = the default ATT MTU (23) minus the 3-byte write header. The spec
    // suggests negotiating ~512 first; this code does not, so every transfer
    // uses the smallest payload. Correct but slow for a full week's schedule.
    // Each chunk is write-no-response with a 10 ms yield to let the Android BLE
    // stack drain; removing the yield overruns the stack on Android.
    const chunkSize = 20;
    for (int i = 0; i < blob.length; i += chunkSize) {
      final end = (i + chunkSize > blob.length) ? blob.length : i + chunkSize;
      await _schedDataChar!.write(
        blob.sublist(i, end),
        withoutResponse: true,
      );
      // Small yield to avoid overwhelming the BLE stack
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // ── Phase 3: END with CRC ──────────────────────────────────────────
    final endPkt = ByteData(5);
    endPkt.setUint8(0, 0x02);
    endPkt.setUint32(1, crc, Endian.little);

    final endByte = await _writeCtrlAwaitByte(endPkt.buffer.asUint8List());
    switch (endByte) {
      case 0x01:
        return ScheduleEndResult.accepted;
      case 0x03:
        return ScheduleEndResult.partialQuarantine;
      case 0x04:
        return ScheduleEndResult.rejected;
      default:
        return ScheduleEndResult.failed;
    }
  }

  /// Writes to the schedule ctrl characteristic and returns the firmware's
  /// first response byte (or null on timeout).
  Future<int?> _writeCtrlAwaitByte(List<int> data) async {
    final completer = Completer<int?>();
    late StreamSubscription sub;
    sub = _schedCtrlChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty ? val[0] : null);
        sub.cancel();
      }
    });
    await _schedCtrlChar!.write(data, withoutResponse: false);
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () { sub.cancel(); return null; },
    );
  }

  // ── Anchor IP table ───────────────────────────────────────────────────────
  // `…0017`: [count u8] then per anchor [uuid 16][ipv4 4 bytes network order]
  // [ts u32 LE]. The watch needs this to reach anchors over UDP for beep
  // commands, so it is re-pushed whenever an IP is learned or a sync says the
  // watch is behind (AppState._pushAnchorIpTableTracked).
  // IPv4 is written as raw dotted-quad octets — NOT little-endian — matching the
  // spec's "network-order" note.

  /// Pushes the known anchor IP addresses to the watch.
  /// [anchors] is the list of anchor [BluetoothDeviceModel] entries that have
  /// an [ipAddress] set.
  Future<bool> pushAnchorIpTable(List<BluetoothDeviceModel> anchors) async {
    if (_anchorIpChar == null) throw StateError('Not connected to watch');

    final validAnchors = anchors
        .where((a) => a.deviceType == DeviceType.anchor && a.ipAddress != null)
        .toList();

    final buf = BytesBuilder(copy: false);
    buf.addByte(validAnchors.length);

    for (final a in validAnchors) {
      buf.add(ScheduleEncoder.uuidToBytes(a.id)); // 16 bytes UUID
      // IPv4 address as 4 bytes (network byte order)
      final parts = a.ipAddress!.split('.');
      for (final part in parts) { buf.addByte(int.parse(part)); }
      // Timestamp (uint32 LE)
      final ts = (a.ipLastUpdated ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      final bd = ByteData(4)..setUint32(0, ts, Endian.little);
      buf.add(bd.buffer.asUint8List());
    }

    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = _anchorIpChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty && val[0] == 0x01);
        sub.cancel();
      }
    });

    await _anchorIpChar!.setNotifyValue(true);
    await _anchorIpChar!.write(buf.toBytes(), withoutResponse: false);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () { sub.cancel(); return false; },
    );
  }

  /// Closes the two broadcast controllers. Not called anywhere in the app today
  /// (the singleton lives for the process lifetime); calling it a second time
  /// after a `connect` would leave listeners on closed controllers.
  void dispose() {
    _statusController.close();
    _seenAnchorsController.close();
  }
}
