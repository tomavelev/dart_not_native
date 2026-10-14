part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Gestures: taps and drags on a box, drag and drop between boxes, and a row
// that is swiped away.
// ---------------------------------------------------------------------------

/// Where a tap went down.
///
/// The renderers report the point in the box's own coordinates. The global
/// position is that same point: a box does not know where on the screen it
/// is, and the difference between two readings - which is what a drag uses a
/// global position for - is the same either way.
class TapDownDetails {
  const TapDownDetails({
    this.globalPosition = Offset.zero,
    Offset? localPosition,
  }) : localPosition = localPosition ?? globalPosition;
  final Offset globalPosition;
  final Offset localPosition;
}

/// Where a tap came up. See [TapDownDetails] for what the positions are.
class TapUpDetails {
  const TapUpDetails({
    this.globalPosition = Offset.zero,
    Offset? localPosition,
  }) : localPosition = localPosition ?? globalPosition;
  final Offset globalPosition;
  final Offset localPosition;
}

/// Where a drag began.
class DragStartDetails {
  const DragStartDetails({
    this.globalPosition = Offset.zero,
    Offset? localPosition,
  }) : localPosition = localPosition ?? globalPosition;
  final Offset globalPosition;
  final Offset localPosition;
}

/// How far a drag moved since the last update.
class DragUpdateDetails {
  const DragUpdateDetails({
    this.delta = Offset.zero,
    this.primaryDelta,
    required this.globalPosition,
    Offset? localPosition,
  }) : localPosition = localPosition ?? globalPosition;

  /// The movement since the last update.
  final Offset delta;

  /// For a drag along one axis, the movement along it; null for a pan.
  final double? primaryDelta;
  final Offset globalPosition;
  final Offset localPosition;
}

/// A speed, in logical pixels per second.
class Velocity {
  const Velocity({required this.pixelsPerSecond});
  static const Velocity zero = Velocity(pixelsPerSecond: Offset.zero);
  final Offset pixelsPerSecond;
}

/// How fast a drag was going when it was let go.
class DragEndDetails {
  const DragEndDetails({
    this.velocity = Velocity.zero,
    this.primaryVelocity,
    this.globalPosition = Offset.zero,
    Offset? localPosition,
  }) : localPosition = localPosition ?? globalPosition;
  final Velocity velocity;

  /// For a drag along one axis, the speed along it; null for a pan.
  final double? primaryVelocity;
  final Offset globalPosition;
  final Offset localPosition;
}

/// A [GestureDetector] hearing a scale whose one finger moves along
/// [axis] only, so that a movement the other way is the scroller's around
/// it - an [InteractiveViewer] that pans one way.
class _AxisScaleDetector extends GestureDetector {
  const _AxisScaleDetector({
    required this.axis,
    super.onScaleStart,
    super.onScaleUpdate,
    super.onScaleEnd,
    super.child,
  });
  final String? axis;

  @override
  String? get _scaleAxis => axis;
}

/// Where a scale - a pinch, or a pan, which is a scale of one - began.
class ScaleStartDetails {
  const ScaleStartDetails({
    this.focalPoint = Offset.zero,
    Offset? localFocalPoint,
    this.pointerCount = 1,
  }) : localFocalPoint = localFocalPoint ?? focalPoint;

  /// The point between the fingers.
  final Offset focalPoint;
  final Offset localFocalPoint;
  final int pointerCount;
}

/// How far a scale has gone: [scale] is the fingers' spread over what it was
/// when they came down, and [focalPointDelta] how far the point between them
/// moved since the last update.
class ScaleUpdateDetails {
  const ScaleUpdateDetails({
    this.focalPoint = Offset.zero,
    Offset? localFocalPoint,
    this.scale = 1.0,
    this.horizontalScale = 1.0,
    this.verticalScale = 1.0,
    this.rotation = 0.0,
    this.pointerCount = 1,
    this.focalPointDelta = Offset.zero,
  }) : localFocalPoint = localFocalPoint ?? focalPoint;
  final Offset focalPoint;
  final Offset localFocalPoint;
  final double scale;
  final double horizontalScale;
  final double verticalScale;

  /// Always zero: no renderer reports a turn.
  final double rotation;
  final int pointerCount;
  final Offset focalPointDelta;
}

