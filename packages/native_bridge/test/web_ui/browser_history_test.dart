@TestOn('browser')
/// Browser tests for the web back button.
///
/// Run with: flutter test --platform chrome
library;

import 'package:dart_not_native/core.dart' hide Router;
import 'package:dart_not_native/routing/route.dart';
import 'package:dart_not_native/web_ui/browser_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

Route route(String path, String name) =>
    Route(path: path, name: name, builder: (_) => UIBuilder.text(name));

Router router() => Router(
  config: RouterConfig(
    routes: [route('/', 'home'), route('/users', 'users')],
    initialPath: '/',
  ),
);

/// Waits for the browser to deliver a popstate for a history move.
Future<void> settleHistory() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late BrowserHistoryAdapter adapter;

  setUp(() {
    SystemBack.clearHandlers();
    adapter = BrowserHistoryAdapter();
  });

  tearDown(SystemBack.clearHandlers);

  test('declares that the browser keeps a history stack', () {
    expect(adapter.hasStack, isTrue);
  });

  test('push writes the route into the URL fragment', () {
    adapter.push('/users/7');

    expect(web.window.location.hash, '#/users/7');
    expect(adapter.currentPath, '/users/7');
  });

  test('replace swaps the fragment without growing the stack', () async {
    adapter.replace('/a');
    final lengthBefore = web.window.history.length;

    adapter.replace('/b');

    expect(adapter.currentPath, '/b');
    expect(web.window.history.length, lengthBefore);
  });

  test('currentPath is null when the URL carries no route', () {
    adapter.replace('');

    expect(adapter.currentPath, isNull);
  });

  test('push then back returns to the previous route', () async {
    adapter.replace('/');
    adapter.push('/users');
    expect(adapter.currentPath, '/users');

    adapter.back();
    await settleHistory();

    expect(adapter.currentPath, '/');
  });

  test('forward re-enters the route a back left behind', () async {
    adapter.replace('/');
    adapter.push('/users');
    adapter.back();
    await settleHistory();

    adapter.forward();
    await settleHistory();

    expect(adapter.currentPath, '/users');
  });

  group('bindBrowserBack', () {
    test('the browser Back button pops the router', () async {
      final r = router();
      RouterHistorySync(router: r, adapter: adapter).bind();
      bindBrowserBack();
      await r.navigate('/users');
      expect(adapter.currentPath, '/users');

      web.window.history.back();
      await settleHistory();

      expect(r.currentPath, '/');
    });

    test('the browser Forward button is not a Back', () async {
      // popstate fires for both, so Forward used to dispatch a Back - closing
      // the dialog the user had just moved past, or popping a route they had
      // just returned to.
      var backs = 0;
      SystemBack.addHandler(() {
        backs++;
        return true;
      });
      addTearDown(SystemBack.clearHandlers);
      bindBrowserBack();

      adapter.replace('/');
      adapter.push('/users');
      web.window.history.back();
      await settleHistory();
      expect(backs, 1, reason: 'the Back is a Back');

      web.window.history.forward();
      await settleHistory();

      expect(backs, 1, reason: 'and the Forward is not another one');
    });

    test('an entry this app did not write still counts as a Back', () async {
      // A link or a hand-typed fragment carries no index; treating it as a
      // Back is what it was before, and the safer guess for an unlabelled move.
      var backs = 0;
      SystemBack.addHandler(() {
        backs++;
        return true;
      });
      addTearDown(SystemBack.clearHandlers);
      bindBrowserBack();

      web.window.history.pushState(null, '', '#/elsewhere');
      web.window.history.back();
      await settleHistory();

      expect(backs, 1);
    });

    test('an in-app back button moves the URL too', () async {
      final r = router();
      RouterHistorySync(router: r, adapter: adapter).bind();
      bindBrowserBack();
      await r.navigate('/users');

      r.goBack();
      await settleHistory();

      expect(r.currentPath, '/');
      expect(
        adapter.currentPath,
        '/',
        reason: 'the URL must follow the app, not lag a screen behind',
      );
    });
  });
}
