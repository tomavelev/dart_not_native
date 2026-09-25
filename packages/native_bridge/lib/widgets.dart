/// A Flutter-shaped widget layer over the `WidgetNode` protocol.
///
/// The framework renders a `WidgetNode` tree through a native Android/iOS view
/// renderer or the web DOM - none of which link the Flutter engine. This file
/// gives that tree a Flutter-looking face: `StatelessWidget`, `StatefulWidget`,
/// `State.setState`, `Scaffold`, `Text`, `Column`, `FloatingActionButton` and
/// friends, so an example reads like a normal Flutter app and differs from one
/// only in its import (and the [runApp] entry point).
///
/// ```dart
/// import 'package:dart_not_native/widgets.dart';
///
/// void main() => runApp(const CounterApp());
///
/// class CounterApp extends StatefulWidget {
///   const CounterApp({super.key});
///   @override
///   State<CounterApp> createState() => _CounterState();
/// }
///
/// class _CounterState extends State<CounterApp> {
///   int _count = 0;
///   @override
///   Widget build(BuildContext context) => Scaffold(
///         appBar: AppBar(title: const Text('Counter')),
///         body: Center(child: Text('$_count')),
///         floatingActionButton: FloatingActionButton(
///           onPressed: () => setState(() => _count++),
///           child: const Icon(Icons.add),
///         ),
///       );
/// }
/// ```
///
/// The mapping is honest about its limits: the node vocabulary is a subset of
/// Flutter's, so a property the protocol has no place for (a Column's
/// `mainAxisAlignment`) is taken as far as it goes and no further. Everything
/// here is pure Dart; nothing imports Flutter.
///
/// `State` follows Flutter's identity rule: a [Key] if the widget has one, its
/// place in the tree otherwise - see [_Owner].
library;

// Icons mirror Flutter's snake_case names (Icons.add_task, Icons.more_vert) on
// purpose, so an example reads identically to a Flutter one.
// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'forms/form.dart';
import 'i18n/translations.dart';
import 'run_app.dart';
import 'src/icon_data.dart';
import 'src/icons.dart';
import 'src/listenable.dart';

export 'src/app_theme.dart' show AppTheme, AppThemeMode;
// The icons an app names, generated from Flutter's own table.
export 'src/icon_data.dart' show IconData;
export 'src/icons.dart' show Icons;
export 'src/frame_probe.dart' show FrameProbe;
export 'src/render_error.dart' show RenderError, RenderErrorKind;
export 'src/frame_stats.dart' show FrameStats;
export 'src/listenable.dart'
    show
        VoidCallback,
        Listenable,
        ValueListenable,
        ChangeNotifier,
        ValueNotifier;
export 'forms/form.dart'
    show Form, FormField, FormBuilder, FieldState, FieldChange;
export 'forms/validators.dart';

// ---------------------------------------------------------------------------
// Foundation: keys, context, the widget/state model and the render owner.
// ---------------------------------------------------------------------------

/// Identity for a widget across rebuilds. A [ValueKey] doubles as the node `id`
/// the renderers and tests address a widget by.
abstract class Key {
  const Key();
}

class ValueKey<T> extends Key {
  const ValueKey(this.value);
  final T value;
  @override
  bool operator ==(Object other) =>
      other is ValueKey<T> && other.value == value;
  @override
  int get hashCode => Object.hash(T, value);
}

String? _idOf(Key? key) => key is ValueKey ? '${key.value}' : null;

/// The handle a build is given. Minimal by design - it exists so signatures
/// read like Flutter's; the real work lives on the [_Owner] it points at.
abstract class BuildContext {
  /// The nearest [InheritedWidget] of type [T] above this one, or null.
  ///
  /// Flutter's name, and Flutter's meaning minus the bookkeeping: there, the
  /// "depend on" part registers this widget to be rebuilt when that one
  /// changes. Here a change rebuilds from the root anyway, so the dependency
  /// is the rebuild, and the two spellings do the same thing.
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// The same lookup without the dependency, as in Flutter.
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>();
}

/// A value made visible to everything built below it.
///
/// Subclass it to hand a subtree something it would otherwise have to be
/// passed - the app's theme, a signed-in user - and read it back with
/// `context.dependOnInheritedWidgetOfExactType<T>()`, as in Flutter:
///
/// ```dart
/// class Config extends InheritedWidget {
///   const Config({required this.apiUrl, required super.child});
///   final String apiUrl;
///   static Config of(BuildContext context) =>
///       context.dependOnInheritedWidgetOfExactType<Config>()!;
///   @override
///   bool updateShouldNotify(Config old) => old.apiUrl != apiUrl;
/// }
/// ```
///
/// [updateShouldNotify] is accepted for compatibility and not consulted: this
/// framework rebuilds from the root and diffs the tree, so a subtree is
/// redrawn either way and a renderer patches what actually moved. State that
/// changes often and is watched from far away is better held in a
/// [ChangeNotifier] than pushed down a tree.
abstract class InheritedWidget extends Widget {
  const InheritedWidget({super.key, required this.child});

  final Widget child;

  /// Whether a change here should rebuild the widgets that read it. Accepted
  /// for compatibility; see the class doc.
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => true;

  @override
  WidgetNode _render(_Owner owner) => owner._withInherited(
    this,
    () => owner.inSlot('child', () => child._render(owner)),
  );
}

/// Anything that can turn itself into a [WidgetNode].
abstract class Widget {
  const Widget({this.key});
  final Key? key;
  WidgetNode _render(_Owner owner);
}

/// A widget whose look is a pure function of its inputs.
abstract class StatelessWidget extends Widget {
  const StatelessWidget({super.key});
  Widget build(BuildContext context);
  @override
  WidgetNode _render(_Owner owner) => build(owner)._render(owner);
}

/// A widget with mutable [State] that survives rebuilds.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  State createState();
  @override
  WidgetNode _render(_Owner owner) => owner._renderStateful(this);
}

/// Mutable state for a [StatefulWidget]. [setState] mutates then asks the host
/// to rebuild, exactly like Flutter.
abstract class State<T extends StatefulWidget> {
  _Owner? _owner;
  StatefulWidget? _widget;

  T get widget => _widget as T;
  BuildContext get context => _owner!;
  bool get mounted => _owner != null;

  void initState() {}
  void dispose() {}

  void setState(void Function() fn) {
    fn();
    _owner?._requestRebuild();
  }

  Widget build(BuildContext context);
}

/// Rebuilds its subtree whenever [listenable] changes.
///
/// The way a screen reads state that does not belong to it - a store several
/// routes share (see [ChangeNotifier]). While the builder is in the tree the
/// app follows the listenable; once it is gone, it stops.
///
/// ```dart
/// ListenableBuilder(
///   listenable: cart,
///   builder: (context, _) => Text('${cart.items.length} in cart'),
/// )
/// ```
///
/// [child] is built once and handed back to [builder], for a subtree that does
/// not depend on the listenable.
class ListenableBuilder extends Widget {
  const ListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) {
    owner._watch(listenable);
    return builder(owner, child)._render(owner);
  }
}

/// [ListenableBuilder] for a [ValueListenable], handing the value to [builder].
///
/// ```dart
/// final favourites = ValueNotifier<Set<String>>({});
///
/// ValueListenableBuilder<Set<String>>(
///   valueListenable: favourites,
///   builder: (context, ids, _) => Text('${ids.length} favourites'),
/// )
/// ```
class ValueListenableBuilder<T> extends Widget {
  const ValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  final ValueListenable<T> valueListenable;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  WidgetNode _render(_Owner owner) {
    owner._watch(valueListenable);
    return builder(owner, valueListenable.value, child)._render(owner);
  }
}

/// Walks the widget tree into a [WidgetNode] tree and keeps each
/// [StatefulWidget]'s [State] alive between builds.
///
/// State is kept by identity - a widget's [Key] if it has one, otherwise where
/// it sits: the path of slots from the root (a child's index in a Column, the
/// `body` of a Scaffold, the route or dialog being drawn) and its type. Two
/// counters side by side are therefore two counters, and a screen drawn on one
/// route does not inherit the state of the same screen on another.
///
/// This is Flutter's own rule, and it has Flutter's consequence: a keyless
/// widget *is* its position, so a row that moves - a list that reorders, an
/// item inserted above it - hands its state to whatever now stands where it
/// stood. Give widgets that move a [Key], which is an identity the app chose
/// and one the framework will follow wherever it goes.
class _Owner implements BuildContext {
  _Owner(this.root, this.host);