/// How fast the point between the fingers was going when they lifted.
class ScaleEndDetails {
  const ScaleEndDetails({
    this.velocity = Velocity.zero,
    this.scaleVelocity = 0.0,
    this.pointerCount = 0,
  });
  final Velocity velocity;
  final double scaleVelocity;
  final int pointerCount;
}

typedef GestureScaleStartCallback = void Function(ScaleStartDetails details);
typedef GestureScaleUpdateCallback = void Function(ScaleUpdateDetails details);
typedef GestureScaleEndCallback = void Function(ScaleEndDetails details);

typedef GestureTapCallback = VoidCallback;
typedef GestureTapDownCallback = void Function(TapDownDetails details);
typedef GestureTapUpCallback = void Function(TapUpDetails details);
typedef GestureLongPressCallback = VoidCallback;
typedef GestureDragStartCallback = void Function(DragStartDetails details);
typedef GestureDragUpdateCallback = void Function(DragUpdateDetails details);
typedef GestureDragEndCallback = void Function(DragEndDetails details);

/// Hears taps and drags on its child: Flutter's `GestureDetector`.
///
/// A tap is reported once it has happened, so [onTapDown], [onTapUp] and
/// [onTap] fire together, in that order, with the point of the tap. The three
/// kinds of drag - a pan, a horizontal drag, a vertical drag - are all the one
/// drag the platform reports; each handler given is called, with the movement
/// along its axis as `primaryDelta`. [onScaleStart], [onScaleUpdate] and
/// [onScaleEnd] hear the same drag with a second finger's pinch in it: one
/// finger is a scale of one that moves its focal point, two spread or close
/// it. As in Flutter, a detector listens for a scale or a drag, not both:
/// with a scale handler, the drag handlers are not called. [behavior] is
/// accepted and not carried: a box takes the touches that land on it.
class GestureDetector extends Widget {
  const GestureDetector({
    super.key,
    this.child,
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.behavior,
    this.excludeFromSemantics = false,
  });
  final Widget? child;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCallback? onTap;

  /// Accepted and never called: a tap that did not happen is not reported.
  final VoidCallback? onTapCancel;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;
  final HitTestBehavior? behavior;
  final bool excludeFromSemantics;

  bool get _taps => onTap != null || onTapDown != null || onTapUp != null;

  bool get _scales =>
      onScaleStart != null || onScaleUpdate != null || onScaleEnd != null;

  /// The one axis a scale's single finger moves along, when it is held to
  /// one: none, for a detector the app made.
  String? get _scaleAxis => null;

