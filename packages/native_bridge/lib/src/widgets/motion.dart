part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Motion.
//
// The tree says what the screen *is*, and a renderer animates the difference
// from what it was. So the animated widgets here are the plain ones with a
// duration attached, and an AnimationController is a run from one value to
// another that the tree is built at the end of: the frames happen on the far
// side of the channel.
// ---------------------------------------------------------------------------

/// How an animation is paced over its duration.
///
/// The protocol carries five paces by name - `linear`, `ease`, `easeIn`,
/// `easeOut`, `easeInOut` - and any cubic Bézier by its two control points
/// (`cubic(a,b,c,d)`), which every renderer can draw: a CSS
/// `cubic-bezier`, an Android `PathInterpolator`, UIKit's cubic timing.
/// Every curve Flutter names is here, and each that is a cubic in Flutter
/// travels as that cubic, with Flutter's numbers - `Curves.fastOutSlowIn`,
/// `Curves.easeOutBack` with its overshoot. The rest - a bounce, a spring -
/// travel as the nearest of the five, which keeps the motion honest about
/// where it goes, if not about the way there.
class Curve {
  const Curve(this.name);

  /// The name the protocol carries; each renderer maps it onto its own.
  final String name;

  /// The curve's value at [t], for code that drives its own animation from a
  /// [Ticker]. It is the cubic of the pace the curve travels as.
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return switch (name) {
      'linear' => t,
      'easeIn' => _cubic(0.42, 0.0, 1.0, 1.0, t),
      'easeOut' => _cubic(0.0, 0.0, 0.58, 1.0, t),
      'easeInOut' => _cubic(0.42, 0.0, 0.58, 1.0, t),
      _ => _cubic(0.25, 0.1, 0.25, 1.0, t),
    };
  }

  /// The curve run backwards.
  Curve get flipped => switch (name) {
    'easeIn' => Curves.easeOut,
    'easeOut' => Curves.easeIn,
    _ => this,
  };

  @override
  bool operator ==(Object other) => other is Curve && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// A cubic Bézier curve through (0,0), ([a],[b]), ([c],[d]) and (1,1),
/// which travels to a renderer as itself.
class Cubic extends Curve {
  const Cubic(this.a, this.b, this.c, this.d) : super('cubic($a,$b,$c,$d)');
  final double a;
  final double b;
  final double c;
  final double d;

  @override
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return _cubic(a, b, c, d, t);
  }

  /// The same curve run backwards: the cubic turned end for end.
  @override
  Curve get flipped => Cubic(1 - c, 1 - d, 1 - a, 1 - b);
}

/// y at x = [t] on the cubic Bézier with control points (a,b) and (c,d),
/// found by bisecting for the parameter - the way Flutter's `Cubic` does.
double _cubic(double a, double b, double c, double d, double t) {
  double at(double p1, double p2, double m) =>
      3 * p1 * (1 - m) * (1 - m) * m + 3 * p2 * (1 - m) * m * m + m * m * m;
  var low = 0.0;
  var high = 1.0;
  while (true) {
    final middle = (low + high) / 2;
    final x = at(a, c, middle);
    if ((t - x).abs() < 0.001) return at(b, d, middle);
    if (x < t) {
      low = middle;
    } else {
      high = middle;
    }
  }
}

/// Flutter's curves, each as the pace it travels as. See [Curve].
abstract final class Curves {
  static const Curve linear = Curve('linear');
  static const Curve ease = Curve('ease');
  static const Curve easeIn = Curve('easeIn');
  static const Curve easeOut = Curve('easeOut');
  static const Curve easeInOut = Curve('easeInOut');

  // Not cubics in Flutter, and so the nearest of the five.
  static const Curve decelerate = easeOut;
  static const Curve fastEaseInToSlowEaseOut = easeInOut;
  static const Curve easeInOutCubicEmphasized = easeInOut;

  // Flutter's cubics, with Flutter's numbers.
  static const Cubic fastLinearToSlowEaseIn = Cubic(0.18, 1.0, 0.04, 1.0);
  static const Cubic fastOutSlowIn = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Cubic slowMiddle = Cubic(0.15, 0.85, 0.85, 0.15);
  static const Cubic linearToEaseOut = Cubic(0.35, 0.91, 0.33, 0.97);
  static const Cubic easeInToLinear = Cubic(0.67, 0.03, 0.65, 0.09);

  static const Cubic easeInSine = Cubic(0.47, 0.0, 0.745, 0.715);
  static const Cubic easeInQuad = Cubic(0.55, 0.085, 0.68, 0.53);
  static const Cubic easeInCubic = Cubic(0.55, 0.055, 0.675, 0.19);
  static const Cubic easeInQuart = Cubic(0.895, 0.03, 0.685, 0.22);
  static const Cubic easeInQuint = Cubic(0.755, 0.05, 0.855, 0.06);
  static const Cubic easeInExpo = Cubic(0.95, 0.05, 0.795, 0.035);
  static const Cubic easeInCirc = Cubic(0.6, 0.04, 0.98, 0.335);
  static const Cubic easeInBack = Cubic(0.6, -0.28, 0.735, 0.045);

  static const Cubic easeOutSine = Cubic(0.39, 0.575, 0.565, 1.0);
  static const Cubic easeOutQuad = Cubic(0.25, 0.46, 0.45, 0.94);
  static const Cubic easeOutCubic = Cubic(0.215, 0.61, 0.355, 1.0);
  static const Cubic easeOutQuart = Cubic(0.165, 0.84, 0.44, 1.0);
  static const Cubic easeOutQuint = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Cubic easeOutExpo = Cubic(0.19, 1.0, 0.22, 1.0);
  static const Cubic easeOutCirc = Cubic(0.075, 0.82, 0.165, 1.0);
  static const Cubic easeOutBack = Cubic(0.175, 0.885, 0.32, 1.275);

  static const Cubic easeInOutSine = Cubic(0.445, 0.05, 0.55, 0.95);
  static const Cubic easeInOutQuad = Cubic(0.455, 0.03, 0.515, 0.955);
  static const Cubic easeInOutCubic = Cubic(0.645, 0.045, 0.355, 1.0);
  static const Cubic easeInOutQuart = Cubic(0.77, 0.0, 0.175, 1.0);
  static const Cubic easeInOutQuint = Cubic(0.86, 0.0, 0.07, 1.0);
  static const Cubic easeInOutExpo = Cubic(1.0, 0.0, 0.0, 1.0);
  static const Cubic easeInOutCirc = Cubic(0.785, 0.135, 0.15, 0.86);
  static const Cubic easeInOutBack = Cubic(0.68, -0.55, 0.265, 1.55);

