@TestOn('browser')
/// Browser test for a scroll travelled over the time the app said
/// (`scrollMs`, `scrollCurve`).
///
/// Run with: flutter test --platform chrome test/web_ui/scroll_travel_test.dart
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  setUp(() => root = mountRoot());
  tearDown(() => root.remove());

  WidgetNode list(double offset, int version, {int? ms}) => WidgetNode(
    type: 'Scroll',
    props: {
      'axis': 'vertical',
      'height': 200,
      'scrollOffset': offset,
      'scrollVersion': version,
      if (ms != null) 'scrollAnimated': true,
      'scrollMs': ?ms,
      if (ms != null) 'scrollCurve': 'linear',
      'id': 'list',
    },
    children: [
      for (var i = 0; i < 40; i++) UIBuilder.box(height: 50, width: 100),
    ],
  );

  test('it takes the time asked, not the browser\'s own', () async {
    // The stylesheet's rule, which a test page does not load.
    final sheet = web.document.createElement('style')
      ..textContent = '.dnn-scroll { height: 200px; overflow: auto; }';
    web.document.head!.appendChild(sheet);
    addTearDown(() => sheet.remove());
    final renderer = WebUIRenderer(root: root);
    await renderer.render(list(0, 0));
    await renderer.render(list(800, 1, ms: 600));
    final viewport = root.querySelector('.dnn-scroll')!;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final halfway = viewport.scrollTop;
    expect(halfway, greaterThan(150));
    expect(halfway, lessThan(650));

    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(viewport.scrollTop, closeTo(800, 1));
  });
}
