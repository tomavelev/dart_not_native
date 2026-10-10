/// Browser Back for the web target.
///
/// The web renderer paints DOM, so the app is one page: without this the
/// browser's Back button leaves the site instead of popping a route. The
/// adapter mirrors the router's navigation into `window.history` and turns
/// `popstate` into a [SystemBack] dispatch, so Back pops a route and only
/// leaves the app once there is nothing left to pop.
///
/// ```dart
/// void main() async {
///   final app = MyNavApp();
///   await runWebApp(app);
///   app.nav.bindSystemBack(adapter: BrowserHistoryAdapter());
///   bindBrowserBack();
/// }
/// ```
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../routing/history_sync.dart';
import '../src/system_back.dart';

/// `window.history`, as a [HistoryAdapter].
///
/// Routes are written to the URL fragment (`#/users/7`), which needs no
/// server-side routing to survive a reload.
class BrowserHistoryAdapter extends HistoryAdapter {
  BrowserHistoryAdapter({web.Window? window}) : _window = window ?? web.window;

  final web.Window _window;

  @override
  bool get hasStack => true;

  /// The path in the current URL, or null when the fragment holds none.
  @override
  String? get currentPath {
    final fragment = _window.location.hash;
    if (fragment.length < 2) return null;
    return fragment.substring(1);
  }

  /// Where the current entry sits in the browser's stack.
  ///
  /// `popstate` says an entry changed, not which way it went, so a Forward
  /// arrives looking exactly like a Back. Stamping each entry with a rising
  /// index is what tells them apart afterwards: the new entry's index is lower
  /// than the one we left for a Back, higher for a Forward.
  int get _index => _indexOf(_window.history.state);

  @override
  void push(String path) => _window.history.pushState(
        {'path': path, 'index': _index + 1}.jsify(),
        '',
        '#$path',
      );

  @override
  void replace(String path) => _window.history.replaceState(
        {'path': path, 'index': _index}.jsify(),
        '',
        '#$path',
      );

  @override
  void back() => _window.history.back();

  @override
  void forward() => _window.history.forward();
}

bool _listening = false;

/// The index of the entry the app is on, so a `popstate` can be read as a Back
/// or a Forward rather than just "something moved".
int _currentIndex = 0;

/// Sends the browser's **Back** to [SystemBack], and its Forward to
/// [SystemBack.dispatchForward].
///
/// `popstate` fires for both, and dispatching Back when the user pressed
/// Forward closed the dialog they had just moved past. The entry's index says
/// which way it went - lower than the one we were on is a Back.
///
/// Call once, after the app is mounted. Safe to call twice.
void bindBrowserBack({web.Window? window}) {
  if (_listening) return;
  _listening = true;
  final target = window ?? web.window;
  _currentIndex = _indexOf(target.history.state);
  target.addEventListener(
    'popstate',
    ((web.PopStateEvent event) {
      final previous = _currentIndex;
      _currentIndex = _indexOf(event.state);
      // An entry with no index is one this app did not write - a link, a
      // fragment typed by hand. Treated as a Back, which is what it was before
      // any of this and the safer guess for an unlabelled move.
      if (_currentIndex <= previous) {
        SystemBack.dispatch();
      } else {
        // Forward: a router that kept the page Back left can show it again.
        SystemBack.dispatchForward();
      }
    }).toJS,
  );
}

/// The index an entry carries, or 0 for one this app did not write.
int _indexOf(JSAny? state) {
  final index = (state?.dartify() as Map?)?['index'];
  return index is int ? index : 0;
}

/// Forgets which entry the app is on. For tests, which share one window.
void resetBrowserBackForTesting() {
  _listening = false;
  _currentIndex = 0;
}
