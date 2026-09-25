/// Asking for the keyboard, painted with Flutter widgets.
///
/// The ask travels as a version rather than a state, so the field takes the
/// caret once per ask and never steals it back on an unrelated render.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterUIRenderer renderer;

  setUp(() => renderer = FlutterUIRenderer());
  tearDown(() => renderer.dispose());

  WidgetNode screen({
    bool autofocus = false,
    int? focusVersion,
    bool focusRequested = true,
    String hint = 'Search',
  }) => UIBuilder.column(
    children: [
      UIBuilder.textField(
        hint: hint,
        eventId: 'search',
        autofocus: autofocus,
        focusVersion: focusVersion,
        focusRequested: focusRequested,
      ),
      UIBuilder.textField(hint: 'Other', eventId: 'other'),
    ],
  );

  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: renderer.build)),
      ),
    );
    await tester.pump();
  }

  /// Whether the field showing [hint] holds the caret.
  bool focused(WidgetTester tester, String hint) {
    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint,
      ),
    );
    return field.focusNode?.hasFocus ?? false;
  }

  testWidgets('a field that asks for nothing does not take the caret', (
    tester,
  ) async {
    await show(tester, screen());

    expect(focused(tester, 'Search'), isFalse);
  });

  testWidgets('autofocus takes the keyboard when the field appears', (
    tester,
  ) async {
    await show(tester, screen(autofocus: true));

    expect(focused(tester, 'Search'), isTrue);
  });

  testWidgets('autofocus does not take it back on a later render', (
    tester,
  ) async {
    await show(tester, screen(autofocus: true));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Other',
      ),
    );
    await tester.pump();

    await show(tester, screen(autofocus: true, hint: 'Search'));

    expect(focused(tester, 'Other'), isTrue);
    expect(focused(tester, 'Search'), isFalse);
  });

  testWidgets('a new version moves the caret to the field', (tester) async {
    await show(tester, screen(focusVersion: 1));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Other',
      ),
    );
    await tester.pump();

    await show(tester, screen(focusVersion: 2));

    expect(focused(tester, 'Search'), isTrue);
  });

  testWidgets('the same version again is an ask already answered', (
    tester,
  ) async {
    await show(tester, screen(focusVersion: 1));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Other',
      ),
    );
    await tester.pump();

    await show(tester, screen(focusVersion: 1));

    expect(focused(tester, 'Other'), isTrue);
  });

  testWidgets('asking to give it up dismisses the keyboard', (tester) async {
    await show(tester, screen(focusVersion: 1));
    expect(focused(tester, 'Search'), isTrue);

    await show(tester, screen(focusVersion: 2, focusRequested: false));

    expect(focused(tester, 'Search'), isFalse);
  });
}
