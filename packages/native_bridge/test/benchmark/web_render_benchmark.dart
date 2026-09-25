@TestOn('browser')
/// Measures what the web renderer costs per render.
///
/// Run with:
///   flutter test --platform chrome benchmark/web_render_benchmark.dart
///
/// The cases are the ones an app actually hits: a first paint, a re-render
/// where nothing changed, a one-character text change, and a list that grows
/// or shrinks. Numbers are machine-dependent - run before and after a change
/// and compare.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'bench.dart';
import 'scenes.dart';

void main() {
  test('web renderer', () async {
    final root = web.document.createElement('div');
    web.document.body!.appendChild(root);
    final renderer = WebUIRenderer(root: root, animations: false);
    // A second, unbatched renderer measured with the synchronous harness, so
    // the reconciliation algorithm can be compared against an earlier build
    // without the batching changing what the timer sees.
    final syncRoot = web.document.createElement('div');
    web.document.body!.appendChild(syncRoot);
    final syncRenderer = WebUIRenderer(
      root: syncRoot,
      animations: false,
      batched: false,
    );

    final todo = todoScene(items: 50);
    final components = componentsScene();
    // ignore: avoid_print
    print(
      '\nscene sizes: todo(50 items) = ${countNodes(todo)} nodes, '
      'components = ${countNodes(components)} nodes',
    );

    final bench = Bench(iterations: 100, warmup: 10);

    // Every case awaits the render, so the timing covers the DOM work and not
    // just the call that queues it.
    await bench.runAsync('first paint, todo 50', () async {
      while (root.firstChild != null) {
        root.removeChild(root.firstChild!);
      }
      renderer.forgetRenderedTree();
      await renderer.render(todo);
    });

    await renderer.render(todo);
    await bench.runAsync(
      're-render, nothing changed',
      () => renderer.render(todo),
    );

    var toggle = false;
    await bench.runAsync('re-render, one text changed', () {
      toggle = !toggle;
      return renderer.render(todoScene(items: 50, completed: toggle ? 1 : 2));
    });

    var grow = false;
    await bench.runAsync('re-render, list grows and shrinks', () {
      grow = !grow;
      return renderer.render(todoScene(items: grow ? 50 : 49));
    });

    await renderer.render(components);
    await bench.runAsync(
      're-render, components',
      () => renderer.render(components),
    );

    var burst = 0;
    await bench.runAsync('burst: 5 renders in one tick', () {
      // Only the last tree reaches the DOM: this is the cost an app pays when
      // a handler changes state several times before yielding.
      Future<RenderError?>? last;
      for (var i = 0; i < 5; i++) {
        burst = (burst + 1) % 5;
        last = renderer.render(todoScene(items: 50, completed: burst));
      }
      return last!;
    });

    bench.report('web renderer (batched, awaited)');

    final syncBench = Bench(iterations: 100, warmup: 10);
    syncRenderer.render(todo);
    syncBench.run(
      're-render, nothing changed',
      () => syncRenderer.render(todo),
    );
    var syncToggle = false;
    syncBench.run('re-render, one text changed', () {
      syncToggle = !syncToggle;
      syncRenderer.render(todoScene(items: 50, completed: syncToggle ? 1 : 2));
    });
    var syncGrow = false;
    syncBench.run('re-render, list grows and shrinks', () {
      syncGrow = !syncGrow;
      syncRenderer.render(todoScene(items: syncGrow ? 50 : 49));
    });
    // A list that changes at the front: the case keyed reconciliation exists
    // for, since every row after the change shifts position.
    var prepended = false;
    syncBench.run('front insert, rows unkeyed', () {
      prepended = !prepended;
      syncRenderer.render(todoScene(items: 50, firstId: prepended ? 0 : 1));
    });

    syncRenderer.render(todoScene(items: 50, keyedRows: true));
    var prependedKeyed = false;
    syncBench.run('front insert, rows keyed by id', () {
      prependedKeyed = !prependedKeyed;
      syncRenderer.render(
        todoScene(items: 50, firstId: prependedKeyed ? 0 : 1, keyedRows: true),
      );
    });
    syncBench.run('build the tree only', () => todoScene(items: 50));
    syncBench.report('web renderer (unbatched, synchronous harness)');
    syncRoot.remove();

    // Let any queued work settle so the numbers above are the whole cost.
    await Future<void>.delayed(Duration.zero);
    root.remove();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
