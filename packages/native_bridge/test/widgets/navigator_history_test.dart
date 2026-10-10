/// The browser's Back button, for an app that never wired a router to it.
///
/// `MaterialApp(routes:)` and `Navigator.push` reach the platform's history
/// by themselves. The browser here is a fake that behaves as the real one
/// does in the two ways that matter: Back moves to the entry before, and the
/// app only hears about it when that entry is one the app wrote - from the
/// first entry, Back leaves the site and the app is told nothing.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBrowser extends HistoryAdapter {
  FakeBrowser([String? openedAt]) : entries = [openedAt];

  /// The fragment of each entry, oldest first; the first is the page load.
  final List<String?> entries;
  int at = 0;

  /// Whether Back was pressed with nothing of the app's behind it.
  bool left = false;

  @override
  bool get hasStack => true;

  @override
  String? get currentPath => entries[at];

  @override
  void push(String path) {
    entries
      ..removeRange(at + 1, entries.length)
      ..add(path);
    at++;
  }

  @override
  void replace(String path) => entries[at] = path;

  /// Back, whoever asked for it: the browser reports both the same way.
  @override
  void back() {
    if (at == 0) {
      left = true;
      return;
    }
    at--;
    scheduleMicrotask(SystemBack.dispatch);
  }

  @override
  void forward() {
    if (at < entries.length - 1) at++;
  }
}

late BuildContext _context;

class _Page extends StatelessWidget {
  const _Page(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    _context = context;
    return Scaffold(body: Text(name, key: const ValueKey('page')));
  }
}

