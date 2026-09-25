/// Golden tests for the widget trees the example apps build.
///
/// The framework's output is a serialized tree that native renderers turn
/// into real platform views, so the tree - not a screenshot - is what a
/// golden should pin: a change in any example's layout, labels, ids or event
/// wiring shows up here as a reviewable JSON diff.
///
/// Pixel-level appearance is covered by the Maestro screenshot flows in
/// `maestro/web`, and the DOM markup by the browser goldens in
/// `packages/native_bridge/test/web_ui/dom_golden_test.dart`.
///
/// Regenerate after an intended change with:
///   UPDATE_GOLDENS=1 flutter test test/goldens/tree_golden_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';
import '../support/example_apps.dart';

final bool _update = Platform.environment['UPDATE_GOLDENS'] == '1';
const _encoder = JsonEncoder.withIndent('  ');

File _goldenFile(String name) => File('test/goldens/trees/$name.json');

void expectGolden(WidgetNode tree, String name) {
  final actual = _encoder.convert(tree.toJson());
  final file = _goldenFile(name);

  if (_update) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$actual\n');
    return;
  }

  expect(
    file.existsSync(),
    isTrue,
    reason:
        'Missing golden $name. Create it with '
        'UPDATE_GOLDENS=1 flutter test test/goldens/tree_golden_test.dart',
  );
  expect(
    actual,
    file.readAsStringSync().trimRight(),
    reason:
        'The tree of "$name" changed. Review the diff and, if the change '
        'is intended, regenerate with UPDATE_GOLDENS=1.',
  );
}

void main() {
  group('first frame', () {
    exampleApps.forEach((name, build) {
      test(name, () async {
        final tester = AppTester.mount(build());
        // Examples that load asynchronously settle before the golden is taken.
        await Future<void>.delayed(Duration.zero);

        expectGolden(tester.tree, name);
      });
    });
  });

  group('after interaction', () {
    test('todo with one completed item', () async {
      final tester = AppTester.mount(exampleApps['todo']!());

      await tester.submitInto('new_todo', 'Buy milk');
      await tester.submitInto('new_todo', 'Walk the dog');
      await tester.toggle('todo_1_done');

      expectGolden(tester.tree, 'todo__one_completed');
    });

    test('calculator showing a result', () async {
      final tester = AppTester.mount(exampleApps['calculator']!());

      for (final id in ['key_7', 'key_plus', 'key_5', 'key_equals']) {
        await tester.tap(id);
      }

      expectGolden(tester.tree, 'calculator__result');
    });

    test('routing on a detail screen', () async {
      final tester = AppTester.mount(exampleApps['routing']!());

      await tester.tap('nav_users');
      await tester.tap('user_2');

      expectGolden(tester.tree, 'routing__user_detail');
    });

    test('i18n in Spanish', () async {
      final tester = AppTester.mount(exampleApps['i18n']!());

      await tester.tap('lang_es');

      expectGolden(tester.tree, 'i18n__spanish');
    });

    test('storage after saving both stores', () async {
      final tester = AppTester.mount(exampleApps['storage']!());
      await Future<void>.delayed(Duration.zero);

      await tester.tap('save_regular');
      await tester.tap('save_secure');
      await Future<void>.delayed(Duration.zero);

      expectGolden(tester.tree, 'storage__saved');
    });

    test('inbox confirming a delete from the actions sheet', () async {
      final tester = AppTester.mount(exampleApps['inbox']!());

      await tester.tap('actions_2');
      await tester.tap('sheet_delete');

      expectGolden(tester.tree, 'inbox__confirm_delete');
    });
  });

  test('no golden file is left behind by a removed example', () {
    final expected = {
      ...exampleApps.keys,
      'todo__one_completed',
      'calculator__result',
      'routing__user_detail',
      'i18n__spanish',
      'storage__saved',
      'inbox__confirm_delete',
    }.map((name) => '$name.json').toSet();

    final directory = Directory('test/goldens/trees');
    final present = directory
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();

    expect(present, expected);
  });
}
