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
/// Flutter's, so a property the protocol has no place for is either composed
/// out of the nodes there are (a `Chip` is boxes, a `ListTile` a row) or
/// accepted and left alone, and the doc comment of each widget says which.
/// Everything here is pure Dart; nothing imports Flutter.
///
/// `State` follows Flutter's identity rule: a [Key] if the widget has one, its
/// place in the tree otherwise - see [_Owner].
///
/// The library is split into parts under `src/widgets/` because the one thing
/// every widget shares - `_render`, the step from widget to node - is private
/// to it.
library;

// Icons mirror Flutter's snake_case names (Icons.add_task, Icons.more_vert) on
// purpose, so an example reads identically to a Flutter one.
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:math' as math;

import 'forms/form.dart' as forms;
import 'run_app.dart';
import 'src/icon_data.dart';
import 'src/flutter_slots.dart';
import 'src/icons.dart';
// What only the platform can answer - is there a Flutter binding to start,
// which language is the device in - behind one name per target, chosen the
// way `run_app.dart` chooses its entry point.
import 'src/widgets/binding_stub.dart'
    if (dart.library.ui) 'src/widgets/binding_flutter.dart'
    if (dart.library.js_interop) 'src/widgets/binding_web.dart'
    as platform_binding;

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
// The framework's own form model. `Form` and `FormField` are Flutter's widgets
// in this library, so the model's classes are reachable here as [FormModel]
// and [FormFieldModel]; the builder and the field states keep their names.
export 'forms/form.dart' show FormBuilder, FieldState, FieldChange;
export 'forms/validators.dart';
export 'i18n/translations.dart' show Locale;

part 'src/widgets/painting.dart';
part 'src/widgets/theme.dart';
part 'src/widgets/binding.dart';
part 'src/widgets/async.dart';
part 'src/widgets/layout.dart';
part 'src/widgets/text.dart';
part 'src/widgets/buttons.dart';
part 'src/widgets/inputs.dart';
part 'src/widgets/scrolling.dart';
part 'src/widgets/navigation.dart';
part 'src/widgets/gestures.dart';
part 'src/widgets/motion.dart';
part 'src/widgets/custom_paint.dart';
part 'src/widgets/platform_views.dart';

// ---------------------------------------------------------------------------
// Foundation: keys, context, the widget/state model and the render owner.
// ---------------------------------------------------------------------------

/// A function that takes one value and returns nothing, as Flutter names it.
typedef ValueChanged<T> = void Function(T value);

/// A function that hands back a value.
typedef ValueGetter<T> = T Function();

/// A function that is handed one.
typedef ValueSetter<T> = void Function(T value);

/// Builds a widget from a context, as Flutter names it.
typedef WidgetBuilder = Widget Function(BuildContext context);

/// Builds a widget around a child that was built already.
typedef TransitionBuilder =
    Widget Function(BuildContext context, Widget? child);

/// True in a build with assertions on, which is what Flutter means by debug.
const bool kDebugMode = !kReleaseMode;

/// True in a build compiled for release.
const bool kReleaseMode = bool.fromEnvironment('dart.vm.product');

/// Flutter's third mode. There is no profile build of a pure Dart program.
const bool kProfileMode = false;

/// True when the program was compiled to run in a browser.
const bool kIsWeb = bool.fromEnvironment('dart.library.js_interop');

/// Marks a class whose fields never change. Flutter's `@immutable` is a hint
/// to the analyzer; this one is only the name, so a class carrying the
/// annotation compiles unchanged.
const Object immutable = Object();

/// As [immutable]: the name `@protected` code is written against.
const Object protected = Object();

/// As [immutable]: the name `@mustCallSuper` code is written against.
const Object mustCallSuper = Object();

/// As [immutable]: the name `@visibleForTesting` code is written against.
const Object visibleForTesting = Object();

/// Prints in the way Flutter's `debugPrint` does. There is no log buffer to
/// throttle here, so it is `print` with Flutter's signature.
void debugPrint(String? message, {int? wrapWidth}) {
  // ignore: avoid_print
  print(message);
}

/// Identity for a widget across rebuilds. A [ValueKey] doubles as the node `id`
/// the renderers and tests address a widget by.
abstract class Key {
  /// `Key('save')` is a `ValueKey<String>`, as in Flutter.
  const factory Key(String value) = ValueKey<String>;

  /// For subclasses, which is what Flutter calls it too.
  const Key.empty();
}

