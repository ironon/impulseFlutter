import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/bluetooth_device_model.dart';
import '../services/anchor_service.dart';
import '../services/bluetooth_service.dart';
import '../services/watch_service.dart';
import '../state/app_state.dart';
import '../templates/template.dart';
import '../theme/app_theme.dart';
import '../utils/schedule_encoder.dart';
import '../widgets/template_form.dart';

/// Goal-first onboarding (§8.1): pair watch → pick a goal → place only the
/// anchors that goal needs → 2–3-question quick-form → armed. Success metric
/// is time-to-first-armed-commitment; skippable and re-enterable ("add
/// another goal" reopens the goal picker).
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, this.startAtGoalPicker = false});

  /// True when re-entered from Home as "add another goal" — permissions and
  /// watch pairing are already done.
  final bool startAtGoalPicker;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Step { permissions, pairWatch, pickGoal, placeAnchors, quickForm, armed }

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _btService = BluetoothService();
  final _watchService = WatchService();

  late _Step _step;
  String? _status;

  // Scan state
  bool _scanning = false;
  final List<BluetoothDeviceModel> _found = [];
  StreamSubscription<List<fbp.ScanResult>>? _scanSub;

  // Chosen goal
  Template? _goal;

  // Anchor placement
  int _roleIndex = 0;
  final Map<String, String> _roleToAnchorId = {}; // role -> anchor uuid
  final _nameCtrl = TextEditingController();
  String? _placingAnchorId; // anchor being named for the current role

  // Quick-form values
  Map<String, dynamic> _params = {};

  @override
  void initState() {
    super.initState();
    _step = widget.startAtGoalPicker ? _Step.pickGoal : _Step.permissions;
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Permissions (§8.1 item 1) ─────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    setState(() => _status = null);
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.notification,
      ].request();
    } catch (_) {
      // Desktop / platforms without the plugin: continue, BLE will surface
      // its own errors honestly.
    }
    if (mounted) setState(() => _step = _Step.pairWatch);
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  Future<void> _startScan(DeviceType wanted) async {
    setState(() {
      _scanning = true;
      _found.clear();
      _status = null;
    });
    try {
      _scanSub?.cancel();
      _scanSub = _btService.startScan().listen((results) {
        for (final r in results) {
          final type = _btService.classifyDevice(r);
          if (type != wanted) continue;
          final id = type == DeviceType.anchor
              ? (_btService.extractAnchorUuid(r) ?? r.device.remoteId.str)
              : r.device.remoteId.str;
          final model = BluetoothDeviceModel(
            id: id,
            name: r.advertisementData.advName.isEmpty
                ? (type == DeviceType.anchor ? 'Anchor' : 'Impulse Watch')
                : r.advertisementData.advName,
            isConnected: false,
            rssi: r.rssi,
            lastSeen: DateTime.now(),
            deviceType: type,
            bleRemoteId: r.device.remoteId.str,
          );
          final idx = _found.indexWhere((d) => d.id == model.id);
          if (idx >= 0) {
            _found[idx] = model;
          } else {
            _found.add(model);
          }
        }
        if (mounted) setState(() {});
      });
      // startScan has a 15 s timeout built in.
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) setState(() => _scanning = false);
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _status = 'Couldn\'t scan: $e';
      });
    }
  }

  // ── Watch pairing (§8.1 item 2) ───────────────────────────────────────────

  Future<void> _pairWatch(BluetoothDeviceModel model) async {
    setState(() => _status = 'Connecting…');
    try {
      final device = fbp.BluetoothDevice.fromId(model.bleRemoteId ?? model.id);
      await _watchService.connect(device);
      await _btService
          .addOrUpdateDevice(model.copyWith(isConnected: true));
      if (!mounted) return;
      context.read<AppState>().connectionChanged();

      // Push time + timezone right away (§8.11) — probe, degrade gracefully.
      final tzOffset = DateTime.now().timeZoneOffset.inMinutes;
      if (_watchService.hasTimeCharacteristic) {
        await _watchService.pushTime(DateTime.now().toUtc(), tzOffset);
      }
      setState(() {
        _status = null;
        _step = _Step.pickGoal;
      });
    } catch (e) {
      setState(() => _status = 'Couldn\'t connect: $e');
    }
  }

  // ── Anchor placement (§8.1 item 4) ────────────────────────────────────────

  List<AnchorRoleRequirement> get _requiredRoles =>
      _goal?.onboarder?.requiredAnchors ?? const [];

  AnchorRoleRequirement get _currentRole => _requiredRoles[_roleIndex];

  Future<void> _assignAnchor(BluetoothDeviceModel anchor) async {
    final name = _nameCtrl.text.trim();
    await _btService.addOrUpdateDevice(anchor.copyWith(
      name: name.isEmpty ? _currentRole.label : name,
      role: _currentRole.role,
    ));
    _roleToAnchorId[_currentRole.role] = anchor.id;
    _nameCtrl.clear();
    _placingAnchorId = null;
    if (_roleIndex + 1 < _requiredRoles.length) {
      setState(() => _roleIndex += 1);
    } else {
      _enterQuickForm();
    }
  }

  void _enterQuickForm() {
    // Pre-fill anchor-role params from the placement step.
    final params = Map<String, dynamic>.of(_goal!.defaultParams);
    for (final p in _goal!.params) {
      if (p.kind == ParamKind.anchorRole && p.anchorRole != null) {
        final assigned = _roleToAnchorId[p.anchorRole!] ??
            _btService.anchors
                .where((a) => a.role == p.anchorRole)
                .firstOrNull
                ?.id;
        if (assigned != null) params[p.key] = assigned;
      }
    }
    setState(() {
      _params = params;
      _step = _Step.quickForm;
    });
  }

  // ── Quick-form → armed (§8.1 items 5–6) ───────────────────────────────────

  /// Params the quick-form still needs but the user can't answer here
  /// (e.g. the gym's SSID while sitting at home).
  List<TemplateParam> get _unanswerable => _goal!.quickFormParams
      .where((p) => p.kind == ParamKind.wifiSsid && _params[p.key] == null)
      .toList();

  bool get _quickFormComplete {
    for (final p in _goal!.quickFormParams) {
      if ((p.kind == ParamKind.anchorRole || p.kind == ParamKind.wifiSsid) &&
          _params[p.key] == null) {
        return false;
      }
    }
    return true;
  }

  Future<void> _saveDraft() async {
    final app = context.read<AppState>();
    await app.addDraft(TemplateDraft(
      id: ScheduleEncoder.generateUuid(),
      templateId: _goal!.id,
      params: _params,
      createdAt: DateTime.now(),
      note: 'I\'ll grab this on site',
    ));
    if (!mounted) return;
    setState(() => _step = _Step.armed);
  }

  Future<void> _arm() async {
    final app = context.read<AppState>();
    final blocks = _goal!.expand(
      _params,
      instanceId: ScheduleEncoder.generateUuid(),
      newUuid: ScheduleEncoder.generateUuid,
    );
    await app.saveTemplateBlocks(const [], blocks);
    if (!mounted) return;
    setState(() => _step = _Step.armed);
  }

  void _finish() {
    final app = context.read<AppState>();
    app.markOnboardingDone();
    Navigator.of(context).maybePop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(_step)),
        automaticallyImplyLeading: widget.startAtGoalPicker,
        actions: [
          if (_step != _Step.armed)
            TextButton(
              onPressed: _finish,
              child: const Text('Just exploring',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_status != null) ...[
                Text(_status!,
                    style:
                        const TextStyle(color: Colors.amber, fontSize: 13)),
                const SizedBox(height: 12),
              ],
              Expanded(child: _stepBody()),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(_Step s) {
    switch (s) {
      case _Step.permissions:
        return 'Welcome';
      case _Step.pairWatch:
        return 'Meet your watch';
      case _Step.pickGoal:
        return 'Pick a goal';
      case _Step.placeAnchors:
        return 'Place your anchors';
      case _Step.quickForm:
        return 'Almost there';
      case _Step.armed:
        return 'Armed';
    }
  }

  Widget _stepBody() {
    switch (_step) {
      case _Step.permissions:
        return _permissionsStep();
      case _Step.pairWatch:
        return _pairWatchStep();
      case _Step.pickGoal:
        return _goalPickerStep();
      case _Step.placeAnchors:
        return _placeAnchorsStep();
      case _Step.quickForm:
        return _quickFormStep();
      case _Step.armed:
        return _armedStep();
    }
  }

  // ── Step bodies ───────────────────────────────────────────────────────────

  Widget _permissionsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stop negotiating with yourself.',
              style: TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'You design the day once, in a clear-headed moment — the watch '
            'and anchors carry it out so you don\'t have to keep re-deciding.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
          ),
          const SizedBox(height: 24),
          const Text(
            'Impulse needs Bluetooth to talk to your watch and anchors, and '
            'notifications for gentle reminders. Nothing leaves your phone.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
          ),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.lightOrange,
              foregroundColor: AppTheme.darkGrey,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _requestPermissions,
            child: const Text('Let\'s go',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );

  Widget _pairWatchStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your watch is the part of Impulse that keeps you to the line '
            'you drew. Power it on and scan.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _scanButton(DeviceType.watch, 'Scan for my watch'),
          const SizedBox(height: 16),
          Expanded(child: _deviceList(onTap: _pairWatch)),
          if (_watchService.isConnected)
            _primaryButton('It buzzed — that\'s hello. Continue',
                () => setState(() => _step = _Step.pickGoal)),
        ],
      );

  Widget _goalPickerStep() {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What do you want to stop fighting yourself about?',
            style: TextStyle(
                color: AppTheme.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              for (final t in app.registry.onboarders)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    leading: Icon(t.onboarder!.heroIcon,
                        color: AppTheme.lightOrange, size: 34),
                    title: Text('"${t.onboarder!.problemStatement}"',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: 15,
                            fontStyle: FontStyle.italic)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(t.displayName,
                          style: const TextStyle(
                              color: AppTheme.textGrey, fontSize: 12)),
                    ),
                    onTap: () {
                      setState(() {
                        _goal = t;
                        _roleIndex = 0;
                        _roleToAnchorId.clear();
                        if (t.onboarder!.requiredAnchors.isEmpty) {
                          _enterQuickForm();
                        } else {
                          _step = _Step.placeAnchors;
                          _startScan(DeviceType.anchor);
                        }
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeAnchorsStep() {
    final role = _currentRole;
    final placing = _found
        .where((d) => d.id == _placingAnchorId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Anchor ${_roleIndex + 1} of ${_requiredRoles.length}: ${role.label}',
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 17,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(role.placementCopy,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        const SizedBox(height: 16),
        if (placing == null) ...[
          _scanButton(DeviceType.anchor, 'Scan for anchors'),
          const SizedBox(height: 12),
          const Text(
            'Tap "beep" to find out which physical anchor is which.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _deviceList(
              onTap: (d) => setState(() => _placingAnchorId = d.id),
              showBeep: true,
            ),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Name this anchor',
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: 15)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: AppTheme.textWhite),
                    decoration: InputDecoration(
                      hintText: role.label,
                      hintStyle: const TextStyle(color: AppTheme.textGrey),
                      filled: true,
                      fillColor: AppTheme.backgroundGrey,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _placingAnchorId = null),
                        child: const Text('Back',
                            style: TextStyle(color: AppTheme.textGrey)),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.lightOrange,
                          foregroundColor: AppTheme.darkGrey,
                        ),
                        onPressed: () => _assignAnchor(placing),
                        child: Text('This is my ${role.role}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _quickFormStep() {
    final t = _goal!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.displayName,
            style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('A few quick choices — everything is adjustable later.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 13)),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: TemplateForm(
              params: t.quickFormParams,
              values: _params,
              onChanged: (v) => setState(() => _params = {..._params, ...v}),
            ),
          ),
        ),
        if (_unanswerable.isNotEmpty && !_quickFormComplete) ...[
          TextButton(
            onPressed: _saveDraft,
            child: const Text('I\'ll grab this on site — save as draft',
                style: TextStyle(color: AppTheme.lightOrange)),
          ),
          const SizedBox(height: 4),
        ],
        _primaryButton('Arm it', _quickFormComplete ? _arm : null),
      ],
    );
  }

  Widget _armedStep() {
    final draft = _unanswerable.isNotEmpty && !_quickFormComplete;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(draft ? Icons.bookmark_added_outlined : Icons.verified_outlined,
            color: AppTheme.lightOrange, size: 56),
        const SizedBox(height: 16),
        Text(
          draft
              ? 'Saved as a draft'
              : 'Done. Past-you runs the day now.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppTheme.textWhite,
              fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          draft
              ? 'Finish it from the Commitments screen when you\'re on site — '
                  'it won\'t run until then.'
              : 'You can adjust this freely for the next two hours — after '
                  'that, it\'s a commitment.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 14),
        ),
        const SizedBox(height: 32),
        _primaryButton('Take me home', _finish),
      ],
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────────────────

  Widget _scanButton(DeviceType type, String label) => OutlinedButton.icon(
        onPressed: _scanning ? null : () => _startScan(type),
        icon: _scanning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.lightOrange))
            : const Icon(Icons.bluetooth_searching,
                color: AppTheme.lightOrange),
        label: Text(_scanning ? 'Scanning…' : label,
            style: const TextStyle(color: AppTheme.lightOrange)),
      );

  Widget _deviceList({
    required void Function(BluetoothDeviceModel) onTap,
    bool showBeep = false,
  }) {
    if (_found.isEmpty) {
      return Center(
        child: Text(
          _scanning ? 'Looking…' : 'Nothing yet — try scanning.',
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
        ),
      );
    }
    return ListView(
      children: [
        for (final d in _found)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                d.deviceType == DeviceType.watch
                    ? Icons.watch
                    : Icons.sensors,
                color: AppTheme.lightOrange,
              ),
              title: Text(d.name,
                  style: const TextStyle(color: AppTheme.textWhite)),
              subtitle: Text(
                  '${_btService.getSignalStrength(d.rssi)} signal',
                  style: const TextStyle(
                      color: AppTheme.textGrey, fontSize: 12)),
              trailing: showBeep
                  ? TextButton(
                      onPressed: d.bleRemoteId == null
                          ? null
                          : () => AnchorService().identify(d.bleRemoteId!),
                      child: const Text('Beep',
                          style: TextStyle(color: AppTheme.lightOrange)),
                    )
                  : null,
              onTap: () => onTap(d),
            ),
          ),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.lightOrange,
          foregroundColor: AppTheme.darkGrey,
          disabledBackgroundColor: AppTheme.cardGrey,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}
