/// The widgets that react to a bloc: build from its state, or act on a change.
library;

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:dart_not_native/widgets.dart';

import 'provider.dart';
import 'rebuild.dart';

/// Builds a widget from a bloc's state.
typedef BlocWidgetBuilder<S> = Widget Function(BuildContext context, S state);

/// Whether a builder should take the [current] state, given the one before.
typedef BlocBuilderCondition<S> = bool Function(S previous, S current);

/// Does something in answer to a state change.
typedef BlocWidgetListener<S> = void Function(BuildContext context, S state);

/// Whether a listener should be called for [current], given the one before.
typedef BlocListenerCondition<S> = bool Function(S previous, S current);

/// Picks the part of a state a [BlocSelector] builds from.
typedef BlocWidgetSelector<S, T> = T Function(S state);

/// What the widgets below share: one subscription to one bloc, moved when the
/// bloc is a different one and dropped when the widget leaves the tree.
abstract class _BlocState<
  W extends StatefulWidget,
  B extends StateStreamable<S>,
  S
>
    extends LiveState<W> {
  B? _bloc;
  StreamSubscription<S>? _subscription;
  late S _previous;

  /// The bloc the widget was handed, if it was handed one.
  B? get given;

  /// A bloc has been attached - the first, or a different one. Whatever was
  /// held from the last one's states no longer applies.
  void attached(B bloc) {}

  /// The bloc emitted [current], having been at [previous].
  void changed(S previous, S current);

  /// The bloc to build from: the one given, or the one provided. Called at
  /// the top of every build, which is what notices a different instance - a
  /// parent passing another `bloc:`, a provider above being replaced - and
  /// moves the subscription across.
  B attach(BuildContext context) {
    markBuilt();
    final bloc = given ?? context.read<B>();
    if (identical(bloc, _bloc)) return bloc;
    _subscription?.cancel();
    _bloc = bloc;
    _previous = bloc.state;
    attached(bloc);
    // The stream carries changes only, so the state the bloc is in right now
    // is never reported as one.
    _subscription = bloc.stream.listen((state) {
      // Cancelling does not recall an event already on its way.
      if (!alive || !identical(bloc, _bloc)) return;
      final previous = _previous;
      _previous = state;
      changed(previous, state);
    });
    return bloc;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

/// Rebuilds from a bloc's state.
///
/// ```dart
/// BlocBuilder<GuestsBloc, GuestsState>(
///   buildWhen: (previous, current) => previous.guests != current.guests,
///   builder: (context, state) => Text('${state.guests.length} guests'),
/// )
/// ```
///
/// The bloc is the one provided above unless [bloc] names another.
///
/// [buildWhen] decides which states [builder] is *given*: one it turns down
/// is skipped, and the builder goes on being handed the last it accepted. It
/// does not decide whether [builder] runs. In Flutter the two are the same
/// thing; here any change anywhere rebuilds the tree from the root, so a
/// builder may run again with the state it already had. Keep builders pure,
/// as Flutter also asks, and the difference is not visible.
class BlocBuilder<B extends StateStreamable<S>, S> extends StatefulWidget {
  const BlocBuilder({
    required this.builder,
    super.key,
    this.bloc,
    this.buildWhen,
  });

  final BlocWidgetBuilder<S> builder;
  final B? bloc;
  final BlocBuilderCondition<S>? buildWhen;

  @override
  State<BlocBuilder<B, S>> createState() => _BlocBuilderState<B, S>();
}

class _BlocBuilderState<B extends StateStreamable<S>, S>
    extends _BlocState<BlocBuilder<B, S>, B, S> {
  late S _state;

  @override
  B? get given => widget.bloc;

  @override
  void attached(B bloc) => _state = bloc.state;

  @override
  void changed(S previous, S current) {
    if (!(widget.buildWhen?.call(previous, current) ?? true)) return;
    _state = current;
    requestRebuild(this);
  }

  @override
  Widget build(BuildContext context) {
    attach(context);
    return widget.builder(context, _state);
  }
}

/// Calls [listener] once for each state change - for the things a build must
/// not do: show a snackbar, navigate, open a dialog.
///
/// ```dart
/// BlocListener<SessionBloc, SessionState>(
///   listenWhen: (previous, current) => current is SessionExpired,
///   listener: (context, state) => context.go('/login'),
///   child: const HomeScreen(),
/// )
/// ```
///
/// Once per change, however often the tree rebuilds, and never for the state
/// the bloc was already in when this started listening.
class BlocListener<B extends StateStreamable<S>, S> extends StatefulWidget
    implements SingleChildWidget {
  const BlocListener({
    required this.listener,
    super.key,
    this.bloc,
    this.listenWhen,
    this.child,
  });

  final BlocWidgetListener<S> listener;
  final B? bloc;
  final BlocListenerCondition<S>? listenWhen;
  final Widget? child;

  @override
  Widget withChild(Widget child) => BlocListener<B, S>(
    key: key,
    listener: listener,
    bloc: bloc,
    listenWhen: listenWhen,
    child: child,
  );

  @override
  State<BlocListener<B, S>> createState() => _BlocListenerState<B, S>();
}

class _BlocListenerState<B extends StateStreamable<S>, S>
    extends _BlocState<BlocListener<B, S>, B, S> {
  @override
  B? get given => widget.bloc;

  @override
  void changed(S previous, S current) {
    if (!(widget.listenWhen?.call(previous, current) ?? true)) return;
    widget.listener(context, current);
  }

  @override
  Widget build(BuildContext context) {
    attach(context);
    return widget.child ??
        (throw StateError(
          '$BlocListener was built without a child. A listener written '
          'without one belongs in the `listeners:` list of a '
          'MultiBlocListener.',
        ));
  }
}

/// A [BlocListener] and a [BlocBuilder] on one bloc, for a screen that both
/// draws a state and reacts to it.
///
/// ```dart
/// BlocConsumer<SessionBloc, SessionState>(
///   listenWhen: (_, current) => current is SessionFailed,
///   listener: (context, state) => showError(context, state),
///   builder: (context, state) => SignInButton(busy: state is SessionChecking),
/// )
/// ```
class BlocConsumer<B extends StateStreamable<S>, S> extends StatelessWidget {
  const BlocConsumer({
    required this.builder,
    required this.listener,
    super.key,
    this.bloc,
    this.buildWhen,
    this.listenWhen,
  });

  final BlocWidgetBuilder<S> builder;
  final BlocWidgetListener<S> listener;
  final B? bloc;
  final BlocBuilderCondition<S>? buildWhen;
  final BlocListenerCondition<S>? listenWhen;

  @override
  Widget build(BuildContext context) => BlocListener<B, S>(
    bloc: bloc,
    listenWhen: listenWhen,
    listener: listener,
    child: BlocBuilder<B, S>(
      bloc: bloc,
      buildWhen: buildWhen,
      builder: builder,
    ),
  );
}

/// Builds from one part of a bloc's state, and takes a new value only when
/// that part changes.
///
/// ```dart
/// BlocSelector<GuestsBloc, GuestsState, int>(
///   selector: (state) => state.guests.length,
///   builder: (context, count) => Text('$count guests'),
/// )
/// ```
class BlocSelector<B extends StateStreamable<S>, S, T> extends StatefulWidget {
  const BlocSelector({
    required this.selector,
    required this.builder,
    super.key,
    this.bloc,
  });

  final BlocWidgetSelector<S, T> selector;
  final BlocWidgetBuilder<T> builder;
  final B? bloc;

  @override
  State<BlocSelector<B, S, T>> createState() => _BlocSelectorState<B, S, T>();
}

class _BlocSelectorState<B extends StateStreamable<S>, S, T>
    extends _BlocState<BlocSelector<B, S, T>, B, S> {
  late T _selected;

  @override
  B? get given => widget.bloc;

  @override
  void attached(B bloc) => _selected = widget.selector(bloc.state);

  @override
  void changed(S previous, S current) {
    final selected = widget.selector(current);
    if (selected == _selected) return;
    _selected = selected;
    requestRebuild(this);
  }

  @override
  Widget build(BuildContext context) {
    attach(context);
    return widget.builder(context, _selected);
  }
}
