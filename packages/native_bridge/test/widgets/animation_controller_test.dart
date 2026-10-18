/// An `AnimationController` is a run from one value to another: the tree is
/// built at the end of it, carrying how long it takes, and the renderer
/// moves the screen there. A run started while the screen is being built is
/// drawn at its start first.
library;

import 'dart:math' as math;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fading extends StatefulWidget {
  const _Fading({super.key, this.start = false, this.repeat = false});
  final bool start;
  final bool repeat;
  @override
  State<_Fading> createState() => _FadingState();
}

class _FadingState extends State<_Fading> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.start) controller.forward();
    if (widget.repeat) controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FadeTransition(opacity: controller, child: const Text('faded')),
      AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Transform.rotate(
          angle: controller.value * math.pi,
          child: child,
        ),
        child: const Text('turned'),
      ),
    ],
  );
}

void main() {
  Future<void> wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  ({double opacity, int ms}) fade(AppTester app) {
    final node = app.ofType('AnimatedOpacity').single;
    return (
      opacity: (node.props['opacity'] as num).toDouble(),
      ms: node.props['durationMs'] as int,
    );
  }

  Map<String, dynamic> turn(AppTester app) => app.nodes
      .firstWhere((n) => n.type == 'Box' && n.props['transform'] != null)
      .props;

  test('a run is built at its end, carrying its length', () async {
    final key = GlobalKey<_FadingState>();
    final app = AppTester.widget(_Fading(key: key));
    expect(fade(app), (opacity: 0.0, ms: 0));

    final done = key.currentState!.controller.forward();
    await wait(10);
    expect(fade(app), (opacity: 1.0, ms: 100));
    expect(turn(app)['animateMs'], 100);
    expect(key.currentState!.controller.status, AnimationStatus.forward);

    await done;
    await wait(10);
    expect(fade(app), (opacity: 1.0, ms: 0));
    // At rest it says it takes no time: the same box to a renderer.
    expect(turn(app)['animateMs'], 0);
    expect(key.currentState!.controller.status, AnimationStatus.completed);
  });

  test('outside a build its value is where the run is by the clock', () async {
    final key = GlobalKey<_FadingState>();
    AppTester.widget(_Fading(key: key));
    final controller = key.currentState!.controller;
    controller.forward();
    await wait(50);
    expect(controller.value, inExclusiveRange(0.1, 0.95));
    expect(controller.isAnimating, isTrue);
  });

  test('started in initState, it is drawn at its start, then its end', () async {
    final app = AppTester.widget(const _Fading(start: true));
    expect(fade(app).opacity, 0);
    await wait(10);
    // Not yet: the tree that moves it is a tree of its own.
    expect(fade(app).opacity, 0);
    await wait(50);
    expect(fade(app), (opacity: 1.0, ms: 100));
  });

  test('repeat goes back and forth, a run each way', () async {
    final key = GlobalKey<_FadingState>();
    final app = AppTester.widget(_Fading(key: key, repeat: true));
    await wait(50);
    expect(fade(app), (opacity: 1.0, ms: 100));
    await wait(100);
    expect(fade(app), (opacity: 0.0, ms: 100));
    key.currentState!.controller.stop();
    expect(key.currentState!.controller.isAnimating, isFalse);
  });

  test('the app\'s listeners hear each frame; status listeners each status',
      () async {
    final controller = AnimationController(
      vsync: const _NoTicks(),
      duration: const Duration(milliseconds: 100),
    );
    final heard = <double>[];
    final statuses = <AnimationStatus>[];
    controller
      ..addListener(() => heard.add(controller.value))
      ..addStatusListener(statuses.add);
    await controller.forward();
    expect(heard.length, greaterThan(3));
    expect(heard.where((v) => v > 0.05 && v < 0.95), isNotEmpty);
    expect(heard, orderedEquals([...heard]..sort()));
    expect(heard.last, 1);
    expect(statuses, [AnimationStatus.forward, AnimationStatus.completed]);
    expect(controller.value, 1);

    await controller.reverse();
    expect(statuses.last, AnimationStatus.dismissed);
    expect(controller.value, 0);

    controller.value = 0.25;
    expect(controller.value, 0.25);
    expect(controller.status, AnimationStatus.forward);
  });

  test('a slide in from the side, unmeasured, starts out of sight and then '
      'where it starts', () async {
    final app = AppTester.widget(const _Sliding());
    WidgetNode box() => app.nodes.firstWhere(
      (n) => n.type == 'Box' && n.props['sizeEventId'] != null,
    );
    await wait(60);
    expect(box().props['opacity'], 0);
    await app.emit(box().props['sizeEventId'] as String, {
      'width': 100.0,
      'height': 50.0,
    });
    await wait(5);
    expect(box().props['opacity'], isNull);
    expect(box().props['transform'], {'dx': 200.0, 'dy': 0.0});
    expect(box().props['animateMs'], 0);
    await wait(60);
    expect(box().props['transform'], {'dx': 0.0, 'dy': 0.0});
    expect(box().props['animateMs'], 300);
  });

  test('a run stops where an interval or a tween sequence turns', () async {
    final key = GlobalKey<_StaggeredState>();
    final app = AppTester.widget(_Staggered(key: key));
    List<({double opacity, int ms, String? curve})> fades() => [
      for (final n in app.ofType('AnimatedOpacity'))
        (
          opacity: (n.props['opacity'] as num).toDouble(),
          ms: n.props['durationMs'] as int,
          curve: n.props['curve'] as String?,
        ),
    ];
    double scale() => (app.nodes
            .firstWhere((n) => n.type == 'Box' && n.props['transform'] != null)
            .props['transform'] as Map)['scale'] as double;
    expect(fades().map((f) => f.opacity), [0, 0]);

    key.currentState!.controller.forward();
    // To a quarter of the way, where the sequence turns: the first fade is
    // half done along its own curve, over that leg.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fades()[0].opacity, closeTo(Curves.easeOut.transform(0.5), 1e-9));
    expect(fades()[0].ms, 50);
    expect(fades()[0].curve, Curves.easeOut.name);
    expect(fades()[1].opacity, 0);
    expect(scale(), closeTo(1.5, 1e-9));

    // Then to the middle: the first is in, the second not yet begun.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fades()[0].opacity, 1);
    expect(fades()[1].opacity, 0);
    expect(fades()[1].ms, 50);

    // Then the second, over the rest.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(fades()[1].opacity, 1);
    expect(fades()[1].ms, 100);
    expect(scale(), closeTo(1, 1e-9));
  });

  test('a listener that rebuilds draws the run a frame at a time', () async {
    final key = GlobalKey<_TickingState>();
    final app = AppTester.widget(_Ticking(key: key));
    final seen = <double>{};
    key.currentState!.controller.forward();
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final box = app.nodes.firstWhere((n) => n.props['opacity'] != null);
      seen.add((box.props['opacity'] as num).toDouble());
      expect(box.props['animateMs'], anyOf(isNull, 0));
    }
    expect(seen.where((v) => v > 0.05 && v < 0.95).length, greaterThan(3));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final box = app.nodes.firstWhere((n) => n.props['opacity'] != null);
    expect(box.props['opacity'], 1);
  });

  test('started from a tap, a listener that rebuilds never shows the end '
      'first', () async {
    final key = GlobalKey<_TickingState>();
    final app = AppTester.widget(_Ticking(key: key, button: true));
    double opacity() => (app.nodes
            .firstWhere((n) => n.props['opacity'] != null)
            .props['opacity'] as num)
        .toDouble();
    final button = app.nodes.firstWhere((n) => n.props['label'] == 'go');
    await app.tapEvent(button.props['eventId'] as String);
    final seen = [opacity()];
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      seen.add(opacity());
    }
    // A fifth of the way at most, in the first 50 ms of 200.
    expect(seen.every((v) => v < 0.5), isTrue, reason: '$seen');
  });

  test('half the range takes half the time; a curve travels with it', () async {
    final key = GlobalKey<_FadingState>();
    final app = AppTester.widget(
      MaterialApp(
        home: Builder(
          builder: (context) => _Curved(key: key),
        ),
      ),
    );
    key.currentState!.controller.animateTo(0.5);
    await wait(10);
    final node = app.ofType('AnimatedOpacity').single;
    expect(node.props['durationMs'], 50);
    expect(node.props['curve'], Curves.easeIn.name);
    expect(node.props['opacity'], closeTo(Curves.easeIn.transform(0.5), 1e-9));
  });
}

