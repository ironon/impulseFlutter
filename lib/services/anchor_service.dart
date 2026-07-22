import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../utils/ble_constants.dart';

enum AnchorToggleResult {
  success,         // Firmware responded 0x01
  rejected,        // Firmware responded 0x02 (enforcement active)
  connectionError, // Could not connect or discover service/characteristic
}

/// Anchor WiFi connection state, from the WiFi Status characteristic `…000E`
/// (firmware §4.4, v0.8). States 0/3/4 are "distress" (§8.14).
enum AnchorWifiState {
  neverProvisioned, // 0x00
  connecting,       // 0x01
  connected,        // 0x02
  authFailed,       // 0x03  (distress)
  apNotFound,       // 0x04  (distress)
  unknown;

  static AnchorWifiState fromByte(int b) {
    switch (b) {
      case 0: return AnchorWifiState.neverProvisioned;
      case 1: return AnchorWifiState.connecting;
      case 2: return AnchorWifiState.connected;
      case 3: return AnchorWifiState.authFailed;
      case 4: return AnchorWifiState.apNotFound;
      default: return AnchorWifiState.unknown;
    }
  }

  /// True when a human/peer must intervene (§4.5.1): auth-fail, AP-not-found, or
  /// never-provisioned.
  bool get isDistress =>
      this == AnchorWifiState.authFailed ||
      this == AnchorWifiState.apNotFound ||
      this == AnchorWifiState.neverProvisioned;
}

/// Decoded WiFi Status `…000E` payload (firmware §4.4):
/// `[state][ssid_len][ssid][ipv4 net-order][rssi+128][slots_used][schedule_crc u32 LE]`.
class AnchorWifiStatus {
  final AnchorWifiState state;
  /// SSID of the slot in use or last attempted; empty when never provisioned.
  final String ssid;
  /// Dotted-quad IPv4, or null when not connected (all-zero).
  final String? ipv4;
  /// AP link RSSI in dBm, or null when not connected.
  final int? rssi;
  final int slotsUsed;
  /// CRC32 of the schedule blob the anchor holds (mirrors GET /schedule); null
  /// on a pre-v0.8/truncated payload, 0 ⇒ no schedule. Used for §8.16 sync check.
  final int? scheduleCrc;

  const AnchorWifiStatus({
    required this.state,
    required this.ssid,
    required this.ipv4,
    required this.rssi,
    required this.slotsUsed,
    required this.scheduleCrc,
  });

  static AnchorWifiStatus? fromBytes(List<int> b) {
    if (b.length < 2) return null;
    int pos = 0;
    final state = AnchorWifiState.fromByte(b[pos++]);
    final ssidLen = b[pos++];
    if (pos + ssidLen > b.length) return null;
    final ssid = utf8.decode(b.sublist(pos, pos + ssidLen), allowMalformed: true);
    pos += ssidLen;
    String? ipv4;
    if (pos + 4 <= b.length) {
      // network byte order (big-endian) → a.b.c.d
      final a = b[pos], bb = b[pos + 1], c = b[pos + 2], d = b[pos + 3];
      pos += 4;
      ipv4 = (a | bb | c | d) == 0 ? null : '$a.$bb.$c.$d';
    }
    int? rssi;
    if (pos < b.length) {
      final r = b[pos++];
      rssi = r == 0 ? null : r - 128;
    }
    int slotsUsed = 0;
    if (pos < b.length) slotsUsed = b[pos++];
    int? scheduleCrc;
    if (pos + 4 <= b.length) {
      scheduleCrc = ByteData.sublistView(
              Uint8List.fromList(b.sublist(pos, pos + 4)))
          .getUint32(0, Endian.little);
      pos += 4;
    }
    return AnchorWifiStatus(
      state: state,
      ssid: ssid,
      ipv4: ipv4,
      rssi: rssi,
      slotsUsed: slotsUsed,
      scheduleCrc: scheduleCrc,
    );
  }
}

/// Outcome of a credential offer to an anchor (`…0003`, §8.14).
class AnchorWifiOfferResult {
  /// True when the anchor responded `0x01` = accepted (NOT "connected").
  final bool accepted;
  /// True when we couldn't connect / discover / write at all.
  final bool connectionError;
  /// The most recent WiFi Status observed after the offer (from a `…000E`
  /// notify or read within the wait window), if any.
  final AnchorWifiStatus? statusAfter;

  const AnchorWifiOfferResult({
    required this.accepted,
    required this.connectionError,
    required this.statusAfter,
  });

  static const connError = AnchorWifiOfferResult(
      accepted: false, connectionError: true, statusAfter: null);
}

class AnchorService {
  static final AnchorService _instance = AnchorService._internal();
  factory AnchorService() => _instance;
  AnchorService._internal();

  /// Connects to the anchor and writes the Identify characteristic so it
  /// beeps (~800 ms) — the "which physical anchor is this" affordance.
  /// Returns true when the write went out.
  Future<bool> identify(String bleRemoteId) async {
    final fbpDevice = fbp.BluetoothDevice.fromId(bleRemoteId);
    try {
      await fbpDevice.connect(timeout: const Duration(seconds: 8));
      final services = await fbpDevice.discoverServices();
      var wrote = false;
      for (final svc in services) {
        if (svc.serviceUuid.str.toLowerCase() ==
            BleConstants.anchorServiceUuid) {
          for (final c in svc.characteristics) {
            if (c.characteristicUuid.str.toLowerCase() ==
                BleConstants.anchorIdentifyCharUuid) {
              await c.write([0x01], withoutResponse: true);
              wrote = true;
              break;
            }
          }
        }
      }
      await fbpDevice.disconnect();
      return wrote;
    } catch (_) {
      try { await fbpDevice.disconnect(); } catch (_) {}
      return false;
    }
  }

