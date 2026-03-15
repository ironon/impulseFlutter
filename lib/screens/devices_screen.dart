import 'package:flutter/material.dart';
import '../models/bluetooth_device_model.dart';
import '../services/bluetooth_service.dart';
import '../theme/app_theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final BluetoothService _bluetoothService = BluetoothService();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initializeBluetooth();
  }

  Future<void> _initializeBluetooth() async {
    await _bluetoothService.initialize();
    setState(() {});
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
    });

    try {
      _bluetoothService.startScan().listen((results) {
        for (var result in results) {
          final device = BluetoothDeviceModel(
            id: result.device.remoteId.toString(),
            name: result.device.platformName.isNotEmpty
                ? result.device.platformName
                : 'Unknown Device',
            isConnected: false,
            rssi: result.rssi,
            lastSeen: DateTime.now(),
          );
          _bluetoothService.addOrUpdateDevice(device);
        }
        setState(() {});
      });

      await Future.delayed(const Duration(seconds: 15));
      await _bluetoothService.stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
          ),
        ],
      ),
      body: _bluetoothService.deviceHistory.isEmpty
          ? _buildEmptyState()
          : _buildDeviceList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 64,
            color: AppTheme.textGrey,
          ),
          const SizedBox(height: 16),
          Text(
            'No devices found',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the refresh button to scan',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bluetoothService.deviceHistory.length,
      itemBuilder: (context, index) {
        final device = _bluetoothService.deviceHistory[index];
        return _buildDeviceCard(device);
      },
    );
  }

  Widget _buildDeviceCard(BluetoothDeviceModel device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: device.isConnected
                ? AppTheme.lightOrange.withValues(alpha: 0.2)
                : AppTheme.darkGrey,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.bluetooth,
            color: device.isConnected
                ? AppTheme.lightOrange
                : AppTheme.textGrey,
            size: 32,
          ),
        ),
        title: Text(
          device.name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.isConnected ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  device.isConnected ? 'Connected' : 'Disconnected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: device.isConnected
                            ? Colors.green
                            : AppTheme.textGrey,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'RSSI: ${device.rssi} dBm (${_bluetoothService.getSignalStrength(device.rssi)})',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              'Last seen: ${_formatDateTime(device.lastSeen)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                  ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: AppTheme.textGrey,
        ),
        onTap: () {
          // TODO: Navigate to device details
        },
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
