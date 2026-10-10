/// Which `State` belongs to which widget.
///
/// A `State` outlives the build that created it, so the framework has to
/// recognise a widget it has seen before. A [Key] is the app saying "this is
/// the same thing wherever it moves to"; without one, a widget is identified by
/// its place in the tree - the rule Flutter follows, and the reason two widgets
/// of the same type side by side each keep their own state.
library;

import 'package:dart_not_native/core.dart' show SystemBack;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

/// A counter that is *not* keyed, so only its position identifies it. Its
/// children carry ids so a test can address them.
class _Counter extends StatefulWidget {
  const _Counter(this.name, {super.key});

  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$count', key: ValueKey('${widget.name}_text')),
          ElevatedButton(
            key: ValueKey('${widget.name}_button'),
            onPressed: () => setState(() => count++),
            child: const Text('+'),
          ),
        ],
      );
}

/// The order the reorder tests draw, flipped from the test itself.
final _order = ValueNotifier<List<String>>(['a', 'b']);

class _OrderScreen extends StatelessWidget {
  const _OrderScreen({required this.keyed});

  /// Whether the counters carry a [Key] - the whole question of these tests.
  final bool keyed;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ValueListenableBuilder<List<String>>(
          valueListenable: _order,
          builder: (context, names, _) => Column(
            children: [
              for (final name in names)
                keyed ? _Counter(name, key: ValueKey('k_$name')) : _Counter(name),
            ],
          ),
        ),
      );
}

/// A screen and a dialog, each with a counter of the same type.
class _DialogScreen extends StatelessWidget {
  const _DialogScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            const _Counter('screen'),
            ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => const AlertDialog(
                  title: Text('Dialog'),
                  content: _Counter('dialog'),
                ),
              ),
              child: const Text('Open'),
            ),
          ],
        ),
      );
}

/// Two routes drawing the same kind of screen.
class _RoutedApp extends StatelessWidget {
  const _RoutedApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (context, params) => Scaffold(
                body: Column(
                  children: [
                    const _Counter('home'),
                    ElevatedButton(
                      key: const ValueKey('to_other'),
                      onPressed: () => Navigator.of(context).pushNamed('/other'),
                      child: const Text('Go'),
                    ),
                  ],
                ),
              ),
          '/other': (context, params) =>
              const Scaffold(body: _Counter('other')),
        },
      );
}

class _Screen extends StatelessWidget {
  const _Screen(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(body: Column(children: children));
}

void main() {
  late AppTester tester;

  setUp(SystemBack.clearHandlers);
  tearDown(SystemBack.clearHandlers);

  String countOf(String name) => tester.text('${name}_text');
  Future<void> bump(String name) => tester.tap('${name}_button');

  test('two keyless widgets of a type each keep their own state', () async {
    tester = AppTester.mount(
      hostApp(const _Screen([_Counter('a'), _Counter('b')])),
    );

    await bump('a');
    await bump('a');

    expect(countOf('a'), '2');
    expect(countOf('b'), '0', reason: 'the second counter is a second widget');
  });

  test('a widget keeps its state across an ordinary rebuild', () {
    tester = AppTester.mount(
      hostApp(const _Screen([_Counter('a'), _Counter('b')])),
    );

    return () async {
      await bump('a');
      // Any rebuild: the other counter's setState re-runs the whole tree.
      await bump('b');

      expect(countOf('a'), '1');
      expect(countOf('b'), '1');
    }();
  });

  group('when the order changes', () {
    setUp(() => _order.value = ['a', 'b']);

    test('a key carries the state with it', () async {
      tester = AppTester.mount(hostApp(const _OrderScreen(keyed: true)));
      await bump('a');
      await bump('a');

      _order.value = ['b', 'a'];

      // The state went where the key went, which is what a key is for.
      expect(countOf('a'), '2');
      expect(countOf('b'), '0');
    });

    test('without a key the state stays where it was', () async {
      tester = AppTester.mount(hostApp(const _OrderScreen(keyed: false)));
      await bump('a');
      await bump('a');

      _order.value = ['b', 'a'];

      // The honest limit, and Flutter's own: a keyless widget *is* its
      // position, so the counter now drawn first inherits what the counter
      // drawn first had. Give rows that move a key.
      expect(countOf('b'), '2');
      expect(countOf('a'), '0');
    });
  });

  test('a dialog is its own place, not the screen behind it', () async {
    tester = AppTester.mount(hostApp(const _DialogScreen()));
    await bump('screen');
    await bump('screen');

    await tester.tap('open');

    expect(countOf('screen'), '2');
    expect(countOf('dialog'), '0');
  });

  test('two routes drawing the same screen do not share one state', () async {
    tester = AppTester.mount(hostApp(const _RoutedApp()));
    await bump('home');
    await bump('home');

    await tester.tap('to_other');

    // Before position mattered, both counters answered to "_Counter" and the
    // second route opened on the first route's number.
    expect(countOf('other'), '0');
  });

  test('nesting is part of the place, not just the order', () async {
    tester = AppTester.mount(
      hostApp(const _Screen([
        _Counter('top'),
        Card(child: _Counter('nested')),
      ])),
    );

    await bump('nested');

    expect(countOf('nested'), '1');
    expect(countOf('top'), '0');
  });
}
