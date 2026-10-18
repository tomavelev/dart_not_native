part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Scrolling.
//
// Flutter's rule, and now this framework's: a Scaffold's body does not scroll.
// What scrolls is a SingleChildScrollView, a ListView or a GridView, placed
// where it has a bounded height to scroll in.
// ---------------------------------------------------------------------------

/// How a scroller answers a drag. The platforms each scroll their own way, so
/// only one of these changes anything: [NeverScrollableScrollPhysics] makes a
/// list that does not scroll at all - it is laid out in full, for the scroller
/// around it to move.
class ScrollPhysics {
  const ScrollPhysics({this.parent});
  final ScrollPhysics? parent;

  bool get _never =>
      this is NeverScrollableScrollPhysics || (parent?._never ?? false);
}

class NeverScrollableScrollPhysics extends ScrollPhysics {
  const NeverScrollableScrollPhysics({super.parent});
}

class AlwaysScrollableScrollPhysics extends ScrollPhysics {
  const AlwaysScrollableScrollPhysics({super.parent});
}

class BouncingScrollPhysics extends ScrollPhysics {
  const BouncingScrollPhysics({super.parent});
}

class ClampingScrollPhysics extends ScrollPhysics {
  const ClampingScrollPhysics({super.parent});
}

/// Moves a scroller from code, and says where it is.
///
/// The scroll itself happens in the renderer, which is told where to go
/// ([jumpTo], [animateTo] - the offset travels with the next tree) and says
/// where a finger has since dragged it: when the scroller comes to rest, and
/// at most about every 100 ms while it moves. So [offset] and the listeners
/// follow the reader, a step behind rather than frame by frame - enough to
/// load more near the end or to show a "back to top" button, not to move
/// something in step with the drag.
///
/// This applies to every scroller: a [SingleChildScrollView], a [GridView]
/// and a [ListView], windowed or not.
class ScrollController extends ChangeNotifier {
  ScrollController({
    this.initialScrollOffset = 0.0,
    this.keepScrollOffset = true,
    this.debugLabel,
  }) : _offset = initialScrollOffset;

  final double initialScrollOffset;
  final bool keepScrollOffset;
  final String? debugLabel;

  /// The name its scroller goes by for what moves in step with it
  /// (`scrollLinkSource`), said once something has been built from its
  /// offset ([_linked]).
  late final String _link = 'scroll${_links++}';
  static int _links = 0;
  bool _linked = false;

  double _offset;
  int _version = 0;
  _Owner? _owner;
  int _attachedPass = -1;
  double? _contentExtent;
  double _viewport = 0;

  /// The last build this was drawn in - as against built only to be kept
  /// alive under another page or behind another tab.
  int _shownPass = -1;

  /// Whether the renderer has said where the scroller is.
  bool _reported = false;

  /// Running while the scroller is taken to be moving: see
  /// [ScrollEndNotification].
  Timer? _restTimer;

  /// How far the renderer says the scroller can go, once it has said.
  double? _maxExtent;

  /// Takes what the renderer reports: where the reader has scrolled to.
  void _report(double offset, double? maxExtent, double? viewport) {
    _reported = true;
    if (maxExtent != null) _maxExtent = maxExtent;
    if (viewport != null) _viewport = viewport;
    if (offset == _offset) return;
    _offset = offset;
    // No rebuild of its own: the scroller is already there. A listener that
    // wants one asks for it.
    notifyListeners();
  }

  /// Marks the scroller as drawn in [owner]'s current build.
  ///
  /// A scroller that was not drawn in the build before - its page was under
  /// another, its tab was not showing - is a new view to the renderer, which
  /// starts a new view at the top. Flutter keeps the position with the page;
  /// so the scroller is sent back to where it was, as if by [jumpTo].
  void _shown(_Owner owner) {
    final returning = _shownPass >= 0 && _shownPass < owner._pass - 1;
    if (returning && _reported && _offset > 0) _version++;
    _shownPass = owner._pass;
  }

  /// Whether a scroller built with this controller is on screen: built in
  /// this build, or in the last one by a build that has not reached it yet -
  /// a header above the list it follows asks before the list is built.
  bool get hasClients {
    final owner = _owner;
    if (owner == null) return false;
    return _attachedPass == owner._pass ||
        (owner._building && _attachedPass == owner._pass - 1);
  }

  /// Where the scroller is: where the app last sent it, or where the
  /// renderer has since said the reader took it - see the class doc.
  double get offset {
    _Owner._current?._readOffset(this);
    return _offset;
  }

  ScrollPosition get position => ScrollPosition._(this);

  /// As [position], for code written against a controller with several.
  Iterable<ScrollPosition> get positions => hasClients ? [position] : const [];

  /// Whether the offset last asked for is to be travelled to, and over how
  /// long, along what.
  bool _animated = false;
  Duration _travel = Duration.zero;
  Curve _travelCurve = Curves.ease;

  /// Scrolls to [value] at once.
  void jumpTo(double value) {
    _animated = false;
    _go(value);
  }

  void _go(double value) {
    _offset = math.max(0, value);
    _version++;
    notifyListeners();
    _owner?._requestRebuild();
  }

  /// Scrolls to [offset], travelling there over [duration] along [curve];
  /// the returned future completes when it is there. A duration of zero is
  /// a [jumpTo].
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    _animated = duration > Duration.zero;
    _travel = duration;
    _travelCurve = curve;
    _go(offset);
    return _animated ? Future<void>.delayed(duration) : Future<void>.value();
  }

  void _attach(_Owner owner, {double? contentExtent, required double viewport}) {
    _owner = owner;
    _attachedPass = owner._pass;
    _contentExtent = contentExtent;
    _viewport = viewport;
  }

  /// What a windowed list's node carries: nothing until there is a position
  /// to send it to - one the app asked for, or the one it was at when its
  /// page was last on screen. A scroller's node always carries [_offset]
  /// instead - see [_scroller].
  double? get _wireOffset =>
      _version > 0 || initialScrollOffset != 0 ? _offset : null;

  @override
  void dispose() {
    _owner = null;
    super.dispose();
  }
}

/// A scroller's extent, as far as it can be known without measuring.
class ScrollPosition {
  ScrollPosition._(this._controller);
  final ScrollController _controller;

  double get pixels => _controller.offset;
  double get minScrollExtent => 0;

  /// The scroller's own length once the renderer has reported it; until
  /// then the height of the window, the nearest thing known on this side.
  double get viewportDimension => _controller._viewport;

  /// How far the scroller can go. Exact once the renderer has reported it
  /// (after the first scroll) and for a list of rows of known height;
  /// otherwise the content was never measured here, and this is a number
  /// large enough that "scroll to the end" asks for the end.
  double get maxScrollExtent {
    final reported = _controller._maxExtent;
    if (reported != null) return reported;
    final extent = _controller._contentExtent;
    if (extent == null) return 1e7;
    return math.max(0, extent - viewportDimension);
  }

