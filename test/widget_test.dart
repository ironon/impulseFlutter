// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:impulse_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ImpulseApp());

    // Verify that the bottom navigation bar is present
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Verify all three tabs are accessible
    expect(find.text('Automations'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Tap the Automations tab
    await tester.tap(find.text('Automations').first);
    await tester.pumpAndSettle();

    // Verify that Automations screen is shown - should have calendar view
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Tap the Settings tab
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    // Verify that Settings screen is shown
    expect(find.text('Coming soon'), findsWidgets);
  });
}
