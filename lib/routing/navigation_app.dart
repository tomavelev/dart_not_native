/// NavigationApp - Integrates router with the UI framework
///
/// Provides a high-level widget for multi-screen apps with routing.

import 'package:dart_not_native/material.dart';
import 'package:dart_not_native/routing/route.dart';

/// App state for navigation
class NavigationAppState {
  final Router router;
  DateTime lastUpdated = DateTime.now();

  NavigationAppState({required this.router});
}

/// High-level navigation app widget
class NavigationApp {
  final Router router;
  NativeUIRenderer? _renderer;
  Function(NavigationAppState)? _onStateChange;

  NavigationApp({required this.router});

  /// Listen to app state changes
  void onStateChange(Function(NavigationAppState) callback) {
    _onStateChange = callback;
  }

  /// Set renderer and start rendering
  void render(NativeUIRenderer renderer) {
    _renderer = renderer;

    // Listen to route changes
    router.onRouteChange((event) {
      _renderCurrentRoute();
    });

    // Initial render
    _renderCurrentRoute();
  }

  void _renderCurrentRoute() {
    if (_renderer == null) return;

    final tree = router.buildCurrentRoute();
    _renderer!.render(tree);

    _onStateChange?.call(NavigationAppState(router: router));
  }

  /// Navigate to a path
  Future<bool> navigate(String path, {Map<String, dynamic>? params}) {
    return router.navigate(path, params: params);
  }

  /// Navigate by route name
  Future<bool> navigateNamed(String name, {Map<String, dynamic>? params}) {
    return router.navigateNamed(name, params: params);
  }

  /// Go back
  bool goBack() {
    return router.goBack();
  }

  /// Get current path
  String get currentPath => router.currentPath;

  /// Get current params
  Map<String, dynamic> get currentParams => router.currentParams;

  /// Get history
  List<String> get history => router.history;
}

/// Builder helper for creating NavigationApp with routes
class NavigationAppBuilder {
  final List<Route> routes = [];
  Route? notFoundRoute;
  String? initialPath;

  /// Add a route
  NavigationAppBuilder addRoute({
    required String path,
    required String name,
    required RouteBuilder builder,
    Transition transition = Transition.slideRight,
    Duration transitionDuration = const Duration(milliseconds: 300),
    List<RouteGuard>? guards,
    Map<String, dynamic>? defaultParams,
  }) {
    routes.add(
      Route(
        path: path,
        name: name,
        builder: builder,
        transition: transition,
        transitionDuration: transitionDuration,
        guards: guards,
        defaultParams: defaultParams,
      ),
    );
    return this;
  }

  /// Set 404 route
  NavigationAppBuilder setNotFoundRoute(RouteBuilder builder) {
    notFoundRoute = Route(path: '/404', name: 'not_found', builder: builder);
    return this;
  }

  /// Set initial path
  NavigationAppBuilder setInitialPath(String path) {
    initialPath = path;
    return this;
  }

  /// Build the app
  NavigationApp build() {
    if (initialPath == null) {
      throw ArgumentError('initialPath is required');
    }

    final config = RouterConfig(
      routes: routes,
      notFoundRoute: notFoundRoute,
      initialPath: initialPath!,
    );

    return NavigationApp(router: Router(config: config));
  }
}

/// Helper to build route builders
class RouteBuilders {
  /// Build a simple static route
  static RouteBuilder simple(WidgetNode widget) {
    return (_) => widget;
  }

  /// Build a route with parameters
  static RouteBuilder withParams(
    WidgetNode Function(Map<String, dynamic> params) builder,
  ) {
    return builder;
  }

  /// Build a route with dynamic content
  static RouteBuilder dynamicPath(
    WidgetNode Function(String path, Map<String, dynamic> params) builder,
  ) {
    return (params) => builder('', params);
  }

  /// Build a route that shows parameters
  static RouteBuilder showParams() {
    return (params) => UIBuilder.column(
      children: [
        UIBuilder.text('Route Parameters:'),
        UIBuilder.sizedBox(height: 16),
        ...params.entries
            .map((e) => UIBuilder.text('${e.key}: ${e.value}'))
            .toList(),
      ],
    );
  }
}
