/// Integration tests: the whole app on a real device or desktop host.
///
/// Run on a connected device or emulator:
///   flutter test integration_test
///   flutter test integration_test -d linux      # desktop host
///   flutter test integration_test -d chrome     # Flutter web host
///
/// The web target of this framework does not run Flutter at all - it renders
/// DOM - so its end-to-end coverage lives in `maestro/web` (real browser,
/// real CSS) and in the browser tests under
/// `packages/native_bridge/test/web_ui`.
library;

import 'package:dart_not_native/material.dart';
import 'package:dart_not_native_example/examples/todo_example.dart' as todo;
import 'package:dart_not_native_example/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('counter host app', () {
    testWidgets('launches and counts up', (tester) async {
      await tester.pumpWidget(const app.MyApp());
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('todo example', () {
    testWidgets('adds, completes and deletes a todo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: todo.TodoPage(title: 'My Todos')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.byTooltip('Add Todo'));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsOneWidget);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      expect(find.text('Buy milk'), findsNothing);
      expect(find.text('No todos yet. Add one above!'), findsOneWidget);
    });
  });
}