  final Widget root;
  final _WidgetHost host;
  final Map<Object, State> _states = {};
  Set<Object> _activePass = {};

  /// The inherited widgets above whatever is being built right now, oldest
  /// first. Building is depth-first and synchronous, so this list *is* the
  /// ancestor chain - no parent pointers needed.
  final List<InheritedWidget> _inherited = [];

  /// Builds [body] with [widget] visible to everything inside it.
  T _withInherited<T>(InheritedWidget widget, T Function() body) {
    _inherited.add(widget);
    try {
      return body();
    } finally {
      _inherited.removeLast();
    }
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      getInheritedWidgetOfExactType<T>();

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() {
    // The nearest one wins, so search from the inside out.
    for (var i = _inherited.length - 1; i >= 0; i--) {
      final candidate = _inherited[i];
      if (candidate is T) return candidate;
    }
    return null;
  }

  /// Where the build currently is: a slot per step down the tree - a child's
  /// index in a Column, the `body` of a Scaffold, the route being drawn - so a
  /// widget without a [Key] can be told apart from another of its type
  /// somewhere else in the tree.
  final List<Object> _slots = [];

  /// How many widgets of each type have been built at each path this pass,
  /// which separates siblings a parent renders without a slot of their own.
  final Map<String, int> _atPath = {};

  /// Renders [body] one step deeper, at [slot].
  T inSlot<T>(Object slot, T Function() body) {
    _slots.add(slot);
    try {
      return body();
    } finally {
      _slots.removeLast();
    }
  }

  /// The identity of a keyless widget of [type] here: its path, and which one
  /// it is if several of its type are built at the same path.
  String _positionId(Type type) {
    final path = '${_slots.join('/')}/$type';
    final seen = _atPath[path] ?? 0;
    _atPath[path] = seen + 1;
    return '$path#$seen';
  }

  /// The listenables the last build depended on, and the listener watching
  /// each. A subscription belongs to the tree rather than to a widget: this
  /// framework rebuilds from the root and diffs, so one listener per
  /// listenable is all a rebuild needs - and it sidesteps the identity
  /// problem two keyless builders of the same type would otherwise have.
  final Map<Listenable, VoidCallback> _watched = {};
  Set<Listenable> _watchedThisPass = {};

  /// Rebuilds while [listenable] is in the tree.
  void _watch(Listenable listenable) {
    _watchedThisPass.add(listenable);
    if (_watched.containsKey(listenable)) return;
    void onChange() => _requestRebuild();
    listenable.addListener(onChange);
    _watched[listenable] = onChange;
  }

  /// Lets go of every listenable the build just finished did not use.
  void _pruneWatched() {
    for (final listenable in _watched.keys.toList()) {
      if (_watchedThisPass.contains(listenable)) continue;
      listenable.removeListener(_watched.remove(listenable)!);
    }
  }

  /// Lets go of everything, for a host tearing the app down.
  void disposeWatched() {
    for (final entry in _watched.entries) {
      entry.key.removeListener(entry.value);
    }
    _watched.clear();
  }

  /// The dialogs and sheets open over the app, oldest first. Each is state: it
  /// is in the tree while it is open and drops out when it is dismissed.
  final List<_OverlayEntry> _overlays = [];

  /// The snackbar showing, if any, and a counter so each new one is a fresh
  /// snackbar rather than the last rendered again.
  SnackBar? _snackBar;
  int _snackBarSeq = 0;

  /// The router of the routed [MaterialApp] mounted below, if any, so
  /// Navigator.pushNamed/pop reach it.
  NavigationApp? routerNav;

  /// The overlay being built right now, so a dialog can bind its dismiss to the
  /// entry it belongs to.
  _OverlayEntry? _buildingOverlay;

  WidgetNode buildRoot() {
    final before = _states.keys.toSet();
    _activePass = {};
    _watchedThisPass = {};
    _atPath.clear();
    _slots.clear();
    _inherited.clear();
    final root = this.root._render(this);
    for (final gone in before.difference(_activePass)) {
      _states.remove(gone)?.dispose();
    }
    final overlays = <WidgetNode>[];
    for (final entry in List.of(_overlays)) {
      _buildingOverlay = entry;
      if (entry.kind == _OverlayKind.dialog) {
        overlays.add(inSlot(entry.id, () => entry.build(this)._render(this)));
      } else {
        overlays.add(
          UIBuilder.bottomSheet(
            id: entry.id,
            content: [inSlot(entry.id, () => entry.build(this)._render(this))],
            onDismiss: () => _dismiss(entry, null),
          ),
        );
      }
      _buildingOverlay = null;
    }
    final snackBar = _snackBar;
    if (snackBar != null) {
      final action = snackBar.action;
      overlays.add(
        UIBuilder.snackbar(
          id: 'snackbar_$_snackBarSeq',
          message: _stringOf(snackBar.content, this) ?? '',
          actionLabel: action?.label,
          onAction: action == null
              ? null
              : () {
                  _snackBar = null;
                  action.onPressed();
                  _requestRebuild();
                },
          duration: snackBar.duration,
          onDismiss: () {
            _snackBar = null;
            _requestRebuild();
          },
        ),
      );
    }
    // After the overlays too: a dialog watching a listenable is as much a part
    // of this build as the screen behind it.
    _pruneWatched();
    return overlays.isEmpty
        ? root
        : UIBuilder.overlay(child: root, overlays: overlays);
  }

  Future<T?> pushOverlay<T>(
    _OverlayKind kind,
    Widget Function(BuildContext) build,
  ) {
    final entry = _OverlayEntry(kind, build);
    _overlays.add(entry);
    _requestRebuild();
    return entry.completer.future.then((value) => value as T?);
  }

  void _dismiss(_OverlayEntry entry, Object? result) {
    if (_overlays.remove(entry) && !entry.completer.isCompleted) {
      entry.completer.complete(result);
    }
    _requestRebuild();
  }

  void popOverlay([Object? result]) {
    if (_overlays.isNotEmpty) _dismiss(_overlays.last, result);
  }

  void showSnackBar(SnackBar snackBar) {
    _snackBar = snackBar;
    _snackBarSeq++;
    _requestRebuild();
  }

  WidgetNode _renderStateful(StatefulWidget widget) {
    // A Key is an identity the app chose, and it travels with the widget: keep
    // it wherever the widget moves to. Without one, the widget *is* its place
    // in the tree - the same rule Flutter follows, and the reason two of a
    // type side by side no longer share one State.
    final id = widget.key ?? _positionId(widget.runtimeType);
    _activePass.add(id);
    var state = _states[id];
    if (state == null) {
      state = widget.createState()
        .._owner = this
        .._widget = widget;
      _states[id] = state;
      state.initState();
    } else {
      state._widget = widget;
    }
    // Its subtree hangs below it, so a child of one instance cannot be
    // mistaken for the same child of another.
    return inSlot(id, () => state!.build(this)._render(this));
  }

  void _requestRebuild() => host.render();
}

/// The [NativeUIApp] the framework actually mounts; its [build] is the widget
/// tree converted to nodes, run inside the app's binding scope so `onPressed`
/// and `onChanged` callbacks register themselves.
class _WidgetHost extends NativeUIApp {
  _WidgetHost(Widget root, {AppTheme theme = AppTheme.fallback}) {
    // The root is wrapped rather than the app wrapping it, so Theme.of works
    // in any screen without every app remembering to provide one.
    _owner = _Owner(Theme(data: theme, child: root), this);
  }
  late final _Owner _owner;

  @override
  WidgetNode build() => _owner.buildRoot();

