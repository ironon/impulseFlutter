import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bluetooth_device_model.dart';

class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  static const String _devicesKey = 'paired_devices';
  List<BluetoothDeviceModel> _deviceHistory = [];

  List<BluetoothDeviceModel> get deviceHistory => _deviceHistory;

  // Initialize and load device history
  Future<void> initialize() async {
    await _loadDeviceHistory();
  }

  // Load device history from shared preferences
  Future<void> _loadDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? devicesJson = prefs.getString(_devicesKey);

    if (devicesJson != null) {
      final List<dynamic> decoded = jsonDecode(devicesJson);
      _deviceHistory = decoded
          .map((json) => BluetoothDeviceModel.fromJson(json))
          .toList();
    }
  }

  // Save device history to shared preferences
  Future<void> _saveDeviceHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(
      _deviceHistory.map((device) => device.toJson()).toList(),
    );
    await prefs.setString(_devicesKey, encoded);
  }

  // Add or update a device in history
  Future<void> addOrUpdateDevice(BluetoothDeviceModel device) async {
    final index = _deviceHistory.indexWhere((d) => d.id == device.id);

    if (index != -1) {
      _deviceHistory[index] = device;
    } else {
      _deviceHistory.add(device);
    }

    await _saveDeviceHistory();
  }

  // Update device connection status
  Future<void> updateDeviceStatus(String deviceId, bool isConnected, int rssi) async {
    final index = _deviceHistory.indexWhere((d) => d.id == deviceId);

    if (index != -1) {
      _deviceHistory[index] = _deviceHistory[index].copyWith(
        isConnected: isConnected,
        rssi: rssi,
        lastSeen: DateTime.now(),
      );
      await _saveDeviceHistory();
    }
  }

  // Start scanning for devices
  Stream<List<fbp.ScanResult>> startScan() async* {
    // Check if Bluetooth is available
    if (await fbp.FlutterBluePlus.isSupported == false) {
      throw Exception('Bluetooth not supported by this device');
    }

    // Start scanning
    await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    // Listen to scan results
    yield* fbp.FlutterBluePlus.scanResults;
  }

  // Stop scanning
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  // Connect to a device
  Future<void> connectToDevice(fbp.BluetoothDevice device) async {
    await device.connect();
  }

  // Disconnect from a device
  Future<void> disconnectFromDevice(fbp.BluetoothDevice device) async {
    await device.disconnect();
  }

  // Get signal strength description
  String getSignalStrength(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    return 'Weak';
  }
}
