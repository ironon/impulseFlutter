// Proximity tab — the first Debug screen tab (§2A.4 / §8.13), built on the nRF
// firmware's read-only Debug Telemetry v2 characteristics:
//
//   Watch `…001D` (contract §4.1/§4.2): clock, window and criterion, the
//   enforcement decision (`last_decision`), the channel-sounding link and its
//   identity verdict, thresholds, worn detector, radio/escalation, integrity,
//   and one record per anchor the event names.
//
//   Anchor `…0020` (contract §4.3/§4.4): clock and its provenance, schedule,
//   alarm state and cap, the last WATCH_REMOVED/WATCH_WORN command with the
//   fine-grained reason, radio state, dock support, and today's events.
//
// The screen is read-only, so nothing here is behind BuildConfig. It also owns
// no decision logic: the checklists and the interpretation sentence come from
// `services/beep_conditions.dart` (pure, unit-tested), and the byte layouts from
// `models/debug_telemetry.dart`.
//
// CONNECTION BEHAVIOUR DIFFERS FROM THE ESP32 BUILD. The nRF watch does NOT
// evict the phone once per anchor poll: the app link is its own peripheral
// connection and the ranging link is a second, central connection to the anchor
// (CONFIG_BT_MAX_CONN=2). The only thing that drops the phone is a WiFi
// escalation, which takes BLE off the air entirely (`impulse_ble_quiesce`).
// So snapshots arrive as notifications while a window is running; when the
// link goes, the reason byte in the CS link panel says why.
//
// Keep anchor sessions short. The anchor holds two links (app and ranging
// watch), so this tab opens exactly one AnchorTelemetrySession at a time and
// disposes it on switch and on dispose.

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

  /// Arrival time of each snapshot. The decoders are pure and never stamp a
  /// clock (the same bytes can be decoded by a test); "how old is this?" is a
  /// property of the read, so it lives here.
  DateTime? _telemetryAt;
  DateTime? _anchorTelemetryAt;

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
        _telemetryAt = DateTime.now();
        _adoptDefaultAnchor(t);
      });
    });
    // Repaint "updated N s ago" and the live age counters without a BLE poll.
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
      _telemetryAt = DateTime.now();
      _adoptDefaultAnchor(t);
    });
    await _refreshAnchor();
  }

  Future<void> _refreshAnchor() async {
    final session = _session;
    if (session == null) return;
    final t = await session.readDebugTelemetry();
    if (!mounted || t == null || _session != session) return;
    setState(() {
      _anchorTelemetry = t;
      _anchorTelemetryAt = DateTime.now();
    });
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
      _anchorTelemetryAt = null;
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
        setState(() {
          _anchorTelemetry = t;
          _anchorTelemetryAt = DateTime.now();
        });
      }
    });
    // connect() already seeded the stream, but this listener subscribed after
    // that broadcast — read once explicitly so the card is not blank.
    final first = await session.readDebugTelemetry();
    if (!mounted || _session != session) return;
    setState(() {
      _connecting = false;
      _anchorTelemetry = first;
      _anchorTelemetryAt = first == null ? null : DateTime.now();
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
        _anchorTelemetryAt = null;
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
        _decision(w),
        const SizedBox(height: 12),
        _anchors(w),
        const SizedBox(height: 12),
        _csLink(w),
        const SizedBox(height: 12),
        _thresholds(w),
        const SizedBox(height: 12),
        _worn(w),
        const SizedBox(height: 12),
        _radioAndEscalation(w),
        const SizedBox(height: 12),
        _clocks(w),
        const SizedBox(height: 12),
        _integrity(w),
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
    return _card('Debug telemetry v2', [
      _row('watch', connected ? 'connected' : 'not connected'),
      _row('…001D present',
          _watch.hasDebugTelemetryCharacteristic ? 'yes' : 'no'),
      _row('snapshot', _snapshotAge(_telemetryAt)),
      _row('snapshot seq', w == null ? '—' : '${w.snapshotSeq}',
          valueColor: AppTheme.textGrey),
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
        'Notify is an 8-byte change hint, never the payload; every hint '
        'triggers one full read. Unlike the ESP32 build, the nRF watch keeps '
        'this link while it ranges (ranging is a second connection to the '
        'anchor), so snapshots stream. The link only goes when BLE is '
        'quiesced for a WiFi escalation — the CS link panel shows the reason.',
        style: TextStyle(color: AppTheme.textGrey, fontSize: 11),
      ),
    ]);
  }

  // ── The decision and its plain-English reading ────────────────────────────

  Widget _decision(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Decision', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    final decision = w.lastDecision;
    return _card('Decision', [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Pill(
            w.criteria?.label ?? 'NO WINDOW',
            w.criteria == null ? AppTheme.textGrey : AppTheme.lightOrange,
            bold: true,
          ),
          _Pill(
            w.conditionMet ? 'MET (silent)' : 'NOT MET',
            w.conditionMet ? Colors.lightGreen : Colors.redAccent,
            bold: true,
          ),
          if (w.failsafe) _Pill('FAIL-SAFE', Colors.amber, bold: true),
          if (w.verdictFromLostLink)
            const _Pill('LOST-LINK AWAY', Colors.amber),
          if (w.outputSilenced) const _Pill('SILENCED', Colors.amber),
          if (w.identityConflict)
            const _Pill('IDENTITY CONFLICT', Colors.redAccent, bold: true),
        ],
      ),
      const SizedBox(height: 8),
      _row('last decision', decision?.label ?? 'never evaluated'),
      _row('last poll met', w.lastPollMet?.label ?? 'never polled'),
      _row('since last poll', _fmtAge(w.sinceLastPollS)),
      _row('since last burst', _fmtAge(w.sinceLastBurstS)),
      _row('poll cadence', '${w.pollIntervalS}s'),
      _row('event index', w.eventIndex?.toString() ?? 'none'),
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

  // ── Anchors as seen by the watch ──────────────────────────────────────────

  Widget _anchors(WatchDebugTelemetry? w) {
    final records = w?.anchors ?? const <WatchAnchorRecord>[];
    return _card('Anchors (channel sounding)', [
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
        'The watch ranges one anchor at a time with Bluetooth Channel '
        'Sounding; distance is centimetres, not RSSI. Records the schedule '
        'names but the watch has not ranged carry NOT_RANGED — that is '
        'honest, not a decode failure. The phone scan is independent and shows '
        'what this phone hears from the same beacon.',
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
    final phone = _phoneRssi[r.anchorUuid];
    final meters = r.distanceM;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _anchorName(r.anchorUuid),
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _Pill(
                r.verdict.label,
                r.verdict == ProxVerdict.near
                    ? Colors.lightGreen
                    : r.verdict == ProxVerdict.away
                        ? AppTheme.lightOrange
                        : AppTheme.textGrey,
                bold: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          _row('distance',
              meters == null ? 'not ranged' : '${meters.toStringAsFixed(2)} m',
              valueColor: meters == null ? AppTheme.textGrey : null),
          _row('ifft (primary)',
              _cm(r.ifftCm)),
          _row('phase slope', _cm(r.phaseSlopeCm)),
          _row('CS-RTT', _cm(r.rttCm)),
          _row('samples', '${r.sampleCount}'),
          _row('age', _fmtAge(r.ageS)),
          _row('abstain reason',
              r.abstainReason?.label ?? (r.ranged ? '—' : 'not ranged'),
              valueColor: r.abstainReason == null ? AppTheme.textGrey : null),
          _row('flags', _recordFlags(r)),
          _row('quality',
              r.quality == null ? 'unknown' : '${r.quality}'),
          _row('uuid', _short(r.anchorUuid)),
          _row('phone RSSI',
              phone == null ? 'not scanned yet' : '$phone dBm (this phone)',
              valueColor: phone == null ? AppTheme.textGrey : null),
        ],
      ),
    );
  }

  // ── CS link and identity ──────────────────────────────────────────────────

  Widget _csLink(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Channel-sounding link', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    final identity = w.identityConflict || w.linkPeerKind == LinkPeerKind.otherAnchor
        ? 'CONFLICT — ranging a different anchor than the event names'
        : w.linkPeerKind == LinkPeerKind.eventAnchor
            ? 'matches the event\'s anchor'
            : 'identity unknown (the watch cannot tell which anchor it ranges)';
    return _card('Channel-sounding link', [
      _row('link up', _yesNo(w.linkUp)),
      _row('link ready', _yesNo(w.linkReady),
          valueColor: w.linkReady ? null : Colors.amber),
      _row('ranging on', _yesNo(w.rangingOn)),
      const SizedBox(height: 4),
      _row('peer address', w.linkPeerAddr ?? 'unknown'),
      _row('peer addr type', w.linkPeerAddrType?.label ?? 'unknown'),
      _row('peer uuid', _shortOrNone(w.linkPeerUuid)),
      _row('event anchor', _shortOrNone(w.eventAnchorId)),
      _row('identity', identity,
          valueColor: w.identityConflict
              ? Colors.redAccent
              : (w.linkPeerKind == LinkPeerKind.eventAnchor
                  ? Colors.lightGreen
                  : Colors.amber)),
      _row('attempts / failures',
          '${w.linkConnectAttempts} / ${w.linkConnectFailures}'),
      _row('connected',
          w.linkConnectedAtMs == null
              ? 'never'
              : '${_uptimeAge(w, w.linkConnectedAtMs!)} ago'),
      _row('last disconnect',
          w.linkLastDisconnectReason == null
              ? 'never'
              : 'HCI 0x${w.linkLastDisconnectReason!.toRadixString(16).padLeft(2, '0')}'),
      _row('last measure result',
          w.proxLastResult?.label ?? 'never'),
      _row('abstain reason', w.csAbstainReason?.label ?? 'unknown'),
      _row('quality',
          w.csLastQuality == null ? 'unknown' : '${w.csLastQuality}'),
    ]);
  }

  // ── Thresholds ────────────────────────────────────────────────────────────

  Widget _thresholds(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Thresholds', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    return _card('Thresholds in force', [
      _row('near', _metres(w.nearEnterCm)),
      _row('away', _metres(w.awayEnterCm)),
      _row('near run', '${w.nearRun} consecutive burst(s)'),
      _row('away run', '${w.awayRun} consecutive burst(s)'),
      _row('abstain run', '${w.abstainRun} (fail-safe above 5)'),
      const SizedBox(height: 4),
      _row('last burst', _cm(w.csDistanceCm)),
      _row('last ifft', _cm(w.csIfftCm)),
      _row('last phase slope', _cm(w.csPhaseSlopeCm)),
      _row('last RTT', _cm(w.csRttCm)),
      _row('burst samples', '${w.csBurstCount}'),
      _row('rejected',
          'range ${w.csRejectedRange} · quality ${w.csRejectedQuality} · '
              'relay ${w.csSuspectRelay} · no-ifft ${w.csMissingIfft}'),
    ]);
  }

  // ── Worn detector ─────────────────────────────────────────────────────────

  Widget _worn(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Worn detector', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    final still = w.stillForS;
    final stillThreshold = w.stillThresholdS;
    final motionThreshold = w.motionThresholdMms2;
    return _card('Worn detector', [
      _row('worn', w.worn ? 'yes (on the wrist)' : 'NO (removed)',
          valueColor: w.worn ? Colors.lightGreen : Colors.amber),
      _row('source', w.wornSource.label),
      _row('diagnostic',
          w.wornDiag == null
              ? 'unavailable'
              : '${w.wornDiag} '
                  '${w.wornSource == WornSource.imu ? 'mmi-m/s²' : 'mV'}'
                  '${motionThreshold == null ? '' : ' vs $motionThreshold mmi-m/s² threshold'}'),
      _row('still for',
          still == null
              ? 'not applicable (IR build)'
              : '${still}s'
                  '${stillThreshold == null ? '' : ' of $stillThreshold s threshold'}'),
      _row('outputs shaking',
          w.motorOn || w.buzzerOn
              ? 'yes — the IMU is measuring the watch, not the wrist'
              : 'no'),
      _row('still clock frozen',
          w.motorOn || w.buzzerOn
              ? 'alarming: the detector masks its own vibration'
              : 'no (the stillness clock is running)'),
    ]);
  }

  // ── Radio and escalation ──────────────────────────────────────────────────

  Widget _radioAndEscalation(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Radio & escalation', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    return _card('Radio & escalation', [
      _row('radio phase', w.radioPhase.label),
      _row('phase since',
          w.radioPhaseSinceMs == null
              ? 'never'
              : '${_uptimeAge(w, w.radioPhaseSinceMs!)} ago'),
      _row('WiFi dwell left', '${w.radioPhaseDwellRemainingS}s'),
      _row('BLE quiesced', _yesNo(w.bleQuiesced)),
      _row('WiFi on air', _yesNo(w.wifiOnAir)),
      _row('WiFi connected', _yesNo(w.wifiConnected)),
      _row('WiFi provisioned', _yesNo(w.wifiProvisioned)),
      _row('own IPv4', w.ownIpv4 ?? 'none'),
      const SizedBox(height: 4),
      _row('pending cmd',
          '${w.escPendingCmd.label}'
              '${w.escSinceRequestS == null ? '' : ' · ${w.escSinceRequestS}s'}'),
      _row('last delivered', w.escLastDeliveredCmd.label),
      _row('delivered BLE / UDP',
          '${w.escDeliveredBle} / ${w.escDeliveredUdp}'),
      _row('WiFi entries / attempts',
          '${w.escWifiEntries} / ${w.escAttempts}'),
      _row('last ACK', w.escLastAckResult?.label ?? 'none'),
      _row('refused', _yesNo(w.ackRefused),
          valueColor: w.ackRefused ? Colors.amber : null),
      _row('gave up', _yesNo(w.escGaveUp),
          valueColor: w.escGaveUp ? Colors.amber : null),
    ]);
  }

  // ── Clocks, side by side ──────────────────────────────────────────────────

  Widget _clocks(WatchDebugTelemetry? w) {
    final a = _anchorTelemetry;
    final watchTime = w?.watchLocalTime;
    final anchorTime = a?.anchorLocalTime;
    return _card('Clocks', [
      _row('watch local',
          watchTime == null ? 'invalid' : _fmtTime(watchTime),
          valueColor: (w?.timeValid ?? false) ? null : Colors.redAccent),
      _row('watch utc', w?.utcNow?.toString() ?? 'unknown'),
      _row('watch tz', w == null ? '—' : '${w.tzOffsetMin} min'),
      _row('watch minute',
          w?.localMinute == null ? 'invalid' : _fmtMinute(w!.localMinute)),
      _row('watch source',
          w?.clockSource?.label ??
              'not reported (the watch did not fill clock_source)',
          valueColor: w?.clockSource == ClockSource.never
              ? Colors.redAccent
              : AppTheme.textGrey),
      const SizedBox(height: 6),
      _row('anchor local',
          anchorTime == null ? 'invalid' : _fmtTime(anchorTime),
          valueColor: (a?.timeValid ?? false) ? null : Colors.redAccent),
      _row('anchor utc', a?.utcNow?.toString() ?? 'unknown'),
      _row('anchor tz', a == null ? '—' : '${a.tzOffsetMin} min'),
      _row('anchor minute',
          a?.localMinute == null ? 'invalid' : _fmtMinute(a!.localMinute)),
      _row('anchor source', a?.clockSourceLabel ?? 'not read'),
      const SizedBox(height: 4),
      _row('skew', _skewText(w, a),
          valueColor: _skewSeverity(w, a) ? Colors.amber : null),
    ]);
  }

  // ── Integrity ─────────────────────────────────────────────────────────────

  Widget _integrity(WatchDebugTelemetry? w) {
    if (w == null) {
      return _card('Integrity', [
        const Text('No watch snapshot yet.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
      ]);
    }
    return _card('Integrity', [
      _row('quarantined loosenings', '${w.integrityPendingCount}'),
      _row('settle window', '${w.integritySettleWindowMin} min'),
      _row('pass allowance', '${w.passAllowance}'),
      _row('passes left', '${w.passRemaining}'),
    ]);
  }

  // ── Anchor 0020 card ──────────────────────────────────────────────────────

  Widget _anchorTelemetryCard() {
    final choices = _anchorChoices();
    final a = _anchorTelemetry;
    return _card('Anchor telemetry (…0020)', [
      const Text(
        'Pick an anchor to open one short read-only session. An anchor holds '
        'two links (this phone and the ranging watch), so disconnect by '
        'picking another or leaving this tab.',
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
        _row('snapshot', _snapshotAge(_anchorTelemetryAt)),
        _row('clock',
            a.timeValid
                ? '${_fmtMinute(a.localMinute)} local · utc ${a.utcNow} · '
                    'tz ${a.tzOffsetMin}m · ${a.clockSourceLabel}'
                : 'invalid — nothing has set it since boot',
            valueColor: a.timeValid ? null : Colors.redAccent),
        _row('schedule',
            a.scheduleLoaded
                ? '${a.scheduleEventCount} stored · ${a.todayEventCount} today'
                : 'NOT loaded'),
        _row('schedule CRC',
            a.scheduleCrc == null
                ? 'none'
                : '0x${a.scheduleCrc!.toRadixString(16)}'),
        _row('active event',
            a.activeEventId.isEmpty
                ? 'none'
                : '${_short(a.activeEventId)} · '
                    '${a.activeEventCriteria?.label ?? '?'} '
                    '${_fmtMinute(a.activeEventStartMin)}–'
                    '${_fmtMinute(a.activeEventEndMin)} · index '
                    '${a.activeEventIndex ?? '—'}'),
        _row('beeping',
            a.beeping
                ? '${a.beepingForS}s · profile ${a.beepProfileLabel} · phase '
                    '${a.beepPhaseOn ? 'on' : 'off'} · '
                    '${a.beepCapRemainingS}s of cap left'
                : 'no',
            valueColor: a.beepCapExpired ? Colors.amber : null),
        _row('alarm event', _shortOrNone(a.alarmEventId)),
        _row('buzzer',
            a.buzzerCompiledOut ? 'COMPILED OUT' : 'compiled in',
            valueColor: a.buzzerCompiledOut ? Colors.amber : null),
        _row('last command',
            '${a.lastCmd.label} · ${_fmtAge(a.sinceLastCmdS)} · '
            '${a.lastCmdTransport?.label ?? 'none'}'),
        _row('last result',
            '${a.lastCmdResult?.label ?? 'none'} · '
            '${a.lastCmdReason?.label ?? 'no reason'}'
            '${a.ackSent ? ' · ACK sent' : (a.lastCmdTransport == AnchorCmdTransport.udp ? ' · no ACK' : '')}'),
        _row('last cmd event', _shortOrNone(a.lastCmdEventId)),
        _row('last cmd src', a.lastCmdSrcIp ?? 'none'),
        _row('rejections',
            'unknown ${a.rejectUnknownEvent} · window '
            '${a.rejectOutsideWindow} · negated ${a.rejectNegated} · '
            'not-in-list ${a.rejectNotInBeepList} · malformed '
            '${a.rejectMalformed} · accepted ${a.acceptedApplied}'),
        _row('cap stops', '${a.capStops}'),
        const SizedBox(height: 4),
        _row('radio', '${a.radioPhase.label} · '
            '${a.wifiDwellRemainingS}s dwell left'),
        _row('WiFi', a.wifiConnected ? 'connected' : 'not connected'),
        _row('BLE', a.bleQuiesced
            ? 'quiesced (WiFi has the air)'
            : '${a.bleAdvertising ? 'advertising' : 'not advertising'} · '
                '${a.peerLinkCount} peer link(s)'),
        _row('WiFi fallback', a.wifiFallbackArmed ? 'armed' : 'not armed'),
        _row('own last IP', a.ownLastIp ?? 'none'),
        const SizedBox(height: 4),
        _row('CS reflector',
            a.csReflectorState?.label ?? 'not built'),
        _row('CS procedures', _yesNo(a.csProceduresActive)),
        _row('dock support',
            a.dockSupported
                ? 'supported (dock_state ${a.dockState?.label ?? '?'})'
                : 'NOT SUPPORTED by this firmware',
            valueColor: a.dockSupported ? null : Colors.amber),
        _row('servo',
            a.servoState?.label ?? 'unavailable',
            valueColor: AppTheme.textGrey),
        _row('identify', a.identifyActive != 0 ? 'active' : 'idle'),
        _row('boot count', '${a.bootCount}'),
        const SizedBox(height: 6),
        const Text('Relevant events (this anchor, today)',
            style: TextStyle(color: AppTheme.textWhite, fontSize: 12)),
        if (a.events.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('none',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          )
        else
          for (final e in a.events)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_short(e.eventId)} · ${e.criteria?.label ?? '?'} '
                '${_fmtMinute(e.startMin)}–${_fmtMinute(e.endMin)}'
                '${e.negatedToday ? ' · negated' : ''}'
                '${e.inBeepList ? ' · beep list' : ''}'
                '${e.isDockEvent ? ' · dock event' : ''}'
                '${e.isAnchorIdTarget ? ' · names this anchor' : ''}'
                '${e.hasAnchorProfile ? ' · profile' : ' · NO profile'}'
                '${e.clockInvalid ? ' · CLOCK INVALID' : ''}'
                '${e.windowOpenNow ? ' · OPEN now' : ''}'
                '${e.activeAlarmEvent ? ' · alarming' : ''}',
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
        '✓ met · ✗ not met · ? unknown. Rows marked (status) are outcomes and '
        'advisories: shown, never counted as the reason.',
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
      if (seen.add(r.anchorUuid)) {
        out.add(_AnchorChoice(r.anchorUuid, _short(r.anchorUuid), false));
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
      if (r.isLinkPeer) 'link peer',
      if (r.identityConflict) 'identity conflict',
      if (r.ipKnown) 'IP known',
      if (r.ranged) 'ranged',
    ];
    return flags.isEmpty ? 'none' : flags.join(' · ');
  }

  /// Age of an `*_at_ms` uptime field, derived from the snapshot's own
  /// `uptime_ms` so a stale snapshot does not look fresh.
  String _uptimeAge(WatchDebugTelemetry w, int sinceMs) {
    final ageMs = w.uptimeMs - sinceMs;
    if (ageMs < 0) return '${(sinceMs - w.uptimeMs) ~/ 1000}s in the future';
    return '${ageMs ~/ 1000}s';
  }

  String _skewText(WatchDebugTelemetry? w, AnchorDebugTelemetry? a) {
    if (w == null) return 'watch snapshot unavailable';
    if (a == null) return 'anchor not read';
    if (!w.timeValid || w.localMinute == null) return 'watch clock invalid';
    if (!a.timeValid || a.localMinute == null) return 'anchor clock invalid';
    final diff = (w.localMinute! - a.localMinute!).abs() % 1440;
    final skew = diff > 720 ? 1440 - diff : diff;
    final hours = skew ~/ 60;
    final minutes = skew % 60;
    final apart = hours > 0 ? '$hours h $minutes min' : '$minutes min';
    return 'watch ${_fmtMinute(w.localMinute)} vs anchor '
        '${_fmtMinute(a.localMinute)} · '
        '${skew == 0 ? 'in sync' : '$apart apart'}'
        '${skew > 1 ? ' — ANCHOR CLOCK DISAGREES' : ''}';
  }

  bool _skewSeverity(WatchDebugTelemetry? w, AnchorDebugTelemetry? a) {
    if (w == null || a == null) return false;
    if (!w.timeValid || !a.timeValid) return true;
    if (w.localMinute == null || a.localMinute == null) return true;
    final diff = (w.localMinute! - a.localMinute!).abs() % 1440;
    final skew = diff > 720 ? 1440 - diff : diff;
    return skew > 1;
  }

  String _snapshotAge(DateTime? at) {
    if (at == null) return 'not read yet';
    final seconds = DateTime.now().difference(at).inSeconds;
    return 'updated ${seconds < 0 ? 0 : seconds} s ago';
  }

  String _cm(int? cm) {
    if (cm == null) return 'none';
    return '$cm cm (${(cm / 100).toStringAsFixed(2)} m)';
  }

  String _metres(int cm) =>
      '${(cm / 100).toStringAsFixed(2)} m ($cm cm)';

  String _fmtMinute(int? m) {
    if (m == null) return 'never';
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  String _fmtAge(int? seconds) =>
      seconds == null ? 'never' : '${seconds}s ago';

  String _short(String uuid) =>
      uuid.length <= 8 ? uuid : uuid.substring(0, 8);

  String _shortOrNone(String uuid) => uuid.isEmpty ? 'none' : _short(uuid);

  String _yesNo(bool v) => v ? 'yes' : 'no';

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

/// A small coloured label used for the decision and per-anchor verdicts.
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
