@TestOn('browser')
/// A keyed element moved among its siblings keeps the scroll of every
/// scroller in it. A browser starts an element that is taken out and put
/// back scrolled to the top, so a list on a page that slid back into place
/// beside another - a tab returned to - came back at its first row.
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
    // The stylesheet's rule, which a test page does not load.
    final sheet = web.document.createElement('style')
      ..textContent = '.dnn-scroll { height: 200px; overflow: auto; }';
    web.document.head!.appendChild(sheet);
    addTearDown(() => sheet.remove());
  });
  tearDown(() => root.remove());

  WidgetNode page(String id) => UIBuilder.box(
    height: 200,
    id: id,
    child: UIBuilder.scroll(
      child: UIBuilder.column(
        children: [
          for (var i = 0; i < 50; i++)
            UIBuilder.box(height: 40, child: UIBuilder.text('$id $i')),
        ],
      ),
    ),
  );

  web.Element scroller(String id) =>
      web.document.getElementById(id)!.querySelector('.dnn-scroll')!;

  test('a page moved in front of another keeps its list where it was',
      () async {
    await renderer.render(
      UIBuilder.stack(children: [page('other'), page('list')]),
    );
    scroller('list').scrollTop = 600;
    expect(scroller('list').scrollTop, 600);

    await renderer.render(UIBuilder.stack(children: [page('list')]));

    expect(scroller('list').scrollTop, 600);
  });
}
