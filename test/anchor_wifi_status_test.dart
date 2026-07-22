import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:impulse_app/services/anchor_service.dart';

/// Builds a WiFi Status `…000E` payload exactly as the anchor firmware emits it
/// (firmware §4.4): [state][ssid_len][ssid][ipv4 net-order][rssi+128][slots][crc LE].
List<int> _payload({
  required int state,
  required String ssid,
  List<int>? ipv4,
  int? rssiWire,
  int slotsUsed = 0,
  int? scheduleCrc,
}) {
  final b = <int>[];
  b.add(state);
  final ssidBytes = utf8.encode(ssid);
  b.add(ssidBytes.length);
  b.addAll(ssidBytes);
  b.addAll(ipv4 ?? [0, 0, 0, 0]);
  b.add(rssiWire ?? 0);
  b.add(slotsUsed);
  if (scheduleCrc != null) {
    final d = ByteData(4)..setUint32(0, scheduleCrc, Endian.little);
    b.addAll(d.buffer.asUint8List());
  }
  return b;
}

void main() {
  group('AnchorWifiStatus.fromBytes', () {
    test('connected: parses ssid, ipv4, rssi, slots, crc', () {
      final bytes = _payload(
        state: 2,
        ssid: 'HomeNet',
        ipv4: [192, 168, 1, 42],
        rssiWire: 128 - 55, // -55 dBm encoded as rssi+128
        slotsUsed: 3,
        scheduleCrc: 0xDEADBEEF,
      );
      final s = AnchorWifiStatus.fromBytes(bytes)!;
      expect(s.state, AnchorWifiState.connected);
      expect(s.ssid, 'HomeNet');
      expect(s.ipv4, '192.168.1.42');
      expect(s.rssi, -55);
      expect(s.slotsUsed, 3);
      expect(s.scheduleCrc, 0xDEADBEEF);
      expect(s.state.isDistress, isFalse);
    });

    test('never provisioned: empty ssid, no ip, distress', () {
      final s = AnchorWifiStatus.fromBytes(
          _payload(state: 0, ssid: '', scheduleCrc: 0))!;
      expect(s.state, AnchorWifiState.neverProvisioned);
      expect(s.ssid, isEmpty);
      expect(s.ipv4, isNull);
      expect(s.rssi, isNull);
      expect(s.scheduleCrc, 0);
      expect(s.state.isDistress, isTrue);
    });

    test('auth failed and AP-not-found are distress', () {
      final auth = AnchorWifiStatus.fromBytes(
          _payload(state: 3, ssid: 'HomeNet', slotsUsed: 1, scheduleCrc: 0))!;
      final noap = AnchorWifiStatus.fromBytes(
          _payload(state: 4, ssid: 'HomeNet', slotsUsed: 1, scheduleCrc: 0))!;
      expect(auth.state, AnchorWifiState.authFailed);
      expect(auth.state.isDistress, isTrue);
      expect(noap.state, AnchorWifiState.apNotFound);
      expect(noap.state.isDistress, isTrue);
      // Not connected → no ip / rssi even though a slot is occupied.
      expect(auth.ipv4, isNull);
      expect(auth.rssi, isNull);
    });

    test('truncated payload without crc still parses core fields', () {
      final bytes = _payload(
        state: 2,
        ssid: 'X',
        ipv4: [10, 0, 0, 1],
        rssiWire: 128 - 60,
        slotsUsed: 2,
        // no scheduleCrc
      );
      final s = AnchorWifiStatus.fromBytes(bytes)!;
      expect(s.ipv4, '10.0.0.1');
      expect(s.slotsUsed, 2);
      expect(s.scheduleCrc, isNull);
    });

    test('too-short payload returns null', () {
      expect(AnchorWifiStatus.fromBytes([0x02]), isNull);
    });
  });
}
