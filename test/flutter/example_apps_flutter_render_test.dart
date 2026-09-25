/// Every example app, painted with Flutter widgets.
///
/// The same `NativeUIApp` that renders to DOM on web and to native views on
/// mobile is mounted in a `NativeUIAppHost` here. This is the proof that the
/// node vocabulary the examples use is fully covered by the Flutter renderer -
/// nothing falls through to the unknown-widget placeholder, and no screen
/// overflows or throws.
library;

import 'package:dart_not_native/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/example_apps.dart';

void main() {
  exampleApps.forEach((name, build) {
    group(name, () {
      testWidgets('paints without an exception', (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: NativeUIAppHost(app: build())),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });

      testWidgets('uses no node type the renderer cannot paint', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(home: NativeUIAppHost(app: build())),
        );
        await tester.pump();

        expect(find.textContaining('Unknown widget:'), findsNothing);
      });

      testWidgets('fits a phone-sized screen', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(home: NativeUIAppHost(app: build())),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'a screen that overflows paints a stripe for the user',
        );
      });
    });
  });

  testWidgets('an interaction repaints, on the same events the web uses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NativeUIAppHost(app: exampleApps['counter']!())),
    );
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the todo example runs end to end in Flutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NativeUIAppHost(app: exampleApps['todo']!())),
    );
    expect(find.text('No todos yet. Add one above!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.text('Buy milk'),
      findsOneWidget,
      reason: 'the row shows it and the field was cleared',
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 completed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('No todos yet. Add one above!'), findsOneWidget);
  });

  testWidgets('the calculator example runs end to end in Flutter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NativeUIAppHost(app: exampleApps['calculator']!())),
    );

    for (final key in ['7', '+', '5', '=']) {
      await tester.tap(find.text(key).first);
      await tester.pumpAndSettle();
    }

    expect(find.text('12'), findsOneWidget);
  });
}
