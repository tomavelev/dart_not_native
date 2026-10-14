/// Flutter's cubic curves travel as cubics, with Flutter's numbers, and the
/// five named paces by name.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a cubic says its control points', () {
    expect(Curves.fastOutSlowIn.name, 'cubic(0.4,0.0,0.2,1.0)');
    expect(Curves.easeOutBack.name, 'cubic(0.175,0.885,0.32,1.275)');
    expect(const Cubic(0.1, 0.2, 0.3, 0.4).name, 'cubic(0.1,0.2,0.3,0.4)');
  });

  test('the five are said by name', () {
    expect(Curves.ease.name, 'ease');
    expect(Curves.easeInOut.name, 'easeInOut');
  });

  test('a curve with no cubic in Flutter is the nearest of the five', () {
    expect(Curves.bounceOut, Curves.easeOut);
    expect(Curves.decelerate, Curves.easeOut);
  });

  test('an overshooting cubic overshoots', () {
    expect(Curves.easeOutBack.transform(0.7), greaterThan(1.0));
  });

  test('flipped turns a cubic end for end', () {
    final flipped = Curves.easeInQuad.flipped as Cubic;
    expect(flipped.a, closeTo(1 - 0.68, 1e-9));
    expect(flipped.b, closeTo(1 - 0.53, 1e-9));
    expect(
      flipped.transform(0.3),
      closeTo(1 - Curves.easeInQuad.transform(0.7), 0.01),
    );
  });

  test('an animated box carries the cubic to the renderer', () {
    final app = AppTester.widget(
      const AnimatedOpacity(
        opacity: 0.5,
        duration: Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        child: Text('x'),
      ),
    );
    expect(
      app.ofType('AnimatedOpacity').single.props['curve'],
      'cubic(0.4,0.0,0.2,1.0)',
    );
  });
}