  void _scale(String phase, Map<String, dynamic> data) {
    double n(String key, [double fallback = 0]) =>
        (data[key] as num?)?.toDouble() ?? fallback;
    final at = Offset(n('x'), n('y'));
    final fingers = (data['pointers'] as num?)?.toInt() ?? 1;
    switch (phase) {
      case 'start':
        onScaleStart?.call(
          ScaleStartDetails(
            focalPoint: at,
            localFocalPoint: at,
            pointerCount: fingers,
          ),
        );
      case 'update':
        final scale = n('scale', 1);
        onScaleUpdate?.call(
          ScaleUpdateDetails(
            focalPoint: at,
            localFocalPoint: at,
            scale: scale,
            horizontalScale: scale,
            verticalScale: scale,
            pointerCount: fingers,
            focalPointDelta: Offset(n('dx'), n('dy')),
          ),
        );
      case 'end':
        onScaleEnd?.call(
          ScaleEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(n('vx'), n('vy'))),
          ),
        );
    }
  }

  bool get _drags =>
      onPanStart != null ||
      onPanUpdate != null ||
      onPanEnd != null ||
      onHorizontalDragStart != null ||
      onHorizontalDragUpdate != null ||
      onHorizontalDragEnd != null ||
      onVerticalDragStart != null ||
      onVerticalDragUpdate != null ||
      onVerticalDragEnd != null;

  /// The one axis this detector drags along, when it listens for no other:
  /// a drag the other way is then the scroller's around it, as in Flutter.
  String? get _dragAxis {
    if (onPanStart != null || onPanUpdate != null || onPanEnd != null) {
      return null;
    }
    final horizontal =
        onHorizontalDragStart != null ||
        onHorizontalDragUpdate != null ||
        onHorizontalDragEnd != null;
    final vertical =
        onVerticalDragStart != null ||
        onVerticalDragUpdate != null ||
        onVerticalDragEnd != null;
    if (horizontal == vertical) return null;
    return horizontal ? 'horizontal' : 'vertical';
  }

  void _pan(String phase, Map<String, dynamic> data) {
    double n(String key) => (data[key] as num?)?.toDouble() ?? 0;
    final at = Offset(n('x'), n('y'));
    switch (phase) {
      case 'start':
        final details = DragStartDetails(globalPosition: at, localPosition: at);
        onPanStart?.call(details);
        onHorizontalDragStart?.call(details);
        onVerticalDragStart?.call(details);
      case 'update':
        final delta = Offset(n('dx'), n('dy'));
        onPanUpdate?.call(
          DragUpdateDetails(
            delta: delta,
            globalPosition: at,
            localPosition: at,
          ),
        );
        onHorizontalDragUpdate?.call(
          DragUpdateDetails(
            delta: Offset(delta.dx, 0),
            primaryDelta: delta.dx,
            globalPosition: at,
            localPosition: at,
          ),
        );
        onVerticalDragUpdate?.call(
          DragUpdateDetails(
            delta: Offset(0, delta.dy),
            primaryDelta: delta.dy,
            globalPosition: at,
            localPosition: at,
          ),
        );
      case 'end':
        final speed = Offset(n('vx'), n('vy'));
        onPanEnd?.call(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: speed),
            globalPosition: at,
            localPosition: at,
          ),
        );
        onHorizontalDragEnd?.call(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(speed.dx, 0)),
            primaryVelocity: speed.dx,
            globalPosition: at,
            localPosition: at,
          ),
        );
        onVerticalDragEnd?.call(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(0, speed.dy)),
            primaryVelocity: speed.dy,
            globalPosition: at,
            localPosition: at,
          ),
        );
    }
  }

  @override
  WidgetNode _render(_Owner owner) {
    final node = child == null ? null : _renderChild(owner, child!);
    final doubleTap = onDoubleTap;
    final longPress = onLongPress;
    final scales = _scales;
    if (!_taps &&
        !_drags &&
        !scales &&
        doubleTap == null &&
        longPress == null) {
      return node ?? UIBuilder.sizedBox();
    }
    return UIBuilder.box(
      onTap: _taps
          ? (x, y) {
              final at = Offset(x, y);
              onTapDown?.call(
                TapDownDetails(globalPosition: at, localPosition: at),
              );
              onTapUp?.call(TapUpDetails(globalPosition: at, localPosition: at));
              onTap?.call();
            }
          : null,
      onDoubleTap: doubleTap == null ? null : (_, _) => doubleTap(),
      onLongPress: longPress == null ? null : (_, _) => longPress(),
      onPan: scales ? _scale : (_drags ? _pan : null),
      panAxis: scales ? _scaleAxis : (_drags ? _dragAxis : null),
      panScale: scales,
      expand: _expandOfChild(node),
      id: _idOf(key),
      child: node,
    );
  }
}

/// The axes a box that only listens - a [GestureDetector], an [InkWell] -
/// fills: the ones its child fills. In Flutter the two are the same size, so
/// a detector around a `SizedBox.expand` or a filling `CustomPaint` takes
/// touches over the whole area; a box left hugging its child would not.
String? _expandOfChild(WidgetNode? child) {
  if (child == null || (child.type != 'Box' && child.type != 'Canvas')) {
    return null;
  }
  final expand = child.props['expand'];
  return expand is String ? expand : null;
}

/// What a [Draggable] is carrying, and who to tell when it lands.
class _Dragged {
  const _Dragged(this.data, this.onCompleted);
  final Object? data;
  final VoidCallback? onCompleted;
}

/// How a drag ended: whether a target took it. The velocity and the offset
/// are always zero.
class DraggableDetails {
  const DraggableDetails({
    this.wasAccepted = false,
    this.velocity = Velocity.zero,
    this.offset = Offset.zero,
  });
  final bool wasAccepted;
  final Velocity velocity;
  final Offset offset;
}