  // A bounce or a spring is not one of the five; each lands where it would
  // have, along the pace nearest its overall shape.
  static const Curve bounceIn = easeIn;
  static const Curve bounceOut = easeOut;
  static const Curve bounceInOut = easeInOut;
  static const Curve elasticIn = easeIn;
  static const Curve elasticOut = easeOut;
  static const Curve elasticInOut = easeInOut;
}

/// Where an animation is in its run.
enum AnimationStatus { dismissed, forward, reverse, completed }

/// A value that changes over time, in Flutter. The ones that move are an
/// [AnimationController] and what is made from one - a [CurvedAnimation], a
/// tween's [Animatable.animate] - and they move as runs the renderer plays
/// (see [AnimationController]); the rest stand still, for the signatures that
/// name them - a progress indicator's `valueColor`, a page route's builder.
abstract class Animation<T> extends Listenable {
  const Animation();
  T get value;
  AnimationStatus get status;
  bool get isCompleted => status == AnimationStatus.completed;
  bool get isDismissed => status == AnimationStatus.dismissed;

  /// [child]'s values along this animation, as [Animatable.animate] gives
  /// them: what a route's transition is usually written with.
  Animation<U> drive<U>(Animatable<U> child) =>
      child.animate(this as Animation<double>);
}

/// [parent] run backwards: one minus its value, in Flutter.
class ReverseAnimation extends Animation<double> {
  const ReverseAnimation(this.parent);
  final Animation<double> parent;
  @override
  double get value => 1 - parent.value;
  @override
  AnimationStatus get status => switch (parent.status) {
    AnimationStatus.forward => AnimationStatus.reverse,
    AnimationStatus.reverse => AnimationStatus.forward,
    AnimationStatus.completed => AnimationStatus.dismissed,
    AnimationStatus.dismissed => AnimationStatus.completed,
  };
  @override
  void addListener(VoidCallback listener) => parent.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => parent.removeListener(listener);
}

/// The curve [animation] runs along, where it is one that says: a
/// [CurvedAnimation], or a tween chained to a [CurveTween], anywhere along
/// it.
Curve? _curveIn(Animation<Object?> animation) => switch (animation) {
  CurvedAnimation(:final curve) => curve,
  ReverseAnimation(:final parent) => _curveIn(parent),
  _AnimatedEvaluation(:final parent, :final animatable) =>
    _curveOfAnimatable(animatable) ?? _curveIn(parent),
  _ => null,
};

Curve? _curveOfAnimatable(Animatable<Object?> animatable) =>
    switch (animatable) {
      CurveTween(:final curve) => curve,
      _ChainedEvaluation(:final parent, :final evaluatable) =>
        _curveOfAnimatable(evaluatable) ?? _curveOfAnimatable(parent),
      _ => null,
    };

/// How long a transition widget takes to move to the value [animation] has
/// now - over an [AnimatedSwitcher]'s transition, or over the run of the
/// controller that drives it, which it then follows; null when it is
/// simply drawn at its value.
({Duration duration, Curve curve})? _timeFor(
  BuildContext context,
  Animation<Object?> animation,
) {
  final switching = _TransitionTime.of(context);
  if (switching != null) {
    return (duration: switching.duration, curve: switching.curve);
  }
  if (!_controlled(animation)) return null;
  _Owner._current?._watch(animation);
  return _runTime(animation) ??
      (duration: Duration.zero, curve: Curves.linear);
}

/// How long a transition widget takes to move to the value its animation
/// has now: set round what an [AnimatedSwitcher]'s `transitionBuilder`
/// returns, which is built at the animation's start and then at its end.
/// Anywhere else a transition is drawn at its value outright.
class _TransitionTime extends InheritedWidget {
  const _TransitionTime({
    required this.duration,
    required this.curve,
    required super.child,
  });
  final Duration duration;
  final Curve curve;

  static _TransitionTime? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TransitionTime>();

  @override
  bool updateShouldNotify(_TransitionTime oldWidget) =>
      oldWidget.duration != duration || oldWidget.curve != curve;
}

/// A child at the opacity an [Animation] says, in Flutter.
///
/// Driven by an [AnimationController], it fades over each of its runs (and
/// so do the other transitions below). Otherwise the child is drawn at the
/// value the animation has when the widget is built - which, for the
/// animation a page route hands its `buildTransitions`, is fully shown.
/// Built by an [AnimatedSwitcher]'s `transitionBuilder`, it fades from the
/// value at the start to the value at the end.
class FadeTransition extends StatelessWidget {
  const FadeTransition({
    super.key,
    required this.opacity,
    this.alwaysIncludeSemantics = false,
    this.child,
  });
  final Animation<double> opacity;
  final bool alwaysIncludeSemantics;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final time = _timeFor(context, opacity);
    final value = opacity.value.clamp(0.0, 1.0).toDouble();
    final child = this.child ?? const SizedBox.shrink();
    if (time != null) {
      return AnimatedOpacity(
        opacity: value,
        duration: time.duration,
        curve: time.curve,
        child: child,
      );
    }
    return value >= 1 ? child : Opacity(opacity: value, child: child);
  }
}

/// A child at the scale an [Animation] says, in Flutter - moving there, in
/// an [AnimatedSwitcher]'s transition (see [FadeTransition]).
class ScaleTransition extends StatelessWidget {
  const ScaleTransition({
    super.key,
    required this.scale,
    this.alignment = Alignment.center,
    this.filterQuality,
    this.child,
  });
  final Animation<double> scale;

  /// Accepted and not carried: a box scales about its middle.
  final Alignment alignment;
  final Object? filterQuality;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final time = _timeFor(context, scale);
    return AnimatedScale(
      scale: scale.value,
      duration: time?.duration ?? Duration.zero,
      curve: time?.curve ?? Curves.linear,
      child: child,
    );
  }
}

/// A child turned by as many turns as an [Animation] says, in Flutter -
/// turning there, in an [AnimatedSwitcher]'s transition.
class RotationTransition extends StatelessWidget {
  const RotationTransition({
    super.key,
    required this.turns,
    this.alignment = Alignment.center,
    this.filterQuality,
    this.child,
  });
  final Animation<double> turns;
  final Alignment alignment;
  final Object? filterQuality;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final time = _timeFor(context, turns);
    return AnimatedRotation(
      turns: turns.value,
      duration: time?.duration ?? Duration.zero,
      curve: time?.curve ?? Curves.linear,
      child: child,
    );
  }
}

