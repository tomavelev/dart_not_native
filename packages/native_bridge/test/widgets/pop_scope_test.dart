/// `PopScope`: a page with a say in whether it may be left.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late BuildContext _context;

/// What each scope heard, as `name: didPop result`.
final List<String> heard = [];

/// Whether the editor's scope lets the page go. A test changes it and asks
/// for a rebuild, as a screen does when its form becomes dirty.
bool _canPop = false;

class _Home extends StatelessWidget {
  const _Home({this.guarded = false});
  final bool guarded;

  @override
  Widget build(BuildContext context) {
    _context = context;
    const page = Scaffold(body: Text('Home', key: ValueKey('page')));
    return guarded
        ? PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) =>
                heard.add('home: $didPop $result'),
            child: page,
          )
        : page;
  }
}

class _Editor extends StatefulWidget {
  const _Editor();

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  @override
  Widget build(BuildContext context) {
    _context = context;
    return PopScope<String>(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) =>
          heard.add('editor: $didPop $result'),
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit')),
        body: Column(
          children: [
            const Text('Editor', key: ValueKey('page')),
            ElevatedButton(
              key: const ValueKey('clean'),
              onPressed: () => setState(() => _canPop = true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late AppTester tester;

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> pushEditor() async {
    unawaited(
      Navigator.of(_context).push<String>(
        MaterialPageRoute<String>(builder: (_) => const _Editor()),
      ),
    );
    await settle();
  }

  /// The platform's back gesture, and whether anything took it.
  Future<bool> back() async {
    final taken = SystemBack.dispatch();
    await settle();
    return taken;
  }

  String showing() => tester.text('page');

  setUp(() {
    SystemBack.clearHandlers();
    heard.clear();
    _canPop = false;
  });

  tearDown(() {
    tester.app.unmount();
    SystemBack.clearHandlers();
  });

  group('a page that is not to be left', () {
    setUp(() async {
      tester = AppTester.widget(const _Home());
      await pushEditor();
    });

    test('stays where it is on the back gesture, and is told', () async {
      final taken = await back();

      expect(taken, isTrue, reason: 'or the platform would close the app');
      expect(showing(), 'Editor');
      expect(heard, ['editor: false null']);
    });

    test('stays where it is on maybePop, which says it was dealt with',
        () async {
      final handled = await Navigator.of(_context).maybePop();
      await settle();

      expect(handled, isTrue);
      expect(showing(), 'Editor');
      expect(heard, ['editor: false null']);
    });

    test("stays where it is on the app bar's back arrow", () async {
      final arrow = tester
          .ofType('AppBar')
          .single
          .props
          .entries
          .firstWhere((entry) => entry.key.toLowerCase().contains('event'));
      await tester.emit(arrow.value as String);
      await settle();

      expect(showing(), 'Editor');
      expect(heard, ['editor: false null']);
    });

    test('goes when the app pops it, whatever canPop says', () async {
      Navigator.of(_context).pop('saved');
      await settle();

      expect(showing(), 'Home');
      expect(heard, ['editor: true saved']);
    });

    test('is asked every time, not once', () async {
      await back();
      await back();

      expect(heard, ['editor: false null', 'editor: false null']);
    });

    test('goes on the back gesture once it says it may', () async {
      await tester.tap('clean');
      await settle();

      await back();

      expect(showing(), 'Home');
      expect(heard, ['editor: true null']);
    });

    test('a dialog over it takes the back gesture first', () async {
      unawaited(
        showDialog<void>(
          context: _context,
          builder: (_) => const AlertDialog(title: Text('Discard?')),
        ),
      );
      await settle();
      expect(tester.ofType('Dialog'), hasLength(1));

      await back();

      expect(tester.ofType('Dialog'), isEmpty);
      expect(heard, isEmpty, reason: 'the page was not asked');

      await back();
      expect(showing(), 'Editor');
      expect(heard, ['editor: false null']);
    });
  });

  test('a page that may be left hears that it was, with the result',
      () async {
    _canPop = true;
    tester = AppTester.widget(const _Home());
    await pushEditor();

    Navigator.of(_context).pop('done');
    await settle();

    expect(heard, ['editor: true done']);
  });

  test("a result of another type is null, not an error", () async {
    _canPop = true;
    tester = AppTester.widget(const _Home());
    // A route that can be popped with anything, under a scope that expects
    // a String.
    unawaited(
      Navigator.of(_context).push<Object?>(
        MaterialPageRoute<Object?>(builder: (_) => const _Editor()),
      ),
    );
    await settle();

    Navigator.of(_context).pop(42);
    await settle();

    expect(heard, ['editor: true null']);
  });

  test('the page underneath is not asked about the one on top', () async {
    tester = AppTester.widget(const _Home(guarded: true));
    _canPop = true;
    await pushEditor();

    await back();

    expect(showing(), 'Home');
    expect(heard, ['editor: true null']);
  });

  group("on an app's first screen", () {
    test('a refused back gesture is taken, so the app stays open', () async {
      tester = AppTester.widget(const _Home(guarded: true));
      await settle();

      expect(await back(), isTrue);
      expect(heard, ['home: false null']);
    });

    test('with nothing refusing, the gesture is the platform\'s', () async {
      tester = AppTester.widget(const _Home());
      await settle();

      expect(await back(), isFalse);
    });
  });

  test('onPopInvoked, the older spelling, hears the same', () async {
    final calls = <bool>[];
    tester = AppTester.widget(
      PopScope<Object?>(
        canPop: false,
        onPopInvoked: calls.add,
        child: const Scaffold(body: Text('Home', key: ValueKey('page'))),
      ),
    );
    await settle();

    await back();

    expect(calls, [false]);
  });
}
