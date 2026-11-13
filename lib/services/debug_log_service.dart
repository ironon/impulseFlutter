// In-memory BLE packet log for the Debug screen (spec v2 §8.13).
//
// A process-wide singleton ring buffer: 300 entries, oldest dropped first. Every
// decode site (watch status / seen anchors / calibration / prox score / dock
// status / anchor HTTP / mDNS / manual writes) calls log() with a human summary and
// the raw bytes, so the Log tab is a complete record of what arrived.
//
// Deliberately memory-only: nothing is written to disk, so a release build cannot
// leak packet contents and the log vanishes with the process. `clear()` empties the
// list but does not emit an event — listeners repaint on the next entry.

import 'dart:async';

/// One formatted packet: when it arrived, which subsystem produced it, the decoded
/// one-liner, and the raw bytes as uppercase hex. `source` values in use: `status`,
/// `seen_anchors`, `calib`, `prox_score`, `dock_status`, `dock`, `anchor_http`,
/// `mdns`, `manual_write` (plus `status (read)` / `seen_anchors (read)` variants).
class DebugLogEntry {
  final DateTime timestamp;
  final String source;   // e.g. 'status', 'seen_anchors', 'anchor_ip'
  final String decoded;  // human-readable interpretation
  final String hex;      // raw bytes as hex string

  DebugLogEntry({
    required this.timestamp,
    required this.source,
    required this.decoded,
    required this.hex,
  });
}

/// Process-wide packet log for the Debug screen.
///
/// Not a service with lifecycle: `log()` is fire-and-forget from any decode site, the
/// buffer is capped at 300 entries, and listeners get the entry on a broadcast stream.
/// There is deliberately no persistence (see the file header).
class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  static const int _maxEntries = 300;

  final List<DebugLogEntry> entries = [];
  final _controller = StreamController<DebugLogEntry>.broadcast();

  Stream<DebugLogEntry> get stream => _controller.stream;

  void log(String source, String decoded, List<int> rawBytes) {
    final hex = rawBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    final entry = DebugLogEntry(
      timestamp: DateTime.now(),
      source:    source,
      decoded:   decoded,
      hex:       hex,
    );

    entries.add(entry);
    if (entries.length > _maxEntries) entries.removeAt(0);
    _controller.add(entry);
  }

  void clear() => entries.clear();
}
