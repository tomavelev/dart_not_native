/// A `go_router`-shaped router for the widget layer.
///
/// `go_router` is built on Flutter's `Router`, `Navigator` and `Page`, none of
/// which exist here, so an app that routes with it cannot be moved onto
/// `widgets.dart` by swapping one import. This library is the second import:
/// the names and signatures an app actually writes - [GoRouter], [GoRoute],
/// [ShellRoute], [GoRouterState], `context.go` - over this framework's own
/// widget model.
///
/// ```dart
/// import 'package:dart_not_native/router.dart';
/// import 'package:dart_not_native/widgets.dart';
///
/// final router = GoRouter(
///   initialLocation: '/',
///   redirect: (context, state) => signedIn ? null : '/login',
///   routes: [
///     GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
///     ShellRoute(
///       builder: (context, state, child) => AppShell(child: child),
///       routes: [
///         GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
///         GoRoute(
///           path: '/guests/:id',
///           builder: (_, state) => GuestScreen(state.pathParameters['id']!),
///         ),
///       ],
///     ),
///   ],
/// );
///
/// void main() => runApp(MaterialApp.router(routerConfig: router));
/// ```
///
/// It is a subset, and says so where it stops: there are no `Page`s or
/// transitions (`pageBuilder`), no `StatefulShellRoute`, no navigator keys and
/// no `onExit`. What is here behaves as `go_router` does unless a doc comment
/// says otherwise.
///
/// Pure Dart: nothing here imports Flutter or the browser, so the same file
/// compiles for a Flutter host and with plain `dart compile js`. The browser's
/// history is reached through [GoRouter.attachHistory].
library;

import 'dart:async';

import 'routing/history_sync.dart' show HistoryAdapter, NoHistoryAdapter;
import 'src/system_back.dart';
import 'widgets.dart';

// What [GoRouter.attachHistory] takes, so an app wiring the browser needs no
// third import for the type.
export 'routing/history_sync.dart' show HistoryAdapter, NoHistoryAdapter;

// ---------------------------------------------------------------------------
// Signatures, as go_router spells them.
// ---------------------------------------------------------------------------

/// Decides whether a navigation should end up somewhere else. Return the
/// location to go to instead, or null to let it through.
typedef GoRouterRedirect =
    FutureOr<String?> Function(BuildContext context, GoRouterState state);

/// Builds the page for a [GoRoute].
typedef GoRouterWidgetBuilder =
    Widget Function(BuildContext context, GoRouterState state);

/// Builds the frame a [ShellRoute] draws around whichever of its routes is
/// showing, which arrives as [child].
typedef ShellRouteBuilder =
    Widget Function(BuildContext context, GoRouterState state, Widget child);

/// Builds the page shown when a location matches no route, or a redirect went
/// wrong. The problem is in `state.error`.
typedef GoExceptionWidgetBuilder =
    Widget Function(BuildContext context, GoRouterState state);

/// A navigation that could not be carried out: no route for the location, or a
/// redirect that never settles. It reaches the app as `state.error` in
/// [GoRouter]'s `errorBuilder`, not as a throw.
class GoException implements Exception {
  const GoException(this.message);
  final String message;
  @override
  String toString() => 'GoException: $message';
}

/// A mistake in how the router was called - popping with nothing to pop.
class GoError extends Error {
  GoError(this.message);
  final String message;
  @override
  String toString() => 'GoError: $message';
}

// ---------------------------------------------------------------------------
// The route table.
// ---------------------------------------------------------------------------

/// A node in the route table: a [GoRoute] or a [ShellRoute].
abstract class RouteBase {
  const RouteBase._({this.redirect, required this.routes});

  /// Runs when this route is part of a match, after the router's own redirect
  /// and after the redirects of the routes above it.
  final GoRouterRedirect? redirect;

  /// The routes nested under this one.
  final List<RouteBase> routes;
}

/// A page at a path.
///
/// [path] may carry parameters (`/users/:id`), which arrive in
/// [GoRouterState.pathParameters]. A top-level path starts with `/`; a child's
/// is relative to its parent's, so `GoRoute(path: '/users', routes:
/// [GoRoute(path: ':id')])` serves `/users/7`.
///
/// A parameter matches one whole segment. `go_router`'s inline patterns
/// (`:id(\d+)`) are not supported.
class GoRoute extends RouteBase {
  const GoRoute({
    required this.path,
    this.name,
    this.builder,
    super.redirect,
    super.routes = const <RouteBase>[],
  }) : assert(path != '', 'GoRoute path cannot be empty'),
       assert(name != '', 'GoRoute name cannot be empty'),
       assert(
         builder != null || redirect != null,
         'builder or redirect must be provided',
       ),
       super._();

  final String path;

  /// A name [GoRouter.goNamed] can reach this route by, wherever it is nested.
  final String? name;

  /// Builds the page. A route with only a [redirect] has none, and must always
  /// redirect: landing on it is an error.
  final GoRouterWidgetBuilder? builder;
}

