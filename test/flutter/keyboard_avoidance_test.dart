/// Keyboard avoidance on the Flutter-hosted target.
///
/// The other three renderers each had to be taught this: UIKit moves nothing
/// out from under the keyboard, Android only does when the window is allowed to
/// resize, and `100vh` on web does not shrink. Flutter gets it from `Scaffold`,
/// whose `resizeToAvoidBottomInset` defaults to true, plus the
/// `SingleChildScrollView` the renderer wraps a body in - which is exactly why
/// it is worth a test: both are defaults a later change could quietly drop, and
/// nothing else here would notice.
library;

import 'package:dart_not_native/material.dart' show NativeUIAppHost;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';

/// A screen whose field sits below the fold, so only avoidance can show it.
class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppBar(title: Text('Profile')),
    body: Column(
      children: [
        for (var i = 0; i < 12; i++) Text('Filler $i'),
        const TextField(decoration: InputDecoration(hintText: 'Bio')),
      ],
    ),
  );
}

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      flutter.MaterialApp(
        home: NativeUIAppHost(app: hostApp(const _ProfileScreen())),
      ),
    );
    await tester.pump();
  }

  testWidgets('the body scrolls, so a field below the fold is reachable', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.byType(flutter.SingleChildScrollView), findsOneWidget);
  });

  testWidgets('the scaffold resizes for the keyboard', (tester) async {
    await pumpScreen(tester);

    final scaffold = tester.widget<flutter.Scaffold>(
      find.byType(flutter.Scaffold),
    );
    // Null means the default, which is true; false would leave the keyboard
    // covering the bottom of the screen.
    expect(scaffold.resizeToAvoidBottomInset ?? true, isTrue);
  });

  testWidgets(
    'the body shrinks by the keyboard inset rather than hiding under it',
    (tester) async {
      await pumpScreen(tester);
      final before = tester.getSize(find.byType(flutter.SingleChildScrollView));

      // What the platform reports while a keyboard is open.
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();

      final after = tester.getSize(find.byType(flutter.SingleChildScrollView));
      expect(
        after.height,
        lessThan(before.height),
        reason: 'the viewport should give the keyboard its space back',
      );
    },
  );
}
