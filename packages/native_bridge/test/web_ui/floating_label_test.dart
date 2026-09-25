@TestOn('browser')
/// The hooks the floating label hangs on.
///
/// The label is moved by CSS, not by the renderer, so what a test can reach
/// here is the state the stylesheet selects on: the class on the field, and a
/// placeholder for `:placeholder-shown` to answer about. That the stylesheet
/// carries matching rules is asserted in
/// `test/web_ui/floating_label_css_test.dart`; that the animation looks right
/// is a thing for eyes.
///
/// Run with: flutter test --platform chrome
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

  web.Element field() => root.querySelector('.dnn-textfield')!;
  web.Element input() => root.querySelector('input')!;
  web.Element label() => root.querySelector('label')!;

  test('a labelled field floats its label', () async {
    await renderer.render(
      UIBuilder.textField(hint: '', eventId: 'name', label: 'Full Name'),
    );

    expect(field().classList.contains('dnn-textfield--floating'), isTrue);
    // The label is still the field's name; floating it moves where it is
    // drawn, not what it is.
    expect(label().getAttribute('for'), input().id);
    expect(label().textContent, 'Full Name');
  });

  test('a floating field always has a placeholder to be shown', () async {
    // :placeholder-shown is how the CSS knows the field is empty, and an empty
    // placeholder attribute is never "shown" - so a hintless field gets a
    // space. Without it the label would sit raised over an empty field.
    await renderer.render(
      UIBuilder.textField(hint: '', eventId: 'name', label: 'Full Name'),
    );

    expect(input().getAttribute('placeholder'), ' ');
  });

  test('a hint is the placeholder when there is one', () async {
    await renderer.render(
      UIBuilder.textField(
        hint: 'you@example.com',
        eventId: 'email',
        label: 'Email',
      ),
    );

    expect(input().getAttribute('placeholder'), 'you@example.com');
  });

  test('floatingLabel: false keeps the label above the field', () async {
    await renderer.render(
      UIBuilder.textField(
        hint: 'you@example.com',
        eventId: 'email',
        label: 'Email',
        floatingLabel: false,
      ),
    );

    expect(field().classList.contains('dnn-textfield--floating'), isFalse);
    expect(label().textContent, 'Email');
  });

  test('a field with no label has nothing to float', () async {
    await renderer.render(
      UIBuilder.textField(hint: 'Add a new todo...', eventId: 'new_todo'),
    );

    expect(field().classList.contains('dnn-textfield--floating'), isFalse);
    // And no stand-in placeholder either: the hint is the visible text.
    expect(input().getAttribute('placeholder'), 'Add a new todo...');
  });

  test('the class follows a patch rather than waiting for a rebuild', () async {
    await renderer.render(
      UIBuilder.textField(
        hint: 'you@example.com',
        eventId: 'email',
        label: 'Email',
        floatingLabel: false,
      ),
    );
    final before = input();

    await renderer.render(
      UIBuilder.textField(
        hint: 'you@example.com',
        eventId: 'email',
        label: 'Email',
      ),
    );

    expect(field().classList.contains('dnn-textfield--floating'), isTrue);
    expect(input(), same(before), reason: 'patched in place, so typing is safe');
  });
}
