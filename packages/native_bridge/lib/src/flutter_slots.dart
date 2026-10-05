/// The registry behind `FlutterSlot` nodes: which Flutter widget belongs in
/// which slot, and where each slot came to rest on screen.
///
/// Pure Dart, with no Flutter import, because it is exported from the
/// web-safe core: the app registers a builder while it builds its tree, on
/// any target, and only the Flutter side ever calls one. That is why a builder
/// is held as a plain [Object] here - the type that says "a function from a
/// BuildContext to a Widget" lives in `package:dart_not_native/flutter_slot.dart`,
/// next to the code that can use it.
library;

import 'listenable.dart';
import 'ui_renderer.dart';

/// Where a slot is, in logical pixels from the top left of the Flutter view.
///
/// [visible] is false while the hole is scrolled out of sight or covered; the
/// rectangle is then the last one known, kept so the widget comes back where
/// it left.
class FlutterSlotRect {
  const FlutterSlotRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.visible = true,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is FlutterSlotRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(x, y, width, height, visible);

  @override
  String toString() =>
      'FlutterSlotRect($x, $y, $width x $height${visible ? '' : ', hidden'})';
}

/// The slots of the running app.
///
/// A slot lives for as long as the tree keeps asking for it. The app registers
/// the builder every time it builds the node (`flutterSlotNode` does), and the
/// renderer that then draws the tree calls [sync] with it: a slot that
/// renderer drew last time and that is missing now is dropped, builder and
/// rectangle both. Nothing has to be unregistered by hand, the same way
/// nothing in a tree has to be removed by hand.
///
/// Listeners hear about every change - a slot arriving, leaving, getting a
/// new builder, or moving - which is what `FlutterSlotLayer` repaints on.
class FlutterSlots extends ChangeNotifier {
  FlutterSlots();

  /// The registry every part of the framework shares.
  static final FlutterSlots instance = FlutterSlots();

  final Map<String, Object> _builders = {};
  final Map<String, FlutterSlotRect> _rects = {};

  /// The slots each renderer drew in its last tree, by renderer.
  ///
  /// Kept per renderer because an app can have more than one on screen - a
  /// Flutter host pushed over another - and one of them rendering must not
  /// drop the slots of the other.
  final Map<Object, Set<String>> _drawn = {};

  /// The registered slot ids, in the order they were first registered.
  List<String> get slotIds => List.unmodifiable(_builders.keys);

  /// Whether a builder is registered under [slotId].
  bool isRegistered(String slotId) => _builders.containsKey(slotId);

  /// The builder registered under [slotId], or null.
  ///
  /// An [Object] for the reason the library comment gives; the Flutter side
  /// checks that it is a `Widget Function(BuildContext)` before calling it.
  Object? builderOf(String slotId) => _builders[slotId];

  /// Registers [builder] under [slotId], replacing the one before it.
  ///
  /// Called on every build, usually with a fresh closure; listeners are told
  /// each time the closure is a different one, since it may well close over
  /// different state.
  void register(String slotId, Object builder) {
    if (identical(_builders[slotId], builder)) return;
    _builders[slotId] = builder;
    notifyListeners();
  }

  /// Drops [slotId] and its rectangle. Dropping one that is not there does
  /// nothing.
  void unregister(String slotId) {
    final hadBuilder = _builders.remove(slotId) != null;
    final hadRect = _rects.remove(slotId) != null;
    for (final drawn in _drawn.values) {
      drawn.remove(slotId);
    }
    if (hadBuilder || hadRect) notifyListeners();
  }

  /// Where [slotId] was last reported to be, or null before any report.
  FlutterSlotRect? rectOf(String slotId) => _rects[slotId];

  /// Records where [slotId] is.
  void setRect(String slotId, FlutterSlotRect rect) {
    if (_rects[slotId] == rect) return;
    _rects[slotId] = rect;
    notifyListeners();
  }

  /// Records the payload of a [RendererEvents.slotRect] event:
  /// `{slotId, x, y, width, height, visible}`.
  ///
  /// Answers false, changing nothing, for a payload with no slot id or with a
  /// measurement missing: a rectangle half made up would put the widget
  /// somewhere the platform never said.
  bool reportRect(Map<String, dynamic> data) {
    final slotId = data['slotId'];
    final x = data['x'];
    final y = data['y'];
    final width = data['width'];
    final height = data['height'];
    if (slotId is! String ||
        x is! num ||
        y is! num ||
        width is! num ||
        height is! num) {
      return false;
    }
    setRect(
      slotId,
      FlutterSlotRect(
        x: x.toDouble(),
        y: y.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
        visible: data['visible'] != false,
      ),
    );
    return true;
  }

  /// Ends a build pass: [owner] - a renderer - has just been given [tree].
  ///
  /// Every slot [owner] drew last time and that [tree] no longer holds is
  /// dropped. A slot registered but in no tree yet is left alone: it was
  /// registered for a render that is still on its way.
  void sync(Object owner, WidgetNode tree) {
    final now = slotIdsIn(tree);
    final before = _drawn[owner] ?? const <String>{};
    var changed = false;
    for (final slotId in before.difference(now)) {
      changed = _builders.remove(slotId) != null || changed;
      changed = _rects.remove(slotId) != null || changed;
    }
    if (now.isEmpty) {
      _drawn.remove(owner);
    } else {
      _drawn[owner] = now;
    }
    if (changed) notifyListeners();
  }

  /// Drops every slot [owner] drew: the renderer is going away.
  void release(Object owner) {
    final drawn = _drawn.remove(owner);
    if (drawn == null) return;
    var changed = false;
    for (final slotId in drawn) {
      changed = _builders.remove(slotId) != null || changed;
      changed = _rects.remove(slotId) != null || changed;
    }
    if (changed) notifyListeners();
  }

  /// Drops everything. For tests, and for an app that tears itself down.
  void clear() {
    if (_builders.isEmpty && _rects.isEmpty && _drawn.isEmpty) return;
    _builders.clear();
    _rects.clear();
    _drawn.clear();
    notifyListeners();
  }

  /// The slot ids of every `FlutterSlot` node in [tree].
  static Set<String> slotIdsIn(WidgetNode tree) {
    final found = <String>{};
    void walk(WidgetNode node) {
      if (node.type == 'FlutterSlot') {
        final slotId = node.props['slotId'];
        if (slotId is String) found.add(slotId);
      }
      for (final child in node.children ?? const <WidgetNode>[]) {
        walk(child);
      }
    }

    walk(tree);
    return found;
  }
}
