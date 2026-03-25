import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/automation_model.dart';

/// Encodes a list of [Automation] events into the binary wire format defined
/// in firmware_spec.md §6.2, and appends a CRC-32 checksum.
///
/// The returned [Uint8List] is suitable for:
///   - HTTP POST body to an anchor's /schedule endpoint (full blob + CRC).
///   - The DATA phase of the BLE schedule transfer (pass [blobOnly] = true to
///     omit the CRC; pass the CRC separately in the END packet).
class ScheduleEncoder {
  // ── CRC-32 (ISO 3309 / zlib polynomial 0xEDB88320) ─────────────────────

  static int crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if (crc & 1 != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  // ── UUID string → 16 raw bytes ──────────────────────────────────────────

  static Uint8List uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Generates a random UUID v4 string.
  static String generateUuid() {
    final rng = Random.secure();
    final b = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    String hex(List<int> s) =>
        s.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(b.sublist(0, 4))}-${hex(b.sublist(4, 6))}'
        '-${hex(b.sublist(6, 8))}-${hex(b.sublist(8, 10))}'
        '-${hex(b.sublist(10, 16))}';
  }

  // ── Binary encoder ──────────────────────────────────────────────────────

  /// Returns the raw schedule blob WITHOUT the trailing CRC.
  static Uint8List encodeBlob(List<Automation> events) {
    final buf = BytesBuilder(copy: false);

    // Event count (uint16 LE)
    _writeUint16(buf, events.length);

    for (final e in events) {
      // UUID (16 bytes)
      buf.add(uuidToBytes(e.id));

      // referenceDate as Unix timestamp seconds (int64 LE)
      final ts = e.referenceDate.millisecondsSinceEpoch ~/ 1000;
      _writeInt64(buf, ts);

      // startTime / endTime (uint16 LE, minutes since midnight)
      _writeUint16(buf, e.startMinutes);
      _writeUint16(buf, e.endMinutes);

      // recurrenceType, dayOfWeek, dayOfMonth (1 byte each)
      buf.addByte(e.recurrenceType.index);
      buf.addByte(e.dayOfWeek ?? 0);
      buf.addByte(e.dayOfMonth ?? 0);

      // criteria, enforcementProfile (1 byte each)
      buf.addByte(e.criteria.index);
      buf.addByte(e.profile.index);

      // anchorProfile (0xFF if null)
      buf.addByte(e.anchorProfile?.index ?? 0xFF);

      // negate (1 byte)
      buf.addByte(e.negate ? 1 : 0);

      // anchorId presence flag + 16 bytes
      final hasAnchor = e.anchorId != null ? 1 : 0;
      buf.addByte(hasAnchor);
      buf.add(hasAnchor == 1 ? uuidToBytes(e.anchorId!) : Uint8List(16));

      // wifiSSID length + bytes
      if (e.wifiSSID != null && e.wifiSSID!.isNotEmpty) {
        final ssidBytes = utf8.encode(e.wifiSSID!);
        buf.addByte(ssidBytes.length);
        buf.add(ssidBytes);
      } else {
        buf.addByte(0);
      }

      // beepAnchors count + UUIDs
      buf.addByte(e.beepAnchors.length);
      for (final uuid in e.beepAnchors) {
        buf.add(uuidToBytes(uuid));
      }
    }

    return buf.toBytes();
  }

  /// Returns the blob with the 4-byte CRC appended (for HTTP anchor endpoint).
  static Uint8List encodeWithCrc(List<Automation> events) {
    final blob = encodeBlob(events);
    final crc  = crc32(blob);
    final out  = Uint8List(blob.length + 4);
    out.setRange(0, blob.length, blob);
    out.buffer.asByteData().setUint32(blob.length, crc, Endian.little);
    return out;
  }

  // ── Little-endian write helpers ─────────────────────────────────────────

  static void _writeUint16(BytesBuilder b, int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  static void _writeInt64(BytesBuilder b, int v) {
    for (int i = 0; i < 8; i++) {
      b.addByte(v & 0xFF);
      v >>= 8;
    }
  }
}
