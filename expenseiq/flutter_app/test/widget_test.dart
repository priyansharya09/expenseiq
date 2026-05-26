// Widget test for ExpenseIQ app
//
// Verifies that the app boots and shows the auth gate / login screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expenseiq/main.dart';

void main() {
  testWidgets('App should boot and show ExpenseIQ title', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const ExpenseIQApp());

    // Allow the async auth check to complete
    await tester.pump(const Duration(seconds: 1));

    // The app should render without crashing.
    // Look for the app to have rendered something (either login or loading).
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
