/// Tests for NavigationApp: the router driving a renderer.
library;

import 'package:dart_not_native/core.dart' hide Route, Router, RouterConfig;
import 'package:dart_not_native/routing/navigation_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

NavigationApp buildApp() =>
    (NavigationAppBuilder()
          ..setInitialPath('/home')
          ..addRoute(
            path: '/home',
            name: 'home',
            builder: RouteBuilders.simple(
              UIBuilder.scaffold(
                appBar: UIBuilder.appBar(title: 'Home'),
                body: UIBuilder.text('Home', id: 'screen'),
              ),
            ),
          )
          ..addRoute(
            path: '/users/:id',
            name: 'user',
            builder: RouteBuilders.withParams(
              (params) => UIBuilder.scaffold(
                appBar: UIBuilder.appBar(title: 'User'),
                body: UIBuilder.text('User ${params['id']}', id: 'screen'),
              ),
            ),
          )
          ..setNotFoundRoute(
            RouteBuilders.simple(UIBuilder.text('Not found', id: 'screen')),
          ))
        .build();

void main() {
  group('NavigationAppBuilder', () {
    test('requires an initial path', () {
      final builder = NavigationAppBuilder()
        ..addRoute(
          path: '/home',
          name: 'home',
          builder: RouteBuilders.simple(UIBuilder.text('Home')),
        );

      expect(builder.build, throwsA(isA<ArgumentError>()));
    });

    test('registers routes and the 404 fallback', () {
      final app = buildApp();

      expect(app.currentPath, '/home');
      expect(app.router.config.routes.map((r) => r.name), ['home', 'user']);
      expect(app.router.config.notFoundRoute?.name, 'not_found');
    });
  });

  group('NavigationApp', () {
    late NavigationApp app;
    late InMemoryRenderer renderer;

    setUp(() {
      app = buildApp();
      renderer = InMemoryRenderer();
    });

    String screen() =>
        nodeById(renderer.tree!, 'screen')!.props['content'] as String;

    test('render paints the initial route', () {
      app.render(renderer);

      expect(screen(), 'Home');
    });

    test('navigating re-renders with the new route and its params', () async {
      app.render(renderer);

      await app.navigate('/users/7');

      expect(screen(), 'User 7');
      expect(app.currentParams, {'id': '7'});
      expect(app.history, ['/home', '/users/7']);
    });

    test('navigateNamed reaches the same screen', () async {
      app.render(renderer);

      await app.navigateNamed('user', params: {'id': '9'});

      // The path template supplies no id, the explicit param does.
      expect(app.currentParams['id'], '9');
    });

    test('going back re-renders the previous route', () async {
      app.render(renderer);
      await app.navigate('/users/7');

      expect(app.goBack(), isTrue);

      expect(screen(), 'Home');
    });

    test('an unknown path renders the 404 screen', () async {
      app.render(renderer);

      await app.navigate('/does/not/exist');

      expect(screen(), 'Not found');
    });

    test('state change callbacks fire on every render', () async {
      final paths = <String>[];
      app.onStateChange((state) => paths.add(state.router.currentPath));

      app.render(renderer);
      await app.navigate('/users/1');
      app.goBack();

      expect(paths, ['/home', '/users/1', '/home']);
    });

    test('navigation before a renderer is attached does not throw', () async {
      expect(await app.navigate('/users/1'), isTrue);
      expect(app.currentPath, '/users/1');
    });
  });

  group('RouteBuilders', () {
    test('showParams renders one line per parameter', () {
      final tree = RouteBuilders.showParams()({'id': '7', 'tab': 'posts'});

      expect(texts(tree), ['Route Parameters:', 'id: 7', 'tab: posts']);
    });
  });
}