/// A key that only has to be unique among the widgets it sits beside.
abstract class LocalKey extends Key {
  const LocalKey() : super.empty();
}

class ValueKey<T> extends LocalKey {
  const ValueKey(this.value);
  final T value;
  @override
  bool operator ==(Object other) =>
      other is ValueKey<T> && other.value == value;
  @override
  int get hashCode => Object.hash(T, value);
  @override
  String toString() => '[<$value>]';
}

/// A key that is equal to another only when both hold the very same object.
class ObjectKey extends LocalKey {
  const ObjectKey(this.value);
  final Object? value;
  @override
  bool operator ==(Object other) =>
      other is ObjectKey && identical(other.value, value);
  @override
  int get hashCode => identityHashCode(value);
  @override
  String toString() => '[ObjectKey#${identityHashCode(value)}]';
}

/// A key equal only to itself: a new identity every time one is made.
class UniqueKey extends LocalKey {
  // Not const on purpose - two const instances would be the same instance.
  UniqueKey();
  @override
  String toString() => '[#${identityHashCode(this)}]';
}

/// A key that finds its widget's [State] from anywhere - how a screen calls
/// `formKey.currentState!.validate()` on a form built somewhere below it.
///
/// Flutter's global keys also let a widget move between parents with its
/// state. That part holds here as well: the state is kept under the key
/// alone, wherever in the tree the widget is drawn.
class GlobalKey<T extends State<StatefulWidget>> extends Key {
  GlobalKey({this.debugLabel}) : super.empty();

  final String? debugLabel;
  State? _state;

  /// The state of the widget carrying this key, while it is in the tree.
  T? get currentState {
    final state = _state;
    return state is T ? state : null;
  }

  /// The context that widget was last built with.
  BuildContext? get currentContext => _state?._context;

  /// The widget carrying this key, while it is in the tree.
  Widget? get currentWidget => _state?._widget;

  @override
  String toString() => '[GlobalKey#${identityHashCode(this)}]';
}

String? _idOf(Key? key) => key is ValueKey ? '${key.value}' : null;

/// The handle a build is given.
///
/// It remembers where in the tree it was made - which inherited widgets and
/// which states were above it - so a lookup works from a callback as well as
/// during the build: `onPressed: () => ScaffoldMessenger.of(context)...` runs
/// long after the build returned, and still finds what was above the button.
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

  /// The nearest [State] of type [T] above this context, or null.
  T? findAncestorStateOfType<T extends State<StatefulWidget>>();

  /// The nearest stateful or inherited widget of type [T] above this context.
  /// Only those two kinds leave a trace on the way down, so a stateless
  /// ancestor is not found - which is the one way this differs from Flutter.
  T? findAncestorWidgetOfExactType<T extends Widget>();

  /// Whether the widget this context was made for is still in the tree. The
  /// check to make after an `await`, before touching the context again.
  bool get mounted;
}

/// One step of the way down the tree that a context can look back up: an
/// inherited widget, or a state. A linked list rather than a copied one, so
/// taking a context costs one allocation however deep the tree is.
class _Scope {
  const _Scope(this.parent, {this.inherited, this.state});
  final _Scope? parent;
  final InheritedWidget? inherited;
  final State? state;
}

class _Context implements BuildContext {
  _Context(this._owner, this._scope);
  final _Owner _owner;
  final _Scope? _scope;

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      getInheritedWidgetOfExactType<T>();

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() {
    // The nearest one wins, so search from the inside out.
    for (var scope = _scope; scope != null; scope = scope.parent) {
      final candidate = scope.inherited;
      if (candidate is T) return candidate;
    }
    return null;
  }

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() {
    for (var scope = _scope; scope != null; scope = scope.parent) {
      final candidate = scope.state;
      if (candidate is T) return candidate;
    }
    return null;
  }

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    for (var scope = _scope; scope != null; scope = scope.parent) {
      final Widget? candidate = scope.inherited ?? scope.state?._widget;
      if (candidate is T) return candidate;
    }
    return null;
  }

  @override
  bool get mounted {
    if (!_owner._alive) return false;
    for (var scope = _scope; scope != null; scope = scope.parent) {
      final state = scope.state;
      if (state != null) return state.mounted;
    }
    return true;
  }
}

/// The owner behind a context. Every context the framework hands out is one
/// of its own, so the cast only fails for a context an app made up.
_Owner _ownerOf(BuildContext context) => (context as _Context)._owner;

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
  WidgetNode _render(_Owner owner) => build(owner._context())._render(owner);
}

