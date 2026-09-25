/// Widget tests for the Flutter-hosted native FFI widget.
///
/// The native library is not loaded in a test process, so these cover the
/// contract that matters for a host app: the widget degrades to a readable
/// error instead of taking the app down with it.
library;

import 'package:dart_not_native/native_stateful_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool showResetButton = true}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeStatefulWidget(
              nativeMethodName: 'increment_counter',
              label: 'Counter (Native FFI)',
              initialMethodName: 'get_counter',
              resetMethodName: 'reset_counter',
              showResetButton: showResetButton,
            ),
          ),
        ),
      );

  testWidgets('renders its label', (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.text('Counter (Native FFI)'), findsOneWidget);
  });

  testWidgets('an unavailable native library becomes a visible error, not a '
      'crash', (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.text('Failed to load value'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers an action and a reset button', (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.byTooltip('Invoke'), findsOneWidget);
    expect(find.byTooltip('Reset'), findsOneWidget);
  });

  testWidgets('the reset button can be hidden', (tester) async {
    await pump(tester, showResetButton: false);
    await tester.pump();

    expect(find.byTooltip('Reset'), findsNothing);
  });

  testWidgets('tapping the action reports the failure instead of throwing', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();

    await tester.tap(find.byTooltip('Invoke'));
    await tester.pump();

    expect(find.textContaining('Method failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
