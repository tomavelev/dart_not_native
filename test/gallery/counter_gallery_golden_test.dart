/// Pixel golden of the counter as the **Flutter renderer** paints it.
///
/// This is the Flutter entry in the per-platform gallery: the same `CounterApp`
/// that renders through Android Views, UIKit, and the DOM, here painted by the
/// framework's Flutter renderer. Regenerate with:
///
///   flutter test --update-goldens test/gallery/counter_gallery_golden_test.dart
///
/// What this golden does *not* cover is worth knowing before trusting it: the
/// suite draws with the test font, whose every glyph is the same box, so the
/// picture says where text and icons are and how big they are, and nothing
/// about which ones they are. Swapping `Icons.add` for `Icons.remove` leaves it
/// byte for byte identical. The tree goldens under `test/goldens/trees` are
/// what covers identity.
library;

import 'package:dart_not_native/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/example_apps.dart';
import '../support/tolerant_golden_comparator.dart';

void main() {
  setUpAll(() {
    // A picture is the one thing in this suite that does not survive a change
    // of machine: the engine that rasterised the golden is not the engine
    // reading it back. See [AntiAliasTolerantComparator].
    final strict = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = AntiAliasTolerantComparator(
      strict.basedir.resolve('counter_gallery_golden_test.dart'),
    );
  });

  testWidgets('counter, painted by the Flutter renderer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2250);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NativeUIAppHost(app: exampleApps['counter']!()),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(NativeUIAppHost),
      matchesGoldenFile('images/counter_flutter.png'),
    );
  });
}
