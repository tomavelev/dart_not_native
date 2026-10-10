@TestOn('browser')
/// The colours an app gives one control, in the DOM: custom properties on
/// the control, which the kit's stylesheet reads in place of the brand's.
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
    renderer.onEvent('e', (_) {});
  });
  tearDown(() => root.remove());

  WidgetNode node(String type, Map<String, dynamic> props) =>
      WidgetNode(type: type, props: {'eventId': 'e', ...props});

  web.HTMLElement control(String type) =>
      root.querySelector('[data-type="$type"]')! as web.HTMLElement;

  String property(web.HTMLElement element, String part) =>
      element.style.getPropertyValue('--dnn-control-$part');

  test('a checkbox carries its fill and its tick', () async {
    await renderer.render(
      node('Checkbox', {
        'checked': true,
        'activeColor': '#2e7d32',
        'checkColor': '#e91e63',
      }),
    );

    expect(property(control('Checkbox'), 'active'), isNotEmpty);
    expect(property(control('Checkbox'), 'check'), isNotEmpty);
    expect(
      control('Checkbox').classList.contains('dnn-control--active'),
      isTrue,
    );
  });

  test('a radio carries its colour', () async {
    await renderer.render(
      node('Radio', {
        'value': 'a',
        'selected': true,
        'activeColor': '#2e7d32',
      }),
    );

    expect(property(control('Radio'), 'active'), isNotEmpty);
  });

  test('a switch is its colour when on, under a white thumb', () async {
    await renderer.render(
      node('Toggle', {'enabled': true, 'activeColor': '#2e7d32'}),
    );

    final toggle = control('Toggle');
    expect(property(toggle, 'active'), isNotEmpty);
    expect(property(toggle, 'thumb'), '#ffffff');
  });

  test('a switch carries the thumb and the off colours it is given',
      () async {
    await renderer.render(
      node('Toggle', {
        'enabled': false,
        'thumbColor': '#e91e63',
        'inactiveTrackColor': '#9e9e9e',
        'inactiveThumbColor': '#2e7d32',
      }),
    );

    final toggle = control('Toggle');
    expect(property(toggle, 'thumb'), isNotEmpty);
    expect(property(toggle, 'inactive-track'), isNotEmpty);
    expect(property(toggle, 'inactive-thumb'), isNotEmpty);
    expect(toggle.classList.contains('dnn-control--active'), isFalse);
  });

  test('a slider carries the one colour a range input has', () async {
    await renderer.render(
      node('Slider', {'value': 0.5, 'activeColor': '#2e7d32'}),
    );

    expect(property(control('Slider'), 'active'), isNotEmpty);
  });

  test('a control given none carries none', () async {
    await renderer.render(node('Checkbox', {'checked': true}));

    expect(property(control('Checkbox'), 'active'), isEmpty);
    expect(
      control('Checkbox').classList.contains('dnn-control--active'),
      isFalse,
    );
  });

  test('a control that stops being coloured goes back to the brand\'s',
      () async {
    await renderer.render(
      node('Toggle', {'id': 't', 'enabled': true, 'activeColor': '#2e7d32'}),
    );
    final before = control('Toggle');
    expect(property(before, 'active'), isNotEmpty);

    await renderer.render(node('Toggle', {'id': 't', 'enabled': true}));

    final after = control('Toggle');
    expect(property(after, 'active'), isEmpty);
    expect(property(after, 'thumb'), isEmpty);
    expect(after.classList.contains('dnn-control--active'), isFalse);
  });

  test('a floating button is the colour it was given', () async {
    await renderer.render(
      UIBuilder.scaffold(
        body: UIBuilder.text('x'),
        floatingActionButton: node('FloatingActionButton', {
          'tooltip': 'Add',
          'icon': 'add',
          'backgroundColor': '#2e7d32',
          'foregroundColor': '#e91e63',
        }),
      ),
    );

    final fab = root.querySelector('.dnn-fab')! as web.HTMLElement;
    expect(fab.style.getPropertyValue('background-color'), contains('46'));
    expect(fab.style.getPropertyValue('color'), contains('233'));
    // Over a kit that colours its button with a rule that says important.
    expect(fab.style.getPropertyPriority('background-color'), 'important');
  });
}
