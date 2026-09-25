@TestOn('browser')
/// Asking for the keyboard from the app's side.
///
/// The tree carries states, so "focus this field" cannot be a state - a field
/// that is simply "focused" would take the caret back every time the app
/// re-rendered for an unrelated reason. It travels as a version instead: a
/// number that changed since the last render is one ask, acted on once.
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

  WidgetNode screen({
    bool autofocus = false,
    int? focusVersion,
    bool focusRequested = true,
    String hint = 'Search',
  }) => UIBuilder.column(
    children: [
      UIBuilder.textField(
        hint: hint,
        eventId: 'search',
        autofocus: autofocus,
        focusVersion: focusVersion,
        focusRequested: focusRequested,
      ),
      UIBuilder.textField(hint: 'Other', eventId: 'other'),
    ],
  );

  web.Element field(int index) =>
      root.querySelectorAll('input').item(index)! as web.Element;

  test('a field says nothing about focus, so nothing takes it', () async {
    await renderer.render(screen());

    expect(web.document.activeElement, isNot(field(0)));
  });

  test('autofocus takes the keyboard when the field is first drawn', () async {
    await renderer.render(screen(autofocus: true));

    expect(web.document.activeElement, field(0));
  });

  test('autofocus does not take it back on a later render', () async {
    await renderer.render(screen(autofocus: true));
    (field(1) as web.HTMLElement).focus();

    await renderer.render(screen(autofocus: true, hint: 'Search again'));

    expect(web.document.activeElement, field(1));
  });

  test('a new version is an ask, and moves the caret', () async {
    await renderer.render(screen(focusVersion: 1));
    (field(1) as web.HTMLElement).focus();

    await renderer.render(screen(focusVersion: 2));

    expect(web.document.activeElement, field(0));
  });

  test('the same version again is the same ask, already answered', () async {
    await renderer.render(screen(focusVersion: 1));
    (field(1) as web.HTMLElement).focus();

    await renderer.render(screen(focusVersion: 1, hint: 'Search again'));

    expect(web.document.activeElement, field(1));
  });

  test('asking to give it up blurs the field', () async {
    await renderer.render(screen(focusVersion: 1));
    expect(web.document.activeElement, field(0));

    await renderer.render(screen(focusVersion: 2, focusRequested: false));

    expect(web.document.activeElement, isNot(field(0)));
  });
}
