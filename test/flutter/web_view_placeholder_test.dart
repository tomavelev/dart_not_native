/// What the Flutter-hosted target shows where a web page would be.
///
/// The other three renderers draw the platform's own browser view. Flutter's
/// would need `webview_flutter`, which the framework does not depend on, so
/// this target says what is missing rather than drawing an empty box - and
/// this pins that it says it, since a silently blank area is exactly the
/// failure the placeholder exists to prevent.
library;

import 'package:dart_not_native/material.dart' show NativeUIAppHost;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: const [
        Text('Above'),
        WebView(url: 'https://example.com/', height: 200),
      ],
    ),
  );
}

void main() {
  testWidgets('it says what is missing, and where', (tester) async {
    await tester.pumpWidget(
      flutter.MaterialApp(home: NativeUIAppHost(app: hostApp(const _Screen()))),
    );
    await tester.pump();

    expect(find.textContaining('webview_flutter'), findsOneWidget);
    expect(find.textContaining('https://example.com/'), findsOneWidget);
    // Not the generic unknown-widget placeholder: the type is known, it is
    // this target that cannot draw it.
    expect(find.textContaining('Unknown widget'), findsNothing);
  });

  testWidgets('it takes the height the app asked for', (tester) async {
    await tester.pumpWidget(
      flutter.MaterialApp(home: NativeUIAppHost(app: hostApp(const _Screen()))),
    );
    await tester.pump();

    final box = tester.getSize(
      find.ancestor(
        of: find.textContaining('webview_flutter'),
        matching: find.byType(flutter.Container),
      ).first,
    );
    expect(box.height, 200);
  });
}
