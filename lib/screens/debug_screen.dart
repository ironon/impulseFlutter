import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/bluetooth_device_model.dart';
import '../services/anchor_telemetry_service.dart';
import '../services/bluetooth_service.dart';
import '../services/debug_log_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/build_config.dart';

/// Advanced-mode debug menu (§2A.4 / §8.13): decoded Watch Status, live Prox
/// Score + Dock Status meters, the raw BLE log, and — in dev builds only —
/// write-capable tools (manual characteristic write, force schedule re-push,
/// fingerprint upload stub, time write). Write tools are compile-time gated
/// behind [BuildConfig.debugWriteToolsEnabled] so a release build can never
/// use them as an in-the-moment escape hatch.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Debug'),
          bottom: const TabBar(
            indicatorColor: AppTheme.lightOrange,
            labelColor: AppTheme.lightOrange,
            unselectedLabelColor: AppTheme.textGrey,
            tabs: [
              Tab(text: 'Status'),
              Tab(text: 'Meters'),
              Tab(text: 'Log'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StatusTab(),
            _MetersTab(),
            _LogTab(),
          ],
        ),
      ),
    );
  }
}

// ── Status tab: decoded Watch Status + (dev-only) write tools ────────────────

class _StatusTab extends StatelessWidget {
  const _StatusTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = app.status;
    final watch = app.watch;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Decoded Watch Status',
            style: TextStyle(
                color: AppTheme.textWhite,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: status == null
                ? const Text('No status received yet.',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('activity', status.activityLabel),
                      _row('bt / wifi',
                          '${status.btConnected} / ${status.wifiConnected}'),
                      _row('worn', '${status.worn}'),
                      _row(
                          'battery',
                          status.batteryPct == 0xFF
                              ? 'n/a'
                              : '${status.batteryPct}%'),
                      _row('active_event',
                          status.activeEventId ?? 'none'),
                      _row('condition_met',
                          status.conditionMet?.toString() ?? 'n/a (pre-v0.6)'),
                      _row('unreachable',
                          '${status.unreachableAnchors.length} queued'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Characteristic probes',
                    style:
                        TextStyle(color: AppTheme.textWhite, fontSize: 13)),
                const SizedBox(height: 6),
                _row('Time …0019',
                    watch.hasTimeCharacteristic ? 'present' : 'absent'),
                _row('Pending …001A',
                    watch.hasPendingChangesCharacteristic
                        ? 'present'
                        : 'absent'),
                _row('Passes …001B',
                    watch.hasEmergencyPassCharacteristic
                        ? 'present'
                        : 'absent'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (BuildConfig.debugWriteToolsEnabled)
          const _WriteTools()
        else
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Write tools are excluded from this build.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(k,
                  style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: 12,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}

// ── Dev-only write tools (§2A.4) ─────────────────────────────────────────────

class _WriteTools extends StatefulWidget {
  const _WriteTools();

  @override
  State<_WriteTools> createState() => _WriteToolsState();
}

class _WriteToolsState extends State<_WriteTools> {
  final _charUuidCtrl = TextEditingController();
  final _hexCtrl = TextEditingController();
  String? _msg;

  @override
  void dispose() {
    _charUuidCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Future<void> _forceRepush() async {
    final app = context.read<AppState>();
    final result = await app.pushScheduleToWatch();
    setState(() => _msg = 'Re-push: ${result?.name ?? 'watch not connected'}');
  }

  Future<void> _pushTime() async {
    final app = context.read<AppState>();
    if (!app.watch.hasTimeCharacteristic) {
      setState(() => _msg = 'Time characteristic absent on this firmware');
      return;
    }
    final resp = await app.watch
        .pushTime(DateTime.now().toUtc(), DateTime.now().timeZoneOffset.inMinutes);
    setState(() => _msg = 'Time write resp: '
        '${resp == null ? 'timeout' : '0x${resp.toRadixString(16).padLeft(2, '0')}'}'
        '${resp == 0x02 ? ' (rejected — would end the active window)' : ''}');
  }

  Future<void> _manualWrite() async {
    final app = context.read<AppState>();
    final device = app.watch.device;
    if (device == null || !device.isConnected) {
      setState(() => _msg = 'Watch not connected');
      return;
    }
    final uuid = _charUuidCtrl.text.trim().toLowerCase();
    final hex = _hexCtrl.text.replaceAll(RegExp(r'[\s,]'), '');
    if (uuid.isEmpty || hex.isEmpty || hex.length.isOdd) {
      setState(() => _msg = 'Need a characteristic UUID and even-length hex');
      return;
    }
    final bytes = <int>[];
    try {
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    } catch (_) {
      setState(() => _msg = 'Bad hex');
      return;
    }
    try {
      for (final svc in device.servicesList) {
        for (final c in svc.characteristics) {
          if (c.characteristicUuid.str.toLowerCase() == uuid) {
            await c.write(bytes,
                withoutResponse: !c.properties.write);
            DebugLogService()
                .log('manual_write', 'wrote ${bytes.length} bytes to $uuid', bytes);
            setState(() => _msg = 'Wrote ${bytes.length} bytes');
            return;
          }
        }
      }
      setState(() => _msg = 'Characteristic not found on the watch');
    } catch (e) {
      setState(() => _msg = 'Write failed: $e');
    }
  }

  void _fingerprintStub() {
    // §8.5: debug-only stub — the on-anchor self-training path is primary.
    setState(() => _msg =
        'Fingerprint upload stub: blob format is firmware §6.3.2 '
        '([count u16] then per device [mac 6][type u8][mu f32][M f32][W f32]); '
        'transfer via …000A/…000B is not implemented yet.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Write tools (dev build only)',
            style: TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_msg != null) ...[
          Text(_msg!,
              style: const TextStyle(color: Colors.amber, fontSize: 12)),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _forceRepush,
              child: const Text('Force schedule re-push'),
            ),
            OutlinedButton(
              onPressed: _pushTime,
              child: const Text('Write time now'),
            ),
            OutlinedButton(
              onPressed: _fingerprintStub,
              child: const Text('Fingerprint upload (stub)'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Manual characteristic write (watch connection)',
            style: TextStyle(color: AppTheme.textWhite, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _charUuidCtrl,
          style: const TextStyle(
              color: AppTheme.textWhite, fontSize: 12, fontFamily: 'monospace'),
          decoration: _dec('characteristic uuid (full, lowercase)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hexCtrl,
          style: const TextStyle(
              color: AppTheme.textWhite, fontSize: 12, fontFamily: 'monospace'),
          decoration: _dec('payload hex, e.g. 01a0ff'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _manualWrite,
          child: const Text('Write'),
        ),
      ],
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
        filled: true,
        fillColor: AppTheme.backgroundGrey,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}

// ── Meters tab: live Prox Score + Dock Status ────────────────────────────────

class _MetersTab extends StatefulWidget {
  const _MetersTab();

  @override
  State<_MetersTab> createState() => _MetersTabState();
}

class _MetersTabState extends State<_MetersTab> {
  final _btService = BluetoothService();
  AnchorTelemetrySession? _session;
  String? _connectedAnchorId;
  bool _connecting = false;
  ProxScoreReading? _prox;
  DockStatusReading? _dock;
  StreamSubscription? _proxSub;
  StreamSubscription? _dockSub;

  @override
  void dispose() {
    _proxSub?.cancel();
    _dockSub?.cancel();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _connect(BluetoothDeviceModel anchor) async {
    if (anchor.bleRemoteId == null) return;
    await _disconnect();
    setState(() => _connecting = true);
    final session = AnchorTelemetrySession(anchor.bleRemoteId!);
    final ok = await session.connect();
    if (!mounted) {
      session.dispose();
      return;
    }
    if (!ok) {
      setState(() {
        _connecting = false;
        _connectedAnchorId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t reach that anchor')));
      return;
    }
    _session = session;
    _proxSub = session.proxStream.listen((r) {
      if (mounted) setState(() => _prox = r);
    });
    _dockSub = session.dockStream.listen((r) {
      if (mounted) setState(() => _dock = r);
    });
    setState(() {
      _connecting = false;
      _connectedAnchorId = anchor.id;
    });
  }

  Future<void> _disconnect() async {
    await _proxSub?.cancel();
    await _dockSub?.cancel();
    _proxSub = null;
    _dockSub = null;
    _session?.dispose();
    _session = null;
    if (mounted) {
      setState(() {
        _connectedAnchorId = null;
        _prox = null;
        _dock = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchors =
        _btService.anchors.where((a) => a.bleRemoteId != null).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Connect to an anchor to watch its live proximity score and dock '
          'state. Keep sessions short — anchors hold few connections.',
          style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (anchors.isEmpty)
          const Text('No directly-scanned anchors known.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13))
        else
          Wrap(
            spacing: 8,
            children: [
              for (final a in anchors)
                ChoiceChip(
                  label: Text(a.name),
                  selected: _connectedAnchorId == a.id,
                  selectedColor: AppTheme.lightOrange,
                  labelStyle: TextStyle(
                    color: _connectedAnchorId == a.id
                        ? AppTheme.darkGrey
                        : AppTheme.textWhite,
                    fontSize: 13,
                  ),
                  onSelected: (sel) =>
                      sel ? _connect(a) : _disconnect(),
                ),
            ],
          ),
        const SizedBox(height: 16),
        if (_connecting)
          const Center(
              child: CircularProgressIndicator(color: AppTheme.lightOrange)),
        if (_prox != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Prox Score',
                      style: TextStyle(
                          color: AppTheme.textWhite, fontSize: 14)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: _prox!.score / 255,
                    minHeight: 10,
                    backgroundColor: AppTheme.backgroundGrey,
                    color: AppTheme.lightOrange,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_prox!.score} / 255'
                    '${_prox!.fingerprintActive ? ' · fingerprint active' : ''}'
                    '${_prox!.lowDeviceCount ? ' · low device count' : ''}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_dock != null)
          Card(
            child: ListTile(
              leading: Icon(
                _dock!.docked ? Icons.smartphone : Icons.phonelink_erase,
                color:
                    _dock!.docked ? Colors.lightGreen : AppTheme.textGrey,
              ),
              title: Text(_dock!.docked ? 'Phone docked' : 'Not docked',
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontSize: 14)),
              subtitle: Text('RSSI ${_dock!.rssi} dBm',
                  style: const TextStyle(
                      color: AppTheme.textGrey, fontSize: 12)),
            ),
          ),
      ],
    );
  }
}

// ── Log tab: the original raw BLE log ────────────────────────────────────────

class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  final _logService = DebugLogService();
  final _scrollCtrl = ScrollController();
  StreamSubscription<DebugLogEntry>? _sub;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _sub = _logService.stream.listen((_) {
      if (mounted) {
        setState(() {});
        if (_autoScroll) _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyAll() {
    final text = _logService.entries.map((e) {
      final t = '${e.timestamp.hour.toString().padLeft(2, '0')}:'
          '${e.timestamp.minute.toString().padLeft(2, '0')}:'
          '${e.timestamp.second.toString().padLeft(2, '0')}.'
          '${e.timestamp.millisecond.toString().padLeft(3, '0')}';
      return '[$t] [${e.source}] ${e.decoded}\n  HEX: ${e.hex}';
    }).join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _logService.entries;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text('${entries.length} packets',
                  style:
                      const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.vertical_align_bottom,
                  color:
                      _autoScroll ? AppTheme.lightOrange : AppTheme.textGrey,
                ),
                tooltip: 'Auto-scroll',
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy all',
                onPressed: entries.isEmpty ? null : _copyAll,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Clear',
                onPressed: entries.isEmpty
                    ? null
                    : () {
                        _logService.clear();
                        setState(() {});
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    'No packets yet.\nConnect to the watch to see data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(8),
                  itemCount: entries.length,
                  itemBuilder: (context, i) =>
                      _EntryTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DebugLogEntry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.timestamp;
    final timeStr = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.cardGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  color: AppTheme.textGrey,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.lightOrange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.source,
                  style: const TextStyle(
                    color: AppTheme.lightOrange,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.decoded,
            style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.hex,
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
