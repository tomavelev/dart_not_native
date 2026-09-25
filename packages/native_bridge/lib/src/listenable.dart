/// State that outlives one screen.
///
/// `setState` keeps state inside the widget that owns it, which is the right
/// place for a draft, a toggle or a page index. Anything two screens share -
/// a signed-in user, a cart, a favourites list - has nowhere to live there:
/// routing away rebuilds the screen and disposes its `State`.
///
/// A [ValueNotifier] is that somewhere. It holds the value, tells whoever is
/// listening when it changes, and lives as long as the app does:
///
/// ```dart
/// final favourites = ValueNotifier<Set<String>>({});
///
/// // In any screen, on any route:
/// ValueListenableBuilder<Set<String>>(
///   valueListenable: favourites,
///   builder: (context, ids, _) => Text('${ids.length} favourites'),
/// )
/// ```
///
/// These are Flutter's own names and signatures, so an app written against
/// `widgets.dart` and one written against Flutter share this code unchanged -
/// the same promise the rest of the widget layer makes.
library;

/// A function that takes no arguments and returns nothing, as Flutter names it.
typedef VoidCallback = void Function();

/// Something that can tell listeners it changed.
abstract class Listenable {
  const Listenable();

  /// Calls [listener] whenever this object changes.
  void addListener(VoidCallback listener);

  /// Stops calling [listener]. Removing one that was never added does nothing.
  void removeListener(VoidCallback listener);
}

/// A [Listenable] that carries a value.
abstract class ValueListenable<T> extends Listenable {
  const ValueListenable();

  /// The current value.
  T get value;
}

/// A [Listenable] that others can change and that reports it.
///
/// Subclass it for state with behaviour of its own:
///
/// ```dart
/// class Cart extends ChangeNotifier {
///   final List<String> items = [];
///   void add(String item) {
///     items.add(item);
///     notifyListeners();
///   }
/// }
/// ```
class ChangeNotifier implements Listenable {
  final List<VoidCallback> _listeners = [];
  bool _disposed = false;

  /// Whether anyone is listening - useful for a notifier that only does work
  /// while someone is watching.
  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    assert(!_disposed, 'A disposed ChangeNotifier cannot be listened to.');
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Tells every listener that something changed.
  ///
  /// Over a copy of the list, so a listener that removes itself - or adds
  /// another - while being called does not disturb this round.
  void notifyListeners() {
    assert(!_disposed, 'A disposed ChangeNotifier cannot notify.');
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Drops every listener. The notifier is not usable afterwards.
  void dispose() {
    _listeners.clear();
    _disposed = true;
  }
}

/// A single value that reports its own changes.
///
/// Assigning an equal value changes nothing and notifies no one, so a rebuild
/// only happens when there is something new to draw. A mutable value edited in
/// place (a list `add`ed to) is the same object and so is *not* a change -
/// assign a new one, or use a [ChangeNotifier] of your own and call
/// [ChangeNotifier.notifyListeners].
class ValueNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  ValueNotifier(this._value);

  T _value;

  @override
  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  /// Replaces the value with what [change] makes of it.
  ///
  /// A shorthand for the read-modify-write an immutable value needs:
  /// `favourites.update((ids) => {...ids, id})`.
  void update(T Function(T value) change) => value = change(_value);

  @override
  String toString() => 'ValueNotifier<$T>($value)';
}