/// A widget with mutable [State] that survives rebuilds.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});
  State createState();
  @override
  WidgetNode _render(_Owner owner) => owner._renderStateful(this);
}

/// A widget the framework renders itself; only its name is Flutter's, kept so
/// `extends PreferredSizeWidget`-style code has something to implement.
abstract class PreferredSizeWidget implements Widget {
  /// The size this widget would like when nothing constrains it.
  Size get preferredSize;
}

/// Mutable state for a [StatefulWidget]. [setState] mutates then asks the host
/// to rebuild, exactly like Flutter.
abstract class State<T extends StatefulWidget> {
  _Owner? _owner;
  StatefulWidget? _widget;
  _Context? _context;

  T get widget => _widget as T;
  BuildContext get context => _context!;
  bool get mounted => _owner != null;

  /// Called once, before the first build.
  void initState() {}

  /// Called once after [initState], where Flutter calls it the first time.
  ///
  /// Flutter calls it again whenever an inherited widget this state read
  /// changes; nothing here tracks who read what, so a value taken from the
  /// context in this method is taken once. Read it in [build] instead if it
  /// can change.
  void didChangeDependencies() {}

  /// Called when the parent rebuilt and handed this state a new widget
  /// instance; [oldWidget] is the one it had. [widget] is already the new one.
  void didUpdateWidget(covariant T oldWidget) {}

  void _didUpdate(StatefulWidget old) => didUpdateWidget(old as T);

  /// Called when the state leaves the tree, just before [dispose].
  void deactivate() {}

  /// Called once the widget is gone for good: cancel timers, close streams.
  void dispose() {}

  void setState(VoidCallback fn) {
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
    return builder(owner._context(), child)._render(owner);
  }
}

/// Flutter's older name for [ListenableBuilder], with `animation:` for the
/// listenable.
class AnimatedBuilder extends ListenableBuilder {
  const AnimatedBuilder({
    super.key,
    required Listenable animation,
    required super.builder,
    super.child,
  }) : super(listenable: animation);
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
    return builder(
      owner._context(),
      valueListenable.value,
      child,
    )._render(owner);
  }
}

/// A node built straight from the owner, for a facade widget whose `State`
/// has to end in a node rather than in another widget.
class _NodeWidget extends Widget {
  const _NodeWidget(this.builder);
  final WidgetNode Function(_Owner owner) builder;
  @override
  WidgetNode _render(_Owner owner) => builder(owner);
}

/// Takes the callbacks of a subtree that is built and thrown away.
class _NoRenderer implements NativeUIRenderer {
  const _NoRenderer();
  @override
  Future<RenderError?> render(WidgetNode tree) async => null;
  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async =>
      null;
  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {}
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
class _Owner {
  _Owner(this.root, this.host);

  final Widget root;
  final _WidgetHost host;
  final Map<Object, State> _states = {};
  Set<Object> _activePass = {};

  /// False once the host is unmounted, so a context that outlived the app
  /// says it is no longer mounted.
  bool _alive = true;

  /// What is above whatever is being built right now. Building is depth-first
  /// and synchronous, so this chain *is* the ancestor chain - and a context is
  /// a copy of where it pointed when the context was taken.
  _Scope? _scope;

  /// A context for whatever is being built right now.
  _Context _context() => _Context(this, _scope);

  /// Builds [body] with [widget] visible to everything inside it.
  T _withInherited<T>(InheritedWidget widget, T Function() body) {
    final outer = _scope;
    _scope = _Scope(outer, inherited: widget);
    try {
      return body();
    } finally {
      _scope = outer;
    }
  }

  /// The nearest inherited widget of type [T] above the build in progress.
  T? _inherited<T extends InheritedWidget>() {
    for (var scope = _scope; scope != null; scope = scope.parent) {
      final candidate = scope.inherited;
      if (candidate is T) return candidate;
    }
    return null;
  }

  /// The owner whose build is in progress, if one is. Building is synchronous,
  /// so there is at most one - and it is how a value with no context of its
  /// own, an [EdgeInsetsDirectional] being turned into four numbers, finds the
  /// reading direction it is being built under.
  static _Owner? _current;

  /// The reading direction where the build currently is: the nearest
  /// [Directionality] above, left to right with none.
  TextDirection get _direction =>
      _inherited<Directionality>()?.textDirection ?? TextDirection.ltr;

  /// The outermost [Directionality] built this pass, and the direction a
  /// [MaterialApp] handed its navigator - see [_screenDirection].
  TextDirection? _outerDirection;
  TextDirection? _appDirection;

