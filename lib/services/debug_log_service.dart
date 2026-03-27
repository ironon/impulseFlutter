import 'dart:async';

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