/// A child moved by the [Offset] an [Animation] says, in multiples of its
/// own size, in Flutter - sliding there, in an [AnimatedSwitcher]'s
/// transition.
class SlideTransition extends StatelessWidget {
  const SlideTransition({
    super.key,
    required this.position,
    this.transformHitTests = true,
    this.textDirection,
    this.child,
  });
  final Animation<Offset> position;
  final bool transformHitTests;
  final TextDirection? textDirection;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final time = _timeFor(context, position);
    var offset = position.value;
    // Read from the right, a slide along the line is the other way round.
    if (textDirection == TextDirection.rtl) offset = Offset(-offset.dx, offset.dy);
    return AnimatedSlide(
      offset: offset,
      duration: time?.duration ?? Duration.zero,
      curve: time?.curve ?? Curves.linear,
      child: child,
    );
  }
}

/// A child shown by as much of its size along [axis] as an [Animation]
/// says, in Flutter. Here it is all of it or none of it - none at zero -
/// and in an [AnimatedSwitcher]'s transition the space moves from the one
/// to the other.
class SizeTransition extends StatelessWidget {
  const SizeTransition({
    super.key,
    this.axis = Axis.vertical,
    required this.sizeFactor,
    this.axisAlignment = 0.0,
    this.fixedCrossAxisSizeFactor,
    this.child,
  });
  final Axis axis;
  final Animation<double> sizeFactor;
  final double axisAlignment;
  final double? fixedCrossAxisSizeFactor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final time = _timeFor(context, sizeFactor);
    final shown = sizeFactor.value > 0
        ? (child ?? const SizedBox.shrink())
        : (axis == Axis.vertical
              ? const SizedBox(height: 0)
              : const SizedBox(width: 0));
    if (time == null) return shown;
    return AnimatedSize(
      duration: time.duration,
      curve: time.curve,
      alignment: axis == Axis.vertical
          ? Alignment(0, axisAlignment)
          : Alignment(axisAlignment, 0),
      child: shown,
    );
  }
}

/// Something that gives a value for a point along an animation, in Flutter.
abstract class Animatable<T> {
  const Animatable();

  /// The value at [t], 0 to 1.
  T transform(double t);

  /// The value at the point [animation] is at.
  T evaluate(Animation<double> animation) => transform(animation.value);

  /// An animation of this, driven by [parent].
  Animation<T> animate(Animation<double> parent) =>
      _AnimatedEvaluation<T>(parent, this);

  /// This, along the values [parent] gives.
  Animatable<T> chain(Animatable<double> parent) =>
      _ChainedEvaluation<T>(parent, this);
}

class _AnimatedEvaluation<T> extends Animation<T> {
  _AnimatedEvaluation(this.parent, this.animatable);
  final Animation<double> parent;
  final Animatable<T> animatable;
  @override
  T get value => animatable.evaluate(parent);
  @override
  AnimationStatus get status => parent.status;
  @override
  void addListener(VoidCallback listener) => parent.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      parent.removeListener(listener);
}

class _ChainedEvaluation<T> extends Animatable<T> {
  _ChainedEvaluation(this.parent, this.evaluatable);
  final Animatable<double> parent;
  final Animatable<T> evaluatable;
  @override
  T transform(double t) => evaluatable.transform(parent.transform(t));
}

/// The values between [begin] and [end], in Flutter: numbers, offsets,
/// sizes, alignments and colours go between the two; anything else is
/// [begin] before the middle and [end] from it.
class Tween<T extends Object?> extends Animatable<T> {
  Tween({this.begin, this.end});
  T? begin;
  T? end;

  /// The value a [t] of the way from [begin] to [end].
  T lerp(double t) {
    final a = begin, b = end;
    double number(Object? n) => (n as num?)?.toDouble() ?? 0;
    final Object? value = switch ((a, b)) {
      (num? _, num? _) when a != null || b != null =>
        number(a) + (number(b) - number(a)) * t,
      (Offset x, Offset y) => Offset(
        x.dx + (y.dx - x.dx) * t,
        x.dy + (y.dy - x.dy) * t,
      ),
      (Size x, Size y) => Size(
        x.width + (y.width - x.width) * t,
        x.height + (y.height - x.height) * t,
      ),
      (Alignment x, Alignment y) => Alignment(
        x.x + (y.x - x.x) * t,
        x.y + (y.y - x.y) * t,
      ),
      (Color x, Color y) => Color.fromARGB(
        (x.alpha + (y.alpha - x.alpha) * t).round(),
        (x.red + (y.red - x.red) * t).round(),
        (x.green + (y.green - x.green) * t).round(),
        (x.blue + (y.blue - x.blue) * t).round(),
      ),
      _ => t < 0.5 ? a : b,
    };
    return value as T;
  }

  @override
  T transform(double t) {
    if (t == 0.0) return begin as T;
    if (t == 1.0) return end as T;
    return lerp(t);
  }
}

/// A [Tween] of colours.
class ColorTween extends Tween<Color?> {
  ColorTween({super.begin, super.end});
}

/// A [Tween] of sizes.
class SizeTween extends Tween<Size?> {
  SizeTween({super.begin, super.end});
}

/// A [Tween] of whole numbers, rounded.
class IntTween extends Tween<int> {
  IntTween({super.begin, super.end});
  @override
  int lerp(double t) => (begin! + (end! - begin!) * t).round();
}

/// A [Tween] that stays at [value].
class ConstantTween<T> extends Tween<T> {
  ConstantTween(T value) : super(begin: value, end: value);
  @override
  T lerp(double t) => begin as T;
}

/// [curve]'s value at a point, as an [Animatable].
class CurveTween extends Animatable<double> {
  CurveTween({required this.curve});
  Curve curve;
  @override
  double transform(double t) => curve.transform(t);
}

/// [parent] along [curve], in Flutter.
class CurvedAnimation extends Animation<double> {
  CurvedAnimation({required this.parent, required this.curve, this.reverseCurve});
  final Animation<double> parent;
  Curve curve;
  Curve? reverseCurve;
  @override
  double get value {
    final reversing = parent.status == AnimationStatus.reverse;
    return (reversing ? reverseCurve ?? curve : curve).transform(parent.value);
  }

  @override
  AnimationStatus get status => parent.status;
  @override
  void addListener(VoidCallback listener) => parent.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      parent.removeListener(listener);
}

