import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bluetooth_device_model.dart';
import '../utils/ble_constants.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  static const String _devicesKey = 'paired_devices';
  List<BluetoothDeviceModel> _deviceHistory = [];

  List<BluetoothDeviceModel> get deviceHistory => _deviceHistory;

  List<BluetoothDeviceModel> get watches =>
      _deviceHistory.where((d) => d.deviceType == DeviceType.watch).toList();

  List<BluetoothDeviceModel> get anchors =>
      _deviceHistory.where((d) => d.deviceType == DeviceType.anchor).toList();

  Future<void> initialize() async {
    await _loadDeviceHistory();
  }

  Future<void> _loadDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString(_devicesKey);
    if (json != null) {
      final List<dynamic> decoded = jsonDecode(json);
      _deviceHistory = decoded
          .map((j) => BluetoothDeviceModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _saveDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _devicesKey,
      jsonEncode(_deviceHistory.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> removeDevice(String id) async {
    _deviceHistory.removeWhere((d) => d.id == id);
    await _saveDeviceHistory();
  }

  Future<void> addOrUpdateDevice(BluetoothDeviceModel device) async {
    final idx = _deviceHistory.indexWhere((d) => d.id == device.id);
    if (idx != -1) {
      _deviceHistory[idx] = device;
    } else {
      _deviceHistory.add(device);
    }
    await _saveDeviceHistory();
  }

  Future<void> updateDeviceStatus(
    String deviceId,
    bool isConnected,
    int rssi,
  ) async {
    final idx = _deviceHistory.indexWhere((d) => d.id == deviceId);
    if (idx != -1) {
      _deviceHistory[idx] = _deviceHistory[idx].copyWith(
        isConnected: isConnected,
        rssi: rssi,
        lastSeen: DateTime.now(),
      );
      await _saveDeviceHistory();
    }
  }

  Future<void> updateAnchorIp(
    String anchorId,
    String ipAddress,
  ) async {
    final idx = _deviceHistory.indexWhere((d) => d.id == anchorId);
    if (idx != -1) {
      _deviceHistory[idx] = _deviceHistory[idx].copyWith(
        ipAddress: ipAddress,
        ipLastUpdated: DateTime.now(),
      );
      await _saveDeviceHistory();
    }
  }

  // ── Scanning ─────────────────────────────────────────────────────────────

  /// Starts a BLE scan and returns scan results as a stream.
  /// Devices advertising [WATCH_SERVICE_UUID] are typed as [DeviceType.watch].
  /// Devices with iBeacon manufacturer data (Apple company ID) may be anchors.
  Stream<List<fbp.ScanResult>> startScan() async* {
    if (await fbp.FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth not supported by this device');
    }

    await fbp.FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );

    yield* fbp.FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  /// Infers the device type from advertisement data.
  DeviceType classifyDevice(fbp.ScanResult result) {
    for (final svcUuid in result.advertisementData.serviceUuids) {
      final u = svcUuid.str.toLowerCase();
      if (u == BleConstants.watchServiceUuid)  return DeviceType.watch;
      if (u == BleConstants.anchorServiceUuid) return DeviceType.anchor;
    }
    // Fallback: iBeacon manufacturer data (visible on Android, stripped on iOS)
    final mfr = result.advertisementData.manufacturerData;
    if (mfr.containsKey(0x004C)) {
      final data = mfr[0x004C]!;
      if (data.length >= 23 &&
          data[0] == BleConstants.iBeaconType &&
          data[1] == BleConstants.iBeaconLength) {
        return DeviceType.anchor;
      }
    }
    return DeviceType.unknown;
  }

  /// Extracts the anchor's iBeacon UUID from a scan result.
  /// Checks service data first (scan response, works on iOS), then falls back
  /// to iBeacon manufacturer data (works on Android).
  String? extractAnchorUuid(fbp.ScanResult result) {
    // Primary: service data payload in the scan response (16 raw UUID bytes)
    final svcData = result.advertisementData.serviceData;
    for (final entry in svcData.entries) {
      if (entry.key.str.toLowerCase() == BleConstants.anchorServiceUuid &&
          entry.value.length >= 16) {
        return _bytesToUuidStr(entry.value.sublist(0, 16));
      }
    }
    // Fallback: iBeacon manufacturer data
    final mfr = result.advertisementData.manufacturerData;
    if (!mfr.containsKey(0x004C)) return null;
    final data = mfr[0x004C]!;
    if (data.length < 23 ||
        data[0] != BleConstants.iBeaconType ||
        data[1] != BleConstants.iBeaconLength) { return null; }
    return _bytesToUuidStr(data.sublist(2, 18));
  }

  String _bytesToUuidStr(List<int> b) {
    String h(int s, int e) => b
        .sublist(s, e)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${h(0,4)}-${h(4,6)}-${h(6,8)}-${h(8,10)}-${h(10,16)}';
  }

  String getSignalStrength(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    return 'Weak';
  }
}