  /// The direction the screen as a whole is laid out in, which is the one
  /// thing about direction the renderers are told (`RootProps.textDirection`).
  ///
  /// It is the direction in force around a [MaterialApp]'s pages - its
  /// locale's, or that of a [Directionality] its `builder` put above them -
  /// and without a `MaterialApp` the outermost [Directionality] in the tree.
  /// A [Directionality] further down turns what the widget layer resolves
  /// below it (insets, alignments, a row's order) without turning the
  /// renderers' own chrome.
  TextDirection get _screenDirection =>
      _appDirection ?? _outerDirection ?? TextDirection.ltr;

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
  String _positionId(Object type) {
    final path = '${_slots.join('/')}/$type';
    final seen = _atPath[path] ?? 0;
    _atPath[path] = seen + 1;
    return '$path#$seen';
  }

  /// An id for a node whose widget has no key but whose renderer needs one to
  /// keep its place between builds - a windowed list, say. Derived from where
  /// the widget sits, and spelled with nothing but word characters so it is
  /// safe wherever a renderer puts it.
  String _autoId(String kind) =>
      _positionId(kind).replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

  /// Which page a key belongs to. A local key only has to be unique on its
  /// own page, so the same screen pushed twice - or the same `ValueKey` on two
  /// routes of the stack - is two states and not one.
  Object? _keyScope;

  T _withKeyScope<T>(Object scope, T Function() body) {
    final outer = _keyScope;
    _keyScope = scope;
    try {
      return body();
    } finally {
      _keyScope = outer;
    }
  }

  /// How many enclosing subtrees are being built only to keep their state:
  /// the tabs that are not showing, the routes beneath the top one.
  int _hidden = 0;

  /// The bindings a hidden subtree's callbacks go to, one per place in the
  /// tree, kept so that state a builder retains (a list's window) survives.
  final Map<String, EventBindings> _scratch = {};
  Set<String> _scratchUsed = {};

  /// Builds [widget] and throws the nodes away, so its `State`s stay alive
  /// while it is not on screen - what Flutter's `Offstage` does for an
  /// `IndexedStack`.
  ///
  /// The callbacks it would have registered go to bindings of its own that no
  /// renderer is attached to. Otherwise a hidden button would claim an event
  /// id - the one its key gives it, or the next from the counter - that a
  /// visible one is using, and a tap would run the wrong page's handler.
  void _offstage(Object slot, Widget widget) {
    final place = '${_slots.join('/')}/$slot';
    _scratchUsed.add(place);
    final scratch = _scratch.putIfAbsent(place, EventBindings.new);
    _hidden++;
    try {
      scratch.runBuild(
        const _NoRenderer(),
        () => inSlot(slot, () => widget._render(this)),
        invalidate: _requestRebuild,
      );
    } finally {
      _hidden--;
    }
  }

  /// Whether the widget being built is offered no limit down or across: a
  /// child of a Column has all the height it asks for, a child of a Row all
  /// the width, and so has whatever sits in a scroller. Layout happens in the
  /// renderers, but a few widgets have to know this much to say the right
  /// thing to them - an [Align] may only stretch along an axis that ends.
  bool _unboundedHeight = false;
  bool _unboundedWidth = false;

  /// The main axis of the Row or Column whose direct child is being built, so
  /// an [Expanded] knows which axis it bounds.
  Axis? _flexAxis;

  T _withLayout<T>(
    T Function() body, {
    bool? unboundedHeight,
    bool? unboundedWidth,
    Axis? flexAxis,
  }) {
    final height = _unboundedHeight;
    final width = _unboundedWidth;
    final flex = _flexAxis;
    _unboundedHeight = unboundedHeight ?? height;
    _unboundedWidth = unboundedWidth ?? width;
    _flexAxis = flexAxis;
    try {
      return body();
    } finally {
      _unboundedHeight = height;
      _unboundedWidth = width;
      _flexAxis = flex;
    }
  }

  /// The axes a box with no size of its own may fill: the ones that end.
  String? get _expandBounded => _unboundedHeight
      ? (_unboundedWidth ? null : 'width')
      : (_unboundedWidth ? 'height' : 'both');

  /// How many vertical scrollers enclose the build in progress. A list inside
  /// one cannot scroll itself, and a [LayoutBuilder] there has no height to
  /// fill.
  int _scrollDepth = 0;

