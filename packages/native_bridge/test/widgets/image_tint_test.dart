/// `Image.color` travels to the renderer as a tint.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a colour is carried', () {
    final app = AppTester.widget(
      const Scaffold(
        body: Image(
          image: NetworkImage('https://example.com/a.png'),
          color: Color(0xFF112233),
        ),
      ),
    );

    expect(app.ofType('Image').single.props['color'], '#112233');
  });

  test('an image without one says nothing', () {
    final app = AppTester.widget(
      const Scaffold(
        body: Image(image: NetworkImage('https://example.com/a.png')),
      ),
    );

    expect(app.ofType('Image').single.props.containsKey('color'), isFalse);
  });
}
