@TestOn('browser')
/// Keyboard avoidance on the web target.
///
/// A soft keyboard does not shrink `100vh`, so a screen sized by it keeps its
/// bottom - and any field near it - underneath the keyboard. The renderer
/// publishes the visual viewport's height as `--dnn-viewport-height` instead,
/// and `dnn.css` sizes the scaffold by that, falling back to `100vh` where the
/// API is missing.
///
/// A test cannot open a keyboard, so what is pinned here is the wiring: the
/// property is published on start-up and republished whenever the visual
/// viewport reports a resize, which is the event a keyboard causes.
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

  test('the visual viewport height is published on start-up', () {
    WebUIRenderer(root: root, animations: false);

    final published = root.style.getPropertyValue('--dnn-viewport-height');
    expect(published, isNotEmpty, reason: 'the property should be set at once');
    expect(published, endsWith('px'));
    expect(
      double.parse(published.replaceAll('px', '')),
      closeTo(web.window.visualViewport!.height.toDouble(), 1),
    );
  });

  test('a viewport resize republishes the height', () {
    WebUIRenderer(root: root, animations: false);
    root.style.setProperty('--dnn-viewport-height', '1px');

    // What an opening keyboard fires.
    web.window.visualViewport!.dispatchEvent(web.Event('resize'));

    expect(
      double.parse(
        root.style.getPropertyValue('--dnn-viewport-height').replaceAll('px', ''),
      ),
      closeTo(web.window.visualViewport!.height.toDouble(), 1),
    );
  });

  test('the scaffold is sized by the property, not by 100vh', () async {
    final renderer = WebUIRenderer(root: root, animations: false);
    await renderer.render(
      UIBuilder.scaffold(
        appBar: UIBuilder.appBar(title: 'Form'),
        body: UIBuilder.textField(eventId: 'name', hint: 'Name'),
      ),
    );

    final scaffold = root.querySelector('.dnn-scaffold')! as web.HTMLElement;
    // The stylesheet is not loaded in the test host, so assert the input the
    // rule reads rather than the computed height: the property resolves on the
    // scaffold, which is what `min-height: var(--dnn-viewport-height, 100vh)`
    // needs.
    final resolved = web.window
        .getComputedStyle(scaffold)
        .getPropertyValue('--dnn-viewport-height')
        .trim();
    expect(resolved, isNotEmpty);
    expect(resolved, root.style.getPropertyValue('--dnn-viewport-height'));
  });
}
