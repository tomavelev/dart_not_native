@TestOn('browser')
/// Where focus goes when a dialog opens, and where it comes back to.
///
/// A keyboard user who opens a dialog from a button should land back on that
/// button when it closes. Landing at the top of the document instead is the
/// kind of thing that only shows up when you try to use the app without a
/// mouse.
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

  /// A screen with a button, optionally under [overlays].
  WidgetNode screen({List<WidgetNode> overlays = const []}) {
    final content = UIBuilder.column(
      // The id is what survives the rebuild that opening a dialog causes -
      // see the renderer's note on _focusBeforeModalId.
      children: [
        UIBuilder.button(label: 'Open', eventId: 'open', id: 'open_button'),
      ],
    );
    if (overlays.isEmpty) return content;
    return UIBuilder.overlay(child: content, overlays: overlays);
  }

  WidgetNode dialog() => UIBuilder.dialog(
        title: 'Confirm',
        content: [UIBuilder.text('Really?')],
        dismissEventId: 'dismiss',
      );

  web.HTMLElement button() =>
      root.querySelector('button')! as web.HTMLElement;

  test('opening a dialog moves focus into it', () async {
    await renderer.render(screen());
    button().focus();

    await renderer.render(screen(overlays: [dialog()]));

    expect(
      (web.document.activeElement as web.Element?)?.getAttribute('role'),
      'dialog',
    );
  });

  test('closing it puts focus back where it was', () async {
    await renderer.render(screen());
    button().focus();
    await renderer.render(screen(overlays: [dialog()]));

    await renderer.render(screen());

    expect(web.document.activeElement, button());
  });

  test('a stack returns to before the first, not to the sheet', () async {
    await renderer.render(screen());
    button().focus();
    await renderer.render(screen(overlays: [
      UIBuilder.bottomSheet(content: [UIBuilder.text('Sheet')]),
    ]));
    await renderer.render(screen(overlays: [
      UIBuilder.bottomSheet(content: [UIBuilder.text('Sheet')]),
      dialog(),
    ]));

    // Closing only the dialog leaves the sheet open, so focus stays put.
    await renderer.render(screen(overlays: [
      UIBuilder.bottomSheet(content: [UIBuilder.text('Sheet')]),
    ]));
    expect(web.document.activeElement, isNot(button()));

    await renderer.render(screen());

    expect(web.document.activeElement, button());
  });

  test('a control with no id cannot be returned to', () async {
    await renderer.render(
      UIBuilder.column(
        children: [UIBuilder.button(label: 'Open', eventId: 'open')],
      ),
    );
    (root.querySelector('button')! as web.HTMLElement).focus();

    await renderer.render(
      UIBuilder.overlay(
        child: UIBuilder.column(
          children: [UIBuilder.button(label: 'Open', eventId: 'open')],
        ),
        overlays: [dialog()],
      ),
    );
    await renderer.render(
      UIBuilder.column(
        children: [UIBuilder.button(label: 'Open', eventId: 'open')],
      ),
    );

    // Nothing to aim at, so focus is left where the browser put it rather
    // than moved somewhere arbitrary. Documented, not silently broken.
    expect(web.document.activeElement, isNot(root.querySelector('button')));
  });

  test('a retitled dialog keeps the caret in the field being typed in', () async {
    WidgetNode withTitle(String title) => UIBuilder.overlay(
          child: UIBuilder.column(children: [UIBuilder.text('Behind')]),
          overlays: [
            UIBuilder.dialog(
              title: title,
              content: [UIBuilder.textField(hint: 'Name', eventId: 'name')],
              dismissEventId: 'dismiss',
            ),
          ],
        );

    await renderer.render(withTitle('Rename'));
    final field = root.querySelector('input')! as web.HTMLInputElement;
    field.focus();
    field.value = 'Ada';
    field.setSelectionRange(2, 2);

    // A title that counts, or names what is being confirmed, changes while the
    // dialog is open. Rebuilding for it used to cost the user their place.
    await renderer.render(withTitle('Rename (1 selected)'));

    expect(root.querySelector('h2')!.textContent, 'Rename (1 selected)');
    expect(
      web.document.activeElement,
      same(field),
      reason: 'the same element, not a replacement',
    );
    expect(field.selectionStart, 2, reason: 'and the caret where it was');
  });

  test('a dialog that becomes undismissable is rebuilt, not half-patched',
      () async {
    WidgetNode dialogWith({required bool dismissible}) => UIBuilder.overlay(
          child: UIBuilder.column(children: [UIBuilder.text('Behind')]),
          overlays: [
            UIBuilder.dialog(
              title: 'Working',
              content: [UIBuilder.text('Please wait')],
              dismissEventId: 'dismiss',
              dismissible: dismissible,
            ),
          ],
        );

    await renderer.render(dialogWith(dismissible: true));
    final before = root.querySelector('.dnn-dialog');

    await renderer.render(dialogWith(dismissible: false));

    // The listeners close over what they were built with, so this one has to
    // be built again rather than patched.
    expect(root.querySelector('.dnn-dialog'), isNot(same(before)));
  });

  test('a button that left with the render is not chased', () async {
    await renderer.render(screen());
    button().focus();
    await renderer.render(screen(overlays: [dialog()]));

    // The screen behind changed while the dialog was open, so the button the
    // user came from is gone. Focusing a detached node would move the caret to
    // the body; leaving it alone is better.
    await renderer.render(
      UIBuilder.column(children: [UIBuilder.text('Something else')]),
    );

    expect(web.document.body!.contains(web.document.activeElement), isTrue);
  });
}
