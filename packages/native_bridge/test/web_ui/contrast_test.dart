@TestOn('browser')
/// Text over a colour the app chose, in a real browser.
///
/// The rule itself is `src/contrast.dart` and its own test; this is about
/// where the renderer applies it - and, for a card, that the children inherit
/// it rather than each being painted.
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

  web.HTMLElement find(String selector) =>
      root.querySelector(selector) as web.HTMLElement;

  /// What the browser resolves, which is the only answer that matters: an
  /// inherited colour never appears in an element's own style.
  String colorOf(String selector) =>
      web.window.getComputedStyle(find(selector)).color;

  /// `#212121` and `#ffffff` as the browser writes them back.
  const dark = 'rgb(33, 33, 33)';
  const light = 'rgb(255, 255, 255)';

  test('a pale card carries dark text, a dark card white', () async {
    await renderer.render(
      DSCard.filled(
        title: 'Title',
        backgroundColor: '#ffeb3b',
        content: UIBuilder.text('Body', id: 'body'),
      ),
    );

    expect(colorOf('[data-type="Card"]'), dark);
    expect(colorOf('#body'), dark);

    await renderer.render(
      DSCard.filled(
        title: 'Title',
        backgroundColor: '#1a237e',
        content: UIBuilder.text('Body', id: 'body'),
      ),
    );

    expect(colorOf('[data-type="Card"]'), light);
    expect(colorOf('#body'), light);
  });

  test('a card the app did not colour is left to the theme', () async {
    await renderer.render(
      DSCard.filled(content: UIBuilder.text('Body', id: 'body')),
    );

    expect(
      find('[data-type="Card"]').style.getPropertyValue('color'),
      '',
    );
  });

  test('text that states its own colour keeps it', () async {
    await renderer.render(
      DSCard.filled(
        backgroundColor: '#1a237e',
        content: UIBuilder.text('Body', id: 'body', color: '#ff0000'),
      ),
    );

    expect(colorOf('#body'), 'rgb(255, 0, 0)');
  });

  test('a button, a badge and an app bar read over their own fill', () async {
    await renderer.render(
      UIBuilder.column(
        children: [
          AndroidUIBuilder.appBar(title: 'Bar', backgroundColor: '#ffeb3b'),
          UIBuilder.button(label: 'Go', eventId: 'go', color: '#ffeb3b'),
          DSBadge.solid(label: 'New', color: '#ffeb3b'),
        ],
      ),
    );

    expect(colorOf('[data-type="AppBar"]'), dark);
    expect(colorOf('[data-type="Button"]'), dark);
    expect(colorOf('[data-type="Badge"]'), dark);
  });

  test('an animated box hands its colour to what is inside it', () async {
    await renderer.render(
      UIBuilder.animatedContainer(
        color: '#1a237e',
        child: UIBuilder.text('Inside', id: 'inside'),
      ),
    );

    expect(colorOf('#inside'), light);
    expect(colorOf('[data-type="AnimatedContainer"]'), light);
  });
}
