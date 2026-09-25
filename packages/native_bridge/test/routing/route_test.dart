/// Unit tests for route matching, parameter extraction and history.
library;

import 'package:dart_not_native/core.dart' hide Route;
import 'package:dart_not_native/routing/route.dart';
import 'package:flutter_test/flutter_test.dart';

Route route(String path, {String? name, Map<String, dynamic>? defaultParams}) =>
    Route(
      path: path,
      name: name ?? path,
      builder: (params) => UIBuilder.text('$path $params'),
      defaultParams: defaultParams,
    );

void main() {
  group('Route.matches', () {
    test('static paths match exactly', () {
      final home = route('/home');

      expect(home.matches('/home'), isTrue);
      expect(home.matches('/home/'), isFalse);
      expect(home.matches('/away'), isFalse);
    });

    test('a :param segment matches any single segment', () {
      final user = route('/users/:id');

      expect(user.matches('/users/42'), isTrue);
      expect(user.matches('/users/abc'), isTrue);
      expect(
        user.matches('/users'),
        isFalse,
        reason: 'segment counts must agree',
      );
      expect(user.matches('/users/42/posts'), isFalse);
    });

    test('static segments still have to match around a param', () {
      expect(route('/users/:id/posts').matches('/users/1/posts'), isTrue);
      expect(route('/users/:id/posts').matches('/users/1/likes'), isFalse);
    });
  });

  group('Route.extractParams', () {
    test('reads named segments out of the path', () {
      final params = route(
        '/users/:id/posts/:postId',
      ).extractParams('/users/42/posts/7');

      expect(params, {'id': '42', 'postId': '7'});
    });

    test('a static route has no params', () {
      expect(route('/home').extractParams('/home'), isEmpty);
    });

    test('default params are merged in', () {
      final params = route(
        '/search/:q',
        defaultParams: {'page': 1},
      ).extractParams('/search/dart');

      expect(params, {'page': 1, 'q': 'dart'});
    });

    test(
      'extracting params does not pollute the route for later navigations',
      () {
        final search = route('/search/:q', defaultParams: {'page': 1});

        search.extractParams('/search/dart');

        expect(
          search.defaultParams,
          {'page': 1},
          reason:
              'defaultParams is the route definition, not per-navigation state',
        );
        expect(search.extractParams('/search/flutter'), {
          'page': 1,
          'q': 'flutter',
        });
      },
    );
  });

  group('RouterConfig', () {
    final routes = [route('/home'), route('/users/:id', name: 'user')];

    test('findByName returns the route or null', () {
      final config = RouterConfig(routes: routes, initialPath: '/home');

      expect(config.findByName('user')?.path, '/users/:id');
      expect(config.findByName('missing'), isNull);
    });

    test('findByPath matches parameterised routes', () {
      final config = RouterConfig(routes: routes, initialPath: '/home');

      expect(config.findByPath('/users/9')?.name, 'user');
    });

    test('an unmatched path falls back to the 404 route, else null', () {
      final withoutFallback = RouterConfig(
        routes: routes,
        initialPath: '/home',
      );
      expect(withoutFallback.findByPath('/nope'), isNull);

      final notFound = route('/404', name: 'not_found');
      final withFallback = RouterConfig(
        routes: routes,
        notFoundRoute: notFound,
        initialPath: '/home',
      );
      expect(withFallback.findByPath('/nope')?.name, 'not_found');
    });
  });

  group('NavigationState', () {
    NavigationState state() =>
        NavigationState(initialRoute: route('/home'), initialPath: '/home');

    RouteEntry entry(String path) =>
        RouteEntry(route: route(path), path: path, params: const {});

    test('starts on the initial route with no history to walk', () {
      final nav = state();

      expect(nav.current.path, '/home');
      expect(nav.canGoBack, isFalse);
      expect(nav.canGoForward, isFalse);
      expect(nav.pathHistory, ['/home']);
    });

    test('push, pop and forward walk the history', () {
      final nav = state()..push(entry('/settings'));

      expect(nav.current.path, '/settings');
      expect(nav.canGoBack, isTrue);

      expect(nav.pop(), isTrue);
      expect(nav.current.path, '/home');
      expect(nav.canGoForward, isTrue);

      expect(nav.forward(), isTrue);
      expect(nav.current.path, '/settings');
    });

    test('pop and forward report failure at the ends', () {
      final nav = state();

      expect(nav.pop(), isFalse);
      expect(nav.forward(), isFalse);
    });

    test('pushing after going back drops the forward history', () {
      final nav = state()
        ..push(entry('/a'))
        ..push(entry('/b'));
      nav.pop();

      nav.push(entry('/c'));

      expect(nav.pathHistory, ['/home', '/a', '/c']);
      expect(nav.canGoForward, isFalse);
    });

    test('replace swaps the current entry without growing history', () {
      final nav = state()..push(entry('/a'));

      nav.replace(entry('/b'));

      expect(nav.pathHistory, ['/home', '/b']);
      expect(nav.canGoForward, isFalse);
    });
  });
}