  double get extentBefore => pixels;
  double get extentAfter => math.max(0, maxScrollExtent - pixels);
  bool get atEdge => pixels <= 0 || pixels >= maxScrollExtent;
  bool get hasContentDimensions => true;

  void jumpTo(double value) => _controller.jumpTo(value);

  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) => _controller.animateTo(to, duration: duration, curve: curve);
}

/// Something a widget says to the ones above it - Flutter's `Notification`.
///
/// [dispatch] hands it to each [NotificationListener] of its type above
/// [BuildContext], nearest first, until one answers true.
abstract class Notification {
  const Notification();

  void dispatch(BuildContext? target) {
    if (target is! _Context) return;
    _send(this, _listenersAbove(target._scope));
  }
}

/// Answers true to keep a notification from the listeners further up.
typedef NotificationListenerCallback<T extends Notification> =
    bool Function(T notification);

/// Hears the notifications of type [T] sent from below it - Flutter's
/// `NotificationListener`.
///
/// ```dart
/// NotificationListener<ScrollNotification>(
///   onNotification: (scroll) {
///     if (scroll.metrics.extentAfter < 200) loadMore();
///     return false;
///   },
///   child: ListView(children: rows),
/// )
/// ```
///
/// A scroller sends [ScrollNotification]s as often as it reports where it
/// is: when it comes to rest and about every 100 ms on the way (see
/// [ScrollController]).
class NotificationListener<T extends Notification> extends StatelessWidget {
  const NotificationListener({
    super.key,
    required this.child,
    this.onNotification,
  });
  final Widget child;
  final NotificationListenerCallback<T>? onNotification;

  bool _hear(Notification notification) =>
      notification is T && (onNotification?.call(notification) ?? false);

  @override
  Widget build(BuildContext context) =>
      _NotificationScope(listener: this, child: child);
}

class _NotificationScope extends InheritedWidget {
  const _NotificationScope({required this.listener, required super.child});
  final NotificationListener<Notification> listener;

  @override
  bool updateShouldNotify(_NotificationScope oldWidget) => false;
}

/// The listeners above [scope], nearest first.
List<NotificationListener<Notification>> _listenersAbove(_Scope? scope) => [
  for (var at = scope; at != null; at = at.parent)
    if (at.inherited case final _NotificationScope found) found.listener,
];

void _send(
  Notification notification,
  List<NotificationListener<Notification>> listeners,
) {
  for (final listener in listeners) {
    if (listener._hear(notification)) return;
  }
}

/// Which way a scroller's offset grows.
enum AxisDirection { up, right, down, left }

/// Where a scroller is and how far it can go, at the moment of a
/// [ScrollNotification].
class ScrollMetrics {
  const ScrollMetrics({
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportDimension,
    required this.axisDirection,
  });
  final double pixels;
  final double minScrollExtent;
  final double maxScrollExtent;
  final double viewportDimension;
  final AxisDirection axisDirection;

  Axis get axis =>
      axisDirection == AxisDirection.up || axisDirection == AxisDirection.down
      ? Axis.vertical
      : Axis.horizontal;
  double get extentBefore => math.max(0, pixels - minScrollExtent);
  double get extentAfter => math.max(0, maxScrollExtent - pixels);
  double get extentInside => viewportDimension;
  double get extentTotal => maxScrollExtent - minScrollExtent + viewportDimension;
  bool get atEdge => pixels <= minScrollExtent || pixels >= maxScrollExtent;
  bool get outOfRange => pixels < minScrollExtent || pixels > maxScrollExtent;
  bool get hasPixels => true;
  bool get hasContentDimensions => true;
  bool get hasViewportDimension => true;
}

/// A scroller saying something about its scrolling. [depth] is always 0:
/// a scroller's notifications are heard as its own wherever they are heard.
abstract class ScrollNotification extends Notification {
  const ScrollNotification({required this.metrics, this.context});
  final ScrollMetrics metrics;
  final BuildContext? context;
  int get depth => 0;
}

/// A scroller that was at rest has moved.
class ScrollStartNotification extends ScrollNotification {
  const ScrollStartNotification({required super.metrics, super.context});
}

/// A scroller is somewhere else, [scrollDelta] further along than it last
/// said.
class ScrollUpdateNotification extends ScrollNotification {
  const ScrollUpdateNotification({
    required super.metrics,
    super.context,
    this.scrollDelta,
  });
  final double? scrollDelta;
}

/// A scroller has stopped: nothing was heard from it for a moment. No
/// renderer says "at rest" in so many words, so it is the app's own clock.
class ScrollEndNotification extends ScrollNotification {
  const ScrollEndNotification({required super.metrics, super.context});
}

/// The offsets a widget that follows a scroller is built at, besides the
/// one it is at: between them a renderer goes in a straight line.
const _scrollStops = [
  0.0, 16.0, 32.0, 64.0, 96.0, 128.0, 192.0, 256.0, 384.0, 512.0, 768.0,
  1024.0,
];

/// [render], and when what it built read where a scroller is - a header
/// that shrinks, a title that fades in, a picture that moves slower than the
/// page - the boxes in it that change with the offset, each with a table of
/// what it is at a dozen offsets (`scrollLink`). A renderer applies the table
/// from its own scroll callback, so they move in step with the finger;
/// between the reports the app hears, nothing else is asked of Dart.
///
/// The table comes from building the same widgets at each of
/// [_scrollStops] and comparing the trees: a box's opacity, size and
/// movement are followed, and only while the trees keep one shape. What
/// else changes - words, colours - follows the reports, as before.
WidgetNode _followingScroll(_Owner owner, WidgetNode Function() render) {
  if (owner._sampling) return render();
  final outer = owner._offsetReads;
  final reads = owner._offsetReads = <ScrollController>{};
  final WidgetNode node;
  try {
    node = render();
  } finally {
    owner._offsetReads = outer;
  }
  final controller = reads.length == 1 ? reads.single : null;
  if (controller == null || !controller._reported) return node;
  final place = owner._positionId('scrollFollow');
  owner._followedUsed.add(place);
  final real = controller._offset;
  // The tables of the last report still say what the widgets do, when the
  // tree has kept its shape and every box shows what its table says for
  // where the scroller is now: one build, not a dozen.
  final last = owner._followed[place];
  if (last != null && last.source == controller._link) {
    final again = _relinked(node, last.linked, real);
    if (again != null) {
      owner._followed[place] = (source: last.source, linked: again);
      return again;
    }
  }
  final max = controller._maxExtent;
  final stops = [
    // Past the top, where a scroller that bounces goes - for a bar that
    // stretches there.
    -160.0,
    for (final stop in _scrollStops)
      if (max == null || stop < max) stop,
    if (max != null && max > 0 && max < _scrollStops.last) max,
  ];
  if (stops.length < 2) return node;
  final samples = <WidgetNode>[];
  final bindings = EventBindings.required;
  WidgetNode at(double offset) {
    controller._offset = offset;
    return bindings.forgetting(render);
  }

  owner._sampling = true;
  try {
    for (final stop in stops) {
      samples.add(at(stop));
    }
    // Where the line between two stops is not what the widgets do there - a
    // header that stops shrinking between them - the middle is a stop too,
    // and so on down, for a couple of dozen builds at most.
    final values = [for (final sample in samples) _followedValues(sample)];
    var budget = 24;
    var i = 0;
    while (i < stops.length - 1 && budget > 0) {
      final low = stops[i], high = stops[i + 1];
      if (high - low <= 4) {
        i++;
        continue;
      }
      final middle = (low + high) / 2;
      final sample = at(middle);
      final value = _followedValues(sample);
      final a = values[i], b = values[i + 1];
      var straight = value != null &&
          a != null &&
          b != null &&
          value.length == a.length &&
          a.length == b.length;
      for (var k = 0; straight && k < value!.length; k++) {
        if ((value[k] - (a![k] + b![k]) / 2).abs() > 0.5) straight = false;
      }
      if (straight) {
        i++;
        continue;
      }
      stops.insert(i + 1, middle);
      samples.insert(i + 1, sample);
      values.insert(i + 1, value);
      budget--;
    }
  } finally {
    controller._offset = real;
    owner._sampling = false;
  }
  final linked = _linkedTo(node, samples, stops, controller._link);
  if (linked == null) {
    owner._followed.remove(place);
    return node;
  }
  owner._followed[place] = (source: controller._link, linked: linked);
  if (!controller._linked) {
    // Its scroller says its name from the next build on.
    controller._linked = true;
    owner._requestRebuild();
  }
  return linked;
}

