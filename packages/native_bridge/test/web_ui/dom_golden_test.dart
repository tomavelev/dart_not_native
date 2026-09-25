@TestOn('browser')
/// Golden tests for the web target.
///
/// This framework renders native UI, not a canvas, so the meaningful golden
/// is the markup a style kit produces - which elements, which CSS classes,
/// which attributes - rather than a screenshot. Pixel-level appearance is
/// covered by the Maestro screenshot flows in `maestro/web`.
///
/// Run with: flutter test --platform chrome
///
/// When a golden drifts the test prints the fresh markup; review it and, if
/// the change is intended, paste it into `goldens/dom.dart`.
library;

import 'package:dart_not_native/web_ui/kits/materialize_kit.dart';
import 'package:dart_not_native/web_ui/kits/mdl_kit.dart';
import 'package:dart_not_native/web_ui/style_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'goldens/dom.dart';
import 'scenes.dart';
import 'support/golden_dom.dart';

const _kits = <WebStyleKit>[MdlKit(), MaterializeKit(), PlainKit()];

void main() {
  for (final scene in goldenScenes.entries) {
    group(scene.key, () {
      for (final kit in _kits) {
        final name = '${scene.key}__${kit.name}';

        test('renders as expected with the ${kit.name} kit', () async {
          final actual = await renderToHtml(scene.value, kit: kit);

          expectGolden(actual, domGoldens[name]!, name: name);
        });
      }
    });
  }

  test('every golden has a scene and every scene a golden', () {
    final expected = {
      for (final scene in goldenScenes.keys)
        for (final kit in _kits) '${scene}__${kit.name}',
    };

    expect(domGoldens.keys.toSet(), expected);
  });
}
