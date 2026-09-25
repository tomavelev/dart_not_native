@TestOn('browser')
/// The keyboard's return key advancing to the next field.
///
/// A form whose return key dismissed the keyboard made the user reach for the
/// next field by hand, every field, every time. `textInputAction: 'next'` says
/// the return key should advance instead; what "next" means is the reading
/// order of the tree, so the app never has to name the field.
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

  /// Presses Enter in [input], the way a return key does.
  void pressEnter(web.Element input) {
    input.dispatchEvent(
      web.KeyboardEvent('keydown', web.KeyboardEventInit(key: 'Enter')),
    );
  }

  List<web.Element> inputs() {
    final found = root.querySelectorAll('input, textarea');
    return [
      for (var i = 0; i < found.length; i++) found.item(i)! as web.Element,
    ];
  }

  test('Enter moves to the next field', () async {
    await renderer.render(
      UIBuilder.column(
        children: [
          UIBuilder.textField(
            hint: 'First',
            eventId: 'first',
            textInputAction: 'next',
          ),
          UIBuilder.textField(hint: 'Second', eventId: 'second'),
        ],
      ),
    );

    final fields = inputs();
    (fields.first as web.HTMLElement).focus();
    pressEnter(fields.first);

    expect(web.document.activeElement, fields[1]);
  });

  test('a field that asks for done leaves focus alone', () async {
    await renderer.render(
      UIBuilder.column(
        children: [
          UIBuilder.textField(hint: 'First', eventId: 'first'),
          UIBuilder.textField(hint: 'Second', eventId: 'second'),
        ],
      ),
    );

    final fields = inputs();
    (fields.first as web.HTMLElement).focus();
    pressEnter(fields.first);

    expect(web.document.activeElement, fields.first);
  });

  test('the last field has nowhere to go and stays put', () async {
    await renderer.render(
      UIBuilder.column(
        children: [
          UIBuilder.textField(hint: 'Only', eventId: 'only', textInputAction: 'next'),
        ],
      ),
    );

    final fields = inputs();
    (fields.first as web.HTMLElement).focus();
    pressEnter(fields.first);

    expect(web.document.activeElement, fields.first);
  });

  test('a disabled field is stepped over', () async {
    await renderer.render(
      UIBuilder.column(
        children: [
          UIBuilder.textField(
            hint: 'First',
            eventId: 'first',
            textInputAction: 'next',
          ),
          UIBuilder.textField(
            hint: 'Skipped',
            eventId: 'skipped',
            enabled: false,
          ),
          UIBuilder.textField(hint: 'Third', eventId: 'third'),
        ],
      ),
    );

    final fields = inputs();
    (fields.first as web.HTMLElement).focus();
    pressEnter(fields.first);

    expect(web.document.activeElement, fields[2]);
  });

  test('the submit event still fires, so an app hears it either way', () async {
    final submitted = <String>[];
    renderer.onEvent('first_submit', (data) => submitted.add('${data['value']}'));
    await renderer.render(
      UIBuilder.column(
        children: [
          UIBuilder.textField(
            hint: 'First',
            eventId: 'first',
            textInputAction: 'next',
          ),
          UIBuilder.textField(hint: 'Second', eventId: 'second'),
        ],
      ),
    );

    pressEnter(inputs().first);

    expect(submitted, hasLength(1));
  });
}