/// [color] - a protocol colour, `#rrggbb` or `#aarrggbb` - as `#aarrggbb`.
String? _argb(Object? color) {
  if (color is! String || !color.startsWith('#')) return null;
  final digits = color.substring(1);
  if (digits.length == 6) return '#ff$digits';
  return digits.length == 8 ? color : null;
}

/// [node] with the tables [linked] - the same widgets as last time - carry,
/// or null when it is not that tree any more: another shape, or a box whose
/// followed props are not what its table says for [offset].
WidgetNode? _relinked(WidgetNode node, WidgetNode linked, double offset) {
  if (node.type != linked.type) return null;
  final kids = node.children ?? const <WidgetNode>[];
  final theirs = linked.children ?? const <WidgetNode>[];
  if (kids.length != theirs.length) return null;
  List<WidgetNode>? children;
  for (var i = 0; i < kids.length; i++) {
    final again = _relinked(kids[i], theirs[i], offset);
    if (again == null) return null;
    if (!identical(again, kids[i])) (children ??= List.of(kids))[i] = again;
  }
  final link = linked.props['scrollLink'];
  if (link is! Map) {
    return children == null
        ? node
        : WidgetNode(type: node.type, props: node.props, children: children);
  }
  final at = [for (final v in link['at'] as List) (v as num).toDouble()];
  double along(List values) {
    double value(int i) => (values[i] as num).toDouble();
    if (offset <= at.first) return value(0);
    for (var i = 1; i < at.length; i++) {
      if (offset <= at[i]) {
        final t = (offset - at[i - 1]) / (at[i] - at[i - 1]);
        return value(i - 1) + (value(i) - value(i - 1)) * t;
      }
    }
    return value(at.length - 1);
  }

  final p = node.props;
  final moved = p['transform'] is Map ? p['transform'] as Map : null;
  double? own(String name) => switch (name) {
    'opacity' => (p['opacity'] as num?)?.toDouble() ?? 1,
    'width' || 'height' => (p[name] as num?)?.toDouble(),
    'scale' => (moved?['scale'] as num?)?.toDouble() ?? 1,
    _ => (moved?[name] as num?)?.toDouble() ?? 0,
  };
  for (final name in const [
    'opacity', 'width', 'height', 'dx', 'dy', 'scale', 'rotate',
  ]) {
    final values = link[name];
    if (values is! List) continue;
    final value = own(name);
    // Within a pixel, or a hundredth of an opacity or a scale.
    if (value == null || (value - along(values)).abs() > 0.6) return null;
  }
  final colors = link['color'];
  if (colors is List) {
    final now = int.tryParse(_argb(p['color'])?.substring(1) ?? '', radix: 16);
    if (now == null) return null;
    for (final shift in const [24, 16, 8, 0]) {
      final channel = [
        for (final c in colors)
          (int.parse((c as String).substring(1), radix: 16) >> shift) & 0xff,
      ];
      if ((((now >> shift) & 0xff) - along(channel)).abs() > 2) return null;
    }
  }
  return WidgetNode(
    type: node.type,
    props: {...p, 'scrollLink': link},
    children: children ?? node.children,
  );
}

/// The props a box's table can follow, for every box in [node] in order -
/// what the stops are compared by.
List<double>? _followedValues(WidgetNode node) {
  final out = <double>[];
  void walk(WidgetNode n) {
    if (n.type == 'Box') {
      final p = n.props;
      final moved = p['transform'] is Map ? p['transform'] as Map : null;
      double number(Object? v, double otherwise) =>
          (v as num?)?.toDouble() ?? otherwise;
      out
        ..add(number(p['opacity'], 1))
        ..add(number(p['width'], -1))
        ..add(number(p['height'], -1))
        ..add(number(moved?['dx'], 0))
        ..add(number(moved?['dy'], 0))
        ..add(number(moved?['scale'], 1))
        ..add(number(moved?['rotate'], 0));
      final argb = int.tryParse(_argb(p['color'])?.substring(1) ?? '', radix: 16);
      if (argb != null) {
        out.addAll([
          for (final shift in const [24, 16, 8, 0]) ((argb >> shift) & 0xff).toDouble(),
        ]);
      }
    }
    for (final child in n.children ?? const <WidgetNode>[]) {
      walk(child);
    }
  }

  walk(node);
  return out;
}

