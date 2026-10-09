/// Unit tests for the Router: navigation, guards, listeners and history.
library;

import 'package:dart_not_native/core.dart' hide Router;
import 'package:dart_not_native/routing/route.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

Route route(
  String path,
  String name, {
  List<RouteGuard>? guards,
  RouteBuilder? builder,
}) => Route(
  path: path,
  name: name,
  guards: guards,
  builder:
      builder ??
      (params) => UIBuilder.text('$name ${params['id'] ?? ''}'.trim()),
);

Router router({
  List<Route>? routes,
  Route? notFound,
  String initial = '/home',
}) => Router(
  config: RouterConfig(
    routes:
        routes ??
        [
          route('/home', 'home'),
          route('/users/:id', 'user'),
          route('/settings', 'settings'),
        ],
    notFoundRoute: notFound,
    initialPath: initial,
  ),
);

void main() {
  group('Router construction', () {
    test('starts on the initial path', () {
      final r = router();

      expect(r.currentPath, '/home');
      expect(r.currentRoute.route.name, 'home');
      expect(r.history, ['/home']);
    });

    test('an unroutable initial path is rejected', () {
      expect(() => router(initial: '/nowhere'), throwsA(isA<ArgumentError>()));
    });
  });

  group('navigate', () {
    test('pushes the matched route and its path params', () async {
      final r = router();

      expect(await r.navigate('/users/42'), isTrue);

      expect(r.currentPath, '/users/42');
      expect(r.currentParams, {'id': '42'});
      expect(r.history, ['/home', '/users/42']);
    });

    test('explicit params are merged over the extracted ones', () async {
      final r = router();

      await r.navigate('/users/42', params: {'tab': 'posts'});

      expect(r.currentParams, {'id': '42', 'tab': 'posts'});
    });

    test('an unknown path is refused and leaves history alone', () async {
      final r = router();

      expect(await r.navigate('/nowhere'), isFalse);
      expect(r.history, ['/home']);
    });

    test(
      'an unknown path lands on the 404 route when one is configured',
      () async {
        final r = router(notFound: route('/404', 'not_found'));

        expect(await r.navigate('/nowhere'), isTrue);
        expect(r.currentRoute.route.name, 'not_found');
      },
    );

    test('navigateNamed resolves the path from the route name', () async {
      final r = router();

      expect(await r.navigateNamed('settings'), isTrue);
      expect(r.currentPath, '/settings');

      expect(await r.navigateNamed('nope'), isFalse);
    });
  });

  group('guards', () {
    test('a failing guard blocks navigation', () async {
      var allowed = false;
      final r = router(
        routes: [
          route('/home', 'home'),
          route('/admin', 'admin', guards: [() async => allowed]),
        ],
      );

      expect(await r.navigate('/admin'), isFalse);
      expect(r.currentPath, '/home');

      allowed = true;
      expect(await r.navigate('/admin'), isTrue);
      expect(r.currentPath, '/admin');
    });

    test('guards run in order and stop at the first refusal', () async {
      final calls = <String>[];
      final r = router(
        routes: [
          route('/home', 'home'),
          route(
            '/admin',
            'admin',
            guards: [
              () async {
                calls.add('first');
                return false;
              },
              () async {
                calls.add('second');
                return true;
              },
            ],
          ),
        ],
      );

      await r.navigate('/admin');

      expect(calls, ['first']);
    });
  });

  group('back, forward and replace', () {
    test('goBack and goForward walk the history', () async {
      final r = router();
      await r.navigate('/settings');

      expect(r.goBack(), isTrue);
      expect(r.currentPath, '/home');
      expect(r.goForward(), isTrue);
      expect(r.currentPath, '/settings');
    });

    test('they report failure at the ends of the history', () async {
      final r = router();

      expect(r.goBack(), isFalse);
      expect(r.goForward(), isFalse);
    });

    test('replaceWith swaps the entry instead of pushing', () async {
      final r = router();
      await r.navigate('/settings');

      r.replaceWith('/users/7');

      expect(r.currentPath, '/users/7');
      expect(r.currentParams, {'id': '7'});
      expect(r.history, ['/home', '/users/7']);
    });

    test('replaceWith ignores an unknown path', () async {
      final r = router();

      r.replaceWith('/nowhere');

      expect(r.currentPath, '/home');
    });
  });

  group('listeners', () {
    test('report the type and the routes moved between', () async {
      final r = router();
      final events = <RouterEvent>[];
      r.onRouteChange(events.add);

      await r.navigate('/settings');
      r.goBack();
      r.goForward();
      r.replaceWith('/users/1');

      expect(events.map((e) => e.type), ['push', 'pop', 'forward', 'replace']);
      expect(events.first.from.path, '/home');
      expect(events.first.to.path, '/settings');
      expect(events.last.to.path, '/users/1');
    });

    test('a removed listener stops hearing events', () async {
      final r = router();
      var calls = 0;
      void listener(RouterEvent _) => calls++;
      r.onRouteChange(listener);

      await r.navigate('/settings');
      r.removeListener(listener);
      await r.navigate('/home');

      expect(calls, 1);
    });

    test('refused navigation fires nothing', () async {
      final r = router();
      var calls = 0;
      r.onRouteChange((_) => calls++);

      await r.navigate('/nowhere');

      expect(calls, 0);
    });
  });

  test('buildCurrentRoute renders the current route with its params', () async {
    final r = router();
    await r.navigate('/users/42');

    final tree = r.buildCurrentRoute();

    expect(texts(tree), ['user 42']);
  });
}
