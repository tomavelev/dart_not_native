part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Builders: widgets that are a function, and the two that wait for one.
// ---------------------------------------------------------------------------

/// A widget that is its [builder] - the way to get a context from *below*
/// something the surrounding build has just put in the tree.
class Builder extends StatelessWidget {
  const Builder({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => builder(context);
}

/// Hands a `setState` to a builder, for state too small to deserve a class:
/// the checkbox inside a dialog.
class StatefulBuilder extends StatefulWidget {
  const StatefulBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, StateSetter setState) builder;
  @override
  State<StatefulBuilder> createState() => _StatefulBuilderState();
}

/// The `setState` a [StatefulBuilder] hands out.
typedef StateSetter = void Function(VoidCallback fn);

class _StatefulBuilderState extends State<StatefulBuilder> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}

/// Gives [child] a [key] without anything else: an identity for a subtree
/// whose own widget cannot carry one.
class KeyedSubtree extends StatefulWidget {
  const KeyedSubtree({super.key, required this.child});
  final Widget child;
  @override
  State<KeyedSubtree> createState() => _KeyedSubtreeState();
}

// A State of its own is what makes the key mean something: the child's
// position hangs below this state, so the subtree's states travel with the
// key rather than with the place it happens to be drawn in.
class _KeyedSubtreeState extends State<KeyedSubtree> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Where an asynchronous computation is.
enum ConnectionState {
  /// Not connected to anything: no future, no stream.
  none,

  /// Connected and waiting for the first result.
  waiting,

  /// A stream that has produced something and may produce more.
  active,

  /// Finished.
  done,
}

/// The latest thing a future or a stream had to say.
class AsyncSnapshot<T> {
  const AsyncSnapshot._(
    this.connectionState,
    this.data,
    this.error,
    this.stackTrace,
  );

  const AsyncSnapshot.nothing()
    : this._(ConnectionState.none, null, null, null);
  const AsyncSnapshot.waiting()
    : this._(ConnectionState.waiting, null, null, null);
  const AsyncSnapshot.withData(ConnectionState state, T data)
    : this._(state, data, null, null);
  const AsyncSnapshot.withError(
    ConnectionState state,
    Object error, [
    StackTrace stackTrace = StackTrace.empty,
  ]) : this._(state, null, error, stackTrace);

  final ConnectionState connectionState;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;

  bool get hasData => data != null;
  bool get hasError => error != null;

  /// The data, or the error thrown, or a [StateError] when there is neither.
  T get requireData {
    if (hasData) return data as T;
    if (hasError) Error.throwWithStackTrace(error!, stackTrace!);
    throw StateError('Snapshot has neither data nor error');
  }

  /// The same result, at another stage of the connection.
  AsyncSnapshot<T> inState(ConnectionState state) =>
      AsyncSnapshot<T>._(state, data, error, stackTrace);

  @override
  bool operator ==(Object other) =>
      other is AsyncSnapshot<T> &&
      other.connectionState == connectionState &&
      other.data == data &&
      other.error == error;
  @override
  int get hashCode => Object.hash(connectionState, data, error);
  @override
  String toString() => 'AsyncSnapshot<$T>($connectionState, $data, $error)';
}

/// Builds a widget from an [AsyncSnapshot].
typedef AsyncWidgetBuilder<T> =
    Widget Function(BuildContext context, AsyncSnapshot<T> snapshot);

/// Builds from the latest state of a [future].
///
/// As in Flutter, the future must be one the app holds on to - made in
/// `initState`, or kept in a field - and not one created in the `build` that
/// builds this widget: a new future on every build is a new wait on every
/// build.
class FutureBuilder<T> extends StatefulWidget {
  const FutureBuilder({
    super.key,
    required this.future,
    this.initialData,
    required this.builder,
  });

  final Future<T>? future;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<FutureBuilder<T>> createState() => _FutureBuilderState<T>();
}

class _FutureBuilderState<T> extends State<FutureBuilder<T>> {
  /// Which future the snapshot belongs to: an answer from one the widget has
  /// since replaced must not be shown.
  Object? _token;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    final initial = widget.initialData;
    _snapshot = initial == null
        ? AsyncSnapshot<T>.nothing()
        : AsyncSnapshot<T>.withData(ConnectionState.none, initial);
    _subscribe();
  }

  @override
  void didUpdateWidget(FutureBuilder<T> oldWidget) {
    if (identical(oldWidget.future, widget.future)) return;
    _token = null;
    _snapshot = _snapshot.inState(ConnectionState.none);
    _subscribe();
  }

  void _subscribe() {
    final future = widget.future;
    if (future == null) return;
    final token = _token = Object();
    future.then<void>(
      (data) {
        if (!identical(_token, token) || !mounted) return;
        setState(() {
          _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, data);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!identical(_token, token) || !mounted) return;
        setState(() {
          _snapshot = AsyncSnapshot<T>.withError(
            ConnectionState.done,
            error,
            stackTrace,
          );
        });
      },
    );
    // Unless it answered synchronously, which a future never does.
    if (_snapshot.connectionState != ConnectionState.done) {
      _snapshot = _snapshot.inState(ConnectionState.waiting);
    }
  }

  @override
  void dispose() => _token = null;

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}

/// Builds from the latest event of a [stream].
class StreamBuilder<T> extends StatefulWidget {
  const StreamBuilder({
    super.key,
    this.initialData,
    required this.stream,
    required this.builder,
  });

  final Stream<T>? stream;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  @override
  State<StreamBuilder<T>> createState() => _StreamBuilderState<T>();
}

class _StreamBuilderState<T> extends State<StreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    final initial = widget.initialData;
    _snapshot = initial == null
        ? AsyncSnapshot<T>.nothing()
        : AsyncSnapshot<T>.withData(ConnectionState.none, initial);
    _subscribe();
  }

  @override
  void didUpdateWidget(StreamBuilder<T> oldWidget) {
    if (identical(oldWidget.stream, widget.stream)) return;
    _unsubscribe();
    _snapshot = _snapshot.inState(ConnectionState.none);
    _subscribe();
  }

  void _subscribe() {
    final stream = widget.stream;
    if (stream == null) return;
    _snapshot = _snapshot.inState(ConnectionState.waiting);
    _subscription = stream.listen(
      (data) => _set(AsyncSnapshot<T>.withData(ConnectionState.active, data)),
      onError: (Object error, StackTrace stackTrace) => _set(
        AsyncSnapshot<T>.withError(ConnectionState.active, error, stackTrace),
      ),
      onDone: () => _set(_snapshot.inState(ConnectionState.done)),
    );
  }

  void _set(AsyncSnapshot<T> snapshot) {
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() => _unsubscribe();

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);
}
