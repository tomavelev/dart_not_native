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

  test('an AnimatedBuilder is read through what it builds', () async {
    await push(
      (_, animation, _, child) => AnimatedBuilder(
        animation: animation,
        builder: (_, child) => Opacity(opacity: animation.value, child: child),
        child: child,
      ),
    );
    expect(transition()!['page'], {'opacity': 0.0});
  });

  test('a Transform moves it by its offset, scale and turn', () async {
    final screen = MediaQuery.sizeOf(page);
    await push(
      (_, animation, _, child) => AnimatedBuilder(
        animation: animation,
        builder: (_, child) => Transform.translate(
          offset: Offset((1 - animation.value) * screen.width / 2, 0),
          child: Transform.scale(
            scale: 0.5 + animation.value / 2,
            child: child,
          ),
        ),
        child: child,
      ),
    );
    final moved = transition()!['page'] as Map;
    expect(moved['dx'], closeTo(0.5, 1e-9));
    expect(moved['scale'], closeTo(0.5, 1e-9));
  });

  test('a turning matrix is a turn', () async {
    await push(
      (_, animation, _, child) => AnimatedBuilder(
        animation: animation,
        builder: (_, child) => Transform(
          transform: Matrix4.rotationZ((1 - animation.value) * math.pi / 4),
          child: child,
        ),
        child: child,
      ),
    );
    expect(
      (transition()!['page'] as Map)['rotate'],
      closeTo(math.pi / 4, 1e-9),
    );
  });

  test('a SizeTransition reveals the page, and a KeyedSubtree is passed '
      'through', () async {
    await push(
      (_, animation, _, child) => SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        axisAlignment: -1,
        child: KeyedSubtree(
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
    expect(transition()!['page'], {
      'opacity': 0.0,
      'reveal': 0.0,
      'revealAxis': 'horizontal',
      'revealAlign': -1.0,
    });
  });

  test('padding and a widget of the app\'s own are read through', () async {
    await push(
      (_, animation, _, child) => _Framed(
        child: Padding(
          padding: EdgeInsets.zero,
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
    );
    expect(transition()!['page'], {'opacity': 0.0});
  });

  test('something else in the way ends the reading there', () async {
    await push(
      (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: Stack(
          children: [SlideTransition(
            position: Tween(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          )],
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

  group('the page beneath', () {
    // Slides a third of the way off as it is covered, as Cupertino's does.
    Widget parallax(
      BuildContext _,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
    ) => SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-1 / 3, 0),
      ).animate(secondaryAnimation),
      child: FadeTransition(opacity: animation, child: child),
    );

    Future<void> pushOver(Route<void> route) async {
      Navigator.of(page).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => screen('under'),
          transitionsBuilder: parallax,
        ),
      );
      await pumpEventQueue();
      Navigator.of(page).push(route);
      await pumpEventQueue();
    }

    test('moves as its secondaryAnimation says when one is pushed over it, '
        'and back when that one is popped', () async {
      await pushOver(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => screen('over'),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      expect(transition(), {
        'kind': 'push',
        'ms': 300,
        'page': {'opacity': 0.0},
        'picture': {'dx': -1 / 3},
      });

      Navigator.of(page).pop();
      await pumpEventQueue();
      expect(transition(), {
        'kind': 'pop',
        'ms': 300,
        'picture': {'opacity': 0.0},
        'page': {'dx': -1 / 3},
      });
    });

    test('under a page that leaves the move to the renderer, that move is '
        'said so both go together', () async {
      await pushOver(MaterialPageRoute<void>(builder: (_) => screen('over')));
      expect(transition(), {
        'kind': 'push',
        'ms': 300,
        'page': {'dx': 0.25, 'curve': 'easeOut'},
        'picture': {'dx': -1 / 3},
      });
    });

    test(
      'a transition that ignores it leaves the page beneath still',
      () async {
        await push(
          (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        );
        Navigator.of(page).push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => screen('three'),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
        await pumpEventQueue();
        expect(transition()!.containsKey('picture'), isFalse);
      },
    );
  });

  test('ReverseAnimation runs the other way', () {
    const reversed = ReverseAnimation(kAlwaysCompleteAnimation);
    expect(reversed.value, 0);
    expect(reversed.status, AnimationStatus.dismissed);
  });
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(child: child);
}
