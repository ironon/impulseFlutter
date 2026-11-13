// Proximity tab — the first Debug screen tab (§2A.4 / §8.13), built on the
// firmware's read-only Debug Telemetry characteristics:
//
//   Watch `…001D` (firmware §5.6): the whole enforcement decision — clock,
//   window, proximity path/verdicts/score, motion, getAway gate, phoneAway
//   timer, last WATCH_REMOVED send, and every registered anchor.
//
//   Anchor `…0020` (firmware §4.4): WiFi/clock/schedule, every guard that
//   precedes a beep, the last UDP result, and today's relevant events.
//
// The screen is read-only, so nothing here is behind BuildConfig. It also owns
// no decision logic: the checklists and the interpretation sentence come from
// `services/beep_conditions.dart` (pure, unit-tested), and the byte layouts from
// `models/debug_telemetry.dart`.
//
// Keep anchor sessions short. An anchor accepts a phone + a watch + repair
// (firmware §4.3), so this tab opens exactly one AnchorTelemetrySession at a
// time and disposes it on switch and on dispose. During enforcement the watch
// also evicts the phone link once per anchor poll (§10.1, Option A), which is
// why snapshots usually arrive per reconnect rather than as a live stream.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/bluetooth_device_model.dart';
import '../models/debug_telemetry.dart';
import '../services/anchor_telemetry_service.dart';
import '../services/beep_conditions.dart';
import '../services/bluetooth_service.dart';
import '../services/watch_service.dart';
import '../theme/app_theme.dart';

/// One row of the anchor chooser: a device record plus whether the phone can
/// connect to it directly (watch-learned anchors have no `bleRemoteId`).
class _AnchorChoice {
  final String id;
  final String name;
  final bool connectable;
  const _AnchorChoice(this.id, this.name, this.connectable);
}

class DebugProximityTab extends StatefulWidget {
  const DebugProximityTab({super.key});

  @override
  State<DebugProximityTab> createState() => _DebugProximityTabState();
}

class _DebugProximityTabState extends State<DebugProximityTab> {
  final _watch = WatchService();
  final _bt = BluetoothService();

  WatchDebugTelemetry? _telemetry;
  AnchorDebugTelemetry? _anchorTelemetry;

  String? _selectedAnchorId;
  bool _manualAnchor = false;
  AnchorTelemetrySession? _session;
  String? _sessionAnchorId;
  StreamSubscription<AnchorDebugTelemetry>? _anchorDebugSub;
  StreamSubscription<WatchDebugTelemetry>? _watchSub;
  StreamSubscription<List<fbp.ScanResult>>? _scanSub;
  Timer? _ticker;
  Timer? _scanTimer;

