@TestOn('browser')
/// What a screen reader would find.
///
/// These assert the attributes assistive technology actually reads, which is
/// the only part of accessibility a test can reach - whether it then *sounds*
/// right still needs a person and a screen reader.
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

  web.Element input() => root.querySelector('input')!;
  web.Element label() => root.querySelector('label')!;

  group('a text field', () {
    test('its visible label names it', () async {
      await renderer.render(
        UIBuilder.textField(hint: 'you@example.com', eventId: 'email',
            label: 'Email address'),
      );

      // for/id, so the label is the field's name rather than nearby text.
      expect(label().getAttribute('for'), isNotEmpty);
      expect(label().getAttribute('for'), input().id);
      expect(label().textContent, 'Email address');
    });

    test('with no label, the placeholder names it', () async {
      await renderer.render(
        UIBuilder.textField(hint: 'Search', eventId: 'q'),
      );

      // Otherwise the field is announced as "edit text" and nothing else.
      expect(input().getAttribute('aria-label'), 'Search');
    });

    test('a label takes over from the placeholder', () async {
      await renderer.render(
        UIBuilder.textField(hint: 'Search', eventId: 'q', label: 'Query'),
      );

      expect(input().hasAttribute('aria-label'), isFalse,
          reason: 'the label element already names it; two names is worse');
    });

    test('an error marks it invalid and says why', () async {
      await renderer.render(
        UIBuilder.textField(
          hint: 'you@example.com',
          eventId: 'email',
          label: 'Email address',
          error: 'That is not an email',
        ),
      );

      expect(input().getAttribute('aria-invalid'), 'true');
      final describedBy = input().getAttribute('aria-describedby')!;
      expect(
        root.querySelector('[id="$describedBy"]')!.textContent,
        'That is not an email',
      );
    });

    test('and the marks come off when it is valid again', () async {
      const invalid = 'email';
      await renderer.render(
        UIBuilder.textField(
          hint: 'you@example.com',
          eventId: invalid,
          label: 'Email address',
          error: 'That is not an email',
        ),
      );
      await renderer.render(
        UIBuilder.textField(
          hint: 'you@example.com',
          eventId: invalid,
          label: 'Email address',
        ),
      );

      expect(input().hasAttribute('aria-invalid'), isFalse);
      expect(input().hasAttribute('aria-describedby'), isFalse);
    });
  });

  group('what was already there stays', () {
    test('a dialog is a modal dialog, named by its title', () async {
      await renderer.render(
        UIBuilder.overlay(
          child: UIBuilder.text('Behind'),
          overlays: [
            UIBuilder.dialog(title: 'Delete?', content: [UIBuilder.text('Sure?')]),
          ],
        ),
      );

      final surface = root.querySelector('[role="dialog"]')!;
      expect(surface.getAttribute('aria-modal'), 'true');
      final labelledBy = surface.getAttribute('aria-labelledby')!;
      expect(root.querySelector('[id="$labelledBy"]')!.textContent, 'Delete?');
    });

    test('a snackbar announces itself without stealing focus', () async {
      await renderer.render(
        UIBuilder.overlay(
          child: UIBuilder.text('Behind'),
          overlays: [UIBuilder.snackbar(message: 'Deleted')],
        ),
      );

      expect(root.querySelector('[aria-live]'), isNotNull);
      expect(web.document.activeElement, isNot(root.querySelector('[aria-live]')));
    });

    test('an image carries its alt text', () async {
      await renderer.render(
        UIBuilder.image(src: 'cat.png', alt: 'A sleeping cat'),
      );

      expect(root.querySelector('img')!.getAttribute('alt'), 'A sleeping cat');
    });
  });
}
