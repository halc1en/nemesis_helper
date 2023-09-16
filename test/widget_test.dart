// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nemesis_helper/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AppLoader(null));

    expect(find.text('Reference'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Tap 'Settings'
    await tester.tap(find.byIcon(Icons.help));
    await tester.pump();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Scale'), findsOneWidget);
  });
}
