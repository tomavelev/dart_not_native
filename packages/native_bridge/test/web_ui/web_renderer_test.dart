@TestOn('browser')
/// Widget tests for the web target.
///
/// The framework renders real DOM (no canvas), so these are the equivalent of
/// Flutter widget tests: mount a tree, inspect the elements, dispatch real
/// browser events and assert what the user would see.
///
/// Run with: flutter test --platform chrome
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/kits/materialize_kit.dart';
import 'package:dart_not_native/web_ui/kits/mdl_kit.dart';
import 'package:dart_not_native/web_ui/style_kit.dart';
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

  group('layout primitives', () {
    test('a scaffold renders its app bar, body and fab in order', () async {
      await renderer.render(
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'Demo'),
          body: UIBuilder.center(child: UIBuilder.text('Body')),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'Add',
            eventId: 'add',
          ),
        ),
      );

      final scaffold = root.querySelector('[data-type="Scaffold"]')!;
      expect(childTypes(scaffold), [
        'AppBar',
        'Center',
        'FloatingActionButton',
      ]);
      expect(scaffold.textContent, contains('Demo'));
      expect(scaffold.textContent, contains('Body'));
    });

    test('column and row keep their alignment and spacing', () async {
      await renderer.render(
        UIBuilder.column(
          crossAxisAlignment: 'stretch',
          children: [
            UIBuilder.row(
              mainAxisAlignment: 'spaceBetween',
              spacing: 12,
              children: [UIBuilder.text('a'), UIBuilder.text('b')],
            ),
          ],
        ),
      );

      final column =
          root.querySelector('[data-type="Column"]') as web.HTMLElement;
      final row = root.querySelector('[data-type="Row"]') as web.HTMLElement;

      expect(column.className, contains('dnn-column--stretch'));
      expect(row.className, contains('dnn-row--spaceBetween'));
      expect(row.style.getPropertyValue('gap'), '12px');
    });

    test('sizes and paddings become inline styles', () async {
      await renderer.render(
        UIBuilder.column(
          children: [
            UIBuilder.padding(all: 24, child: UIBuilder.text('padded')),
            UIBuilder.sizedBox(height: 8, width: 16),
            UIBuilder.expanded(child: UIBuilder.text('grow'), flex: 3),
          ],
        ),
      );

      final padding =
          root.querySelector('[data-type="Padding"]') as web.HTMLElement;
      final box =
          root.querySelector('[data-type="SizedBox"]') as web.HTMLElement;
      final expanded =
          root.querySelector('[data-type="Expanded"]') as web.HTMLElement;

      expect(padding.style.getPropertyValue('padding'), '24px');
      expect(box.style.getPropertyValue('height'), '8px');
      expect(box.style.getPropertyValue('width'), '16px');
      expect(expanded.style.getPropertyValue('flex'), startsWith('3 1 0'));
    });

    test('a button drawn to a stated shape carries it inline', () async {
      await renderer.render(
        UIBuilder.button(
          label: 'exact',
          eventId: 'e',
          minHeight: 30,
          minWidth: 120,
          fontSize: 11,
          paddingHorizontal: 6,
          paddingVertical: 2,
        ),
      );

      final button =
          root.querySelector('[data-type="Button"]') as web.HTMLElement;

      // The size classes set a fixed height; a stated one has to win, so the
      // class's height gives way to min-height.
      expect(button.style.getPropertyValue('height'), 'auto');
      expect(button.style.getPropertyValue('min-height'), '30px');
      expect(button.style.getPropertyValue('min-width'), '120px');
      expect(button.style.getPropertyValue('font-size'), '11px');
      expect(button.style.getPropertyValue('padding'), '2px 6px');
    });

    test('a column carries how it distributes its children', () async {
      await renderer.render(
        UIBuilder.column(
          crossAxisAlignment: 'stretch',
          mainAxisAlignment: 'spaceBetween',
          children: [UIBuilder.text('top'), UIBuilder.text('bottom')],
        ),
      );

      final column = root.querySelector('[data-type="Column"]')!;

      // Two axes, two classes: the stylesheet turns them into align-items and
      // justify-content (asserted against the shipped file in
      // column_alignment_css_test.dart).
      expect(column.classList.contains('dnn-column--stretch'), isTrue);
      expect(column.classList.contains('dnn-column--main-spaceBetween'), isTrue);
    });

    test('padding that differs per edge keeps each of them', () async {
      await renderer.render(
        UIBuilder.padding(
          left: 8,
          top: 24,
          right: 4,
          bottom: 0,
          child: UIBuilder.text('padded'),
        ),
      );

      final padding =
          root.querySelector('[data-type="Padding"]') as web.HTMLElement;

      // CSS order is top right bottom left, which is not the order the
      // protocol writes them in - so this is the mapping, not a formality.
      expect(padding.style.getPropertyValue('padding'), '24px 4px 0px 8px');
    });

    test('text styling reaches the element', () async {
      await renderer.render(
        UIBuilder.text(
          'styled',
          fontSize: 20,
          fontWeight: 700,
          color: 'rgb(255, 0, 0)',
          decoration: 'lineThrough',
        ),
      );

      final text = root.querySelector('[data-type="Text"]') as web.HTMLElement;

      expect(text.textContent, 'styled');
      expect(text.style.getPropertyValue('font-size'), '20px');
      expect(text.style.getPropertyValue('font-weight'), '700');
      expect(text.style.getPropertyValue('text-decoration'), 'line-through');
    });

    test(
      'an id prop becomes the element id, which is how e2e tests select',
      () async {
        await renderer.render(UIBuilder.text('0', id: 'counter_value'));

        expect(web.document.getElementById('counter_value')!.textContent, '0');
      },
    );

    test('an unknown node type renders a visible placeholder', () async {
      await renderer.render(const WidgetNode(type: 'Hologram', props: {}));

      expect(root.textContent, contains('Unknown widget: Hologram'));
    });
  });

  group('images', () {
    test('render with their source, alt text and fit', () async {
      await renderer.render(
        UIBuilder.image(
          src: 'logo.png',
          alt: 'Company logo',
          width: 120,
          height: 80,
          fit: 'contain',
          id: 'logo',
        ),
      );

      final image =
          web.document.getElementById('logo')! as web.HTMLImageElement;
      expect(image.tagName.toLowerCase(), 'img');
      expect(image.getAttribute('src'), 'logo.png');
      expect(image.alt, 'Company logo', reason: 'also the accessible name');
      expect(image.style.getPropertyValue('width'), '120px');
      expect(image.style.getPropertyValue('height'), '80px');
      expect(image.style.getPropertyValue('object-fit'), 'contain');
    });

    test('default to covering the box they are given', () async {
      await renderer.render(UIBuilder.image(src: 'a.png', alt: 'A', id: 'a'));

      final image = web.document.getElementById('a')! as web.HTMLElement;
      expect(image.style.getPropertyValue('object-fit'), 'cover');
    });

    test('every fit maps onto a CSS value', () async {
      for (final fit in ['cover', 'contain', 'fill', 'none', 'scaleDown']) {
        await renderer.render(
          UIBuilder.image(src: 'a.png', alt: 'A', fit: fit, id: 'a'),
        );

        final image = web.document.getElementById('a')! as web.HTMLElement;
        expect(
          image.style.getPropertyValue('object-fit'),
          isNotEmpty,
          reason: '$fit has no mapping',
        );
      }
    });
  });

  group('events', () {
    test('a button click dispatches its event with the node payload', () async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('delete', received.add);
      await renderer.render(
        UIBuilder.button(
          label: 'Delete',
          eventId: 'delete',
          data: {'id': 7},
          id: 'delete_btn',
        ),
      );

      click('delete_btn');

      expect(received, [
        {'id': 7},
      ]);
    });

    test('a disabled button is disabled in the DOM', () async {
      await renderer.render(
        UIBuilder.button(
          label: 'Save',
          eventId: 'save',
          disabled: true,
          id: 'save_btn',
        ),
      );

      final button = web.document.getElementById('save_btn')!;

      expect(button.hasAttribute('disabled'), isTrue);
    });

    test('a checkbox reports its new state plus the node payload', () async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('toggle', received.add);
      await renderer.render(
        withId(
          UIBuilder.checkbox(
            eventId: 'toggle',
            checked: false,
            data: {'id': 3},
          ),
          'todo_3_done',
        ),
      );

      final checkbox = inputInside('todo_3_done');
      checkbox.checked = true;
      checkbox.dispatchEvent(web.Event('change'));

      expect(received, [
        {'id': 3, 'checked': true},
      ]);
    });

    test('an icon button exposes its tooltip to assistive tech', () async {
      await renderer.render(
        UIBuilder.iconButton(
          icon: 'delete',
          eventId: 'delete',
          tooltip: 'Delete item',
        ),
      );

      final button = root.querySelector('[data-type="IconButton"]')!;

      expect(button.getAttribute('aria-label'), 'Delete item');
      expect(button.getAttribute('title'), 'Delete item');
    });

    test('a text field emits change, submit, focus and blur', () async {
      final events = <String>[];
      final values = <String>[];
      for (final suffix in ['change', 'submit', 'focus', 'blur']) {
        renderer.onEvent('name_$suffix', (data) {
          events.add(suffix);
          values.add(data['value'] as String);
        });
      }
      await renderer.render(
        withId(
          UIBuilder.textField(hint: 'Name', eventId: 'name'),
          'name_field',
        ),
      );

      final input = inputInside('name_field');
      input.value = 'Ada';
      input.dispatchEvent(web.Event('input'));
      input.dispatchEvent(web.Event('focus'));
      input.dispatchEvent(web.Event('blur'));
      input.dispatchEvent(enterKey());

      expect(events, ['change', 'focus', 'blur', 'submit']);
      expect(values.toSet(), {'Ada'});
    });

    test('events with no handler are reported rather than thrown', () async {
      final result = await renderer.handleEvent('nobody_listens', {});

      expect(result['success'], isFalse);
    });
  });

  group('text fields', () {
    test('render hint, label and error', () async {
      await renderer.render(
        withId(
          UIBuilder.textField(
            hint: 'you@example.com',
            eventId: 'email',
            label: 'Email',
            error: 'Invalid email',
          ),
          'email_field',
        ),
      );

      final field = web.document.getElementById('email_field')!;

      expect(
        inputInside('email_field').getAttribute('placeholder'),
        'you@example.com',
      );
      expect(field.querySelector('[data-part="label"]')!.textContent, 'Email');
      expect(
        field.querySelector('[data-part="error"]')!.textContent,
        'Invalid email',
      );
    });

    test('honour the iOS placeholder prop as well as hint', () async {
      await renderer.render(
        withId(
          iOSUIBuilder.textField(placeholder: 'Name', eventId: 'name'),
          'name_field',
        ),
      );

      expect(inputInside('name_field').getAttribute('placeholder'), 'Name');
    });

    test('obscureText becomes a password input, maxLines a textarea', () async {
      await renderer.render(
        UIBuilder.column(
          children: [
            withId(
              UIBuilder.textField(hint: '', eventId: 'pw', obscureText: true),
              'pw_field',
            ),
            withId(
              UIBuilder.textField(hint: '', eventId: 'bio', maxLines: 4),
              'bio_field',
            ),
          ],
        ),
      );

      expect(inputInside('pw_field').getAttribute('type'), 'password');
      final bio = web.document
          .getElementById('bio_field')!
          .querySelector('[data-part="input"]')!;
      expect(bio.tagName.toLowerCase(), 'textarea');
      expect(bio.getAttribute('rows'), '4');
    });

    test('disabled fields are disabled in the DOM', () async {
      await renderer.render(
        withId(
          UIBuilder.textField(hint: '', eventId: 'x', enabled: false),
          'x_field',
        ),
      );

      expect(inputInside('x_field').hasAttribute('disabled'), isTrue);
    });
  });

  group('reconciliation', () {
    test('an unchanged node keeps its element', () async {
      final tree = UIBuilder.column(children: [UIBuilder.text('same')]);
      await renderer.render(tree);
      final before = root.querySelector('[data-type="Text"]');

      await renderer.render(
        UIBuilder.column(children: [UIBuilder.text('same')]),
      );

      expect(
        identical(root.querySelector('[data-type="Text"]'), before),
        isTrue,
      );
    });

    test('a changed node is rebuilt', () async {
      await renderer.render(UIBuilder.text('before'));

      await renderer.render(UIBuilder.text('after'));

      expect(root.querySelector('[data-type="Text"]')!.textContent, 'after');
      expect(root.children.length, 1);
    });

    test('removed children are dropped from the DOM', () async {
      await renderer.render(
        UIBuilder.column(
          children: [
            UIBuilder.text('a'),
            UIBuilder.text('b'),
            UIBuilder.text('c'),
          ],
        ),
      );

      await renderer.render(UIBuilder.column(children: [UIBuilder.text('a')]));

      expect(root.querySelectorAll('[data-type="Text"]').length, 1);
    });

    test('only the nodes that changed are rebuilt', () async {
      WidgetNode list(int completed) => UIBuilder.column(
        children: [
          for (var i = 1; i <= 20; i++)
            UIBuilder.text(
              'item $i',
              id: 'item_$i',
              decoration: i <= completed ? 'lineThrough' : null,
            ),
        ],
      );
      await renderer.render(list(1));

      renderer.debugCreateCount = 0;
      await renderer.render(list(2));

      expect(
        renderer.debugCreateCount,
        1,
        reason: 'one item changed, so one element is rebuilt',
      );
    });

    test('an unchanged tree touches nothing', () async {
      final tree = UIBuilder.column(children: [UIBuilder.text('same')]);
      await renderer.render(tree);

      renderer.debugCreateCount = 0;
      await renderer.render(
        UIBuilder.column(children: [UIBuilder.text('same')]),
      );

      expect(renderer.debugCreateCount, 0);
    });

    test('prepending to a list moves the rows it already has', () async {
      WidgetNode list(List<int> ids) => UIBuilder.column(
        children: [
          for (final id in ids) UIBuilder.text('item $id', id: 'item_$id'),
        ],
      );
      await renderer.render(list([2, 3]));
      final second = web.document.getElementById('item_2');

      renderer.debugCreateCount = 0;
      await renderer.render(list([1, 2, 3]));

      expect(renderer.debugCreateCount, 1, reason: 'only the new row is built');
      expect(identical(web.document.getElementById('item_2'), second), isTrue);
      expect(idsOf(root, '[data-type="Text"]'), ['item_1', 'item_2', 'item_3']);
    });

    test('reordering a list moves rows rather than rebuilding them', () async {
      WidgetNode list(List<int> ids) => UIBuilder.column(
        children: [
          for (final id in ids) UIBuilder.text('item $id', id: 'item_$id'),
        ],
      );
      await renderer.render(list([1, 2, 3]));
      final first = web.document.getElementById('item_1');

      renderer.debugCreateCount = 0;
      await renderer.render(list([3, 1, 2]));

      expect(renderer.debugCreateCount, 0, reason: 'every row already exists');
      expect(identical(web.document.getElementById('item_1'), first), isTrue);
      expect(idsOf(root, '[data-type="Text"]'), ['item_3', 'item_1', 'item_2']);
    });

    test('removing from the middle keeps the rows around it', () async {
      WidgetNode list(List<int> ids) => UIBuilder.column(
        children: [
          for (final id in ids) UIBuilder.text('item $id', id: 'item_$id'),
        ],
      );
      await renderer.render(list([1, 2, 3]));
      final third = web.document.getElementById('item_3');

      renderer.debugCreateCount = 0;
      await renderer.render(list([1, 3]));

      expect(renderer.debugCreateCount, 0);
      expect(identical(web.document.getElementById('item_3'), third), isTrue);
      expect(root.querySelectorAll('[data-type="Text"]').length, 2);
    });

    test('renders in one tick are coalesced into a single pass', () async {
      await renderer.render(UIBuilder.text('0', id: 'v'));

      renderer.debugCreateCount = 0;
      renderer.render(UIBuilder.text('1', id: 'v'));
      renderer.render(UIBuilder.text('2', id: 'v'));
      await renderer.render(UIBuilder.text('3', id: 'v'));

      expect(
        renderer.debugCreateCount,
        1,
        reason: 'only the last tree reaches the DOM',
      );
      expect(web.document.getElementById('v')!.textContent, '3');
    });

    test(
      'an unbatched renderer has updated the DOM when render returns',
      () async {
        final host = mountRoot();
        final sync = WebUIRenderer(
          root: host,
          animations: false,
          batched: false,
        );

        sync.render(UIBuilder.text('now', id: 'sync_text'));

        expect(host.textContent, 'now');
        host.remove();
      },
    );

    test(
      'a text field keeps focus and caret while the app re-renders',
      () async {
        Future<void> renderWith(String value) => renderer.render(
          UIBuilder.column(
            children: [
              UIBuilder.text('todos: $value'),
              withId(
                UIBuilder.textField(
                  hint: 'Add a todo',
                  eventId: 'new_todo',
                  initialValue: '',
                ),
                'new_todo_field',
              ),
            ],
          ),
        );

        await renderWith('0');
        final input = inputInside('new_todo_field');
        input.focus();
        input.value = 'Buy milk';
        input.setSelectionRange(3, 3);

        await renderWith('1');

        expect(
          identical(inputInside('new_todo_field'), input),
          isTrue,
          reason: 'the element must survive the re-render',
        );
        expect(web.document.activeElement, input);
        expect(input.value, 'Buy milk');
        expect(input.selectionStart, 3);
      },
    );

    test('the app can clear a text field by changing its value', () async {
      Future<void> renderWith(String value) => renderer.render(
        withId(
          UIBuilder.textField(
            hint: 'Add a todo',
            eventId: 'new_todo',
            initialValue: value,
          ),
          'new_todo_field',
        ),
      );

      await renderWith('draft');
      expect(inputInside('new_todo_field').value, 'draft');

      await renderWith('');

      expect(inputInside('new_todo_field').value, '');
    });
  });

  group('style kits', () {
    test('each kit renders the same tree with its own markup', () async {
      final tree = UIBuilder.button(label: 'Save', eventId: 'save');

      for (final kit in const <WebStyleKit>[
        MdlKit(),
        MaterializeKit(),
        PlainKit(),
      ]) {
        final host = mountRoot();
        await WebUIRenderer(
          root: host,
          kit: kit,
          animations: false,
        ).render(tree);

        final button = host.querySelector('[data-type="Button"]')!;
        expect(button.textContent, contains('Save'), reason: kit.name);
        expect(
          button.tagName.toLowerCase(),
          anyOf('button', 'a'),
          reason: kit.name,
        );
        host.remove();
      }
    });

    test('every kit declares a name and stylesheets', () {
      for (final kit in const <WebStyleKit>[
        MdlKit(),
        MaterializeKit(),
        PlainKit(),
      ]) {
        expect(kit.name, isNotEmpty);
        expect(kit.stylesheets, isNotEmpty);
      }
    });
  });

  group('alerts and loading', () {
    test('an alert is announced and can be dismissed', () async {
      await renderer.render(
        withId(DSAlert.error(message: 'Save failed', title: 'Oops'), 'alert'),
      );

      final alert = web.document.getElementById('alert') as web.HTMLElement;
      expect(alert.getAttribute('role'), 'alert');
      expect(alert.textContent, contains('Save failed'));

      final close =
          alert.querySelector('[aria-label="Dismiss"]') as web.HTMLElement?;
      expect(close, isNotNull);
      close!.click();

      expect(alert.style.getPropertyValue('display'), 'none');
    });

    test(
      'animations can be switched off for deterministic screenshots',
      () async {
        final still = mountRoot();
        await WebUIRenderer(
          root: still,
          animations: false,
        ).render(DSLoading.spinner());
        final moving = mountRoot();
        await WebUIRenderer(
          root: moving,
          animations: true,
        ).render(DSLoading.spinner());

        expect(
          still.querySelector('.dnn-spinner')!.className,
          isNot(contains('dnn-animate')),
        );
        expect(
          moving.querySelector('.dnn-spinner')!.className,
          contains('dnn-animate'),
        );
        still.remove();
        moving.remove();
      },
    );
  });

  group('the whole component vocabulary renders', () {
    test('no builder produces an unknown widget', () async {
      await renderer.render(
        UIBuilder.column(
          children: [
            UIBuilder.appBar(title: 'Bar'),
            UIBuilder.text('text'),
            UIBuilder.button(label: 'b', eventId: 'e'),
            UIBuilder.iconButton(icon: 'add', eventId: 'e', tooltip: 't'),
            UIBuilder.floatingActionButton(tooltip: 't', eventId: 'e'),
            UIBuilder.checkbox(eventId: 'e', checked: false),
            UIBuilder.textField(hint: 'h', eventId: 'e'),
            UIBuilder.sizedBox(height: 1),
            UIBuilder.center(child: UIBuilder.text('c')),
            UIBuilder.padding(all: 1, child: UIBuilder.text('p')),
            UIBuilder.row(children: [UIBuilder.text('r')]),
            UIBuilder.expanded(child: UIBuilder.text('e')),
            DSButton.primary(label: 'p', eventId: 'e'),
            DSCard.elevated(content: UIBuilder.text('card'), title: 'Card'),
            DSBadge.solid(label: 'badge'),
            DSCheckbox.input(eventId: 'e'),
            DSRadio.input(eventId: 'e', value: 'v'),
            DSToggle.input(eventId: 'e'),
            DSDivider.horizontal(),
            DSDivider.vertical(),
            DSLoading.spinner(),
            DSLoading.progressLinear(value: 0.5),
            DSLoading.progressCircular(value: 0.5),
            DSLoading.skeleton(),
            DSLoading.pulse(child: UIBuilder.text('pulse')),
            DSAlert.info(message: 'info'),
            DSSpacing.md(),
            AndroidUIBuilder.materialButton(label: 'm', eventId: 'e'),
            AndroidUIBuilder.listView(
              children: [
                AndroidUIBuilder.listItem(text: 'item', subtitle: 's'),
              ],
            ),
            AndroidUIBuilder.textField(hint: 'h', eventId: 'e'),
            iOSUIBuilder.navigationBar(title: 'nav'),
            iOSUIBuilder.vStack(children: [UIBuilder.text('v')]),
            iOSUIBuilder.hStack(children: [UIBuilder.text('h')]),
            iOSUIBuilder.button(label: 'i', eventId: 'e'),
            iOSUIBuilder.list(children: [iOSUIBuilder.listRow(text: 'row')]),
            iOSUIBuilder.spacer(),
            iOSUIBuilder.textField(placeholder: 'p', eventId: 'e'),
          ],
        ),
      );

      expect(root.querySelectorAll('.dnn-unknown').length, 0);
      expect(root.textContent, isNot(contains('Unknown widget')));
    });

    test('a card renders its title and hosts its content', () async {
      await renderer.render(
        DSCard.elevated(
          content: UIBuilder.text('card body'),
          title: 'Card title',
        ),
      );

      final card = root.querySelector('[data-type="Card"]')!;

      expect(card.textContent, contains('Card title'));
      expect(card.textContent, contains('card body'));
    });

    test('a list renders one element per row', () async {
      await renderer.render(
        AndroidUIBuilder.listView(
          children: [
            AndroidUIBuilder.listItem(text: 'One', subtitle: 'first'),
            AndroidUIBuilder.listItem(text: 'Two'),
          ],
        ),
      );

      final items = root.querySelectorAll('[data-type="ListItem"]');

      expect(items.length, 2);
      expect(items.item(0)!.textContent, contains('One'));
      expect(items.item(0)!.textContent, contains('first'));
    });
  });
}
