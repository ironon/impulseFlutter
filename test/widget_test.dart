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
  SharedPreferences.setMockInitialValues({});

  testWidgets('App smoke test', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final appState = AppState(integrityStore: IntegrityStore(db));
    await appState.initialize();

    await tester.pumpWidget(ImpulseApp(appState: appState));

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Automations'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Automations').first);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await db.close();
  });
}
