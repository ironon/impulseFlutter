import 'package:flutter/material.dart';

import '../models/bluetooth_device_model.dart';
import '../services/anchor_service.dart';
import '../services/bluetooth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device.name);
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
          _statusMsg = 'Cannot open: anchor is in an active enforcement event.';
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
              'The lock cannot be opened during an active enforcement event.',
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
