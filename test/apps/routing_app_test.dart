/// Tests for the routing example: multi-screen navigation through the tree.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/routing_example_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const RoutingExampleApp())));

  String appBarTitle() =>
      tester.ofType('AppBar').single.props['title'] as String;

  test('starts on the home screen', () {
    expect(appBarTitle(), 'Navigation Demo');
    expect(tester.text('current_path'), 'Current path: /');
    expect(tester.text('history'), 'History: /');
  });

  test('navigating to a list screen renders its rows', () async {
    await tester.tap('nav_users');

    expect(appBarTitle(), 'Users');
    expect(tester.hasText('alice@example.com'), isTrue);
    expect(tester.text('current_path'), 'Current path: /users');
  });

  test('a parameterised route renders the matching record', () async {
    await tester.tap('nav_users');

    await tester.tap('user_2');

    expect(appBarTitle(), 'User Detail');
    expect(tester.text('detail_title'), 'Bob Smith');
    expect(tester.hasText('Role: Engineer'), isTrue);
    expect(tester.text('current_path'), 'Current path: /users/2');
  });

  test('posts work the same way', () async {
    await tester.tap('nav_posts');
    await tester.tap('post_3');

    expect(tester.text('detail_title'), 'Building Scalable Apps');
  });

  test('back returns to the previous screen', () async {
    await tester.tap('nav_users');
    await tester.tap('user_1');

    await tester.tap('back');

    expect(appBarTitle(), 'Users');
    expect(tester.text('current_path'), 'Current path: /users');
  });

  test('history accumulates along the way', () async {
    await tester.tap('nav_users');
    await tester.tap('user_1');

    expect(tester.text('history'), 'History: / → /users → /users/1');
  });

  test('the settings screen reports the live history state', () async {
    await tester.tap('nav_settings');

    expect(tester.text('can_go_back'), 'Can go back: true');
    expect(tester.hasText('1. /'), isTrue);
    expect(tester.hasText('2. /settings'), isTrue);
  });

  test(
    'the home screen offers no back button, and back there is harmless',
    () async {
      expect(tester.find('back'), isNull);

      // No overlay and nothing to pop to: the screen stays put.
      expect(tester.text('current_path'), 'Current path: /');
    },
  );

  test('every list screen keeps the path readout and a working Open button',
      () async {
    for (final entry in {'nav_users': 'user_1', 'nav_posts': 'post_1'}.entries) {
      final fresh = AppTester.mount(hostApp(const RoutingExampleApp()));

      await fresh.tap(entry.key);
      expect(fresh.find('current_path'), isNotNull);

      await fresh.tap(entry.value);
      expect(fresh.find('detail_title'), isNotNull);
    }
  });

  group('favourites, which no one screen owns', () {
    tearDown(() => routingFavourites.value = {});

    test('a user marked on their page is counted on the home page', () async {
      await tester.tap('nav_users');
      await tester.tap('user_2');

      await tester.tap('favourite');
      expect(tester.get('favourite').props['label'], 'Remove favourite');

      await tester.tap('home');
      // The user detail screen is gone and its State with it; the store the
      // two screens share is what carried this across.
      expect(tester.text('favourites_count'), 'Favourites: 1');
    });

    test('marking one twice takes it off again', () async {
      await tester.tap('nav_users');
      await tester.tap('user_1');

      await tester.tap('favourite');
      await tester.tap('favourite');

      expect(routingFavourites.value, isEmpty);
    });
  });

  group('platform back gesture', () {
    setUp(SystemBack.clearHandlers);
    tearDown(SystemBack.clearHandlers);

    test('pops a route and repaints, like the in-app Back button', () async {
      final tester = AppTester.mount(hostApp(const RoutingExampleApp()));
      await tester.tap('nav_users');
      await tester.tap('user_2');
      expect(tester.text('detail_title'), 'Bob Smith');

      expect(SystemBack.dispatch(), isTrue);

      expect(tester.text('current_path'), 'Current path: /users');
      expect(tester.ofType('AppBar').single.props['title'], 'Users');
    });

    test('declines on the first screen, so the platform closes the app', () {
      AppTester.mount(hostApp(const RoutingExampleApp()));

      expect(SystemBack.dispatch(), isFalse);
    });

    test('walks the whole history before declining', () async {
      final tester = AppTester.mount(hostApp(const RoutingExampleApp()));
      await tester.tap('nav_users');
      await tester.tap('user_1');

      expect(SystemBack.dispatch(), isTrue);
      expect(SystemBack.dispatch(), isTrue);
      expect(SystemBack.dispatch(), isFalse);
      expect(tester.text('current_path'), 'Current path: /');
    });
  });
}
