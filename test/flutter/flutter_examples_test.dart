/// Widget tests for the Flutter-hosted examples.
///
/// Most of the framework renders native UI through a widget tree, but the
/// examples also ship plain Flutter screens for the mobile host - those are
/// ordinary Flutter widgets, so they get ordinary widget tests.
library;

import 'package:dart_not_native/material.dart';
import 'package:dart_not_native_example/examples/todo_example.dart' as todo;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Flutter todo screen', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(home: todo.TodoPage(title: 'My Todos')),
    );

    testWidgets('starts empty', (tester) async {
      await pump(tester);

      expect(find.text('No todos yet. Add one above!'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('adding a todo shows a row and clears the field', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.byTooltip('Add Todo'));
      await tester.pump();

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('No todos yet. Add one above!'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('submitting from the keyboard adds a todo', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'From keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('From keyboard'), findsOneWidget);
    });

    testWidgets('blank input is ignored', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Add Todo'));
      await tester.pump();

      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('checking a todo strikes it through', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.byTooltip('Add Todo'));
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(
        tester.widget<Text>(find.text('Buy milk')).style?.decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('deleting removes the row', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.byTooltip('Add Todo'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pump();

      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('No todos yet. Add one above!'), findsOneWidget);
    });
  });
}
