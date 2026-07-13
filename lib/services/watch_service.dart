import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../utils/ble_constants.dart';
import '../utils/schedule_encoder.dart';
import 'debug_log_service.dart';

// ── WatchStatus model ────────────────────────────────────────────────────────

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
  bool get isAlarming => activeEventId != null && conditionMet == false;

  static WatchStatus fromBytes(List<int> bytes) {
    // Layout: activity u8, bt u8, wifi u8, worn u8, battery u8,
    //         active_event_id 16, [condition_met u8], [unreachable_count u8, ...]
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

  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<List<int>>? _seenAnchorsSub;

  final _statusController       = StreamController<WatchStatus>.broadcast();
  final _seenAnchorsController  = StreamController<List<SeenAnchorInfo>>.broadcast();

  Stream<WatchStatus>          get statusStream       => _statusController.stream;
  Stream<List<SeenAnchorInfo>> get seenAnchorsStream  => _seenAnchorsController.stream;

  bool get isConnected => _device != null &&
      (_device!.isConnected);

  fbp.BluetoothDevice? get device => _device;

  // ── Connect / disconnect ─────────────────────────────────────────────────

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
    _statusSub = null;
    _seenAnchorsSub = null;
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
  }

  // ── Runtime capability probes (§8.11, §9.5/§9.6) ──────────────────────────
  // Firmware-dependent characteristics may be absent on a given build; degrade
  // gracefully rather than assume they exist.

  bool get hasTimeCharacteristic          => _timeChar != null;
  bool get hasPendingChangesCharacteristic => _pendingChar != null;
  bool get hasEmergencyPassCharacteristic  => _emergencyPassChar != null;

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
  Future<List<PendingChangeEntry>?> readPendingChanges() async {
    if (_pendingChar == null) return null;
    final val = await _pendingChar!.read();
    return _parsePendingChanges(val);
  }

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
        }
        break;
      }
    }
  }

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
  }

  // ── Seen anchors parsing ─────────────────────────────────────────────────

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

  String _bytesToUuidStr(List<int> b) {
    String h(int start, int end) => b
        .sublist(start, end)
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${h(0,4)}-${h(4,6)}-${h(6,8)}-${h(8,10)}-${h(10,16)}';
  }

  // ── WiFi credentials ─────────────────────────────────────────────────────

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

  void dispose() {
    _statusController.close();
    _seenAnchorsController.close();
  }
}