/// [node] with a `scrollLink` on each box whose followed props differ
/// between [samples] - the same tree built at each of [stops] - or null when
/// none does.
WidgetNode? _linkedTo(
  WidgetNode node,
  List<WidgetNode> samples,
  List<double> stops,
  String source,
) {
  List<WidgetNode>? children;
  final kids = node.children;
  if (kids != null) {
    for (var i = 0; i < kids.length; i++) {
      final along = <WidgetNode>[];
      for (final sample in samples) {
        final theirs = sample.children;
        if (theirs == null ||
            theirs.length != kids.length ||
            theirs[i].type != kids[i].type) {
          break;
        }
        along.add(theirs[i]);
      }
      if (along.length != samples.length) continue;
      final linked = _linkedTo(kids[i], along, stops, source);
      if (linked != null) (children ??= List.of(kids))[i] = linked;
    }
  }
  final table = <String, List<Object>>{};
  if (node.type == 'Box') {
    void follow(String name, double? Function(Map<String, dynamic>) read) {
      final values = <double>[];
      for (final sample in samples) {
        final value = read(sample.props);
        if (value == null) return;
        values.add(value);
      }
      if (values.any((v) => (v - values.first).abs() > 1e-6)) {
        table[name] = values;
      }
    }

    double? number(Object? n) => (n as num?)?.toDouble();
    Map? moved(Map<String, dynamic> p) =>
        p['transform'] is Map ? p['transform'] as Map : null;
    follow('opacity', (p) => number(p['opacity']) ?? 1);
    // A colour goes from stop to stop too, as `#aarrggbb`.
    final colors = [for (final sample in samples) _argb(sample.props['color'])];
    if (!colors.contains(null) && colors.toSet().length > 1) {
      table['color'] = [for (final c in colors) c!];
    }
    follow('width', (p) => number(p['width']));
    follow('height', (p) => number(p['height']));
    // A whole matrix is not taken apart.
    if (!samples.any((s) => moved(s.props)?['matrix'] != null)) {
      follow('dx', (p) => number(moved(p)?['dx']) ?? 0);
      follow('dy', (p) => number(moved(p)?['dy']) ?? 0);
      follow('scale', (p) => number(moved(p)?['scale']) ?? 1);
      follow('rotate', (p) => number(moved(p)?['rotate']) ?? 0);
    }
  }
  if (table.isEmpty && children == null) return null;
  return WidgetNode(
    type: node.type,
    props: table.isEmpty
        ? node.props
        : {
            ...node.props,
            'scrollLink': {'source': source, 'at': stops, ...table},
          },
    children: children ?? kids,
  );
}

/// What a scroller's node is given to report through: [position] is told
/// where the scroller is, and the listeners above the scroller - the ones
/// there when this build drew it - are told that it moved.
void Function(double, double?, double?) _reporting(
  _Owner owner,
  ScrollController position,
  Axis axis,
) {
  final listeners = _listenersAbove(owner._scope);
  if (listeners.isEmpty) return position._report;
  return (offset, maxExtent, viewport) {
    final before = position._offset;
    position._report(offset, maxExtent, viewport);
    final delta = position._offset - before;
    if (delta == 0) return;
    ScrollMetrics metrics() => ScrollMetrics(
      pixels: position._offset,
      minScrollExtent: 0,
      maxScrollExtent: position.position.maxScrollExtent,
      viewportDimension: position._viewport,
      axisDirection: axis == Axis.vertical
          ? AxisDirection.down
          : AxisDirection.right,
    );
    if (position._restTimer == null) {
      _send(ScrollStartNotification(metrics: metrics()), listeners);
    }
    _send(
      ScrollUpdateNotification(metrics: metrics(), scrollDelta: delta),
      listeners,
    );
    position._restTimer?.cancel();
    position._restTimer = Timer(const Duration(milliseconds: 250), () {
      position._restTimer = null;
      _send(ScrollEndNotification(metrics: metrics()), listeners);
    });
  };
}

/// The refresh a [RefreshIndicator] is waiting to hand to a scroller.
class _RefreshScope extends InheritedWidget {
  const _RefreshScope({required this.state, required super.child});
  final _RefreshIndicatorState state;

  @override
  bool updateShouldNotify(_RefreshScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// The one place a scroller becomes a node.
///
/// Where it cannot scroll - its physics say never, or it is vertical inside
/// another vertical scroller, which would leave it no height of its own - the
/// content is laid out in full and the scroller around it does the moving.
WidgetNode _scroller(
  _Owner owner, {
  required Axis axis,
  required WidgetNode Function() content,
  EdgeInsetsGeometry? padding,
  bool shrinkWrap = false,
  ScrollPhysics? physics,
  ScrollController? controller,
  bool reverse = false,
  String? id,
}) {
  final vertical = axis == Axis.vertical;
  final insets = padding?._resolved;
  WidgetNode laidOut() => owner._withLayout(
    content,
    unboundedHeight: vertical ? true : null,
    unboundedWidth: vertical ? null : true,
  );

  if ((physics?._never ?? false) || (vertical && owner._scrollDepth > 0)) {
    final node = laidOut();
    return insets == null
        ? node
        : UIBuilder.padding(
            left: insets.left,
            top: insets.top,
            right: insets.right,
            bottom: insets.bottom,
            child: node,
          );
  }

  // Pull-to-refresh belongs to the first vertical scroller under the
  // indicator, as it does in Flutter.
  _RefreshIndicatorState? refresh;
  if (vertical) {
    final waiting = owner._inherited<_RefreshScope>()?.state;
    if (waiting != null && !waiting._claimed) {
      waiting._claimed = true;
      refresh = waiting;
    }
  }
  // Every scroller has a position that outlives its view: the app's
  // controller, or one kept here by where the scroller sits.
  final position = controller ?? owner._scrollPosition();
  if (controller != null) {
    final reportedViewport = controller._maxExtent == null
        ? null
        : controller._viewport;
    controller._attach(
      owner,
      viewport: reportedViewport ?? _mediaOf(owner).size.height,
    );
  }
  if (owner._hidden == 0) position._shown(owner);

  if (vertical) owner._scrollDepth++;
  final WidgetNode child;
  try {
    child = laidOut();
  } finally {
    if (vertical) owner._scrollDepth--;
  }
  return UIBuilder.scroll(
    child: child,
    axis: vertical ? 'vertical' : 'horizontal',
    padding: insets?._ltrb,
    // With no end to the room on its axis there is nothing to scroll within,
    // so the scroller is as long as its content - which is also what
    // shrinkWrap asks for.
    shrinkWrap:
        shrinkWrap ||
        (vertical ? owner._unboundedHeight : owner._unboundedWidth),
    reverse: reverse,
    onRefresh: refresh?._start,
    refreshing: refresh?._refreshing ?? false,
    // Always said, and it follows the reader: a renderer obeys an offset once
    // per version, so on a scroller it already shows this moves nothing - but
    // a renderer that has to make the scroller's view again (the screen
    // around it changed shape: a snackbar arrived, a page came back) starts
    // the new one here rather than at the top.
    scrollOffset: position._offset,
    scrollVersion: position._version,
    scrollAnimated: position._animated,
    scrollMs: position._travel.inMilliseconds,
    scrollCurve: position._travelCurve.name,
    onScroll: _reporting(owner, position, vertical ? Axis.vertical : Axis.horizontal),
    linkSource: position._linked ? position._link : null,
    id: id,
  );
}

/// Scrolls one child: a form taller than the screen, a wide table.
class SingleChildScrollView extends Widget {
  const SingleChildScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.controller,
    this.child,
    this.clipBehavior = Clip.hardEdge,
  });
  final Axis scrollDirection;

  /// Starts at the far end, as a chat does.
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final Widget? child;
  final Clip clipBehavior;

  @override
  WidgetNode _render(_Owner owner) => _scroller(
    owner,
    axis: scrollDirection,
    padding: padding,
    physics: physics,
    controller: controller,
    reverse: reverse,
    id: _idOf(key),
    // Across a scroller its child has the scroller's own width.
    content: () => scrollDirection == Axis.vertical
        ? _passOn(owner, this, child ?? const SizedBox.shrink())
        : _renderChild(owner, child ?? const SizedBox.shrink()),
  );
}

