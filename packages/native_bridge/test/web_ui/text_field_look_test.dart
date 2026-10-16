@TestOn('browser')
/// A text field's look, in the DOM: inline styles on the input, over the
/// kit's stylesheet, and gone again when the field stops stating them.
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

  Future<web.CSSStyleDeclaration> show(Map<String, dynamic> props) async {
    await renderer.render(
      WidgetNode(
        type: 'TextField',
        props: {'eventId': 'e', 'id': 'f', 'hint': 'Hint', ...props},
      ),
    );
    return (root.querySelector('input')! as web.HTMLElement).style;
  }

  test('a field that says nothing has no inline look', () async {
    final style = await show({});

    for (final property in [
      'color',
      'font-size',
      'background-color',
      'border',
      'padding',
    ]) {
      expect(style.getPropertyValue(property), isEmpty, reason: property);
    }
  });

  test('what is typed takes its colour, size and weight', () async {
    final style = await show({
      'textColor': '#2e7d32',
      'fontSize': 20,
      'fontWeight': 600,
    });

    expect(style.getPropertyValue('color'), contains('46'));
    expect(style.getPropertyValue('font-size'), '20px');
    expect(style.getPropertyValue('font-weight'), '600');
  });

  test('a fill', () async {
    final style = await show({'fillColor': '#fff8e1'});

    expect(style.getPropertyValue('background-color'), contains('255'));
  });

  test('no outline', () async {
    final style = await show({'border': 'none'});

    expect(style.getPropertyValue('border-top-style'), 'none');
    expect(style.getPropertyValue('border-bottom-style'), 'none');
  });

  test('an underline is a border on one side', () async {
    final style = await show({'border': 'underline', 'borderColor': '#2e7d32'});

    expect(style.getPropertyValue('border-top-style'), 'none');
    expect(style.getPropertyValue('border-bottom-style'), 'solid');
    expect(style.getPropertyValue('border-bottom-color'), contains('46'));
  });

  test('a box in the colour, width and radius it was given', () async {
    final style = await show({
      'border': 'outline',
      'borderColor': '#2e7d32',
      'borderWidth': 2,
      'borderRadius': 12,
    });

    expect(style.getPropertyValue('border-top-width'), '2px');
    expect(style.getPropertyValue('border-top-color'), contains('46'));
    expect(style.getPropertyValue('border-radius'), '12px');
  });

  test('a box with no colour of its own keeps the kit\'s line', () async {
    final style = await show({'border': 'outline', 'borderRadius': 12});

    expect(style.getPropertyValue('border-top-width'), isEmpty);
    expect(style.getPropertyValue('border-radius'), '12px');
  });

  test('the room inside, as CSS orders its sides', () async {
    final style = await show({
      'contentPadding': [20, 8, 4, 6],
    });

    expect(style.getPropertyValue('padding'), '8px 4px 6px 20px');
  });

  test('a field that stops stating its look goes back to the kit\'s',
      () async {
    await show({'fillColor': '#fff8e1', 'border': 'none', 'fontSize': 20});

    final style = await show({});

    expect(style.getPropertyValue('background-color'), isEmpty);
    expect(style.getPropertyValue('border-top-style'), isEmpty);
    expect(style.getPropertyValue('font-size'), isEmpty);
  });

  test('the outline changes as the field is focused, in error or disabled',
      () async {
    const look = {
      'border': 'outline',
      'borderColor': '#111111',
      'focusedBorderColor': '#2e7d32',
      'focusedBorderWidth': 2,
      'errorBorderColor': '#b00020',
      'disabledBorderColor': '#cccccc',
    };
    var style = await show(look);
    expect(style.getPropertyValue('border'), contains('rgb(17, 17, 17)'));

    final input = root.querySelector('input')! as web.HTMLElement;
    input.focus();
    expect(style.getPropertyValue('border'), contains('2px'));
    expect(style.getPropertyValue('border'), contains('rgb(46, 125, 50)'));
    input.blur();
    expect(style.getPropertyValue('border'), contains('rgb(17, 17, 17)'));

    style = await show({...look, 'error': 'Required'});
    expect(style.getPropertyValue('border'), contains('rgb(176, 0, 32)'));

    style = await show({...look, 'enabled': false});
    expect(style.getPropertyValue('border'), contains('rgb(204, 204, 204)'));
  });

  test('the hint, label and helper take their styles', () async {
    final style = await show({
      'label': 'Name',
      'floatingLabel': false,
      'helper': 'Help',
      'hintStyle': {'color': '#2e7d32', 'fontSize': 12},
      'labelStyle': {'color': '#b00020'},
      'helperStyle': {'fontWeight': 700},
    });
    expect(style.getPropertyValue('--dnn-hint-color'), '#2e7d32');
    expect(style.getPropertyValue('--dnn-hint-size'), '12px');
    final input = root.querySelector('input')!;
    expect(input.classList.contains('dnn-hint-color'), isTrue);
    expect(input.classList.contains('dnn-hint-weight'), isFalse);
    final label = root.querySelector('[data-part="label"]')! as web.HTMLElement;
    expect(label.style.color, 'rgb(176, 0, 32)');
    final helper =
        root.querySelector('[data-part="helper"]')! as web.HTMLElement;
    expect(helper.style.fontWeight, '700');
  });
}
