/// Unit tests for keeping the router and the platform's history in step.
library;

import 'package:dart_not_native/core.dart' hide Router;
import 'package:dart_not_native/routing/history_sync.dart';
import 'package:dart_not_native/routing/navigation_app.dart';
import 'package:dart_not_native/routing/route.dart';
import 'package:dart_not_native/src/system_back.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what a platform with a history stack would have been told.
class FakeHistoryAdapter extends HistoryAdapter {
  final List<String> calls = [];

  @override
  bool get hasStack => true;

  @override
  void push(String path) => calls.add('push $path');

  @override
  void replace(String path) => calls.add('replace $path');

  @override
  void back() => calls.add('back');

  @override
  void forward() => calls.add('forward');
}

Route route(String path, String name) =>
    Route(path: path, name: name, builder: (_) => UIBuilder.text(name));

Router router() => Router(
  config: RouterConfig(
    routes: [
      route('/', 'home'),
      route('/users', 'users'),
      route('/users/:id', 'user'),
    ],
    initialPath: '/',
  ),
);

void main() {
  setUp(SystemBack.clearHandlers);
  tearDown(SystemBack.clearHandlers);

  group('on a platform with no history stack (Android, iOS)', () {
    late Router r;
    late RouterHistorySync sync;

    setUp(() {
      r = router();
      sync = RouterHistorySync(router: r)..bind();
    });

    test('binding registers one back handler', () {
      expect(sync.isBound, isTrue);
      expect(SystemBack.handlerCount, 1);
    });

    test('the back gesture pops a route and reports it as consumed', () async {
      await r.navigate('/users');

      expect(SystemBack.dispatch(), isTrue);

      expect(r.currentPath, '/');
    });

    test('on the first screen it declines, so the app closes as usual', () {
      expect(SystemBack.dispatch(), isFalse);
      expect(r.currentPath, '/');
    });

    test('repeated gestures walk the whole stack, then decline', () async {
      await r.navigate('/users');
      await r.navigate('/users/7');

      expect(SystemBack.dispatch(), isTrue);
      expect(r.currentPath, '/users');
      expect(SystemBack.dispatch(), isTrue);
      expect(r.currentPath, '/');
      expect(SystemBack.dispatch(), isFalse);
    });

    test('an in-app back button leaves the gesture working', () async {
      await r.navigate('/users');
      await r.navigate('/users/7');

      r.goBack();

      expect(
        SystemBack.dispatch(),
        isTrue,
        reason: 'the in-app pop must not be mistaken for a platform one',
      );
      expect(r.currentPath, '/');
    });

    test('unbinding hands the gesture back to the platform', () async {
      await r.navigate('/users');

      sync.unbind();

      expect(sync.isBound, isFalse);
      expect(SystemBack.dispatch(), isFalse);
      expect(r.currentPath, '/users');
    });

    test('binding twice registers one handler', () {
      sync.bind();

      expect(SystemBack.handlerCount, 1);
    });
  });

  group('on a platform with a history stack (browser)', () {
    late Router r;
    late FakeHistoryAdapter adapter;
    late RouterHistorySync sync;

    setUp(() {
      r = router();
      adapter = FakeHistoryAdapter();
      sync = RouterHistorySync(router: r, adapter: adapter)..bind();
    });

    test('binding seeds the platform with the current route', () {
      expect(adapter.calls, ['replace /']);
    });

    test('navigation is mirrored into the platform history', () async {
      await r.navigate('/users');
      await r.navigate('/users/7');

      expect(adapter.calls, ['replace /', 'push /users', 'push /users/7']);
    });

    test('replaceWith is mirrored as a replace', () async {
      await r.navigate('/users');
      adapter.calls.clear();

      r.replaceWith('/users/7');

      expect(adapter.calls, ['replace /users/7']);
    });

    test('a platform pop moves the router without pushing back', () async {
      await r.navigate('/users');
      adapter.calls.clear();

      expect(sync.handleBack(), isTrue);

      expect(r.currentPath, '/');
      expect(
        adapter.calls,
        isEmpty,
        reason: 'the platform already popped its own stack',
      );
    });

    test('an in-app back button pops the platform stack too', () async {
      await r.navigate('/users');
      adapter.calls.clear();

      r.goBack();

      expect(adapter.calls, ['back']);
    });

    test(
      'the pop the in-app button caused is not read as a second back',
      () async {
        await r.navigate('/users');
        await r.navigate('/users/7');
        r.goBack();
        expect(r.currentPath, '/users');

        // The browser answers the adapter.back() above with a popstate.
        expect(sync.handleBack(), isTrue);

        expect(
          r.currentPath,
          '/users',
          reason: 'the app must not skip two screens for one gesture',
        );
        expect(sync.handleBack(), isTrue);
        expect(r.currentPath, '/');
      },
    );

    test('going forward in the app is mirrored too', () async {
      await r.navigate('/users');
      r.goBack();
      adapter.calls.clear();

      r.goForward();

      expect(adapter.calls, ['forward']);
    });

    test('the platform going forward steps the router on, and is not '
        'written back', () async {
      await r.navigate('/users');
      // The browser's Back, then its Forward.
      SystemBack.dispatch();
      expect(r.currentPath, '/');
      adapter.calls.clear();

      expect(SystemBack.dispatchForward(), isTrue);

      expect(r.currentPath, '/users');
      expect(adapter.calls, isEmpty, reason: 'the platform is already there');
    });

    test('forward with nothing ahead is not taken', () async {
      await r.navigate('/users');

      expect(SystemBack.dispatchForward(), isFalse);
      expect(r.currentPath, '/users');
    });

    test('a forward the app asked for is not read as the user\'s, and does '
        'not cost the next Back', () async {
      await r.navigate('/users');
      await r.navigate('/users/7');
      r.goBack();
      SystemBack.dispatch(); // the platform reporting that pop
      r.goBack();
      SystemBack.dispatch();
      expect(r.currentPath, '/');

      r.goForward();
      // The platform reporting the forward the adapter was asked for.
      expect(SystemBack.dispatchForward(), isTrue);
      expect(r.currentPath, '/users', reason: 'one step, not two');

      // And a Back the user presses is the user's.
      SystemBack.dispatch();
      expect(r.currentPath, '/');
    });

    test('back past the first route declines', () {
      expect(sync.handleBack(), isFalse);
    });

    group('with a dialog open', () {
      test('a back the dialog consumed puts the platform entry back', () async {
        await r.navigate('/users');
        adapter.calls.clear();
        // Registered after the router, as an overlay opened later is.
        SystemBack.addHandler(() => true);

        expect(SystemBack.dispatch(), isTrue);

        expect(r.currentPath, '/users');
        expect(adapter.calls, [
          'push /users',
        ], reason: 'the browser already moved back; the screen did not');
      });

      test('a back the router consumed pushes nothing', () async {
        await r.navigate('/users');
        adapter.calls.clear();

        expect(SystemBack.dispatch(), isTrue);

        expect(adapter.calls, isEmpty);
      });

      test('a back nobody consumed pushes nothing', () {
        adapter.calls.clear();

        expect(SystemBack.dispatch(), isFalse);

        expect(adapter.calls, isEmpty);
      });

      test('the pop an in-app button caused never reaches it', () async {
        await r.navigate('/users');
        var dialogClosed = false;
        SystemBack.addHandler(() => dialogClosed = true);

        r.goBack();
        // The browser answers the adapter.back() with a popstate.
        expect(SystemBack.dispatch(), isTrue);

        expect(dialogClosed, isFalse);
        expect(r.currentPath, '/');
      });

      test('unbinding stops restoring entries', () async {
        await r.navigate('/users');
        sync.unbind();
        adapter.calls.clear();
        SystemBack.addHandler(() => true);

        SystemBack.dispatch();

        expect(adapter.calls, isEmpty);
      });
    });
  });

  group('NavigationApp', () {
    late NavigationApp app;

    setUp(() {
      app =
          (NavigationAppBuilder()
                ..setInitialPath('/')
                ..addRoute(
                  path: '/',
                  name: 'home',
                  builder: (_) => UIBuilder.text('Home', id: 'screen'),
                )
                ..addRoute(
                  path: '/users',
                  name: 'users',
                  builder: (_) => UIBuilder.text('Users', id: 'screen'),
                ))
              .build();
    });

    test('does not touch the back gesture until asked', () {
      expect(app.handlesSystemBack, isFalse);
      expect(SystemBack.hasHandlers, isFalse);
    });

    test('bindSystemBack pops a route and re-renders', () async {
      final renderer = InMemoryRenderer();
      app.render(renderer);
      app.bindSystemBack();
      await app.navigate('/users');
      expect(renderer.tree!.props['content'], 'Users');

      expect(SystemBack.dispatch(), isTrue);

      expect(app.currentPath, '/');
      expect(
        renderer.tree!.props['content'],
        'Home',
        reason: 'the platform gesture must repaint like any navigation',
      );
    });

    test('declines once the app is at its first screen', () {
      app.bindSystemBack();

      expect(SystemBack.dispatch(), isFalse);
    });

    test('unbindSystemBack releases the gesture', () async {
      app.bindSystemBack();
      await app.navigate('/users');

      app.unbindSystemBack();

      expect(app.handlesSystemBack, isFalse);
      expect(SystemBack.dispatch(), isFalse);
      expect(app.currentPath, '/users');
    });

    test('binding twice keeps one handler', () {
      app.bindSystemBack();
      app.bindSystemBack();

      expect(SystemBack.handlerCount, 1);
    });
  });
}