  @override
  void unmount() {
    // A store outlives the app that showed it, so the listeners have to go;
    // otherwise a torn-down screen is still asked to rebuild.
    _owner.disposeWatched();
    super.unmount();
  }
}

/// Wraps [widget] as the [NativeUIApp] the framework mounts. [runApp] uses it;
/// tests use it to drive a widget-style app on an in-memory renderer, the same
/// way they drive a hand-written [NativeUIApp].
NativeUIApp hostApp(Widget widget, {AppTheme theme = AppTheme.fallback}) =>
    _WidgetHost(widget, theme: theme);

/// Mount [app] and render it through the platform's own views (the web DOM on
/// web). The one line of an example that a real Flutter app writes differently.
Future<void> runApp(
  Widget app, {
  bool nativeViews = true,
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
}) => runNativeApp(
  hostApp(app, theme: appTheme),
  nativeViews: nativeViews,
  title: title,
  appTheme: appTheme,
  debugShowRenderErrors: debugShowRenderErrors,
);

// ---------------------------------------------------------------------------
// Overlays: showDialog / showModalBottomSheet / ScaffoldMessenger, backed by
// the host's overlay stack. Each returns a Future that completes when the
// overlay is dismissed - by Navigator.pop, a tap on the scrim or the back
// gesture - exactly like Flutter's.
// ---------------------------------------------------------------------------

enum _OverlayKind { dialog, sheet }

class _OverlayEntry {
  _OverlayEntry(this.kind, this.build);
  final _OverlayKind kind;
  final Widget Function(BuildContext) build;
  final Completer<Object?> completer = Completer<Object?>();
  final String id = 'overlay_${_nextOverlayId++}';
}

int _nextOverlayId = 0;

/// Shows a modal dialog (usually an [AlertDialog]) over the app.
Future<T?> showDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) => (context as _Owner).pushOverlay<T>(_OverlayKind.dialog, builder);

/// Shows a modal sheet rising from the bottom edge.
Future<T?> showModalBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) => (context as _Owner).pushOverlay<T>(_OverlayKind.sheet, builder);

/// Navigates the routed [MaterialApp] and dismisses overlays, like Flutter's
/// `Navigator.of(context)`.
class Navigator {
  const Navigator._(this._owner);
  final _Owner _owner;
  static Navigator of(BuildContext context) => Navigator._(context as _Owner);

  /// Closes the topmost overlay if one is open, otherwise pops the route.
  void pop([Object? result]) {
    if (_owner._overlays.isNotEmpty) {
      _owner.popOverlay(result);
      return;
    }
    _owner.routerNav?.goBack();
  }

  /// Navigates to a named route (a path, which may carry parameters).
  Future<void> pushNamed(String routeName) async {
    await _owner.routerNav?.navigate(routeName);
  }

  String get currentPath => _owner.routerNav?.currentPath ?? '/';
  List<String> get history => _owner.routerNav?.history ?? const [];
  bool get canGoBack => _owner.routerNav?.router.state.canGoBack ?? false;
  bool get canGoForward => _owner.routerNav?.router.state.canGoForward ?? false;
}

/// Shows snackbars, like Flutter's `ScaffoldMessenger.of(context)`.
class ScaffoldMessenger {
  const ScaffoldMessenger._(this._owner);
  final _Owner _owner;
  static ScaffoldMessenger of(BuildContext context) =>
      ScaffoldMessenger._(context as _Owner);
  void showSnackBar(SnackBar snackBar) => _owner.showSnackBar(snackBar);
}

/// A transient message along the bottom edge. [content] is usually a [Text];
/// an optional [action] adds one button (an "Undo").
class SnackBar {
  const SnackBar({
    required this.content,
    this.action,
    this.duration = const Duration(seconds: 4),
  });
  final Widget content;
  final SnackBarAction? action;
  final Duration duration;
}

class SnackBarAction {
  const SnackBarAction({required this.label, required this.onPressed});
  final String label;
  final void Function() onPressed;
}

/// A Material dialog: a [title], some [content] and a row of [actions].
class AlertDialog extends Widget {
  const AlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  @override
  WidgetNode _render(_Owner owner) {
    final entry = owner._buildingOverlay;
    return UIBuilder.dialog(
      title: _stringOf(title, owner),
      content: content == null
          ? const []
          : [owner.inSlot('content', () => content!._render(owner))],
      actions: _renderAll(actions, owner),
      onDismiss: entry == null ? null : () => owner._dismiss(entry, null),
      id: _idOf(key),
    );
  }
}

// ---------------------------------------------------------------------------
// Styling value types.
// ---------------------------------------------------------------------------

/// A 0xAARRGGBB color, like Flutter's. Alpha is dropped when handed to the
/// renderers, which take `#RRGGBB`.
class Color {
  const Color(this.value);

  /// A color from a `#RRGGBB` (or `#AARRGGBB`) string, for design-system tokens
  /// that are hex strings.
  factory Color.fromHex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  final int value;
  String get _hex => '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  @override
  bool operator ==(Object other) => other is Color && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// The handful of Material colors the examples reach for.
abstract final class Colors {
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFF44336);
  static const Color green = Color(0xFF4CAF50);
  static const Color blue = Color(0xFF2196F3);
  static const Color orange = Color(0xFFFF9800);
  static const Color amber = Color(0xFFFFC107);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color blueGrey = Color(0xFF607D8B);
  static const Color deepPurple = Color(0xFF673AB7);
}

class FontWeight {
  const FontWeight._(this.value);
  final int value;
  static const FontWeight normal = FontWeight._(400);
  static const FontWeight bold = FontWeight._(700);
  static const FontWeight w300 = FontWeight._(300);
  static const FontWeight w400 = FontWeight._(400);
  static const FontWeight w500 = FontWeight._(500);
  static const FontWeight w600 = FontWeight._(600);
  static const FontWeight w700 = FontWeight._(700);
}

class TextDecoration {
  const TextDecoration._(this._name);
  final String _name;
  static const TextDecoration none = TextDecoration._('none');
  static const TextDecoration lineThrough = TextDecoration._('lineThrough');
  static const TextDecoration underline = TextDecoration._('underline');
}

class TextStyle {
  const TextStyle({
    this.fontSize,
    this.fontWeight,
    this.color,
    this.decoration,
  });
  final double? fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextDecoration? decoration;
}

/// Uniform-only for now: the node protocol's padding is a single value, so an
/// Space around something, one edge at a time - Flutter's own shape, and the
/// protocol carries all four.
class EdgeInsets {
  const EdgeInsets.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value;

