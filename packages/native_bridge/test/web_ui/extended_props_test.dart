@TestOn('browser')
/// The props the protocol added to nodes it already had, the glyph node, and
/// the slot a Flutter widget would have been painted into.
library;

import 'package:dart_not_native/core.dart';
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
  String style(String type, String property) =>
      of(type).style.getPropertyValue(property);

  group('colours', () {
    test('cssColor turns alpha-first hex into rgba and leaves the rest', () {
      expect(cssColor('#80ff8000'), 'rgba(255, 128, 0, 0.502)');
      expect(cssColor('#ff102030'), 'rgba(16, 32, 48, 1)');
      expect(cssColor('#00000000'), 'rgba(0, 0, 0, 0.000)');
      expect(cssColor('#1976d2'), '#1976d2');
      expect(cssColor('#abc'), '#abc');
      expect(cssColor('rebeccapurple'), 'rebeccapurple');
      // Nine characters that are not hex are not a colour to convert.
      expect(cssColor('#zzzzzzzz'), '#zzzzzzzz');
    });

    test('every node that takes a colour takes one with alpha', () async {
      await renderer.render(
        UIBuilder.column(
          children: [
            UIBuilder.text('t', color: '#80ff0000'),
            UIBuilder.button(label: 'b', eventId: 'e', color: '#8000ff00'),
            UIBuilder.icon(codepoint: 0xe88a, color: '#800000ff'),
            node('Divider', {'color': '#80101010'}),
            node('Card', {'backgroundColor': '#80202020'}),
            node('Badge', {'label': 'n', 'color': '#80303030'}),
            node('AnimatedContainer', {'color': '#80404040'}),
            node('Loading', {'type': 'spinner', 'color': '#80505050'}),
          ],
        ),
      );

      expect(style('Text', 'color'), startsWith('rgba(255, 0, 0, 0.5'));
      expect(style('Button', 'background'), startsWith('rgba(0, 255, 0, 0.5'));
      expect(style('Icon', 'color'), startsWith('rgba(0, 0, 255, 0.5'));
      expect(style('Divider', 'background'), startsWith('rgba(16, 16, 16, 0.5'));
      expect(style('Card', 'background'), startsWith('rgba(32, 32, 32, 0.5'));
      expect(style('Badge', 'background'), startsWith('rgba(48, 48, 48, 0.5'));
      expect(style('AnimatedContainer', 'background-color'),
          startsWith('rgba(64, 64, 64, 0.5'));
      expect(style('Loading', 'color'), startsWith('rgba(80, 80, 80, 0.5'));
    });
  });

  group('an icon', () {
    test('is the glyph at its codepoint, in the icon font', () async {
      await renderer.render(UIBuilder.icon(codepoint: 0xe88a));

      final icon = of('Icon');
      expect(icon.classList.contains('material-icons'), isTrue);
      expect(icon.textContent, String.fromCharCode(0xe88a));
      // Decoration, unless it is given a name.
      expect(icon.getAttribute('aria-hidden'), 'true');
    });

    test('a codepoint from Flutter\'s table is drawn as itself', () async {
      // The shell's icon font is Flutter's own file, so 0xe318 is `Icons.home`
      // here as it is on a device, and nothing has to be looked up.
      await renderer.render(UIBuilder.icon(codepoint: Icons.home.codePoint));
      expect(of('Icon').textContent, String.fromCharCode(0xe318));

      // The outlined, rounded and sharp styles are glyphs of that same font.
      await renderer.render(
        UIBuilder.icon(codepoint: Icons.home_outlined.codePoint),
      );
      expect(of('Icon').textContent, String.fromCharCode(0xf107));
      expect(of('Icon').classList.contains('material-icons'), isTrue);
      expect(style('Icon', 'font-family'), isEmpty);

      // In a family of the app's own the codepoint is all there is.
      await renderer.render(
        UIBuilder.icon(codepoint: 0xe318, fontFamily: 'My Icons'),
      );
      expect(of('Icon').textContent, String.fromCharCode(0xe318));
    });

    test('Flutter\'s name for the default family is the class\'s font',
        () async {
      // CSS knows it as "Material Icons"; an inline "MaterialIcons" would
      // name a family the page does not have.
      await renderer.render(
        UIBuilder.icon(codepoint: 0xf107, fontFamily: 'MaterialIcons'),
      );
      expect(style('Icon', 'font-family'), isEmpty);
    });

    test('a codepoint past the sixteen-bit range is one character', () async {
      // `Icons.abc` is 0xf04b6: two code units, one glyph.
      await renderer.render(UIBuilder.icon(codepoint: Icons.abc.codePoint));
      expect(of('Icon').textContent!.runes.toList(), [0xf04b6]);
    });

    test('a button\'s icon is its codepoint, in every kit', () async {
      for (final kit in _kits) {
        final host = mountRoot();
        final kitRenderer = WebUIRenderer(
          root: host,
          kit: kit,
          animations: false,
        );
        await kitRenderer.render(
          UIBuilder.column(
            children: [
              UIBuilder.iconButton(
                icon: Icons.delete_outlined.name!,
                codepoint: Icons.delete_outlined.codePoint,
                eventId: 'delete',
                tooltip: 'Delete',
              ),
              // A name alone is resolved by the builder.
              UIBuilder.iconButton(
                icon: 'search',
                eventId: 'search',
                tooltip: 'Search',
              ),
            ],
          ),
        );
        final glyphs = host.querySelectorAll('[data-type="IconButton"] i');
        expect(
          [
            for (var i = 0; i < glyphs.length; i++) glyphs.item(i)!.textContent,
          ],
          [
            String.fromCharCode(Icons.delete_outlined.codePoint),
            String.fromCharCode(Icons.search.codePoint),
          ],
          reason: kit.name,
        );
        host.remove();
      }
    });

    test('size, colour and family are its own when stated', () async {
      await renderer.render(
        UIBuilder.icon(
          codepoint: 0xf101,
          size: 32,
          color: '#ff0000',
          fontFamily: 'My Icons',
          semanticLabel: 'Home',
        ),
      );

      expect(style('Icon', 'font-size'), '32px');
      expect(style('Icon', 'color'), 'rgb(255, 0, 0)');
      expect(style('Icon', 'font-family'), '"My Icons"');
      expect(of('Icon').getAttribute('role'), 'img');
      expect(of('Icon').getAttribute('aria-label'), 'Home');
      expect(of('Icon').hasAttribute('aria-hidden'), isFalse);
    });

    test('with no colour it takes the colour of what it is in', () async {
      await renderer.render(
        UIBuilder.box(
          color: '#102030',
          child: UIBuilder.icon(codepoint: 0xe88a),
        ),
      );

      expect(style('Icon', 'color'), isEmpty);
      // The box said white-on-navy, and the glyph is text inside it.
      expect(
        web.window.getComputedStyle(of('Icon')).color,
        'rgb(255, 255, 255)',
      );
    });
  });

  group('text', () {
    test('alignment, spacing, line height, family, italic', () async {
      await renderer.render(
        UIBuilder.text(
          'Hello',
          textAlign: 'center',
          letterSpacing: 1.5,
          lineHeight: 1.8,
          fontFamily: 'Fira Code',
          italic: true,
          selectable: true,
        ),
      );

      expect(style('Text', 'text-align'), 'center');
      // A block, or there would be no width to centre within.
      expect(style('Text', 'display'), 'block');
      expect(style('Text', 'letter-spacing'), '1.5px');
      expect(style('Text', 'line-height'), '1.8');
      expect(style('Text', 'font-family'), '"Fira Code", sans-serif');
      expect(style('Text', 'font-style'), 'italic');
      expect(style('Text', 'user-select'), 'text');
    });

    test('a generic family is not quoted into a name', () async {
      await renderer.render(UIBuilder.text('x', fontFamily: 'monospace'));

      expect(style('Text', 'font-family'), 'monospace');
    });

    test('alignment does not undo a line clamp', () async {
      await renderer.render(
        UIBuilder.text('x', textAlign: 'right', maxLines: 2),
      );

      expect(style('Text', 'display'), '-webkit-box');
      expect(style('Text', 'text-align'), 'right');
    });

    test('spans are child runs, each with only its own style', () async {
      await renderer.render(
        UIBuilder.text(
          'Hello big world',
          color: '#111111',
          spans: [
            {'text': 'Hello '},
            {
              'text': 'big',
              'color': '#80ff0000',
              'fontSize': 20.0,
              'fontWeight': 700,
              'italic': true,
              'decoration': 'underline',
            },
            {'text': ' world'},
          ],
        ),
      );

      final text = of('Text');
      expect(text.textContent, 'Hello big world');
      expect(text.children.length, 3);
      final plain = text.children.item(0)! as web.HTMLElement;
      final big = text.children.item(1)! as web.HTMLElement;
      expect(plain.getAttribute('style'), isNull);
      expect(big.style.getPropertyValue('color'), startsWith('rgba(255, 0, 0'));
      expect(big.style.getPropertyValue('font-size'), '20px');
      expect(big.style.getPropertyValue('font-weight'), '700');
      expect(big.style.getPropertyValue('font-style'), 'italic');
      expect(big.style.getPropertyValue('text-decoration'), 'underline');
      // What a run does not say, it inherits from the node.
      expect(style('Text', 'color'), 'rgb(17, 17, 17)');
    });
  });

  group('layout', () {
    test('a column takes its size, its spacing and the two new alignments',
        () async {
      await renderer.render(
        UIBuilder.column(
          mainAxisAlignment: 'spaceEvenly',
          mainAxisSize: 'min',
          spacing: 12,
          children: [UIBuilder.text('a')],
        ),
      );

      final column = of('Column');
      expect(column.classList.contains('dnn-column--main-spaceEvenly'), isTrue);
      expect(column.classList.contains('dnn-column--size-min'), isTrue);
      expect(column.style.getPropertyValue('gap'), '12px');

      await renderer.render(
        UIBuilder.column(
          mainAxisAlignment: 'spaceAround',
          mainAxisSize: 'max',
          children: [UIBuilder.text('a')],
        ),
      );
      expect(of('Column').classList.contains('dnn-column--main-spaceAround'),
          isTrue);
      expect(of('Column').classList.contains('dnn-column--size-max'), isTrue);
    });

    test('a row takes a cross alignment, a size and the new alignments',
        () async {
      await renderer.render(
        UIBuilder.row(
          mainAxisAlignment: 'spaceAround',
          crossAxisAlignment: 'stretch',
          mainAxisSize: 'min',
          children: [UIBuilder.text('a')],
        ),
      );

      final classes = of('Row').classList;
      expect(classes.contains('dnn-row--spaceAround'), isTrue);
      expect(classes.contains('dnn-row--cross-stretch'), isTrue);
      expect(classes.contains('dnn-row--size-min'), isTrue);
    });

    test('a wrap aligns along its lines and across them', () async {
      await renderer.render(
        UIBuilder.wrap(
          alignment: 'spaceBetween',
          crossAxisAlignment: 'end',
          children: [UIBuilder.text('a')],
        ),
      );
      expect(style('Wrap', 'justify-content'), 'space-between');
      expect(style('Wrap', 'align-items'), 'flex-end');

      await renderer.render(UIBuilder.wrap(children: [UIBuilder.text('a')]));
      // The start is the default the tree leaves out.
      expect(style('Wrap', 'align-items'), 'flex-start');
      expect(style('Wrap', 'justify-content'), isEmpty);
    });

    test('a loose expanded keeps its share but not its stretch', () async {
      await renderer.render(
        UIBuilder.row(
          children: [
            UIBuilder.expanded(child: UIBuilder.text('a'), fit: 'loose', flex: 2),
          ],
        ),
      );

      expect(of('Expanded').classList.contains('dnn-expanded--loose'), isTrue);
      expect(style('Expanded', 'flex'), startsWith('2 1 0'));
    });
  });

  group('a button', () {
    for (final kit in _kits) {
      test('${kit.name}: outlined and tonal are drawn as themselves', () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);

        await renderer.render(
          UIBuilder.column(
            children: [
              UIBuilder.button(label: 'P', eventId: 'e', id: 'p'),
              UIBuilder.button(
                label: 'O',
                eventId: 'e',
                variant: 'outlined',
                id: 'o',
              ),
              UIBuilder.button(
                label: 'T',
                eventId: 'e',
                variant: 'tonal',
                id: 't',
              ),
            ],
          ),
        );

        String classes(String id) => web.document.getElementById(id)!.className;
        // Each variant has a class naming it, which the kit's stylesheet
        // draws, and neither is the filled primary button.
        expect(classes('o'), contains('--outlined'));
        expect(classes('t'), contains('--tonal'));
        expect(classes('o'), isNot(classes('p')));
        expect(classes('t'), isNot(classes('p')));
        expect(classes('o'), isNot(contains('raised')));
        expect(classes('t'), isNot(contains('raised')));
      });

      test('${kit.name}: an icon goes before the label, and stays out of the '
          'name', () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);

        await renderer.render(
          UIBuilder.button(
            label: 'Add',
            eventId: 'e',
            // Flutter's `Icons.add`.
            iconCodepoint: 0xe047,
            foregroundColor: '#ff0000',
            expand: true,
          ),
        );

        final button =
            root.querySelector('[data-type="Button"]')! as web.HTMLElement;
        final icon = button.firstElementChild!;
        expect(icon.textContent, String.fromCharCode(0xe047));
        expect(icon.getAttribute('aria-hidden'), 'true');
        expect(button.textContent, endsWith('Add'));
        expect(button.style.getPropertyValue('color'), 'rgb(255, 0, 0)');
        expect(button.classList.contains('dnn-button--expand'), isTrue);
      });
    }
  });

  group('an icon button', () {
    for (final kit in _kits) {
      test('${kit.name}: colour, size and disabled', () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);
        var taps = 0;
        renderer.onEvent('e', (_) => taps++);

        await renderer.render(
          UIBuilder.iconButton(
            icon: 'delete',
            eventId: 'e',
            tooltip: 'Delete',
            color: '#80ff0000',
            size: 32,
            disabled: true,
          ),
        );

        final button =
            root.querySelector('[data-type="IconButton"]')! as web.HTMLElement;
        expect(button.style.getPropertyValue('color'),
            startsWith('rgba(255, 0, 0, 0.5'));
        expect(button.style.getPropertyValue('width'), '48px');
        expect(
          (button.querySelector('i')! as web.HTMLElement)
              .style
              .getPropertyValue('font-size'),
          '32px',
        );
        expect(button.hasAttribute('disabled'), isTrue);
        button.click();
        expect(taps, 0);
      });
    }
  });

  group('a text field', () {
    WidgetNode field(Map<String, dynamic> extra) => node('TextField', {
      'hint': 'Hint',
      'eventId': 'f',
      'obscureText': false,
      'enabled': true,
      'maxLines': 1,
      'textInputAction': 'done',
      ...extra,
    });

    web.HTMLInputElement input() =>
        root.querySelector('input')! as web.HTMLInputElement;

    test('the keyboard type is an inputmode, and the input stays text',
        () async {
      for (final (type, mode) in [
        ('number', 'numeric'),
        ('decimal', 'decimal'),
        ('email', 'email'),
        ('phone', 'tel'),
        ('url', 'url'),
      ]) {
        await renderer.render(field({'keyboardType': type}));
        expect(input().getAttribute('inputmode'), mode, reason: type);
        expect(input().type, 'text', reason: type);
      }

      await renderer.render(field({}));
      expect(input().hasAttribute('inputmode'), isFalse);
    });

    test('read-only, length, capitalisation and alignment', () async {
      await renderer.render(
        field({
          'readOnly': true,
          'maxLength': 12,
          'textCapitalization': 'words',
          'textAlign': 'right',
        }),
      );

      expect(input().readOnly, isTrue);
      expect(input().maxLength, 12);
      expect(input().getAttribute('autocapitalize'), 'words');
      expect(input().style.getPropertyValue('text-align'), 'right');

      // And all of it goes again, on the same input.
      final before = input();
      await renderer.render(field({}));
      expect(input(), same(before));
      expect(input().readOnly, isFalse);
      expect(input().hasAttribute('maxlength'), isFalse);
      expect(input().hasAttribute('autocapitalize'), isFalse);
      expect(input().style.getPropertyValue('text-align'), isEmpty);
    });

    test('a tappable field sends _tap, and only while it is tappable',
        () async {
      var taps = 0;
      renderer.onEvent('f_tap', (_) => taps++);
      await renderer.render(field({'readOnly': true, 'tappable': true}));

      input().click();
      expect(taps, 1);

      await renderer.render(field({'readOnly': true}));
      input().click();
      expect(taps, 1);
    });

    test('a helper sits under the field until an error takes its place',
        () async {
      await renderer.render(field({'helper': 'At least 8 characters'}));

      final helper = root.querySelector('[data-part="helper"]')!;
      expect(helper.textContent, 'At least 8 characters');
      expect(helper.hasAttribute('hidden'), isFalse);
      expect(input().getAttribute('aria-describedby'), helper.id);

      await renderer.render(
        field({'helper': 'At least 8 characters', 'error': 'Too short'}),
      );
      expect(helper.hasAttribute('hidden'), isTrue);
      expect(input().getAttribute('aria-describedby'), 'dnn-error-f');
    });

    test('a field with no helper has no helper element', () async {
      await renderer.render(field({}));

      expect(root.querySelector('[data-part="helper"]'), isNull);
    });

    for (final kit in _kits) {
      test('${kit.name}: glyphs at both ends, and a suffix that can be tapped',
          () async {
        final root = mountRoot();
        addTearDown(() => root.remove());
        final renderer = WebUIRenderer(root: root, kit: kit, animations: false);
        var taps = 0;
        renderer.onEvent('f_suffix', (_) => taps++);

        await renderer.render(
          field({
            'prefixIcon': 0xe567,
            'suffixIcon': 0xe16a,
            'suffixTappable': true,
          }),
        );

        final prefix = root.querySelector('[data-part="prefix"]')!;
        final suffix =
            root.querySelector('[data-part="suffix"]')! as web.HTMLElement;
        expect(prefix.textContent, String.fromCharCode(0xe567));
        expect(suffix.textContent, String.fromCharCode(0xe16a));
        expect(suffix.tagName, 'BUTTON');
        // All three in the box the glyphs are pinned to.
        final input = root.querySelector('input')!;
        expect(prefix.parentElement, same(input.parentElement));
        expect(input.parentElement!.className, 'dnn-textfield__box');

        suffix.click();
        expect(taps, 1);
      });
    }

    test('a suffix that changes glyph keeps the caret in the field', () async {
      await renderer.render(
        field({
          'suffixIcon': 0xe8f4,
          'suffixTappable': true,
          'obscureText': true,
        }),
      );
      final before = input()..focus();
      expect(before.type, 'password');

      // A show-password button: another glyph, and the text shown.
      await renderer.render(
        field({
          'suffixIcon': 0xe8f5,
          'suffixTappable': true,
          'obscureText': false,
        }),
      );

      expect(input(), same(before));
      expect(web.document.activeElement, same(before));
      expect(before.type, 'text');
      expect(root.querySelector('[data-part="suffix"]')!.textContent,
          String.fromCharCode(0xe8f5));
    });

    test('a suffix that only decorates is not a button', () async {
      await renderer.render(field({'suffixIcon': 0xe5cd}));

      final suffix = root.querySelector('[data-part="suffix"]')!;
      expect(suffix.tagName, 'I');
      expect(suffix.getAttribute('aria-hidden'), 'true');
    });
  });

  group('a Flutter slot', () {
    test('is the room the widget would have taken, with the fallback in it',
        () async {
      await renderer.render(
        UIBuilder.flutterSlot(
          slotId: 'banner',
          height: 50,
          width: 320,
          fallback: UIBuilder.text('Ad'),
        ),
      );

      final slot = of('FlutterSlot');
      expect(slot.style.getPropertyValue('height'), '50px');
      expect(slot.style.getPropertyValue('width'), '320px');
      expect(slot.id, 'slot_banner');
      expect(childTypes(slot), ['Text']);
    });

    test('with no fallback it is an empty box of that size', () async {
      final error = await renderer.render(
        UIBuilder.flutterSlot(slotId: 'banner', height: 90),
      );

      expect(error, isNull);
      expect(of('FlutterSlot').children.length, 0);
      expect(style('FlutterSlot', 'height'), '90px');
      expect(style('FlutterSlot', 'width'), isEmpty);
    });
  });

  test('none of the new node types is unknown to the renderer', () async {
    final error = await renderer.render(
      UIBuilder.column(
        children: [
          for (final type in const [
            'Box',
            'Stack',
            'Positioned',
            'Scroll',
            'Icon',
            'Canvas',
            'Dropdown',
            'BottomBar',
            'BottomNavigation',
            'FlutterSlot',
          ])
            node(type, const {}),
        ],
      ),
    );

    expect(error, isNull);
    expect(root.querySelector('.dnn-unknown'), isNull);
  });
}
