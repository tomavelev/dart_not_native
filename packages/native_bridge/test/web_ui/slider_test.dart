@TestOn('browser')
/// The slider in a real browser: a range input, its steps, and what it sends.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<double> changes;
  late List<double> ends;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    changes = [];
    ends = [];
    renderer
      ..onEvent('vol_change', (data) => changes.add(data['value'] as double))
      ..onEvent('vol_end', (data) => ends.add(data['value'] as double));
  });
  tearDown(() => root.remove());

  web.HTMLInputElement input() =>
      root.querySelector('input[type="range"]') as web.HTMLInputElement;

  Future<void> show({
    double value = 0.5,
    int? divisions,
    bool disabled = false,
  }) =>
      renderer.render(UIBuilder.slider(
        eventId: 'vol',
        value: value,
        divisions: divisions,
        disabled: disabled,
      ));

  test('is the browser\'s own range input, with the range it was given', () async {
    await renderer.render(
      UIBuilder.slider(eventId: 'vol', value: 5, min: 0, max: 10),
    );

    // The browser normalises what it is handed, so '0.0' reads back as '0'.
    expect(double.parse(input().min), 0);
    expect(double.parse(input().max), 10);
    expect(double.parse(input().value), 5);
  });

  test('divisions become a step, and no divisions means continuous', () async {
    await show(divisions: 4);
    expect(double.parse(input().step), 0.25);

    await show();
    // 'any' rather than the browser's default of 1, which would snap a 0..1
    // slider to its two ends.
    expect(input().step, 'any');
  });

  test('a drag reports each step, and the release reports once', () async {
    await show();

    input().value = '0.7';
    input().dispatchEvent(web.Event('input'));
    input().dispatchEvent(web.Event('change'));

    expect(changes, [0.7]);
    expect(ends, [0.7]);
  });

  test('a re-render keeps the element, so a drag is not interrupted', () async {
    await show();
    final before = input();

    await show(value: 0.9);

    expect(input(), same(before));
    expect(double.parse(input().value), 0.9);
  });

  test('a disabled slider says so', () async {
    await show(disabled: true);

    expect(input().disabled, isTrue);
  });
}
