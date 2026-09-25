/// Measures the platform-neutral half: building the widget tree, serialising
/// it, and painting it with Flutter.
///
/// Run with:
///   flutter test benchmark/tree_build_benchmark.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench.dart';
import 'scenes.dart';

/// Renders the todo scene through the app shell, as a real app would.
class _TodoApp extends NativeUIApp {
  int completed = 0;

  @override
  void init() => on('toggle', (_) => setState(() => completed++));

  @override
  WidgetNode build() => todoScene(items: 50, completed: completed);
}

void main() {
  test('tree building and serialisation', () {
    final todo = todoScene(items: 50);
    final components = componentsScene();
    // ignore: avoid_print
    print(
      '\nscene sizes: todo(50 items) = ${countNodes(todo)} nodes, '
      'components = ${countNodes(components)} nodes',
    );

    final bench = Bench(iterations: 500, warmup: 50);

    bench.run('build tree, todo 50', () => todoScene(items: 50));
    bench.run('build tree, components', () => componentsScene());
    bench.run('toJson, todo 50', () => todo.toJson());
    bench.run('toJsonString, todo 50', () => todo.toJsonString());
    // What the old web signature cost per node, for reference.
    bench.run('props.toString() over the tree', () {
      for (final node in _walk(todo)) {
        node.props.toString();
      }
    });

    bench.run('mount + render through NativeUIApp', () {
      final app = _TodoApp()..mount(InMemoryRenderer());
      app.setState(() => app.completed = 1);
    });

    bench.report('tree');
  });

  testWidgets('flutter renderer', (tester) async {
    final renderer = FlutterUIRenderer();
    final bench = Bench(iterations: 30, warmup: 5);

    await renderer.render(todoScene(items: 50));
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );

    var completed = 0;
    await bench.runAsync('render + pump, todo 50', () async {
      completed = completed == 1 ? 2 : 1;
      await renderer.render(todoScene(items: 50, completed: completed));
      await tester.pump();
    });

    bench.report('flutter renderer');
    renderer.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Iterable<WidgetNode> _walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _walk(child);
  }
}
