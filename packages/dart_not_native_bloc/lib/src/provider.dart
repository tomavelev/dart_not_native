/// Providers: putting a value where everything built below can reach it.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:dart_not_native/widgets.dart';

import 'rebuild.dart';

/// A widget that takes exactly one child, and can be given it later.
///
/// What lets `MultiBlocProvider(providers: [...])` take a flat list: each
/// entry is written without a child, and the list is nested by handing every
/// entry the one after it.
abstract class SingleChildWidget implements Widget {
  /// This widget, around [child].
  Widget withChild(Widget child);
}

/// Thrown when `context.read<T>()` finds no provider of [valueType].
class ProviderNotFoundException implements Exception {
  ProviderNotFoundException(this.valueType);

  final Type valueType;

  @override
  String toString() =>
      'ProviderNotFoundException: no provider of $valueType was found.\n'
      'Either none is in the tree, or it was looked up by a different type '
      'than it was provided as: a BlocProvider<GuestsBloc> is found by '
      'read<GuestsBloc>(), not by read<Bloc>(). Give the provider the type '
      'it should be read by - BlocProvider<Base>(create: (_) => Sub()).';
}

// ---------------------------------------------------------------------------
// The lookup.
// ---------------------------------------------------------------------------

/// The inherited widget a provider of `T` is found by.
///
/// [F] is always `T Function(T)`, never `T` itself. Looking a provider up by
/// `_Scope<T>` would also find a `_Scope<Sub>`, because Dart's generics are
/// covariant; a function type that both takes and returns `T` is a subtype of
/// nothing but itself, so this finds the provider of exactly `T` - the rule
/// `provider` and `flutter_bloc` follow, and the one that keeps a lookup's
/// answer from depending on what else happens to be in the tree.
class _Scope<F> extends InheritedWidget {
  const _Scope({required this.host, required super.child});
  final _ProviderHost<Object?> host;

  @override
  bool updateShouldNotify(_Scope<F> oldWidget) =>
      !identical(oldWidget.host, host);
}

/// The nearest provider of exactly [T] above [context], or null.
_ProviderHost<T>? _findProvider<T>(BuildContext context) =>
    context.getInheritedWidgetOfExactType<_Scope<T Function(T)>>()?.host
        as _ProviderHost<T>?;

/// The widget every provider here is built from: holds a value, or makes one,
/// and shows it to its subtree.
class _Provided<T> extends StatefulWidget {
  const _Provided({
    super.key,
    this.create,
    this.value,
    required this.lazy,
    this.dispose,
    required this.child,
  });

  /// Makes the value. Null for a provider that was handed one.
  final T Function(BuildContext context)? create;
  final T? value;
  final bool lazy;

  /// Cleans up a value [create] made. Never called for a [value].
  final void Function(T value)? dispose;
  final Widget child;

  @override
  State<_Provided<T>> createState() => _ProviderHost<T>();
}

/// The State behind a provider: the value, once made, and whoever is
/// following it.
class _ProviderHost<T> extends LiveState<_Provided<T>> {
  T? _created;
  bool _hasCreated = false;
  StreamSubscription<Object?>? _subscription;
  Object? _following;

  Type get valueType => T;

  T get value {
    final create = widget.create;
    if (create == null) return widget.value as T;
    if (!_hasCreated) {
      _created = create(context);
      _hasCreated = true;
    }
    return _created as T;
  }

