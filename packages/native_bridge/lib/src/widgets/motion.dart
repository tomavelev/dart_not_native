part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Motion.
//
// The tree says what the screen *is*, and a renderer animates the difference
// from what it was. So the animated widgets here are the plain ones with a
// duration attached, and there is no AnimationController: the frames happen
// on the far side of the channel.
// ---------------------------------------------------------------------------

/// How an animation is paced over its duration.
///
/// The protocol carries five paces, because every renderer already has those
/// five and no more: a CSS timing function, an Android `Interpolator`, a UIKit
/// animation option. Every curve Flutter names is here, and each travels as
/// the nearest of the five - `Curves.elasticOut` is `easeOut` by the time a
/// renderer sees it, which keeps the code compiling and the motion honest
/// about where it goes, if not about the overshoot on the way.
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

/// A cubic Bézier curve through (0,0), ([a],[b]), ([c],[d]) and (1,1).
/// [transform] is exact; a renderer is handed the nearest of the five paces.
class Cubic extends Curve {
  const Cubic(this.a, this.b, this.c, this.d) : super('easeInOut');
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

  static const Curve decelerate = easeOut;
  static const Curve fastLinearToSlowEaseIn = easeOut;
  static const Curve fastOutSlowIn = easeInOut;
  static const Curve slowMiddle = ease;
  static const Curve fastEaseInToSlowEaseOut = easeInOut;
  static const Curve linearToEaseOut = easeOut;
  static const Curve easeInToLinear = easeIn;

  static const Curve easeInSine = easeIn;
  static const Curve easeInQuad = easeIn;
  static const Curve easeInCubic = easeIn;
  static const Curve easeInQuart = easeIn;
  static const Curve easeInQuint = easeIn;
  static const Curve easeInExpo = easeIn;
  static const Curve easeInCirc = easeIn;
  static const Curve easeInBack = easeIn;

  static const Curve easeOutSine = easeOut;
  static const Curve easeOutQuad = easeOut;
  static const Curve easeOutCubic = easeOut;
  static const Curve easeOutQuart = easeOut;
  static const Curve easeOutQuint = easeOut;
  static const Curve easeOutExpo = easeOut;
  static const Curve easeOutCirc = easeOut;
  static const Curve easeOutBack = easeOut;

  static const Curve easeInOutSine = easeInOut;
  static const Curve easeInOutQuad = easeInOut;
  static const Curve easeInOutCubic = easeInOut;
  static const Curve easeInOutCubicEmphasized = easeInOut;
  static const Curve easeInOutQuart = easeInOut;
  static const Curve easeInOutQuint = easeInOut;
  static const Curve easeInOutExpo = easeInOut;
  static const Curve easeInOutCirc = easeInOut;
  static const Curve easeInOutBack = easeInOut;

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

/// A value that changes over time, in Flutter. Nothing here animates in Dart,
/// so the only animations there are stand still: the class exists for the
/// signatures that name it - a progress indicator's `valueColor`, a page
/// route's builder.
abstract class Animation<T> extends Listenable {
  const Animation();
  T get value;
  AnimationStatus get status;
  bool get isCompleted => status == AnimationStatus.completed;
  bool get isDismissed => status == AnimationStatus.dismissed;
}

/// A child at the opacity an [Animation] says, in Flutter.
///
/// An animation here stands still (see [Animation]), so the child is drawn at
/// the value it has when the widget is built - which, for the animation a
/// page route hands its `buildTransitions`, is fully shown.
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
    final value = opacity.value.clamp(0.0, 1.0).toDouble();
    final child = this.child ?? const SizedBox.shrink();
    return value >= 1 ? child : Opacity(opacity: value, child: child);
  }
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
/// [onEnd] is accepted and never called: the renderer does not report an
/// animation finishing.
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
  WidgetNode _render(_Owner owner) => UIBuilder.animatedOpacity(
    opacity: opacity,
    duration: duration,
    curve: curve.name,
    child: _renderChild(owner, child ?? const SizedBox.shrink()),
  );
}

/// A [Container] that moves to its new look instead of jumping there -
/// Flutter's `AnimatedContainer`.
///
/// A first render sets the box; a later one that changes it moves there over
/// [duration], along [curve]. What moves is what a renderer can move: size,
/// colour, opacity and the transform. A change to padding, margin, alignment
/// or a border lands at once.
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
/// [onEnd] is accepted and never called: the renderer does not report an
/// animation finishing.
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
  WidgetNode _render(_Owner owner) => _box(
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
    clip: clipBehavior != Clip.none,
    fillWhenEmpty: true,
    animateMs: duration.inMilliseconds,
    curve: curve.name,
    id: _idOf(key),
  );
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
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    transform: {'scale': scale},
    animateMs: duration.inMilliseconds,
    curve: curve.name,
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
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
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    transform: {'rotate': turns * 2 * math.pi},
    animateMs: duration.inMilliseconds,
    curve: curve.name,
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
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
    return UIBuilder.box(
      transform: size == null
          ? null
          : {
              'dx': widget.offset.dx * size.width,
              'dy': widget.offset.dy * size.height,
            },
      onSize: _report,
      animateMs: widget.duration.inMilliseconds,
      curve: widget.curve.name,
      id: _idOf(widget.key),
      child: child == null ? null : _renderChild(owner, child),
    );
  });
}

/// A [Padding] with a duration. The protocol does not animate insets, so the
/// new padding lands at once; the widget is here so the code that uses it
/// reads the same.
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
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    padding: padding._resolved._ltrb,
    animateMs: duration.inMilliseconds,
    curve: curve.name,
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
  );
}

/// An [Align] with a duration. The protocol does not animate an alignment, so
/// the child lands in its new place at once.
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
  WidgetNode _render(_Owner owner) => UIBuilder.box(
    alignment: alignment._resolved._xy,
    expand: owner._expandBounded,
    animateMs: duration.inMilliseconds,
    curve: curve.name,
    id: _idOf(key),
    child: child == null ? null : _renderChild(owner, child!),
  );
}

/// Builds the transition between an [AnimatedSwitcher]'s children.
typedef AnimatedSwitcherTransitionBuilder =
    Widget Function(Widget child, Animation<double> animation);

/// Flutter cross-fades from the old child to the new one. Here the new child
/// is simply shown: one tree replaces another, and a renderer has no old
/// child left to fade from.
class AnimatedSwitcher extends Widget {
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
  WidgetNode _render(_Owner owner) =>
      _renderChild(owner, child ?? const SizedBox.shrink());
}

/// Flutter animates its own size as its child's changes. Here the child is
/// shown at its new size at once.
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
  WidgetNode _render(_Owner owner) =>
      _renderChild(owner, child ?? const SizedBox.shrink());
}

/// Which child an [AnimatedCrossFade] shows.
enum CrossFadeState { showFirst, showSecond }

/// Flutter fades between two children. Here the one chosen is shown, without
/// the fade.
class AnimatedCrossFade extends Widget {
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
  WidgetNode _render(_Owner owner) => crossFadeState == CrossFadeState.showFirst
      ? _renderChild(owner, firstChild, 'first')
      : _renderChild(owner, secondChild, 'second')
;
}
