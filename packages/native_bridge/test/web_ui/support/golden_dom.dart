/// Support for the DOM golden tests.
///
/// Browser tests have no file system, so goldens live in `goldens/dom.dart`
/// as string constants. `flutter test --platform chrome` prints the fresh
/// markup of any scene that drifted, which is what you paste back into the
/// golden file after reviewing the change.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/style_kit.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dom.dart';

/// Renders [tree] with [kit] and returns its markup, normalised so the
/// golden captures structure and classes rather than noise.
Future<String> renderToHtml(WidgetNode tree, {required WebStyleKit kit}) async {
  final root = mountRoot();
  await WebUIRenderer(root: root, kit: kit, animations: false).render(tree);
  final html = root.innerHTML.toString();
  root.remove();
  return prettyHtml(normalizeHtml(html));
}

/// Drops the renderer's internal props fingerprint and collapses whitespace.
String normalizeHtml(String html) => html
    .replaceAll(RegExp(r'\sdata-sig="[^"]*"'), '')
    .replaceAll(RegExp(r'>\s+<'), '><')
    .trim();

/// One tag per line, indented, so a golden diff points at the element that
/// changed instead of at one very long line.
String prettyHtml(String html) {
  final buffer = StringBuffer();
  var depth = 0;
  for (final token in html.split(RegExp(r'(?=<)|(?<=>)'))) {
    final part = token.trim();
    if (part.isEmpty) continue;
    final isClose = part.startsWith('</');
    final isSelfContained =
        part.startsWith('<') &&
        (part.endsWith('/>') || _voidTags.any((t) => part.startsWith('<$t')));
    if (isClose) depth--;
    buffer.writeln('${'  ' * (depth < 0 ? 0 : depth)}$part');
    if (part.startsWith('<') && !isClose && !isSelfContained) depth++;
  }
  return buffer.toString().trimRight();
}

const _voidTags = ['input', 'br', 'hr', 'img', 'link', 'meta'];

/// Compares [actual] against [expected], printing the fresh markup on drift.
void expectGolden(String actual, String expected, {required String name}) {
  if (actual.trim() == expected.trim()) return;
  // ignore: avoid_print
  print('=== golden "$name" changed; reviewed replacement:\n$actual\n=== end');
  fail(
    'DOM golden "$name" changed. The new markup was printed above: review '
    'it, and if the change is intended paste it into '
    'test/web_ui/goldens/dom.dart.',
  );
}
