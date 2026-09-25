/// App Builder - Fluent API for configuring apps with plugins
///
/// Simplifies app initialization with routing, i18n, plugins, and renderers.

library;

import 'package:dart_not_native/src/ui_renderer.dart';
import 'package:dart_not_native/routing/navigation_app.dart';
import 'package:dart_not_native/i18n/translations.dart';
import 'plugin.dart';

/// Fluent app configuration builder
class NativeAppBuilder {
  final List<Plugin> _plugins = [];
  NavigationAppBuilder? _routerBuilder;
  I18n? _i18n;
  NativeUIRenderer? _renderer;
  final Map<String, dynamic> _config = {};

  /// Add a plugin to the app
  NativeAppBuilder addPlugin(Plugin plugin) {
    _plugins.add(plugin);
    return this;
  }

  /// Add multiple plugins
  NativeAppBuilder addPlugins(List<Plugin> plugins) {
    _plugins.addAll(plugins);
    return this;
  }

  /// Set up routing
  NativeAppBuilder withRouting(
    NavigationAppBuilder Function(NativeAppBuilder) configure,
  ) {
    _routerBuilder = configure(this);
    return this;
  }

  /// Set up i18n
  NativeAppBuilder withI18n(I18n i18n) {
    _i18n = i18n;
    return this;
  }

  /// Set renderer
  NativeAppBuilder withRenderer(NativeUIRenderer renderer) {
    _renderer = renderer;
    return this;
  }

  /// Set configuration value
  NativeAppBuilder setConfig(String key, dynamic value) {
    _config[key] = value;
    return this;
  }

  /// Set multiple configuration values
  NativeAppBuilder setConfigs(Map<String, dynamic> config) {
    _config.addAll(config);
    return this;
  }

  /// Build and initialize the app
  Future<NativeApp> build() async {
    // Register plugins
    final registry = getPluginRegistry();
    registry.registerAll(_plugins);

    // Initialize plugins
    await registry.initialize();

    // Create app instance
    final app = NativeApp(
      plugins: _plugins,
      routerBuilder: _routerBuilder,
      i18n: _i18n,
      renderer: _renderer,
      config: _config,
    );

    return app;
  }
}

/// Initialized native app instance
class NativeApp {
  final List<Plugin> plugins;
  final NavigationAppBuilder? routerBuilder;
  final I18n? i18n;
  final NativeUIRenderer? renderer;
  final Map<String, dynamic> config;
  late NavigationApp? router;

  NativeApp({
    required this.plugins,
    this.routerBuilder,
    this.i18n,
    this.renderer,
    required this.config,
  });

  /// Get plugin by name
  Plugin? getPlugin(String name) => getPluginRegistry().getPlugin(name);

  /// Get service by name
  T? getService<T>(String name) => getPluginService<T>(name);

  /// Get all plugins
  List<Plugin> getPlugins() => List.unmodifiable(plugins);

  /// Initialize routing if configured
  Future<void> initializeRouting() async {
    if (routerBuilder != null && renderer != null) {
      router = routerBuilder!.setInitialPath('/').build();
      router!.render(renderer!);
    }
  }

  /// Render current route
  void render(WidgetNode tree) {
    renderer?.render(tree);
  }

  /// Navigate
  Future<bool> navigate(String path, {Map<String, dynamic>? params}) async {
    if (router == null) return false;
    return router!.navigate(path, params: params);
  }

  /// Dispose app and all plugins
  Future<void> dispose() async {
    await getPluginRegistry().dispose();
  }

  /// Get configuration value
  T? getConfig<T>(String key) {
    final value = config[key];
    return value is T ? value : null;
  }
}