class _Staggered extends StatefulWidget {
  const _Staggered({super.key});
  @override
  State<_Staggered> createState() => _StaggeredState();
}

class _StaggeredState extends State<_Staggered>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FadeTransition(
        opacity: CurvedAnimation(
          parent: controller,
          curve: const Interval(0, 0.5, curve: Curves.easeOut),
        ),
        child: const Text('first'),
      ),
      FadeTransition(
        opacity: controller.drive(CurveTween(curve: const Interval(0.5, 1))),
        child: const Text('second'),
      ),
      ScaleTransition(
        scale: TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1, end: 1.5), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.5, end: 1), weight: 3),
        ]).animate(controller),
        child: const Text('pulse'),
      ),
    ],
  );
}

class _Ticking extends StatefulWidget {
  const _Ticking({super.key, this.button = false});
  final bool button;
  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => setState(() {}));

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Opacity(opacity: controller.value, child: const Text('ticking')),
      if (widget.button)
        TextButton(onPressed: controller.forward, child: const Text('go')),
    ],
  );
}

class _Curved extends _Fading {
  const _Curved({super.key});
  @override
  State<_Fading> createState() => _CurvedState();
}

class _CurvedState extends _FadingState {
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: controller, curve: Curves.easeIn),
    child: const Text('curved'),
  );
}

class _Sliding extends StatefulWidget {
  const _Sliding();
  @override
  State<_Sliding> createState() => _SlidingState();
}

class _SlidingState extends State<_Sliding>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    controller.forward();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(2, 0),
      end: Offset.zero,
    ).animate(controller),
    child: const Text('in'),
  );
}

class _NoTicks implements TickerProvider {
  const _NoTicks();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
