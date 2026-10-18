@TestOn('browser')
/// A box that follows a scroller (`scrollLink`) is put where its table says
/// on the browser's own `scroll` event, before the app hears anything.
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

  test('a header shrinks and fades as the scroller moves', () async {
    final header = WidgetNode(
      type: 'Box',
      props: {
        'height': 120.0,
        'color': '#2196f3',
        'scrollLink': {
          'source': 'scroll0',
          'at': [0.0, 64.0],
          'height': [120.0, 56.0],
          'opacity': [0.0, 1.0],
          'dy': [0.0, -10.0],
          'color': ['#ff000000', '#ff0000ff'],
        },
      },
      children: [UIBuilder.text('title')],
    );
    final list = WidgetNode(
      type: 'Scroll',
      props: {'scrollLinkSource': 'scroll0'},
      children: [
        UIBuilder.column(
          children: [
            for (var i = 0; i < 50; i++)
              UIBuilder.box(height: 40, child: UIBuilder.text('row $i')),
          ],
        ),
      ],
    );
    await renderer.render(
      UIBuilder.column(children: [header, list]),
    );
    final box = root.querySelector('[data-type="Box"]')! as web.HTMLElement;
    final viewport = root.querySelector('.dnn-scroll')! as web.HTMLElement;
    expect(viewport.scrollHeight, greaterThan(viewport.clientHeight + 64));

    viewport.scrollTop = 32;
    viewport.dispatchEvent(web.Event('scroll'));
    expect(box.style.getPropertyValue('height'), '88px');
    expect(box.style.getPropertyValue('opacity'), '0.5');
    expect(box.style.getPropertyValue('transform'), contains('-5px'));
    // Half way from black to blue.
    expect(box.style.getPropertyValue('background-color'), 'rgb(0, 0, 128)');

    viewport.scrollTop = 200;
    viewport.dispatchEvent(web.Event('scroll'));
    expect(box.style.getPropertyValue('height'), '56px');
    await Future<void>.delayed(Duration.zero);
  });
}