/// An animation that is always [value].
class AlwaysStoppedAnimation<T> extends Animation<T> {
  const AlwaysStoppedAnimation(this.value);
  @override
  final T value;
  @override
  AnimationStatus get status => AnimationStatus.forward;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _FixedAnimation extends Animation<double> {
  const _FixedAnimation(this.value, this.status);
  @override
  final double value;
  @override
  final AnimationStatus status;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// An animation that has finished: what a page's builder is handed.
const Animation<double> kAlwaysCompleteAnimation = _FixedAnimation(
  1,
  AnimationStatus.completed,
);

/// An animation that never started.
const Animation<double> kAlwaysDismissedAnimation = _FixedAnimation(
  0,
  AnimationStatus.dismissed,
);

/// How long after a tree that shows where something starts the tree that
/// moves it is built: long enough to be a tree of its own, which a renderer
/// does not take together with the one before.
const _nextTree = Duration(milliseconds: 40);

/// Whether an animation that is done takes its time, when the platform asks
/// for less motion. Accepted; a run here always takes its time.
enum AnimationBehavior { normal, preserve }

/// A run of an [AnimationController] from one value to another.
class _ControllerRun {
  _ControllerRun(this.from, this.to, this.duration, this.curve, this.startPass);
  final double from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// The build it was started in, if it was started in one: that build
  /// shows where it starts, and the next where it ends.
  final int? startPass;
  final Stopwatch clock = Stopwatch()..start();
  final TickerFuture future = TickerFuture._();
  Timer? timer;

  double get along => duration == Duration.zero
      ? 1
      : (clock.elapsedMicroseconds / duration.inMicroseconds)
            .clamp(0.0, 1.0)
            .toDouble();
}

/// A value that runs between [lowerBound] and [upperBound] over [duration],
/// in Flutter: what an explicit animation - a shake, a pulse, a staggered
/// entrance, a ring that eases - is driven by, through the transitions
/// ([FadeTransition], [ScaleTransition], [RotationTransition],
/// [SlideTransition], [SizeTransition]) or an [AnimatedBuilder].
///
/// ```dart
/// late final _controller = AnimationController(
///   vsync: this,
///   duration: const Duration(seconds: 1),
/// )..repeat(reverse: true);
///
/// FadeTransition(opacity: _controller, child: const Text('Listening'))
/// ```
///
/// What differs: nothing here ticks. A run - [forward], [reverse],
/// [animateTo], each lap of [repeat] - is one build at the value it ends at,
/// carrying the run's length and curve, and the renderer moves the screen
/// there. So listeners and status listeners hear a run start and end, not
/// each frame; [value] read outside a build is where the run is by the clock.
/// Inside an [AnimatedBuilder] the boxes built - an [Opacity], a
/// [Transform], a [Container]'s size or colour - move over the run; what has
/// no box to move, a [Text]'s words or a [CustomPaint]'s picture, is drawn at
/// the end. A run started while the screen is being built - from `initState`
/// - is drawn at its start first, so an entrance is seen.
class AnimationController extends Animation<double> {
  AnimationController({
    double? value,
    this.duration,
    this.reverseDuration,
    this.debugLabel,
    this.lowerBound = 0.0,
    this.upperBound = 1.0,
    this.animationBehavior = AnimationBehavior.normal,
    required TickerProvider vsync,
  }) : _value = (value ?? lowerBound).clamp(lowerBound, upperBound).toDouble() {
    _status = _value == upperBound
        ? AnimationStatus.completed
        : AnimationStatus.dismissed;
  }

  /// A controller with no bounds, starting at [value].
  AnimationController.unbounded({
    double value = 0.0,
    this.duration,
    this.reverseDuration,
    this.debugLabel,
    required TickerProvider vsync,
    this.animationBehavior = AnimationBehavior.preserve,
  }) : lowerBound = double.negativeInfinity,
       upperBound = double.infinity,
       _value = value,
       _status = AnimationStatus.forward;

  Duration? duration;
  Duration? reverseDuration;
  final String? debugLabel;
  final double lowerBound;
  final double upperBound;
  final AnimationBehavior animationBehavior;

  double _value;
  late AnimationStatus _status;
  _ControllerRun? _run;

  /// Set while [repeat] goes on: the laps it has left, null for ever.
  ({double min, double max, bool reverse, Duration period, int? left})? _laps;

  final List<VoidCallback> _listeners = [];
  final List<void Function(AnimationStatus)> _statusListeners = [];
  bool _disposed = false;

  /// The run under way, if any.
  _ControllerRun? get _running => _run;

  /// Where it is: inside a build, where the run under way ends - or starts,
  /// in the build it was started in - and elsewhere where it is by the clock.
  @override
  double get value {
    final run = _run;
    if (run == null) return _value;
    final owner = _Owner._current;
    if (owner != null && owner._building) {
      return run.startPass == owner._pass ? run.from : run.to;
    }
    return run.from + (run.to - run.from) * run.curve.transform(run.along);
  }

  /// Stops and goes to [newValue] at once.
  set value(double newValue) {
    _stopRun();
    _laps = null;
    _value = newValue.clamp(lowerBound, upperBound).toDouble();
    _settleStatus();
    _notify();
  }

  @override
  AnimationStatus get status => _status;

  bool get isAnimating => _run != null;

  /// How fast it moves, in units a second; zero at rest.
  double get velocity {
    final run = _run;
    if (run == null || run.duration == Duration.zero) return 0;
    return (run.to - run.from) / (run.duration.inMicroseconds / 1e6);
  }

  /// Cannot be made to run off another clock here; accepted.
  void resync(TickerProvider vsync) {}

  /// Runs to [upperBound], from [from] if given.
  TickerFuture forward({double? from}) {
    if (from != null) _value = from;
    _laps = null;
    return _animate(upperBound, null, Curves.linear, AnimationStatus.forward);
  }

  /// Runs to [lowerBound], from [from] if given.
  TickerFuture reverse({double? from}) {
    if (from != null) _value = from;
    _laps = null;
    return _animate(lowerBound, null, Curves.linear, AnimationStatus.reverse);
  }

  /// Runs to [target], over [duration] if given and along [curve].
  TickerFuture animateTo(
    double target, {
    Duration? duration,
    Curve curve = Curves.linear,
  }) {
    _laps = null;
    return _animate(target, duration, curve, AnimationStatus.forward);
  }

  /// Runs back to [target], as a reverse run.
  TickerFuture animateBack(
    double target, {
    Duration? duration,
    Curve curve = Curves.linear,
  }) {
    _laps = null;
    return _animate(target, duration, curve, AnimationStatus.reverse);
  }

  /// Runs from [min] to [max] again and again - back and forth with
  /// [reverse] - [count] times, or until stopped. Each lap is a run of its
  /// own; without [reverse] the value goes straight back to [min] between
  /// them, which is not animated.
  TickerFuture repeat({
    double? min,
    double? max,
    bool reverse = false,
    Duration? period,
    int? count,
  }) {
    final lo = min ?? lowerBound;
    final hi = max ?? upperBound;
    final lap = period ?? duration;
    assert(lap != null, 'An AnimationController needs a duration to repeat.');
    _stopRun();
    _laps = (
      min: lo,
      max: hi,
      reverse: reverse,
      period: lap ?? Duration.zero,
      left: count,
    );
    final future = TickerFuture._();
    _nextLap(future);
    return future;
  }

  /// Flung with [velocity]: runs to the bound it points at, as fast as a
  /// spring would be most of the way there.
  TickerFuture fling({double velocity = 1.0}) {
    _laps = null;
    final target = velocity < 0 ? lowerBound : upperBound;
    final time = Duration(
      microseconds: (300000 / velocity.abs().clamp(0.5, 10.0)).round(),
    );
    return _animate(
      target,
      time,
      Curves.easeOut,
      velocity < 0 ? AnimationStatus.reverse : AnimationStatus.forward,
    );
  }

  /// Stops where it is.
  void stop({bool canceled = true}) {
    final run = _run;
    if (run == null && _laps == null) return;
    _laps = null;
    if (run != null) _value = value;
    _stopRun();
    _notify();
  }

  /// Back to [lowerBound], stopped.
  void reset() => value = lowerBound;

  void dispose() {
    _stopRun();
    _laps = null;
    _disposed = true;
    _listeners.clear();
    _statusListeners.clear();
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
  void addStatusListener(void Function(AnimationStatus) listener) =>
      _statusListeners.add(listener);
  void removeStatusListener(void Function(AnimationStatus) listener) =>
      _statusListeners.remove(listener);

  void _notify() {
    if (_disposed) return;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _setStatus(AnimationStatus status) {
    if (_status == status || _disposed) return;
    _status = status;
    for (final listener in List.of(_statusListeners)) {
      listener(status);
    }
  }

  void _settleStatus() => _setStatus(
    _value == upperBound
        ? AnimationStatus.completed
        : _value == lowerBound
        ? AnimationStatus.dismissed
        : (_status == AnimationStatus.reverse
              ? AnimationStatus.reverse
              : AnimationStatus.forward),
  );

  void _stopRun() {
    final run = _run;
    if (run == null) return;
    run.timer?.cancel();
    run.future._complete();
    _run = null;
  }

  TickerFuture _animate(
    double target,
    Duration? time,
    Curve curve,
    AnimationStatus status, {
    TickerFuture? future,
  }) {
    final from = _run == null ? _value : value;
    _stopRun();
    final to = target.clamp(lowerBound, upperBound).toDouble();
    // As Flutter does: the whole duration for the whole range, the part of it
    // for the part.
    final whole = time ??
        (status == AnimationStatus.reverse
            ? reverseDuration ?? duration
            : duration);
    assert(whole != null, 'An AnimationController needs a duration to run.');
    final range = upperBound - lowerBound;
    final part = time != null || !range.isFinite || range == 0
        ? 1.0
        : ((to - from).abs() / range).clamp(0.0, 1.0);
    final length = Duration(
      microseconds: ((whole ?? Duration.zero).inMicroseconds * part).round(),
    );
    _value = from;
    final owner = _Owner._current;
    final pass = owner != null && owner._building ? owner._pass : null;
    final run = _run = _ControllerRun(from, to, length, curve, pass);
    final done = future ?? run.future;
    _setStatus(status);
    if (length == Duration.zero || from == to) {
      _finish(run, done);
      return done;
    }
    run.timer = Timer(length, () => _finish(run, done));
    if (pass != null) {
      // Started inside a build, which shows where it starts: the next one
      // shows where it goes.
      Timer(_nextTree, _notify);
    } else {
      _notify();
    }
    return done;
  }

  void _finish(_ControllerRun run, TickerFuture future) {
    if (!identical(_run, run)) return;
    _run = null;
    _value = run.to;
    if (_laps != null) {
      _notify();
      _nextLap(future);
      return;
    }
    _settleStatus();
    run.future._complete();
    future._complete();
    _notify();
  }

  /// Starts the next lap of [repeat], or finishes it.
  void _nextLap(TickerFuture future) {
    final laps = _laps;
    if (laps == null || _disposed) return;
    if (laps.left == 0) {
      _laps = null;
      _settleStatus();
      future._complete();
      _notify();
      return;
    }
    _laps = (
      min: laps.min,
      max: laps.max,
      reverse: laps.reverse,
      period: laps.period,
      left: laps.left == null ? null : laps.left! - 1,
    );
    final back = laps.reverse && (_value - laps.max).abs() < 1e-9;
    if (!laps.reverse && (_value - laps.max).abs() < 1e-9) {
      // Straight back to the start, shown, and then the lap.
      _value = laps.min;
      _notify();
      Timer(_nextTree, () {
        if (_laps != null && _run == null) _lap(laps, false, future);
      });
      return;
    }
    _lap(laps, back, future);
  }

  void _lap(
    ({double min, double max, bool reverse, Duration period, int? left}) laps,
    bool back,
    TickerFuture future,
  ) {
    final target = back ? laps.min : laps.max;
    final range = (laps.max - laps.min).abs();
    final part = range == 0 ? 1.0 : ((target - _value).abs() / range);
    _animate(
      target,
      Duration(microseconds: (laps.period.inMicroseconds * part).round()),
      Curves.linear,
      back ? AnimationStatus.reverse : AnimationStatus.forward,
      future: future,
    );
  }
}

/// The controller [animation] is driven by, along whatever it is made of,
/// while that is running.
AnimationController? _runningUnder(Animation<Object?> animation) =>
    switch (animation) {
      AnimationController() => animation._running == null ? null : animation,
      CurvedAnimation(:final parent) => _runningUnder(parent),
      ReverseAnimation(:final parent) => _runningUnder(parent),
      _AnimatedEvaluation(:final parent) => _runningUnder(parent),
      _ => null,
    };

/// Whether [animation] is driven by a controller at all.
bool _controlled(Animation<Object?> animation) => switch (animation) {
  AnimationController() => true,
  CurvedAnimation(:final parent) => _controlled(parent),
  ReverseAnimation(:final parent) => _controlled(parent),
  _AnimatedEvaluation(:final parent) => _controlled(parent),
  _ => false,
};

/// How long the run [animation] is part of takes, and along what curve -
/// the one the animation is curved by, else the run's own; null when it is
/// not running.
({Duration duration, Curve curve})? _runTime(Animation<Object?> animation) {
  final controller = _runningUnder(animation);
  final run = controller?._running;
  if (run == null) return null;
  // The build that shows where the run starts does not move.
  final owner = _Owner._current;
  if (owner != null && owner._building && run.startPass == owner._pass) {
    return (duration: Duration.zero, curve: Curves.linear);
  }
  final curve = _curveIn(animation);
  return (
    duration: run.duration,
    curve: curve ?? run.curve,
  );
}

/// Fades [child] whenever [opacity] changes - Flutter's `AnimatedOpacity`.
///
/// It works the way the rest of the framework does: the tree says what the
/// screen *is*, and a renderer animates the difference from what it was. A
/// first render sets the opacity; a later one that changes it fades over
/// [duration].
///
/// ```dart
/// AnimatedOpacity(
///   opacity: _visible ? 1 : 0,
///   duration: const Duration(milliseconds: 300),
///   child: const Text('Saved'),
/// )
/// ```
///
/// [onEnd] is called when the renderer says the move a build started has
/// finished - or, from a renderer that never says, a little after
/// [duration].
class AnimatedOpacity extends Widget {
  const AnimatedOpacity({
    super.key,
    this.child,
    required this.opacity,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });

  final double opacity;
  final Widget? child;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) => owner._animated(
    UIBuilder.animatedOpacity(
      opacity: opacity,
      duration: duration,
      curve: curve.name,
      child: _passOn(owner, this, child ?? const SizedBox.shrink()),
    ),
    opacity,
    duration,
    onEnd,
  );
}

/// A [Container] that moves to its new look instead of jumping there -
/// Flutter's `AnimatedContainer`.
///
/// A first render sets the box; a later one that changes it moves there over
/// [duration], along [curve]. What moves is what a renderer can move: size,
/// colour, opacity, the transform, padding, margin and where the child is
/// aligned.
///
/// ```dart
/// AnimatedContainer(
///   width: _open ? 300 : 80,
///   height: 80,
///   color: _open ? Colors.blue : Colors.grey,
///   duration: const Duration(milliseconds: 300),
///   curve: Curves.easeOut,
///   child: const Text('Tap'),
/// )
/// ```
///
/// [onEnd] is called when the renderer says the move a build started has
/// finished - or, from a renderer that never says, a little after
/// [duration].
class AnimatedContainer extends Widget {
  AnimatedContainer({
    super.key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    double? width,
    double? height,
    BoxConstraints? constraints,
    this.margin,
    this.transform,
    this.transformAlignment,
    this.child,
    this.clipBehavior = Clip.none,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  }) : constraints = (width != null || height != null)
           ? (constraints?.tighten(width: width, height: height) ??
                 BoxConstraints.tightFor(width: width, height: height))
           : constraints;

  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final Widget? child;
  final Clip clipBehavior;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) {
    final node = _box(
      owner,
      child: child,
      constraints: constraints,
      padding: padding,
      margin: margin,
      alignment: alignment,
      color: color,
      decoration: decoration,
      foregroundDecoration: foregroundDecoration,
      transform: transform,
      transformAlignment: transformAlignment,
      clip: clipBehavior != Clip.none,
      fillWhenEmpty: true,
      animateMs: duration.inMilliseconds,
      curve: curve.name,
      id: _idOf(key),
    );
    // Everything the box was told to be, which is everything it can move to.
    return owner._animated(node, node.props.toString(), duration, onEnd);
  }
}

/// Grows or shrinks its child to [scale], over [duration].
class AnimatedScale extends Widget {
  const AnimatedScale({
    super.key,
    this.child,
    required this.scale,
    this.alignment = Alignment.center,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });
  final Widget? child;
  final double scale;

  /// Accepted and not consulted: a box scales about its centre.
  final Alignment alignment;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) => owner._animated(
    UIBuilder.box(
      transform: {'scale': scale},
      animateMs: duration.inMilliseconds,
      curve: curve.name,
      id: _idOf(key),
      child: child == null ? null : _passOn(owner, this, child!),
    ),
    scale,
    duration,
    onEnd,
  );
}

/// Turns its child to [turns] - whole turns, so 0.25 is a quarter - over
/// [duration].
class AnimatedRotation extends Widget {
  const AnimatedRotation({
    super.key,
    this.child,
    required this.turns,
    this.alignment = Alignment.center,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });
  final Widget? child;
  final double turns;
  final Alignment alignment;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) => owner._animated(
    UIBuilder.box(
      transform: {'rotate': turns * 2 * math.pi},
      animateMs: duration.inMilliseconds,
      curve: curve.name,
      id: _idOf(key),
      child: child == null ? null : _passOn(owner, this, child!),
    ),
    turns,
    duration,
    onEnd,
  );
}