/// A frame shared by several routes - a navigation bar, a rail - drawn around
/// whichever of [routes] is showing.
///
/// The frame's `State` outlives navigation between its routes; only the page
/// inside it is replaced.
class ShellRoute extends RouteBase {
  const ShellRoute({
    super.redirect,
    required ShellRouteBuilder this.builder,
    required super.routes,
  }) : super._();

  final ShellRouteBuilder? builder;
}

/// One route's view of the current location.
class GoRouterState {
  const GoRouterState({
    required this.uri,
    required this.matchedLocation,
    this.name,
    this.path,
    required this.fullPath,
    required this.pathParameters,
    this.extra,
    this.error,
  });

  /// The whole location, query included: `state.uri.queryParameters`.
  final Uri uri;

  /// The part of the location this route accounts for - `/users/7` for a
  /// route whose [fullPath] is `/users/:id`, even when a child route matched
  /// more below it.
  final String matchedLocation;

  /// The route's [GoRoute.name], if it has one.
  final String? name;

  /// The route's own [GoRoute.path], as written.
  final String? path;

  /// The route's pattern from the root: `/users/:id`.
  final String? fullPath;

  /// Every path parameter in the location, the parents' included.
  final Map<String, String> pathParameters;

  /// Whatever was passed as `extra` to the navigation that led here. It does
  /// not survive a redirect, as in go_router.
  final Object? extra;

  /// What went wrong, on the state handed to an `errorBuilder`.
  final GoException? error;

  /// The state of the route [context] belongs to: the page's for a context
  /// from a page, the shell's for one from a shell.
  static GoRouterState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StateScope>()?.state ??
      GoRouter.of(context).state;

  @override
  String toString() => 'GoRouterState($uri)';
}

// ---------------------------------------------------------------------------
// Matching: a location against the route table.
// ---------------------------------------------------------------------------

/// One route's share of a matched location.
class _Match {
  const _Match(this.route, this.matchedLocation, this.fullPath);
  final RouteBase route;
  final String matchedLocation;
  final String fullPath;

  /// Whether this match puts a page on screen. A shell is a frame, and a
  /// redirect-only route draws nothing.
  bool get isPage {
    final route = this.route;
    return route is GoRoute && route.builder != null;
  }
}

/// A location and the chain of routes it matched, outermost first - or the
/// reason it matched none.
class _MatchList {
  const _MatchList({
    required this.uri,
    this.matches = const [],
    this.pathParameters = const {},
    this.extra,
    this.error,
  });

  final Uri uri;
  final List<_Match> matches;
  final Map<String, String> pathParameters;
  final Object? extra;
  final GoException? error;

  String get location => uri.toString();

  /// The match whose page is on screen: the innermost one that builds
  /// anything. Null for an error, and for a route that only redirects.
  _Match? get page {
    if (matches.isEmpty || !matches.last.isPage) return null;
    return matches.last;
  }

  int get pageCount => matches.where((m) => m.isPage).length;

  GoRouterState stateFor(_Match match) {
    final route = match.route;
    return GoRouterState(
      uri: uri,
      matchedLocation: match.matchedLocation,
      name: route is GoRoute ? route.name : null,
      path: route is GoRoute ? route.path : null,
      fullPath: match.fullPath,
      pathParameters: pathParameters,
      extra: extra,
    );
  }

  /// The state the router's own redirect is shown - the location as a whole,
  /// before any one route's view of it - and the one an error page gets.
  GoRouterState get topState => GoRouterState(
    uri: uri,
    matchedLocation: uri.path,
    fullPath: matches.isEmpty ? null : matches.last.fullPath,
    pathParameters: pathParameters,
    extra: extra,
    error: error,
  );

  /// What [GoRouter.state] reports: the page's state.
  GoRouterState get state =>
      error != null || matches.isEmpty ? topState : stateFor(matches.last);
}