/// Flutter draws a scrollbar beside its child; the platforms draw their own
/// where they have one, so this is its child.
class Scrollbar extends Widget {
  const Scrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.trackVisibility,
    this.thickness,
    this.radius,
    this.interactive,
  });
  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final bool? trackVisibility;
  final double? thickness;
  final Radius? radius;
  final bool? interactive;
  @override
  WidgetNode _render(_Owner owner) => _passOn(owner, this, child);
}

/// What a windowed list knows about the room it is in when it is asked for a
/// row's height.
class SliverLayoutDimensions {
  const SliverLayoutDimensions({
    required this.scrollOffset,
    required this.precedingScrollExtent,
    required this.viewportMainAxisExtent,
    required this.crossAxisExtent,
  });
  final double scrollOffset;
  final double precedingScrollExtent;
  final double viewportMainAxisExtent;
  final double crossAxisExtent;
}

/// The height of row [index], or null for "there is no such row".
typedef ItemExtentBuilder =
    double? Function(int index, SliverLayoutDimensions dimensions);

/// Builds row [index] of a list, or null past the end.
typedef NullableIndexedWidgetBuilder =
    Widget? Function(BuildContext context, int index);

/// Builds row [index] of a list.
typedef IndexedWidgetBuilder = Widget Function(BuildContext context, int index);

/// A scrolling list.
///
/// The default constructor stacks [children]. [ListView.builder] builds rows
/// on demand, and how many of them depends on what it is told:
///
/// * With an [itemExtent] (or an [itemExtentBuilder]), vertical and not
///   shrink-wrapped, it is **windowed**: only the rows near the visible ones
///   are built and sent, so ten thousand rows cost what thirty do. Flutter's
///   list measures its rows instead and needs no height; this one is told,
///   because a renderer on the other side of a channel is holding twenty rows
///   out of ten thousand and cannot measure the rest.
/// * Without one, every row is built and the platform's scroller scrolls
///   them. Right for a list of dozens; give a list of thousands a row height.
class ListView extends Widget {
  const ListView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.children = const [],
  }) : itemCount = null,
       itemExtentBuilder = null,
       itemBuilder = null,
       separatorBuilder = null;

  /// A list whose rows are built as they are needed - see the class doc for
  /// when that means "only the visible ones".
  ///
  /// Without an [itemCount], rows are built until [itemBuilder] answers null,
  /// and no further than five hundred.
  const ListView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    this.itemExtentBuilder,
    required NullableIndexedWidgetBuilder this.itemBuilder,
    this.itemCount,
  }) : children = const [],
       separatorBuilder = null,
       assert(
         itemExtent == null || itemExtentBuilder == null,
         'Give ListView.builder one row height (itemExtent) or a height per '
         'row (itemExtentBuilder), not both.',
       );

  /// A list with something between each row and the next. Every row is built.
  const ListView.separated({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required NullableIndexedWidgetBuilder this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    required int this.itemCount,
  }) : children = const [],
       itemExtent = null,
       itemExtentBuilder = null;

  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;

  /// Makes the list as long as its rows instead of scrolling them - what a
  /// list inside another scroller has to be.
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final List<Widget> children;
  final int? itemCount;
  final double? itemExtent;
  final ItemExtentBuilder? itemExtentBuilder;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;

  static const int _unboundedLimit = 500;

  /// How many rows of no stated height a list has before only those near
  /// the screen are built.
  static const int _measuredFrom = 60;

  @override
  WidgetNode _render(_Owner owner) {
    final builder = itemBuilder;
    final count = itemCount;
    final vertical = scrollDirection == Axis.vertical;
    final sized = itemExtent != null || itemExtentBuilder != null;
    final windowed =
        builder != null &&
        count != null &&
        // Rows of no stated height are measured as they come; a short list
        // of them is built whole, as it always was.
        (sized ? separatorBuilder == null : count > _measuredFrom) &&
        vertical &&
        !shrinkWrap &&
        !reverse &&
        !(physics?._never ?? false) &&
        owner._scrollDepth == 0 &&
        !owner._unboundedHeight;
    if (windowed) {
      final separator = separatorBuilder;
      if (separator == null) return _renderWindowed(owner, builder, count);
      // A row, then a separator, and so on: twice as many, less one.
      return _renderWindowed(
        owner,
        (context, index) => index.isEven
            ? builder(context, index ~/ 2)
            : separator(context, index ~/ 2),
        count * 2 - 1,
      );
    }

    return _scroller(
      owner,
      axis: scrollDirection,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      controller: controller,
      reverse: reverse,
      id: _idOf(key),
      content: () {
        // A vertical list's rows are as wide as it is.
        final rows = builder == null
            ? _renderAll(children, owner, tight: vertical)
            : _buildRows(owner, builder, count, tight: vertical);
        final extent = itemExtent;
        final sized = extent == null
            ? rows
            : [
                for (final row in rows)
                  vertical
                      ? UIBuilder.box(height: extent, child: row)
                      : UIBuilder.box(width: extent, child: row),
              ];
        return vertical
            ? UIBuilder.column(crossAxisAlignment: 'stretch', children: sized)
            : UIBuilder.row(crossAxisAlignment: 'stretch', children: sized);
      },
    );
  }

  List<WidgetNode> _buildRows(
    _Owner owner,
    NullableIndexedWidgetBuilder builder,
    int? count, {
    required bool tight,
  }) {
    final separator = separatorBuilder;
    final rows = <WidgetNode>[];
    final limit = count ?? _unboundedLimit;
    for (var index = 0; index < limit; index++) {
      final row = builder(owner._context(), index);
      if (row == null) {
        if (count == null) break;
        continue;
      }
      if (separator != null && rows.isNotEmpty) {
        rows.add(
          owner.inSlot(
            'separator$index',
            () => separator(owner._context(), index - 1)._render(owner),
          ),
        );
      }
      rows.add(
        owner._tightly(
          row,
          tight,
          () => owner.inSlot(index, () => row._render(owner)),
        ),
      );
    }
    return rows;
  }

  WidgetNode _renderWindowed(
    _Owner owner,
    NullableIndexedWidgetBuilder builder,
    int count,
  ) {
    final viewport = _mediaOf(owner).size;
    final extentBuilder = itemExtentBuilder;
    final dimensions = SliverLayoutDimensions(
      scrollOffset: controller?._offset ?? 0,
      precedingScrollExtent: 0,
      viewportMainAxisExtent: viewport.height,
      crossAxisExtent: viewport.width,
    );
    final extent = itemExtent;
    controller?._attach(
      owner,
      // A fixed height makes the list's own a product; heights of their own
      // are summed by the list node, not here.
      contentExtent: extent == null ? null : extent * count,
      viewport: viewport.height,
    );
    // A position that outlives the list's view, as every scroller has: the
    // app's controller, or one kept here by where the list sits. It hears
    // where the reader has got to, and sends the list back there when its
    // page returns.
    final position = controller ?? owner._scrollPosition();
    if (owner._hidden == 0) position._shown(owner);
    // Pull-to-refresh belongs to the first vertical scroller under the
    // indicator, and a windowed list is one.
    _RefreshIndicatorState? refresh;
    final waiting = owner._inherited<_RefreshScope>()?.state;
    if (waiting != null && !waiting._claimed) {
      waiting._claimed = true;
      refresh = waiting;
    }
    owner._scrollDepth++;
    try {
      return owner._withLayout(
        () => UIBuilder.lazyList(
          // The window lives under this id between builds, so a list without
          // a key is given one from where it sits.
          id: _idOf(key) ?? owner._autoId('list'),
          itemCount: count,
          itemExtent: extent,
          itemExtentBuilder: extentBuilder == null
              ? null
              : (index) => extentBuilder(index, dimensions) ?? 0,
          measured: extent == null && extentBuilder == null,
          itemBuilder: (index) => owner.inSlot(index, () {
            final row =
                builder(owner._context(), index) ?? const SizedBox.shrink();
            return owner._tightly(row, true, () => row._render(owner));
          }),
          scrollOffset: position._wireOffset,
          scrollVersion: position._version,
          scrollAnimated: position._animated,
          scrollMs: position._travel.inMilliseconds,
          scrollCurve: position._travelCurve.name,
          onScroll: _reporting(owner, position, Axis.vertical),
          linkSource: position._linked ? position._link : null,
          // Room inside the scroller, as Flutter's is: the rows scroll under
          // the edges rather than stopping short of them.
          padding: padding?._resolved._ltrb,
          onRefresh: refresh?._start,
          refreshing: refresh?._refreshing ?? false,
        ),
        unboundedHeight: true,
      );
    } finally {
      owner._scrollDepth--;
    }
  }
}

