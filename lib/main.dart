import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'models/bluetooth_device_model.dart';
import 'services/bluetooth_service.dart';
import 'services/watch_service.dart';
import 'state/app_state.dart';
import 'screens/devices_screen.dart';
import 'screens/automations_screen.dart';
import 'screens/commitments_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_flow.dart';
import 'screens/settings_screen.dart';
import 'screens/debug_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = await bootstrapAppState();
  runApp(ImpulseApp(appState: appState));
}

class ImpulseApp extends StatelessWidget {
  const ImpulseApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp(
        title: 'Impulse',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainScreen(),
      ),
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
    // First run: goal-first onboarding (§8.1). Skippable ("just exploring");
    // re-enterable later from Commitments as "add another goal".
    final onboarded =
        context.select<AppState, bool>((s) => s.onboardingDone);
    if (!onboarded) return const OnboardingFlow();

    final advanced =
        context.select<AppState, bool>((s) => s.advancedMode);

    // Day-first Home leads (§8.7). Normal mode: friendly template cards.
    // Advanced: raw blocks + Debug tab. Switching modes never changes what
    // the watch runs — only how it renders.
    final screens = <Widget>[
      const HomeScreen(),
      advanced ? const AutomationsScreen() : const CommitmentsScreen(),
      const DevicesScreen(),
      const SettingsScreen(),
      if (advanced) const DebugScreen(),
    ];
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.today),
        label: 'Today',
      ),
      BottomNavigationBarItem(
        icon: Icon(advanced ? Icons.grid_view : Icons.self_improvement),
        label: advanced ? 'Blocks' : 'Commitments',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.bluetooth),
        label: 'Devices',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: 'Settings',
      ),
      if (advanced)
        const BottomNavigationBarItem(
          icon: Icon(Icons.bug_report_outlined),
          label: 'Debug',
        ),
    ];
    if (_currentIndex >= screens.length) _currentIndex = screens.length - 1;

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: items,
      ),
    );
  }
}