List<String> _segments(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList();

String _join(String parent, String child) {
  final tail = _segments(child).join('/');
  if (tail.isEmpty) return parent.isEmpty ? '/' : parent;
  return parent.endsWith('/') ? '$parent$tail' : '$parent/$tail';
}

// ---------------------------------------------------------------------------
// The stack.
// ---------------------------------------------------------------------------

/// One layer of the navigation stack. The bottom one is wherever `go` last
/// went; each `push` adds one on top.
class _Entry {
  _Entry(this.list, {this.pushId, this.completer});

  final _MatchList list;

  /// Set on a pushed entry, and what its page is keyed by: a push is a new
  /// page even at a location already on the stack, and `replace` swaps what a
  /// pushed page shows without making it a different page.
  final int? pushId;

  /// Completes the future `push` returned, when this entry is popped.
  final Completer<Object?>? completer;

  _Entry withList(_MatchList list) =>
      _Entry(list, pushId: pushId, completer: completer);

  void complete(Object? result) {
    final completer = this.completer;
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }
}

/// One page to draw: the shells around it, what it is keyed by, and how it
/// is built.
class _PageSpec {
  const _PageSpec(this.shells, this.list, this.tag, this.state, this.builder);
  final List<_Match> shells;
  final _MatchList list;
  final String tag;
  final GoRouterState state;
  final GoRouterWidgetBuilder builder;
}

/// How a change to the stack should show in the platform's own history.
enum _Mirror { push, replace, pop, none }

int _routerSerial = 0;

/// The app's routes, where it currently is among them, and how it moves.
///
/// Hand it to `MaterialApp.router(routerConfig: ...)`. It is a
/// [ChangeNotifier], notifying whenever the location changes.
class GoRouter extends ChangeNotifier implements RouterConfig {
  GoRouter({
    required this.routes,
    String initialLocation = '/',
    Listenable? refreshListenable,
    GoRouterRedirect? redirect,
    GoExceptionWidgetBuilder? errorBuilder,
    this.redirectLimit = 5,
  }) : _refreshListenable = refreshListenable,
       _redirect = redirect,
       _errorBuilder = errorBuilder {
    _index(routes, '', topLevel: true);
    // Not redirected yet: a redirect is owed a BuildContext, and there is none
    // until the router is built. The first build settles it.
    _stack = [_Entry(_parse(initialLocation, null))];
    _unresolved = true;
    refreshListenable?.addListener(refresh);
  }

  final List<RouteBase> routes;

  /// How many redirects one navigation may take before it is given up as an
  /// error. go_router's default.
  final int redirectLimit;

  final Listenable? _refreshListenable;
  final GoRouterRedirect? _redirect;
  final GoExceptionWidgetBuilder? _errorBuilder;

  /// Tells this router's keys apart from another router's in the same tree.
  final int _serial = _routerSerial++;

  final Map<String, String> _namedPaths = {};
  final Map<ShellRoute, int> _shellIds = Map.identity();

  late List<_Entry> _stack;

  /// The context of the tree this router is drawn in, kept for the redirects
  /// a navigation made outside a build has to run.
  BuildContext? _context;

  /// The top of the stack has not been through the redirects, because it was
  /// set before there was a context to run them with.
  bool _unresolved = false;

  /// A location has been through the redirects and may be drawn. Until then
  /// the router draws nothing, rather than flash a page a redirect is about
  /// to replace.
  bool _ready = false;

  /// Counts navigations, so an asynchronous redirect that lands after a later
  /// navigation can tell it has been overtaken.
  int _generation = 0;
  int _nextPushId = 0;
  bool _disposed = false;

  /// The router drawing the tree [context] belongs to.
  static GoRouter of(BuildContext context) =>
      maybeOf(context) ?? (throw GoError('No GoRouter found in context'));

  /// [of], or null where there is no router.
  static GoRouter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_RouterScope>()?.router;

  /// The state of the page on screen.
  GoRouterState get state => _stack.last.list.state;

  // -- The route table ------------------------------------------------------

  /// Walks the table once: checks the paths are the shape matching assumes,
  /// and notes where each named route and each shell is.
  void _index(
    List<RouteBase> routes,
    String parentPath, {
    required bool topLevel,
  }) {
    for (final route in routes) {
      if (route is GoRoute) {
        assert(
          topLevel ? route.path.startsWith('/') : !route.path.startsWith('/'),
          topLevel
              ? 'A top-level path must start with "/": ${route.path}'
              : 'A sub-route path may not start with "/": ${route.path}',
        );
        final fullPath = _join(parentPath, route.path);
        final name = route.name;
        if (name != null) {
          assert(
            !_namedPaths.containsKey(name),
            'Duplicate route name "$name"',
          );
          _namedPaths[name] = fullPath;
        }
        _index(route.routes, fullPath, topLevel: false);
      } else if (route is ShellRoute) {
        _shellIds[route] = _shellIds.length;
        // A shell adds nothing to the path, so its routes are as top-level as
        // it is.
        _index(route.routes, parentPath, topLevel: topLevel);
      }
    }
  }

  /// The location of the route called [name], with its parameters filled in.
  String namedLocation(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
  }) {
    final fullPath = _namedPaths[name];
    if (fullPath == null) throw GoError('Unknown route name: $name');
    final path = [
      for (final segment in _segments(fullPath))
        if (segment.startsWith(':'))
          Uri.encodeComponent(
            pathParameters[segment.substring(1)] ??
                (throw GoError(
                  'Missing path parameter "${segment.substring(1)}" for '
                  'route "$name"',
                )),
          )
        else
          segment,
    ].join('/');
    return Uri(
      path: '/$path',
      queryParameters: queryParameters.isEmpty
          ? null
          : {
              for (final entry in queryParameters.entries)
                entry.key: entry.value is Iterable
                    ? [for (final v in entry.value as Iterable) '$v']
                    : '${entry.value}',
            },
    ).toString();
  }

  _MatchList _parse(String location, Object? extra) {
    var uri = Uri.parse(location);
    var path = uri.path;
    if (!path.startsWith('/')) path = '/$path';
    // `/guests/` and `/guests` are one place.
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    uri = uri.replace(path: path);
    final params = <String, String>{};
    final matches = _matchRoutes(routes, _segments(path), 0, '', '', params);
    if (matches == null) {
      return _MatchList(
        uri: uri,
        extra: extra,
        error: GoException('no routes for location: $uri'),
      );
    }
    return _MatchList(
      uri: uri,
      matches: matches,
      pathParameters: Map.unmodifiable(params),
      extra: extra,
    );
  }

  /// The chain of routes among [routes] that accounts for [segments] from
  /// [at] to the end, or null. The first route that fits wins, searched depth
  /// first, so the table's order is its priority - as in go_router.
  List<_Match>? _matchRoutes(
    List<RouteBase> routes,
    List<String> segments,
    int at,
    String parentPath,
    String parentLocation,
    Map<String, String> params,
  ) {
    for (final route in routes) {
      if (route is ShellRoute) {
        final below = _matchRoutes(
          route.routes,
          segments,
          at,
          parentPath,
          parentLocation,
          params,
        );
        if (below == null) continue;
        // A shell has no path of its own; it is wherever its page is.
        return [
          _Match(route, below.last.matchedLocation, below.last.fullPath),
          ...below,
        ];
      }
      if (route is! GoRoute) continue;
      final pattern = _segments(route.path);
      if (at + pattern.length > segments.length) continue;
      final found = <String, String>{};
      var fits = true;
      for (var i = 0; i < pattern.length && fits; i++) {
        final want = pattern[i];
        final have = segments[at + i];
        if (want.startsWith(':')) {
          found[want.substring(1)] = Uri.decodeComponent(have);
        } else {
          fits = want == have;
        }
      }
      if (!fits) continue;
      final end = at + pattern.length;
      final match = _Match(
        route,
        _join(parentLocation, segments.sublist(at, end).join('/')),
        _join(parentPath, route.path),
      );
      if (end == segments.length) {
        params.addAll(found);
        return [match];
      }
      // Parameters are only kept for the branch that ends up matching.
      final belowParams = <String, String>{...found};
      final below = _matchRoutes(
        route.routes,
        segments,
        end,
        match.fullPath,
        match.matchedLocation,
        belowParams,
      );
      if (below == null) continue;
      params.addAll(belowParams);
      return [match, ...below];
    }
    return null;
  }

  // -- Redirects ------------------------------------------------------------

  /// Where [list] ends up once every redirect has had its say.
  ///
  /// The router's redirect runs first, then each matched route's from the
  /// outside in; the first to name another location starts the whole thing
  /// again from there. It stays synchronous for as long as the redirects do,
  /// so an app whose redirects just read some state never draws a frame of a
  /// page it was about to be sent away from.
  FutureOr<_MatchList> _resolve(
    BuildContext context,
    _MatchList list,
    List<String> history,
  ) {
    if (list.error != null) return list;

    FutureOr<_MatchList> follow(
      String? target,
      FutureOr<_MatchList> Function() otherwise,
    ) {
      if (target == null || target == list.location) return otherwise();
      // `extra` belonged to the navigation that was turned away.
      final next = _parse(target, null);
      final trail = [...history, next.location].join(' => ');
      if (history.contains(next.location)) {
        return _MatchList(
          uri: list.uri,
          error: GoException('redirect loop detected $trail'),
        );
      }
      if (history.length > redirectLimit) {
        return _MatchList(
          uri: list.uri,
          error: GoException('too many redirects $trail'),
        );
      }
      history.add(next.location);
      return _resolve(context, next, history);
    }

    FutureOr<_MatchList> routeLevel(int from) {
      for (var i = from; i < list.matches.length; i++) {
        final match = list.matches[i];
        final redirect = match.route.redirect;
        if (redirect == null) continue;
        final answer = redirect(context, list.stateFor(match));
        if (answer is Future<String?>) {
          return answer.then((to) => follow(to, () => routeLevel(i + 1)));
        }
        if (answer != null && answer != list.location) {
          return follow(answer, () => list);
        }
      }
      return list;
    }

    final redirect = _redirect;
    if (redirect == null) return routeLevel(0);
    final answer = redirect(context, list.topState);
    if (answer is Future<String?>) {
      return answer.then((to) => follow(to, () => routeLevel(0)));
    }
    return follow(answer, () => routeLevel(0));
  }

  /// Runs [target] through the redirects and hands what comes out to [apply] -
  /// at once if the redirects were synchronous, later if not, and never if
  /// another navigation started in the meantime ([overtaken] is told instead).
  ///
  /// Before the router is built there is no context to redirect with, so the
  /// target is applied as it stands and the first build settles it.
  void _navigate(
    _MatchList target,
    void Function(_MatchList resolved) apply, {
    void Function()? overtaken,
  }) {
    final generation = ++_generation;
    final context = _context;
    if (context == null) {
      _unresolved = true;
      apply(target);
      return;
    }
    final resolved = _resolve(context, target, [target.location]);
    if (resolved is Future<_MatchList>) {
      resolved.then((list) {
        if (_disposed || generation != _generation) {
          overtaken?.call();
          return;
        }
        _ready = true;
        apply(list);
      });
    } else {
      _ready = true;
      apply(resolved);
    }
  }

  // -- Navigation -----------------------------------------------------------

  /// Goes to [location], replacing the whole stack with it.
  void go(String location, {Object? extra}) {
    _navigate(_parse(location, extra), (resolved) {
      final same = resolved.location == _stack.last.list.location;
      _commit(
        [_Entry(resolved)],
        // Going where the app already is adds no step to the browser's Back.
        _stack.length == 1 && same ? _Mirror.replace : _Mirror.push,
      );
    });
  }

  /// [go] to the route called [name].
  void goNamed(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    Object? extra,
  }) => go(
    namedLocation(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
    ),
    extra: extra,
  );

  /// Puts [location] on top of the stack, to be [pop]ped back off. The future
  /// completes with whatever it is popped with.
  ///
  /// The page underneath is covered, not gone: it keeps its `State`, and is
  /// as it was left when this one is popped.
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    final completer = Completer<Object?>();
    _navigate(
      _parse(location, extra),
      (resolved) => _commit([
        ..._stack,
        _Entry(resolved, pushId: _nextPushId++, completer: completer),
      ], _Mirror.push),
      overtaken: () => completer.complete(null),
    );
    return completer.future.then((value) => value as T?);
  }

  /// [push] the route called [name].
  Future<T?> pushNamed<T extends Object?>(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    Object? extra,
  }) => push<T>(
    namedLocation(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
    ),
    extra: extra,
  );

  /// Swaps what the top of the stack shows for [location], treating it as the
  /// same page: a pushed page stays the page it was, and whoever is awaiting
  /// its `push` is still answered when it is popped.
  Future<T?> replace<T>(String location, {Object? extra}) {
    final top = _stack.last;
    _navigate(
      _parse(location, extra),
      (resolved) => _commit([
        ..._stack.take(_stack.length - 1),
        top.withList(resolved),
      ], _Mirror.replace),
    );
    final completer = top.completer;
    return completer == null
        ? Future<T?>.value()
        : completer.future.then((value) => value as T?);
  }

  /// Whether [pop] has anything to pop: a pushed page, or a page whose route
  /// is nested inside another page's (`/users/7` under `/users`).
  bool canPop() => _stack.length > 1 || _stack.last.list.pageCount > 1;

  /// Leaves the page on top, completing its `push` with [result].
  ///
  /// Throws a [GoError] when there is nothing to pop, as go_router does; ask
  /// [canPop] first where that can happen.
  void pop<T extends Object?>([T? result]) {
    if (!canPop()) throw GoError('There is nothing to pop');
    _tellPagePopped(result);
    _generation++;
    final top = _stack.last;
    final under = _stack.take(_stack.length - 1);
    if (top.list.pageCount > 1) {
      // The page sits on its parent route's page: `/users/7` over `/users`.
      // Leaving it uncovers the parent, within the same stack entry.
      final matches = top.list.matches;
      var keep = matches.length - 1;
      while (!matches[keep - 1].isPage) {
        keep--;
      }
      final parent = _MatchList(
        uri: Uri(path: matches[keep - 1].matchedLocation),
        matches: matches.sublist(0, keep),
        pathParameters: top.list.pathParameters,
      );
      _commit([...under, top.withList(parent)], _Mirror.pop);
    } else {
      top.complete(result);
      _commit(under.toList(), _Mirror.pop);
    }
  }

  /// Runs the redirects again for where the app is now, and rebuilds.
  ///
  /// What `refreshListenable` calls when it fires: the session ended, so the
  /// redirect that guards the page now has a different answer. If it sends
  /// the app elsewhere, that replaces the whole stack - a page pushed over one
  /// the user may no longer see has no business staying up.
  void refresh() {
    if (_disposed) return;
    _settle(notify: true);
  }

  void _settle({required bool notify}) {
    final top = _stack.last;
    var returned = false;
    _navigate(_parse(top.list.location, top.list.extra), (resolved) {
      final stayed = resolved.location == top.list.location;
      _commit(
        stayed
            ? [..._stack.take(_stack.length - 1), top.withList(resolved)]
            : [_Entry(resolved)],
        stayed ? _Mirror.none : _Mirror.replace,
        // An answer that arrives during a build is about to be drawn by it;
        // one an asynchronous redirect delivers later has to ask.
        notify: notify || returned,
      );
    });
    returned = true;
  }

  /// Makes [stack] the stack: answers the pushes that are no longer on it,
  /// keeps the platform's history in step, and redraws.
  void _commit(List<_Entry> stack, _Mirror mirror, {bool notify = true}) {
    final previous = _stack;
    _stack = stack;
    for (final entry in previous) {
      if (entry.pushId == null) continue;
      if (stack.any((kept) => kept.pushId == entry.pushId)) continue;
      // Swept away by a `go` or a redirect rather than popped with a result.
      entry.complete(null);
    }
    _mirrorToHistory(mirror);
    if (notify && !_disposed) notifyListeners();
  }

  // -- Back, and the platform's history -------------------------------------

  HistoryAdapter _history = const NoHistoryAdapter();
  bool _backBound = false;

  /// What the platform's history holds, one stack per entry, and which of
  /// them the app is on. Only kept for a platform with a history of its own.
  final List<List<_Entry>> _trail = [];
  int _trailAt = 0;

  /// Platform pops this router asked for itself, which must not be read as the
  /// user pressing Back.
  int _selfInflictedPops = 0;

  /// Keeps the platform's history in step with this router - on web, the
  /// browser's Back button and the URL.
  ///
  /// The adapter is the browser's half, which this file cannot import and
  /// still compile for a Flutter host:
  ///
  /// ```dart
  /// import 'package:dart_not_native/web.dart';
  ///
  /// final history = BrowserHistoryAdapter();
  /// final router = GoRouter(
  ///   initialLocation: history.currentPath ?? '/', // a reload, a deep link
  ///   routes: [...],
  /// )..attachHistory(history);
  /// bindBrowserBack();
  /// ```
  ///
  /// Every `go` and `push` becomes a history entry, written to the URL
  /// fragment, and Back returns to the one before it. Without a call to this,
  /// the router still answers the back gesture - Android's button, the iOS
  /// edge swipe - by popping while there is something to pop.
  ///
  /// Unlike go_router, a `push` changes the URL too. There the URL follows
  /// only `go` unless an option says otherwise; here Back is the only way a
  /// browser user has to leave a pushed page, so it has to be an entry.
  void attachHistory(HistoryAdapter adapter) {
    final wasBound = _backBound;
    _unbindBack();
    _history = adapter;
    // Before the first build the binding waits for it, so the entry written
    // is the redirected location rather than the one asked for.
    if (wasBound || _context != null) _bindBack();
  }

  late final SystemBackHandler _backHandler = _handleBack;
  late final SystemBackHandler _forwardHandler = _handleForward;

  /// The browser went forward, onto an entry a Back had stepped off. The
  /// stack that entry stood for is still in the trail, so the app goes there
  /// too - through the redirects, like a Back. False with nothing ahead.
  bool _handleForward() {
    if (!_history.hasStack || _trailAt >= _trail.length - 1) return false;
    _trailAt++;
    _generation++;
    _commit(_trail[_trailAt], _Mirror.none, notify: false);
    _settle(notify: true);
    return true;
  }

  void _bindBack() {
    if (_backBound) return;
    _backBound = true;
    _trail
      ..clear()
      ..add(_stack);
    _trailAt = 0;
    if (_history.hasStack) {
      HistoryAdapter.mirrors++;
      _history.replace(_stack.last.list.location);
    }
    SystemBack.addHandler(_backHandler);
    SystemBack.addForwardHandler(_forwardHandler);
    SystemBack.addFilter(_swallowSelfInflictedPop);
    SystemBack.addListener(_restoreEntryConsumedElsewhere);
  }

  void _unbindBack() {
    if (!_backBound) return;
    _backBound = false;
    if (_history.hasStack) HistoryAdapter.mirrors--;
    SystemBack.removeHandler(_backHandler);
    SystemBack.removeForwardHandler(_forwardHandler);
    SystemBack.removeFilter(_swallowSelfInflictedPop);
    SystemBack.removeListener(_restoreEntryConsumedElsewhere);
  }

  /// Swallows the pop this router asked the platform for, before a handler
  /// registered after it - an open dialog - can mistake it for the user's.
  bool _swallowSelfInflictedPop() {
    if (_selfInflictedPops == 0) return false;
    _selfInflictedPops--;
    return true;
  }

  /// Puts the platform's entry back when Back was consumed by something other
  /// than this router. The browser has already moved by the time it reports
  /// Back; if a dialog took the gesture, the screen stayed, so the URL must.
  void _restoreEntryConsumedElsewhere(SystemBackHandler? consumedBy) {
    if (!_history.hasStack || consumedBy == null) return;
    if (consumedBy == _backHandler) return;
    _history.push(_stack.last.list.location);
  }

  /// The platform asked to go back. Returns whether this router had somewhere
  /// to go; false leaves the platform to do what it would - close the app.
  /// Lets the `PopScope`s on the page showing hear that it is being popped,
  /// while they are still there to hear it.
  void _tellPagePopped(Object? result) {
    final context = _context;
    if (context != null && context.mounted) {
      PopScope.notifyPopped(context, result);
    }
  }

  bool _handleBack() {
    if (!_history.hasStack) {
      // No history to consult: back is "pop", while there is something to.
      if (!canPop()) return false;
      pop();
      return true;
    }
    if (_trailAt == 0) return false;
    _tellPagePopped(null);
    // The browser is already on the previous entry. Put the app there too,
    // without writing it back, then let the redirects see it: the page being
    // returned to may be one the user is no longer allowed.
    _trailAt--;
    _generation++;
    _commit(_trail[_trailAt], _Mirror.none, notify: false);
    _settle(notify: true);
    return true;
  }

  void _mirrorToHistory(_Mirror mirror) {
    if (!_backBound || !_history.hasStack) return;
    final location = _stack.last.list.location;
    switch (mirror) {
      case _Mirror.push:
        // Anything Forward of here is gone, as the browser will have it.
        _trail.removeRange(_trailAt + 1, _trail.length);
        _trail.add(_stack);
        _trailAt++;
        _history.push(location);
      case _Mirror.pop
          when _trailAt > 0 && _sameLocations(_trail[_trailAt - 1], _stack):
        // The entry before this one is where the pop lands, so step the
        // platform back to it - and ignore the pop it reports in return.
        _trailAt--;
        _trail[_trailAt] = _stack;
        _selfInflictedPops++;
        _history.back();
      case _Mirror.pop || _Mirror.replace:
        _trail[_trailAt] = _stack;
        _history.replace(location);
      case _Mirror.none:
        _trail[_trailAt] = _stack;
    }
  }

  static bool _sameLocations(List<_Entry> a, List<_Entry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].list.location != b[i].list.location) return false;
    }
    return true;
  }

  // -- Drawing --------------------------------------------------------------

  /// The page on screen, in its shells. What `MaterialApp.router` draws.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: this,
    builder: (_, _) => _RouterScope(
      router: this,
      // A context from below the scope, so the one a redirect is handed can
      // find this router the way a page's can.
      child: Builder(
        builder: (context) {
          _attach(context);
          return _ready ? _buildTop() : const SizedBox();
        },
      ),
    ),
  );

  void _attach(BuildContext context) {
    _context = context;
    if (_unresolved) {
      _unresolved = false;
      _settle(notify: false);
    }
    _bindBack();
  }

  /// Every page on the stack, the top one showing.
  Widget _buildTop() {
    final pages = <_PageSpec>[];
    for (final entry in _stack) {
      final list = entry.list;
      final pushed = entry.pushId == null ? '' : 'push${entry.pushId}:';
      if (list.page == null) {
        final problem = list.error != null
            ? list
            : _MatchList(
                uri: list.uri,
                error: GoException(
                  'no page for location: ${list.uri} (the route has no '
                  'builder and its redirect let it through)',
                ),
              );
        pages.add(
          _PageSpec(
            const [],
            list,
            '${pushed}error:${list.location}',
            problem.topState,
            _errorBuilder ?? _defaultErrorPage,
          ),
        );
        continue;
      }
      // A route nested in another's is a page over its parent's page:
      // `/users/7` covers `/users`, which is still there when it is popped.
      final shells = <_Match>[];
      for (final match in list.matches) {
        final route = match.route;
        if (route is ShellRoute) {
          shells.add(match);
        } else if (route is GoRoute && route.builder != null) {
          final top = identical(match, list.matches.last);
          pages.add(
            _PageSpec(
              List.of(shells),
              list,
              // A page's State lasts as long as the page is on the stack. A
              // page arrived at with `go` is keyed by what it matched, so
              // another route's page is another page even when both build the
              // same widget, and a changed query string is the same one. A
              // pushed page is itself wherever it points, which is what lets
              // `replace` change that.
              top && entry.pushId != null
                  ? 'push${entry.pushId}'
                  : '${pushed}page:${match.matchedLocation}',
              list.stateFor(match),
              route.builder!,
            ),
          );
        }
      }
    }
    return _buildPages(pages, 0, '');
  }

  /// Draws [pages], oldest first, each inside the shells it has from [depth]
  /// on. Pages that share a shell share one frame, with their own stack
  /// inside it - so a page pushed within a shell appears in the frame that
  /// is already there, and one pushed from outside covers it.
  Widget _buildPages(List<_PageSpec> pages, int depth, String scope) {
    final layers = <Widget>[];
    final seen = <ShellRoute>{};
    var i = 0;
    while (i < pages.length) {
      final page = pages[i];
      if (page.shells.length <= depth) {
        layers.add(
          _Page(
            key: _RouteKey(this, '$scope${page.tag}'),
            state: page.state,
            builder: page.builder,
          ),
        );
        i++;
        continue;
      }
      final shell = page.shells[depth].route as ShellRoute;
      var end = i + 1;
      while (end < pages.length &&
          pages[end].shells.length > depth &&
          identical(pages[end].shells[depth].route, shell)) {
        end++;
      }
      final inside = pages.sublist(i, end);
      // Keyed by the shell alone, which is what lets its State outlive the
      // pages that come and go inside it. The same shell reached a second
      // time, over something that is not in it, is a second frame.
      final tag = seen.add(shell)
          ? '${scope}shell${_shellIds[shell]}'
          : '${scope}shell${_shellIds[shell]}@$i';
      final child = _buildPages(inside, depth + 1, '$tag/');
      layers.add(
        _Page(
          key: _RouteKey(this, tag),
          // The frame describes the page showing in it.
          state: inside.last.list.stateFor(inside.last.shells[depth]),
          builder: (context, state) => shell.builder!(context, state, child),
        ),
      );
      i = end;
    }
    // Always a stack, even of one: a page must not move in the tree - and so
    // lose the State of everything keyless inside it - the first time
    // something is pushed over it.
    return IndexedStack(index: layers.length - 1, children: layers);
  }

  static Widget _defaultErrorPage(BuildContext context, GoRouterState state) =>
      Scaffold(
        body: Center(child: Text('Page not found\n${state.error?.message}')),
      );

  @override
  void dispose() {
    _disposed = true;
    _refreshListenable?.removeListener(refresh);
    _unbindBack();
    for (final entry in _stack) {
      entry.complete(null);
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// The widgets a match is drawn with.
// ---------------------------------------------------------------------------

/// Identity for a page or a shell. A class of its own rather than a
/// `ValueKey`, so it can never equal a key the app chose.
class _RouteKey extends LocalKey {
  const _RouteKey(this.router, this.tag);
  final GoRouter router;
  final String tag;

  @override
  bool operator ==(Object other) =>
      other is _RouteKey && identical(other.router, router) && other.tag == tag;

  @override
  int get hashCode => Object.hash(router, tag);

  // Part of the path that tells keyless widgets below apart, so it has to be
  // as distinct as the key is.
  @override
  String toString() => 'router${router._serial}:$tag';
}

class _RouterScope extends InheritedWidget {
  const _RouterScope({required this.router, required super.child});
  final GoRouter router;

  @override
  bool updateShouldNotify(_RouterScope oldWidget) =>
      !identical(oldWidget.router, router);
}

class _StateScope extends InheritedWidget {
  const _StateScope({required this.state, required super.child});
  final GoRouterState state;

  // A state is made afresh for each build, so it is compared by where it
  // says the app is and what it was handed.
  @override
  bool updateShouldNotify(_StateScope oldWidget) =>
      oldWidget.state.uri != state.uri ||
      oldWidget.state.matchedLocation != state.matchedLocation ||
      oldWidget.state.fullPath != state.fullPath ||
      !identical(oldWidget.state.extra, state.extra);
}

/// One page, or one shell, with its [GoRouterState] visible to what it builds.
///
/// Stateful for what that buys rather than for any state of its own: a
/// stateful widget is the unit of identity here, and everything built below
/// one is told apart by it. Keying this is therefore what keys the page.
class _Page extends StatefulWidget {
  const _Page({
    required _RouteKey super.key,
    required this.state,
    required this.builder,
  });

  final GoRouterState state;
  final GoRouterWidgetBuilder builder;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => _StateScope(
    state: widget.state,
    // Built from below the scope, so `GoRouterState.of` works on the very
    // context the route's builder is given.
    child: Builder(builder: (context) => widget.builder(context, widget.state)),
  );
}

/// go_router's navigation on the context: `context.go('/guests')`.
extension GoRouterHelper on BuildContext {
  /// See [GoRouter.namedLocation].
  String namedLocation(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
  }) => GoRouter.of(this).namedLocation(
    name,
    pathParameters: pathParameters,
    queryParameters: queryParameters,
  );

  /// See [GoRouter.go].
  void go(String location, {Object? extra}) =>
      GoRouter.of(this).go(location, extra: extra);

  /// See [GoRouter.goNamed].
  void goNamed(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    Object? extra,
  }) => GoRouter.of(this).goNamed(
    name,
    pathParameters: pathParameters,
    queryParameters: queryParameters,
    extra: extra,
  );

  /// See [GoRouter.push].
  Future<T?> push<T extends Object?>(String location, {Object? extra}) =>
      GoRouter.of(this).push<T>(location, extra: extra);

  /// See [GoRouter.pushNamed].
  Future<T?> pushNamed<T extends Object?>(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, dynamic> queryParameters = const <String, dynamic>{},
    Object? extra,
  }) => GoRouter.of(this).pushNamed<T>(
    name,
    pathParameters: pathParameters,
    queryParameters: queryParameters,
    extra: extra,
  );

  /// See [GoRouter.canPop].
  bool canPop() => GoRouter.of(this).canPop();

  /// See [GoRouter.pop].
  void pop<T extends Object?>([T? result]) => GoRouter.of(this).pop(result);

  /// See [GoRouter.replace].
  void replace(String location, {Object? extra}) =>
      GoRouter.of(this).replace<Object?>(location, extra: extra);
}