/// How a [GridView] decides its columns.
abstract class SliverGridDelegate {
  const SliverGridDelegate();
}

/// A fixed number of columns.
class SliverGridDelegateWithFixedCrossAxisCount extends SliverGridDelegate {
  const SliverGridDelegateWithFixedCrossAxisCount({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent,
  });
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;

  /// A cell's height, overriding [childAspectRatio]. It needs the grid's
  /// width to become a ratio, so the grid is measured first.
  final double? mainAxisExtent;
}

/// As many columns as fit with none wider than [maxCrossAxisExtent].
class SliverGridDelegateWithMaxCrossAxisExtent extends SliverGridDelegate {
  const SliverGridDelegateWithMaxCrossAxisExtent({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent,
  });
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final double? mainAxisExtent;
}

/// Children in equal cells, row by row: Flutter's `GridView`.
///
/// It scrolls, as Flutter's does - unless it is shrink-wrapped, told never to,
/// or inside another vertical scroller, where it is laid out in full. Every
/// cell is built; a grid long enough to need windowing is a list of rows.
///
/// A delegate that sizes columns by a maximum width has to know the grid's
/// width, which is the renderer's to say: the grid is drawn once against the
/// window's width and again when its own is reported - see [LayoutBuilder].
class GridView extends Widget {
  const GridView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required this.gridDelegate,
    this.children = const [],
  }) : itemBuilder = null,
       itemCount = null;

  const GridView.builder({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required this.gridDelegate,
    required NullableIndexedWidgetBuilder this.itemBuilder,
    this.itemCount,
  }) : children = const [];

  GridView.count({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required int crossAxisCount,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    this.children = const [],
  }) : gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
         crossAxisCount: crossAxisCount,
         mainAxisSpacing: mainAxisSpacing,
         crossAxisSpacing: crossAxisSpacing,
         childAspectRatio: childAspectRatio,
       ),
       itemBuilder = null,
       itemCount = null;

  GridView.extent({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    required double maxCrossAxisExtent,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    this.children = const [],
  }) : gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
         maxCrossAxisExtent: maxCrossAxisExtent,
         mainAxisSpacing: mainAxisSpacing,
         crossAxisSpacing: crossAxisSpacing,
         childAspectRatio: childAspectRatio,
       ),
       itemBuilder = null,
       itemCount = null;

  /// Accepted for Flutter's signature: the grid node lays out rows of
  /// columns, so a horizontal grid is drawn as a vertical one.
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final SliverGridDelegate gridDelegate;
  final List<Widget> children;
  final NullableIndexedWidgetBuilder? itemBuilder;
  final int? itemCount;

  @override
  WidgetNode _render(_Owner owner) {
    final delegate = gridDelegate;
    if (delegate is SliverGridDelegateWithFixedCrossAxisCount &&
        delegate.mainAxisExtent == null) {
      return _grid(
        owner,
        columns: delegate.crossAxisCount,
        crossAxisSpacing: delegate.crossAxisSpacing,
        mainAxisSpacing: delegate.mainAxisSpacing,
        aspectRatio: delegate.childAspectRatio,
      );
    }
    // The columns, or the cells' shape, depend on the width: measure it.
    return LayoutBuilder(
      builder: (context, constraints) => _NodeWidget((owner) {
        final outside = padding?._resolved;
        final width = math.max(
          0.0,
          constraints.maxWidth - (outside?.horizontal ?? 0),
        );
        final int columns;
        final double crossSpacing;
        final double mainSpacing;
        var ratio = 1.0;
        double? cellHeight;
        if (delegate is SliverGridDelegateWithMaxCrossAxisExtent) {
          crossSpacing = delegate.crossAxisSpacing;
          mainSpacing = delegate.mainAxisSpacing;
          ratio = delegate.childAspectRatio;
          cellHeight = delegate.mainAxisExtent;
          // Flutter's own arithmetic for this delegate.
          columns = math.max(
            1,
            (width / (delegate.maxCrossAxisExtent + crossSpacing)).ceil(),
          );
        } else {
          final fixed = delegate as SliverGridDelegateWithFixedCrossAxisCount;
          crossSpacing = fixed.crossAxisSpacing;
          mainSpacing = fixed.mainAxisSpacing;
          cellHeight = fixed.mainAxisExtent;
          columns = fixed.crossAxisCount;
        }
        if (cellHeight != null && cellHeight > 0) {
          final cellWidth = (width - crossSpacing * (columns - 1)) / columns;
          ratio = cellWidth > 0 ? cellWidth / cellHeight : 1;
        }
        return _grid(
          owner,
          columns: columns,
          crossAxisSpacing: crossSpacing,
          mainAxisSpacing: mainSpacing,
          aspectRatio: ratio,
        );
      }),
    )._render(owner);
  }

  WidgetNode _grid(
    _Owner owner, {
    required int columns,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required double aspectRatio,
  }) => _scroller(
    owner,
    axis: Axis.vertical,
    padding: padding,
    shrinkWrap: shrinkWrap,
    physics: physics,
    controller: controller,
    reverse: reverse,
    id: _idOf(key),
    content: () {
      final builder = itemBuilder;
      final cells = <WidgetNode>[];
      if (builder == null) {
        cells.addAll(_renderAll(children, owner));
      } else {
        final count = itemCount;
        final limit = count ?? ListView._unboundedLimit;
        for (var index = 0; index < limit; index++) {
          final cell = builder(owner._context(), index);
          if (cell == null) {
            if (count == null) break;
            continue;
          }
          cells.add(owner.inSlot(index, () => cell._render(owner)));
        }
      }
      return UIBuilder.grid(
        crossAxisCount: columns,
        spacing: crossAxisSpacing,
        runSpacing: mainAxisSpacing,
        childAspectRatio: aspectRatio,
        children: cells,
      );
    },
  );
}

