/// Providers: where a value can be read from, when it is made, and who
/// cleans it up.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:dart_not_native_bloc/dart_not_native_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

class _Repository {
  _Repository(this.name);
  final String name;
  bool disposed = false;
}

class _SpecialCubit extends Cubit0 {}

/// Shows whatever [read] makes of the context, or the error it throws.
class _Probe extends StatelessWidget {
  const _Probe(this.id, this.read);
  final String id;
  final Object? Function(BuildContext context) read;

  @override
  Widget build(BuildContext context) {
    String shown;
    try {
      shown = '${read(context)}';
    } on ProviderNotFoundException catch (e) {
      shown = 'not found: ${e.valueType}';
    }
    return Text(shown, key: ValueKey(id));
  }
}

/// A screen that reads its bloc as it enters the tree, as real ones do to
/// start loading.
class _LoadsOnInit extends StatefulWidget {
  const _LoadsOnInit();
  @override
  State<_LoadsOnInit> createState() => _LoadsOnInitState();
}

class _LoadsOnInitState extends State<_LoadsOnInit> {
  @override
  void initState() {
    super.initState();
    context.read<CounterCubit>().set(7);
  }

  @override
  Widget build(BuildContext context) =>
      Text('${context.read<CounterCubit>().state}', key: const ValueKey('n'));
}

