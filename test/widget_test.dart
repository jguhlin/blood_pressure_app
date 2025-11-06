// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blood_pressure_app/main.dart';

void main() {
  testWidgets('Loads Latest Blood Pressure screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LatestBPPage(autoFetch: false)),
    );
    expect(find.text('Latest Blood Pressure'), findsOneWidget);
    expect(find.text('Systolic (mmHg)'), findsWidgets);
    expect(find.text('Diastolic (mmHg)'), findsWidgets);
  });
}
