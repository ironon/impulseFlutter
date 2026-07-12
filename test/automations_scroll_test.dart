import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/models/automation_model.dart';
import 'package:impulse_app/screens/automations_screen.dart';
import 'package:impulse_app/services/automation_service.dart';
import 'package:impulse_app/services/integrity_store.dart';
import 'package:impulse_app/state/app_state.dart';
import 'package:impulse_app/widgets/automation_block.dart';

/// Regression test for the "timeblocks don't move when the day view scrolls"
/// bug: labels, dividers and blocks must share ONE scrollable coordinate
/// space, so scrolling the timeline moves the blocks with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppState app;

  // Setup/teardown run in a real async zone — drift's close future resolves
  // on a real timer that testWidgets' FakeAsync zone would never fire.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final autoSvc = AutomationService();
    for (final a in List.of(autoSvc.automations)) {
      await autoSvc.deleteAutomation(a.id);
    }
    await autoSvc.addAutomation(Automation(
      id: '00000000-0000-4000-8000-000000000001',
      referenceDate: DateTime.utc(2026, 1, 1),
      startTime: const TimeOfDay(hour: 12, minute: 0),
      endTime: const TimeOfDay(hour: 13, minute: 0),
      recurrenceType: RecurrenceType.daily,
      criteria: Criteria.getOnWifi,
      wifiSSID: 'TestNet',
      profile: EnforcementProfile.normalBuzz,
      color: const Color(0xFF2196F3),
    ));
    db = AppDatabase.forTesting(NativeDatabase.memory());
    app = AppState(integrityStore: IntegrityStore(db));
    await app.initialize();
  });

  tearDown(() async {
    app.dispose();
    await db.close();
  });

  testWidgets('timeblocks scroll together with the hour grid', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: AutomationsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);

    scrollable.position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 400));
    final before = tester.getTopLeft(find.byType(AutomationBlock)).dy;

    scrollable.position.jumpTo(300);
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.getTopLeft(find.byType(AutomationBlock)).dy;

    // Scrolling down by 300 px must move the block up by exactly 300 px.
    expect(before - after, 300);
  });
}