/// Slides its child by [offset], which is in multiples of the child's own
/// size: `Offset(1, 0)` is one whole width to the right.
///
/// The protocol moves a box by pixels, so the child's size has to be known
/// first: it is drawn in place, the renderer reports its size, and from then
/// on it sits where [offset] says and slides when that changes.
class AnimatedSlide extends StatefulWidget {
  const AnimatedSlide({
    super.key,
    this.child,
    required this.offset,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });
  final Widget? child;
  final Offset offset;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  State<AnimatedSlide> createState() => _AnimatedSlideState();
}

class _AnimatedSlideState extends State<AnimatedSlide> {
  Size? _size;

  /// The offset it first stood at, before its size was known - out of sight
  /// until then if that is not its place, and drawn there once measured, so
  /// that a slide in from the side (an entrance) is seen.
  Offset? _unplaced;

  /// Where it is held, once measured, until the tree that slides it from
  /// there: any build before then - its size settling, say - draws it there
  /// too, rather than at the end in the same tree.
  Offset? _held;

  void _report(double width, double height) {
    final old = _size;
    if (old != null &&
        (old.width - width).abs() < 0.5 &&
        (old.height - height).abs() < 0.5) {
      return;
    }
    if (!mounted) return;
    setState(() => _size = Size(width, height));
  }

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    final size = _size;
    final child = widget.child;
    var offset = widget.offset;
    var ms = widget.duration.inMilliseconds;
    if (size == null) {
      _unplaced ??= widget.offset;
    } else if (_unplaced case final from?) {
      _unplaced = null;
      if (from != widget.offset) {
        // Where it started, at once; where it goes, a little after - in a
        // tree of its own, not one the renderer takes with the first.
        _held = from;
        Timer(_nextTree, () {
          if (mounted) setState(() => _held = null);
        });
      }
    }
    if (_held case final from?) {
      offset = from;
      ms = 0;
    }
    final hidden = size == null && _unplaced != Offset.zero;
    return owner._animated(
      UIBuilder.box(
        transform: size == null
            ? null
            : {
                'dx': offset.dx * size.width,
                'dy': offset.dy * size.height,
              },
        opacity: hidden ? 0 : null,
        onSize: _report,
        animateMs: ms,
        curve: widget.curve.name,
        id: _idOf(widget.key),
        child: child == null ? null : _passOn(owner, owner._node!, child),
      ),
      // The offset asked for, not the pixels it comes to: learning the
      // child's size is not the slide moving.
      widget.offset,
      widget.duration,
      widget.onEnd,
    );
  });
}