  /// Where each scroller without a controller of its own has got to, by its
  /// place in the tree - what Flutter keeps in the scroller's own state. It
  /// lasts as long as the scroller is built, drawn or only kept alive.
  final Map<String, ScrollController> _scrollPositions = {};
  Set<String> _scrollPositionsUsed = {};

  ScrollController _scrollPosition() {
    final place = _positionId('Scroll');
    _scrollPositionsUsed.add(place);
    return _scrollPositions.putIfAbsent(place, ScrollController.new);
  }

  /// How many [Scaffold]s enclose the build in progress: only the outermost
  /// one is the platform's own frame.
  int _scaffoldDepth = 0;

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

  /// Lets go of everything, for a host tearing the app down: the stores it
  /// followed, and every state - a ticker left running would otherwise keep
  /// asking a screen that is gone to rebuild.
  void _dispose() {
    _alive = false;
    for (final entry in _watched.entries) {
      entry.key.removeListener(entry.value);
    }
    _watched.clear();
    for (final id in _states.keys.toList()) {
      _drop(id);
    }
    SystemBack.removeHandler(_handleBack);
    _backBound = false;
    if (_guardBound) {
      SystemBack.removeFilter(_beginPlatformBack);
      SystemBack.removeListener(_keepGuard);
      _guardBound = false;
    }
    _guard = false;
  }

  /// The viewport as the renderer last reported it - see [MediaQuery].
  MediaQueryData _media = const MediaQueryData(size: Size(390, 800));

  /// The size each `sizeEventId` last carried. A renderer says a box's size
  /// once and again only when it changes, so a `State` made anew for a box
  /// that is on screen already would otherwise never hear it.
  final Map<String, Size> _sizeReports = {};

  /// The widgets listening for hardware keys in the build on screen.
  final List<void Function(KeyEvent event)> _keyListeners = [];

  /// What a [Draggable] carries, by the token that crosses to the renderer:
  /// the wire holds a string, and a drop hands back the object it stood for.
  final Map<String, _Dragged> _dragData = {};

  /// The dialogs and sheets open over the app, oldest first. Each is state: it
  /// is in the tree while it is open and drops out when it is dismissed.
  final List<_OverlayEntry> _overlays = [];

  /// The snackbars asked for and not yet gone, in the order they were asked
  /// for. The first is the one showing; the rest wait their turn, as
  /// Flutter's do.
  final List<_QueuedSnackBar> _snackBars = [];

  /// Counts the bars shown, so each is a fresh snackbar to a renderer rather
  /// than the last one rendered again.
  int _snackBarSeq = 0;

  /// The router of the routed [MaterialApp] mounted below, if any, so
  /// Navigator.pushNamed/pop reach it.
  NavigationApp? routerNav;

  /// The named routes of the [MaterialApp] being shown, by name, so a
  /// navigator can push one as a page.
  Map<String, Function>? _namedRoutes;

  /// The router of the `MaterialApp.router` built this pass, if any, so a pop
  /// with nothing of the navigator's own to pop reaches the router's pages.
  RouterConfig? _router;

  /// The navigators built this pass, outermost first. The back gesture goes
  /// to the innermost one that has a page to pop.
  final List<NavigatorState> _navigators = [];
  bool _backBound = false;

  /// Whether a history entry of this app's is standing between what it has
  /// open - pushed pages, a dialog - and whatever the browser was showing
  /// before; see [_syncGuard].
  bool _guard = false;
  bool _guardBound = false;

  /// Platform pops this owner asked for itself, to take its guard away, which
  /// are not the user pressing Back.
  int _guardPops = 0;

  /// True while the platform's Back is being answered: the browser has
  /// already left the guard's entry, so whatever that Back closes must not
  /// go and take it away again.
  bool _inPlatformBack = false;

  /// The overlay being built right now, so a dialog can bind its dismiss to the
  /// entry it belongs to.
  _OverlayEntry? _buildingOverlay;

  /// True while [buildRoot] runs. A rebuild asked for meanwhile - a notifier
  /// firing from an `initState`, a future that was already complete - cannot
  /// start inside the one in progress, so it is remembered and run after.
  bool _building = false;
  bool _dirty = false;

  /// Which build this is, counted from the first. A controller compares it
  /// with the build that last attached it to know whether it is still in use.
  int _pass = 0;

  /// Runs [body], in which several states may each ask for a rebuild, and
  /// rebuilds once at the end.
  T _batch<T>(T Function() body) {
    if (_building) return body();
    _building = true;
    try {
      return body();
    } finally {
      _building = false;
      if (_dirty) {
        _dirty = false;
        _requestRebuild();
      }
    }
  }

