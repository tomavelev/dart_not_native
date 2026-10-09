@TestOn('browser')
/// The frame of a screen: scaffold, app bar, bottom bar, bottom navigation
/// and the floating button.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/src/icon_data.dart';
import 'package:dart_not_native/src/icons.dart';
import 'package:dart_not_native/web_ui/kits/materialize_kit.dart';
import 'package:dart_not_native/web_ui/kits/mdl_kit.dart';
import 'package:dart_not_native/web_ui/style_kit.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

const _kits = <WebStyleKit>[MdlKit(), MaterializeKit(), PlainKit()];

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  web.HTMLElement of(String type) =>
      root.querySelector('[data-type="$type"]')! as web.HTMLElement;

  /// What draws [icon]: the character at its codepoint.
  String glyph(IconData icon) => String.fromCharCode(icon.codePoint);

  final navItems = [
    (label: 'Home', icon: 0xe88a, selectedIcon: 0xe88b),
    (label: 'Search', icon: 0xe8b6, selectedIcon: null),
    (label: 'Settings', icon: 0xe8b8, selectedIcon: null),
  ];

  group('a scaffold', () {
    test('holds app bar, body, button and bottom bar, each by its type',
        () async {
      await renderer.render(
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'Demo'),
          body: UIBuilder.text('Body'),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'Add',
            eventId: 'add',
          ),
          bottomBar: UIBuilder.bottomBar(child: UIBuilder.text('Bar')),
        ),
      );

      expect(childTypes(of('Scaffold')), [
        'AppBar',
        'Text',
        'FloatingActionButton',
        'BottomBar',
      ]);
      expect(of('BottomBar').className, 'dnn-bottombar');
      expect(of('BottomBar').textContent, 'Bar');
    });

    test('bodyScrolls: false and safeArea: false are classes', () async {
      await renderer.render(
        UIBuilder.scaffold(
          body: UIBuilder.text('Body'),
          bodyScrolls: false,
          safeArea: false,
        ),
      );

      expect(of('Scaffold').classList.contains('dnn-scaffold--fixed'), isTrue);
      expect(of('Scaffold').classList.contains('dnn-scaffold--edge'), isTrue);
    });

    test('a background colours the screen, and the text over it', () async {
      await renderer.render(
        UIBuilder.scaffold(
          body: UIBuilder.text('Body'),
          backgroundColor: '#ff101010',
        ),
      );

      final style = of('Scaffold').style;
      expect(style.getPropertyValue('background'), 'rgb(16, 16, 16)');
      expect(style.getPropertyValue('color'), 'rgb(255, 255, 255)');
    });

    test('changing its props keeps the screen it holds', () async {
      WidgetNode screen({String? background}) => UIBuilder.scaffold(
        body: UIBuilder.textField(hint: 'Name', eventId: 'name'),
        backgroundColor: background,
      );
      await renderer.render(screen());
      final field = root.querySelector('input')! as web.HTMLInputElement
        ..focus();

      await renderer.render(screen(background: '#eeeeee'));

      expect(web.document.activeElement, same(field));
      await renderer.render(screen());
      expect(of('Scaffold').style.getPropertyValue('background'), isEmpty);
    });

    test('the bottom bar publishes its height for the button to clear',
        () async {
      await renderer.render(
        UIBuilder.scaffold(
          body: UIBuilder.text('Body'),
          bottomBar: UIBuilder.bottomBar(
            child: UIBuilder.sizedBox(height: 70),
          ),
        ),
      );
      await settle();

      expect(
        of('Scaffold').style.getPropertyValue('--dnn-bottombar-height'),
        '70px',
      );
    });
  });

  group('an app bar', () {
    for (final kit in _kits) {
      test('${kit.name}: leading button, title, then the actions', () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);
        final fired = <String>[];
        renderer
          ..onEvent('back', (_) => fired.add('back'))
          ..onEvent('search', (_) => fired.add('search'));

        await renderer.render(
          UIBuilder.appBar(
            title: 'Inbox',
            leading: 'back',
            leadingEventId: 'back',
            actions: [
              UIBuilder.iconButton(
                icon: 'search',
                eventId: 'search',
                tooltip: 'Search',
              ),
            ],
          ),
        );

        final bar = root.querySelector('[data-type="AppBar"]')!;
        final leading = bar.querySelector('.dnn-appbar__leading')!;
        final actions = bar.querySelector('.dnn-appbar__actions')!;
        // All three in one row, in reading order.
        final row = leading.parentElement!;
        expect(row.children.length, 3);
        expect(row.children.item(0), same(leading));
        expect(row.children.item(1)!.textContent, 'Inbox');
        expect(row.children.item(2), same(actions));
        expect(leading.getAttribute('aria-label'), 'Back');
        expect(leading.textContent, glyph(Icons.arrow_back));
        expect(childTypes(actions), ['IconButton']);

        (leading as web.HTMLElement).click();
        (actions.querySelector('button')! as web.HTMLElement).click();
        expect(fired, ['back', 'search']);
      });
    }

    test('close and menu are drawn as themselves', () async {
      await renderer.render(
        UIBuilder.appBar(title: 'T', leading: 'close', leadingEventId: 'x'),
      );
      expect(
        root.querySelector('.dnn-appbar__leading')!.textContent,
        glyph(Icons.close),
      );

      await renderer.render(
        UIBuilder.appBar(title: 'T', leading: 'menu', leadingEventId: 'x'),
      );
      final leading = root.querySelector('.dnn-appbar__leading')!;
      expect(leading.textContent, glyph(Icons.menu));
      expect(leading.getAttribute('aria-label'), 'Menu');
    });

    test('a title node takes the title\'s place, ahead of the actions',
        () async {
      await renderer.render(
        UIBuilder.appBar(
          title: 'Fallback',
          titleNode: UIBuilder.text('Rich title', id: 'rich'),
          actions: [
            UIBuilder.iconButton(icon: 'add', eventId: 'a', tooltip: 'Add'),
          ],
        ),
      );

      final bar = of('AppBar');
      expect(bar.classList.contains('dnn-appbar--title-node'), isTrue);
      expect(bar.querySelector('.dnn-appbar__title')!.hasAttribute('hidden'),
          isTrue);
      expect(childTypes(bar.querySelector('.dnn-appbar__actions')!), [
        'Text',
        'IconButton',
      ]);
    });

    test('centring, colours and elevation', () async {
      await renderer.render(
        UIBuilder.appBar(
          title: 'T',
          centerTitle: true,
          backgroundColor: '#80112233',
          foregroundColor: '#ffff00',
          elevation: 0,
        ),
      );

      final bar = of('AppBar');
      expect(bar.classList.contains('dnn-appbar--center'), isTrue);
      expect(bar.style.getPropertyValue('background'),
          startsWith('rgba(17, 34, 51, 0.5'));
      // The stated foreground outranks the one worked out from the fill.
      expect(bar.style.getPropertyValue('color'), 'rgb(255, 255, 0)');
      expect(bar.style.getPropertyValue('box-shadow'), 'none');
    });

    test('an action added later appears without the bar being rebuilt',
        () async {
      await renderer.render(UIBuilder.appBar(title: 'T'));
      final bar = of('AppBar');

      await renderer.render(
        UIBuilder.appBar(
          title: 'T',
          actions: [
            UIBuilder.iconButton(icon: 'add', eventId: 'a', tooltip: 'Add'),
          ],
        ),
      );

      expect(of('AppBar'), same(bar));
      expect(bar.querySelector('[data-type="IconButton"]'), isNotNull);
    });
  });

  group('bottom navigation', () {
    WidgetNode nav(int selected, {bool rail = false}) =>
        UIBuilder.bottomNavigation(
          items: navItems,
          selectedIndex: selected,
          eventId: 'nav',
          rail: rail,
        );

    List<web.HTMLElement> buttons() {
      final found = of('BottomNavigation').querySelectorAll('button');
      return [
        for (var i = 0; i < found.length; i++)
          found.item(i)! as web.HTMLElement,
      ];
    }

    test('is a row of real buttons, the selected one marked', () async {
      await renderer.render(nav(1));

      expect(of('BottomNavigation').getAttribute('role'), 'navigation');
      expect(buttons().map((b) => b.querySelector('span:last-child')!.textContent),
          ['Home', 'Search', 'Settings']);
      expect(buttons()[1].getAttribute('aria-current'), 'page');
      expect(buttons()[0].hasAttribute('aria-current'), isFalse);
      expect(buttons()[1].querySelector('i')!.textContent,
          String.fromCharCode(0xe8b6));
    });

    test('a tap sends the index', () async {
      final chosen = <Object?>[];
      renderer.onEvent('nav', (data) => chosen.add(data['index']));
      await renderer.render(nav(0));

      buttons()[2].click();

      expect(chosen, [2]);
    });

    test('the selected destination shows its selected icon', () async {
      await renderer.render(nav(0));
      expect(buttons()[0].querySelector('i')!.textContent,
          String.fromCharCode(0xe88b));

      await renderer.render(nav(1));
      expect(buttons()[0].querySelector('i')!.textContent,
          String.fromCharCode(0xe88a));
    });

    test('choosing keeps focus on the button that was pressed', () async {
      await renderer.render(nav(0));
      final pressed = buttons()[2]..focus();

      await renderer.render(nav(2));

      expect(buttons()[2], same(pressed));
      expect(web.document.activeElement, same(pressed));
      expect(pressed.classList.contains('dnn-bottomnav__item--selected'),
          isTrue);
    });

    test('rail: true lays the same destinations out as a rail', () async {
      await renderer.render(nav(0, rail: true));

      expect(of('BottomNavigation').classList.contains('dnn-bottomnav--rail'),
          isTrue);
      expect(buttons(), hasLength(3));
    });
  });

  group('a floating button', () {
    for (final kit in _kits) {
      test('${kit.name}: a label makes it the extended button', () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);
        var taps = 0;
        renderer.onEvent('compose', (_) => taps++);

        await renderer.render(
          UIBuilder.floatingActionButton(
            tooltip: 'Compose',
            eventId: 'compose',
            icon: 'edit',
            label: 'Compose',
          ),
        );

        final fab = root.querySelector('[data-type="FloatingActionButton"]')!
            as web.HTMLElement;
        expect(fab.classList.contains('dnn-fab--extended'), isTrue);
        expect(fab.querySelector('.dnn-fab__label')!.textContent, 'Compose');
        expect(fab.querySelector('i')!.textContent, glyph(Icons.edit));
        fab.click();
        expect(taps, 1);
      });
    }

    test('without a label it is the round one', () async {
      await renderer.render(
        UIBuilder.floatingActionButton(tooltip: 'Add', eventId: 'add'),
      );

      final fab = of('FloatingActionButton');
      expect(fab.classList.contains('dnn-fab--extended'), isFalse);
      expect(fab.querySelector('.dnn-fab__label'), isNull);
    });
  });
}