void main() {
  group('lookup', () {
    test('a provided bloc is read by everything built below it', () {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(3),
          child: _Probe('n', (c) => c.read<CounterCubit>().state),
        ),
      );

      expect(h.text('n'), '3');
    });

    test('and by nothing built beside it', () {
      final h = Harness(
        Column(
          children: [
            _Probe('beside', (c) => c.read<_Repository>().name),
            RepositoryProvider(
              create: (_) => _Repository('api'),
              child: _Probe('below', (c) => c.read<_Repository>().name),
            ),
          ],
        ),
      );

      expect(h.text('below'), 'api');
      expect(h.text('beside'), 'not found: _Repository');
    });

    test('the nearest provider wins', () {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(1),
          child: Column(
            children: [
              _Probe('outer', (c) => c.read<CounterCubit>().state),
              BlocProvider(
                create: (_) => CounterCubit(2),
                child: _Probe('inner', (c) => c.read<CounterCubit>().state),
              ),
            ],
          ),
        ),
      );

      expect(h.text('outer'), '1');
      expect(h.text('inner'), '2');
    });

    test('a provider is found by the type it was provided as, exactly', () {
      final h = Harness(
        // Inferred from `create`: a provider of _SpecialCubit.
        BlocProvider(
          create: (_) => _SpecialCubit(),
          child: Column(
            children: [
              _Probe('exact', (c) => c.read<_SpecialCubit>().state),
              _Probe('wider', (c) => c.read<Cubit0>().state),
            ],
          ),
        ),
      );

      expect(h.text('exact'), '0');
      expect(h.text('wider'), 'not found: Cubit0');
    });

    test('a subtype provided as its supertype is found by the supertype', () {
      final h = Harness(
        BlocProvider<Cubit0>(
          create: (_) => _SpecialCubit(),
          child: Column(
            children: [
              _Probe('declared', (c) => c.read<Cubit0>().runtimeType),
              _Probe('actual', (c) => c.read<_SpecialCubit>().state),
            ],
          ),
        ),
      );

      expect(h.text('declared'), '_SpecialCubit');
      expect(h.text('actual'), 'not found: _SpecialCubit');
    });

    test('BlocProvider.of and RepositoryProvider.of read the same values', () {
      final h = Harness(
        RepositoryProvider(
          create: (_) => _Repository('api'),
          child: BlocProvider(
            create: (_) => CounterCubit(4),
            child: Column(
              children: [
                _Probe('bloc', (c) => BlocProvider.of<CounterCubit>(c).state),
                _Probe(
                  'repo',
                  (c) => RepositoryProvider.of<_Repository>(c).name,
                ),
              ],
            ),
          ),
        ),
      );

      expect(h.text('bloc'), '4');
      expect(h.text('repo'), 'api');
    });

    test('a State can read its bloc in initState', () {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(),
          child: const _LoadsOnInit(),
        ),
      );

      expect(h.text('n'), '7');
    });
  });

  group('creation and disposal', () {
    test('a lazy provider creates its bloc on first read', () {
      var created = 0;
      final show = ValueNotifier(false);
      final h = Harness(
        BlocProvider(
          create: (_) {
            created++;
            return CounterCubit();
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, shown, _) => shown
                ? _Probe('n', (c) => c.read<CounterCubit>().state)
                : const SizedBox(),
          ),
        ),
      );
      expect(created, 0);

      show.value = true;

      expect(created, 1);
      expect(h.text('n'), '0');
      show
        ..value = false
        ..value = true;
      expect(created, 1, reason: 'made once, however often it is read');
    });

    test('lazy: false creates it on the way into the tree', () {
      var created = 0;
      Harness(
        BlocProvider(
          lazy: false,
          create: (_) {
            created++;
            return CounterCubit();
          },
          child: const SizedBox(),
        ),
      );

      expect(created, 1);
    });

    test('a bloc the provider created is closed when it leaves the tree', () {
      final cubit = CounterCubit();
      final show = ValueNotifier(true);
      Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? BlocProvider(
                  create: (_) => cubit,
                  child: _Probe('n', (c) => c.read<CounterCubit>().state),
                )
              : const SizedBox(),
        ),
      );
      expect(cubit.closed, isFalse);

      show.value = false;

      expect(cubit.closed, isTrue);
    });

    test('a lazy bloc nobody read is never created, so never closed', () {
      var created = 0;
      final show = ValueNotifier(true);
      Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? BlocProvider(
                  create: (_) {
                    created++;
                    return CounterCubit();
                  },
                  child: const SizedBox(),
                )
              : const SizedBox(),
        ),
      );

      show.value = false;

      expect(created, 0);
    });

    test('BlocProvider.value never closes the bloc it was given', () {
      final cubit = CounterCubit(5);
      final show = ValueNotifier(true);
      final h = Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? BlocProvider.value(
                  value: cubit,
                  child: _Probe('n', (c) => c.read<CounterCubit>().state),
                )
              : const SizedBox(),
        ),
      );
      expect(h.text('n'), '5');

      show.value = false;

      expect(cubit.closed, isFalse);
    });

    test('a repository is disposed only if it says how', () {
      final plain = _Repository('plain');
      final cleaned = _Repository('cleaned');
      final show = ValueNotifier(true);
      Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? RepositoryProvider(
                  lazy: false,
                  create: (_) => plain,
                  child: RepositoryProvider<Object>(
                    lazy: false,
                    create: (_) => cleaned,
                    dispose: (value) => (value as _Repository).disposed = true,
                    child: const SizedBox(),
                  ),
                )
              : const SizedBox(),
        ),
      );

      show.value = false;

      expect(plain.disposed, isFalse);
      expect(cleaned.disposed, isTrue);
    });
  });

  group('Multi* providers', () {
    Widget app({required Widget child}) => MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => _Repository('guests')),
        RepositoryProvider(create: (_) => 42),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _SpecialCubit()..set(9)),
          // Reads a repository from the list above, and an entry before it
          // in its own list.
          BlocProvider(
            create: (ctx) =>
                CounterCubit(ctx.read<int>() + ctx.read<_SpecialCubit>().state),
          ),
        ],
        child: child,
      ),
    );

    test('nest in order, so an entry can read the ones before it', () {
      final h = Harness(
        app(
          child: Column(
            children: [
              _Probe('repo', (c) => c.read<_Repository>().name),
              _Probe('value', (c) => c.read<_SpecialCubit>().state),
              _Probe('sum', (c) => c.read<CounterCubit>().state),
            ],
          ),
        ),
      );

      expect(h.text('repo'), 'guests');
      expect(h.text('value'), '9');
      expect(h.text('sum'), '51');
    });

    test('a provider with no child is only valid inside one', () {
      expect(
        () => Harness(BlocProvider(create: (_) => CounterCubit())),
        throwsStateError,
      );
    });
  });

  group('outside a build', () {
    test('a callback can read, long after the build', () async {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(),
          child: _Tapper(
            child: BlocBuilder<CounterCubit, int>(
              builder: (_, state) => Text('$state', key: const ValueKey('n')),
            ),
          ),
        ),
      );

      await h.tap('tap');
      await h.tap('tap');

      expect(h.text('n'), '2');
    });

    test('a bloc handed on to a dialog is the same bloc', () async {
      final h = Harness(
        BlocProvider(
          create: (_) => CounterCubit(),
          child: const _OpensDialog(),
        ),
      );

      await h.tap('open');
      expect(h.text('in_dialog'), '0');

      // Read from inside the dialog, where two providers now hold the bloc.
      await h.tap('dialog_tap');

      expect(h.text('in_dialog'), '1');
      expect(h.text('behind'), '1');
    });

    test('a callback reads the provider above where it was written', () async {
      final h = Harness(
        Column(
          children: [
            for (final row in ['a', 'b'])
              BlocProvider(
                create: (_) => CounterCubit(),
                child: Builder(
                  builder: (context) => Column(
                    children: [
                      Text(
                        '${context.watch<CounterCubit>().state}',
                        key: ValueKey(row),
                      ),
                      ElevatedButton(
                        key: ValueKey('${row}_tap'),
                        onPressed: () =>
                            context.read<CounterCubit>().increment(),
                        child: const Text('+'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

      await h.tap('b_tap');

      expect(h.text('a'), '0');
      expect(h.text('b'), '1');
    });

    test('a missing provider is reported by type', () {
      late BuildContext captured;
      Harness(
        _Probe('p', (c) {
          captured = c;
          return null;
        }),
      );

      expect(
        () => captured.read<CounterCubit>(),
        throwsA(
          isA<ProviderNotFoundException>().having(
            (e) => e.valueType,
            'valueType',
            CounterCubit,
          ),
        ),
      );
    });
  });

  group('watch and select', () {
    test('watch rebuilds the tree when the bloc emits', () async {
      final cubit = CounterCubit();
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: _Probe('n', (c) => c.watch<CounterCubit>().state),
        ),
      );
      expect(h.text('n'), '0');

      cubit.increment();
      await h.pump();

      expect(h.text('n'), '1');
    });

    test('read does not', () async {
      final cubit = CounterCubit();
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: _Probe('n', (c) => c.read<CounterCubit>().state),
        ),
      );

      cubit.increment();
      await h.pump();

      expect(h.text('n'), '0');
      expect(h.renders, 1);
    });

    test('select reads one aspect and follows it', () async {
      final cubit = CounterCubit(3);
      final h = Harness(
        BlocProvider.value(
          value: cubit,
          child: _Probe(
            'even',
            (c) => c.select((CounterCubit cubit) => cubit.state.isEven),
          ),
        ),
      );
      expect(h.text('even'), 'false');

      cubit.increment();
      await h.pump();

      expect(h.text('even'), 'true');
    });

    test('watching stops when the provider leaves the tree', () async {
      final cubit = CounterCubit();
      final show = ValueNotifier(true);
      final h = Harness(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, shown, _) => shown
              ? BlocProvider.value(
                  value: cubit,
                  child: _Probe('n', (c) => c.watch<CounterCubit>().state),
                )
              : const SizedBox(),
        ),
      );
      show.value = false;
      final renders = h.renders;

      cubit.increment();
      await h.pump();

      expect(h.renders, renders);
    });

    test('watching a repository is just reading it', () {
      final h = Harness(
        RepositoryProvider.value(
          value: _Repository('api'),
          child: _Probe('n', (c) => c.watch<_Repository>().name),
        ),
      );

      expect(h.text('n'), 'api');
    });
  });
}

class _Tapper extends StatelessWidget {
  const _Tapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      child,
      ElevatedButton(
        key: const ValueKey('tap'),
        onPressed: () => context.read<CounterCubit>().increment(),
        child: const Text('+'),
      ),
    ],
  );
}

class _OpensDialog extends StatelessWidget {
  const _OpensDialog();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      BlocBuilder<CounterCubit, int>(
        builder: (_, state) => Text('$state', key: const ValueKey('behind')),
      ),
      ElevatedButton(
        key: const ValueKey('open'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<CounterCubit>(),
            child: AlertDialog(
              content: BlocBuilder<CounterCubit, int>(
                builder: (_, state) =>
                    Text('$state', key: const ValueKey('in_dialog')),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('dialog_tap'),
                  onPressed: () => context.read<CounterCubit>().increment(),
                  child: const Text('+'),
                ),
              ],
            ),
          ),
        ),
        child: const Text('open'),
      ),
    ],
  );
}
