@TestOn('browser')
/// The WebView node on the web target: an iframe, and the JavaScript switch.
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

  web.Element frame() => root.querySelector('iframe')!;

  test('a web view is an iframe at the height it was given', () async {
    await renderer.render(
      UIBuilder.webView(url: 'https://example.com/', height: 240),
    );

    expect(frame().getAttribute('src'), 'https://example.com/');
    expect((frame() as web.HTMLElement).style.height, '240px');
    // Named, so a screen reader announces it as something rather than nothing.
    expect(frame().getAttribute('title'), isNotEmpty);
  });

  test('JavaScript is off unless asked for', () async {
    await renderer.render(UIBuilder.webView(url: 'https://example.com/'));

    // A sandbox without allow-scripts is how an iframe says "show, do not run".
    final sandbox = frame().getAttribute('sandbox')!;
    expect(sandbox, isNot(contains('allow-scripts')));
  });

  test('asking for JavaScript lifts the sandbox', () async {
    await renderer.render(
      UIBuilder.webView(url: 'https://example.com/', javaScriptEnabled: true),
    );

    expect(frame().hasAttribute('sandbox'), isFalse);
  });

  test('it is a known node type, not an unknown-widget placeholder', () async {
    final error = await renderer.render(
      UIBuilder.webView(url: 'https://example.com/'),
    );

    expect(error, isNull);
    expect(root.querySelector('.dnn-unknown'), isNull);
  });
}
