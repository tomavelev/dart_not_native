/// State two screens share, which `setState` has nowhere to put.
///
/// A routed app's screens are rebuilt as the user moves between them, so a
/// `State` cannot hold what both of them read. A store outside the tree can,
/// and a `ValueListenableBuilder` is how a screen follows it.
library;

import 'package:dart_not_native/core.dart' show SystemBack;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

/// Two screens over one store: a list that adds to it and a home that counts.
class _FavouritesApp extends StatelessWidget {
  const _FavouritesApp(this.favourites, {this.itemsOnly});

  final ValueNotifier<Set<String>> favourites;

  /// A second store only the items screen reads, to watch a subscription go
  /// when the screen that wanted it does.
  final ValueNotifier<String>? itemsOnly;

  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (context, params) => _home(context),
          '/items': (context, params) => _items(context),
        },
      );

  Widget _home(BuildContext context) => Scaffold(
        appBar: const AppBar(title: Text('Home')),
        body: Column(
          children: [
            ValueListenableBuilder<Set<String>>(
              valueListenable: favourites,
              builder: (context, ids, _) => Text(
                '${ids.length} favourites',
                key: const ValueKey('count'),
              ),
            ),
            ElevatedButton(
              key: const ValueKey('to_items'),
              onPressed: () => Navigator.of(context).pushNamed('/items'),
              child: const Text('Items'),
            ),
          ],
        ),
      );

  Widget _items(BuildContext context) => Scaffold(
        appBar: const AppBar(title: Text('Items')),
        body: Column(
          children: [
            for (final id in ['a', 'b', 'c'])
              ElevatedButton(
                key: ValueKey('item_$id'),
                onPressed: () => favourites.update((ids) => {...ids, id}),
                child: Text(id),
              ),
            ValueListenableBuilder<Set<String>>(
              valueListenable: favourites,
              builder: (context, ids, _) => Text(
                'picked: ${ids.join(',')}',
                key: const ValueKey('picked'),
              ),
            ),
            if (itemsOnly != null)
              ValueListenableBuilder<String>(
                valueListenable: itemsOnly!,
                builder: (context, note, _) =>
                    Text(note, key: const ValueKey('note')),
              ),
          ],
        ),
      );
}

void main() {
  late ValueNotifier<Set<String>> favourites;
  AppTester? tester;

  setUp(() {
    SystemBack.clearHandlers();
    favourites = ValueNotifier<Set<String>>({});
  });

  tearDown(() {
    // One app per test: a store is shared by definition, so an app left
    // mounted would still be listening to the next test's notifier.
    tester?.app.unmount();
    tester = null;
    SystemBack.clearHandlers();
  });

  AppTester mount({ValueNotifier<String>? itemsOnly}) =>
      tester = AppTester.mount(
        hostApp(_FavouritesApp(favourites, itemsOnly: itemsOnly)),
      );

  test('a screen reads the store it did not create', () {
    final app = mount();

    expect(app.text('count'), '0 favourites');
  });

  test('changing the store redraws the screen watching it', () {
    final app = mount();

    favourites.value = {'a', 'b'};

    expect(app.text('count'), '2 favourites');
  });

  test('what one screen puts in the store, the other reads', () async {
    final app = mount();
    await app.tap('to_items');
    await app.tap('item_b');
    expect(app.text('picked'), 'picked: b');

    expect(SystemBack.dispatch(), isTrue);

    // The home screen was rebuilt from scratch on the way back; the value it
    // shows outlived the screen that set it.
    expect(app.text('count'), '1 favourites');
  });

  test('the store keeps one listener however many builders read it', () async {
    final app = mount();
    await app.tap('to_items');

    // The app follows a listenable once, not once per builder - which is also
    // why two keyless builders of the same type cannot collide here.
    expect(favourites.hasListeners, isTrue);
  });

  group('a store only one screen reads', () {
    late ValueNotifier<String> itemsOnly;

    setUp(() => itemsOnly = ValueNotifier<String>('note'));

    test('is followed while that screen is up, and let go after', () async {
      final app = mount(itemsOnly: itemsOnly);
      expect(itemsOnly.hasListeners, isFalse, reason: 'home does not read it');

      await app.tap('to_items');
      expect(itemsOnly.hasListeners, isTrue);
      expect(app.text('note'), 'note');

      expect(SystemBack.dispatch(), isTrue);
      expect(
        itemsOnly.hasListeners,
        isFalse,
        reason: 'the screen that wanted it is gone',
      );
    });

    test('unmounting the app lets go of both', () async {
      final app = mount(itemsOnly: itemsOnly);
      await app.tap('to_items');
      expect([favourites.hasListeners, itemsOnly.hasListeners], [true, true]);

      app.app.unmount();

      expect(favourites.hasListeners, isFalse);
      expect(itemsOnly.hasListeners, isFalse);
    });
  });
}
