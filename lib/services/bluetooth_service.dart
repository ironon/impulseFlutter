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

  // ── System-connected devices ─────────────────────────────────────────────

  /// Finds devices that the OS is *already* connected to.
  ///
  /// This is critical on iOS: CoreBluetooth never reports a peripheral in
  /// scan results while the phone holds a connection to it (paired in
  /// Settings, held by another app, or a stale connection from a previous
  /// session). Without this, an already-connected watch is invisible to the
  /// scan even though apps like LightBlue still list it.
  ///
  /// Queries by our known service UUIDs (iOS requires a service filter for
  /// this API), merges the results into the device history, and returns the
  /// devices found.
  Future<List<BluetoothDeviceModel>> discoverSystemDevices() async {
    final found = <BluetoothDeviceModel>[];

    Future<void> query(
      String serviceUuid,
      DeviceType type,
      String fallbackName,
    ) async {
      List<fbp.BluetoothDevice> devices;
      try {
        devices = await fbp.FlutterBluePlus.systemDevices(
          [fbp.Guid(serviceUuid)],
        );
      } catch (_) {
        // API unavailable / adapter off — just skip, scan proceeds normally.
        return;
      }

      for (final d in devices) {
        final remoteId = d.remoteId.toString();

        // Anchors are keyed by their beacon UUID rather than remoteId, so
        // match on either field to avoid creating a duplicate entry.
        final existing = _deviceHistory
            .where((x) => x.id == remoteId || x.bleRemoteId == remoteId)
            .firstOrNull;

        final model = existing != null
            ? existing.copyWith(
                name: d.platformName.isNotEmpty
                    ? d.platformName
                    : existing.name,
                lastSeen: DateTime.now(),
                bleRemoteId: remoteId,
              )
            : BluetoothDeviceModel(
                id: remoteId,
                name: d.platformName.isNotEmpty ? d.platformName : fallbackName,
                isConnected: false,
                rssi: 0, // RSSI is unknown without an advertisement
                lastSeen: DateTime.now(),
                deviceType: type,
                bleRemoteId: remoteId,
              );

        await addOrUpdateDevice(model);
        found.add(model);
      }
    }

    await query(BleConstants.watchServiceUuid, DeviceType.watch, 'Impulse Watch');
    await query(BleConstants.anchorServiceUuid, DeviceType.anchor, 'Anchor');
    return found;
  }

  // ── Scanning ─────────────────────────────────────────────────────────────

  /// Starts a BLE scan and returns scan results as a stream.
  /// Devices advertising [WATCH_SERVICE_UUID] are typed as [DeviceType.watch].
  /// Devices with iBeacon manufacturer data (Apple company ID) may be anchors.
  ///
  /// Note: this only yields devices that are actively advertising. Call
  /// [discoverSystemDevices] as well to pick up devices the OS is already
  /// connected to, since those are hidden from scan results on iOS.
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
    // Fallback: Impulse custom manufacturer data (company ID 0xFFFF, visible on all platforms)
    final mfr = result.advertisementData.manufacturerData;
    if (mfr.containsKey(0xFFFF)) {
      final data = mfr[0xFFFF]!;
      if (data.length >= 23 &&
          data[0] == BleConstants.iBeaconType &&
          data[1] == BleConstants.iBeaconLength) {
        return DeviceType.anchor;
      }
    }
    return DeviceType.unknown;
  }

  /// Extracts the anchor's UUID from a scan result.
  /// Reads from Impulse custom manufacturer data (company ID 0xFFFF), which
  /// is visible on both iOS and Android (unlike Apple 0x004C which iOS strips).
  String? extractAnchorUuid(fbp.ScanResult result) {
    final mfr = result.advertisementData.manufacturerData;
    if (!mfr.containsKey(0xFFFF)) return null;
    final data = mfr[0xFFFF]!;
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