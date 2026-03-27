import 'dart:async';

import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'models/bluetooth_device_model.dart';
import 'services/bluetooth_service.dart';
import 'services/watch_service.dart';
import 'screens/devices_screen.dart';
import 'screens/automations_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/debug_screen.dart';

void main() {
  runApp(const ImpulseApp());
}

class ImpulseApp extends StatelessWidget {
  const ImpulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Impulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  StreamSubscription<List<SeenAnchorInfo>>? _seenAnchorsSub;

  final _btService    = BluetoothService();
  final _watchService = WatchService();

  final List<Widget> _screens = [
    const DevicesScreen(),
    const AutomationsScreen(),
    const SettingsScreen(),
    const DebugScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _seenAnchorsSub = _watchService.seenAnchorsStream.listen((anchors) {
      for (final a in anchors) {
        _btService.addOrUpdateDevice(BluetoothDeviceModel(
          id:          a.uuid,
          name:        'Anchor',
          isConnected: false,
          rssi:        a.rssi,
          lastSeen:    a.lastSeen,
          deviceType:  DeviceType.anchor,
        ));
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _seenAnchorsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_suggest),
            label: 'Automations',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bug_report_outlined),
            label: 'Debug',
          ),
        ],
      ),
    );
  }
}