/// A [Padding] that moves to its new insets over [duration] - Flutter's
/// `AnimatedPadding`.
class AnimatedPadding extends Widget {
  const AnimatedPadding({
    super.key,
    required this.padding,
    this.child,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) {
    final insets = padding._resolved._ltrb;
    return owner._animated(
      UIBuilder.box(
        padding: insets,
        animateMs: duration.inMilliseconds,
        curve: curve.name,
        id: _idOf(key),
        child: child == null ? null : _passOn(owner, this, child!),
      ),
      insets.toString(),
      duration,
      onEnd,
    );
  }
}

/// An [Align] whose child slides to its new place over [duration] -
/// Flutter's `AnimatedAlign`.
class AnimatedAlign extends Widget {
  const AnimatedAlign({
    super.key,
    required this.alignment,
    this.child,
    this.heightFactor,
    this.widthFactor,
    this.curve = Curves.linear,
    required this.duration,
    this.onEnd,
  });
  final AlignmentGeometry alignment;
  final Widget? child;
  final double? heightFactor;
  final double? widthFactor;
  final Curve curve;
  final Duration duration;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) {
    final at = alignment._resolved._xy;
    return owner._animated(
      UIBuilder.box(
        alignment: at,
        expand: owner._expandBounded,
        animateMs: duration.inMilliseconds,
        curve: curve.name,
        id: _idOf(key),
        child: child == null ? null : _renderChild(owner, child!),
      ),
      at.toString(),
      duration,
      onEnd,
    );
  }
}