/// Something that can be picked up and dropped on a [DragTarget].
///
/// The platform does the dragging: it lifts a picture of [child] and carries
/// a token, which the target turns back into [data]. So [feedback] is
/// accepted and not drawn - the lifted picture is the child itself.
///
/// [onDragStarted] is called when it is picked up and [onDragEnd] when it is
/// let go, with whether a target took it; [onDragCompleted] when one did and
/// [onDraggableCanceled] when none did. While it is in the air
/// [childWhenDragging] is drawn where it was. The velocity and the offset
/// those callbacks are given are always zero: where a drag ended is not
/// reported, only that it did.
class Draggable<T extends Object> extends Widget {
  const Draggable({
    super.key,
    required this.child,
    required this.feedback,
    this.data,
    this.axis,
    this.childWhenDragging,
    this.maxSimultaneousDrags,
    this.onDragStarted,
    this.onDraggableCanceled,
    this.onDragEnd,
    this.onDragCompleted,
  });
  final Widget child;
  final Widget feedback;
  final T? data;
  final Axis? axis;
  final Widget? childWhenDragging;
  final int? maxSimultaneousDrags;
  final VoidCallback? onDragStarted;
  final void Function(Velocity velocity, Offset offset)? onDraggableCanceled;
  final void Function(DraggableDetails details)? onDragEnd;
  final VoidCallback? onDragCompleted;

  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child);
    if (maxSimultaneousDrags == 0) return node;
    // The wire carries a string; the object it stands for stays here, looked
    // up again when a target reports the drop.
    final token = _idOf(key) ?? owner._autoId('drag');
    if (owner._hidden == 0) {
      owner._dragData[token] = _Dragged(data, onDragCompleted);
    }
    final away = childWhenDragging;
    return UIBuilder.box(
      dragData: token,
      // Heard whether or not the app listens: a target under the drag says
      // what is over it from the drags in the air.
      onDrag: (phase) => _dragged(owner, token, phase),
      id: _idOf(key),
      // The box is the one the platform lifted a picture of; what it holds
      // in the meantime is the app's to say.
      child: away != null && owner._dragging.contains(token)
          ? _renderChild(owner, away, 'away')
          : node,
    );
  }

  void _dragged(_Owner owner, String token, String phase) {
    if (phase == 'start') {
      if (!owner._dragging.add(token)) return;
      owner._dropped.remove(token);
      onDragStarted?.call();
    } else {
      if (!owner._dragging.remove(token)) return;
      final accepted = owner._dropped.remove(token);
      if (!accepted) onDraggableCanceled?.call(Velocity.zero, Offset.zero);
      onDragEnd?.call(DraggableDetails(wasAccepted: accepted));
    }
    if (childWhenDragging != null) owner._requestRebuild();
  }
}

/// A [Draggable] picked up after a long press. Every platform that
/// distinguishes the two already waits for one, so this is the same thing.
class LongPressDraggable<T extends Object> extends Draggable<T> {
  const LongPressDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.axis,
    super.childWhenDragging,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    this.hapticFeedbackOnStart = true,
    this.delay = const Duration(milliseconds: 500),
  });
  final bool hapticFeedbackOnStart;
  final Duration delay;
}

/// What landed on a [DragTarget], and where.
class DragTargetDetails<T> {
  const DragTargetDetails({required this.data, required this.offset});
  final T data;

  /// Always zero: the renderers report the drop, not its position.
  final Offset offset;
}

/// Builds a drag target from what is hovering over it.
typedef DragTargetBuilder<T> =
    Widget Function(
      BuildContext context,
      List<T?> candidateData,
      List<dynamic> rejectedData,
    );

/// Somewhere a [Draggable] can be dropped.
///
/// While a drag hovers over it the builder's `candidateData` is not empty,
/// which is what a target highlights itself by. It holds a single null rather
/// than the data: the platform says that something is over the target, not
/// what, until it is dropped. [onWillAcceptWithDetails] is therefore asked at
/// the drop, where the data is known, rather than on the way in.
class DragTarget<T extends Object> extends StatefulWidget {
  const DragTarget({
    super.key,
    required this.builder,
    this.onWillAcceptWithDetails,
    this.onAcceptWithDetails,
    this.onLeave,
    this.onMove,
    this.hitTestBehavior = HitTestBehavior.translucent,
  });
  final DragTargetBuilder<T> builder;
  final bool Function(DragTargetDetails<T> details)? onWillAcceptWithDetails;
  final void Function(DragTargetDetails<T> details)? onAcceptWithDetails;
  final void Function(T? data)? onLeave;

  /// Accepted and never called: a drag's movement is not reported.
  final void Function(DragTargetDetails<T> details)? onMove;
  final HitTestBehavior hitTestBehavior;

  @override
  State<DragTarget<T>> createState() => _DragTargetState<T>();
}

class _DragTargetState<T extends Object> extends State<DragTarget<T>> {
  bool _hovering = false;