/// Pull down to refresh: the scroller beneath gains the platform's gesture,
/// and its spinner stays while the future [onRefresh] returns is running.
///
/// It attaches to the first vertical scroller built below it - a
/// [SingleChildScrollView], a [GridView] or a [ListView], windowed or not.
class RefreshIndicator extends StatefulWidget {
  const RefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 2.5,
  });

  /// Flutter's refresh that looks native on each platform - the only kind
  /// there is here.
  const RefreshIndicator.adaptive({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.color,
    this.backgroundColor,
    this.strokeWidth = 2.5,
  });

  final Widget child;
  final Future<void> Function() onRefresh;

  /// Accepted and not carried: the spinner is the platform's own.
  final double displacement;
  final Color? color;
  final Color? backgroundColor;
  final double strokeWidth;

  @override
  State<RefreshIndicator> createState() => _RefreshIndicatorState();
}

class _RefreshIndicatorState extends State<RefreshIndicator> {
  bool _refreshing = false;

  /// Whether a scroller has taken the refresh in the build in progress.
  bool _claimed = false;

  void _start() {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    widget.onRefresh().whenComplete(() {
      if (!mounted) return;
      setState(() => _refreshing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    _claimed = false;
    return _RefreshScope(state: this, child: widget.child);
  }
}

// ---------------------------------------------------------------------------
// List rows.
// ---------------------------------------------------------------------------

/// Which side of a list tile its control sits on.
enum ListTileControlAffinity { leading, trailing, platform }

/// How a [ListTile] is laid out for its kind of list. Accepted for Flutter's
/// signature.
enum ListTileStyle { list, drawer }

/// A row of a list: a [title] over an optional [subtitle], between an
/// optional [leading] and [trailing] widget, in Material's metrics.
class ListTile extends Widget {
  const ListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine = false,
    this.dense,
    this.visualDensity,
    this.shape,
    this.style,
    this.selectedColor,
    this.iconColor,
    this.textColor,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.contentPadding,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.tileColor,
    this.selectedTileColor,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
  });
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;

  /// Makes room for a subtitle of two lines.
  final bool isThreeLine;

  /// A shorter row with smaller text.
  final bool? dense;
  final VisualDensity? visualDensity;
  final ShapeBorder? shape;
  final ListTileStyle? style;
  final Color? selectedColor;
  final Color? iconColor;
  final Color? textColor;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final EdgeInsetsGeometry? contentPadding;

  /// False greys the row and makes it deaf to taps.
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Draws the title and icons in the primary colour.
  final bool selected;
  final Color? tileColor;
  final Color? selectedTileColor;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;

  @override
  WidgetNode _render(_Owner owner) {
    final scheme = _themeOf(owner).colorScheme;
    final compact = dense ?? false;
    final lines = subtitle == null ? 1 : (isThreeLine ? 3 : 2);
    // Material 3's row heights, and the shorter ones a dense list uses.
    final minHeight = switch (lines) {
      1 => compact ? 48.0 : 56.0,
      2 => compact ? 64.0 : 72.0,
      _ => compact ? 76.0 : 88.0,
    };
    final accent = selected ? (selectedColor ?? scheme.primary) : null;
    final titleStyle = TextStyle(
      fontSize: compact ? 13 : 16,
      color: accent ?? textColor ?? scheme.onSurface,
    ).merge(titleTextStyle);
    final subtitleStyle = TextStyle(
      fontSize: compact ? 12 : 14,
      color: textColor ?? scheme.onSurfaceVariant,
    ).merge(subtitleTextStyle);
    final icons = accent ?? iconColor ?? scheme.onSurfaceVariant;
    final insets =
        contentPadding?._resolved ??
        // Material's own default is directional: 16 before the leading
        // widget and 24 after the trailing one, whichever side each is on.
        const EdgeInsetsDirectional.only(start: 16, end: 24)._resolved;
    final vertical = minVerticalPadding ?? (lines == 1 ? 8.0 : 8.0);
    final tap = onTap;
    final hold = onLongPress;
    final fill = selected ? (selectedTileColor ?? tileColor) : tileColor;
    final radius = shape is RoundedRectangleBorder
        ? (shape as RoundedRectangleBorder).borderRadius._resolved._uniform
        : null;
    return UIBuilder.box(
      minHeight: minHeight,
      // A tile is as wide as the list it is in, whatever is in it: the row
      // below needs that width for the title to take what is left of it.
      expand: owner._unboundedWidth ? null : 'width',
      padding: [
        insets.left,
        insets.top + vertical,
        insets.right,
        insets.bottom + vertical,
      ],
      // Centred on the start edge, which is the right in a tile that reads
      // from the right.
      alignment: AlignmentDirectional.centerStart._resolved._xy,
      color: fill?._hex,
      borderRadius: radius,
      opacity: enabled ? null : 0.38,
      onTap: tap == null || !enabled ? null : (_, _) => tap(),
      onLongPress: hold == null || !enabled ? null : (_, _) => hold(),
      ripple: enabled && (tap != null || hold != null),
      // The chosen row of a list of choices says so; its colour alone does
      // not reach a screen reader.
      selected: selected ? true : null,
      id: _idOf(key),
      child: UIBuilder.row(
        // The row is the tile's width, so the title takes what the leading
        // and trailing leave and the trailing sits at the far edge.
        mainAxisSize: 'max',
        spacing: horizontalTitleGap ?? 16,
        children: [
          if (leading != null)
            _withForeground(
              owner,
              icons,
              () => _renderChild(owner, leading!, 'leading'),
              style: TextStyle(color: scheme.onSurfaceVariant),
              iconSize: 24,
            ),
          UIBuilder.expanded(
            child: UIBuilder.column(
              crossAxisAlignment: 'start',
              mainAxisSize: 'min',
              children: [
                if (title != null)
                  _withTextStyle(
                    owner,
                    titleStyle,
                    () => _renderChild(owner, title!, 'title'),
                  ),
                if (subtitle != null)
                  _withTextStyle(
                    owner,
                    subtitleStyle,
                    () => _renderChild(owner, subtitle!, 'subtitle'),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            _withForeground(
              owner,
              icons,
              () => _renderChild(owner, trailing!, 'trailing'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              iconSize: 24,
            ),
        ],
      ),
    );
  }
}

/// A [ListTile] that opens to show [children] beneath it.
class ExpansionTile extends StatefulWidget {
  const ExpansionTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.onExpansionChanged,
    this.children = const [],
    this.trailing,
    this.initiallyExpanded = false,
    this.maintainState = false,
    this.tilePadding,
    this.expandedCrossAxisAlignment,
    this.expandedAlignment,
    this.childrenPadding,
    this.backgroundColor,
    this.collapsedBackgroundColor,
    this.textColor,
    this.collapsedTextColor,
    this.iconColor,
    this.collapsedIconColor,
    this.shape,
    this.collapsedShape,
    this.dense,
    this.enabled = true,
  });
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final ValueChanged<bool>? onExpansionChanged;
  final List<Widget> children;

  /// Replaces the arrow that shows which way the tile will go.
  final Widget? trailing;
  final bool initiallyExpanded;

  /// Keeps the children's state while the tile is closed.
  final bool maintainState;
  final EdgeInsetsGeometry? tilePadding;
  final CrossAxisAlignment? expandedCrossAxisAlignment;

  /// Accepted and not consulted; see [expandedCrossAxisAlignment].
  final Alignment? expandedAlignment;
  final EdgeInsetsGeometry? childrenPadding;
  final Color? backgroundColor;
  final Color? collapsedBackgroundColor;
  final Color? textColor;
  final Color? collapsedTextColor;
  final Color? iconColor;
  final Color? collapsedIconColor;
  final ShapeBorder? shape;
  final ShapeBorder? collapsedShape;
  final bool? dense;
  final bool enabled;

  @override
  State<ExpansionTile> createState() => _ExpansionTileState();
}

class _ExpansionTileState extends State<ExpansionTile> {
  late bool _open = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _open = !_open);
    widget.onExpansionChanged?.call(_open);
  }

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: widget.childrenPadding ?? EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            widget.expandedCrossAxisAlignment ?? CrossAxisAlignment.center,
        children: widget.children,
      ),
    );
    final fill = _open
        ? widget.backgroundColor
        : widget.collapsedBackgroundColor;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: widget.key is ValueKey ? widget.key : null,
          leading: widget.leading,
          title: widget.title,
          subtitle: widget.subtitle,
          dense: widget.dense,
          enabled: widget.enabled,
          contentPadding: widget.tilePadding,
          textColor: _open ? widget.textColor : widget.collapsedTextColor,
          iconColor: _open ? widget.iconColor : widget.collapsedIconColor,
          trailing:
              widget.trailing ??
              Icon(_open ? Icons.expand_less : Icons.expand_more),
          onTap: _toggle,
        ),
        if (_open)
          body
        else if (widget.maintainState)
          Offstage(child: body),
      ],
    );
    return fill == null ? content : ColoredBox(color: fill, child: content);
  }
}

