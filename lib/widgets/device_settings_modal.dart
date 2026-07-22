import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bluetooth_device_model.dart';
import '../services/anchor_service.dart';
import '../services/bluetooth_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class DeviceSettingsModal extends StatefulWidget {
  final BluetoothDeviceModel device;

  const DeviceSettingsModal({super.key, required this.device});

  @override
  State<DeviceSettingsModal> createState() => _DeviceSettingsModalState();
}

class _DeviceSettingsModalState extends State<DeviceSettingsModal> {
  late final TextEditingController _nameController;
  bool _isBusy = false;
  String? _statusMsg;

  // Anchor WiFi state (§8.2/§8.14): read …000E when the card opens.
  AnchorWifiStatus? _wifiStatus;
  bool _wifiChecking = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
    if (widget.device.deviceType == DeviceType.anchor &&
        widget.device.bleRemoteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAnchorWifi());
    }
  }

  /// Read the anchor's real WiFi state (and let §8.14 offer if warranted). The
  /// user is standing at the anchor, so check immediately (§8.14 trigger 3).
  Future<void> _checkAnchorWifi() async {
    if (!mounted) return;
    setState(() => _wifiChecking = true);
    final status =
        await context.read<AppState>().checkAndOfferAnchor(widget.device);
    if (!mounted) return;
    setState(() {
      _wifiChecking = false;
      _wifiStatus = status;
    });
  }

  /// Human wording for the anchor WiFi state (§8.2) — from the anchor, not
  /// inferred from HTTP timeouts.
  String _wifiStateLabel(AnchorWifiStatus s) {
    switch (s.state) {
      case AnchorWifiState.connected:
        return 'On "${s.ssid}"';
      case AnchorWifiState.connecting:
        return 'Connecting…';
      case AnchorWifiState.authFailed:
        return 'Wrong password for "${s.ssid}"';
      case AnchorWifiState.apNotFound:
        return 'Can’t find "${s.ssid}"';
      case AnchorWifiState.neverProvisioned:
        return 'WiFi not set up';
      case AnchorWifiState.unknown:
        return 'Unknown';
    }
  }

  /// "Re-send WiFi" (§8.2): pick a saved network to offer this anchor. When the
  /// anchor is in distress and its SSID isn't saved, this is the prompt-for-
  /// password entry point (we route the user to add it).
  Future<void> _reSendWifi() async {
    final app = context.read<AppState>();
    final nets = app.savedNetworks.networks;
    if (nets.isEmpty) {
      setState(() => _statusMsg =
          'No saved networks yet — add one in Settings ▸ Network first.');
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.cardGrey,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Offer a network to this anchor',
                  style: TextStyle(
                      color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
            ),
            for (final n in nets)
              ListTile(
                leading: const Icon(Icons.wifi, color: AppTheme.textGrey),
                title: Text(n.ssid,
                    style: const TextStyle(color: AppTheme.textWhite)),
                onTap: () => Navigator.pop(ctx, n.ssid),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() { _isBusy = true; _statusMsg = null; });
    final res = await app.offerSavedNetworkToAnchor(widget.device, chosen);
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _wifiStatus = res?.statusAfter ?? _wifiStatus;
      _statusMsg = res == null
          ? 'Couldn’t reach the anchor over Bluetooth.'
          : 'Offered "$chosen" — the anchor will try it.';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == widget.device.name) return;

    final updated = widget.device.copyWith(name: newName);
    await BluetoothService().addOrUpdateDevice(updated);
    if (mounted) {
      setState(() => _statusMsg = 'Name saved.');
    }
  }

  Future<void> _sendToggle(int value) async {
    setState(() { _isBusy = true; _statusMsg = null; });
    final result = await AnchorService().sendToggle(widget.device.bleRemoteId!, value);
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      switch (result) {
        case AnchorToggleResult.success:
          _statusMsg = value == 1 ? 'Anchor opened.' : 'Anchor closed.';
        case AnchorToggleResult.rejected:
          _statusMsg = 'Can\'t open right now — this anchor is holding an active commitment.';
        case AnchorToggleResult.connectionError:
          _statusMsg = 'Could not connect to anchor. Make sure it is nearby and powered on.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAnchor = widget.device.deviceType == DeviceType.anchor;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Device Settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),

          // Display Name section
          const Text(
            'Display Name',
            style: TextStyle(
              color: AppTheme.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.darkGrey,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _nameController,
                builder: (context, value, _) {
                  final canSave = value.text.trim().isNotEmpty &&
                      value.text.trim() != widget.device.name;
                  return ElevatedButton(
                    onPressed: canSave ? _saveName : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.lightOrange,
                      foregroundColor: AppTheme.darkGrey,
                      disabledBackgroundColor: AppTheme.cardGrey,
                    ),
                    child: const Text('Save'),
                  );
                },
              ),
            ],
          ),

          // WiFi section (anchors only, §8.2/§8.14) — real state from …000E.
          if (isAnchor && widget.device.bleRemoteId != null) ...[
            const SizedBox(height: 28),
            const Text(
              'WiFi',
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_wifiChecking)
                  const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.textGrey))
                else
                  Icon(
                    _wifiStatus?.state == AnchorWifiState.connected
                        ? Icons.wifi
                        : Icons.wifi_off,
                    size: 18,
                    color: (_wifiStatus?.state.isDistress ?? false)
                        ? const Color(0xFFE0A100)
                        : AppTheme.textGrey,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _wifiChecking
                        ? 'Checking anchor WiFi…'
                        : _wifiStatus == null
                            ? 'Couldn’t read WiFi state over Bluetooth.'
                            : _wifiStateLabel(_wifiStatus!),
                    style: const TextStyle(
                        color: AppTheme.textWhite, fontSize: 14),
                  ),
                ),
              ],
            ),
            // slots_used is Advanced-mode only (§8.2).
            if (_wifiStatus != null &&
                context.watch<AppState>().advancedMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Credential slots used: ${_wifiStatus!.slotsUsed}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _reSendWifi,
              icon: const Icon(Icons.wifi_find, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.lightOrange,
                side: const BorderSide(color: AppTheme.lightOrange),
              ),
              label: const Text('Re-send WiFi'),
            ),
          ],

          // Servo Control section (anchors only)
          if (isAnchor) ...[
            const SizedBox(height: 28),
            const Text(
              'Servo Lock',
              style: TextStyle(
                color: AppTheme.textGrey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the anchor strap lock to reposition the anchor. '
              'The lock stays closed while a commitment that uses this anchor is running.',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (widget.device.bleRemoteId == null)
              const Text(
                'This anchor has not been directly scanned. Tap \'Scan\' on the '
                'Devices tab to discover it before using servo control.',
                style: TextStyle(color: AppTheme.lightOrange, fontSize: 13),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isBusy ? null : () => _sendToggle(1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.lightOrange,
                        side: const BorderSide(color: AppTheme.lightOrange),
                      ),
                      child: _isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.lightOrange,
                              ),
                            )
                          : const Text('Open'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isBusy ? null : () => _sendToggle(0),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.lightOrange,
                        foregroundColor: AppTheme.darkGrey,
                      ),
                      child: _isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.darkGrey,
                              ),
                            )
                          : const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ],

          // Status message
          if (_statusMsg != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMsg!,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
