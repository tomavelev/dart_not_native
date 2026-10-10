/// Tests for the todo example: list logic plus the mounted app.
library;

import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/todo_example_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

void main() {
  group('TodoLogic', () {
    test('adds trimmed titles and ignores blank ones', () {
      final logic = TodoLogic();

      expect(logic.add('  Buy milk  '), isTrue);
      expect(logic.add(''), isFalse);
      expect(logic.add('   '), isFalse);

      expect(logic.todos.map((t) => t.title), ['Buy milk']);
    });

    test('gives every todo its own id', () {
      final logic = TodoLogic()
        ..add('a')
        ..add('b');

      expect(logic.todos.map((t) => t.id), [1, 2]);
    });

    test('toggle flips completion and updates the count', () {
      final logic = TodoLogic()..add('a');

      logic.toggle(1);
      expect(logic.todos.single.completed, isTrue);
      expect(logic.completedCount, 1);

      logic.toggle(1);
      expect(logic.completedCount, 0);
    });

    test('delete removes only the matching todo', () {
      final logic = TodoLogic()
        ..add('a')
        ..add('b');

      logic.delete(1);

      expect(logic.todos.map((t) => t.title), ['b']);
    });

    test('deleting a missing id is a no-op', () {
      final logic = TodoLogic()..add('a');

      logic.delete(99);

      expect(logic.todos, hasLength(1));
    });
  });

  group('TodoApp', () {
    late AppTester tester;

    setUp(() => tester = AppTester.mount(hostApp(const TodoApp())));

    test('starts with an empty-state message and no rows', () {
      expect(tester.hasText('No todos yet. Add one above!'), isTrue);
      expect(tester.find('todo_summary'), isNull);
    });

    test('typing and tapping add creates a row and clears the field', () async {
      await tester.typeInto('new_todo', 'Buy milk');
      await tester.tap('add');

      expect(tester.text('todo_1_title'), 'Buy milk');
      expect(tester.text('todo_summary'), '0 of 1 completed');
      final field = tester.ofType('TextField').single;
      expect(
        field.props['initialValue'],
        '',
        reason: 'the draft is cleared after adding',
      );
    });

    test('pressing Enter in the field adds the todo', () async {
      await tester.submitInto('new_todo', 'From keyboard');

      expect(tester.text('todo_1_title'), 'From keyboard');
    });

    test('adding a blank todo does nothing', () async {
      await tester.typeInto('new_todo', '   ');
      await tester.tap('add');

      expect(tester.hasText('No todos yet. Add one above!'), isTrue);
    });

    test(
      'checking a todo strikes it through and updates the summary',
      () async {
        await tester.submitInto('new_todo', 'Buy milk');

        await tester.toggle('todo_1_done');

        expect(tester.get('todo_1_title').props['decoration'], 'lineThrough');
        expect(tester.get('todo_1_done').props['checked'], isTrue);
        expect(tester.text('todo_summary'), '1 of 1 completed');
      },
    );

    test('unchecking restores the row', () async {
      await tester.submitInto('new_todo', 'Buy milk');
      await tester.toggle('todo_1_done');

      await tester.toggle('todo_1_done');

      expect(tester.get('todo_1_title').props['decoration'], isNull);
      expect(tester.text('todo_summary'), '0 of 1 completed');
    });

    test('deleting the last todo brings back the empty state', () async {
      await tester.submitInto('new_todo', 'Buy milk');

      await tester.tap('todo_1_delete');

      expect(tester.hasText('No todos yet. Add one above!'), isTrue);
    });

    test('every row carries stable ids for the e2e flows', () async {
      await tester.submitInto('new_todo', 'a');
      await tester.submitInto('new_todo', 'b');

      expect(tester.find('todo_1_title'), isNotNull);
      expect(tester.find('todo_2_title'), isNotNull);
      expect(tester.find('todo_1_done'), isNotNull);
      expect(tester.find('todo_2_done'), isNotNull);
    });

    test('every button and checkbox taps cleanly by its id', () async {
      await tester.submitInto('new_todo', 'a');

      for (final id in ['add', 'todo_1_done', 'todo_1_delete']) {
        expect(tester.eventIdOf(id), isA<String>(), reason: '$id is unwired');
      }
      // Toggling and deleting through their own callbacks runs without a
      // missing handler throwing.
      await tester.toggle('todo_1_done');
      await tester.tap('todo_1_delete');
      expect(tester.hasText('No todos yet. Add one above!'), isTrue);
    });
  });
}