  WidgetNode buildRoot() {
    _pass++;
    _building = true;
    final outer = _current;
    _current = this;
    try {
      // The direction is the screen's, so it is said once, on whatever node
      // turned out to be the root, and only when it is not the default.
      final tree = _buildRoot();
      return UIBuilder.withTextDirection(tree, _screenDirection.name);
    } finally {
      _current = outer;
      _building = false;
      if (_dirty) {
        _dirty = false;
        scheduleMicrotask(_requestRebuild);
      }
    }
  }

  WidgetNode _buildRoot() {
    final before = _states.keys.toSet();
    _activePass = {};
    _watchedThisPass = {};
    _scratchUsed = {};
    _scrollPositionsUsed = {};
    _atPath.clear();
    _slots.clear();
    _scope = null;
    _keyScope = null;
    _unboundedHeight = false;
    _unboundedWidth = false;
    _flexAxis = null;
    _hidden = 0;
    _scrollDepth = 0;
    _scaffoldDepth = 0;
    _keyListeners.clear();
    _dragData.clear();
    _navigators.clear();
    _router = null;
    _outerDirection = null;
    _appDirection = null;
    final root = this.root._render(this);
    final overlays = <WidgetNode>[];
    for (final entry in List.of(_overlays)) {
      _buildingOverlay = entry;
      // A dialog is built where it was asked for: under the theme, the media
      // query and whatever else the screen that opened it could see.
      _scope = entry.scope;
      final node = _withKeyScope(
        entry.id,
        // A dialog or a sheet is as tall as what is in it.
        () => _withLayout(
          () => inSlot(
            entry.id,
            () => entry.build(_context())._render(this),
          ),
          unboundedHeight: true,
        ),
      );
      overlays.add(entry.wrap(this, node));
      _scope = null;
      _buildingOverlay = null;
    }
    final snackBar = _snackBars.firstOrNull?.snackBar;
    if (snackBar != null) {
      final action = snackBar.action;
      overlays.add(
        UIBuilder.snackbar(
          id: 'snackbar_$_snackBarSeq',
          message: _plainText(snackBar.content, this) ?? '',
          actionLabel: action?.label,
          onAction: action == null
              ? null
              : () {
                  _closeSnackBar(SnackBarClosedReason.action);
                  action.onPressed();
                },
          duration: snackBar.duration,
          onDismiss: () => _closeSnackBar(SnackBarClosedReason.timeout),
        ),
      );
    }
    // After the overlays: a state living in a dialog is as much a part of
    // this build as the screen behind it, and so is a listenable it watches.
    for (final gone in before.difference(_activePass)) {
      _drop(gone);
    }
    _scratch.removeWhere((place, _) => !_scratchUsed.contains(place));
    _scrollPositions.removeWhere(
      (place, _) => !_scrollPositionsUsed.contains(place),
    );
    _pruneWatched();
    _trackBack();
    return overlays.isEmpty
        ? root
        : UIBuilder.overlay(child: root, overlays: overlays);
  }

  /// Takes a state out of the tree for good.
  void _drop(Object id) {
    final state = _states.remove(id);
    if (state == null) return;
    state.deactivate();
    state.dispose();
    final key = state._widget?.key;
    if (key is GlobalKey && identical(key._state, state)) key._state = null;
    state._owner = null;
  }

