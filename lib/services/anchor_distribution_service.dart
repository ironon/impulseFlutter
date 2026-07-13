import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_model.dart';
import '../utils/schedule_encoder.dart';
import 'bluetooth_service.dart';
import 'debug_log_service.dart';

/// Anchor schedule distribution over WiFi/HTTP + mDNS IP discovery
/// (§7.3/§8.4). Anchors need the schedule only to decide beep-on-removal
/// windows; the push is fire-and-forget to ALL known IPs unconditionally —
/// an offline anchor simply misses it and catches the next one.
///
/// There is deliberately NO midnight push: a phone can't reliably run at
/// midnight. The anchor persists the blob and recomputes each day locally
/// (firmware §4.7); the app re-pushes on schedule changes, on newly learned
/// IPs, and opportunistically on foreground when the last success is stale.
class AnchorDistributionService {
  static final AnchorDistributionService _instance =
      AnchorDistributionService._internal();
  factory AnchorDistributionService() => _instance;
  AnchorDistributionService._internal();

  static const staleness = Duration(hours: 12);
  static const _prefsKey = 'anchor_last_push_v1';

  final BluetoothService _btService = BluetoothService();

  Map<String, DateTime>? _lastSuccess; // anchor uuid -> last successful push

  Future<Map<String, DateTime>> _loadLastSuccess() async {
    if (_lastSuccess != null) return _lastSuccess!;
    final prefs = await SharedPreferences.getInstance();
    final map = <String, DateTime>{};
    for (final entry in prefs.getStringList(_prefsKey) ?? const <String>[]) {
      final i = entry.indexOf('=');
      if (i <= 0) continue;
      final ts = DateTime.tryParse(entry.substring(i + 1));
      if (ts != null) map[entry.substring(0, i)] = ts;
    }
    return _lastSuccess = map;
  }

  Future<void> _saveLastSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _lastSuccess!.entries
          .map((e) => '${e.key}=${e.value.toIso8601String()}')
          .toList(),
    );
  }

  // ── HTTP push (§7.3) ──────────────────────────────────────────────────────

  /// POST the full blob + 4-byte CRC to one anchor. Returns success.
  Future<bool> pushToAnchor(String ip, List<Automation> events) async {
    try {
      final body = ScheduleEncoder.encodeWithCrc(events);
      final resp = await http
          .post(
            Uri.parse('http://$ip/schedule'),
            headers: {'Content-Type': 'application/octet-stream'},
            body: body,
          )
          .timeout(const Duration(seconds: 6));
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      DebugLogService().log('anchor_http',
          'POST /schedule to $ip -> ${resp.statusCode}', const []);
      return ok;
    } catch (e) {
      DebugLogService()
          .log('anchor_http', 'POST /schedule to $ip failed: $e', const []);
      return false;
    }
  }

  /// Push to every known anchor IP unconditionally (fire-and-forget: failures
  /// are logged, never surfaced as blocking errors).
  Future<void> pushToAllAnchors(List<Automation> events) async {
    final last = await _loadLastSuccess();
    final targets = _btService.anchors
        .where((a) => a.ipAddress != null)
        .toList(growable: false);
    if (targets.isEmpty) return;
    await Future.wait(targets.map((a) async {
      if (await pushToAnchor(a.ipAddress!, events)) {
        last[a.id] = DateTime.now();
      }
    }));
    await _saveLastSuccess();
  }

  /// Foreground staleness push (§7.3): only anchors whose last successful
  /// push is older than [staleness].
  Future<void> pushStale(List<Automation> events) async {
    final last = await _loadLastSuccess();
    final now = DateTime.now();
    final stale = _btService.anchors
        .where((a) =>
            a.ipAddress != null &&
            now.difference(last[a.id] ?? DateTime(2000)) > staleness)
        .toList(growable: false);
    if (stale.isEmpty) return;
    await Future.wait(stale.map((a) async {
      if (await pushToAnchor(a.ipAddress!, events)) {
        last[a.id] = now;
      }
    }));
    await _saveLastSuccess();
  }

  // ── mDNS IP discovery (§5/§8.4) ───────────────────────────────────────────

  /// Resolve `<anchor-uuid>.local` for every known anchor and record fresh
  /// IPs. Returns the uuids whose IP changed (new IP learned ⇒ push trigger).
  Future<List<String>> refreshAnchorIps() async {
    final changed = <String>[];
    final anchors = _btService.anchors;
    if (anchors.isEmpty) return changed;

    final client = MDnsClient();
    try {
      await client.start();
      for (final a in anchors) {
        try {
          final query =
              ResourceRecordQuery.addressIPv4('${a.id}.local');
          await for (final rec
              in client.lookup<IPAddressResourceRecord>(query).timeout(
                    const Duration(seconds: 3),
                  )) {
            final ip = rec.address.address;
            if (ip != a.ipAddress) {
              await _btService.updateAnchorIp(a.id, ip);
              changed.add(a.id);
              DebugLogService()
                  .log('mdns', '${a.name}: ${a.id}.local -> $ip', const []);
            }
            break; // first answer is enough
          }
        } catch (_) {
          // Timeout / no answer: the anchor is off-LAN right now. Best-effort.
        }
      }
    } catch (e) {
      // mDNS unavailable (permissions / platform): degrade silently — manual
      // IPs from Settings still work.
      DebugLogService().log('mdns', 'unavailable: $e', const []);
    } finally {
      client.stop();
    }
    return changed;
  }
}
