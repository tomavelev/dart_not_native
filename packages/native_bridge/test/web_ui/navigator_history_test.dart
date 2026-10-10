@TestOn('browser')
/// `Navigator.push` and `MaterialApp(routes:)` against the browser's own
/// history, with its own `popstate`.
///
/// `test/widgets/navigator_history_test.dart` covers the cases against a fake
/// that behaves as a browser should; this is the same thing asked of a real
/// one, where Back is asynchronous and an entry is something only the
/// browser can count.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/web_ui/browser_history.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

late BuildContext _context;

class _Page extends StatelessWidget {
  const _Page(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    _context = context;
    return Scaffold(body: Text(name));
  }
}

/// Long enough for the browser to deliver a `popstate` and the app to redraw.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late AppTester tester;

  String showing() => tester.texts.last;

  Future<void> pressBack() async {
    web.window.history.back();
    await settle();
  }

  setUp(() {
    SystemBack.clearHandlers();
    HistoryAdapter.mirrors = 0;
    // An entry of this test's own to start from, so that Back from the app's
    // first screen lands somewhere in this document and not out of the suite.
    web.window.history.pushState(null, '', '#');
    HistoryAdapter.platform = BrowserHistoryAdapter();
    // Once for the page, however many tests: a second listener would report
    // every Back twice.
    bindBrowserBack();
  });

  tearDown(() {
    tester.app.unmount();
    HistoryAdapter.platform = null;
    HistoryAdapter.mirrors = 0;
    SystemBack.clearHandlers();
  });

  test('Back pops a pushed page', () async {
    tester = AppTester.widget(const _Page('Home'));
    unawaited(
      Navigator.of(_context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const _Page('Details')),
      ),
    );
    await settle();
    expect(showing(), 'Details');

    await pressBack();

    expect(showing(), 'Home');
  });

  test('two pages deep is two Backs', () async {
    tester = AppTester.widget(const _Page('Home'));
    for (final name in ['One', 'Two']) {
      unawaited(
        Navigator.of(_context).push<void>(
          MaterialPageRoute<void>(builder: (_) => _Page(name)),
        ),
      );
      await settle();
    }

    await pressBack();
    expect(showing(), 'One');
    await pressBack();
    expect(showing(), 'Home');
  });

  test("the app's own pop leaves no entry behind for Back to trip on",
      () async {
    tester = AppTester.widget(const _Page('Home'));
    final before = web.window.history.length;
    unawaited(
      Navigator.of(_context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const _Page('Details')),
      ),
    );
    await settle();
    expect(web.window.history.length, before + 1);

    Navigator.of(_context).pop();
    await settle();

    expect(showing(), 'Home');
    // Pushing again reuses the place the first one had: the browser dropped
    // the entry the app walked back from.
    unawaited(
      Navigator.of(_context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const _Page('Again')),
      ),
    );
    await settle();
    expect(web.window.history.length, before + 1);
    await pressBack();
    expect(showing(), 'Home');
  });

  test('Back closes a dialog over the first screen, and stays', () async {
    tester = AppTester.widget(const _Page('Home'));
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
    expect(showing(), 'Home');
  });

  test('a named route is in the URL, and Back pops it', () async {
    tester = AppTester.widget(
      MaterialApp(
        routes: {
          '/': (_) => const _Page('Home'),
          '/details': (_) => const _Page('Details'),
        },
      ),
    );
    await settle();
    expect(web.window.location.hash, '#/');

    unawaited(Navigator.of(_context).pushNamed<void>('/details'));
    await settle();
    expect(showing(), 'Details');
    expect(web.window.location.hash, '#/details');

    await pressBack();

    expect(showing(), 'Home');
    expect(web.window.location.hash, '#/');

    // And Forward brings the page back.
    web.window.history.forward();
    await settle();

    expect(showing(), 'Details');
    expect(web.window.location.hash, '#/details');
  });
}
