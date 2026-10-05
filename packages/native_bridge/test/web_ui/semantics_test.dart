@TestOn('browser')
/// What a node says of itself to a screen reader, and to a test: its id, what
/// it is, what it is called, and whether it can be pressed.
///
/// `accessibility_test.dart` covers what the controls have always said. This
/// is the vocabulary a tree states itself - `semanticRole`, `semanticValue`,
/// `liveRegion`, `excludeSemantics`, a `semanticLabel` on a control - and the
/// `id` every node may carry. As there, what is asserted is the attributes
/// assistive technology reads; how it sounds still needs a person.
library;

import 'package:dart_not_native/core.dart';
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
  late List<String> events;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    events = [];
  });
  tearDown(() => root.remove());

  void listen(List<String> ids) {
    for (final id in ids) {
      renderer.onEvent(id, (_) => events.add(id));
    }
  }

  web.HTMLElement of(String type) =>
      root.querySelector('[data-type="$type"]')! as web.HTMLElement;
  web.HTMLElement box() => of('Box');
  String? attr(web.Element element, String name) => element.getAttribute(name);

  web.KeyboardEvent key(String key) => web.KeyboardEvent(
    'keydown',
    web.KeyboardEventInit(key: key, bubbles: true, cancelable: true),
  );

  WidgetNode text(String content, [Map<String, dynamic> props = const {}]) =>
      node('Text', {'content': content, ...props});
  WidgetNode button(String label, String eventId) =>
      node('Button', {'label': label, 'eventId': eventId});
  WidgetNode icon([Map<String, dynamic> props = const {}]) =>
      node('Icon', {'codepoint': 0xe047, ...props});

  group('an id', () {
    final nodes = <String, WidgetNode>{
      'Text': text('Hello'),
      'Box': node('Box', {}),
      'Icon': icon(),
      'Button': button('Go', 'go'),
      'IconButton': node('IconButton', {'eventId': 'i', 'tooltip': 'More'}),
      'Checkbox': node('Checkbox', {'eventId': 'c'}),
      'Radio': node('Radio', {'eventId': 'r', 'value': 'a'}),
      'Toggle': node('Toggle', {'eventId': 't'}),
      'Loading': node('Loading', {'type': 'spinner'}),
      'Canvas': node('Canvas', {'width': 10, 'height': 10, 'commands': []}),
      'Image': node('Image', {'src': 'a.png', 'alt': 'A'}),
      'Slider': node('Slider', {'eventId': 's', 'value': 0.5}),
      'TextField': node('TextField', {'eventId': 'f', 'hint': 'Name'}),
      'Dropdown': node('Dropdown', {
        'eventId': 'd',
        'items': ['One', 'Two'],
      }),
      'Column': node('Column', {}),
      'Scroll': node('Scroll', {}),
    };

    for (final entry in nodes.entries) {
      test('is the DOM id of a ${entry.key}', () async {
        await renderer.render(withId(entry.value, 'the_${entry.key}'));

        final element = web.document.getElementById('the_${entry.key}');
        expect(element, isNotNull);
        expect(attr(element!, 'data-type'), entry.key);
      });
    }

    test('on a text field is its frame, with the input inside it', () async {
      await renderer.render(
        node('TextField', {'id': 'name', 'eventId': 'f', 'label': 'Name'}),
      );

      final frame = web.document.getElementById('name')!;
      final input = frame.querySelector('input')!;
      // The input keeps the id its label points at.
      expect(input.id, 'dnn-input-f');
      expect(attr(frame.querySelector('label')!, 'for'), input.id);
      expect(inputInside('name'), same(input));
    });

    test('on a dropdown is its frame, with the select inside it', () async {
      await renderer.render(
        node('Dropdown', {
          'id': 'plan',
          'eventId': 'd',
          'label': 'Plan',
          'items': ['Free', 'Pro'],
        }),
      );

      final frame = web.document.getElementById('plan')!;
      final select = frame.querySelector('select')!;
      expect(select.id, 'dnn-select-d');
      expect(attr(frame.querySelector('label')!, 'for'), select.id);
    });

    // Each of these is patched in a different place, and each has to keep
    // its element while its id arrives and goes.
    final patched = <String, WidgetNode Function(String? id)>{
      'Box': (id) => node('Box', {'width': 10, 'id': ?id}),
      'TextField': (id) => node('TextField', {'eventId': 'f', 'id': ?id}),
      'Slider': (id) => node('Slider', {'eventId': 's', 'id': ?id}),
      'Dropdown': (id) => node('Dropdown', {
        'eventId': 'd',
        'items': ['One'],
        'id': ?id,
      }),
      'Stack': (id) => node('Stack', {'id': ?id}),
      'AnimatedOpacity': (id) =>
          node('AnimatedOpacity', {'opacity': 1, 'id': ?id}),
    };

    for (final entry in patched.entries) {
      test('arrives on, renames and leaves a patched ${entry.key}', () async {
        // Wrapped, so the node under test is not the root of the tree.
        WidgetNode tree(String? id) => node('Column', {}, [entry.value(id)]);
        await renderer.render(tree(null));
        final element = of(entry.key);
        expect(element.hasAttribute('id'), isFalse);

        await renderer.render(tree('first'));
        expect(of(entry.key), same(element));
        expect(element.id, 'first');

        // A different id is a different node - that is what an id means to
        // the reconciler - so this one is a new element under the new name.
        await renderer.render(tree('second'));
        final renamed = of(entry.key);
        expect(renamed.id, 'second');
        expect(web.document.getElementById('first'), isNull);
        expect(root.querySelectorAll('[data-type="${entry.key}"]').length, 1);

        await renderer.render(tree(null));
        expect(of(entry.key), same(renamed));
        expect(renamed.hasAttribute('id'), isFalse);
      });
    }

    test('arrives on, changes on and leaves a node that is rebuilt', () async {
      WidgetNode tree(String? id) =>
          node('Column', {}, [text('Hello', {'id': ?id})]);
      await renderer.render(tree(null));
      expect(of('Text').hasAttribute('id'), isFalse);

      await renderer.render(tree('first'));
      expect(of('Text').id, 'first');

      await renderer.render(tree('second'));
      expect(of('Text').id, 'second');
      expect(web.document.getElementById('first'), isNull);

      await renderer.render(tree(null));
      expect(of('Text').hasAttribute('id'), isFalse);
    });
  });

  group('a box that is tapped', () {
    test('is a button, named by the text inside it', () async {
      listen(['tap']);
      await renderer.render(
        node('Box', {'tapEventId': 'tap'}, [text('Tic Tac Toe')]),
      );

      expect(attr(box(), 'role'), 'button');
      expect(attr(box(), 'tabindex'), '0');
      // No label of its own: a button's name is what it contains.
      expect(box().hasAttribute('aria-label'), isFalse);
      expect(box().textContent, 'Tic Tac Toe');
    });

    test('is named by its label when it has one', () async {
      await renderer.render(
        node(
          'Box',
          {'tapEventId': 'tap', 'semanticLabel': 'Open the game'},
          [text('Tic Tac Toe')],
        ),
      );

      expect(attr(box(), 'role'), 'button');
      expect(attr(box(), 'aria-label'), 'Open the game');
    });

    test('is pressed by Enter, by Space and by a pointerless click', () async {
      listen(['tap']);
      await renderer.render(node('Box', {'tapEventId': 'tap'}, [text('Go')]));

      box().dispatchEvent(key('Enter'));
      expect(events, ['tap']);

      final space = key(' ');
      box().dispatchEvent(space);
      expect(events, ['tap', 'tap']);
      expect(space.defaultPrevented, isTrue, reason: 'or the page scrolls');

      box().click();
      expect(events, ['tap', 'tap', 'tap']);

      box().dispatchEvent(key('a'));
      expect(events, hasLength(3));
    });

    test('is not a button when it holds one', () async {
      listen(['card', 'inner']);
      await renderer.render(
        node(
          'Box',
          {'tapEventId': 'card', 'id': 'card'},
          [
            node('Column', {}, [text('A card'), button('Buy', 'inner')]),
          ],
        ),
      );

      // A button in a button is one control to a screen reader.
      expect(attr(box(), 'role'), 'group');
      expect(root.querySelector('[role="button"] button'), isNull);
      // Still a card the keyboard can reach and press.
      expect(attr(box(), 'tabindex'), '0');
      box().dispatchEvent(key('Enter'));
      expect(events, ['card']);

      // And the button inside is its own: pressing it is not pressing the card.
      (root.querySelector('button')! as web.HTMLElement).click();
      expect(events, ['card', 'inner']);
    });

    test('is not a button when it holds another tapped box', () async {
      await renderer.render(
        node(
          'Box',
          {'tapEventId': 'outer', 'id': 'outer'},
          [
            node('Box', {'tapEventId': 'inner', 'id': 'inner'}, [text('In')]),
          ],
        ),
      );

      expect(attr(web.document.getElementById('inner')!, 'role'), 'button');
      expect(attr(web.document.getElementById('outer')!, 'role'), 'group');
    });

    test('stops being a button when a control arrives inside it', () async {
      WidgetNode tree({required bool withButton}) => node(
        'Box',
        {'tapEventId': 'card'},
        [
          node('Column', {}, [
            text('A card'),
            if (withButton) button('Buy', 'inner'),
          ]),
        ],
      );
      await renderer.render(tree(withButton: false));
      final card = box();
      expect(attr(card, 'role'), 'button');

      // The box's own props are what they were; only its inside changed.
      await renderer.render(tree(withButton: true));
      expect(box(), same(card));
      expect(attr(card, 'role'), 'group');

      await renderer.render(tree(withButton: false));
      expect(attr(card, 'role'), 'button');
    });

    test('says so only while it is tapped', () async {
      await renderer.render(node('Box', {'tapEventId': 'tap', 'width': 10}));
      await renderer.render(node('Box', {'width': 10}));

      expect(box().hasAttribute('role'), isFalse);
      expect(box().hasAttribute('tabindex'), isFalse);
      expect(box().hasAttribute('aria-label'), isFalse);
    });

    test('a long press alone makes no button', () async {
      await renderer.render(
        node('Box', {'longPressEventId': 'hold'}, [text('Hold me')]),
      );

      // It is a gesture of the pointer; there is nothing for a key to press.
      expect(box().hasAttribute('role'), isFalse);
      expect(box().hasAttribute('tabindex'), isFalse);
    });
  });

  group('a box that ignores the pointer', () {
    WidgetNode tree({required bool ignore}) => node(
      'Box',
      {'ignorePointer': ?(ignore ? true : null), 'width': 100},
      [
        node('Column', {}, [
          button('Buy', 'inner'),
          node('Box', {'tapEventId': 'tile', 'id': 'tile'}, [text('Tile')]),
          node('Checkbox', {'eventId': 'check', 'id': 'check'}),
        ]),
      ],
    );

    test('says it is disabled and turns the pointer away', () async {
      await renderer.render(tree(ignore: true));

      expect(attr(box(), 'aria-disabled'), 'true');
      expect(box().style.getPropertyValue('pointer-events'), 'none');
    });

    test('lets nothing inside be pressed without a pointer either', () async {
      listen(['inner', 'tile', 'check']);
      await renderer.render(tree(ignore: true));
      final tile = web.document.getElementById('tile')! as web.HTMLElement;
      final check = inputInside('check');

      // What a screen reader's "activate" sends, and what Enter sends.
      (root.querySelector('button')! as web.HTMLElement).click();
      tile.click();
      tile.dispatchEvent(key('Enter'));
      tile.dispatchEvent(key(' '));
      check.click();

      expect(events, isEmpty);
      expect(check.checked, isFalse);
    });

    test('lets Tab through, so the keyboard can leave', () async {
      await renderer.render(tree(ignore: true));

      final tab = key('Tab');
      web.document.getElementById('tile')!.dispatchEvent(tab);

      expect(tab.defaultPrevented, isFalse);
    });

    test('and lets go when it stops ignoring', () async {
      listen(['inner', 'tile']);
      await renderer.render(tree(ignore: true));
      final ignoring = box();
      await renderer.render(tree(ignore: false));

      expect(box(), same(ignoring));
      expect(box().hasAttribute('aria-disabled'), isFalse);
      expect(box().style.getPropertyValue('pointer-events'), isEmpty);
      (root.querySelector('button')! as web.HTMLElement).click();
      web.document.getElementById('tile')!.dispatchEvent(key('Enter'));
      expect(events, ['inner', 'tile']);
    });
  });

  group('a stated role', () {
    test('makes a box a heading, an image, a button or a progress bar', () async {
      const roles = {
        'heading': 'heading',
        'image': 'img',
        'button': 'button',
        'progress': 'progressbar',
      };
      for (final entry in roles.entries) {
        await renderer.render(
          node('Box', {'semanticRole': entry.key, 'semanticLabel': 'It'}),
        );

        expect(attr(box(), 'role'), entry.value, reason: entry.key);
        expect(attr(box(), 'aria-label'), 'It', reason: entry.key);
        expect(
          attr(box(), 'aria-level'),
          entry.key == 'heading' ? '2' : null,
          reason: entry.key,
        );
      }
    });

    test('outranks what a tap would have made it', () async {
      await renderer.render(
        node(
          'Box',
          {'tapEventId': 'tap', 'semanticRole': 'image', 'semanticLabel': 'Map'},
        ),
      );

      expect(attr(box(), 'role'), 'img');
      expect(attr(box(), 'tabindex'), '0');
    });

    test('makes a text a heading', () async {
      await renderer.render(text('Settings', {'semanticRole': 'heading'}));

      expect(attr(of('Text'), 'role'), 'heading');
      expect(attr(of('Text'), 'aria-level'), '2');
      expect(of('Text').textContent, 'Settings');
    });

    test('arrives on and leaves a text that is already drawn', () async {
      WidgetNode tree(String? role) =>
          node('Column', {}, [text('Settings', {'semanticRole': ?role})]);
      await renderer.render(tree(null));
      expect(of('Text').hasAttribute('role'), isFalse);

      await renderer.render(tree('heading'));
      expect(attr(of('Text'), 'role'), 'heading');

      await renderer.render(tree(null));
      expect(of('Text').hasAttribute('role'), isFalse);
      expect(of('Text').hasAttribute('aria-level'), isFalse);
    });

    test('arrives on and leaves a box without rebuilding it', () async {
      await renderer.render(node('Box', {'width': 10}));
      final before = box();

      await renderer.render(node('Box', {'width': 10, 'semanticRole': 'heading'}));
      expect(box(), same(before));
      expect(attr(box(), 'role'), 'heading');
      expect(attr(box(), 'aria-level'), '2');

      await renderer.render(node('Box', {'width': 10}));
      expect(box().hasAttribute('role'), isFalse);
      expect(box().hasAttribute('aria-level'), isFalse);
    });

    test('makes an icon an image even when a button was asked for', () async {
      await renderer.render(
        icon({'semanticLabel': 'Add', 'semanticRole': 'button'}),
      );

      // The element already says what it is.
      expect(attr(of('Icon'), 'role'), 'img');
    });

    test('does not rename what is already a control', () async {
      await renderer.render(
        node('Button', {'label': 'Go', 'eventId': 'go', 'semanticRole': 'heading'}),
      );

      expect(of('Button').hasAttribute('role'), isFalse);
      expect(of('Button').tagName.toLowerCase(), 'button');
    });

    test('one the protocol does not have is not a role', () async {
      await renderer.render(text('Hello', {'semanticRole': 'banana'}));

      expect(of('Text').hasAttribute('role'), isFalse);
    });
  });

  group('a value', () {
    test('is what a progress bar is at', () async {
      await renderer.render(
        node('Box', {
          'semanticRole': 'progress',
          'semanticLabel': 'Upload',
          'semanticValue': '40%',
        }),
      );

      expect(attr(box(), 'role'), 'progressbar');
      expect(attr(box(), 'aria-label'), 'Upload');
      expect(attr(box(), 'aria-valuetext'), '40%');
      expect(attr(box(), 'aria-valuenow'), '40');
      expect(attr(box(), 'aria-valuemin'), '0');
      expect(attr(box(), 'aria-valuemax'), '100');
    });

    test('that is not a percentage is only said', () async {
      await renderer.render(
        node('Box', {
          'semanticRole': 'progress',
          'semanticValue': 'Step 2 of 5',
        }),
      );

      expect(attr(box(), 'aria-valuetext'), 'Step 2 of 5');
      expect(box().hasAttribute('aria-valuenow'), isFalse);
    });

    test('is said after the name of anything else', () async {
      await renderer.render(
        node('Box', {'semanticLabel': 'Volume', 'semanticValue': 'Loud'}),
      );

      // A group is not read its aria-valuetext, so the name carries it too.
      expect(attr(box(), 'aria-label'), 'Volume, Loud');
      expect(attr(box(), 'aria-valuetext'), 'Loud');
    });

    test('describes a button that is named by its text', () async {
      await renderer.render(
        node(
          'Box',
          {'tapEventId': 'tap', 'semanticValue': 'On'},
          [text('Wi-Fi')],
        ),
      );

      expect(box().hasAttribute('aria-label'), isFalse);
      expect(attr(box(), 'aria-description'), 'On');
      expect(attr(box(), 'aria-valuetext'), 'On');
    });

    test('follows the tree, and goes with it', () async {
      WidgetNode tree(String? value) => node('Box', {
        'semanticRole': 'progress',
        'semanticLabel': 'Upload',
        'semanticValue': ?value,
      });
      await renderer.render(tree('40%'));
      final bar = box();

      await renderer.render(tree('80%'));
      expect(box(), same(bar));
      expect(attr(bar, 'aria-valuetext'), '80%');
      expect(attr(bar, 'aria-valuenow'), '80');

      await renderer.render(tree(null));
      expect(bar.hasAttribute('aria-valuetext'), isFalse);
      expect(bar.hasAttribute('aria-valuenow'), isFalse);
      expect(attr(bar, 'aria-label'), 'Upload');
    });
  });

  group('a live region', () {
    test('is announced politely, for as long as it is one', () async {
      await renderer.render(
        node('Box', {'liveRegion': true}, [text('3 items')]),
      );
      final region = box();
      expect(attr(region, 'aria-live'), 'polite');

      // The same element with new text in it, which is what gets announced.
      await renderer.render(
        node('Box', {'liveRegion': true}, [text('4 items')]),
      );
      expect(box(), same(region));
      expect(region.textContent, '4 items');

      await renderer.render(node('Box', {}, [text('4 items')]));
      expect(box().hasAttribute('aria-live'), isFalse);
    });
  });

  group('excluding semantics', () {
    test('hides what is inside and keeps the label', () async {
      await renderer.render(
        node(
          'Box',
          {'excludeSemantics': true, 'semanticLabel': '4 of 5 stars'},
          [
            node('Row', {}, [icon(), icon()]),
          ],
        ),
      );

      expect(attr(box(), 'aria-label'), '4 of 5 stars');
      expect(box().hasAttribute('aria-hidden'), isFalse);
      expect(attr(of('Row'), 'aria-hidden'), 'true');
    });

    test('hides a child that replaces the one it hid', () async {
      WidgetNode tree(WidgetNode child) =>
          node('Box', {'excludeSemantics': true}, [child]);
      await renderer.render(tree(text('One')));
      expect(attr(of('Text'), 'aria-hidden'), 'true');

      await renderer.render(tree(node('Row', {}, [text('Two')])));
      expect(attr(of('Row'), 'aria-hidden'), 'true');
    });

    test('shows it again when it stops, but not what hid itself', () async {
      WidgetNode tree({required bool exclude}) => node(
        'Box',
        {'excludeSemantics': ?(exclude ? true : null), 'id': 'outer'},
        [text('Shown again')],
      );
      await renderer.render(tree(exclude: true));
      await renderer.render(tree(exclude: false));
      expect(of('Text').hasAttribute('aria-hidden'), isFalse);

      WidgetNode glyph({required bool exclude}) => node(
        'Box',
        {'excludeSemantics': ?(exclude ? true : null)},
        [icon()],
      );
      await renderer.render(glyph(exclude: true));
      await renderer.render(glyph(exclude: false));
      // A bare icon is hidden on its own account.
      expect(attr(of('Icon'), 'aria-hidden'), 'true');
    });
  });

  group('a tooltip', () {
    test('is the title', () async {
      await renderer.render(node('Box', {'tooltip': 'Tip'}, [text('Words')]));

      expect(attr(box(), 'title'), 'Tip');
    });

    test('names a box that has no label and says nothing', () async {
      await renderer.render(node('Box', {'tooltip': 'Information'}, [icon()]));

      expect(attr(box(), 'aria-label'), 'Information');
      expect(attr(box(), 'role'), 'img');
    });

    test('names a tapped box that holds only a glyph', () async {
      await renderer.render(
        node('Box', {'tooltip': 'Delete', 'tapEventId': 'tap'}, [icon()]),
      );

      expect(attr(box(), 'role'), 'button');
      expect(attr(box(), 'aria-label'), 'Delete');
    });

    test('does not name a box that has text', () async {
      await renderer.render(
        node('Box', {'tooltip': 'Tip', 'tapEventId': 'tap'}, [text('Words')]),
      );

      expect(box().hasAttribute('aria-label'), isFalse);
      expect(attr(box(), 'title'), 'Tip');
    });

    test('does not name a box whose icon names itself', () async {
      await renderer.render(
        node('Box', {'tooltip': 'Tip'}, [icon({'semanticLabel': 'Home'})]),
      );

      expect(box().hasAttribute('aria-label'), isFalse);
      expect(box().hasAttribute('role'), isFalse);
    });

    test('gives way to a label', () async {
      await renderer.render(
        node('Box', {'tooltip': 'Tip', 'semanticLabel': 'A tile'}, [icon()]),
      );

      expect(attr(box(), 'aria-label'), 'A tile');
      expect(attr(box(), 'title'), 'Tip');
      expect(attr(box(), 'role'), 'group');
    });

    test('stops naming a box that starts to speak', () async {
      WidgetNode tree(WidgetNode child) =>
          node('Box', {'tooltip': 'Information'}, [child]);
      await renderer.render(tree(icon()));
      expect(attr(box(), 'aria-label'), 'Information');

      await renderer.render(tree(text('Read me')));
      expect(box().hasAttribute('aria-label'), isFalse);
      expect(box().hasAttribute('role'), isFalse);
    });
  });

  group('an icon', () {
    test('with a label is an image with that name', () async {
      await renderer.render(icon({'semanticLabel': 'Favourite'}));

      expect(attr(of('Icon'), 'role'), 'img');
      expect(attr(of('Icon'), 'aria-label'), 'Favourite');
      expect(of('Icon').hasAttribute('aria-hidden'), isFalse);
    });

    test('without one is hidden', () async {
      await renderer.render(icon());

      expect(attr(of('Icon'), 'aria-hidden'), 'true');
      expect(of('Icon').hasAttribute('role'), isFalse);
    });
  });

  group('a control with no visible label', () {
    for (final kit in _kits) {
      test('is named by its semantic label (${kit.name})', () async {
        final kitted = WebUIRenderer(root: root, kit: kit, animations: false);
        const controls = {
          'Checkbox': {'eventId': 'c'},
          'Radio': {'eventId': 'r', 'value': 'a'},
          'Toggle': {'eventId': 't'},
        };
        for (final entry in controls.entries) {
          await kitted.render(
            node(entry.key, {
              ...entry.value,
              'semanticLabel': 'Wi-Fi',
              'id': 'control',
            }),
          );

          expect(
            attr(inputInside('control'), 'aria-label'),
            'Wi-Fi',
            reason: entry.key,
          );
        }
      });

      test('a toggle is a switch (${kit.name})', () async {
        await WebUIRenderer(root: root, kit: kit, animations: false).render(
          node('Toggle', {'eventId': 't', 'id': 'control'}),
        );

        expect(attr(inputInside('control'), 'role'), 'switch');
        expect(inputInside('control').type, 'checkbox');
      });
    }

    test('one with a label of its own is left to it', () async {
      await renderer.render(
        node('Checkbox', {'eventId': 'c', 'label': 'Remember me', 'id': 'c'}),
      );

      expect(inputInside('c').hasAttribute('aria-label'), isFalse);
      expect(of('Checkbox').textContent, contains('Remember me'));
    });

    test('keeps its name when it is ticked in place', () async {
      WidgetNode tree({required bool checked}) => node('Checkbox', {
        'eventId': 'c',
        'id': 'c',
        'semanticLabel': 'Wi-Fi',
        'checked': checked,
      });
      await renderer.render(tree(checked: false));
      final input = inputInside('c');

      await renderer.render(tree(checked: true));

      expect(inputInside('c'), same(input));
      expect(input.checked, isTrue);
      expect(attr(input, 'aria-label'), 'Wi-Fi');
    });
  });

  group('loading', () {
    for (final kit in _kits) {
      test('a bar says how far along it is (${kit.name})', () async {
        await WebUIRenderer(root: root, kit: kit, animations: false).render(
          node('Loading', {
            'type': 'progress-linear',
            'value': 0.4,
            'semanticLabel': 'Uploading',
            'id': 'upload',
          }),
        );

        final bar = web.document.getElementById('upload')!;
        expect(attr(bar, 'role'), 'progressbar');
        expect(attr(bar, 'aria-label'), 'Uploading');
        expect(attr(bar, 'aria-valuenow'), '40');
        expect(attr(bar, 'aria-valuemin'), '0');
        expect(attr(bar, 'aria-valuemax'), '100');
      });
    }

    test('a ring says how far along it is', () async {
      await renderer.render(
        node('Loading', {'type': 'progress-circular', 'value': 0.75}),
      );

      expect(attr(of('Loading'), 'role'), 'progressbar');
      expect(attr(of('Loading'), 'aria-valuenow'), '75');
    });

    test('one that does not know has no value', () async {
      await renderer.render(
        node('Loading', {'type': 'progress-linear', 'indeterminate': true}),
      );

      expect(attr(of('Loading'), 'role'), 'progressbar');
      expect(of('Loading').hasAttribute('aria-valuenow'), isFalse);
    });

    test('a spinner is a named progress bar with no value', () async {
      await renderer.render(
        node('Loading', {'type': 'spinner', 'semanticLabel': 'Loading inbox'}),
      );

      expect(attr(of('Loading'), 'role'), 'progressbar');
      expect(attr(of('Loading'), 'aria-label'), 'Loading inbox');
      expect(of('Loading').hasAttribute('aria-valuenow'), isFalse);
    });

    test('a skeleton says nothing unless it was given a name', () async {
      await renderer.render(node('Loading', {'type': 'skeleton'}));
      expect(of('Loading').hasAttribute('role'), isFalse);

      await renderer.render(
        node('Loading', {'type': 'skeleton', 'semanticLabel': 'Loading'}),
      );
      expect(attr(of('Loading'), 'role'), 'progressbar');
      expect(attr(of('Loading'), 'aria-label'), 'Loading');
    });
  });

  group('a canvas', () {
    WidgetNode canvas([Map<String, dynamic> props = const {}]) =>
        node('Canvas', {'width': 20, 'height': 20, 'commands': [], ...props});

    test('with a label is an image with that name', () async {
      await renderer.render(canvas({'semanticLabel': 'Sales by month'}));

      expect(attr(of('Canvas'), 'role'), 'img');
      expect(attr(of('Canvas'), 'aria-label'), 'Sales by month');
    });

    test('without one says nothing', () async {
      await renderer.render(canvas());

      expect(of('Canvas').hasAttribute('role'), isFalse);
      expect(of('Canvas').hasAttribute('aria-label'), isFalse);
    });

    test('is renamed on the surface it already has', () async {
      await renderer.render(canvas({'semanticLabel': 'January'}));
      final surface = root.querySelector('canvas');

      await renderer.render(canvas({'semanticLabel': 'February'}));

      expect(root.querySelector('canvas'), same(surface));
      expect(attr(of('Canvas'), 'aria-label'), 'February');
    });
  });

  group('what the components already say', () {
    for (final kit in _kits) {
      test('an app bar title is the first heading (${kit.name})', () async {
        await WebUIRenderer(root: root, kit: kit, animations: false).render(
          UIBuilder.scaffold(
            appBar: UIBuilder.appBar(title: 'Inbox'),
            body: text('Body'),
          ),
        );

        final heading = root.querySelector('[role="heading"]')!;
        expect(heading.textContent, 'Inbox');
        expect(attr(heading, 'aria-level'), '1');
        expect(of('AppBar').contains(heading), isTrue);
      });
    }

    test('a navigation bar title is a heading', () async {
      await renderer.render(node('NavigationBar', {'title': 'Settings'}));

      final heading = root.querySelector('[role="heading"]')!;
      expect(heading.textContent, 'Settings');
      expect(attr(heading, 'aria-level'), '1');
    });

    test('tabs are a tab list that says which is selected', () async {
      await renderer.render(
        node('Tabs', {
          'tabs': ['One', 'Two'],
          'selectedIndex': 1,
          'eventId': 'tabs',
        }),
      );

      expect(attr(of('Tabs'), 'role'), 'tablist');
      final tabs = root.querySelectorAll('[role="tab"]');
      expect(tabs.length, 2);
      expect(attr(tabs.item(0)! as web.Element, 'aria-selected'), 'false');
      expect(attr(tabs.item(1)! as web.Element, 'aria-selected'), 'true');
    });

    test('bottom navigation says which destination is current', () async {
      await renderer.render(
        node('BottomNavigation', {
          'eventId': 'nav',
          'selectedIndex': 1,
          'items': [
            {'label': 'Home', 'icon': 0xe318},
            {'label': 'Search', 'icon': 0xe567},
          ],
        }),
      );

      final items = of('BottomNavigation').querySelectorAll('button');
      expect(items.length, 2);
      expect((items.item(0)! as web.Element).hasAttribute('aria-current'), isFalse);
      expect(attr(items.item(1)! as web.Element, 'aria-current'), 'page');
    });

    test('a slider is the browser\'s own range', () async {
      await renderer.render(
        node('Slider', {'eventId': 's', 'min': 10, 'max': 50, 'value': 20}),
      );

      final slider = of('Slider') as web.HTMLInputElement;
      expect(slider.type, 'range');
      expect(slider.min, '10');
      expect(slider.max, '50');
      expect(slider.value, '20');
    });

    test('a dropdown is the browser\'s own select, named by its label', () async {
      await renderer.render(
        node('Dropdown', {
          'eventId': 'd',
          'label': 'Plan',
          'items': ['Free', 'Pro'],
          'selectedIndex': 1,
        }),
      );

      final select = root.querySelector('select')! as web.HTMLSelectElement;
      expect(select.value, 'Pro');
      final label = root.querySelector('label')!;
      expect(label.textContent, 'Plan');
      expect(attr(label, 'for'), select.id);
    });

    test('a disabled button is disabled, not only grey', () async {
      listen(['go']);
      await renderer.render(
        node('Button', {'label': 'Go', 'eventId': 'go', 'disabled': true}),
      );

      final button = of('Button') as web.HTMLButtonElement;
      expect(button.disabled, isTrue);
      button.click();
      expect(events, isEmpty);
    });
  });

  // A button the app drew from a box and switched off has no tap left to be
  // found by, and a filter chip's tick is only a picture: the node says both.
  group('a box that stands for a control', () {
    test('disabled is aria-disabled, with the role it was given', () async {
      await renderer.render(
        node('Box', {'disabled': true, 'semanticRole': 'button'}, [text('E')]),
      );
      expect(attr(box(), 'role'), 'button');
      expect(attr(box(), 'aria-disabled'), 'true');
    });

    test('selected is aria-pressed, and follows a patch', () async {
      WidgetNode chip(bool on) => node(
        'Box',
        {'id': 'mon', 'tapEventId': 'toggle', 'selected': on},
        [text('Mon')],
      );
      await renderer.render(chip(true));
      expect(attr(box(), 'aria-pressed'), 'true');
      await renderer.render(chip(false));
      expect(attr(box(), 'aria-pressed'), 'false');
    });

    test('a box that is neither says neither', () async {
      await renderer.render(node('Box', {'tapEventId': 'tap'}, [text('Go')]));
      expect(box().hasAttribute('aria-pressed'), isFalse);
      expect(box().hasAttribute('aria-disabled'), isFalse);
    });
  });
}
