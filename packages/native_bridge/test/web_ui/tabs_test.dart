@TestOn('browser')
/// The tab strip in a real browser: what it draws, what it announces, and what
/// a click reports.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<int> taps;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    taps = [];
    renderer.onEvent('folders', (data) => taps.add(data['index'] as int));
  });
  tearDown(() => root.remove());

  web.Element bar() => root.querySelector('[data-type="Tabs"]')!;
  List<web.Element> tabs() => [
        for (var i = 0; i < bar().children.length; i++) bar().children.item(i)!,
      ];

  Future<void> show(int selected) => renderer.render(UIBuilder.tabs(
        eventId: 'folders',
        tabs: const ['All', 'Unread', 'Archived'],
        selectedIndex: selected,
      ));

  test('is a row of buttons, one marked selected', () async {
    await show(1);

    expect(tabs().map((t) => t.textContent), ['All', 'Unread', 'Archived']);
    expect(
      tabs().map((t) => t.getAttribute('aria-selected')),
      ['false', 'true', 'false'],
    );
    expect(tabs()[1].classList.contains('dnn-tabs__tab--selected'), isTrue);
  });

  test('announces itself as a tab list, so it is reached as one', () async {
    await show(0);

    expect(bar().getAttribute('role'), 'tablist');
    expect(tabs().every((t) => t.getAttribute('role') == 'tab'), isTrue);
    // Real buttons, so they are focusable and answer to the keyboard without
    // anything else being wired.
    expect(tabs().every((t) => t.tagName.toLowerCase() == 'button'), isTrue);
  });

  test('a click reports which tab, and nothing else changes', () async {
    await show(0);

    (tabs()[2] as web.HTMLElement).click();

    expect(taps, [2]);
    // The renderer keeps no selection of its own: the tree still says 0 until
    // the app says otherwise.
    expect(tabs()[0].getAttribute('aria-selected'), 'true');
  });

  test('the app moving the selection moves the marks', () async {
    await show(0);

    await show(2);

    expect(
      tabs().map((t) => t.getAttribute('aria-selected')),
      ['false', 'false', 'true'],
    );
  });
}
