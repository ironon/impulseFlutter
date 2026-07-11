import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../models/automation_model.dart';
import '../services/automation_service.dart';
import '../services/integrity_store.dart';
import '../services/watch_service.dart';
import '../services/self_binding_policy.dart';

/// App modes (§2A). Normal is the default friendly template layer; Advanced is
/// the raw-block power-user surface with the debug menu.
enum AppMode { normal, advanced }

/// The single reactive state layer (§2). Screens `watch`/`select` this rather
/// than polling services. It observes watch connection + live status, holds the
/// authoring copy of the schedule, and surfaces the trust stores.
class AppState extends ChangeNotifier {
  AppState({
    required IntegrityStore integrityStore,
    WatchService? watchService,
    AutomationService? automationService,
  })  : _integrity = integrityStore,
        _watch = watchService ?? WatchService(),
        _automations = automationService ?? AutomationService();

  final IntegrityStore _integrity;
  final WatchService _watch;
  final AutomationService _automations;

  IntegrityStore get integrity => _integrity;

  StreamSubscription<WatchStatus>? _statusSub;

  // ── Live watch state ──
  WatchStatus? _status;
  WatchStatus? get status => _status;
  bool get watchConnected => _watch.isConnected;

  // ── Mode ──
  AppMode _mode = AppMode.normal;
  AppMode get mode => _mode;
  bool get advancedMode => _mode == AppMode.advanced;
  void setMode(AppMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  // ── Self-binding policy config (§8.9) ──
  SelfBindingConfig _policyConfig = const SelfBindingConfig();
  SelfBindingConfig get policyConfig => _policyConfig;

  // ── Emergency pass allowance (§8.10) ──
  int _passAllowance = 2;
  int get passAllowance => _passAllowance;

  List<Automation> get schedule => _automations.automations;

  Future<void> initialize() async {
    await _automations.initialize();
    _statusSub = _watch.statusStream.listen((s) {
      _status = s;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Call after any BLE connection state change so widgets re-render.
  void connectionChanged() => notifyListeners();

  void setPolicyConfig(SelfBindingConfig config) {
    _policyConfig = config;
    notifyListeners();
  }

  void setPassAllowance(int allowance) {
    _passAllowance = allowance;
    notifyListeners();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}

/// Convenience factory for tests / bootstrap.
Future<AppState> bootstrapAppState({AppDatabase? db}) async {
  final database = db ?? AppDatabase();
  final state = AppState(integrityStore: IntegrityStore(database));
  await state.initialize();
  return state;
}