void main() {
  late FakeBrowser browser;
  late AppTester tester;

  /// Lets a `popstate` arrive and the rebuild it causes run.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> pressBack() async {
    browser.back();
    await settle();
  }

  Future<void> push(String name) async {
    unawaited(
      Navigator.of(_context).push<void>(
        MaterialPageRoute<void>(builder: (_) => _Page(name)),
      ),
    );
    await settle();
  }

  String showing() => tester.texts.last;

  setUp(() {
    SystemBack.clearHandlers();
    HistoryAdapter.mirrors = 0;
    browser = FakeBrowser();
    HistoryAdapter.platform = browser;
  });

  tearDown(() {
    tester.app.unmount();
    HistoryAdapter.platform = null;
    HistoryAdapter.mirrors = 0;
    SystemBack.clearHandlers();
  });

  group('Navigator.push', () {
    setUp(() => tester = AppTester.widget(const _Page('Home')));

    test('an app that pushes nothing writes nothing', () async {
      await settle();

      expect(browser.entries, [null]);
    });

    test('a pushed page puts one entry behind it', () async {
      await push('Details');

      expect(showing(), 'Details');
      expect(browser.entries, hasLength(2));
      expect(browser.at, 1);
    });

    test('Back pops the page instead of leaving the site', () async {
      await push('Details');

      await pressBack();

      expect(showing(), 'Home');
      expect(browser.left, isFalse);
    });

    test('and from the first screen Back leaves, as it should', () async {
      await push('Details');
      await pressBack();

      await pressBack();

      expect(browser.left, isTrue);
      expect(showing(), 'Home');
    });

    test('two pages deep is two Backs, with one entry at a time', () async {
      await push('One');
      await push('Two');
      expect(browser.at, 1);

      await pressBack();
      expect(showing(), 'One');
      expect(browser.at, 1, reason: 'the entry is put back for the next Back');

      await pressBack();
      expect(showing(), 'Home');
      expect(browser.at, 0);
      expect(browser.left, isFalse);
    });

    test("the app's own back button takes the entry away with the page",
        () async {
      await push('Details');

      Navigator.of(_context).pop();
      await settle();

      expect(showing(), 'Home');
      expect(browser.at, 0);
      expect(browser.left, isFalse);
    });

    test('and the pop that causes is not read as another Back', () async {
      await push('One');
      await push('Two');
      Navigator.of(_context).pop();
      await settle();
      expect(showing(), 'One');

      Navigator.of(_context).pop();
      await settle();

      expect(showing(), 'Home');
      expect(browser.left, isFalse);
    });

    test('a dialog over a pushed page takes Back first, and the page the next',
        () async {
      await push('Details');
      unawaited(
        showDialog<void>(
          context: _context,
          builder: (_) => const AlertDialog(title: Text('Sure?')),
        ),
      );
      await settle();
      expect(tester.ofType('Dialog'), hasLength(1));

      await pressBack();
      expect(tester.ofType('Dialog'), isEmpty);
      expect(showing(), 'Details');
      expect(browser.at, 1, reason: 'the entry the dialog spent is put back');

      await pressBack();
      expect(showing(), 'Home');
      expect(browser.left, isFalse);
    });
  });

  group('a dialog or a sheet', () {
    setUp(() => tester = AppTester.widget(const _Page('Home')));

    Future<void> ask({bool dismissible = true}) async {
      unawaited(
        showDialog<void>(
          context: _context,
          barrierDismissible: dismissible,
          builder: (_) => const AlertDialog(title: Text('Sure?')),
        ),
      );
      await settle();
    }

    test('over the first screen is closed by Back, which does not leave',
        () async {
      await ask();
      expect(browser.at, 1);

      await pressBack();

      expect(tester.ofType('Dialog'), isEmpty);
      expect(browser.left, isFalse);
      expect(browser.at, 0);
    });

    test('and the Back after that leaves, as it should', () async {
      await ask();
      await pressBack();

      await pressBack();

      expect(browser.left, isTrue);
    });

    test('closed by the app, it takes its entry with it', () async {
      await ask();

      Navigator.of(_context).pop();
      await settle();

      expect(tester.ofType('Dialog'), isEmpty);
      expect(browser.at, 0);
      expect(browser.left, isFalse);
    });

    test('one that cannot be dismissed keeps Back from leaving', () async {
      await ask(dismissible: false);

      await pressBack();
      await pressBack();

      expect(tester.ofType('Dialog'), hasLength(1));
      expect(browser.left, isFalse);
      expect(browser.at, 1);
    });

    test('a sheet is the same', () async {
      unawaited(
        showModalBottomSheet<void>(
          context: _context,
          builder: (_) => const Text('A sheet'),
        ),
      );
      await settle();
      expect(tester.ofType('BottomSheet'), hasLength(1));

      await pressBack();

      expect(tester.ofType('BottomSheet'), isEmpty);
      expect(browser.left, isFalse);
    });

    test('two open at once are two Backs', () async {
      await ask();
      await ask();
      expect(tester.ofType('Dialog'), hasLength(2));
      expect(browser.at, 1, reason: 'one entry, however many are open');

      await pressBack();
      expect(tester.ofType('Dialog'), hasLength(1));
      await pressBack();
      expect(tester.ofType('Dialog'), isEmpty);
      expect(browser.left, isFalse);
    });
  });

  test('a first screen that refuses to be left keeps Back in the app',
      () async {
    var asked = 0;
    tester = AppTester.widget(
      PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) => asked++,
        child: const _Page('Home'),
      ),
    );
    await settle();
    expect(browser.at, 1, reason: 'an entry for Back to land on');

    await pressBack();
    await pressBack();

    expect(asked, 2);
    expect(browser.left, isFalse);
    expect(browser.at, 1);
  });

  group('MaterialApp(routes:)', () {
    Widget app() => MaterialApp(
      routes: {
        '/': (_) => const _Page('Home'),
        '/details': (_) => const _Page('Details'),
        '/more': (_) => const _Page('More'),
      },
    );

    Future<void> go(String name) async {
      unawaited(Navigator.of(_context).pushNamed<void>(name));
      await settle();
    }

    test('the first route is written over the entry the page loaded on',
        () async {
      tester = AppTester.widget(app());
      await settle();

      expect(browser.entries, ['/']);
    });

    test('a named route is an entry, and its name is in the URL', () async {
      tester = AppTester.widget(app());

      await go('/details');

      expect(showing(), 'Details');
      expect(browser.entries, ['/', '/details']);
      expect(browser.currentPath, '/details');
    });

    test('Back pops it instead of leaving the site', () async {
      tester = AppTester.widget(app());
      await go('/details');
      await go('/more');

      await pressBack();
      expect(showing(), 'Details');
      expect(browser.currentPath, '/details');

      await pressBack();
      expect(showing(), 'Home');
      expect(browser.left, isFalse);
    });

    test('a link straight to a page opens it over the first one', () async {
      browser = FakeBrowser('/details');
      HistoryAdapter.platform = browser;

      tester = AppTester.widget(app());
      await settle();

      expect(showing(), 'Details');
      expect(browser.entries, ['/', '/details']);

      await pressBack();
      expect(showing(), 'Home');
    });

    test('a link to nowhere opens the first route', () async {
      browser = FakeBrowser('/not-a-route');
      HistoryAdapter.platform = browser;

      tester = AppTester.widget(app());
      await settle();

      expect(showing(), 'Home');
      expect(browser.entries, ['/']);
    });

    test('a page pushed over a named route needs no entry of its own',
        () async {
      tester = AppTester.widget(app());
      await go('/details');
      await push('Unnamed');
      expect(browser.entries, ['/', '/details']);

      await pressBack();

      expect(showing(), 'Details');
      // The router put back the entry that Back spent on the pushed page.
      expect(browser.currentPath, '/details');
      expect(browser.left, isFalse);
    });
  });

  test('with no history to mirror into, nothing is written and Back still pops',
      () async {
    HistoryAdapter.platform = null;
    tester = AppTester.widget(const _Page('Home'));
    await push('Details');

    SystemBack.dispatch();
    await settle();

    expect(showing(), 'Home');
  });
}
