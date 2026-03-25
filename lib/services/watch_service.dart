import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../utils/ble_constants.dart';
import '../utils/schedule_encoder.dart';

// ── WatchStatus model ────────────────────────────────────────────────────────

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

  const WatchStatus({
    required this.activityState,
    required this.btConnected,
    required this.wifiConnected,
    required this.worn,
    required this.batteryPct,
    this.activeEventId,
  });

  String get activityLabel {
    switch (activityState) {
      case 0: return 'Dormant';
      case 1: return 'Enforcement';
      case 2: return 'Sleep';
      default: return 'Unknown';
    }
  }

  static WatchStatus fromBytes(List<int> bytes) {
    if (bytes.length < 21) {
      return const WatchStatus(
        activityState: 0,
        btConnected: false,
        wifiConnected: false,
        worn: false,
        batteryPct: 0xFF,
      );
    }
    final actState    = bytes[0];
    final btConn      = bytes[1] != 0;
    final wifiConn    = bytes[2] != 0;
    final worn        = bytes[3] != 0;
    final batt        = bytes[4];

    // Active event UUID (16 bytes at offset 5)
    final eventBytes  = bytes.sublist(5, 21);
    final allZero     = eventBytes.every((b) => b == 0);
    String? eventId;
    if (!allZero) {
      eventId = _bytesToUuidStr(eventBytes);
    }

    return WatchStatus(
      activityState: actState,
      btConnected: btConn,
      wifiConnected: wifiConn,
      worn: worn,
      batteryPct: batt,
      activeEventId: eventId,
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
        }
        break;
      }
    }
  }

  Future<void> _subscribeNotifications() async {
    if (_statusChar != null) {
      await _statusChar!.setNotifyValue(true);
      _statusSub = _statusChar!.onValueReceived.listen((bytes) {
        _statusController.add(WatchStatus.fromBytes(bytes));
      });
      // Read current value immediately
      try {
        final val = await _statusChar!.read();
        if (val.isNotEmpty) _statusController.add(WatchStatus.fromBytes(val));
      } catch (_) {}
    }

    if (_seenAnchorsChar != null) {
      await _seenAnchorsChar!.setNotifyValue(true);
      _seenAnchorsSub = _seenAnchorsChar!.onValueReceived.listen((bytes) {
        _seenAnchorsController.add(_parseSeenAnchors(bytes));
      });
      try {
        final val = await _seenAnchorsChar!.read();
        if (val.isNotEmpty) _seenAnchorsController.add(_parseSeenAnchors(val));
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
  Future<bool> pushSettings({
    required bool disconnectedIsDormant,
    required bool awayIsDormant,
    required int tzOffsetMinutes,
  }) async {
    if (_settingsChar == null) throw StateError('Not connected to watch');

    final data = ByteData(4);
    data.setUint8(0, disconnectedIsDormant ? 1 : 0);
    data.setUint8(1, awayIsDormant         ? 1 : 0);
    data.setInt16(2, tzOffsetMinutes, Endian.little);

    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = _settingsChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty && val[0] == 0x01);
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
      onTimeout: () { sub.cancel(); return false; },
    );
  }

  // ── Schedule transfer ─────────────────────────────────────────────────────

  /// Encodes and sends the full schedule to the watch via the 3-phase BLE
  /// transfer protocol.  Returns true if the watch acknowledged successfully.
  Future<bool> pushSchedule(List<Automation> automations) async {
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

    var respOk = await _writeCtrlAwaitNotify(beginPkt.buffer.asUint8List());
    if (!respOk) return false;

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

    respOk = await _writeCtrlAwaitNotify(endPkt.buffer.asUint8List());
    return respOk;
  }

  /// Writes to the schedule ctrl characteristic and waits for a notify
  /// response from the firmware.  Returns true if firmware replied 0x01.
  Future<bool> _writeCtrlAwaitNotify(List<int> data) async {
    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = _schedCtrlChar!.onValueReceived.listen((val) {
      if (!completer.isCompleted) {
        completer.complete(val.isNotEmpty && val[0] == 0x01);
        sub.cancel();
      }
    });
    await _schedCtrlChar!.write(data, withoutResponse: false);
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () { sub.cancel(); return false; },
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
