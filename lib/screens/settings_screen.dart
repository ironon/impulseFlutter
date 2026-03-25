import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/watch_service.dart';
import '../services/bluetooth_service.dart';
import '../services/automation_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _watchService = WatchService();
  final _btService    = BluetoothService();
  final _autoService  = AutomationService();

  // WiFi cred fields
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _passVisible = false;

  // Watch settings
  bool _disconnectedIsDormant = true;
  bool _awayIsDormant         = true;
  int  _tzOffsetMin           = 0;

  // Per-anchor IP text controllers  (anchorId -> controller)
  final Map<String, TextEditingController> _ipCtrls = {};

  bool _isBusy = false;
  String? _msg;

  static const String _prefDisconn = 'setting_disc_dorm';
  static const String _prefAway    = 'setting_away_dorm';
  static const String _prefTz      = 'setting_tz';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _btService.initialize().then((_) => setState(() {}));
    _autoService.initialize();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _disconnectedIsDormant = p.getBool(_prefDisconn) ?? true;
      _awayIsDormant         = p.getBool(_prefAway)    ?? true;
      _tzOffsetMin           = p.getInt(_prefTz)       ?? 0;
    });
  }

  Future<void> _savePrefsLocally() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefDisconn, _disconnectedIsDormant);
    await p.setBool(_prefAway,    _awayIsDormant);
    await p.setInt(_prefTz,       _tzOffsetMin);
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    for (final c in _ipCtrls.values) { c.dispose(); }
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pushWifi() async {
    if (!_watchService.isConnected) { _show('Watch not connected'); return; }
    if (_ssidCtrl.text.trim().isEmpty) { _show('Enter an SSID first'); return; }
    _busy(true);
    try {
      await _watchService.pushWifiCredentials(
        _ssidCtrl.text.trim(), _passCtrl.text,
      );
      _show('WiFi credentials sent ✓');
    } catch (e) { _show('Error: $e'); }
    _busy(false);
  }

  Future<void> _pushSettings() async {
    if (!_watchService.isConnected) { _show('Watch not connected'); return; }
    _busy(true);
    try {
      await _savePrefsLocally();
      final ok = await _watchService.pushSettings(
        disconnectedIsDormant: _disconnectedIsDormant,
        awayIsDormant:         _awayIsDormant,
        tzOffsetMinutes:       _tzOffsetMin,
      );
      _show(ok ? 'Settings saved on watch ✓' : 'Watch returned error');
    } catch (e) { _show('Error: $e'); }
    _busy(false);
  }

  Future<void> _pushAnchorIps() async {
    if (!_watchService.isConnected) { _show('Watch not connected'); return; }
    _busy(true);
    try {
      for (final entry in _ipCtrls.entries) {
        final ip = entry.value.text.trim();
        if (ip.isNotEmpty) await _btService.updateAnchorIp(entry.key, ip);
      }
      final ok = await _watchService.pushAnchorIpTable(_btService.anchors);
      _show(ok ? 'Anchor IPs sent ✓' : 'Watch returned error');
    } catch (e) { _show('Error: $e'); }
    _busy(false);
  }

  Future<void> _pushSchedule() async {
    if (!_watchService.isConnected) { _show('Watch not connected'); return; }
    _busy(true);
    try {
      final ok = await _watchService.pushSchedule(_autoService.automations);
      _show(ok ? 'Schedule pushed ✓' : 'Schedule rejected by watch');
    } catch (e) { _show('Error: $e'); }
    _busy(false);
  }

  void _busy(bool v) { if (mounted) setState(() => _isBusy = v); }
  void _show(String m) { if (mounted) setState(() => _msg = m); }

  String _tzLabel(int offsetMin) {
    final sign = offsetMin >= 0 ? '+' : '-';
    final abs  = offsetMin.abs();
    final h    = (abs ~/ 60).toString().padLeft(2, '0');
    final m    = (abs  % 60).toString().padLeft(2, '0');
    return 'UTC$sign$h:$m';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final anchors = _btService.anchors;
    for (final a in anchors) {
      _ipCtrls.putIfAbsent(
        a.id, () => TextEditingController(text: a.ipAddress ?? ''));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_isBusy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_msg != null) _banner(_msg!),

          // ── Watch connection status ────────────────────────────────────
          _section('Watch Connection'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _watchService.isConnected ? Icons.watch : Icons.watch_off,
                    color: _watchService.isConnected
                        ? AppTheme.lightOrange : AppTheme.textGrey,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _watchService.isConnected
                        ? 'Watch connected'
                        : 'Not connected — go to Devices tab',
                    style: TextStyle(
                      color: _watchService.isConnected
                          ? AppTheme.textWhite : AppTheme.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── WiFi credentials ───────────────────────────────────────────
          _section('Push WiFi Credentials to Watch'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _textField(_ssidCtrl, 'Network SSID', false),
                  const SizedBox(height: 12),
                  _textField(
                    _passCtrl, 'Password', !_passVisible,
                    suffix: IconButton(
                      icon: Icon(
                        _passVisible ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textGrey,
                      ),
                      onPressed: () => setState(() => _passVisible = !_passVisible),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _fullBtn('Send to Watch', _pushWifi),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Watch behaviour ────────────────────────────────────────────
          _section('Watch Behaviour'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _toggle(
                    'Enforce when disconnected from phone',
                    _disconnectedIsDormant,
                    (v) => setState(() => _disconnectedIsDormant = v),
                  ),
                  const Divider(color: AppTheme.cardGrey),
                  _toggle(
                    'Enforce when on WiFi but no BLE',
                    _awayIsDormant,
                    (v) => setState(() => _awayIsDormant = v),
                  ),
                  const Divider(color: AppTheme.cardGrey),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Timezone',
                          style: TextStyle(color: AppTheme.textWhite, fontSize: 14)),
                      Text(_tzLabel(_tzOffsetMin),
                          style: const TextStyle(
                              color: AppTheme.lightOrange, fontSize: 14)),
                    ],
                  ),
                  Slider(
                    value:      _tzOffsetMin.toDouble(),
                    min:        -720,
                    max:         840,
                    divisions:   156,
                    activeColor: AppTheme.lightOrange,
                    onChanged:  (v) => setState(() => _tzOffsetMin = v.round()),
                  ),
                  const SizedBox(height: 8),
                  _fullBtn('Save & Push to Watch', _pushSettings),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Schedule ───────────────────────────────────────────────────
          _section('Schedule'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_autoService.automations.length} event(s) stored',
                    style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _fullBtn('Push Schedule to Watch', _pushSchedule),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Anchor IPs ─────────────────────────────────────────────────
          _section('Anchor IP Addresses'),
          if (anchors.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'No anchors discovered yet. Scan from the Devices tab.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ...anchors.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  a.name,
                                  style: const TextStyle(
                                      color: AppTheme.textWhite, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: _textField(
                                    _ipCtrls[a.id]!, 'e.g. 192.168.1.42', false),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 4),
                    _fullBtn('Push IPs to Watch', _pushAnchorIps),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _banner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: AppTheme.cardGrey,
            borderRadius: BorderRadius.circular(8)),
        child: Text(msg,
            style: const TextStyle(color: AppTheme.textWhite, fontSize: 13)),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textGrey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      );

  Widget _textField(TextEditingController ctrl, String hint, bool obscure,
      {Widget? suffix}) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: AppTheme.textWhite),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textGrey),
          filled: true,
          fillColor: AppTheme.backgroundGrey,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.cardGrey)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.cardGrey)),
          suffixIcon: suffix,
        ),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: AppTheme.textWhite, fontSize: 14))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppTheme.lightOrange,
          ),
        ],
      );

  Widget _fullBtn(String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isBusy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.lightOrange,
            foregroundColor: AppTheme.darkGrey,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
