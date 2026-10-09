@TestOn('browser')
/// A screen that reads right to left, in the DOM.
///
/// The renderer's part is one attribute - `dir` on its root - and keeping what
/// names a side on that side. What the attribute then turns is the browser's
/// and the stylesheet's doing, so the tests that measure where something
/// landed bring the stylesheet's rules with them (see
/// `support/direction_rules.dart`, which a VM test holds to the shipped file).
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:dart_not_native/widgets.dart' as w;
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/direction_rules.dart';
import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late web.Element sheet;
  late WebUIRenderer renderer;

  setUp(() {
    sheet = web.document.createElement('style')
      ..textContent = directionStylesheet();
    web.document.head!.appendChild(sheet);
    root = mountRoot();
    root.style.width = '400px';
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() {
    root.remove();
    sheet.remove();
  });

  WidgetNode rtl(WidgetNode tree) => UIBuilder.withTextDirection(tree, 'rtl');

  /// The element whose own text is [text].
  web.Element withText(String text) {
    final all = root.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      final element = all.item(i)! as web.Element;
      if (element.children.length == 0 && element.textContent == text) {
        return element;
      }
    }
    fail('nothing on screen says "$text"');
  }

  double left(web.Element element) => element.getBoundingClientRect().left;

  WidgetNode screen() => node('Scaffold', {}, [
    node(
      'AppBar',
      {'title': 'Inbox', 'leading': 'back', 'leadingEventId': 'back'},
      [
        node('IconButton', {'icon': 'search', 'eventId': 'search', 'id': 'act'}),
      ],
    ),
    UIBuilder.row(
      mainAxisSize: 'max',
      children: [
        UIBuilder.text('first'),
        UIBuilder.expanded(child: UIBuilder.text('middle')),
        UIBuilder.text('last'),
      ],
    ),
  ]);

  group('dir on the mount root', () {
    test('a tree that says nothing leaves the root alone', () async {
      await renderer.render(screen());
      expect(root.hasAttribute('dir'), isFalse);
    });

    test('rtl on the tree\'s root is dir="rtl" on the mount root', () async {
      await renderer.render(rtl(screen()));
      expect(root.getAttribute('dir'), 'rtl');
      // The prop is the screen's, not the node's: nothing below repeats it.
      expect(root.querySelectorAll('[dir]').length, 0);
    });

    test('it follows the tree from one render to the next', () async {
      await renderer.render(screen());
      await renderer.render(rtl(screen()));
      expect(root.getAttribute('dir'), 'rtl');
      await renderer.render(screen());
      expect(root.hasAttribute('dir'), isFalse);
    });

    test('turning the screen round rebuilds nothing', () async {
      await renderer.render(screen());
      final scaffold = root.firstElementChild;
      final title = withText('Inbox');
      final built = renderer.debugCreateCount;

      await renderer.render(rtl(screen()));

      expect(root.firstElementChild, same(scaffold));
      expect(withText('Inbox'), same(title));
      expect(renderer.debugCreateCount, built);
    });

    test('whatever the root node is - an overlay as much as a scaffold',
        () async {
      await renderer.render(rtl(UIBuilder.overlay(child: screen())));
      expect(root.getAttribute('dir'), 'rtl');
    });
  });

  group('an app bar', () {
    web.Element leading() => root.querySelector('.dnn-appbar__leading')!;

    test('reads leading, title, actions from the left', () async {
      await renderer.render(screen());
      expect(left(leading()), lessThan(left(withText('Inbox'))));
      expect(
        left(withText('Inbox')),
        lessThan(left(web.document.getElementById('act')!)),
      );
    });

    test('and from the right in rtl', () async {
      await renderer.render(rtl(screen()));
      expect(left(leading()), greaterThan(left(withText('Inbox'))));
      expect(
        left(withText('Inbox')),
        greaterThan(left(web.document.getElementById('act')!)),
      );
      // The actions are at the far end, not just after the title.
      expect(left(web.document.getElementById('act')!), lessThan(60));
      expect(left(leading()), greaterThan(340));
    });

    test('the back arrow is turned round, and only in rtl', () async {
      await renderer.render(screen());
      String transform() =>
          web.window.getComputedStyle(leading()).getPropertyValue('transform');
      expect(leading().classList.contains('dnn-appbar__leading--back'), isTrue);
      expect(transform(), 'none');

      await renderer.render(rtl(screen()));
      expect(transform(), 'matrix(-1, 0, 0, 1, 0, 0)');
    });

    test('a close button has no direction to turn', () async {
      await renderer.render(
        rtl(
          node('AppBar', {
            'title': 'Edit',
            'leading': 'close',
            'leadingEventId': 'x',
          }),
        ),
      );
      expect(
        leading().classList.contains('dnn-appbar__leading--back'),
        isFalse,
      );
    });
  });

  group('a row', () {
    test('runs from the right in rtl, the first child rightmost', () async {
      await renderer.render(rtl(screen()));
      expect(left(withText('first')), greaterThan(left(withText('middle'))));
      expect(left(withText('middle')), greaterThan(left(withText('last'))));
    });
  });

  group('a list tile from the widget layer', () {
    final locale = w.ValueNotifier<w.Locale>(const w.Locale('en'));
    setUp(() => locale.value = const w.Locale('en'));

    w.Widget app() => w.ValueListenableBuilder<w.Locale>(
      valueListenable: locale,
      builder: (context, value, _) => w.MaterialApp(
        locale: value,
        supportedLocales: const [w.Locale('en'), w.Locale('ar')],
        home: const w.ListTile(
          leading: w.Text('L'),
          title: w.Text('Title'),
          trailing: w.Text('R'),
        ),
      ),
    );

    test('puts leading on the left and trailing on the right in English',
        () async {
      final mounted = w.hostApp(app())..mount(renderer);
      addTearDown(mounted.unmount);
      await renderer.render(mounted.build());

      expect(left(withText('L')), lessThan(left(withText('Title'))));
      expect(left(withText('Title')), lessThan(left(withText('R'))));
    });

    test('and the other way round once the app switches to Arabic', () async {
      final mounted = w.hostApp(app())..mount(renderer);
      addTearDown(mounted.unmount);
      await renderer.render(mounted.build());
      final tile = withText('Title');

      locale.value = const w.Locale('ar');
      await renderer.render(mounted.build());

      expect(root.getAttribute('dir'), 'rtl');
      expect(left(withText('L')), greaterThan(left(withText('Title'))));
      expect(left(withText('Title')), greaterThan(left(withText('R'))));
      // The same tile, turned - a language switch does not rebuild the page.
      expect(withText('Title'), same(tile));
    });
  });

  group('what names a side stays on that side', () {
    web.HTMLElement first(String type) =>
        root.querySelector('[data-type="$type"]')! as web.HTMLElement;

    test('a box\'s alignment is the left and the right', () async {
      await renderer.render(
        rtl(
          node(
            'Box',
            {
              'width': 200.0,
              'height': 40.0,
              'alignment': [-1.0, 0.0],
              'id': 'box',
            },
            [UIBuilder.text('x')],
          ),
        ),
      );

      expect(first('Box').style.getPropertyValue('justify-items'), 'left');
      expect(
        left(withText('x')),
        closeTo(left(web.document.getElementById('box')!), 0.5),
      );
    });

    test('a box\'s padding is left, top, right, bottom', () async {
      await renderer.render(
        rtl(
          node('Box', {
            'padding': [40.0, 1.0, 2.0, 3.0],
          }, [UIBuilder.text('x')]),
        ),
      );
      expect(first('Box').style.getPropertyValue('padding'), '1px 2px 3px 40px');
    });

    test('a Positioned left is the left', () async {
      await renderer.render(
        rtl(
          node('Stack', {}, [
            node('Positioned', {'left': 12.0, 'top': 0.0}, [
              UIBuilder.text('x'),
            ]),
          ]),
        ),
      );
      expect(first('Positioned').style.getPropertyValue('left'), '12px');
      expect(first('Positioned').style.getPropertyValue('right'), '');
    });

    test('a stack that states an alignment names a side', () async {
      await renderer.render(
        rtl(
          node('Stack', {
            'alignment': [1.0, -1.0],
          }, [UIBuilder.text('x')]),
        ),
      );
      expect(first('Stack').style.getPropertyValue('justify-items'), 'right');
    });

    test('and one that states none starts at the start', () async {
      await renderer.render(rtl(node('Stack', {}, [UIBuilder.text('x')])));
      expect(first('Stack').style.getPropertyValue('justify-items'), 'start');
    });

    test('textAlign left is left; no textAlign is the start', () async {
      await renderer.render(
        rtl(
          UIBuilder.column(
            crossAxisAlignment: 'stretch',
            children: [
              node('Text', {'content': 'said', 'textAlign': 'left'}),
              UIBuilder.text('unsaid'),
            ],
          ),
        ),
      );

      String align(String text) => web.window
          .getComputedStyle(withText(text))
          .getPropertyValue('text-align');
      expect(align('said'), 'left');
      expect(align('unsaid'), 'start');
    });
  });

  test('a floating button sits in the end corner', () async {
    WidgetNode tree() => node('Scaffold', {}, [
      UIBuilder.text('body'),
      node('FloatingActionButton', {
        'icon': 'add',
        'eventId': 'fab',
        'id': 'fab',
      }),
    ]);
    web.DOMRect fab() =>
        web.document.getElementById('fab')!.getBoundingClientRect();

    await renderer.render(tree());
    expect(fab().left, greaterThan(web.window.innerWidth / 2));

    await renderer.render(rtl(tree()));
    expect(fab().right, lessThan(web.window.innerWidth / 2));
  });
}