  void _drop(String token) {
    final dragged = _owner?._dragData[token];
    if (mounted && _hovering) setState(() => _hovering = false);
    final data = dragged?.data;
    // Something else was dropped here: another type's draggable, or a drag
    // from outside the app.
    if (dragged == null || data is! T) return;
    final details = DragTargetDetails<T>(data: data, offset: Offset.zero);
    if (!(widget.onWillAcceptWithDetails?.call(details) ?? true)) return;
    _owner?._dropped.add(token);
    widget.onAcceptWithDetails?.call(details);
    dragged.onCompleted?.call();
  }

  void _hover(bool over) {
    if (!mounted || over == _hovering) return;
    setState(() => _hovering = over);
    if (!over) widget.onLeave?.call(null);
  }

  /// What is over the target: the data of the drags in the air that this
  /// target takes - or, for one from outside the app, nothing it can name.
  List<T?> _candidates(_Owner owner) {
    if (!_hovering) return <T?>[];
    final carried = [
      for (final token in owner._dragging)
        if ((owner._dragData[token] ?? owner._dragDataBefore[token])?.data
            case final T data)
          data,
    ];
    return carried.isEmpty ? <T?>[null] : carried;
  }

  @override
  Widget build(BuildContext context) => _NodeWidget(
    (owner) => UIBuilder.box(
      onDrop: _drop,
      onDropHover: _hover,
      id: _idOf(widget.key),
      child: owner.inSlot(
        'child',
        () => widget.builder(
          owner._context(),
          _candidates(owner),
          const <dynamic>[],
        )._render(owner),
      ),
    ),
  );
}

/// Which way a [Dismissible] may be swiped.
enum DismissDirection {
  vertical,
  horizontal,
  endToStart,
  startToEnd,
  up,
  down,
  none,
}

/// A row that is swiped away.
///
/// The row follows the finger, with [background] showing behind it - or
/// [secondaryBackground], for a swipe towards the start. Let go past the
/// threshold, or flung, it slides the rest of the way and [onDismissed] is
/// called, once [confirmDismiss] agrees; let go short of it, it slides back.
/// As in Flutter the app must then take the row out of its list.
///
/// Short of Flutter: the gap the row leaves does not close by itself
/// ([resizeDuration] and [onResize] are accepted and not carried) and
/// [onUpdate] is not called. Each movement of the finger is a build, so on a
/// long screen the row is a little behind the finger.
class Dismissible extends StatefulWidget {
  const Dismissible({
    required Key super.key,
    required this.child,
    this.background,
    this.secondaryBackground,
    this.confirmDismiss,
    this.onResize,
    this.onUpdate,
    this.onDismissed,
    this.direction = DismissDirection.horizontal,
    this.resizeDuration,
    this.dismissThresholds = const <DismissDirection, double>{},
    this.movementDuration = const Duration(milliseconds: 200),
    this.crossAxisEndOffset = 0.0,
    this.behavior = HitTestBehavior.opaque,
  });
  final Widget child;

  /// Behind the row for a swipe from the start - and from the end too, when
  /// there is no [secondaryBackground].
  final Widget? background;
  final Widget? secondaryBackground;

  /// Asked before dismissing; false or null puts the row back.
  final Future<bool?> Function(DismissDirection direction)? confirmDismiss;
  final VoidCallback? onResize;
  final void Function(Object details)? onUpdate;
  final void Function(DismissDirection direction)? onDismissed;
  final DismissDirection direction;

  /// How far, as a part of the row's own extent, a swipe has to go to
  /// dismiss: 0.4 where a direction is not named.
  final Map<DismissDirection, double> dismissThresholds;

  /// How long the row takes to slide away, or back.
  final Duration movementDuration;

  /// Accepted and not carried.
  final Duration? resizeDuration;
  final double crossAxisEndOffset;
  final HitTestBehavior behavior;

  @override
  State<Dismissible> createState() => _DismissibleState();
}

class _DismissibleState extends State<Dismissible> {
  /// How far the row is from where it sits, along its axis, in pixels.
  double _offset = 0;

  /// Whether a finger has it, in which case it moves at once.
  bool _dragging = false;

  /// The way it was dismissed, once it has been.
  DismissDirection? _dismissed;
  Size? _size;

  static const double _fling = 700;