  const EdgeInsets.symmetric({double horizontal = 0, double vertical = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical;

  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  const EdgeInsets.fromLTRB(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Whether every edge is the same, which is how the node is written.
  bool get isUniform => left == top && top == right && right == bottom;
}

class MainAxisAlignment {
  const MainAxisAlignment._(this._name);
  final String _name;
  static const MainAxisAlignment start = MainAxisAlignment._('start');
  static const MainAxisAlignment center = MainAxisAlignment._('center');
  static const MainAxisAlignment end = MainAxisAlignment._('end');
  static const MainAxisAlignment spaceBetween = MainAxisAlignment._(
    'spaceBetween',
  );
}

class CrossAxisAlignment {
  const CrossAxisAlignment._(this._name);
  final String _name;
  static const CrossAxisAlignment start = CrossAxisAlignment._('start');
  static const CrossAxisAlignment center = CrossAxisAlignment._('center');
  static const CrossAxisAlignment end = CrossAxisAlignment._('end');
  static const CrossAxisAlignment stretch = CrossAxisAlignment._('stretch');
}

// ---------------------------------------------------------------------------
// Icons.
// ---------------------------------------------------------------------------

/// The Material icons the examples use, by their real codepoints so the native

class Icon extends Widget {
  const Icon(this.icon, {super.key, this.color, this.size});
  final IconData icon;
  final Color? color;
  final double? size;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.text(
    String.fromCharCode(icon.codePoint),
    fontSize: size,
    color: color?._hex,
    id: _idOf(key),
  );
}

// ---------------------------------------------------------------------------
// App scaffolding.
// ---------------------------------------------------------------------------

/// Builds the page for a route, given its parameters (e.g. the `:id` in
/// `/users/:id`).
typedef RouteWidgetBuilder =
    Widget Function(BuildContext context, Map<String, dynamic> params);

/// The app shell. Pass [home] for a single-screen app, or [initialRoute] and
/// [routes] for a routed one - `Navigator.of(context).pushNamed` then moves
/// between them, the history stack and the platform back gesture come with it.
class MaterialApp extends StatefulWidget {
  const MaterialApp({
    super.key,
    this.home,
    this.title,
    this.initialRoute,
    this.routes,
  });
  final Widget? home;
  final String? title;
  final String? initialRoute;
  final Map<String, RouteWidgetBuilder>? routes;
  @override
  State<MaterialApp> createState() => _MaterialAppState();
}

class _MaterialAppState extends State<MaterialApp> {
  NavigationApp? _nav;
  _Owner? _renderOwner;

  @override
  void initState() {
    final routes = widget.routes;
    if (routes == null) return;
    var builder = NavigationAppBuilder();
    routes.forEach((path, routeBuilder) {
      builder = builder.addRoute(
        path: path,
        name: path,
        builder: (params) {
          final owner = _renderOwner!;
          return owner.inSlot(
            'route:$path',
            () => routeBuilder(owner, params)._render(owner),
          );
        },
      );
    });
    final nav = builder.setInitialPath(widget.initialRoute ?? '/').build();
    nav.router.onRouteChange((_) {
      if (mounted) setState(() {});
    });
    nav.bindSystemBack();
    _nav = nav;
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav;
    if (nav == null) return widget.home ?? const SizedBox();
    final owner = context as _Owner;
    owner.routerNav = nav;
    _renderOwner = owner;
    // The current route's node, built inside this build's binding scope.
    return _RawNode(nav.router.buildCurrentRoute());
  }
}

/// Wraps an already-built [WidgetNode] as a widget, for the routed shell.
class _RawNode extends Widget {
  const _RawNode(this.node);
  final WidgetNode node;
  @override
  WidgetNode _render(_Owner owner) => node;
}

class AppBar extends Widget {
  const AppBar({super.key, this.title});
  final Widget? title;
  @override
  WidgetNode _render(_Owner owner) =>
      UIBuilder.appBar(title: _stringOf(title, owner) ?? '');
}

class Scaffold extends Widget {
  const Scaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
  });
  final AppBar? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.scaffold(
    appBar: appBar == null
        ? null
        : owner.inSlot('appBar', () => appBar!._render(owner)),
    body: owner.inSlot('body', () => body._render(owner)),
    floatingActionButton: floatingActionButton == null
        ? null
        : owner.inSlot('fab', () => floatingActionButton!._render(owner)),
  );
}

// ---------------------------------------------------------------------------
// Layout.
// ---------------------------------------------------------------------------

List<WidgetNode> _renderAll(List<Widget> children, _Owner owner) => [
  for (var i = 0; i < children.length; i++)
    owner.inSlot(i, () => children[i]._render(owner)),
];

class Column extends Widget {
  const Column({
    super.key,
    this.children = const [],
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });
  final List<Widget> children;

  /// How the children are distributed down the column. Like Flutter's, it
  /// shows only where the column has height to spare - asking for `center`,
  /// `end` or `spaceBetween` also asks the column to fill what it is in.
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.column(
    crossAxisAlignment: crossAxisAlignment._name,
    mainAxisAlignment: mainAxisAlignment._name,
    children: _renderAll(children, owner),
  );
}

class Row extends Widget {
  const Row({
    super.key,
    this.children = const [],
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.spacing = 0,
  });
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.row(
    mainAxisAlignment: mainAxisAlignment._name,
    spacing: spacing,
    children: _renderAll(children, owner),
  );
}

/// Lays its [children] out in a horizontal run that wraps onto the next line
/// when it runs out of width. [spacing] separates children on a line,
/// [runSpacing] separates the lines.
class Wrap extends Widget {
  const Wrap({
    super.key,
    this.spacing = 0,
    this.runSpacing = 0,
    this.children = const [],
  });
  final double spacing;
  final double runSpacing;
  final List<Widget> children;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.wrap(
    spacing: spacing,
    runSpacing: runSpacing,
    children: _renderAll(children, owner),
  );
}

class Center extends Widget {
  const Center({super.key, required this.child});
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.center(
    child: owner.inSlot('child', () => child._render(owner)),
  );
}

class Padding extends Widget {
  const Padding({super.key, required this.padding, required this.child});
  final EdgeInsets padding;
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.padding(
    left: padding.left,
    top: padding.top,
    right: padding.right,
    bottom: padding.bottom,
    child: owner.inSlot('child', () => child._render(owner)),
  );
}

/// A trailing action revealed when a [SwipeActions] row is swiped left.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.onPressed,
    this.color = '#d32f2f',
  });

  /// The button text shown when the row is swiped open.
  final String label;

  /// Fired when the button is tapped, or when the row is swiped all the way
  /// (which fires the first action).
  final void Function() onPressed;

  /// The action button's colour, `#rrggbb`; defaults to a destructive red.
  final String color;
}

/// A row that reveals trailing [actions] when swiped left, iOS Mail style: a
/// partial swipe slides [child] over to show the action buttons to tap, and a
/// full swipe fires the first action. A renderer without swipe shows [child]
/// alone, so the row still works (through whatever other affordance it has).
class SwipeActions extends Widget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.leadingActions = const [],
  });
  final Widget child;

  /// Revealed by dragging the row to the left, at its trailing edge - where
  /// iOS Mail puts Delete.
  final List<SwipeAction> actions;

  /// Revealed by dragging the row to the right, at its leading edge - where
  /// iOS Mail puts Mark as read.
  final List<SwipeAction> leadingActions;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.swipeActions(
    child: owner.inSlot('child', () => child._render(owner)),
    actions: [
      for (final a in actions)
        (label: a.label, color: a.color, onPressed: a.onPressed),
    ],
    leadingActions: [
      for (final a in leadingActions)
        (label: a.label, color: a.color, onPressed: a.onPressed),
    ],
    id: _idOf(key),
  );
}

class Expanded extends Widget {
  const Expanded({super.key, this.flex = 1, required this.child});
  final int flex;
  final Widget child;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.expanded(
    flex: flex,
    child: owner.inSlot('child', () => child._render(owner)),
  );
}

class SizedBox extends Widget {
  const SizedBox({super.key, this.width, this.height});
  final double? width;
  final double? height;
  @override
  WidgetNode _render(_Owner owner) =>
      UIBuilder.sizedBox(width: width, height: height);
}

/// A flexible gap in a Row or Column - an [Expanded] with an empty child.
class Spacer extends Widget {
  const Spacer({super.key, this.flex = 1});
  final int flex;
  @override
  WidgetNode _render(_Owner owner) =>
      UIBuilder.expanded(flex: flex, child: UIBuilder.sizedBox());
}

/// A scrolling list. The default constructor stacks [children]; [ListView.builder]
/// builds only the rows near the visible ones (a windowed long list), for which
/// [itemExtent] and a [key] - the window's stable id - are required.
class ListView extends Widget {
  const ListView({super.key, this.children = const []})
    : itemCount = 0,
      itemExtent = null,
      itemExtentBuilder = null,
      itemBuilder = null;

  /// A windowed list. Every row is [itemExtent] tall, or each says its own
  /// height through [itemExtentBuilder] - one of the two, since the list's
  /// own height is a sum over rows it is not holding.
  ///
  /// Flutter's `ListView.builder` measures its rows instead and needs neither;
  /// this one is told, because a renderer on the other side of a channel is
  /// holding twenty rows out of ten thousand and cannot measure the rest.
  const ListView.builder({
    required Key super.key,
    required this.itemCount,
    required Widget Function(int index) this.itemBuilder,
    this.itemExtent,
    this.itemExtentBuilder,
  }) : children = const [],
       assert(
         (itemExtent == null) != (itemExtentBuilder == null),
         'Give ListView.builder one row height (itemExtent) or a height per '
         'row (itemExtentBuilder), not both and not neither.',
       );

  final List<Widget> children;
  final int itemCount;
  final double? itemExtent;
  final double Function(int index)? itemExtentBuilder;
  final Widget Function(int index)? itemBuilder;

  @override
  WidgetNode _render(_Owner owner) {
    final builder = itemBuilder;
    if (builder != null) {
      return UIBuilder.lazyList(
        id: _idOf(key) ?? 'list',
        itemCount: itemCount,
        itemExtent: itemExtent,
        itemExtentBuilder: itemExtentBuilder,
        itemBuilder: (index) =>
            owner.inSlot(index, () => builder(index)._render(owner)),
      );
    }
    return UIBuilder.column(
      crossAxisAlignment: 'stretch',
      children: _renderAll(children, owner),
    );
  }
}