  /// Connects, discovers, and returns the anchor GATT service (or null). Leaves
  /// the connection OPEN — the caller must disconnect. Shared by the WiFi paths.
  Future<fbp.BluetoothService?> _connectAndFindService(
      fbp.BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.serviceUuid.str.toLowerCase() == BleConstants.anchorServiceUuid) {
          return svc;
        }
      }
    } catch (_) {}
    return null;
  }

  fbp.BluetoothCharacteristic? _findChar(
      fbp.BluetoothService svc, String uuid) {
    for (final c in svc.characteristics) {
      if (c.characteristicUuid.str.toLowerCase() == uuid) return c;
    }
    return null;
  }

  /// Reads the anchor's WiFi Status characteristic `…000E` (§4.4). This is the
  /// cheap BLE read that §8.14's check-then-offer sweep is built on — never a
  /// blind write. Returns null on connection failure or if the characteristic
  /// is absent (older firmware — caller degrades gracefully, §10 item 6).
  Future<AnchorWifiStatus?> readWifiStatus(String bleRemoteId) async {
    final device = fbp.BluetoothDevice.fromId(bleRemoteId);
    final svc = await _connectAndFindService(device);
    if (svc == null) {
      try { await device.disconnect(); } catch (_) {}
      return null;
    }
    try {
      final c = _findChar(svc, BleConstants.anchorWifiStatusCharUuid);
      if (c == null) return null; // pre-v0.8 anchor: probe-absent, degrade
      final bytes = await c.read().timeout(const Duration(seconds: 8));
      return AnchorWifiStatus.fromBytes(bytes);
    } catch (_) {
      return null;
    } finally {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  /// Offers a saved network to the anchor by writing `{ssid,password}` JSON to
  /// WiFi Credentials `…0003` (§4.4 / §8.14). Subscribes to `…000E` FIRST so the
  /// connection outcome can be observed — `0x01` means *accepted*, never
  /// "connected" (v0.8 non-blocking write). Waits up to [outcomeWait] for a
  /// status notify so the caller learns whether the offer actually worked.
  Future<AnchorWifiOfferResult> sendWifiCredentials(
    String bleRemoteId, {
    required String ssid,
    required String password,
    Duration outcomeWait = const Duration(seconds: 16),
  }) async {
    final device = fbp.BluetoothDevice.fromId(bleRemoteId);
    final svc = await _connectAndFindService(device);
    if (svc == null) {
      try { await device.disconnect(); } catch (_) {}
      return AnchorWifiOfferResult.connError;
    }

    StreamSubscription<List<int>>? statusSub;
    StreamSubscription<List<int>>? credSub;
    try {
      final credChar = _findChar(svc, BleConstants.anchorWifiCredCharUuid);
      if (credChar == null) return AnchorWifiOfferResult.connError;
      final statusChar = _findChar(svc, BleConstants.anchorWifiStatusCharUuid);

      // Subscribe to …000E BEFORE writing so we don't miss the outcome notify.
      AnchorWifiStatus? latestStatus;
      final outcomeCompleter = Completer<void>();
      if (statusChar != null) {
        await statusChar.setNotifyValue(true);
        statusSub = statusChar.onValueReceived.listen((bytes) {
          final s = AnchorWifiStatus.fromBytes(bytes);
          if (s != null) {
            latestStatus = s;
            // A terminal (connected or distress) state ends the wait early.
            if (s.state == AnchorWifiState.connected || s.state.isDistress) {
              if (!outcomeCompleter.isCompleted) outcomeCompleter.complete();
            }
          }
        });
      }

      // Capture the accepted/malformed byte the firmware notifies on …0003.
      bool accepted = false;
      final acceptCompleter = Completer<void>();
      await credChar.setNotifyValue(true);
      credSub = credChar.onValueReceived.listen((bytes) {
        if (bytes.isNotEmpty) accepted = bytes[0] == 0x01;
        if (!acceptCompleter.isCompleted) acceptCompleter.complete();
      });

      final payload = utf8.encode(jsonEncode({'ssid': ssid, 'password': password}));
      await credChar.write(payload, withoutResponse: false)
          .timeout(const Duration(seconds: 10));

      // Wait briefly for the accepted byte (best-effort — ATT write already acked).
      await acceptCompleter.future
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      // If we never saw the notify, treat the ATT-acked write as accepted.
      if (!acceptCompleter.isCompleted) accepted = true;

      // Then wait (bounded) for the connection outcome via …000E.
      if (statusChar != null) {
        await outcomeCompleter.future.timeout(outcomeWait, onTimeout: () {});
      }

      return AnchorWifiOfferResult(
        accepted: accepted,
        connectionError: false,
        statusAfter: latestStatus,
      );
    } catch (_) {
      return AnchorWifiOfferResult.connError;
    } finally {
      try { await statusSub?.cancel(); } catch (_) {}
      try { await credSub?.cancel(); } catch (_) {}
      try { await device.disconnect(); } catch (_) {}
    }
  }

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