  bool get _vertical =>
      widget.direction == DismissDirection.vertical ||
      widget.direction == DismissDirection.up ||
      widget.direction == DismissDirection.down;

  /// The direction a movement of [sign] along the axis is, where the screen
  /// reads [rtl]; null for one this row is not swiped in.
  DismissDirection? _way(double sign, bool rtl) {
    if (sign == 0) return null;
    final DismissDirection way;
    if (_vertical) {
      way = sign < 0 ? DismissDirection.up : DismissDirection.down;
    } else {
      // Towards the end of the line is startToEnd, whichever side that is.
      way = (sign > 0) != rtl
          ? DismissDirection.startToEnd
          : DismissDirection.endToStart;
    }
    final allowed = switch (widget.direction) {
      DismissDirection.horizontal || DismissDirection.vertical => true,
      DismissDirection.none => false,
      final one => one == way,
    };
    return allowed ? way : null;
  }

  double _extent(_Owner owner) {
    final size = _size;
    if (size != null) return _vertical ? size.height : size.width;
    final screen = _mediaOf(owner).size;
    return _vertical ? screen.height : screen.width;
  }

  void _pan(_Owner owner, bool rtl, String phase, Map<String, dynamic> data) {
    if (_dismissed != null || !mounted) return;
    double n(String key) => (data[key] as num?)?.toDouble() ?? 0;
    switch (phase) {
      case 'start':
        setState(() => _dragging = true);
      case 'update':
        final moved = _offset + (_vertical ? n('dy') : n('dx'));
        // Not past where it sits, the way it may not be swiped.
        setState(() => _offset = _way(moved.sign, rtl) == null ? 0 : moved);
      case 'end':
        final way = _way(_offset.sign, rtl);
        final extent = _extent(owner);
        final speed = _vertical ? n('vy') : n('vx');
        final far =
            extent > 0 &&
            _offset.abs() / extent > (widget.dismissThresholds[way] ?? 0.4);
        // A fling the way the row has gone; one back is a change of mind.
        final flung = speed.abs() > _fling && speed.sign == _offset.sign;
        if (way != null && (far || flung)) {
          unawaited(_leave(way, extent));
        } else {
          setState(() {
            _dragging = false;
            _offset = 0;
          });
        }
    }
  }

  Future<void> _leave(DismissDirection way, double extent) async {
    final sign = _offset.sign;
    // Held where the finger left it while the app is asked.
    setState(() => _dragging = false);
    final confirm = widget.confirmDismiss;
    if (confirm != null && await confirm(way) != true) {
      if (mounted) setState(() => _offset = 0);
      return;
    }
    if (!mounted) return;
    setState(() {
      _dismissed = way;
      _offset = sign * extent;
    });
    // Told once the row has slid away, as Flutter tells it.
    await Future<void>.delayed(widget.movementDuration);
    if (mounted) widget.onDismissed?.call(way);
  }

  void _measured(double width, double height) {
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
    final rtl = owner._direction == TextDirection.rtl;
    final row = _renderChild(owner, widget.child);
    if (widget.direction == DismissDirection.none) return row;
    // What shows behind the row is the background of the way it has gone.
    final way = _way(_offset.sign, rtl);
    final towardsStart =
        way == DismissDirection.endToStart || way == DismissDirection.up;
    final behind = way == null
        ? null
        : (towardsStart
              ? widget.secondaryBackground ?? widget.background
              : widget.background);
    return UIBuilder.stack(
      id: _idOf(widget.key),
      children: [
        // Always there, and empty at rest: a background that arrived with the
        // first movement would move the row along among its siblings, and a
        // renderer would make the row's view again with the finger still on
        // the old one.
        UIBuilder.positioned(
          fill: true,
          child: behind == null
              ? UIBuilder.sizedBox()
              : _renderChild(owner, behind, 'background'),
        ),
        UIBuilder.box(
          transform: _offset == 0
              ? null
              : {_vertical ? 'dy' : 'dx': _offset},
          // Under the finger it is where the finger is; let go, it slides.
          animateMs: _dragging ? 0 : widget.movementDuration.inMilliseconds,
          curve: 'easeOut',
          panAxis: _vertical ? 'vertical' : 'horizontal',
          onPan: (phase, data) => _pan(owner, rtl, phase, data),
          onSize: _measured,
          // As wide as the row it holds, which is as wide as it was.
          expand: _vertical ? null : 'width',
          child: row,
        ),
      ],
    );
  });
}
