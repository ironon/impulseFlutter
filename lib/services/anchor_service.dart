import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../utils/ble_constants.dart';

enum AnchorToggleResult {
  success,         // Firmware responded 0x01
  rejected,        // Firmware responded 0x02 (enforcement active)
  connectionError, // Could not connect or discover service/characteristic
}

class AnchorService {
  static final AnchorService _instance = AnchorService._internal();
  factory AnchorService() => _instance;
  AnchorService._internal();

  /// Connects to the anchor with [bleRemoteId], writes [value] (0=close, 1=open)
  /// to the toggle characteristic, and returns the firmware's response.
  Future<AnchorToggleResult> sendToggle(String bleRemoteId, int value) async {
    final fbpDevice = fbp.BluetoothDevice.fromId(bleRemoteId);
    try {
      await fbpDevice.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      return AnchorToggleResult.connectionError;
    }

    try {
      List<fbp.BluetoothService> services;
      try {
        services = await fbpDevice.discoverServices();
      } catch (_) {
        await fbpDevice.disconnect();
        return AnchorToggleResult.connectionError;
      }

      fbp.BluetoothService? anchorSvc;
      for (final svc in services) {
        if (svc.serviceUuid.str.toLowerCase() == BleConstants.anchorServiceUuid) {
          anchorSvc = svc;
          break;
        }
      }
      if (anchorSvc == null) {
        await fbpDevice.disconnect();
        return AnchorToggleResult.connectionError;
      }

      fbp.BluetoothCharacteristic? toggleChar;
      for (final c in anchorSvc.characteristics) {
        if (c.characteristicUuid.str.toLowerCase() == BleConstants.anchorToggleCharUuid) {
          toggleChar = c;
          break;
        }
      }
      if (toggleChar == null) {
        await fbpDevice.disconnect();
        return AnchorToggleResult.connectionError;
      }

      List<int> response;
      try {
        response = await toggleChar.write([value], withoutResponse: false)
            .then((_) => toggleChar!.read())
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        await fbpDevice.disconnect();
        return AnchorToggleResult.connectionError;
      }

      await fbpDevice.disconnect();

      if (response.isEmpty) return AnchorToggleResult.connectionError;
      if (response[0] == 0x01) return AnchorToggleResult.success;
      if (response[0] == 0x02) return AnchorToggleResult.rejected;
      return AnchorToggleResult.connectionError;
    } catch (_) {
      try { await fbpDevice.disconnect(); } catch (_) {}
      return AnchorToggleResult.connectionError;
    }
  }
}
