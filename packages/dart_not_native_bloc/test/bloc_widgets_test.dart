/// The widgets that react to a bloc: what they build, when they are told,
/// and when they stop listening.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:dart_not_native_bloc/dart_not_native_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The shape of a helper real apps write over the widgets here: generic in
/// the bloc and its state, bounded as flutter_bloc's own are. It has to
/// type-check as written.
abstract interface class _HasError {
  String? get error;
}

class _FormState implements _HasError {
  const _FormState({this.error, this.saved = 0});
  @override
  final String? error;
  final int saved;
}

class _FormCubit extends Cubit<_FormState> {
  _FormCubit() : super(const _FormState());
  void fail(String message) => emit(_FormState(error: message));
  void save() => emit(_FormState(saved: state.saved + 1));
}

class _ErrorListener<B extends StateStreamable<S>, S extends _HasError>
    extends StatelessWidget {
  const _ErrorListener({required this.onError, required this.child});

  final void Function(String message) onError;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<B, S>(
    listenWhen: (previous, current) =>
        current.error != null && current.error != previous.error,
    listener: (context, state) => onError(state.error!),
    child: child,
  );
}

Widget _count(String id) => BlocBuilder<CounterCubit, int>(
  builder: (_, state) => Text('$state', key: ValueKey(id)),
);

