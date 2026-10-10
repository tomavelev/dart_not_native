/// Keeps a [Router]'s history and the platform's own history in step.
///
/// The browser has a real history stack; Android and iOS do not, but both
/// deliver a back gesture. [RouterHistorySync] pops the router when the
/// platform asks to go back and, where the platform keeps a stack, mirrors
/// the router's navigation into it so Back means the same thing in both.
///
/// The platform side sits behind [HistoryAdapter], so the logic here - which
/// is mostly about not letting the two stacks drive each other in circles -
/// is testable without a browser.
library;

import '../src/system_back.dart';
import 'route.dart';

/// The platform's history stack.
abstract class HistoryAdapter {
  const HistoryAdapter();

  /// The history the widget layer mirrors into, in place of the platform's
  /// own - the browser's, in a browser; none anywhere else.
  ///
  /// `MaterialApp(routes:)` and `Navigator.push` reach the platform's history
  /// without being handed an adapter, so this is how one is put in their way:
  /// a fake in a test, or an adapter that writes paths where the browser's
  /// writes fragments. Set it before `runApp`. Null is the platform's.
  static HistoryAdapter? platform;

  /// How many routers are mirroring themselves into a history stack right
  /// now. While one is, it is that router which puts an entry back when a
  /// Back was spent on something else, and nothing else should.
  static int mirrors = 0;

  /// Whether this platform keeps a history stack that must be mirrored.
  /// False on Android and iOS, where back is only a gesture.
  bool get hasStack;

  /// The path the platform is showing as the app starts - a reload, a link
  /// straight to a page - or null where there is none to read.
  String? get currentPath => null;

  /// Pushes [path] onto the platform stack.
  void push(String path);

  /// Replaces the platform's current entry with [path].
  void replace(String path);

  /// Pops the platform stack, as the user's Back would.
  void back();

  /// Re-enters the entry a [back] left behind.
  void forward();
}

/// A platform with no history stack of its own (Android, iOS): back arrives
/// only as a gesture, and nothing is mirrored.
class NoHistoryAdapter extends HistoryAdapter {
  const NoHistoryAdapter();

  @override
  bool get hasStack => false;

  @override
  void push(String path) {}

  @override
  void replace(String path) {}

  @override
  void back() {}

  @override
  void forward() {}
}

class RouterHistorySync {
  RouterHistorySync({
    required this.router,
    this.adapter = const NoHistoryAdapter(),
  });

  final Router router;
  final HistoryAdapter adapter;

  /// True while a router change is being applied on behalf of the platform,
  /// so it is not mirrored straight back to the platform.
  bool _applyingPlatformChange = false;

  /// Platform pops this binding caused itself, which must not be read as the
  /// user pressing Back.
  int _selfInflictedPops = 0;

  /// The same for Forward.
  int _selfInflictedForwards = 0;

  bool _bound = false;

  bool get isBound => _bound;

  /// Starts mirroring and registers with [SystemBack]. Safe to call twice.
  void bind() {
    if (_bound) return;
    _bound = true;
    if (adapter.hasStack) HistoryAdapter.mirrors++;
    if (adapter.hasStack) adapter.replace(router.currentPath);
    router.onRouteChange(_onRouteChange);
    SystemBack.addHandler(handleBack);
    SystemBack.addForwardHandler(handleForward);
    SystemBack.addFilter(_swallowSelfInflictedPop);
    SystemBack.addListener(_restoreEntryConsumedElsewhere);
  }

  /// Stops mirroring.
  void unbind() {
    if (!_bound) return;
    _bound = false;
    if (adapter.hasStack) HistoryAdapter.mirrors--;
    router.removeListener(_onRouteChange);
    SystemBack.removeHandler(handleBack);
    SystemBack.removeForwardHandler(handleForward);
    SystemBack.removeFilter(_swallowSelfInflictedPop);
    SystemBack.removeListener(_restoreEntryConsumedElsewhere);
  }

  /// Swallows the pop this binding asked the platform for, before a handler
  /// registered after the router - an open dialog - can mistake it for the
  /// user's Back.
  bool _swallowSelfInflictedPop() {
    if (_selfInflictedPops == 0) return false;
    _selfInflictedPops--;
    return true;
  }

  /// Puts the platform's entry back when Back was consumed by something other
  /// than the router.
  ///
  /// The browser has already moved to the previous entry by the time it
  /// reports Back. If a dialog took the gesture instead, the screen stays
  /// where it was, so the URL must too - otherwise the next Back would leave
  /// two screens behind.
  void _restoreEntryConsumedElsewhere(SystemBackHandler? consumedBy) {
    if (!adapter.hasStack || consumedBy == null || consumedBy == handleBack) {
      return;
    }
    adapter.push(router.currentPath);
  }

  /// The platform asked to go back.
  ///
  /// Returns whether the router consumed it; false means the app has nowhere
  /// left to go and the platform should do what it normally would - leave the
  /// screen, or close the app.
  bool handleBack() {
    if (_selfInflictedPops > 0) {
      // A pop this binding asked the platform for, not the user pressing Back.
      _selfInflictedPops--;
      return true;
    }
    _applyingPlatformChange = true;
    try {
      return router.goBack();
    } finally {
      _applyingPlatformChange = false;
    }
  }

  /// The platform went forward - the browser's Forward button, after a Back.
  ///
  /// The router keeps the entries Back stepped off, so it steps on to the
  /// next one; the platform is already there. False when the router has
  /// nothing ahead - an entry it never knew, or one a push has since dropped.
  bool handleForward() {
    if (_selfInflictedForwards > 0) {
      // A forward this binding asked the platform for.
      _selfInflictedForwards--;
      return true;
    }
    _applyingPlatformChange = true;
    try {
      return router.goForward();
    } finally {
      _applyingPlatformChange = false;
    }
  }

  void _onRouteChange(RouterEvent event) {
    if (_applyingPlatformChange || !adapter.hasStack) return;
    switch (event.type) {
      case 'push':
        adapter.push(event.to.path);
      case 'replace':
        adapter.replace(event.to.path);
      case 'pop':
        // The app navigated back on its own (an in-app Back button): keep the
        // platform stack in step, and ignore the pop it reports back.
        _selfInflictedPops++;
        adapter.back();
      case 'forward':
        // Counted as a forward, which is what the platform reports it as. It
        // was counted as a pop, and the browser never reported it at all -
        // so the next Back the user pressed was swallowed as this one's.
        _selfInflictedForwards++;
        adapter.forward();
    }
  }
}
