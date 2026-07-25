import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expenseiq/widgets/calculator_sheet.dart';

/// Drives the real keypad and reads back the previewed result, so the test
/// covers tokenizing, precedence and the sheet wiring together.
Future<double?> compute(WidgetTester tester, String keys) async {
  double? captured;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => captured = await showCalculatorSheet(context),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  for (final k in keys.split(' ')) {
    await tester.tap(find.widgetWithText(SizedBox, k).first);
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(SizedBox, '=').first);
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('adds', (t) async => expect(await compute(t, '1 2 + 8'), 20));
  testWidgets('respects precedence', (t) async => expect(await compute(t, '2 + 3 × 4'), 14));
  testWidgets('divides', (t) async => expect(await compute(t, '9 0 ÷ 3'), 30));
  testWidgets('splits a bill', (t) async => expect(await compute(t, '1 2 0 0 ÷ 4'), 300));
  testWidgets('decimals', (t) async => expect(await compute(t, '1 0 . 5 + . 5'), 11));
  testWidgets('percent of preceding value', (t) async => expect(await compute(t, '5 0 0 - 1 0 %'), 450));
  testWidgets('chained ops', (t) async => expect(await compute(t, '1 0 0 + 2 0 - 5'), 115));
  testWidgets('00 key', (t) async => expect(await compute(t, '5 00'), 500));
}
