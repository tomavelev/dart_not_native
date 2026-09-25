@TestOn('browser')
/// The app theme reaches the DOM: its primary drives the `--dnn-primary`
/// custom property the style kits read for the app bar, primary button and FAB.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  test('the palette drives the --dnn-* custom properties', () async {
    final root = mountRoot();
    WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(
        primary: '#e91e63',
        onPrimary: '#000000',
        secondary: '#00bcd4',
        surface: '#fafafa',
        error: '#b00020',
      ),
    );

    expect(root.style.getPropertyValue('--dnn-primary'), '#e91e63');
    expect(root.style.getPropertyValue('--dnn-on-primary'), '#000000');
    expect(root.style.getPropertyValue('--dnn-secondary'), '#00bcd4');
    expect(root.style.getPropertyValue('--dnn-surface'), '#fafafa');
    expect(root.style.getPropertyValue('--dnn-error'), '#b00020');
    root.remove();
  });

  test('no theme leaves the Material-blue default', () async {
    final root = mountRoot();
    WebUIRenderer(root: root, animations: false);
    expect(root.style.getPropertyValue('--dnn-primary'), '#1976d2');
    (root as web.Element).remove();
  });

  test('a badge with no colour renders in the theme primary', () async {
    final root = mountRoot();
    final renderer = WebUIRenderer(
      root: root,
      animations: false,
      theme: const AppTheme(primary: '#e91e63'),
    );
    await renderer.render(DSBadge.solid(label: 'New'));

    // The badge's own markup carries the resolved colour (as rgb), not just the
    // CSS var — #e91e63 == rgb(233, 30, 99).
    expect(root.innerHTML.toString(), contains('rgb(233, 30, 99)'));
    root.remove();
  });
}