/// A single fixed-height row: a [title] over an optional [subtitle], with an
/// optional [trailing] widget at the end.
class ListTile extends Widget {
  const ListTile({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final void Function()? onTap;
  @override
  WidgetNode _render(_Owner owner) {
    final lines = <WidgetNode>[
      if (title != null) owner.inSlot('title', () => title!._render(owner)),
      if (subtitle != null)
        owner.inSlot('subtitle', () => subtitle!._render(owner)),
    ];
    return UIBuilder.padding(
      all: 8,
      child: UIBuilder.row(
        spacing: 8,
        children: [
          UIBuilder.expanded(
            child: UIBuilder.column(
              crossAxisAlignment: 'start',
              children: lines,
            ),
          ),
          if (trailing != null)
            owner.inSlot('trailing', () => trailing!._render(owner)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text and controls.
// ---------------------------------------------------------------------------

/// The string a widget handed as a title or a label draws.
///
/// The protocol carries those as text rather than as a subtree, so the facade
/// reads it out of the widget: a [Text], or a [Tr] - which resolves its key
/// here, and registers the locale as something this build depends on.
String? _stringOf(Widget? widget, _Owner owner) {
  if (widget is Text) return widget.data;
  if (widget is Tr) return widget.resolve(owner);
  return null;
}

/// Text from the translation table, redrawn when the locale changes.
///
/// The framework does the two things an app used to do by hand: look the key
/// up, and repaint when someone calls `setLocale`. A screen no longer keeps a
/// listener of its own.
///
/// ```dart
/// AppBar(title: const Tr('navigation.settings')),
/// const Tr('plurals.items', count: 3),
/// Tr('messages.welcome', params: {'name': user.name}),
/// ```
///
/// Resolves against the global [I18n] unless given another. A key with no
/// translation falls back to [defaultValue], then to the key itself, which is
/// [I18n.t]'s own behaviour - a missing string shows up on screen rather than
/// crashing a release build.
class Tr extends Widget {
  const Tr(
    this.translationKey, {
    super.key,
    this.params,
    this.count,
    this.defaultValue,
    this.style,
    this.i18n,
  });

  /// The key to look up, nested keys included (`forms.email`).
  final String translationKey;

  /// Values for the placeholders in the translation.
  final Map<String, dynamic>? params;

  /// How many, for a key whose translation is a plural table.
  final int? count;

  /// Drawn when no locale has this key.
  final String? defaultValue;

  final TextStyle? style;

  /// The table to translate against. The global one by default.
  final I18n? i18n;

  /// The translated string, and the locale this build now follows.
  String resolve(_Owner owner) {
    final table = i18n ?? getI18n();
    owner._watch(table);
    final count = this.count;
    if (count != null) {
      return table.plural(
        translationKey,
        count,
        params: params,
        defaultValue: defaultValue,
      );
    }
    return table.t(translationKey, params: params, defaultValue: defaultValue);
  }

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.text(
    resolve(owner),
    fontSize: style?.fontSize,
    fontWeight: style?.fontWeight?.value,
    color: style?.color?._hex,
    decoration: style?.decoration?._name,
    id: _idOf(key),
  );
}

class Text extends Widget {
  const Text(this.data, {super.key, this.style, this.maxLines, this.overflow});
  final String data;
  final TextStyle? style;

  /// The most lines this text may take. Without one it wraps as far as it
  /// likes, which is what a row of unknown text will do to a fixed height.
  final int? maxLines;

  /// What happens to the text that does not fit - see [TextOverflow]. An
  /// overflow without a [maxLines] caps the text at one line, as Flutter's
  /// does.
  final TextOverflow? overflow;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.text(
    data,
    fontSize: style?.fontSize,
    fontWeight: style?.fontWeight?.value,
    color: style?.color?._hex,
    decoration: style?.decoration?._name,
    maxLines: maxLines ?? (overflow == null ? null : 1),
    overflow: overflow?.name,
    id: _idOf(key),
  );
}

/// What becomes of text that does not fit in the lines it is allowed.
///
/// Flutter's names, and the two that every renderer can honour: `ellipsis`
/// ends the last line with `…`, `clip` cuts it off. Flutter's `fade` and
/// `visible` are not here - a fade is a gradient mask that UIKit, Android's
/// TextView and CSS each spell differently enough that the same text would
/// look like three different things.
enum TextOverflow { clip, ellipsis }

/// How a button is filled and how big it is - the slice of Flutter's
/// `ButtonStyle` the protocol carries.
///
/// [backgroundColor] is the fill. [padding], [minimumSize] and [textStyle] are
/// how Flutter says "smaller" or "larger", and reach the renderers as numbers:
/// a button's padding is symmetric here, so the left and top edges of an
/// [EdgeInsets] are the ones that travel.
class ButtonStyle {
  const ButtonStyle({
    this.backgroundColor,
    this.padding,
    this.minimumSize,
    this.textStyle,
  });

  final Color? backgroundColor;
  final EdgeInsets? padding;
  final Size? minimumSize;
  final TextStyle? textStyle;
}

/// A width and a height, as Flutter spells it.
class Size {
  const Size(this.width, this.height);
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is Size && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

/// A raised, filled button. `onPressed: null` disables it, like Flutter.
class ElevatedButton extends Widget {
  const ElevatedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });
  final void Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;

  /// Mirrors `ElevatedButton.styleFrom(...)`, for the parameters the protocol
  /// carries.
  static ButtonStyle styleFrom({
    Color? backgroundColor,
    EdgeInsets? padding,
    Size? minimumSize,
    TextStyle? textStyle,
  }) => ButtonStyle(
    backgroundColor: backgroundColor,
    padding: padding,
    minimumSize: minimumSize,
    textStyle: textStyle,
  );

  @override
  WidgetNode _render(_Owner owner) => _button(
    label: _stringOf(child, owner) ?? '',
    onPressed: onPressed,
    variant: 'primary',
    style: style,
    id: _idOf(key),
  );
}

/// A flat button; the tertiary variant of the design system.
class TextButton extends Widget {
  const TextButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  });
  final void Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;

  /// Mirrors `TextButton.styleFrom(...)`, as [ElevatedButton.styleFrom] does.
  static ButtonStyle styleFrom({
    Color? backgroundColor,
    EdgeInsets? padding,
    Size? minimumSize,
    TextStyle? textStyle,
  }) => ButtonStyle(
    backgroundColor: backgroundColor,
    padding: padding,
    minimumSize: minimumSize,
    textStyle: textStyle,
  );

  @override
  WidgetNode _render(_Owner owner) => _button(
    label: _stringOf(child, owner) ?? '',
    onPressed: onPressed,
    variant: 'tertiary',
    style: style,
    id: _idOf(key),
  );
}

/// The one place a [ButtonStyle] becomes node props.
WidgetNode _button({
  required String label,
  required void Function()? onPressed,
  required String variant,
  required ButtonStyle? style,
  String? id,
}) => UIBuilder.button(
  label: label,
  onPressed: onPressed,
  variant: variant,
  color: style?.backgroundColor?._hex,
  // A button's padding is symmetric in the protocol, so one edge of each
  // axis travels; a Flutter app writing EdgeInsets.symmetric - which is
  // what button padding is - loses nothing.
  paddingHorizontal: style?.padding?.left,
  paddingVertical: style?.padding?.top,
  minWidth: style?.minimumSize?.width,
  minHeight: style?.minimumSize?.height,
  fontSize: style?.textStyle?.fontSize,
  disabled: onPressed == null,
  id: id,
);

/// A live camera preview.
///
/// Framework-specific, like [MapView], and drawn where a camera costs nothing
/// but a permission: **iOS** uses `AVCapture` and **web** `getUserMedia`.
/// **Android and the Flutter host draw a placeholder** - CameraX and the
/// `camera` plugin are dependencies the app chooses.
///
/// The app declares the permission itself: `NSCameraUsageDescription` in an
/// iOS app's Info.plist (without it the system stops the app on the first
/// frame), and a browser only offers a camera on a secure origin.
///
/// [active] false stops the camera without removing the widget, which is what
/// a screen behind a dialog should do - a preview nobody is looking at still
/// costs battery, heat and the indicator light.
///
/// Frames never reach Dart. [onStatus] only says whether it started: `ready`,
/// `denied`, `unavailable`, `stopped` or `error`.
class CameraPreview extends Widget {
  const CameraPreview({
    super.key,
    this.height = 300,
    this.facing = CameraFacing.back,
    this.active = true,
    this.onStatus,
  });

  final double height;
  final CameraFacing facing;
  final bool active;
  final void Function(String status, String? message)? onStatus;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.cameraPreview(
    height: height,
    facing: facing.name,
    active: active,
    onStatus: onStatus,
    id: _idOf(key),
  );
}

/// Which camera a [CameraPreview] shows.
enum CameraFacing {
  /// The one pointing away from the user.
  back,

  /// The one pointing at them.
  front,
}

/// A pin on a [MapView].
class MapMarker {
  const MapMarker({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;
}

/// A map centred on [latitude]/[longitude].
///
/// Framework-specific, like [Tabs]: Flutter has no map of its own, and what
/// draws one differs per target. **iOS** uses MapKit, which is free and needs
/// no key. **Web** lays out raster tiles - OpenStreetMap's by default, free
/// and attributed on screen; point [tileUrl] at your own source for anything
/// but a demo. **Android and the Flutter host draw a labelled placeholder**,
/// because the Maps SDK needs a dependency *and* an API key, which is the
/// app's decision to make.
///
/// [onCameraIdle] reports where the map came to rest after a pan, never while
/// it moves: a position per frame would rebuild the whole tree per frame.
class MapView extends Widget {
  const MapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 13,
    this.height = 300,
    this.markers = const [],
    this.interactive = true,
    this.tileUrl,
    this.onCameraIdle,
  });

  final double latitude;
  final double longitude;

  /// The slippy-map scale: 0 is the world, 15 a neighbourhood, 18 a building.
  final double zoom;
  final double height;
  final List<MapMarker> markers;
  final bool interactive;

  /// Web only: the tile template, `{z}/{x}/{y}`.
  final String? tileUrl;
  final void Function(double latitude, double longitude, double zoom)?
  onCameraIdle;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.map(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    height: height,
    interactive: interactive,
    tileUrl: tileUrl,
    onCameraIdle: onCameraIdle,
    markers: [
      for (final marker in markers)
        (
          latitude: marker.latitude,
          longitude: marker.longitude,
          label: marker.label,
        ),
    ],
    id: _idOf(key),
  );
}

/// Fades [child] whenever [opacity] changes - Flutter's `AnimatedOpacity`.
///
/// The one piece of motion the protocol carries, and it works the way the rest
/// of the framework does: the tree says what the screen *is*, and a renderer
/// animates the difference from what it was. A first render sets the opacity;
/// a later one that changes it fades over [duration].
///
/// ```dart
/// AnimatedOpacity(
///   opacity: _visible ? 1 : 0,
///   duration: const Duration(milliseconds: 300),
///   child: const Text('Saved'),
/// )
/// ```
class AnimatedOpacity extends Widget {
  const AnimatedOpacity({
    super.key,
    required this.opacity,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
  });

  final double opacity;
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.animatedOpacity(
    opacity: opacity,
    duration: duration,
    curve: curve.name,
    child: owner.inSlot('child', () => child._render(owner)),
  );
}

/// How an animation is paced over its duration - the framework's slice of
/// Flutter's `Curves`.
///
/// Five, because every renderer already has these five and no more: a CSS
/// timing function, an Android `Interpolator`, a UIKit animation option. Ask
/// for `Curves.elasticOut` and the code will not compile here, which is the
/// honest answer - it would have to be faked on three of the four targets.
class Curve {
  const Curve(this.name);

  /// The name the protocol carries; each renderer maps it onto its own.
  final String name;

  @override
  bool operator ==(Object other) => other is Curve && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// The curves the protocol carries. See [Curve].
abstract final class Curves {
  static const Curve linear = Curve('linear');
  static const Curve ease = Curve('ease');
  static const Curve easeIn = Curve('easeIn');
  static const Curve easeOut = Curve('easeOut');
  static const Curve easeInOut = Curve('easeInOut');
}

/// A box that moves to its new size and colour instead of jumping there -
/// Flutter's `AnimatedContainer`.
///
/// Same shape as [AnimatedOpacity], and the same reasoning: the tree says what
/// the screen *is*, and each renderer animates the difference it sees. A first
/// render sets the box; a later one that changes [width], [height] or [color]
/// moves there over [duration], along [curve].
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
/// Size and colour are what it carries. Padding, alignment, borders and
/// rotation land at once rather than moving, and a `Container` with no
/// animation is not part of the facade at all - reach for [SizedBox],
/// [Padding] or [Card].
///
/// One deliberate difference from Flutter: the child is centred in the box on
/// all four renderers. Flutter's `Container` passes its own constraints down
/// instead, which would mean four layout systems disagreeing about a child
/// that does not fill the space.
class AnimatedContainer extends Widget {
  const AnimatedContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.color,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
  });

  final Widget child;
  final double? width;
  final double? height;
  final Color? color;
  final Duration duration;
  final Curve curve;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.animatedContainer(
    width: width,
    height: height,
    color: color?._hex,
    duration: duration,
    curve: curve.name,
    child: owner.inSlot('child', () => child._render(owner)),
  );
}

/// The app's palette, visible to everything below it.
///
/// `runApp(theme: ...)` puts one at the root, so a screen can read the colours
/// the renderers are drawing with rather than repeating them:
///
/// ```dart
/// AnimatedContainer(color: Color.fromHex(Theme.of(context).primary), ...)
/// ```
///
/// One caveat, and it is a real one: this is the theme the app *declared*, not
/// the appearance on screen. Each renderer resolves light or dark from the
/// platform at render time - a trait collection, a night ui-mode,
/// `prefers-color-scheme` - and the widget layer is not told which it chose.
/// `Theme.of(context).dark` reaches the dark palette when an app needs to pick
/// deliberately.
class Theme extends InheritedWidget {
  const Theme({super.key, required this.data, required super.child});

  final AppTheme data;

  /// The nearest theme, or the framework's fallback palette when an app has
  /// not declared one - never null, so a screen can read a colour without
  /// asking whether anyone set it.
  static AppTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Theme>()?.data ??
      AppTheme.fallback;

  @override
  bool updateShouldNotify(Theme oldWidget) => oldWidget.data != data;
}

/// A strip of labels, one of them selected.
///
/// Framework-specific, like [Tr]: Flutter spells this as a `TabBar` driven by
/// a `TabController`, and the selection here lives in the app like every other
/// piece of state, so the shapes do not match. What it draws is each
/// platform's own way of choosing one of a few things - Material tabs on
/// Android, a segmented control on iOS, a tab strip on web.
///
/// The bar only: what the selected tab shows is the app's own tree.
///
/// ```dart
/// Tabs(
///   tabs: const ['All', 'Unread'],
///   selectedIndex: _tab,
///   onChanged: (index) => setState(() => _tab = index),
/// ),
/// if (_tab == 0) const _AllMail() else const _Unread(),
/// ```
class Tabs extends Widget {
  const Tabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final void Function(int index) onChanged;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.tabs(
    tabs: tabs,
    selectedIndex: selectedIndex,
    onChanged: onChanged,
    id: _idOf(key),
  );
}

/// Children in equal cells, [crossAxisCount] to a row - Flutter's
/// `GridView.count`, with the parameters the protocol carries.
///
/// The grid sizes to its rows rather than scrolling itself: the screen around
/// it already scrolls, and a list long enough to need windowing wants a
/// `LazyList` instead.
class GridView extends Widget {
  const GridView.count({
    super.key,
    required this.crossAxisCount,
    this.children = const [],
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.childAspectRatio = 1,
  });

  final int crossAxisCount;
  final List<Widget> children;

  /// Between the rows.
  final double mainAxisSpacing;

  /// Between the columns.
  final double crossAxisSpacing;

  /// A cell's width over its height.
  final double childAspectRatio;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.grid(
    crossAxisCount: crossAxisCount,
    spacing: crossAxisSpacing,
    runSpacing: mainAxisSpacing,
    childAspectRatio: childAspectRatio,
    children: _renderAll(children, owner),
  );
}

/// A value chosen by dragging along a track - Flutter's `Slider`, with the
/// parameters the protocol carries.
///
/// [onChanged] fires as the thumb moves; [onChangeEnd] when it is let go,
/// which is the one to act on when acting is expensive.
class Slider extends Widget {
  const Slider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
  });

  final double value;

  /// Null disables the slider, as in Flutter.
  final void Function(double value)? onChanged;
  final void Function(double value)? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.slider(
    value: value,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    min: min,
    max: max,
    divisions: divisions,
    disabled: onChanged == null,
    id: _idOf(key),
  );
}

class FloatingActionButton extends Widget {
  const FloatingActionButton({
    super.key,
    required this.onPressed,
    this.child,
    this.tooltip,
  });
  final void Function()? onPressed;
  final Widget? child;
  final String? tooltip;
  @override
  WidgetNode _render(_Owner owner) {
    // Default to the add icon so a childless FAB still carries a codepoint and
    // renders its glyph on the native renderers, which draw by codepoint.
    final icon = child is Icon ? (child as Icon).icon : Icons.add;
    return UIBuilder.floatingActionButton(
      tooltip: tooltip ?? '',
      onPressed: onPressed,
      icon: icon.name ?? 'add',
      codepoint: icon.codePoint,
      id: _idOf(key),
    );
  }
}

class IconButton extends Widget {
  const IconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
  });
  final void Function()? onPressed;
  final Widget icon;
  final String? tooltip;
  @override
  WidgetNode _render(_Owner owner) {
    final data = icon is Icon ? (icon as Icon).icon : null;
    return UIBuilder.iconButton(
      icon: data?.name ?? '',
      codepoint: data?.codePoint,
      onPressed: onPressed,
      tooltip: tooltip ?? '',
      id: _idOf(key),
    );
  }
}

