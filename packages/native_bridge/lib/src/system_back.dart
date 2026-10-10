/// Platform back: the Android back button and predictive-back gesture, the
/// iOS swipe from the left screen edge, and the browser's Back button.
///
/// The framework renders native UI, so "back" arrives from the platform, not
/// from a widget. Each platform binding turns its own gesture into one call
/// to [SystemBack.dispatch]; apps and the router register handlers here and
/// never see the platform difference.
///
/// ```dart
/// SystemBack.addHandler(() {
///   if (!sheetIsOpen) return false; // not ours: let the platform decide
///   closeSheet();
///   return true;                    // consumed
/// });
/// ```
///
/// Handlers run most-recently-registered first, so a modal opened last gets
/// the gesture before the router underneath it. The first handler to return
/// true consumes the gesture; if every handler declines, [dispatch] returns
/// false and the platform does what it would normally do - leave the screen,
/// or close the app.
library;

typedef SystemBackHandler = bool Function();

/// Told, after a dispatch, which handler consumed the gesture - null when none
/// did.
typedef SystemBackListener = void Function(SystemBackHandler? consumedBy);

class SystemBack {
  SystemBack._();

  static final List<SystemBackHandler> _handlers = [];
  static final List<SystemBackHandler> _filters = [];
  static final List<SystemBackListener> _listeners = [];
  static final List<SystemBackHandler> _forwardHandlers = [];

  /// Registers [handler] for the platform's *forward* - the browser's
  /// Forward button, which is the only platform that has one. Asked newest
  /// first, like a back handler, and the first to say true has taken it.
  static void addForwardHandler(SystemBackHandler handler) =>
      _forwardHandlers.add(handler);

  static bool removeForwardHandler(SystemBackHandler handler) =>
      _forwardHandlers.remove(handler);

  /// The platform went forward. True if something in the app went with it.
  static bool dispatchForward() {
    for (final handler in _forwardHandlers.reversed.toList(growable: false)) {
      if (handler()) return true;
    }
    return false;
  }

  /// Registers [handler]; it is offered the gesture before any handler
  /// registered earlier.
  static void addHandler(SystemBackHandler handler) => _handlers.add(handler);

  /// Removes [handler]. Returns whether it was registered.
  static bool removeHandler(SystemBackHandler handler) =>
      _handlers.remove(handler);

  /// Registers [filter], run before every handler. One that returns true
  /// swallows the gesture: no handler sees it and no listener is told.
  ///
  /// For a gesture that is not the user's at all - the browser's `popstate`
  /// after the app itself called `history.back()`.
  static void addFilter(SystemBackHandler filter) => _filters.add(filter);

  static bool removeFilter(SystemBackHandler filter) => _filters.remove(filter);

  /// Registers [listener], told which handler consumed each gesture.
  ///
  /// A platform whose own history moves before the gesture arrives - the
  /// browser - uses this to put that history back when something other than
  /// the router, such as a dialog closing, consumed it.
  static void addListener(SystemBackListener listener) =>
      _listeners.add(listener);

  static bool removeListener(SystemBackListener listener) =>
      _listeners.remove(listener);

  /// Drops every handler, filter and listener (used when tearing an app down,
  /// and by tests).
  static void clearHandlers() {
    _handlers.clear();
    _filters.clear();
    _listeners.clear();
    _forwardHandlers.clear();
  }

  /// Whether anything is listening.
  static bool get hasHandlers => _handlers.isNotEmpty;

  /// Number of registered handlers.
  static int get handlerCount => _handlers.length;

  /// Offers the gesture to each handler, newest first, and returns whether
  /// one of them consumed it.
  ///
  /// A handler may register or remove handlers while it runs; the walk is
  /// taken over a snapshot. Exceptions are not swallowed - a handler that
  /// throws surfaces as it would anywhere else.
  static bool dispatch() {
    for (final filter in _filters.toList(growable: false)) {
      if (filter()) return true;
    }
    SystemBackHandler? consumedBy;
    for (final handler in _handlers.reversed.toList(growable: false)) {
      if (handler()) {
        consumedBy = handler;
        break;
      }
    }
    for (final listener in _listeners.toList(growable: false)) {
      listener(consumedBy);
    }
    return consumedBy != null;
  }
}
