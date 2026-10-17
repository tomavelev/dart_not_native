@TestOn('browser')
/// A box that is a `Focus`: a stop for the Tab key that says when focus
/// comes into it and leaves it, and takes focus when asked.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<bool> said;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root);
    said = [];
    renderer.onEvent('f', (data) => said.add(data['focused'] == true));
  });
  tearDown(() => root.remove());

  WidgetNode focus({
    int? version,
    bool? requested,
    bool passedOver = false,
  }) {
    final box = UIBuilder.box(
      child: UIBuilder.button(label: 'inside', eventId: 'b'),
    );
    return UIBuilder.column(
      children: [
        WidgetNode(
          type: box.type,
          props: {
            ...box.props,
            'focusEventId': 'f',
            'focusable': true,
            if (passedOver) 'focusSkip': true,
            'focusVersion': ?version,
            'focusRequested': ?requested,
          },
          children: box.children,
        ),
        UIBuilder.button(label: 'outside', eventId: 'o'),
      ],
    );
  }

  web.HTMLElement box() =>
      root.querySelector('.dnn-focus')! as web.HTMLElement;
  web.HTMLElement button(String label) {
    final all = root.querySelectorAll('button');
    for (var i = 0; i < all.length; i++) {
      final b = all.item(i)! as web.HTMLElement;
      if (b.textContent?.trim() == label) return b;
    }
    throw StateError('no $label');
  }

  test('is a stop for the Tab key, or not with focusSkip', () async {
    await renderer.render(focus());
    expect(box().tabIndex, 0);
    await renderer.render(focus(passedOver: true));
    expect(box().tabIndex, -1);
  });

  test('says when focus comes in, and only when it leaves altogether',
      () async {
    await renderer.render(focus());
    box().focus();
    button('inside').focus();
    button('outside').focus();
    await pumpEventQueue();
    expect(said, [true, false]);
  });

  test('takes focus when asked, and gives it up', () async {
    await renderer.render(focus());
    await renderer.render(focus(version: 1));
    await pumpEventQueue();
    expect(web.document.activeElement, box());
    await renderer.render(focus(version: 2, requested: false));
    await pumpEventQueue();
    expect(web.document.activeElement, isNot(box()));
    expect(said, [true, false]);
  });
}