  Future<T?> pushOverlay<T>(_OverlayEntry entry) {
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

  /// Closes every open drawer: the app is moving to another page, and a
  /// drawer belongs to the one it was opened on.
  void _closeDrawers() {
    for (final entry in _overlays.where((entry) => entry.isDrawer).toList()) {
      _dismiss(entry, null);
    }
  }

  /// Queues [snackBar]: it shows now if nothing is showing, and otherwise
  /// when the ones ahead of it have gone.
  _QueuedSnackBar showSnackBar(SnackBar snackBar) {
    final queued = _QueuedSnackBar(snackBar);
    _snackBars.add(queued);
    if (_snackBars.length == 1) {
      // A number per bar shown, so a renderer sees a new bar - with its own
      // time to run - and not the last one with its words changed.
      _snackBarSeq++;
      _requestRebuild();
    }
    return queued;
  }

  /// Takes down the snackbar showing, and shows the next one waiting.
  void _closeSnackBar(SnackBarClosedReason reason) {
    if (_snackBars.isEmpty) return;
    _snackBars.removeAt(0).closed.complete(reason);
    if (_snackBars.isNotEmpty) _snackBarSeq++;
    _requestRebuild();
  }

  /// Takes [queued] down if it is showing, and out of the queue if it is
  /// still waiting.
  void _closeQueuedSnackBar(_QueuedSnackBar queued, SnackBarClosedReason reason) {
    if (_snackBars.firstOrNull == queued) {
      _closeSnackBar(reason);
    } else if (_snackBars.remove(queued)) {
      queued.closed.complete(reason);
    }
  }

  /// Drops every snackbar still waiting, then takes down the one showing.
  void _clearSnackBars() {
    if (_snackBars.isEmpty) return;
    for (final waiting in _snackBars.sublist(1)) {
      waiting.closed.complete(SnackBarClosedReason.remove);
    }
    _snackBars.removeRange(1, _snackBars.length);
    _closeSnackBar(SnackBarClosedReason.hide);
  }

  /// Holds the platform back gesture while some navigator has a page to pop.
  ///
  /// Registered when the first page is pushed, so it is newer than a router's
  /// own handler and is offered the gesture first; a dialog opened later is
  /// newer still, and one opened earlier is deferred to in [_handleBack].
  void _trackBack() {
    final wanted = _navigators.any((navigator) => navigator._routes.isNotEmpty);
    if (wanted && !_backBound) {
      SystemBack.addHandler(_handleBack);
      _backBound = true;
    } else if (!wanted && _backBound) {
      SystemBack.removeHandler(_handleBack);
      _backBound = false;
    }
    _syncGuard(_wantsGuard);
  }

  /// The platform's history - the browser's, in a browser - or whatever the
  /// app put in its place.
  HistoryAdapter get _history =>
      HistoryAdapter.platform ?? platform_binding.platformHistory();

  /// Whether there is something on screen that Back should close: a pushed
  /// page, or a dialog or sheet over whatever is showing.
  bool get _wantsGuard =>
      _overlays.isNotEmpty ||
      _navigators.any((navigator) => navigator._routes.isNotEmpty);

  /// Keeps one history entry of this app's in the browser while there is
  /// something for Back to close, so that Back has something to come back
  /// *to*.
  ///
  /// A page pushed with `Navigator.push` has no name to write in the URL, and
  /// neither has a dialog; and the browser only tells an app about Back when
  /// the entry it lands on is the app's own. With nothing of this app's
  /// behind it, Back left the site with the page or the dialog still open.
  /// So the first of them writes an entry for where the app already is - the
  /// guard - and each Back that closes one puts it back for the next
  /// ([_keepGuard]). It goes when the last of them does.
  ///
  /// Not while a router is mirroring itself into the history
  /// ([HistoryAdapter.mirrors]): its entries are already behind the page, and
  /// it puts back the one a Back spends on something that is not a route.
  void _syncGuard(bool wanted) {
    if (wanted == _guard || _inPlatformBack) return;
    final history = _history;
    if (!history.hasStack) return;
    if (wanted) {
      if (HistoryAdapter.mirrors > 0) return;
      if (!_guardBound) {
        SystemBack.addFilter(_beginPlatformBack);
        SystemBack.addListener(_keepGuard);
        _guardBound = true;
      }
      history.push(history.currentPath ?? '/');
      _guard = true;
    } else {
      // The app closed the last of them itself - its own back button, a
      // dialog's Cancel - so the guard is still in the browser. Taken away,
      // and the pop the browser reports for that is not the user's.
      _guard = false;
      _guardPops++;
      history.back();
    }
  }

  /// First to hear of every Back. Swallows the ones this owner asked the
  /// platform for; for any other, notes that the browser has already left
  /// the guard's entry, so that nothing closed on the way takes it away
  /// again - [_keepGuard] settles it once the gesture has been answered.
  bool _beginPlatformBack() {
    if (_guardPops > 0) {
      _guardPops--;
      return true;
    }
    _inPlatformBack = true;
    // A filter after this one may swallow the gesture, and then no listener
    // is told: the note must not outlive the dispatch either way.
    scheduleMicrotask(() => _inPlatformBack = false);
    return false;
  }

  /// Last to hear of every Back. The browser spent the guard on it: with
  /// something still to close the guard goes back for the next Back, and
  /// with nothing it has done its job and is already gone.
  void _keepGuard(SystemBackHandler? consumedBy) {
    _inPlatformBack = false;
    if (!_guard) return;
    if (_wantsGuard) {
      final history = _history;
      history.push(history.currentPath ?? '/');
    } else {
      _guard = false;
    }
  }

  bool _handleBack() {
    // An open dialog or sheet takes the gesture itself.
    if (_overlays.isNotEmpty) return false;
    for (final navigator in _navigators.reversed) {
      if (navigator._routes.isEmpty) continue;
      navigator._popRoute(null);
      return true;
    }
    return false;
  }

  WidgetNode _renderStateful(StatefulWidget widget) {
    // A Key is an identity the app chose, and it travels with the widget: keep
    // it wherever the widget moves to on its page. Without one, the widget
    // *is* its place in the tree - the same rule Flutter follows, and the
    // reason two of a type side by side do not share one State.
    final key = widget.key;
    final Object id = key == null
        ? _positionId(widget.runtimeType)
        : key is GlobalKey
        ? key
        // The type is part of it, as in Flutter: a widget that hands its own
        // key down to the one it builds is not asking to share a State.
        : (_keyScope, key, widget.runtimeType);
    _activePass.add(id);
    var state = _states[id];
    if (state == null) {
      state = widget.createState()
        .._owner = this
        .._widget = widget;
      state._context = _Context(this, _Scope(_scope, state: state));
      _states[id] = state;
      if (key is GlobalKey) key._state = state;
      state.initState();
      state.didChangeDependencies();
    } else {
      final old = state._widget!;
      state._widget = widget;
      state._context = _Context(this, _Scope(_scope, state: state));
      if (!identical(old, widget)) {
        state._didUpdate(old);
      }
    }
    // Its subtree hangs below it, so a child of one instance cannot be
    // mistaken for the same child of another.
    final outer = _scope;
    final context = state._context!;
    _scope = context._scope;
    try {
      return inSlot(
        // Only the last step of a position id: the steps before it are in
        // the path already, and pushing the whole id again doubled the path
        // at every stateful widget on the way down - megabytes, thirty deep.
        key == null
            ? (id as String).substring(id.lastIndexOf('/') + 1)
            : '$key:${widget.runtimeType}',
        () => state!.build(context)._render(this),
      );
    } finally {
      _scope = outer;
    }
  }

  void _requestRebuild() {
    if (!_alive) return;
    if (_building) {
      _dirty = true;
      return;
    }
    host.render();
  }
}

/// The [NativeUIApp] the framework actually mounts; its [build] is the widget
/// tree converted to nodes, run inside the app's binding scope so `onPressed`
/// and `onChanged` callbacks register themselves.
class _WidgetHost extends NativeUIApp {
  _WidgetHost(Widget root, {AppTheme theme = AppTheme.fallback}) {
    // The root is wrapped rather than the app wrapping it, so Theme.of and
    // Navigator.of work in any screen without every app remembering to
    // provide them.
    _owner = _Owner(
      _RootScope(theme: theme, child: Navigator._(child: root)),
      this,
    );
  }
  late final _Owner _owner;

