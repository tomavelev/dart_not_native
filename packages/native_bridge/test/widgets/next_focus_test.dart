/// `FocusScope.of(context).nextFocus()`: the keyboard, sent to the next field.
///
/// A renderer focuses a field when its `focusVersion` goes up, so "which
/// field was asked" is read here off the tree.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late BuildContext _context;

class _Form extends StatelessWidget {
  const _Form({this.second, this.secondEnabled = true, this.nodes});

  /// Stands in for the second field when a test wants something else there.
  final Widget? second;
  final bool secondEnabled;

  /// A node for each of the three fields, when a test wants to hold them.
  final List<FocusNode>? nodes;

  @override
  Widget build(BuildContext context) {
    _context = context;
    TextField field(int index, String id) => TextField(
      key: ValueKey(id),
      focusNode: nodes?[index],
      enabled: index != 1 || secondEnabled,
      // What nearly every form does: on Enter, on to the next.
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
    return Scaffold(
      body: Column(
        children: [
          field(0, 'name'),
          second ?? field(1, 'email'),
          field(2, 'phone'),
        ],
      ),
    );
  }
}

void main() {
  late AppTester tester;

  /// The ids of the fields asked to take the keyboard, most recent last.
  List<String> asked() {
    final fields = tester.ofType('TextField')
      ..sort(
        (a, b) => ((a.props['focusVersion'] as int?) ?? 0).compareTo(
          (b.props['focusVersion'] as int?) ?? 0,
        ),
      );
    return [
      for (final field in fields)
        if (field.props['focusVersion'] != null &&
            field.props['focusRequested'] != false)
          field.props['id'] as String,
    ];
  }

  Future<void> submit(String id) => tester.submitInto(id, 'x');

  group('from a field\'s own onSubmitted', () {
    setUp(() => tester = AppTester.widget(const _Form()));

    test('no field is asked for the keyboard until something asks', () {
      expect(asked(), isEmpty);
    });

    test('goes to the field after it', () async {
      await submit('name');

      expect(asked(), ['email']);
    });

    test('and from that one to the one after', () async {
      await submit('email');

      expect(asked(), ['phone']);
    });

    test('and from the last round to the first', () async {
      await submit('phone');

      expect(asked(), ['name']);
    });

    test('says that it moved', () async {
      late bool moved;
      tester = AppTester.widget(
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextField(
                  key: const ValueKey('a'),
                  onSubmitted: (_) =>
                      moved = FocusScope.of(context).nextFocus(),
                ),
                const TextField(key: ValueKey('b')),
              ],
            ),
          ),
        ),
      );

      await tester.submitInto('a', 'x');

      expect(moved, isTrue);
      expect(asked(), ['b']);
    });
  });

  test('previousFocus goes the other way, and round from the first', () async {
    tester = AppTester.widget(
      Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              for (final id in ['a', 'b', 'c'])
                TextField(
                  key: ValueKey(id),
                  onSubmitted: (_) => FocusScope.of(context).previousFocus(),
                ),
            ],
          ),
        ),
      ),
    );

    await tester.submitInto('c', 'x');
    expect(asked(), ['b']);

    await tester.submitInto('a', 'x');
    expect(asked().last, 'c');
  });

  group('a field the keyboard cannot go to is passed over', () {
    test('a disabled one', () async {
      tester = AppTester.widget(const _Form(secondEnabled: false));

      await submit('name');

      expect(asked(), ['phone']);
    });

    test('a read-only one', () async {
      tester = AppTester.widget(
        const _Form(second: TextField(key: ValueKey('email'), readOnly: true)),
      );

      await submit('name');

      expect(asked(), ['phone']);
    });

    test('one whose node says skipTraversal', () async {
      tester = AppTester.widget(
        _Form(
          second: TextField(
            key: const ValueKey('email'),
            focusNode: FocusNode(skipTraversal: true),
          ),
        ),
      );

      await submit('name');

      expect(asked(), ['phone']);
    });
  });

  test('with one field there is nowhere to go, and it says so', () async {
    late bool moved;
    tester = AppTester.widget(
      Builder(
        builder: (context) => Scaffold(
          body: TextField(
            key: const ValueKey('only'),
            onSubmitted: (_) => moved = FocusScope.of(context).nextFocus(),
          ),
        ),
      ),
    );

    await tester.submitInto('only', 'x');

    expect(moved, isFalse);
    expect(asked(), isEmpty);
  });

  test('with no field at all it is false', () {
    tester = AppTester.widget(
      Builder(
        builder: (context) {
          _context = context;
          return const Scaffold(body: Text('nothing to type into'));
        },
      ),
    );

    expect(FocusScope.of(_context).nextFocus(), isFalse);
  });

  group('called from outside a field', () {
    test('starts from the field whose node has the keyboard', () async {
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      tester = AppTester.widget(_Form(nodes: nodes));
      // What a renderer sends when the user taps into the second field.
      await tester.emit('${tester.eventIdOf('email')}_focus');
      expect(nodes[1].hasFocus, isTrue);

      expect(FocusScope.of(_context).nextFocus(), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(asked(), ['phone']);
    });

    test('with no way to know where the keyboard is, starts at the first',
        () async {
      tester = AppTester.widget(const _Form());

      expect(FocusScope.of(_context).nextFocus(), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(asked(), ['name']);
    });
  });

  test('a field asked this way keeps its place through a rebuild', () async {
    tester = AppTester.widget(const _Form());
    await submit('name');
    final version = tester.get('email').props['focusVersion'];

    // Anything that rebuilds: the ask is not made again.
    await submit('phone');

    expect(tester.get('email').props['focusVersion'], version);
  });

  test('a field that was not given a node sends no focus events', () {
    tester = AppTester.widget(const _Form());

    final events = tester.get('name').props.keys.toList();
    expect(events, isNot(contains('focusEventId')));
    // And nothing it was not sending before says it wants the keyboard.
    expect(tester.get('name').props.containsKey('focusVersion'), isFalse);
  });
}
