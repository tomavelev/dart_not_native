/// NavigationApp - Integrates router with the UI framework
///
/// Provides a high-level widget for multi-screen apps with routing.
library;

import 'package:dart_not_native/src/native_ui_app.dart';
import 'package:dart_not_native/src/ui_renderer.dart';
import 'history_sync.dart';
import 'route.dart' as routing;

/// App state for navigation
class NavigationAppState {
  final routing.Router router;
  DateTime lastUpdated = DateTime.now();

  NavigationAppState({required this.router});
}

/// Mixed into a [NativeUIApp] that routes, so a host can reach the
/// [NavigationApp] driving it - to wire the platform back gesture, for one -
/// without the app having to do it itself.
///
/// ```dart
/// class MyApp extends NativeUIApp with NavigationHost {
///   @override
///   late final NavigationApp nav = NavigationAppBuilder()...build();
/// }
/// ```
mixin NavigationHost on NativeUIApp {
  NavigationApp get nav;
}

/// High-level navigation app widget
class NavigationApp {
  final routing.Router router;
  NativeUIRenderer? _renderer;
  Function(NavigationAppState)? _onStateChange;

  NavigationApp({required this.router});

  RouterHistorySync? _historySync;

  /// Wires the platform back gesture - the Android back button, the iOS swipe
  /// from the left screen edge, the browser's Back button - to this app's
  /// router, so it pops a route instead of leaving the app.
  ///
  /// Pass the [adapter] for platforms that keep their own history stack
  /// (`BrowserHistoryAdapter` from `package:dart_not_native/web.dart`); the
  /// default suits Android and iOS, where back is only a gesture.
  ///
  /// Returns the binding, so an app that shows modals can consult it.
  RouterHistorySync bindSystemBack({
    HistoryAdapter adapter = const NoHistoryAdapter(),
  }) {
    final sync = _historySync ??= RouterHistorySync(
      router: router,
      adapter: adapter,
    );
    sync.bind();
    return sync;
  }

  /// Stops handling the platform back gesture.
  void unbindSystemBack() => _historySync?.unbind();

  /// Whether the platform back gesture is wired to this app.
  bool get handlesSystemBack => _historySync?.isBound ?? false;

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
  final List<routing.Route> routes = [];
  routing.Route? notFoundRoute;
  String? initialPath;

  /// Add a route
  NavigationAppBuilder addRoute({
    required String path,
    required String name,
    required routing.RouteBuilder builder,
    routing.Transition transition = routing.Transition.slideRight,
    Duration transitionDuration = const Duration(milliseconds: 300),
    List<routing.RouteGuard>? guards,
    Map<String, dynamic>? defaultParams,
  }) {
    routes.add(
      routing.Route(
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
  NavigationAppBuilder setNotFoundRoute(routing.RouteBuilder builder) {
    notFoundRoute = routing.Route(
      path: '/404',
      name: 'not_found',
      builder: builder,
    );
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

    final config = routing.RouterConfig(
      routes: routes,
      notFoundRoute: notFoundRoute,
      initialPath: initialPath!,
    );

    return NavigationApp(router: routing.Router(config: config));
  }
}

/// Helper to build route builders
class RouteBuilders {
  /// Build a simple static route
  static routing.RouteBuilder simple(WidgetNode widget) {
    return (_) => widget;
  }

  /// Build a route with parameters
  static routing.RouteBuilder withParams(
    WidgetNode Function(Map<String, dynamic> params) builder,
  ) {
    return builder;
  }

  /// Build a route with dynamic content
  static routing.RouteBuilder dynamicPath(
    WidgetNode Function(String path, Map<String, dynamic> params) builder,
  ) {
    return (params) => builder('', params);
  }

  /// Build a route that shows parameters
  static routing.RouteBuilder showParams() {
    return (params) => UIBuilder.column(
      children: [
        UIBuilder.text('Route Parameters:'),
        UIBuilder.sizedBox(height: 16),
        ...params.entries.map((e) => UIBuilder.text('${e.key}: ${e.value}')),
      ],
    );
  }
}