  Map<String, int> _phoneRssi = {};
  bool _scanning = false;
  bool _connecting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // The tab may be opened before Devices/Settings have loaded the registry.
    // initialize() only loads prefs; it changes no device behaviour.
    _bt.initialize();
    _watchSub = _watch.debugTelemetryStream.listen((t) {
      if (!mounted) return;
      setState(() {
        _telemetry = t;
        _adoptDefaultAnchor(t);
      });
    });
    // Repaint "updated N s ago" without a BLE poll.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refreshWatch();
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _anchorDebugSub?.cancel();
    _scanSub?.cancel();
    _scanTimer?.cancel();
    _ticker?.cancel();
    _session?.dispose();
    super.dispose();
  }

  // ── Data acquisition ──────────────────────────────────────────────────────

  void _adoptDefaultAnchor(WatchDebugTelemetry t) {
    // The owner's question is almost always about the window that is running:
    // default the anchor chooser (and therefore the checklists) to the active
    // event's anchor. A manual choice is never overwritten.
    if (_manualAnchor) return;
    if (t.eventAnchorId.isNotEmpty) _selectedAnchorId = t.eventAnchorId;
  }

  Future<void> _refreshWatch() async {
    final t = await _watch.readDebugTelemetry();
    if (!mounted || t == null) return;
    setState(() {
      _telemetry = t;
      _adoptDefaultAnchor(t);
    });
    await _refreshAnchor();
  }

  Future<void> _refreshAnchor() async {
    final session = _session;
    if (session == null) return;
    final t = await session.readDebugTelemetry();
    if (!mounted || t == null || _session != session) return;
    setState(() => _anchorTelemetry = t);
  }

  Future<void> _refreshAll() async {
    if (!_watch.isConnected) {
      setState(() => _message = 'Watch is not connected');
      return;
    }
    if (!_watch.hasDebugTelemetryCharacteristic) {
      setState(() => _message =
          'This firmware does not expose …001D (Debug Telemetry)');
      return;
    }
    setState(() => _message = null);
    await _refreshWatch();
  }

  Future<void> _selectAnchor(_AnchorChoice choice) async {
    setState(() {
      _selectedAnchorId = choice.id;
      _manualAnchor = true;
      _anchorTelemetry = null;
      _message = null;
    });
    await _disconnectAnchor();
    if (!choice.connectable) {
      if (mounted) {
        setState(() => _message =
            'Anchor was learned from the watch and has no BLE address — '
            'read …0020 after scanning it from the phone.');
      }
      return;
    }
    BluetoothDeviceModel? model;
    for (final a in _bt.anchors) {
      if (a.id == choice.id) model = a;
    }
    if (model?.bleRemoteId != null) await _connectAnchor(model!);
  }

  Future<void> _connectAnchor(BluetoothDeviceModel anchor) async {
    if (anchor.bleRemoteId == null) return;
    setState(() => _connecting = true);
    final session = AnchorTelemetrySession(anchor.bleRemoteId!);
    final ok = await session.connect();
    if (!mounted || _selectedAnchorId != anchor.id) {
      session.dispose();
      if (mounted) setState(() => _connecting = false);
      return;
    }
    if (!ok) {
      session.dispose();
      setState(() {
        _connecting = false;
        _message = 'Couldn\'t reach that anchor';
      });
      return;
    }
    _session = session;
    _sessionAnchorId = anchor.id;
    _anchorDebugSub = session.debugStream.listen((t) {
      if (mounted && _session == session) {
        setState(() => _anchorTelemetry = t);
      }
    });
    // connect() already seeded the stream, but this listener subscribed after
    // that broadcast — read once explicitly so the card is not blank.
    final first = await session.readDebugTelemetry();
    if (!mounted || _session != session) return;
    setState(() {
      _connecting = false;
      _anchorTelemetry = first;
      if (first == null) {
        _message = 'Connected, but this anchor does not expose …0020';
      }
    });
  }

  Future<void> _disconnectAnchor() async {
    await _anchorDebugSub?.cancel();
    _anchorDebugSub = null;
    _session?.dispose();
    _session = null;
    _sessionAnchorId = null;
    if (mounted) {
      setState(() {
        _anchorTelemetry = null;
        _connecting = false;
      });
    }
  }

  Future<void> _scanFromPhone() async {
    if (_scanning) {
      await _stopScan();
      return;
    }
    setState(() {
      _scanning = true;
      _message = 'Scanning from the phone for 10 s…';
      _phoneRssi = {};
    });
    try {
      _scanSub = _bt.startScan().listen(
        (results) {
          final found = <String, int>{};
          for (final r in results) {
            // Same identity extraction the Devices tab uses: the anchor UUID
            // lives in the 0xFFFF manufacturer block, not the remoteId.
            final uuid = _bt.extractAnchorUuid(r);
            if (uuid != null) found[uuid] = r.rssi;
          }
          if (mounted) setState(() => _phoneRssi = found);
        },
        onError: (Object e) {
          if (mounted) setState(() => _message = 'Scan failed: $e');
        },
      );
      _scanTimer = Timer(const Duration(seconds: 10), () {
        _stopScan();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _message = 'Scan failed: $e';
        });
      }
    }
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _bt.stopScan();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _scanning = false;
        if (_message != null && _message!.startsWith('Scanning')) {
          _message = _phoneRssi.isEmpty
              ? 'Phone scan finished — no anchor advertisements seen'
              : 'Phone scan finished';
        }
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = _telemetry;
    final selected = _selectedAnchorId ?? w?.eventAnchorId;
    final report = evaluateBeepConditions(
      watch: w,
      anchor: _anchorTelemetry,
      anchorId: (selected?.isEmpty ?? true) ? null : selected,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(w),
        const SizedBox(height: 12),
        _clockAndWindow(w),
        const SizedBox(height: 12),
        _decision(w),
        const SizedBox(height: 12),
        _anchors(w),
        const SizedBox(height: 12),
        _anchorTelemetryCard(),
        const SizedBox(height: 12),
        _conditions(report),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(WatchDebugTelemetry? w) {
    final connected = _watch.isConnected;
    return _card('Debug telemetry', [
      _row('watch', connected ? 'connected' : 'not connected'),
      _row('…001D present',
          _watch.hasDebugTelemetryCharacteristic ? 'yes' : 'no'),
      _row('snapshot', _snapshotAge(w)),
      const SizedBox(height: 8),
      Row(
        children: [
          OutlinedButton.icon(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
          ),
          const SizedBox(width: 8),
          if (_message != null)
            Expanded(
              child: Text(_message!,
                  style:
                      const TextStyle(color: Colors.amber, fontSize: 11)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'During enforcement the watch drops the phone link for each anchor '
        'poll, so expect roughly one snapshot per reconnect — not a live '
        'stream. Notify is only a change hint; this screen reads the full '
        'payload.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
      ),
    ]);
  }

  // ── Clock & window ────────────────────────────────────────────────────────

  Widget _clockAndWindow(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Clock & window', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    final local = w.watchLocalTime;
    return _card('Clock & window', [
      _row('watch local time',
          local == null ? 'unknown' : _fmtTime(local),
          valueColor: w.timeValid ? null : Colors.redAccent),
      _row('time valid', w.timeValid ? 'yes' : 'no'),
      _row('activity', w.activityState.label),
      _row('window',
          w.criteria == null
              ? 'none'
              : '${w.criteria!.label} ${_fmtMinute(w.startMin)}–'
                  '${_fmtMinute(w.endMin)}'),
      _row('profile', w.profileLabel),
      _row('grace',
          w.graceActive ? 'active · ${w.graceRemainingS}s left' : 'inactive'),
      _row('poll interval', '${w.pollIntervalS}s'),
      _row('since last poll', _fmtAge(w.sinceLastPollS)),
      _row('last poll met',
          w.lastPollMet == 0xFF
              ? 'never polled'
              : (w.lastPollMet == 0 ? 'no (enforcing)' : 'yes (compliant)')),
      _row('v0 stub', w.v0Stub ? 'YES — verdicts forced' : 'no',
          valueColor: w.v0Stub ? Colors.redAccent : null),
    ]);
  }

  // ── Proximity decision ────────────────────────────────────────────────────

  Widget _decision(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Proximity decision', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    return _card('Proximity decision', [
      _row('path', w.proxPath.label),
      _row('since query', _fmtAge(w.sinceLastQueryS)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _verdictPill('v0.8', w.verdictV08, false),
          _verdictPill('v2', w.verdictV2, false),
          _verdictPill('final', w.verdictFinal, true),
          if (w.proxV2Authoritative)
            const _Pill('HMM authoritative', AppTheme.textGrey),
        ],
      ),
      const SizedBox(height: 6),
      _row('verdict source',
          w.proxV2Authoritative
              ? 'HMM (v2); the NEAR floor may promote a confident v0.8 NEAR'
              : 'v0.8 threshold'),
      const SizedBox(height: 10),
      _scoreBar(w),
      _row('threshold source',
          w.nearThrSource == 1 ? 'anchor-calibrated' : 'global default'),
      _row('emit',
          w.emitQ8 == 0
              ? '0 (dead zone)'
              : (w.emitQ8 / 256).toStringAsFixed(2)),
      _row('HMM λ / p_near',
          '${(w.lambdaQ8 / 256).toStringAsFixed(2)} / '
          '${(w.pNearU8 / 255 * 100).toStringAsFixed(0)}%'),
      _row('motion', w.motionState.label),
      _row('PDR',
          w.pdrAbstained
              ? 'abstained'
              : 'rate ${w.pdrRateU8}, ${w.pdrCovered} slots, '
                  'llr ${w.pdrLlr}'),
      _row('dock read', _dockLabel(w.dock)),
      _row('removed send',
          '${w.removedResult.label} · ${_fmtAge(w.sinceRemovedS)}'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.backgroundGrey,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          buildProximityInterpretation(w),
          style: const TextStyle(color: AppTheme.textWhite, fontSize: 12),
        ),
      ),
    ]);
  }

  Widget _scoreBar(WatchDebugTelemetry w) {
    final scoreFraction = (w.score / 255).clamp(0.0, 1.0);
    final thresholdFraction = (w.nearThr / 255).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('score ${w.score}',
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontSize: 12)),
              const Spacer(),
              Text('threshold ${w.nearThr}',
                  style: const TextStyle(
                      color: AppTheme.textGrey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, c) {
            final width = c.maxWidth;
            return SizedBox(
              height: 14,
              width: width,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 2,
                    height: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 2,
                    height: 10,
                    width: width * scoreFraction,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.lightOrange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (width * thresholdFraction - 1).clamp(0.0, width),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppTheme.textWhite),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Anchors as seen by the watch ──────────────────────────────────────────

  Widget _anchors(WatchDebugTelemetry? w) {
    final records = w?.anchors ?? const <WatchAnchorRecord>[];
    return _card('Anchors (watch scan)', [
      Row(
        children: [
          const Text('Phone distance',
              style: TextStyle(color: AppTheme.textWhite, fontSize: 12)),
          const Spacer(),
          OutlinedButton(
            onPressed: _scanFromPhone,
            child: Text(_scanning ? 'Scanning…' : 'Scan from phone (10 s)'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'The watch\'s RSSI is an input to the engine, not a distance. The '
        'phone scan shows what this phone hears from the same beacon.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
      ),
      const SizedBox(height: 8),
      if (records.isEmpty)
        const Text('No anchor records in this snapshot.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12))
      else
        for (final r in records) _anchorRecordCard(r),
    ]);
  }

  Widget _anchorRecordCard(WatchAnchorRecord r) {
    final phone = _phoneRssi[r.uuid];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_anchorName(r.uuid),
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _row('uuid', _short(r.uuid)),
          _row('watch RSSI',
              '${r.rssi} dBm · ${_fmtAge(r.sinceSeenS)}'
              '${r.rssiFresh ? ' · fresh' : ' · stale'}'),
          _row('last score', r.lastScore.toString()),
          _row('flags', _recordFlags(r)),
          _row('phone RSSI',
              phone == null ? 'not scanned yet' : '$phone dBm (this phone)',
              valueColor: phone == null ? AppTheme.textGrey : null),
        ],
      ),
    );
  }

  // ── Anchor 0020 card ──────────────────────────────────────────────────────

  Widget _anchorTelemetryCard() {
    final choices = _anchorChoices();
    final a = _anchorTelemetry;
    return _card('Anchor telemetry (…0020)', [
      const Text(
        'Pick an anchor to open one short read-only session. Anchors hold few '
        'connections — disconnect by picking another or leaving this tab.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
      ),
      const SizedBox(height: 8),
      if (choices.isEmpty)
        const Text('No anchors known yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in choices)
              ChoiceChip(
                label: Text(c.name),
                selected: _selectedAnchorId == c.id,
                selectedColor: AppTheme.lightOrange,
                labelStyle: TextStyle(
                  color: _selectedAnchorId == c.id
                      ? AppTheme.darkGrey
                      : AppTheme.textWhite,
                  fontSize: 12,
                ),
                onSelected: (sel) {
                  if (sel) _selectAnchor(c);
                },
              ),
          ],
        ),
      const SizedBox(height: 8),
      if (_connecting)
        const Center(
            child: CircularProgressIndicator(color: AppTheme.lightOrange)),
      if (a == null)
        const Text('No anchor snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12))
      else ...[
        if (_sessionAnchorId != null && _sessionAnchorId != _selectedAnchorId)
          const Text(
            'The open session is for a different anchor than the checklist '
            'selection.',
            style: TextStyle(color: Colors.amber, fontSize: 11),
          ),
        _row('wifi / IP',
            a.wifiConnected
                ? 'connected · ${a.ip ?? 'no IP'}'
                : 'not connected · ${a.ip ?? 'no IP'}'),
        _row('clock',
            a.timeValid
                ? '${_fmtMinute(a.localMinute)} local · '
                    'utc ${a.utcNow} · tz ${a.tzOffsetMin}m'
                : 'invalid — SNTP has not set it',
            valueColor: a.timeValid ? null : Colors.redAccent),
        _row('clock skew', _skewText(a)),
        _row('schedule',
            a.scheduleLoaded
                ? 'loaded · ${a.todayEventCount} event(s) today'
                : 'NOT loaded'),
        _row('beeping',
            a.beeping
                ? '${a.dockAlarm ? 'dock alarm' : 'watch-removed alarm'} · '
                    '${a.beepingForS}s of ${a.maxBeepMinutes * 60}s cap · '
                    'profile ${a.beepProfileLabel} · phase '
                    '${a.beepPhaseOn ? 'on' : 'off'}'
                : 'no'),
        _row('dock',
            'docked=${a.docked} · phone link '
                '${a.dockPhoneConnected ? 'registered' : 'none'} · '
                'seen this window=${a.dockSeenThisWindow}'),
        _row('dock RSSI',
            '${a.dockLastRssi} dBm vs threshold ${a.dockRssiThr} dBm · '
            'undock ${a.undockStreak}/${a.undockConfirm}'),
        _row('adv undocked', a.advUndocked ? 'flag set' : 'clear'),
        _row('last UDP',
            '${a.lastUdpCmdLabel} · ${_fmtAge(a.sinceLastUdpS)} → '
            '${a.lastUdpResult.label}'),
        _row('last UDP event', _shortOrNone(a.lastUdpEventId)),
        _row('alarm event', _shortOrNone(a.alarmEventId)),
        const SizedBox(height: 6),
        const Text('Relevant events (this anchor, today)',
            style: TextStyle(color: AppTheme.textWhite, fontSize: 12)),
        if (a.relevantEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('none',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          )
        else
          for (final e in a.relevantEvents)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_short(e.eventId)} · ${e.criteria?.label ?? '?'} '
                '${_fmtMinute(e.startMin)}–${_fmtMinute(e.endMin)}'
                '${e.negatedToday ? ' · negated' : ''}'
                '${e.inBeepList ? ' · beep list' : ''}'
                '${e.isDockEvent ? ' · dock event' : ''}'
                '${e.hasAnchorProfile ? ' · profile' : ' · NO profile'}'
                '${e.windowOpenNow ? ' · OPEN now' : ''}',
                style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ),
      ],
    ]);
  }

  // ── Beep checklists ───────────────────────────────────────────────────────

  Widget _conditions(BeepReport report) {
    return _card('Beep conditions', [
      const Text(
        'All three outputs, with every guard the firmware evaluates. '
        '✓ met · ✗ not met · ? unknown.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
      ),
      if (report.warning != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            report.warning!,
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
        ),
      ],
      for (final g in report.groups) ...[
        const SizedBox(height: 12),
        _groupVerdict(g),
        const SizedBox(height: 4),
        for (final c in g.conditions) _conditionRow(c),
      ],
    ]);
  }

  Widget _groupVerdict(BeepConditionGroup g) {
    final color = g.state == ConditionState.met
        ? Colors.lightGreen
        : g.state == ConditionState.unmet
            ? Colors.redAccent
            : AppTheme.textGrey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(g.title,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
        Text(g.verdict,
            style: TextStyle(
                color: color, fontSize: 12, fontFamily: 'monospace')),
        Text(g.subtitle,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 11)),
      ],
    );
  }

  Widget _conditionRow(BeepCondition c) {
    // Informational rows are outcomes or advisories (see
    // BeepCondition.informational): amber/grey, never red, and labelled so
    // they don't read as the guard that is blocking.
    final color = c.informational
        ? (c.state == ConditionState.unmet ? Colors.amber : AppTheme.textGrey)
        : c.state == ConditionState.met
            ? Colors.lightGreen
            : c.state == ConditionState.unmet
                ? Colors.redAccent
                : AppTheme.textGrey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(c.state.symbol,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.informational ? '${c.label}  (status)' : c.label,
                    style: TextStyle(
                        color: color, fontSize: 12, fontFamily: 'monospace')),
                Text(c.detail,
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────────

  List<_AnchorChoice> _anchorChoices() {
    final out = <_AnchorChoice>[];
    final seen = <String>{};
    for (final a in _bt.anchors) {
      if (seen.add(a.id)) {
        out.add(_AnchorChoice(a.id, a.name, a.bleRemoteId != null));
      }
    }
    for (final r in _telemetry?.anchors ?? const <WatchAnchorRecord>[]) {
      if (seen.add(r.uuid)) {
        out.add(_AnchorChoice(r.uuid, _short(r.uuid), false));
      }
    }
    return out;
  }

  String _anchorName(String uuid) {
    for (final d in _bt.deviceHistory) {
      if (d.id == uuid) return d.name;
    }
    return _short(uuid);
  }

  String _recordFlags(WatchAnchorRecord r) {
    final flags = [
      if (r.isEventAnchor) 'event anchor',
      if (r.inBeepList) 'beep list',
      if (r.bleMacValid) 'MAC known',
      if (r.ipKnown) 'IP known',
    ];
    return flags.isEmpty ? 'none' : flags.join(' · ');
  }

  String _skewText(AnchorDebugTelemetry a) {
    final w = _telemetry;
    if (w == null) return 'watch snapshot unavailable';
    if (!w.timeValid) return 'watch clock invalid';
    if (!a.timeValid || a.localMinute == 0xFFFF) return 'anchor clock invalid';
    final diff = (w.localMinute - a.localMinute).abs() % 1440;
    final skew = diff > 720 ? 1440 - diff : diff;
    return 'watch ${_fmtMinute(w.localMinute)} vs anchor '
        '${_fmtMinute(a.localMinute)} · '
        '${skew == 0 ? 'in sync' : '$skew min apart'}'
        '${skew > 1 ? ' — warn' : ''}';
  }

  String _snapshotAge(WatchDebugTelemetry? w) {
    final at = w?.receivedAt;
    if (at == null) return 'not read yet';
    final seconds = DateTime.now().difference(at).inSeconds;
    return 'updated ${seconds < 0 ? 0 : seconds} s ago';
  }

  String _fmtMinute(int m) {
    if (m == 0xFFFF) return 'never';
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String _fmtAge(int seconds) =>
      seconds == 0xFFFF ? 'never' : '${seconds}s ago';

  String _short(String uuid) =>
      uuid.length <= 8 ? uuid : uuid.substring(0, 8);

  String _shortOrNone(String uuid) => uuid.isEmpty ? 'none' : _short(uuid);

  String _dockLabel(int dock) {
    switch (dock) {
      case 0: return 'undocked';
      case 1: return 'docked';
      default: return 'unknown';
    }
  }

  Widget _verdictPill(String title, ProxVerdict v, bool highlight) {
    final color = v == ProxVerdict.near
        ? Colors.lightGreen
        : v == ProxVerdict.away
            ? AppTheme.lightOrange
            : AppTheme.textGrey;
    return _Pill('$title ${v.label}', color, bold: highlight);
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(k,
                  style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      color: valueColor ?? AppTheme.textWhite,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}

/// A small coloured label used for the three verdicts.
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  const _Pill(this.text, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
