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
      child: _renderChild(owner, child ?? const SizedBox.shrink()),
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
      child: child == null ? null : _renderChild(owner, child!),
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
      child: child == null ? null : _renderChild(owner, child!),
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
    return owner._animated(
      UIBuilder.box(
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
        child: child == null ? null : _renderChild(owner, child!),
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
/// The transition is the fade. A [transitionBuilder] is called, with an
/// animation that has finished (see [Animation]), and what it returns is
/// what fades; a [layoutBuilder] is accepted and not called - the children
/// are stacked about their centres, which is Flutter's default.
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
      child: child == null
          ? null
          : builder == null
          ? child
          : builder(child, kAlwaysCompleteAnimation),
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
        child: _FadeTo(
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

  // A key of its own for each child that has been here, so a child's state
  // stays with it while the ones around it come and go.
  Key _keyOf(int serial) => ValueKey('switch-${identityHashCode(this)}-$serial');

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    final current = KeyedSubtree(
      key: _keyOf(_serial),
      child: _entered && widget.duration > Duration.zero
          ? _FadeTo(
              from: 0,
              to: 1,
              duration: widget.duration,
              curve: widget.inCurve,
              child: child,
            )
          : child,
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
/// not moved to. [reverseDuration] is accepted and not carried, and
/// [onEnd] is not called.
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
  String? id,
}) => UIBuilder.box(
  alignment: alignment._resolved._xy,
  clip: clip,
  animateSize: duration > Duration.zero,
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
