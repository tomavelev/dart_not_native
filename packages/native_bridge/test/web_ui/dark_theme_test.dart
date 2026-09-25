@TestOn('browser')
/// Dark mode on the web target.
///
/// There is no second stylesheet and no `prefers-color-scheme` rule: every
/// colour in `dnn.css` is a `--dnn-*` token, and the renderer writes the whole
/// set from the palette in force. So what has to hold is that the right palette
/// is published - and that `system` asks the browser rather than assuming.
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

  String token(String name) => root.style.getPropertyValue(name);

  test('the default theme publishes the light palette', () {
    WebUIRenderer(root: root, animations: false);

    expect(token('--dnn-surface'), '#ffffff');
    expect(token('--dnn-text'), '#212121');
    expect(token('--dnn-surface-variant'), '#f5f5f5');
    expect(root.style.getPropertyValue('color-scheme'), 'light');
  });

  test('mode dark publishes the dark palette', () {
    WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(mode: AppThemeMode.dark),
    );

    expect(token('--dnn-surface'), '#121212');
    expect(token('--dnn-text'), '#ececec');
    expect(token('--dnn-surface-variant'), '#1e1e1e');
    expect(token('--dnn-primary'), '#90caf9');
    expect(root.style.getPropertyValue('color-scheme'), 'dark');
  });

  test('an app can supply its own dark palette', () {
    WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(
        mode: AppThemeMode.dark,
        dark: AppTheme(surface: '#001018', text: '#c8faff'),
      ),
    );

    expect(token('--dnn-surface'), '#001018');
    expect(token('--dnn-text'), '#c8faff');
  });

  test('the snackbar tokens carry the other appearance', () {
    WebUIRenderer(root: root, animations: false);

    // Light app, so a snackbar is drawn dark - it is a message over the app,
    // not part of the surface it covers.
    expect(token('--dnn-inverse-surface'), '#121212');
    expect(token('--dnn-inverse-text'), '#ececec');
  });

  test('the semantic colours lighten in dark too', () {
    WebUIRenderer(root: root, animations: false);
    expect(token('--dnn-success'), '#388e3c');
    expect(token('--dnn-warning'), '#fbc02d');
    expect(token('--dnn-info'), '#0288d1');
    expect(token('--dnn-error'), '#d32f2f');

    final darkRoot = mountRoot();
    addTearDown(() => darkRoot.remove());
    WebUIRenderer(
      root: darkRoot,
      animations: false,
      theme: const AppTheme(mode: AppThemeMode.dark),
    );

    // A deep green or a mid blue goes muddy on a dark ground, so each has a
    // lightened counterpart rather than being one fixed hue for both.
    expect(darkRoot.style.getPropertyValue('--dnn-success'), '#66bb6a');
    expect(darkRoot.style.getPropertyValue('--dnn-warning'), '#ffca28');
    expect(darkRoot.style.getPropertyValue('--dnn-info'), '#4fc3f7');
    expect(darkRoot.style.getPropertyValue('--dnn-error'), '#ef5350');
  });

  test('mode system follows what the browser reports', () {
    WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(mode: AppThemeMode.system),
    );

    // The test host's own preference decides, so the assertion is the
    // agreement between the two rather than a fixed colour.
    final prefersDark =
        web.window.matchMedia('(prefers-color-scheme: dark)').matches;
    expect(token('--dnn-surface'), prefersDark ? '#121212' : '#ffffff');
    expect(
      root.style.getPropertyValue('color-scheme'),
      prefersDark ? 'dark' : 'light',
    );
  });

  test('the scaffold resolves the dark tokens it is painted with', () async {
    final renderer = WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(mode: AppThemeMode.dark),
    );
    await renderer.render(
      UIBuilder.scaffold(
        appBar: UIBuilder.appBar(title: 'Dark'),
        body: UIBuilder.text('Body'),
      ),
    );

    final scaffold = root.querySelector('.dnn-scaffold')! as web.HTMLElement;
    final resolved = web.window.getComputedStyle(scaffold);
    expect(resolved.getPropertyValue('--dnn-text').trim(), '#ececec');
    expect(resolved.getPropertyValue('--dnn-surface').trim(), '#121212');
  });
}
