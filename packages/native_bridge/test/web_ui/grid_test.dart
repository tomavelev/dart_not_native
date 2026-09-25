@TestOn('browser')
/// The grid in a real browser: CSS grid, its gaps and its cell shape.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  web.HTMLElement grid() =>
      root.querySelector('[data-type="GridView"]') as web.HTMLElement;

  test('is a CSS grid of equal columns', () async {
    await renderer.render(UIBuilder.grid(
      crossAxisCount: 3,
      spacing: 4,
      runSpacing: 8,
      children: [for (var i = 0; i < 5; i++) UIBuilder.text('$i')],
    ));

    expect(grid().style.getPropertyValue('grid-template-columns'),
        'repeat(3, 1fr)');
    expect(grid().style.getPropertyValue('column-gap'), '4px');
    expect(grid().style.getPropertyValue('row-gap'), '8px');
    expect(grid().children.length, 5);
  });

  test('the cell ratio reaches the cells, not the grid', () async {
    await renderer.render(UIBuilder.grid(
      crossAxisCount: 2,
      childAspectRatio: 1.5,
      children: [UIBuilder.text('a'), UIBuilder.text('b')],
    ));

    // The grid declares it once and the stylesheet gives it to every child, so
    // the rows line up whatever is inside them.
    expect(grid().style.getPropertyValue('--dnn-grid-ratio'), '1.5');
  });

  test('a grid re-renders in place rather than being rebuilt', () async {
    WidgetNode tree(String suffix) => UIBuilder.grid(
          crossAxisCount: 2,
          children: [
            UIBuilder.text('a$suffix', id: 'a'),
            UIBuilder.text('b$suffix', id: 'b'),
          ],
        );
    await renderer.render(tree(''));
    final before = grid();

    await renderer.render(tree('!'));

    // The grid element survives; its cells are text, which the reconciler
    // redraws by replacing - the same as any other changed Text on web.
    expect(grid(), same(before));
    expect(grid().children.length, 2);
    expect(grid().children.item(0)!.textContent, 'a!');
  });
}