void main() {
  group('BlocBuilder', () {
    test('builds from the current state, then from each new one', () async {
      final cubit = CounterCubit(2);
      final h = Harness(BlocProvider.value(value: cubit, child: _count('n')));
      expect(h.text('n'), '2');

      cubit.increment();
      await h.pump();

      expect(h.text('n'), '3');
    });

    test('buildWhen turns states down, and sees the one before', () async {
      final cubit = CounterCubit();
      final seen = <String>[];
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: BlocBuilder<CounterCubit, int>(
            buildWhen: (previous, current) {
              seen.add('$previous>$current');
              return current.isEven;
            },
            builder: (_, state) => Text('$state', key: const ValueKey('n')),
          ),
        ),
      );

      cubit.increment();
      await h.pump();
      expect(h.text('n'), '0', reason: '1 was turned down');
      expect(h.renders, 1, reason: 'and asked for no rebuild');

      cubit.increment();
      await h.pump();
      expect(h.text('n'), '2');
      expect(seen, ['0>1', '1>2']);
    });

    test(
      'a state that was turned down stays turned down across rebuilds',
      () async {
        final cubit = CounterCubit();
        final other = ValueNotifier(0);
        final h = Harness(
          BlocProvider.value(
            value: cubit,
            child: ValueListenableBuilder<int>(
              valueListenable: other,
              builder: (_, _, _) => BlocBuilder<CounterCubit, int>(
                buildWhen: (_, current) => current.isEven,
                builder: (_, state) => Text('$state', key: const ValueKey('n')),
              ),
            ),
          ),
        );
        cubit.increment();
        await h.pump();

        // Something unrelated redraws the tree: the builder runs again, with
        // the state it had.
        other.value++;

        expect(h.text('n'), '0');
      },
    );

    test('takes an explicit bloc over the provided one', () {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(1),
          child: BlocBuilder<CounterCubit, int>(
            bloc: CounterCubit(8),
            builder: (_, state) => Text('$state', key: const ValueKey('n')),
          ),
        ),
      );

      expect(h.text('n'), '8');
    });

    test('follows the new bloc when it is handed a different one', () async {
      final first = CounterCubit(1);
      final second = CounterCubit(50);
      final which = ValueNotifier(first);
      final h = Harness(
        ValueListenableBuilder<CounterCubit>(
          valueListenable: which,
          builder: (_, cubit, _) => BlocBuilder<CounterCubit, int>(
            bloc: cubit,
            builder: (_, state) => Text('$state', key: const ValueKey('n')),
          ),
        ),
      );

      which.value = second;
      expect(h.text('n'), '50');

      first.increment();
      await h.pump();
      expect(h.text('n'), '50', reason: 'the old bloc is no longer heard');

      second.increment();
      await h.pump();
      expect(h.text('n'), '51');
    });

    test('several builders on one bloc cost one rebuild per emit', () async {
      final cubit = CounterCubit();
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: Column(children: [_count('a'), _count('b'), _count('c')]),
        ),
      );
      expect(h.renders, 1);

      cubit.increment();
      await h.pump();

      expect([h.text('a'), h.text('b'), h.text('c')], ['1', '1', '1']);
      expect(h.renders, 2);
    });

    test('stops listening when it leaves the tree', () async {
      final cubit = CounterCubit();
      final show = ValueNotifier(true);
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, shown, _) => shown ? _count('n') : const SizedBox(),
          ),
        ),
      );
      show.value = false;
      final renders = h.renders;

      cubit.increment();
      await h.pump();

      expect(h.renders, renders);
    });
  });

  group('BlocListener', () {
    test(
      'is called once per change, however often the tree rebuilds',
      () async {
        final cubit = CounterCubit();
        final other = ValueNotifier(0);
        final heard = <int>[];
        Harness(
          BlocProvider.value(
            value: cubit,
            child: ValueListenableBuilder<int>(
              valueListenable: other,
              builder: (_, _, _) => BlocListener<CounterCubit, int>(
                listener: (_, state) => heard.add(state),
                child: _count('n'),
              ),
            ),
          ),
        );

        cubit.increment();
        await pumpEventQueue();
        other.value++;
        other.value++;
        cubit.increment();
        await pumpEventQueue();

        expect(heard, [1, 2]);
      },
    );

    test('is not called for the state it started with', () async {
      final heard = <int>[];
      Harness(
        BlocProvider(
          create: (_) => CounterCubit(4),
          child: BlocListener<CounterCubit, int>(
            listener: (_, state) => heard.add(state),
            child: const SizedBox(),
          ),
        ),
      );
      await pumpEventQueue();

      expect(heard, isEmpty);
    });

    test('listenWhen filters, and sees the state before', () async {
      final cubit = CounterCubit();
      final heard = <int>[];
      final seen = <String>[];
      Harness(
        BlocListener<CounterCubit, int>(
          bloc: cubit,
          listenWhen: (previous, current) {
            seen.add('$previous>$current');
            return current.isOdd;
          },
          listener: (_, state) => heard.add(state),
          child: const SizedBox(),
        ),
      );

      cubit
        ..increment()
        ..increment()
        ..increment();
      await pumpEventQueue();

      expect(heard, [1, 3]);
      // The previous state is the bloc's previous state, heard or not.
      expect(seen, ['0>1', '1>2', '2>3']);
    });

    test('hands the listener a context it can act with', () async {
      final cubit = CounterCubit();
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: BlocListener<CounterCubit, int>(
              listener: (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('now $state'))),
              child: const SizedBox(),
            ),
          ),
        ),
      );

      cubit.increment();
      await h.pump();

      expect(h.nodes.where((n) => n.props['message'] == 'now 1'), hasLength(1));
    });

    test('stops listening when it leaves the tree', () async {
      final cubit = CounterCubit();
      final show = ValueNotifier(true);
      final heard = <int>[];
      Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? BlocListener<CounterCubit, int>(
                  bloc: cubit,
                  listener: (_, state) => heard.add(state),
                  child: const SizedBox(),
                )
              : const SizedBox(),
        ),
      );
      cubit.increment();
      await pumpEventQueue();

      show.value = false;
      cubit.increment();
      await pumpEventQueue();

      expect(heard, [1]);
    });

    test(
      'an emit already on its way when it leaves is not delivered',
      () async {
        final cubit = CounterCubit();
        final show = ValueNotifier(true);
        final heard = <int>[];
        Harness(
          ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, shown, _) => shown
                ? BlocListener<CounterCubit, int>(
                    bloc: cubit,
                    listener: (_, state) => heard.add(state),
                    child: const SizedBox(),
                  )
                : const SizedBox(),
          ),
        );

        cubit.increment();
        show.value = false;
        await pumpEventQueue();

        expect(heard, isEmpty);
      },
    );

    test('moves to the new bloc when its bloc changes', () async {
      final first = CounterCubit();
      final second = CounterCubit(100);
      final which = ValueNotifier(first);
      final heard = <int>[];
      Harness(
        ValueListenableBuilder<CounterCubit>(
          valueListenable: which,
          // The provider is told which bloc; the listener finds it there.
          builder: (_, cubit, _) => BlocProvider.value(
            value: cubit,
            child: BlocListener<CounterCubit, int>(
              listener: (_, state) => heard.add(state),
              child: const SizedBox(),
            ),
          ),
        ),
      );

      which.value = second;
      first.increment();
      second.increment();
      await pumpEventQueue();

      expect(heard, [101]);
    });

    test(
      'a generic helper over it type-checks and filters as written',
      () async {
        final cubit = _FormCubit();
        final errors = <String>[];
        Harness(
          BlocProvider.value(
            value: cubit,
            child: _ErrorListener<_FormCubit, _FormState>(
              onError: errors.add,
              child: const SizedBox(),
            ),
          ),
        );

        cubit
          ..save()
          ..fail('offline')
          ..fail('offline')
          ..save();
        await pumpEventQueue();

        expect(errors, ['offline']);
      },
    );
  });

  group('MultiBlocListener', () {
    test('nests listeners written without children', () async {
      final counter = CounterCubit();
      final form = _FormCubit();
      final heard = <String>[];
      final h = Harness(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: counter),
            BlocProvider.value(value: form),
          ],
          child: MultiBlocListener(
            listeners: [
              BlocListener<CounterCubit, int>(
                listener: (_, state) => heard.add('count $state'),
              ),
              BlocListener<_FormCubit, _FormState>(
                listener: (_, state) => heard.add('saved ${state.saved}'),
              ),
            ],
            child: const Text('child', key: ValueKey('child')),
          ),
        ),
      );
      expect(h.text('child'), 'child');

      counter.increment();
      form.save();
      await pumpEventQueue();

      expect(heard, ['count 1', 'saved 1']);
    });

    test('a listener with no child is only valid inside one', () {
      expect(
        () => Harness(
          BlocListener<CounterCubit, int>(
            bloc: CounterCubit(),
            listener: (_, _) {},
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('BlocConsumer', () {
    test('builds and listens, each under its own condition', () async {
      final cubit = CounterCubit();
      final heard = <int>[];
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: BlocConsumer<CounterCubit, int>(
            listenWhen: (_, current) => current.isOdd,
            listener: (_, state) => heard.add(state),
            buildWhen: (_, current) => current.isEven,
            builder: (_, state) => Text('$state', key: const ValueKey('n')),
          ),
        ),
      );

      cubit.increment();
      await h.pump();
      expect(h.text('n'), '0');
      expect(heard, [1]);

      cubit.increment();
      await h.pump();
      expect(h.text('n'), '2');
      expect(heard, [1]);
    });
  });

  group('BlocSelector', () {
    test('rebuilds only when the selected part changes', () async {
      final cubit = CounterCubit();
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: BlocSelector<CounterCubit, int, bool>(
            selector: (state) => state >= 2,
            builder: (_, reached) =>
                Text(reached ? 'reached' : 'not yet', key: const ValueKey('n')),
          ),
        ),
      );
      expect(h.text('n'), 'not yet');

      cubit.increment();
      await h.pump();
      expect(h.renders, 1, reason: 'the selection did not change');

      cubit.increment();
      await h.pump();
      expect(h.text('n'), 'reached');
      expect(h.renders, 2);
    });
  });
}