class Checkbox extends Widget {
  const Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });
  final bool value;
  final void Function(bool value)? onChanged;
  final String? label;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.checkbox(
    checked: value,
    label: label,
    onChanged: onChanged == null ? null : (v) => onChanged!(v),
    id: _idOf(key),
  );
}

/// A radio button in a group: it is [selected] when [value] equals [groupValue],
/// and calls [onChanged] with its own value when tapped.
class Radio<T> extends Widget {
  const Radio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.label,
  });
  final T value;
  final T? groupValue;
  final void Function(T value)? onChanged;
  final String? label;
  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: _idOf(key));
    final changed = onChanged;
    if (changed != null) bindings.onTap(eventId, () => changed(value));
    return WidgetNode(
      type: 'Radio',
      props: {
        'eventId': eventId,
        'value': '$value',
        'selected': value == groupValue,
        if (label != null) 'label': label,
        if (_idOf(key) != null) 'id': _idOf(key),
      },
    );
  }
}

/// An on/off switch.
class Switch extends Widget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });
  final bool value;
  final void Function(bool value)? onChanged;
  final String? label;
  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: _idOf(key));
    final changed = onChanged;
    if (changed != null) {
      bindings.onToggle(eventId, changed, field: 'enabled');
    }
    return WidgetNode(
      type: 'Toggle',
      props: {
        'eventId': eventId,
        'enabled': value,
        if (label != null) 'label': label,
        if (_idOf(key) != null) 'id': _idOf(key),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Design-system components: thin widgets over the design-system builders, so a
// showcase reads in Flutter shapes (Card, Divider, Switch, LinearProgressIndicator)
// while still drawing the framework's own components.
// ---------------------------------------------------------------------------

/// A Material card. [Card.outlined] and [Card.filled] are the other variants.
class Card extends Widget {
  const Card({super.key, this.child}) : _variant = 'elevated';
  const Card.outlined({super.key, this.child}) : _variant = 'outlined';
  const Card.filled({super.key, this.child}) : _variant = 'filled';
  final Widget? child;
  final String _variant;
  @override
  WidgetNode _render(_Owner owner) {
    final content = owner.inSlot(
      'content',
      () => (child ?? const SizedBox())._render(owner),
    );
    switch (_variant) {
      case 'outlined':
        return DSCard.outlined(content: content);
      case 'filled':
        return DSCard.filled(content: content);
      default:
        return DSCard.elevated(content: content);
    }
  }
}

/// A web page embedded in the screen, drawn with the platform's own browser
/// view.
///
/// Give it a [height]: a web view has no size of its own, and a scrolling body
/// would otherwise collapse it to nothing. [javaScriptEnabled] is off by
/// default - a page that is only being read does not need to run code.
///
/// The Flutter-hosted target cannot draw one without `webview_flutter`, which
/// the framework does not depend on; it shows a placeholder saying so.
class WebView extends Widget {
  const WebView({
    super.key,
    required this.url,
    this.height = 300,
    this.javaScriptEnabled = false,
  });
  final String url;
  final double height;
  final bool javaScriptEnabled;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.webView(
    url: url,
    height: height,
    javaScriptEnabled: javaScriptEnabled,
    id: _idOf(key),
  );
}

/// A small label chip. [color] is a `#RRGGBB` string; the named constructors are
/// the semantic colors.
class Badge extends Widget {
  const Badge({
    super.key,
    required this.label,
    this.color,
    this.outlined = false,
  });
  const Badge.dot({super.key, this.color}) : label = null, outlined = false;
  final String? label;
  final String? color;
  final bool outlined;
  @override
  WidgetNode _render(_Owner owner) {
    final text = label;
    // A null colour follows the app theme's primary (filled by the renderer).
    if (text == null) return DSBadge.dot(color: color);
    if (outlined) return DSBadge.outlined(label: text, color: color);
    return DSBadge.solid(label: text, color: color);
  }
}

/// A colored alert banner. Use the named constructors for the semantic types.
class Alert extends Widget {
  const Alert.success({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'success';
  const Alert.error({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'error';
  const Alert.warning({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'warning';
  const Alert.info({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'info';
  final String _type;
  final String message;
  final String? title;
  final bool dismissible;
  @override
  WidgetNode _render(_Owner owner) {
    switch (_type) {
      case 'error':
        return DSAlert.error(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      case 'warning':
        return DSAlert.warning(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      case 'info':
        return DSAlert.info(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      default:
        return DSAlert.success(
          message: message,
          title: title,
          dismissible: dismissible,
        );
    }
  }
}

/// A thin horizontal rule.
class Divider extends Widget {
  const Divider({super.key, this.height});
  final double? height;
  @override
  WidgetNode _render(_Owner owner) => height == null
      ? DSDivider.horizontal()
      : DSDivider.horizontal(margin: height!);
}

/// A determinate (or, with a null [value], indeterminate) linear progress bar.
class LinearProgressIndicator extends Widget {
  const LinearProgressIndicator({super.key, this.value});
  final double? value;
  @override
  WidgetNode _render(_Owner owner) =>
      DSLoading.progressLinear(value: value ?? 0, indeterminate: value == null);
}

/// A determinate (or, with a null [value], spinning) circular progress ring.
class CircularProgressIndicator extends Widget {
  const CircularProgressIndicator({super.key, this.value});
  final double? value;
  @override
  WidgetNode _render(_Owner owner) => value == null
      ? DSLoading.spinner()
      : DSLoading.progressCircular(value: value!);
}

/// A placeholder bar shown while content loads.
class Skeleton extends Widget {
  const Skeleton({super.key, this.width, this.height = 16});
  final double? width;
  final double height;
  @override
  WidgetNode _render(_Owner owner) =>
      DSLoading.skeleton(width: width ?? double.infinity, height: height);
}

/// Holds a text field's value the Flutter way, so an app can read it (to add a
/// todo) and `clear()` it after. Its `text` seeds the field and is kept current
/// as the user types.
///
/// A [_version] counter separates an app-driven edit (`clear()`, or setting
/// [text]) from the user's own typing: only the former bumps it, and the field
/// node carries it, so a renderer can apply a clear that happens while the field
/// is focused without a re-render on every keystroke fighting the typing.
class TextEditingController {
  TextEditingController({String text = ''}) : _text = text;
  String _text;
  int _version = 0;

  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _version++;
  }

  void clear() => text = '';

  /// The field reporting the user's own typing; does not bump the version.
  void _setFromUser(String value) => _text = value;
}

class TextField extends Widget {
  const TextField({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onFocus,
    this.onBlur,
    this.decoration,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.autofocus = false,
  });
  final TextEditingController? controller;

  /// Asks for the keyboard from the app's side - see [FocusNode].
  final FocusNode? focusNode;

  /// Takes the keyboard the first time the field is drawn, for a screen whose
  /// whole point is a field: a search, a single-question form.
  final bool autofocus;
  final void Function(String value)? onChanged;
  final void Function(String value)? onSubmitted;
  final void Function()? onFocus;
  final void Function()? onBlur;
  final InputDecoration? decoration;
  final bool obscureText;
  final bool enabled;
  final int maxLines;

  /// What the keyboard's return key does - see [TextInputAction].
  final TextInputAction textInputAction;
  @override
  WidgetNode _render(_Owner owner) {
    final bindings = EventBindings.required;
    final controller = this.controller;
    // The controller tracks the value as it is typed (without bumping its
    // version, so no forced re-render per keystroke); the field's own callback
    // still runs. The node carries the version, so a renderer can tell an
    // app-driven clear() from the user's own typing.
    void Function(String)? handleChanged;
    if (controller != null || onChanged != null) {
      handleChanged = (value) {
        controller?._setFromUser(value);
        onChanged?.call(value);
      };
    }
    final id = _idOf(key);
    final eventId = bindings.allocate(key: id);
    bindings.onText(
      eventId,
      onChanged: handleChanged,
      onSubmitted: onSubmitted,
      onFocus: onFocus,
      onBlur: onBlur,
    );
    final decoration = this.decoration;
    return WidgetNode(
      type: 'TextField',
      props: {
        'hint': decoration?.hintText ?? '',
        'eventId': eventId,
        if (id != null) 'id': id,
        if (decoration?.labelText != null) 'label': decoration!.labelText,
        if (decoration?.labelText != null &&
            decoration!.floatingLabelBehavior == FloatingLabelBehavior.never)
          'floatingLabel': false,
        if (decoration?.errorText != null) 'error': decoration!.errorText,
        'obscureText': obscureText,
        'enabled': enabled,
        if (controller != null) 'initialValue': controller.text,
        if (controller != null) 'valueVersion': controller._version,
        if (autofocus) 'autofocus': true,
        // Version 0 is "never asked": a field holding a node nobody has
        // called yet must not take the keyboard on first render.
        if (focusNode != null && focusNode!._version > 0)
          'focusVersion': focusNode!._version,
        if (focusNode != null && focusNode!._version > 0 && !focusNode!._wanted)
          'focusRequested': false,
        'maxLines': maxLines,
        'textInputAction': textInputAction.name,
      },
    );
  }
}

/// Asks for, or gives up, the keyboard on a field.
///
/// Flutter's `FocusNode` is a live object a field attaches itself to; here the
/// tree is the only thing that crosses to a renderer, so the ask travels as a
/// version. `requestFocus()` bumps it and the renderer focuses the field it
/// sits on; `unfocus()` bumps it the other way and the keyboard goes.
///
/// ```dart
/// final email = FocusNode();
/// ...
/// TextField(focusNode: email, ...)
/// ...
/// onPressed: () => setState(email.requestFocus),
/// ```
///
/// The `setState` matters: the ask reaches the renderer with the next tree,
/// so something has to draw one.
class FocusNode {
  int _version = 0;
  bool _wanted = true;

  /// Whether the last ask was for the keyboard rather than against it.
  bool get isRequested => _wanted;

  /// Take the keyboard on the next render.
  void requestFocus() {
    _version++;
    _wanted = true;
  }

  /// Give it up on the next render.
  void unfocus() {
    _version++;
    _wanted = false;
  }
}

/// What the keyboard's return key says and does, the slice of Flutter's
/// `TextInputAction` the protocol carries.
enum TextInputAction {
  /// Closes the keyboard.
  done,

  /// Moves to the next field in the tree's reading order, so a form is filled
  /// in without reaching for each field. The last field has nowhere to go and
  /// closes the keyboard instead, and a multi-line field keeps its newline key
  /// whatever this says.
  next,
}

/// The slice of Flutter's `InputDecoration` the protocol carries.
class InputDecoration {
  const InputDecoration({
    this.hintText,
    this.labelText,
    this.errorText,
    this.floatingLabelBehavior = FloatingLabelBehavior.auto,
  });
  final String? hintText;
  final String? labelText;
  final String? errorText;

  /// Whether [labelText] floats in the field's outline or sits above it.
  final FloatingLabelBehavior floatingLabelBehavior;
}

/// Where a field's label sits - the slice of Flutter's `FloatingLabelBehavior`
/// the protocol carries.
enum FloatingLabelBehavior {
  /// In the field's outline, rising out of the way once the field has focus or
  /// a value. What Flutter does, and what Material and the web do. The native
  /// iOS renderer keeps the label above the field, since UIKit has no floating
  /// label and iOS forms do not use one.
  auto,

  /// Above the field, as plain text, on every renderer.
  never,
}

/// A [TextField] bound to a [FormField].
///
/// It shows the field's value, label, hint and validation error, reports edits
/// back with `setValue`, and validates on submit (and on blur by default). Give
/// a field a [TextFormField] and the wiring is done - build a `Form` with a
/// `FormBuilder`, then:
///
/// ```dart
/// final form = (FormBuilder()..addEmailField(name: 'email')).build();
/// // ...
/// TextFormField(field: form.getField('email')!)
/// ```
///
/// It rebuilds itself when a validator reports an error, so a submit that calls
/// `form.validate()` shows every field's error without the app rebuilding.
class TextFormField extends StatefulWidget {
  const TextFormField({
    super.key,
    required this.field,
    this.validateOnBlur = true,
    this.maxLines = 1,
    this.focusNode,
  });

  /// The field this input is bound to.
  final FormField field;

  /// Lets the form move the caret here - a failed submit sending the user to
  /// the first field that needs attention, say. See [FocusNode].
  final FocusNode? focusNode;

  /// Whether losing focus validates the field. A submit always validates.
  final bool validateOnBlur;

  final int maxLines;

  @override
  State<TextFormField> createState() => _TextFormFieldState();
}

class _TextFormFieldState extends State<TextFormField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.field.value,
  );
  StreamSubscription<FieldChange>? _changeSub;
  StreamSubscription<String>? _errorSub;

  FormField get _field => widget.field;

  /// Which validation run is the current one: an edit while an earlier run is
  /// still in flight makes that run's answer stale, and a stale answer must
  /// not repaint the field.
  int _validation = 0;

  @override
  void initState() {
    // Rebuild when the field changes from elsewhere (an external setValue) or a
    // validator reports an error; the user's own typing already shows in the
    // native field, so that case is skipped to avoid a rebuild per keystroke.
    _changeSub = _field.onChange.listen((_) {
      if (mounted && _field.value != _controller.text) setState(() {});
    });
    _errorSub = _field.onError.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _errorSub?.cancel();
  }

  Future<void> _validate() async {
    final run = ++_validation;
    await _field.validate();
    if (mounted && run == _validation) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Push an external value change (e.g. Form.reset) into the native field.
    if (_field.value != _controller.text) _controller.text = _field.value;
    return TextField(
      key: ValueKey('field_${_field.name}'),
      controller: _controller,
      focusNode: widget.focusNode,
      obscureText: _field.obscured,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: _field.label,
        hintText: _field.hint,
        errorText: _field.errorMessage,
      ),
      onChanged: (value) {
        _field.markTouched();
        _field.setValue(value);
        // Once a field has shown an error, every edit re-checks it, so the
        // message goes as soon as the value is right instead of standing
        // until the next submit. A field that has never failed is not
        // validated on every keystroke - the first check is still the blur or
        // the submit, which is where someone expects to be told.
        if (_field.errorMessage != null) unawaited(_validate());
      },
      onSubmitted: (_) => _validate(),
      onBlur: widget.validateOnBlur ? _validate : null,
    );
  }
}