  /// Rebuilds the tree whenever the value emits, if it is something that
  /// does. What `context.watch` asks for.
  void follow() {
    final value = this.value;
    if (identical(value, _following)) return;
    _subscription?.cancel();
    _subscription = null;
    _following = value;
    if (value is StateStreamable<Object?>) {
      _subscription = value.stream.listen((_) {
        if (alive) requestRebuild(this);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // An eager provider makes its value on the way into the tree, as in
    // flutter_bloc - for a bloc whose constructor starts the loading.
    if (!widget.lazy) value;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_hasCreated) widget.dispose?.call(_created as T);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    markBuilt();
    return _Scope<T Function(T)>(host: this, child: widget.child);
  }
}

Widget _childOf(Widget? child, Type provider) =>
    child ??
    (throw StateError(
      '$provider was built without a child. A provider written without one '
      'belongs in the `providers:` list of a Multi* widget, which gives it '
      'the next entry as its child.',
    ));

// ---------------------------------------------------------------------------
// context.read, context.watch and context.select.
// ---------------------------------------------------------------------------

/// `context.read<T>()`: the provided value of type [T], without following it.
///
/// For a callback - `onPressed: () => context.read<GuestsBloc>().add(...)` -
/// and for handing one provided value to another's constructor.
///
/// [T] is the type the value was *provided* as, exactly: a
/// `BlocProvider<GuestsBloc>` is found by `read<GuestsBloc>()` and not by
/// `read<Bloc>()`, as in `flutter_bloc`. Dart infers that type from `create`,
/// so `BlocProvider(create: (_) => GuestsBloc())` is a provider of
/// `GuestsBloc`; write `BlocProvider<Base>(...)` to provide it as something
/// wider.
///
/// A context remembers where it was made, so this works from a callback as
/// it does during a build - and finds what was above the widget the callback
/// was written in, not what is above wherever it ends up being called.
extension ReadContext on BuildContext {
  T read<T>() {
    final host = _findProvider<T>(this);
    if (host == null) throw ProviderNotFoundException(T);
    return host.value;
  }
}

/// `context.watch<T>()`: [ReadContext.read], and rebuild when it emits.
///
/// ```dart
/// final state = context.watch<GuestsBloc>().state;
/// ```
///
/// For a value that is not a bloc or cubit there is nothing to follow, and
/// this is `read`.
extension WatchContext on BuildContext {
  T watch<T>() {
    final host = _findProvider<T>(this);
    if (host == null) throw ProviderNotFoundException(T);
    host.follow();
    return host.value;
  }
}

/// `context.select((GuestsBloc bloc) => bloc.state.guests.length)`: one
/// aspect of a provided value, followed.
///
/// In Flutter this exists to rebuild a widget only when the selected part
/// changes. A rebuild here is from the root whichever part changed, so this
/// is [WatchContext.watch] with the selector applied - the same value, and
/// the same code, without the saving.
extension SelectContext on BuildContext {
  R select<T, R>(R Function(T value) selector) => selector(watch<T>());
}

// ---------------------------------------------------------------------------
// The providers an app writes.
// ---------------------------------------------------------------------------

/// Provides a bloc or cubit to everything built below it, read back with
/// `context.read<T>()` or [BlocProvider.of].
///
/// ```dart
/// BlocProvider(
///   create: (context) => GuestsBloc(context.read<GuestRepository>()),
///   child: const GuestsScreen(),
/// )
/// ```
///
/// The default constructor owns the bloc it creates: it is made the first
/// time something reads it (at once with `lazy: false`) and closed when this
/// provider leaves the tree. [BlocProvider.value] hands on a bloc that
/// already exists - to a dialog, to another route - and never closes it,
/// since whoever made it will.
class BlocProvider<T extends StateStreamableSource<Object?>>
    extends StatelessWidget
    implements SingleChildWidget {
  const BlocProvider({
    required T Function(BuildContext context) create,
    super.key,
    this.child,
    this.lazy = true,
  }) : _create = create,
       _value = null;

  const BlocProvider.value({required T value, super.key, this.child})
    : _value = value,
      _create = null,
      lazy = true;

  final Widget? child;

  /// Whether the bloc is created on first read rather than straight away.
  final bool lazy;

  final T Function(BuildContext context)? _create;
  final T? _value;

  /// The bloc of type [T] provided above [context]. With `listen: true` the
  /// tree is also rebuilt whenever it emits, as `context.watch` does.
  static T of<T extends StateStreamableSource<Object?>>(
    BuildContext context, {
    bool listen = false,
  }) {
    final host = _findProvider<T>(context);
    if (host == null) throw ProviderNotFoundException(T);
    if (listen) host.follow();
    return host.value;
  }

  static void _close(StateStreamableSource<Object?> bloc) => bloc.close();

  @override
  Widget withChild(Widget child) => _create != null
      ? BlocProvider<T>(key: key, create: _create, lazy: lazy, child: child)
      : BlocProvider<T>.value(key: key, value: _value as T, child: child);

  @override
  Widget build(BuildContext context) => _Provided<T>(
    create: _create,
    value: _value,
    lazy: lazy,
    dispose: _close,
    child: _childOf(child, BlocProvider<T>),
  );
}

/// Provides a repository - or any object that is not a bloc - to everything
/// built below it, read back with `context.read<T>()`.
///
/// ```dart
/// RepositoryProvider(
///   create: (context) => GuestRepository(api),
///   child: const App(),
/// )
/// ```
///
/// Like [BlocProvider], the value is created on first read unless `lazy` is
/// false. It is not closed - a repository has no `close` to call - unless a
/// [dispose] says how.
class RepositoryProvider<T> extends StatelessWidget
    implements SingleChildWidget {
  const RepositoryProvider({
    required T Function(BuildContext context) create,
    void Function(T value)? dispose,
    super.key,
    this.child,
    this.lazy = true,
  }) : _create = create,
       _dispose = dispose,
       _value = null;

  const RepositoryProvider.value({required T value, super.key, this.child})
    : _value = value,
      _create = null,
      _dispose = null,
      lazy = true;

  final Widget? child;
  final bool lazy;

  final T Function(BuildContext context)? _create;
  final void Function(T value)? _dispose;
  final T? _value;

  /// The repository of type [T] provided above [context].
  static T of<T>(BuildContext context, {bool listen = false}) {
    final host = _findProvider<T>(context);
    if (host == null) throw ProviderNotFoundException(T);
    if (listen) host.follow();
    return host.value;
  }

  @override
  Widget withChild(Widget child) => _create != null
      ? RepositoryProvider<T>(
          key: key,
          create: _create,
          dispose: _dispose,
          lazy: lazy,
          child: child,
        )
      : RepositoryProvider<T>.value(key: key, value: _value as T, child: child);

  @override
  Widget build(BuildContext context) => _Provided<T>(
    create: _create,
    value: _value,
    lazy: lazy,
    dispose: _dispose,
    child: _childOf(child, RepositoryProvider<T>),
  );
}

/// Nests [widgets] around [child], the first outermost - so each can read
/// the ones written before it.
Widget _nest(List<SingleChildWidget> widgets, Widget child) {
  var tree = child;
  for (final widget in widgets.reversed) {
    tree = widget.withChild(tree);
  }
  return tree;
}

/// Several [BlocProvider]s as a flat list rather than a staircase.
///
/// ```dart
/// MultiBlocProvider(
///   providers: [
///     BlocProvider(create: (_) => SessionBloc()),
///     BlocProvider(create: (context) => GuestsBloc(context.read())),
///   ],
///   child: const App(),
/// )
/// ```
///
/// Exactly the nesting it replaces: an entry can read the entries above it.
class MultiBlocProvider extends StatelessWidget {
  const MultiBlocProvider({
    required this.providers,
    required this.child,
    super.key,
  });

  final List<SingleChildWidget> providers;
  final Widget child;

  @override
  Widget build(BuildContext context) => _nest(providers, child);
}

/// Several [RepositoryProvider]s as a flat list; see [MultiBlocProvider].
class MultiRepositoryProvider extends StatelessWidget {
  const MultiRepositoryProvider({
    required this.providers,
    required this.child,
    super.key,
  });

  final List<SingleChildWidget> providers;
  final Widget child;

  @override
  Widget build(BuildContext context) => _nest(providers, child);
}

/// Several `BlocListener`s as a flat list; see [MultiBlocProvider].
class MultiBlocListener extends StatelessWidget {
  const MultiBlocListener({
    required this.listeners,
    required this.child,
    super.key,
  });

  final List<SingleChildWidget> listeners;
  final Widget child;

  @override
  Widget build(BuildContext context) => _nest(listeners, child);
}
