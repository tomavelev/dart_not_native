/// Route Definition and Management
///
/// Core routing system for multi-screen navigation support.

import 'package:dart_not_native/src/ui_renderer.dart';

typedef RouteBuilder = WidgetNode Function(Map<String, dynamic> params);
typedef RouteGuard = Future<bool> Function();

/// Represents a transition animation style
enum Transition {
  fade, // Fade in/out
  slideLeft, // Slide from left
  slideRight, // Slide from right
  slideUp, // Slide from bottom
  slideDown, // Slide from top
  scale, // Scale animation
  none, // No animation
}

/// Route configuration
class Route {
  final String path;
  final String name;
  final RouteBuilder builder;
  final Transition? transition;
  final Duration transitionDuration;
  final List<RouteGuard>? guards;
  final Map<String, dynamic>? defaultParams;

  Route({
    required this.path,
    required this.name,
    required this.builder,
    this.transition = Transition.slideRight,
    this.transitionDuration = const Duration(milliseconds: 300),
    this.guards,
    this.defaultParams,
  });

  /// Extract parameters from a URL path
  Map<String, dynamic> extractParams(String urlPath) {
    // Copy the defaults: defaultParams is the route definition, not
    // per-navigation state, so writing extracted params into it would leak
    // them into the next navigation.
    final params = {...?defaultParams};

    // Simple parameter extraction: /users/:id -> {id: value}
    final pathSegments = path.split('/');
    final urlSegments = urlPath.split('/');

    for (int i = 0; i < pathSegments.length; i++) {
      if (i >= urlSegments.length) break;

      final segment = pathSegments[i];
      if (segment.startsWith(':')) {
        final paramName = segment.substring(1);
        params[paramName] = urlSegments[i];
      }
    }

    return params;
  }

  /// Check if this route matches the given path
  bool matches(String urlPath) {
    final pathSegments = path.split('/');
    final urlSegments = urlPath.split('/');

    if (pathSegments.length != urlSegments.length) return false;

    for (int i = 0; i < pathSegments.length; i++) {
      final segment = pathSegments[i];
      final urlSegment = urlSegments[i];

      if (segment.startsWith(':')) {
        // Parameter - always matches
        continue;
      } else if (segment != urlSegment) {
        return false;
      }
    }

    return true;
  }
}

/// Route entry in navigation history
class RouteEntry {
  final Route route;
  final String path;
  final Map<String, dynamic> params;
  final DateTime timestamp;

  RouteEntry({required this.route, required this.path, required this.params})
    : timestamp = DateTime.now();
}

/// Navigation state and history
class NavigationState {
  final List<RouteEntry> history;
  int _currentIndex;

  NavigationState({required Route initialRoute, required String initialPath})
    : history = [
        RouteEntry(
          route: initialRoute,
          path: initialPath,
          params: initialRoute.extractParams(initialPath),
        ),
      ],
      _currentIndex = 0;

  /// Current route
  RouteEntry get current => history[_currentIndex];

  /// Can navigate back?
  bool get canGoBack => _currentIndex > 0;

  /// Can navigate forward?
  bool get canGoForward => _currentIndex < history.length - 1;

  /// Full history (for debugging)
  List<String> get pathHistory => history.map((e) => e.path).toList();

  /// Add entry to history
  void push(RouteEntry entry) {
    // Remove forward history when navigating to new route
    if (_currentIndex < history.length - 1) {
      history.removeRange(_currentIndex + 1, history.length);
    }
    history.add(entry);
    _currentIndex = history.length - 1;
  }

  /// Navigate back
  bool pop() {
    if (canGoBack) {
      _currentIndex--;
      return true;
    }
    return false;
  }

  /// Navigate forward
  bool forward() {
    if (canGoForward) {
      _currentIndex++;
      return true;
    }
    return false;
  }

  /// Replace current route
  void replace(RouteEntry entry) {
    history[_currentIndex] = entry;
  }
}

/// Router configuration
class RouterConfig {
  final List<Route> routes;
  final Route? notFoundRoute;
  final String initialPath;

  RouterConfig({
    required this.routes,
    this.notFoundRoute,
    required this.initialPath,
  });

  /// Find route by name
  Route? findByName(String name) {
    try {
      return routes.firstWhere((r) => r.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Find route by path
  Route? findByPath(String path) {
    try {
      return routes.firstWhere((r) => r.matches(path));
    } catch (e) {
      return notFoundRoute;
    }
  }
}

/// Router state change event
class RouterEvent {
  final String type; // 'push', 'pop', 'replace', 'forward'
  final RouteEntry from;
  final RouteEntry to;
  final DateTime timestamp;

  RouterEvent({required this.type, required this.from, required this.to})
    : timestamp = DateTime.now();
}

/// Router - manages navigation and history
class Router {
  final RouterConfig config;
  late NavigationState state;
  final List<Function(RouterEvent)> listeners = [];

  Router({required this.config}) {
    final initialRoute = config.findByPath(config.initialPath);
    if (initialRoute == null) {
      throw ArgumentError(
        'No route found for initial path: ${config.initialPath}',
      );
    }
    state = NavigationState(
      initialRoute: initialRoute,
      initialPath: config.initialPath,
    );
  }

  /// Listen to route changes
  void onRouteChange(Function(RouterEvent) listener) {
    listeners.add(listener);
  }

  /// Remove listener
  void removeListener(Function(RouterEvent) listener) {
    listeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners(RouterEvent event) {
    for (final listener in listeners) {
      listener(event);
    }
  }

  /// Navigate to path
  Future<bool> navigate(String path, {Map<String, dynamic>? params}) async {
    final route = config.findByPath(path);
    if (route == null) return false;

    // Run route guards
    if (route.guards != null) {
      for (final guard in route.guards!) {
        final allowed = await guard();
        if (!allowed) return false;
      }
    }

    final routeParams = {...route.extractParams(path), ...?params};
    final entry = RouteEntry(route: route, path: path, params: routeParams);

    final from = state.current;
    state.push(entry);

    _notifyListeners(RouterEvent(type: 'push', from: from, to: entry));

    return true;
  }

  /// Navigate by route name with parameters
  Future<bool> navigateNamed(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    final route = config.findByName(name);
    if (route == null) return false;

    return navigate(route.path, params: params);
  }

  /// Go back
  bool goBack() {
    if (!state.canGoBack) return false;

    final from = state.current;
    state.pop();
    final to = state.current;

    _notifyListeners(RouterEvent(type: 'pop', from: from, to: to));

    return true;
  }

  /// Go forward
  bool goForward() {
    if (!state.canGoForward) return false;

    final from = state.current;
    state.forward();
    final to = state.current;

    _notifyListeners(RouterEvent(type: 'forward', from: from, to: to));

    return true;
  }

  /// Replace current route
  void replaceWith(String path, {Map<String, dynamic>? params}) {
    final route = config.findByPath(path);
    if (route == null) return;

    final routeParams = {...route.extractParams(path), ...?params};
    final entry = RouteEntry(route: route, path: path, params: routeParams);

    final from = state.current;
    state.replace(entry);

    _notifyListeners(RouterEvent(type: 'replace', from: from, to: entry));
  }

  /// Get current route entry
  RouteEntry get currentRoute => state.current;

  /// Get current path
  String get currentPath => state.current.path;

  /// Get current parameters
  Map<String, dynamic> get currentParams => state.current.params;

  /// Build current route widget
  WidgetNode buildCurrentRoute() {
    return state.current.route.builder(state.current.params);
  }

  /// Get navigation history for debugging
  List<String> get history => state.pathHistory;
}