/// Builds the transition between an [AnimatedSwitcher]'s children.
typedef AnimatedSwitcherTransitionBuilder =
    Widget Function(Widget child, Animation<double> animation);

/// Fades from the old child to the new one - Flutter's `AnimatedSwitcher`.
///
/// A child is new when its type or its key is not the last one's, as in
/// Flutter: two `Text`s are the same child unless they are given different
/// keys. The old child stays, drawn under the new one and deaf to touches,
/// and fades out over [reverseDuration] while the new one fades in over
/// [duration].
///
/// ```dart
/// AnimatedSwitcher(
///   duration: const Duration(milliseconds: 300),
///   child: Text('$count', key: ValueKey(count)),
/// )
/// ```
///
/// The transition is a fade unless a [transitionBuilder] says otherwise. It
/// is called with the animation standing at its start and then at its end,
/// and the [FadeTransition]s, [ScaleTransition]s, [SlideTransition]s,
/// [RotationTransition]s and [SizeTransition]s in what it returns move
/// from the one to the other - a [Tween] or a [CurvedAnimation] between
/// them is evaluated at both ends. Anything else in it is drawn as it is at
/// the end. A [layoutBuilder] is accepted and not called - the children are
/// stacked about their centres, which is Flutter's default.
class AnimatedSwitcher extends StatelessWidget {
  const AnimatedSwitcher({
    super.key,
    this.child,
    required this.duration,
    this.reverseDuration,
    this.switchInCurve = Curves.linear,
    this.switchOutCurve = Curves.linear,
    this.transitionBuilder,
    this.layoutBuilder,
  });
  final Widget? child;
  final Duration duration;
  final Duration? reverseDuration;
  final Curve switchInCurve;
  final Curve switchOutCurve;
  final AnimatedSwitcherTransitionBuilder? transitionBuilder;
  final Widget Function(Widget? currentChild, List<Widget> previousChildren)?
  layoutBuilder;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    final builder = transitionBuilder;
    return _Switch(
      // What makes a child a new one: Flutter's `Widget.canUpdate`.
      identity: child == null ? null : (child.runtimeType, child.key),
      duration: duration,
      reverseDuration: reverseDuration ?? duration,
      inCurve: switchInCurve,
      outCurve: switchOutCurve,
      alignment: Alignment.center,
      transition: builder,
      child: child,
    );
  }
}

/// A child that is leaving a [_Switch].
class _Leaving {
  _Leaving(this.serial, this.child);
  final int serial;
  final Widget? child;
  Timer? timer;
}

/// One child at a time, each fading in over the one before it.
class _Switch extends StatefulWidget {
  const _Switch({
    required this.identity,
    required this.child,
    required this.duration,
    required this.reverseDuration,
    required this.inCurve,
    required this.outCurve,
    required this.alignment,
    this.leavingOver = false,
    this.transition,
  });
  final Object? identity;
  final Widget? child;
  final Duration duration;
  final Duration reverseDuration;
  final Curve inCurve;
  final Curve outCurve;
  final AlignmentGeometry alignment;

  /// Whether a child that is leaving is laid over the stack rather than in
  /// it, so the stack is the size of the child coming in alone.
  final bool leavingOver;

  /// How a child comes and goes, when not by a fade: built at the
  /// animation's start and then at its end (see [AnimatedSwitcher]).
  final AnimatedSwitcherTransitionBuilder? transition;

  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  int _serial = 0;
  final List<_Leaving> _leaving = [];

  /// Whether the child showing came in after another, and so fades in.
  bool _entered = false;

  @override
  void didUpdateWidget(_Switch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    final gone = _Leaving(_serial, oldWidget.child);
    _serial++;
    _entered = true;
    if (widget.reverseDuration <= Duration.zero) return;
    _leaving.add(gone);
    gone.timer = Timer(widget.reverseDuration, () {
      _leaving.remove(gone);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final gone in _leaving) {
      gone.timer?.cancel();
    }
    super.dispose();
  }

  Widget _gone(_Leaving gone) {
    final fading = KeyedSubtree(
      key: _keyOf(gone.serial),
      child: IgnorePointer(
        child: _moving(
          from: 1,
          to: 0,
          duration: widget.reverseDuration,
          curve: widget.outCurve,
          child: gone.child ?? const SizedBox.shrink(),
        ),
      ),
    );
    return widget.leavingOver
        ? Positioned(left: 0, top: 0, right: 0, child: fading)
        : fading;
  }

  /// [child] on its way from [from] to [to]: faded, or moved by the
  /// switch's transition.
  Widget _moving({
    required double from,
    required double to,
    required Duration duration,
    required Curve curve,
    required Widget child,
  }) {
    final transition = widget.transition;
    if (transition == null) {
      return _FadeTo(
        from: from,
        to: to,
        duration: duration,
        curve: curve,
        child: child,
      );
    }
    return _Transitioning(
      from: from,
      to: to,
      duration: duration,
      curve: curve,
      transition: transition,
      child: child,
    );
  }

  // A key of its own for each child that has been here, so a child's state
  // stays with it while the ones around it come and go.
  Key _keyOf(int serial) => ValueKey('switch-${identityHashCode(this)}-$serial');

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    final current = KeyedSubtree(
      key: _keyOf(_serial),
      child: _entered && widget.duration > Duration.zero
          ? _moving(
              from: 0,
              to: 1,
              duration: widget.duration,
              curve: widget.inCurve,
              child: child,
            )
          : (widget.transition?.call(child, kAlwaysCompleteAnimation) ??
                child),
    );
    if (_leaving.isEmpty) return current;
    return Stack(
      alignment: widget.alignment,
      children: [
        for (final gone in _leaving) _gone(gone),
        current,
      ],
    );
  }
}

