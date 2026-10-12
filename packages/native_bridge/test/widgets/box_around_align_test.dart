/// A box with no width of its own around an `Align` is as wide as it is
/// offered, as Flutter's `Container` is: the `Align` takes the room, and the
/// box around it has to have it to give.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> outer(Widget child) {
    final app = AppTester.widget(
      Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 160, color: const Color(0xFFEEEEEE), child: child),
          ],
        ),
      ),
    );
    return app.ofType('Box').first.props;
  }

  test('around an Align it fills the width', () {
    final box = outer(
      const Align(alignment: Alignment.bottomRight, child: Text('x')),
    );

    expect(box['height'], 160);
    expect(box['expand'], 'width');
  });

  test('around an AnimatedAlign too', () {
    final box = outer(
      const AnimatedAlign(
        alignment: Alignment.bottomRight,
        duration: Duration(milliseconds: 200),
        child: Text('x'),
      ),
    );

    expect(box['expand'], 'width');
  });

  test('an Align that hugs its child leaves the box hugging', () {
    final box = outer(
      const Align(
        alignment: Alignment.bottomRight,
        widthFactor: 1,
        child: Text('x'),
      ),
    );

    expect(box['expand'], isNull);
  });

  test('around plain text it still hugs', () {
    expect(outer(const Text('x'))['expand'], isNull);
  });
}
