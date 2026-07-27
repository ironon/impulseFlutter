import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// App-side record of which anchors have a calibration-v2 per-anchor near-zone
/// threshold, and what it is. The authoritative copy lives on each anchor (in
/// its fingerprint NVS blob); this local cache lets the Devices screen show
/// "calibrated ✓ (threshold N)" vs "not calibrated" without connecting, and is
/// updated whenever a guided calibration FINALIZEs.
///
/// Kept in `shared_preferences` (a simple per-anchor record), keyed by the
/// anchor's 16-byte UUID string.
class CalibrationStore {
  static const _key = 'anchor_calibration_v1';

  final Map<String, CalibrationRecord> _entries = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _entries.clear();
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    decoded.forEach((uuid, v) {
      _entries[uuid.toLowerCase()] =
          CalibrationRecord.fromJson(v as Map<String, dynamic>);
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// The calibration record for [anchorUuid], or null if never calibrated.
  CalibrationRecord? recordFor(String anchorUuid) =>
      _entries[anchorUuid.toLowerCase()];

  /// Record a completed FINALIZE for [anchorUuid].
  Future<void> record(String anchorUuid,
      {required int nearThreshold,
      required int insideN,
      required int edgeN,
      required int confidence,
      DateTime? at}) async {
    _entries[anchorUuid.toLowerCase()] = CalibrationRecord(
      nearThreshold: nearThreshold,
      insideN: insideN,
      edgeN: edgeN,
      confidence: confidence,
      calibratedAt: at ?? DateTime.now(),
    );
    await _save();
  }

  Future<void> remove(String anchorUuid) async {
    _entries.remove(anchorUuid.toLowerCase());
    await _save();
  }
}

/// One anchor's persisted calibration outcome.
class CalibrationRecord {
  final int nearThreshold; // 0..255 score-space cutoff (0 = fell back to global)
  final int insideN;
  final int edgeN;
  final int confidence; // 0 = low/overlap … 255 = clean separation
  final DateTime calibratedAt;

  const CalibrationRecord({
    required this.nearThreshold,
    required this.insideN,
    required this.edgeN,
    required this.confidence,
    required this.calibratedAt,
  });

  /// True when the demonstration cleanly separated inside from edge.
  bool get isConfident => confidence > 0;

  Map<String, dynamic> toJson() => {
        'nearThreshold': nearThreshold,
        'insideN': insideN,
        'edgeN': edgeN,
        'confidence': confidence,
        'calibratedAt': calibratedAt.toIso8601String(),
      };

  factory CalibrationRecord.fromJson(Map<String, dynamic> json) =>
      CalibrationRecord(
        nearThreshold: json['nearThreshold'] as int? ?? 0,
        insideN: json['insideN'] as int? ?? 0,
        edgeN: json['edgeN'] as int? ?? 0,
        confidence: json['confidence'] as int? ?? 0,
        calibratedAt: DateTime.tryParse(json['calibratedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
