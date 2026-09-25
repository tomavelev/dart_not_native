@TestOn('browser')
/// What the web renderer's two promises cost, as ratios.
///
/// The benchmark next door (`test/benchmark/web_render_benchmark.dart`) prints
/// the timings; a browser on a busy CI runner makes those useless as a gate.
/// These are the two claims the renderer makes about its own work, stated so
/// that only a change in *behaviour* can break them:
///
/// - it patches rather than rebuilds: the elements survive a re-render, and a
///   tree that did not change costs a fraction of drawing one;
/// - it coalesces the renders of one tick, so five state changes before
///   yielding cost about one render, not five.
///
/// Both would otherwise fail silently: the screen still looks right when the
/// reconciler falls back to rebuilding everything, and when the scheduler
/// stops batching.
///
/// Run with: flutter test --platform chrome
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import '../benchmark/bench.dart';
import '../benchmark/scenes.dart';

void main() {
  late web.Element root;
  late WebUIRenderer renderer;

  setUp(() {
    root = web.document.createElement('div');
    web.document.body!.appendChild(root);
    renderer = WebUIRenderer(root: root, animations: false);
  });

  tearDown(() => root.remove());

  /// The median of [iterations] awaited runs, in microseconds.
  Future<int> median(int iterations, Future<void> Function() body) async {
    final bench = Bench(iterations: iterations, warmup: iterations ~/ 4);
    await bench.runAsync('x', body);
    return bench.results.single.median;
  }

  test('re-rendering an unchanged tree costs a fraction of drawing it', () async {
    // The clearest signal the reconciler gives: nothing changed, so nothing
    // should be built. A renderer that started rebuilding would pay the full
    // paint here. (A *changed* row is a much narrower margin - most of a
    // re-render is walking and comparing the tree rather than touching the
    // DOM - so that ratio is recorded in BASELINE.md rather than asserted.)
    final tree = todoScene(items: 50, completed: 1);
    await renderer.render(tree);

    final unchanged = await median(40, () => renderer.render(tree));
    final paint = await median(40, () async {
      while (root.firstChild != null) {
        root.removeChild(root.firstChild!);
      }
      await WebUIRenderer(root: root, animations: false).render(tree);
    });

    // Measured at about 7x cheaper; a third is the line, which leaves room for
    // a busy machine and none for a renderer that stopped reusing anything.
    expect(
      unchanged * 3,
      lessThan(paint),
      reason: 'an unchanged re-render took ${unchanged}us '
          'against a full paint of ${paint}us',
    );
  });

  test('a re-render keeps the elements it already has', () {
    // The cost above is the consequence; this is the behaviour itself, and it
    // holds however fast the machine is. Rebuilding would replace every row -
    // and take the focus, scroll position and selection inside them with it.
    return () async {
      await renderer.render(todoScene(items: 50, completed: 1));
      final rows = root.querySelectorAll('[data-type="Row"]');
      final first = rows.item(0);
      final last = rows.item(rows.length - 1);

      await renderer.render(todoScene(items: 50, completed: 2));

      final after = root.querySelectorAll('[data-type="Row"]');
      expect(after.length, rows.length);
      expect(after.item(0), same(first));
      expect(after.item(after.length - 1), same(last));
    }();
  });

  test('five renders in one tick cost about one', () async {
    final trees = [
      for (var completed = 0; completed < 5; completed++)
        todoScene(items: 50, completed: completed),
    ];

    var index = 0;
    final single = await median(40, () {
      index = (index + 1) % trees.length;
      return renderer.render(trees[index]);
    });

    final burst = await median(40, () {
      Future<RenderError?>? last;
      for (var i = 0; i < trees.length; i++) {
        index = (index + 1) % trees.length;
        last = renderer.render(trees[index]);
      }
      return last!;
    });

    // Only the last tree of a tick can be visible, so only it is drawn. Five
    // separate renders would be five times the DOM work; the ceiling is three,
    // which allows for the four trees still being built and compared.
    expect(
      burst,
      lessThan(single * 3),
      reason: 'a burst of five took ${burst}us against ${single}us for one',
    );
  });
}