/// A [ListTile] with a [Checkbox]; tapping anywhere on the row toggles it.
class CheckboxListTile extends StatelessWidget {
  const CheckboxListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.isThreeLine = false,
    this.dense,
    this.selected = false,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.contentPadding,
    this.tristate = false,
    this.activeColor,
    this.checkColor,
    this.tileColor,
    this.enabled,
  });
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title;
  final Widget? subtitle;

  /// The widget on the other side of the row from the checkbox.
  final Widget? secondary;
  final bool isThreeLine;
  final bool? dense;
  final bool selected;
  final ListTileControlAffinity controlAffinity;
  final EdgeInsetsGeometry? contentPadding;
  final bool tristate;
  final Color? activeColor;
  final Color? checkColor;
  final Color? tileColor;
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final changed = (enabled ?? true) ? onChanged : null;
    final control = Checkbox(
      key: key is ValueKey ? key : null,
      value: value,
      tristate: tristate,
      onChanged: changed,
      activeColor: activeColor,
      checkColor: checkColor,
      labelledBy: title,
    );
    final leads = controlAffinity == ListTileControlAffinity.leading;
    return ListTile(
      leading: leads ? control : secondary,
      title: title,
      subtitle: subtitle,
      trailing: leads ? secondary : control,
      isThreeLine: isThreeLine,
      dense: dense,
      selected: selected,
      enabled: changed != null,
      contentPadding: contentPadding,
      tileColor: tileColor,
      onTap: changed == null ? null : () => changed(!(value ?? false)),
    );
  }
}

/// A [ListTile] with a [Switch]; tapping anywhere on the row flips it.
class SwitchListTile extends StatelessWidget {
  const SwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.isThreeLine = false,
    this.dense,
    this.selected = false,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.contentPadding,
    this.activeColor,
    this.activeThumbColor,
    this.tileColor,
  });

  const SwitchListTile.adaptive({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.isThreeLine = false,
    this.dense,
    this.selected = false,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.contentPadding,
    this.activeColor,
    this.activeThumbColor,
    this.tileColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool isThreeLine;
  final bool? dense;
  final bool selected;
  final ListTileControlAffinity controlAffinity;
  final EdgeInsetsGeometry? contentPadding;
  final Color? activeColor;
  final Color? activeThumbColor;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    final control = Switch(
      key: key is ValueKey ? key : null,
      value: value,
      onChanged: changed,
      activeColor: activeColor,
      activeThumbColor: activeThumbColor,
      labelledBy: title,
    );
    final leads = controlAffinity == ListTileControlAffinity.leading;
    return ListTile(
      leading: leads ? control : secondary,
      title: title,
      subtitle: subtitle,
      trailing: leads ? secondary : control,
      isThreeLine: isThreeLine,
      dense: dense,
      selected: selected,
      enabled: changed != null,
      contentPadding: contentPadding,
      tileColor: tileColor,
      onTap: changed == null ? null : () => changed(!value),
    );
  }
}

/// A [ListTile] with a [Radio]; tapping anywhere on the row chooses it.
class RadioListTile<T> extends StatelessWidget {
  const RadioListTile({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.toggleable = false,
    this.title,
    this.subtitle,
    this.secondary,
    this.isThreeLine = false,
    this.dense,
    this.selected = false,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.contentPadding,
    this.activeColor,
    this.tileColor,
  });
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool toggleable;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool isThreeLine;
  final bool? dense;
  final bool selected;
  final ListTileControlAffinity controlAffinity;
  final EdgeInsetsGeometry? contentPadding;
  final Color? activeColor;
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final changed = onChanged;
    final control = Radio<T>(
      key: key is ValueKey ? key : null,
      value: value,
      groupValue: groupValue,
      onChanged: changed,
      toggleable: toggleable,
      activeColor: activeColor,
      labelledBy: title,
    );
    // A radio leads its row unless told otherwise, as in Flutter.
    final trails = controlAffinity == ListTileControlAffinity.trailing;
    return ListTile(
      leading: trails ? secondary : control,
      title: title,
      subtitle: subtitle,
      trailing: trails ? control : secondary,
      isThreeLine: isThreeLine,
      dense: dense,
      selected: selected,
      enabled: changed != null,
      contentPadding: contentPadding,
      tileColor: tileColor,
      onTap: changed == null
          ? null
          : () => changed(toggleable && value == groupValue ? null : value),
    );
  }
}
