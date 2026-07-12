// Basic smoke test for the Impulse app shell.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:impulse_app/data/app_database.dart';
import 'package:impulse_app/main.dart';
import 'package:impulse_app/services/integrity_store.dart';
import 'package:impulse_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppState appState;

  setUp(() async {
    // Skip first-run onboarding for the shell smoke test.
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    appState = AppState(integrityStore: IntegrityStore(db));
    await appState.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(ImpulseApp(appState: appState));

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    // Normal mode is the default: friendly Commitments tab, no Debug tab.
    expect(find.text('Commitments'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Debug'), findsNothing);

    await tester.tap(find.text('Commitments').first);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Advanced mode reveals the raw-block view and the Debug tab.
    await appState.setMode(AppMode.advanced);
    await tester.pumpAndSettle();
    expect(find.text('Blocks'), findsWidgets);
    expect(find.text('Debug'), findsWidgets);
  });

  testWidgets('first run shows goal-first onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db2 = AppDatabase.forTesting(NativeDatabase.memory());
    final fresh = AppState(integrityStore: IntegrityStore(db2));
    await fresh.initialize();

    await tester.pumpWidget(ImpulseApp(appState: fresh));
    expect(find.text('Stop negotiating with yourself.'), findsOneWidget);
    expect(find.text('Just exploring'), findsOneWidget);

    // Skip path lands on the main shell.
    await tester.tap(find.text('Just exploring'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}
