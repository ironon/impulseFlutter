import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../models/bluetooth_device_model.dart';
import '../services/bluetooth_service.dart';
import '../services/watch_service.dart';
import '../services/automation_service.dart';
import '../theme/app_theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _btService    = BluetoothService();
  final _watchService = WatchService();
  final _autoService  = AutomationService();

  bool _isScanning    = false;
  bool _isPushing     = false;
  String? _statusMsg;

  WatchStatus? _watchStatus;
  StreamSubscription<WatchStatus>?        _statusSub;
  StreamSubscription<List<SeenAnchorInfo>>? _seenAnchorsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _btService.initialize();
    await _autoService.initialize();
    _statusSub = _watchService.statusStream.listen((s) {
      if (mounted) setState(() => _watchStatus = s);
    });
    _seenAnchorsSub = _watchService.seenAnchorsStream.listen((anchors) {
      for (final a in anchors) {
        _btService.addOrUpdateDevice(BluetoothDeviceModel(
          id:         a.uuid,
          name:       'Anchor',
          isConnected: false,
          rssi:       a.rssi,
          lastSeen:   a.lastSeen,
          deviceType: DeviceType.anchor,
        ));
      }
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _seenAnchorsSub?.cancel();
    super.dispose();
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  void _startScan() {
    setState(() { _isScanning = true; _statusMsg = null; });

    _btService.startScan().listen(
      (results) {
        for (final r in results) {
          final type = _btService.classifyDevice(r);
          // For anchors, use the UUID from iBeacon data as the device ID
          final id = (type == DeviceType.anchor)
              ? (_btService.extractAnchorUuid(r) ??
                 r.device.remoteId.toString())
              : r.device.remoteId.toString();

          final device = BluetoothDeviceModel(
            id:          id,
            name:        r.device.platformName.isNotEmpty
                           ? r.device.platformName
                           : (type == DeviceType.anchor ? 'Anchor' : 'Impulse Watch'),
            isConnected: false,
            rssi:        r.rssi,
            lastSeen:    DateTime.now(),
            deviceType:  type,
          );
          _btService.addOrUpdateDevice(device);
        }
        if (mounted) setState(() {});
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
      onError: (e) {
        if (mounted) {
          setState(() { _isScanning = false; _statusMsg = 'Scan error: $e'; });
        }
      },
    );

    Future.delayed(const Duration(seconds: 15), () {
      _btService.stopScan();
      if (mounted) setState(() => _isScanning = false);
    });
  }

  // ── Watch connection ──────────────────────────────────────────────────────

  Future<void> _connectWatch(BluetoothDeviceModel model) async {
    setState(() { _statusMsg = 'Connecting…'; });
    try {
      // Find the actual fbp.BluetoothDevice from scan results
      final fbpDevices = fbp.FlutterBluePlus.connectedDevices;
      fbp.BluetoothDevice? fbpDevice = fbpDevices
          .where((d) => d.remoteId.toString() == model.id)
          .firstOrNull;

      fbpDevice ??= fbp.BluetoothDevice.fromId(model.id);

      await _watchService.connect(fbpDevice);
      await _btService.updateDeviceStatus(model.id, true, model.rssi);

      setState(() { _statusMsg = 'Connected to ${model.name}'; });
    } catch (e) {
      setState(() { _statusMsg = 'Connection failed: $e'; });
    }
  }

  Future<void> _disconnectWatch() async {
    await _watchService.disconnect();
    setState(() { _statusMsg = 'Disconnected'; _watchStatus = null; });
  }

  // ── Schedule push ─────────────────────────────────────────────────────────

  Future<void> _pushSchedule() async {
    if (!_watchService.isConnected) {
      setState(() => _statusMsg = 'Not connected to watch');
      return;
    }
    setState(() { _isPushing = true; _statusMsg = 'Pushing schedule…'; });
    try {
      final ok = await _watchService.pushSchedule(_autoService.automations);
      setState(() {
        _isPushing = false;
        _statusMsg = ok ? 'Schedule pushed ✓' : 'Schedule push failed';
      });
    } catch (e) {
      setState(() { _isPushing = false; _statusMsg = 'Error: $e'; });
    }
  }

  // ── Anchor identify ───────────────────────────────────────────────────────

  Future<void> _identifyAnchor(BluetoothDeviceModel anchor) async {
    setState(() => _statusMsg = 'Connecting to anchor…');
    try {
      final fbpDevice = fbp.BluetoothDevice.fromId(anchor.id);
      await fbpDevice.connect(timeout: const Duration(seconds: 8));
      final services = await fbpDevice.discoverServices();
      for (final svc in services) {
        if (svc.serviceUuid.str.toLowerCase() == '4a0f0001-f8ce-11ee-8001-020304050607') {
          final idChar = svc.characteristics.firstWhere(
            (c) => c.characteristicUuid.str.toLowerCase() ==
                   '4a0f0002-f8ce-11ee-8001-020304050607',
          );
          await idChar.write([0x01], withoutResponse: true);
          break;
        }
      }
      await fbpDevice.disconnect();
      setState(() => _statusMsg = 'Anchor should beep now');
    } catch (e) {
      setState(() => _statusMsg = 'Identify failed: $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final watches = _btService.watches;
    final anchors = _btService.anchors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          if (_isPushing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.upload_rounded),
              tooltip: 'Push schedule to watch',
              onPressed: _watchService.isConnected ? _pushSchedule : null,
            ),
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status banner
          if (_statusMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMsg!,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: 13),
              ),
            ),

          // ── Watch section ──────────────────────────────────────────────
          _sectionHeader('Watch'),
          const SizedBox(height: 8),
          if (watches.isEmpty)
            _emptyCard('No watch found — tap refresh to scan')
          else
            ...watches.map((w) => _watchCard(w)),

          const SizedBox(height: 24),

          // ── Anchors section ────────────────────────────────────────────
          _sectionHeader('Anchors'),
          const SizedBox(height: 8),
          if (anchors.isEmpty)
            _emptyCard('No anchors found')
          else
            ...anchors.map((a) => _anchorCard(a)),
        ],
      ),
    );
  }

  // ── Sub-widgets ───────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Text(
        title,
        style: const TextStyle(
          color: AppTheme.textGrey,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      );

  Widget _emptyCard(String msg) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(msg,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 14)),
        ),
      );

  Widget _watchCard(BluetoothDeviceModel watch) {
    final connected = _watchService.isConnected;
    final status    = _watchStatus;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: connected
                        ? AppTheme.lightOrange.withValues(alpha: 0.2)
                        : AppTheme.darkGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.watch,
                      color: connected ? AppTheme.lightOrange : AppTheme.textGrey,
                      size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(watch.name,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: connected ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          connected ? 'Connected' : 'Not connected',
                          style: TextStyle(
                            color: connected ? Colors.green : AppTheme.textGrey,
                            fontSize: 13,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                connected
                    ? TextButton(
                        onPressed: _disconnectWatch,
                        child: const Text('Disconnect',
                            style: TextStyle(color: AppTheme.textGrey)),
                      )
                    : ElevatedButton(
                        onPressed: () => _connectWatch(watch),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.lightOrange,
                          foregroundColor: AppTheme.darkGrey,
                        ),
                        child: const Text('Connect'),
                      ),
              ],
            ),

            // Watch status panel (when connected)
            if (connected && status != null) ...[
              const Divider(height: 24, color: AppTheme.cardGrey),
              _statusRow('State',   status.activityLabel),
              _statusRow('WiFi',    status.wifiConnected ? 'Connected' : 'Disconnected'),
              _statusRow('Worn',    status.worn ? 'Yes' : 'No'),
              if (status.batteryPct != 0xFF)
                _statusRow('Battery', '${status.batteryPct}%'),
              if (status.activeEventId != null)
                _statusRow('Event', '${status.activeEventId!.substring(0, 8)}…'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Push Schedule Now'),
                  onPressed: _isPushing ? null : _pushSchedule,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.lightOrange,
                    foregroundColor: AppTheme.darkGrey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _anchorCard(BluetoothDeviceModel anchor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: AppTheme.darkGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.router, color: AppTheme.textGrey, size: 28),
        ),
        title: Text(anchor.name,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${anchor.id.substring(0, 8)}…',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
            Text(
              'RSSI: ${anchor.rssi} dBm  ·  '
              '${_btService.getSignalStrength(anchor.rssi)}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
            if (anchor.ipAddress != null)
              Text('IP: ${anchor.ipAddress}',
                  style: const TextStyle(color: AppTheme.textGrey, fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.notifications_active_outlined,
              color: AppTheme.lightOrange),
          tooltip: 'Identify (beep)',
          onPressed: () => _identifyAnchor(anchor),
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
            Text(value,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
          ],
        ),
      );
}
