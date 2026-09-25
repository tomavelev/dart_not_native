/// The store behind state that outlives one screen.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cart extends ChangeNotifier {
  final List<String> items = [];

  void add(String item) {
    items.add(item);
    notifyListeners();
  }
}

void main() {
  group('ValueNotifier', () {
    test('a new value reaches every listener', () {
      final notifier = ValueNotifier<int>(0);
      var first = 0;
      var second = 0;
      notifier
        ..addListener(() => first++)
        ..addListener(() => second++);

      notifier.value = 1;

      expect(notifier.value, 1);
      expect([first, second], [1, 1]);
    });

    test('an equal value is not a change', () {
      // Otherwise every render that assigns the value it already holds would
      // rebuild the app, forever.
      final notifier = ValueNotifier<String>('a');
      var calls = 0;
      notifier.addListener(() => calls++);

      notifier.value = 'a';

      expect(calls, 0);
    });

    test('update reads, changes and writes back', () {
      final favourites = ValueNotifier<Set<String>>({'1'});
      var calls = 0;
      favourites.addListener(() => calls++);

      favourites.update((ids) => {...ids, '2'});

      expect(favourites.value, {'1', '2'});
      expect(calls, 1);
    });

    test('a value edited in place is the same value, and says nothing', () {
      // The trap the class documents: a mutated list is not a new list.
      final notifier = ValueNotifier<List<String>>([]);
      var calls = 0;
      notifier.addListener(() => calls++);

      notifier.value.add('mutated');

      expect(calls, 0, reason: 'assign a new list, or use a ChangeNotifier');
    });
  });

  group('listeners', () {
    test('removing one stops it, and leaves the others', () {
      final notifier = ValueNotifier<int>(0);
      var kept = 0;
      var dropped = 0;
      void keptListener() => kept++;
      void droppedListener() => dropped++;
      notifier
        ..addListener(keptListener)
        ..addListener(droppedListener);

      notifier.removeListener(droppedListener);
      notifier.value = 1;

      expect([kept, dropped], [1, 0]);
    });

    test('removing one that was never added does nothing', () {
      final notifier = ValueNotifier<int>(0);

      expect(() => notifier.removeListener(() {}), returnsNormally);
    });

    test('a listener may remove itself while being called', () {
      // A builder that leaves the tree in the middle of a round would
      // otherwise trip the iteration.
      final notifier = ValueNotifier<int>(0);
      var calls = 0;
      late void Function() listener;
      listener = () {
        calls++;
        notifier.removeListener(listener);
      };
      notifier.addListener(listener);

      notifier.value = 1;
      notifier.value = 2;

      expect(calls, 1);
    });

    test('hasListeners answers whether anyone is watching', () {
      final notifier = ValueNotifier<int>(0);
      void listener() {}

      expect(notifier.hasListeners, isFalse);
      notifier.addListener(listener);
      expect(notifier.hasListeners, isTrue);
      notifier.removeListener(listener);
      expect(notifier.hasListeners, isFalse);
    });

    test('dispose drops them all', () {
      final notifier = ValueNotifier<int>(0);
      notifier.addListener(() {});

      notifier.dispose();

      expect(notifier.hasListeners, isFalse);
    });
  });

  group('ChangeNotifier of your own', () {
    test('notifies when the object itself changed', () {
      final cart = _Cart();
      var calls = 0;
      cart.addListener(() => calls++);

      cart.add('apples');

      expect(cart.items, ['apples']);
      expect(calls, 1);
    });
  });
}