/// [child] as [transition] builds it with the animation at [from], then at
/// [to] - the transition widgets in it moving from the one to the other.
class _Transitioning extends StatefulWidget {
  const _Transitioning({
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
    required this.transition,
    required this.child,
  });
  final double from;
  final double to;
  final Duration duration;
  final Curve curve;
  final AnimatedSwitcherTransitionBuilder transition;
  final Widget child;

  @override
  State<_Transitioning> createState() => _TransitioningState();
}

class _TransitioningState extends State<_Transitioning> {
  late double _at = widget.from;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_FadeToState._settle, () {
      if (mounted) setState(() => _at = widget.to);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _at == widget.to
        ? (widget.to >= widget.from
              ? AnimationStatus.completed
              : AnimationStatus.dismissed)
        : (widget.to >= widget.from
              ? AnimationStatus.forward
              : AnimationStatus.reverse);
    return _TransitionTime(
      duration: widget.duration,
      curve: widget.curve,
      child: widget.transition(widget.child, _FixedAnimation(_at, status)),
    );
  }
}

/// Draws [child] at [from], then fades it to [to].
///
/// A renderer animates the difference between two trees, so there have to be
/// two: the first says where the fade starts, and one a moment later says
/// where it ends.
class _FadeTo extends StatefulWidget {
  const _FadeTo({
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
    required this.child,
  });
  final double from;
  final double to;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_FadeTo> createState() => _FadeToState();
}

class _FadeToState extends State<_FadeTo> {
  // Long enough for a renderer to have drawn the start: a browser that is
  // handed both ends in one frame shows only the last.
  static const _settle = Duration(milliseconds: 32);

  late double _opacity = widget.from;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_settle, () {
      if (mounted) setState(() => _opacity = widget.to);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _opacity,
    duration: widget.duration,
    curve: widget.curve,
    child: widget.child,
  );
}

/// Moves to the size its child comes to - Flutter's `AnimatedSize`.
///
/// When the child grows or shrinks, the box goes from the size it was to the
/// new one over [duration], the child placed at [alignment] inside it and
/// clipped to it on the way unless [clipBehavior] is [Clip.none]. The
/// renderer does the moving, since only it knows how big the child came
/// out; a child that changes size between renders - a picture arriving - is
/// not moved to. [onEnd] is called when a move has got there, as the
/// renderer says. [reverseDuration] is accepted and not carried.
class AnimatedSize extends Widget {
  const AnimatedSize({
    super.key,
    this.child,
    this.alignment = Alignment.center,
    this.curve = Curves.linear,
    required this.duration,
    this.reverseDuration,
    this.clipBehavior = Clip.hardEdge,
    this.onEnd,
  });
  final Widget? child;
  final AlignmentGeometry alignment;
  final Curve curve;
  final Duration duration;
  final Duration? reverseDuration;
  final Clip clipBehavior;
  final VoidCallback? onEnd;

  @override
  WidgetNode _render(_Owner owner) => _sizing(
    owner,
    child: owner.inSlot('child', () => _renderChild(
      owner,
      child ?? const SizedBox.shrink(),
    )),
    alignment: alignment,
    duration: duration,
    curve: curve,
    clip: clipBehavior != Clip.none,
    onEnd: onEnd,
    id: _idOf(key),
  );
}

/// A box that hugs [child] and moves to its new size when the child's
/// changes - what [AnimatedSize] and [AnimatedCrossFade] are drawn with.
WidgetNode _sizing(
  _Owner owner, {
  required WidgetNode child,
  required AlignmentGeometry alignment,
  required Duration duration,
  required Curve curve,
  bool clip = true,
  VoidCallback? onEnd,
  String? id,
}) => UIBuilder.box(
  alignment: alignment._resolved._xy,
  clip: clip,
  animateSize: duration > Duration.zero,
  onSizeEnd: onEnd,
  animateMs: duration > Duration.zero ? duration.inMilliseconds : null,
  curve: curve.name,
  id: id,
  child: child,
);

/// Which child an [AnimatedCrossFade] shows.
enum CrossFadeState { showFirst, showSecond }

/// Fades between two children - Flutter's `AnimatedCrossFade`.
///
/// The child [crossFadeState] names is shown; when it changes, the other
/// fades out under it as it fades in, over [duration], while the space moves
/// from the size of the one going to the size of the one coming, along
/// [sizeCurve] - the one going laid over it at the top, as wide as it, and
/// clipped to it. A child that is not showing is not built, so it starts
/// again when it comes back.
class AnimatedCrossFade extends StatelessWidget {
  const AnimatedCrossFade({
    super.key,
    required this.firstChild,
    required this.secondChild,
    this.firstCurve = Curves.linear,
    this.secondCurve = Curves.linear,
    this.sizeCurve = Curves.linear,
    this.alignment = Alignment.topCenter,
    required this.crossFadeState,
    required this.duration,
    this.reverseDuration,
  });
  final Widget firstChild;
  final Widget secondChild;
  final Curve firstCurve;
  final Curve secondCurve;
  final Curve sizeCurve;
  final AlignmentGeometry alignment;
  final CrossFadeState crossFadeState;
  final Duration duration;
  final Duration? reverseDuration;

  @override
  Widget build(BuildContext context) {
    final first = crossFadeState == CrossFadeState.showFirst;
    // Flutter runs one animation forwards to the second child and back to
    // the first, so the reverse duration is the way back.
    final time = first ? (reverseDuration ?? duration) : duration;
    return _SizeBox(
      alignment: alignment,
      duration: time,
      curve: sizeCurve,
      child: _Switch(
        identity: crossFadeState,
        duration: time,
        reverseDuration: time,
        inCurve: first ? firstCurve : secondCurve,
        outCurve: first ? secondCurve : firstCurve,
        alignment: alignment,
        leavingOver: true,
        child: first ? firstChild : secondChild,
      ),
    );
  }
}

/// [child] in a box that moves to the child's new size - see [_sizing].
class _SizeBox extends Widget {
  const _SizeBox({
    required this.alignment,
    required this.duration,
    required this.curve,
    required this.child,
  });
  final AlignmentGeometry alignment;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) => _sizing(
    owner,
    child: _renderChild(owner, child),
    alignment: alignment,
    duration: duration,
    curve: curve,
  );
}
