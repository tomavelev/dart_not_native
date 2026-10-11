import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = [
  NavigationRailDestination(icon: Icon(Icons.home), label: Text('Home')),
  NavigationRailDestination(icon: Icon(Icons.search), label: Text('Search')),
];

void main() {
  group('a NavigationRail', () {
    test('says nothing of what it was not given', () {
      final app = AppTester.widget(
        const NavigationRail(destinations: _destinations, selectedIndex: 0),
      );
      final rail = app.ofType('BottomNavigation').single;

      expect(rail.props['rail'], isTrue);
      expect(rail.props.containsKey('extended'), isFalse);
      expect(rail.props.containsKey('hasLeading'), isFalse);
      expect(rail.props.containsKey('hasTrailing'), isFalse);
      expect(rail.children ?? const [], isEmpty);
    });

    test('carries its leading and then its trailing as children', () {
      final app = AppTester.widget(
        const NavigationRail(
          destinations: _destinations,
          selectedIndex: 0,
          leading: Text('Above'),
          trailing: Text('Below'),
        ),
      );
      final rail = app.ofType('BottomNavigation').single;

      expect(rail.props['hasLeading'], isTrue);
      expect(rail.props['hasTrailing'], isTrue);
      expect(
        [for (final child in rail.children!) child.props['content']],
        ['Above', 'Below'],
      );
    });

    test('a trailing alone is the only child, and is named as one', () {
      final app = AppTester.widget(
        const NavigationRail(
          destinations: _destinations,
          selectedIndex: 0,
          trailing: Text('Below'),
        ),
      );
      final rail = app.ofType('BottomNavigation').single;

      expect(rail.props.containsKey('hasLeading'), isFalse);
      expect(rail.props['hasTrailing'], isTrue);
      expect(rail.children, hasLength(1));
    });

    test('says when it is extended', () {
      final app = AppTester.widget(
        const NavigationRail(
          destinations: _destinations,
          selectedIndex: 1,
          extended: true,
        ),
      );

      expect(app.ofType('BottomNavigation').single.props['extended'], isTrue);
    });

    test('a button in its leading is a button that can be pressed', () {
      var pressed = 0;
      final app = AppTester.widget(
        NavigationRail(
          destinations: _destinations,
          selectedIndex: 0,
          leading: IconButton(
            key: const ValueKey('compose'),
            icon: const Icon(Icons.add),
            onPressed: () => pressed++,
          ),
        ),
      );

      app.tap('compose');

      expect(pressed, 1);
    });
  });
}
