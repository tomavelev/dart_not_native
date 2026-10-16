/// A route's own transition moves its page: what `transitionsBuilder` (or a
/// route's `buildTransitions`) does to the page at the start of its
/// animation is read off the transition widgets it returns and told to the
/// renderer - `page` for one arriving, `picture` for one leaving. It used to
/// be accepted and never called.
library;

import 'dart:math' as math;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tilted<T> extends PageRoute<T> {
  _Tilted(this.child);
  final Widget child;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => RotationTransition(
    turns: Tween<double>(begin: 0.25, end: 0).animate(animation),
    child: child,
  );
}

void main() {
  late AppTester tester;
  late BuildContext page;

  Widget screen(String name) => Builder(
    builder: (context) {
      page = context;
      return Scaffold(body: Text(name));
    },
  );

  Map<String, dynamic>? transition() =>
      (tester.tree.props[RootProps.pageTransition] as Map?)
          ?.cast<String, dynamic>();

  setUp(() => tester = AppTester.widget(MaterialApp(home: screen('home'))));

  Future<void> push(RouteTransitionsBuilder builder) async {
    Navigator.of(page).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => screen('two'),
        transitionsBuilder: builder,
      ),
    );
    await pumpEventQueue();
  }

  test('a fade starts the page clear, and leaves its picture clear', () async {
    await push(
      (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    expect(tester.hasText('two'), isTrue);
    expect(transition(), {
      'kind': 'push',
      'ms': 300,
      'page': {'opacity': 0.0},
    });

    Navigator.of(page).pop();
    await pumpEventQueue();
    expect(transition(), {
      'kind': 'pop',
      'ms': 300,
      'picture': {'opacity': 0.0},
    });
  });

  test(
    'a slide from the side, along the curve its tween is chained to',
    () async {
      await push(
        (_, animation, _, child) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOut)),
          ),
          child: child,
        ),
      );
      expect(transition()!['page'], {'dx': 1.0, 'curve': 'easeOut'});
    },
  );

  test('a curved animation names its curve', () async {
    await push(
      (_, animation, _, child) => ScaleTransition(
        scale: Tween<double>(
          begin: 0.5,
          end: 1,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeIn)),
        child: child,
      ),
    );
    expect(transition()!['page'], {'scale': 0.5, 'curve': 'easeIn'});
  });

  test('transitions inside one another add up', () async {
    await push(
      (_, animation, _, child) => FadeTransition(
        opacity: Tween<double>(begin: 0.5, end: 1).animate(animation),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
            child: child,
          ),
        ),
      ),
    );
    final moved = transition()!['page'] as Map;
    expect(moved['opacity'], 0.5);
    expect(moved['dy'], 0.25);
    expect(moved['scale'], closeTo(0.8, 1e-9));
    expect(moved.containsKey('dx'), isFalse);
  });

  test('a route of its own that overrides buildTransitions', () async {
    Navigator.of(page).push(_Tilted<void>(screen('two')));
    await pumpEventQueue();
    expect(
      (transition()!['page'] as Map)['rotate'],
      closeTo(math.pi / 2, 1e-9),
    );
  });

  test('a whole turn is told from where it ends, and still turns', () async {
    await push(
      (_, animation, _, child) =>
          RotationTransition(turns: animation, child: child),
    );
    expect(
      (transition()!['page'] as Map)['rotate'],
      closeTo(-2 * math.pi, 1e-9),
    );
  });

  test('a builder that returns the page as it is does not move it', () async {
    await push((_, _, _, child) => child);
    expect(transition()!['page'], isEmpty);
  });

  test('something else in the way ends the reading there', () async {
    await push(
      (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: Padding(
          padding: EdgeInsets.zero,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
      ),
    );
    expect(transition()!['page'], {'opacity': 0.0});
  });

  test('a MaterialPageRoute leaves the move to the renderer', () async {
    Navigator.of(
      page,
    ).push(MaterialPageRoute<void>(builder: (_) => screen('x')));
    await pumpEventQueue();
    expect(transition(), {'kind': 'push', 'ms': 300});
  });

  test('ReverseAnimation runs the other way', () {
    const reversed = ReverseAnimation(kAlwaysCompleteAnimation);
    expect(reversed.value, 0);
    expect(reversed.status, AnimationStatus.dismissed);
  });
}
