@TestOn('browser')
/// Choosing: a dropdown, and the date and time pickers.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<String> events;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    events = [];
    for (final id in ['fruit', 'picked', 'dismissed']) {
      renderer.onEvent(id, (data) => events.add('$id $data'));
    }
  });
  tearDown(() => root.remove());

  group('a dropdown', () {
    WidgetNode dropdown({
      int? selected,
      List<String> items = const ['Apples', 'Pears', 'Plums'],
      String? label = 'Fruit',
      String? hint = 'Pick one',
      String? error,
      bool enabled = true,
    }) => UIBuilder.dropdown(
      items: items,
      selectedIndex: selected,
      eventId: 'fruit',
      label: label,
      hint: hint,
      error: error,
      enabled: enabled,
    );

    web.HTMLSelectElement select() =>
        root.querySelector('select')! as web.HTMLSelectElement;
    List<String> options() => [
      for (var i = 0; i < select().options.length; i++)
        select().options.item(i)!.textContent ?? '',
    ];

    test('is a select, named by its label', () async {
      await renderer.render(dropdown(selected: 1));

      final label = root.querySelector('label')! as web.HTMLLabelElement;
      expect(label.textContent, 'Fruit');
      expect(label.htmlFor, select().id);
      expect(options(), ['Apples', 'Pears', 'Plums']);
      expect(select().selectedIndex, 1);
    });

    test('with nothing chosen it shows the hint, which cannot be chosen',
        () async {
      await renderer.render(dropdown());

      expect(options().first, 'Pick one');
      expect(select().selectedIndex, 0);
      expect(select().options.item(0)!.hasAttribute('disabled'), isTrue);
    });

    test('with no label, the hint names it', () async {
      await renderer.render(dropdown(label: null));

      expect(select().getAttribute('aria-label'), 'Pick one');
    });

    test('choosing sends the item\'s index, not the option\'s', () async {
      await renderer.render(dropdown());

      // The second option is the first item: the hint is ahead of it.
      select().selectedIndex = 2;
      select().dispatchEvent(web.Event('change'));

      expect(events, ['fruit {index: 1}']);
    });

    test('the choice coming back keeps the select, and its focus', () async {
      await renderer.render(dropdown());
      final before = select()..focus();

      await renderer.render(dropdown(selected: 2));

      expect(select(), same(before));
      expect(web.document.activeElement, same(before));
      expect(options(), ['Apples', 'Pears', 'Plums']);
      expect(select().selectedIndex, 2);

      select().selectedIndex = 0;
      select().dispatchEvent(web.Event('change'));
      expect(events, ['fruit {index: 0}']);
    });

    test('new items replace the options in place', () async {
      await renderer.render(dropdown(selected: 0));
      final before = select();

      await renderer.render(dropdown(selected: 1, items: ['Figs', 'Dates']));

      expect(select(), same(before));
      expect(options(), ['Figs', 'Dates']);
      expect(select().selectedIndex, 1);
    });

    test('an error marks it invalid and says why', () async {
      await renderer.render(dropdown(error: 'Choose a fruit'));

      final error = root.querySelector('.dnn-dropdown__error')!;
      expect(error.textContent, 'Choose a fruit');
      expect(select().getAttribute('aria-invalid'), 'true');
      expect(select().getAttribute('aria-describedby'), error.id);

      await renderer.render(dropdown());
      expect(select().hasAttribute('aria-invalid'), isFalse);
      expect(error.hasAttribute('hidden'), isTrue);
    });

    test('disabled is disabled', () async {
      await renderer.render(dropdown(enabled: false, selected: 0));

      expect(select().disabled, isTrue);
    });
  });

  group('a date picker', () {
    WidgetNode picker({String initial = '2026-03-15', String? title}) =>
        UIBuilder.overlay(
          child: UIBuilder.text('Behind'),
          overlays: [
            node('DatePicker', {
              'initial': initial,
              'first': '2026-01-01',
              'last': '2026-12-31',
              'eventId': 'picked',
              'title': ?title,
              'confirmLabel': 'Choose',
              'dismissEventId': 'dismissed',
              'id': 'when',
            }),
          ],
        );

    web.HTMLInputElement input() =>
        root.querySelector('input[type="date"]')! as web.HTMLInputElement;
    web.HTMLElement part(String name) =>
        root.querySelector('[data-part="$name"]')! as web.HTMLElement;

    test('is a dialog around a date input, opened on the initial date',
        () async {
      await renderer.render(picker(title: 'When?'));

      expect(root.querySelector('[role="dialog"]'), isNotNull);
      expect(root.querySelector('h2')!.textContent, 'When?');
      expect(input().value, '2026-03-15');
      expect(input().min, '2026-01-01');
      expect(input().max, '2026-12-31');
      expect(part('confirm').textContent, 'Choose');
      expect(part('cancel').textContent, 'Cancel');
      // Focus goes into the field, so the next key changes the date.
      expect(web.document.activeElement, same(input()));
    });

    test('confirming sends the date in the field', () async {
      await renderer.render(picker());

      input().value = '2026-07-04';
      part('confirm').click();

      expect(events, ['picked {value: 2026-07-04}']);
    });

    test('a date typed outside the range is brought back inside it', () async {
      await renderer.render(picker());

      input().value = '2031-01-01';
      part('confirm').click();
      input().value = '';
      part('confirm').click();

      expect(events, [
        'picked {value: 2026-12-31}',
        'picked {value: 2026-03-15}',
      ]);
    });

    test('cancel, the scrim and Escape all dismiss, and none of them picks',
        () async {
      await renderer.render(picker());

      part('cancel').click();
      (root.querySelector('.dnn-scrim')! as web.HTMLElement).click();
      input().dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(key: 'Escape', bubbles: true),
        ),
      );

      expect(events, [
        'dismissed {reason: cancel}',
        'dismissed {reason: scrim}',
        'dismissed {reason: escape}',
      ]);
    });

    test('a re-render does not undo what the user has picked so far',
        () async {
      await renderer.render(picker(title: 'When?'));
      final before = input()..value = '2026-09-09';

      await renderer.render(picker(title: 'When exactly?'));

      expect(input(), same(before));
      expect(root.querySelector('h2')!.textContent, 'When exactly?');
      expect(input().value, '2026-09-09');
    });

    test('closing it gives focus back', () async {
      await renderer.render(
        UIBuilder.button(label: 'Open', eventId: 'open', id: 'open'),
      );
      (web.document.getElementById('open')! as web.HTMLElement).focus();
      await renderer.render(
        UIBuilder.overlay(
          child: UIBuilder.button(label: 'Open', eventId: 'open', id: 'open'),
          overlays: [
            node('DatePicker', {
              'initial': '2026-03-15',
              'first': '2026-01-01',
              'last': '2026-12-31',
              'eventId': 'picked',
              'dismissEventId': 'dismissed',
              'id': 'when',
            }),
          ],
        ),
      );
      expect(web.document.activeElement, same(input()));

      await renderer.render(
        UIBuilder.button(label: 'Open', eventId: 'open', id: 'open'),
      );

      expect(web.document.activeElement, web.document.getElementById('open'));
    });
  });

  group('a time picker', () {
    WidgetNode picker({int hour = 9, int minute = 5}) => node('TimePicker', {
      'hour': hour,
      'minute': minute,
      'eventId': 'picked',
      'dismissEventId': 'dismissed',
      'id': 'at',
    });

    web.HTMLInputElement input() =>
        root.querySelector('input[type="time"]')! as web.HTMLInputElement;

    test('opens on the hour and minute it was given', () async {
      await renderer.render(picker());

      expect(input().value, '09:05');
      expect(input().getAttribute('aria-label'), 'Time');
    });

    test('confirming sends hour and minute as numbers', () async {
      await renderer.render(picker());

      input().value = '17:40';
      (root.querySelector('[data-part="confirm"]')! as web.HTMLElement).click();

      expect(events, ['picked {hour: 17, minute: 40}']);
    });

    test('Enter in the field confirms; an emptied field keeps the time',
        () async {
      await renderer.render(picker(hour: 23, minute: 59));

      input().value = '';
      input().dispatchEvent(enterKey());

      expect(events, ['picked {hour: 23, minute: 59}']);
    });

    test('cancel dismisses', () async {
      await renderer.render(picker());

      (root.querySelector('[data-part="cancel"]')! as web.HTMLElement).click();

      expect(events, ['dismissed {reason: cancel}']);
    });
  });
}
