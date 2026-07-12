import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_model.dart';
import '../models/bluetooth_device_model.dart';
import '../services/automation_service.dart';
import '../services/bluetooth_service.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/policy_verdict.dart';

/// Day-first Home dashboard (§8.7): today's timeline of commitments with the
/// active one highlighted (alarming vs. on-track from `condition_met`), then
/// watch vitals, unreachable-anchor notices, and anchor reachability (§8.12).
/// The shape of the day comes first; device telemetry is secondary.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _btService = BluetoothService();
  final _autoService = AutomationService();

  List<SeenAnchorInfo> _seenAnchors = const [];
  StreamSubscription<List<SeenAnchorInfo>>? _seenSub;

  @override
  void initState() {
    super.initState();
    _seenSub = WatchService().seenAnchorsStream.listen((anchors) {
      if (mounted) setState(() => _seenAnchors = anchors);
    });
  }

  @override
  void dispose() {
    _seenSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = app.status;
    final now = DateTime.now();
    final today = _autoService
        .getAutomationsForDate(now)
        .where((a) => !a.negate)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final pendingIds = app.pendingEventIds;

    return Scaffold(
      appBar: AppBar(title: const Text('Today')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Active-commitment banner ──
          _activeBanner(app, status, today, now),
          const SizedBox(height: 16),

          // ── Today's timeline ──
          const Text('The shape of the day',
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (today.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing scheduled today. A quiet day — or an empty one. '
                'Your call.',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
              ),
            )
          else
            for (final a in today)
              _timelineTile(app, status, a, now, pendingIds),
          const SizedBox(height: 20),

          // ── Watch vitals ──
          const Text('Watch',
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _watchCard(app, status),
          const SizedBox(height: 20),

          // ── Unreachable-anchor notices (§8.7) ──
          if (status != null && status.unreachableAnchors.isNotEmpty) ...[
            for (final u in status.unreachableAnchors)
              Card(
                color: Colors.amber.withValues(alpha: 0.12),
                child: ListTile(
                  leading:
                      const Icon(Icons.wifi_tethering_off, color: Colors.amber),
                  title: Text(
                    'Couldn\'t reach ${u.name.isEmpty ? 'an anchor' : u.name}',
                    style: const TextStyle(
                        color: AppTheme.textWhite, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Check it\'s powered and online.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],

          // ── Anchors (§8.12 seen-anchor reachability) ──
          const Text('Anchors',
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_btService.anchors.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No anchors paired yet — set them up from Devices.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
            )
          else
            for (final anchor in _btService.anchors) _anchorTile(anchor),
        ],
      ),
    );
  }

  // ── Active banner ──────────────────────────────────────────────────────────

  Widget _activeBanner(AppState app, WatchStatus? status,
      List<Automation> today, DateTime now) {
    final active = _activeCommitment(app, status, today, now);
    if (active == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.spa_outlined,
                  color: AppTheme.lightOrange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  today.isEmpty
                      ? 'Nothing on the line right now.'
                      : 'Between commitments — the next one is set.',
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Alarming vs in-window-compliant, from the condition_met byte (v0.6).
    final alarming = status?.isAlarming == true;
    return Card(
      color: alarming
          ? Colors.redAccent.withValues(alpha: 0.15)
          : Colors.green.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              alarming ? Icons.notifications_active : Icons.check_circle,
              color: alarming ? Colors.redAccent : Colors.lightGreen,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarming
                        ? 'The watch is holding the line'
                        : 'In a commitment — on track',
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_describe(active)} · until ${_fmtTime(active.endTime)}'
                    '${alarming ? ' — past-you set this' : ''}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The commitment to feature: the watch's active_event_id when known,
  /// otherwise whichever of today's windows contains now.
  Automation? _activeCommitment(AppState app, WatchStatus? status,
      List<Automation> today, DateTime now) {
    if (status?.activeEventId != null) {
      final match =
          app.schedule.where((a) => a.id == status!.activeEventId).firstOrNull;
      if (match != null) return match;
    }
    final mins = now.hour * 60 + now.minute;
    return today
        .where((a) => mins >= a.startMinutes && mins < a.endMinutes)
        .firstOrNull;
  }

  // ── Timeline tile ─────────────────────────────────────────────────────────

  Widget _timelineTile(AppState app, WatchStatus? status, Automation a,
      DateTime now, Set<String> pendingIds) {
    final mins = now.hour * 60 + now.minute;
    final isActive = mins >= a.startMinutes && mins < a.endMinutes;
    final isPast = mins >= a.endMinutes;
    final isWatchActive = status?.activeEventId == a.id;
    final alarming = isWatchActive && status?.conditionMet == false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              _fmtTime(a.startTime),
              style: TextStyle(
                color: isActive ? AppTheme.lightOrange : AppTheme.textGrey,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Container(
            width: 4,
            height: 44,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: isPast
                  ? AppTheme.cardGrey
                  : (alarming
                      ? Colors.redAccent
                      : (isActive ? AppTheme.lightOrange : a.color)),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: isPast ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _describe(a),
                          style: TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: 14,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pendingIds.contains(a.id)) ...[
                        const SizedBox(width: 6),
                        const PendingBadge(compact: true),
                      ],
                    ],
                  ),
                  Text(
                    '${_fmtTime(a.startTime)}–${_fmtTime(a.endTime)}'
                    '${isActive ? (alarming ? ' · holding the line' : ' · now') : ''}',
                    style: TextStyle(
                      color: alarming ? Colors.redAccent : AppTheme.textGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Watch vitals card ─────────────────────────────────────────────────────

  Widget _watchCard(AppState app, WatchStatus? status) {
    if (!app.watchConnected || status == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.watch_off, color: AppTheme.textGrey),
          title: Text('Watch not connected',
              style: TextStyle(color: AppTheme.textWhite, fontSize: 14)),
          subtitle: Text('Connect from the Devices tab.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _vital(
              icon: status.worn ? Icons.watch : Icons.watch_off,
              label: status.worn ? 'Worn' : 'Off wrist',
              highlight: status.worn,
            ),
            _vital(
              icon: Icons.bolt,
              label: status.activityLabel,
              highlight: status.activityState == 1,
            ),
            _vital(
              icon: _batteryIcon(status.batteryPct),
              label: status.batteryPct == 0xFF
                  ? 'Battery —'
                  : '${status.batteryPct}%',
              highlight: false,
            ),
            _vital(
              icon: status.wifiConnected ? Icons.wifi : Icons.wifi_off,
              label: status.wifiConnected ? 'WiFi' : 'No WiFi',
              highlight: status.wifiConnected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vital(
      {required IconData icon,
      required String label,
      required bool highlight}) {
    return Column(
      children: [
        Icon(icon,
            color: highlight ? AppTheme.lightOrange : AppTheme.textGrey,
            size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
      ],
    );
  }

  IconData _batteryIcon(int pct) {
    if (pct == 0xFF) return Icons.battery_unknown;
    if (pct >= 80) return Icons.battery_full;
    if (pct >= 50) return Icons.battery_5_bar;
    if (pct >= 20) return Icons.battery_3_bar;
    return Icons.battery_alert;
  }

  // ── Anchor tile (§8.12) ───────────────────────────────────────────────────

  Widget _anchorTile(BluetoothDeviceModel anchor) {
    final seen = _seenAnchors.where((s) => s.uuid == anchor.id).firstOrNull;
    final watchSees = seen != null &&
        DateTime.now().difference(seen.lastSeen) < const Duration(minutes: 5);
    final phoneSawRecently =
        DateTime.now().difference(anchor.lastSeen) < const Duration(minutes: 5);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.sensors,
          color: watchSees || phoneSawRecently
              ? AppTheme.lightOrange
              : AppTheme.textGrey,
        ),
        title: Text(
          anchor.role == null ? anchor.name : '${anchor.name} (${anchor.role})',
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 14),
        ),
        subtitle: Text(
          watchSees
              ? 'The watch can see this anchor'
              : (phoneSawRecently
                  ? 'Nearby — seen by this phone'
                  : 'Not seen recently'),
          style: TextStyle(
            color: watchSees ? Colors.lightGreen : AppTheme.textGrey,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _describe(Automation a) {
    final origin = a.origin;
    if (origin != TemplateOrigin.manual) {
      switch (origin) {
        case TemplateOrigin.sunriseLock:
          return 'Sunrise Lock';
        case TemplateOrigin.studyTime:
          return 'Study Time';
        case TemplateOrigin.gymTime:
          return 'Gym Time';
        case TemplateOrigin.phoneFree:
          return 'Phone-Free Block';
        case TemplateOrigin.manual:
          break;
      }
    }
    return a.criteria.label;
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }
}
