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
/// along its axis as `primaryDelta`. [behavior] is accepted and not carried:
/// a box takes the touches that land on it.
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
  final HitTestBehavior? behavior;
  final bool excludeFromSemantics;

  bool get _taps => onTap != null || onTapDown != null || onTapUp != null;

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
    if (!_taps && !_drags && doubleTap == null && longPress == null) {
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
      onPan: _drags ? _pan : null,
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

/// Where a drag ended. Accepted for Flutter's signature.
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
/// a token, which the target turns back into [data]. So [feedback] and
/// [childWhenDragging] are accepted and not drawn - the lifted picture is the
/// child itself - and of the callbacks only [onDragCompleted] is called, when
/// a target accepts the drop: a drag starting, or ending over nothing, is
/// something the renderers do not report.
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
    return UIBuilder.box(dragData: token, id: _idOf(key), child: node);
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
    widget.onAcceptWithDetails?.call(details);
    dragged.onCompleted?.call();
  }

  void _hover(bool over) {
    if (!mounted || over == _hovering) return;
    setState(() => _hovering = over);
    if (!over) widget.onLeave?.call(null);
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
          _hovering ? <T?>[null] : <T?>[],
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

/// A row that is swiped to dismiss it.
///
/// Drawn with the platform's swipe actions, which is the same gesture with
/// one difference worth knowing: in Flutter the row slides away under the
/// finger and is gone; here the swipe *reveals an action* behind the row - a
/// button in the colour and words of [background] - and a full swipe, or a
/// tap on it, dismisses. [onDismissed] is called either way, after
/// [confirmDismiss] agrees, and as in Flutter the app must then take the row
/// out of its list.
///
/// The button's label is the text found in [background] (or
/// [secondaryBackground], for a swipe from the end) and "Delete" if there is
/// none; its colour is that background's.
class Dismissible extends Widget {
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

  /// Asked before dismissing; false or null keeps the row.
  final Future<bool?> Function(DismissDirection direction)? confirmDismiss;
  final VoidCallback? onResize;
  final void Function(Object details)? onUpdate;
  final void Function(DismissDirection direction)? onDismissed;
  final DismissDirection direction;

  /// Accepted and not carried: the swipe is the platform's own.
  final Duration? resizeDuration;
  final Map<DismissDirection, double> dismissThresholds;
  final Duration movementDuration;
  final double crossAxisEndOffset;
  final HitTestBehavior behavior;

  Future<void> _dismiss(DismissDirection way) async {
    final confirm = confirmDismiss;
    if (confirm != null && await confirm(way) != true) return;
    onDismissed?.call(way);
  }

  /// The colour a background paints itself, if it says.
  static Color? _colorOf(Widget? background) => switch (background) {
    Container() =>
      background.color ??
          (background.decoration is BoxDecoration
              ? (background.decoration as BoxDecoration).color
              : null),
    ColoredBox() => background.color,
    _ => null,
  };

  ({String label, String color, void Function() onPressed}) _action(
    _Owner owner,
    Widget? background,
    DismissDirection way,
  ) => (
    label: _plainText(background, owner) ?? 'Delete',
    color:
        (_colorOf(background) ?? _themeOf(owner).colorScheme.error)._hex,
    onPressed: () => unawaited(_dismiss(way)),
  );

  @override
  WidgetNode _render(_Owner owner) {
    final node = _renderChild(owner, child);
    final fromEnd =
        direction == DismissDirection.horizontal ||
        direction == DismissDirection.endToStart;
    final fromStart =
        direction == DismissDirection.horizontal ||
        direction == DismissDirection.startToEnd;
    // A vertical dismissal has no platform gesture to stand in for it.
    if (!fromEnd && !fromStart) return node;
    return UIBuilder.swipeActions(
      child: node,
      actions: [
        if (fromEnd)
          _action(
            owner,
            secondaryBackground ?? background,
            DismissDirection.endToStart,
          ),
      ],
      leadingActions: [
        if (fromStart)
          _action(owner, background, DismissDirection.startToEnd),
      ],
      id: _idOf(key),
    );
  }
}
