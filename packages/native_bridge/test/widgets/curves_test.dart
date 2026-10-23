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
    expect(Curves.decelerate, Curves.easeOut);
  });

  test('a bounce and an elastic travel as their own shape', () {
    List<double> samples(Curve curve) {
      final name = curve.name;
      expect(name, startsWith('samples('));
      return [
        for (final v in name.substring(8, name.length - 1).split(','))
          double.parse(v),
      ];
    }

    final bounce = samples(Curves.bounceOut);
    expect(bounce, hasLength(65));
    expect(bounce.first, 0);
    expect(bounce.last, 1);
    // It falls back on its way: not a cubic's one rise.
    var falls = 0;
    for (var i = 1; i < bounce.length; i++) {
      if (bounce[i] < bounce[i - 1]) falls++;
    }
    expect(falls, greaterThan(3));
    // Flutter's numbers: a third of the way it is 7.5625 t².
    expect(Curves.bounceOut.transform(0.2), closeTo(7.5625 * 0.04, 1e-9));

    final elastic = samples(Curves.elasticOut);
    expect(elastic.reduce((a, b) => a > b ? a : b), greaterThan(1.2));
    expect(elastic.last, closeTo(1, 1e-3));
    expect(const ElasticOutCurve(0.8), isNot(Curves.elasticOut));
    expect(Curves.bounceIn.transform(0.3),
        closeTo(1 - Curves.bounceOut.transform(0.7), 1e-9));
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