  @override
  void init() {
    // What a renderer says on its own account, with no node asking.
    on(RendererEvents.viewport, _owner._onViewport);
    on(RendererEvents.key, _owner._onKey);
    on(
      RendererEvents.lifecycle,
      (data) => WidgetsBinding.instance._onLifecycle('${data['state']}'),
    );
  }

  @override
  WidgetNode build() => _owner.buildRoot();

  @override
  void unmount() {
    // A store outlives the app that showed it, so the listeners have to go;
    // otherwise a torn-down screen is still asked to rebuild.
    _owner._dispose();
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
///
/// [appTheme] is the palette the renderers colour their own chrome with - the
/// app bar, the platform's buttons, the scaffold - and it is handed to them at
/// start-up, before any widget has been built. A `MaterialApp(theme: ...)`
/// further down cannot reach back to that moment, so an app with a theme
/// passes it to both:
///
/// ```dart
/// final theme = ThemeData(colorSchemeSeed: Colors.teal);
/// runApp(
///   MaterialApp(theme: theme, home: const Home()),
///   appTheme: theme.toAppTheme(),
/// );
/// ```
///
/// [systemBack] false leaves the app out of the platform's back gesture -
/// Android's button, the iOS edge swipe - and, in a browser, out of its
/// history: nothing is written to it and the Back button is the page's.
Future<void> runApp(
  Widget app, {
  bool nativeViews = true,
  bool systemBack = true,
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
}) => runNativeApp(
  hostApp(app, theme: appTheme),
  nativeViews: nativeViews,
  systemBack: systemBack,
  title: title,
  appTheme: appTheme,
  debugShowRenderErrors: debugShowRenderErrors,
);
