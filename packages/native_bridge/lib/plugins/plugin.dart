/// Plugin System - Extensible Architecture
///
/// Core plugin interfaces and lifecycle management for easy feature addition.

library;

import 'package:dart_not_native/src/ui_renderer.dart';
import 'package:dart_not_native/routing/navigation_app.dart';

/// Plugin lifecycle state
enum PluginState {
  uninitialized,
  initializing,
  initialized,
  disposing,
  disposed,
  error,
}

/// Plugin context for accessing framework services
class PluginContext {
  final Map<String, dynamic> _services = {};
  final Map<String, dynamic> _config = {};
  final List<String> _dependsOn = [];

  /// Register a service provided by this plugin
  void registerService<T>(String name, T service) {
    _services[name] = service;
  }

  /// Get a service from registry
  T? getService<T>(String name) {
    final service = _services[name];
    return service is T ? service : null;
  }

  /// Set configuration value
  void setConfig(String key, dynamic value) {
    _config[key] = value;
  }

  /// Get configuration value
  T? getConfig<T>(String key) {
    final value = _config[key];
    return value is T ? value : null;
  }

  /// Declare dependency on another plugin
  void dependsOn(String pluginName) {
    _dependsOn.add(pluginName);
  }

  /// Get all service names
  List<String> get serviceNames => _services.keys.toList();

  /// Get all services
  Map<String, dynamic> get allServices => Map.from(_services);

  /// Check if service exists
  bool hasService(String name) => _services.containsKey(name);

  /// Get all dependencies
  List<String> get dependencies => List.from(_dependsOn);
}

/// Base class for all plugins
abstract class Plugin {
  /// Plugin metadata
  String get name;
  String get version;
  String? get description;

  /// Stable identifier, used as the key a plugin registers its services under.
  /// Defaults to [name], which is what a plugin with one service wants.
  String get id => name;

  /// Names of the plugins that must be initialized before this one.
  ///
  /// [PluginRegistry] resolves these into an initialization order, and refuses
  /// to start when they form a cycle or name a plugin nobody registered.
  List<String> get dependencies => const [];

  /// Plugin state
  PluginState get state;

  /// Initialize the plugin
  /// Called once when app starts, before other plugins
  Future<void> initialize(PluginContext context);

  /// Dispose the plugin
  /// Called when app shuts down
  Future<void> dispose();

  /// Get all services provided by this plugin
  List<String> get providedServices => [];

  /// Optional: Register routes for this plugin
  void registerRoutes(NavigationAppBuilder router) {}

  /// Optional: Register event handlers
  void registerEventHandlers(NativeUIRenderer renderer) {}

  /// Optional: Get configuration schema for validation
  Map<String, dynamic>? getConfigSchema() => null;
}

/// Abstract plugin implementation with lifecycle
abstract class BasePlugin extends Plugin {
  PluginState _state = PluginState.uninitialized;

  @override
  PluginState get state => _state;

  @override
  String? get description => null;

  late PluginContext _context;

  /// Access plugin context
  PluginContext get context => _context;

  @override
  Future<void> initialize(PluginContext context) async {
    if (_state != PluginState.uninitialized) {
      throw StateError('Plugin $name is already initialized');
    }

    try {
      _state = PluginState.initializing;
      _context = context;

      // Call subclass initialization
      await onInitialize(context);

      _state = PluginState.initialized;
    } catch (e) {
      _state = PluginState.error;
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_state == PluginState.disposed) return;

    try {
      _state = PluginState.disposing;

      // Call subclass disposal
      await onDispose();

      _state = PluginState.disposed;
    } catch (e) {
      _state = PluginState.error;
      rethrow;
    }
  }

  /// Override this to implement plugin initialization
  Future<void> onInitialize(PluginContext context);

  /// Override this to implement plugin cleanup
  Future<void> onDispose();
}

/// Plugin configuration validation
class PluginConfig {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? schema;

  PluginConfig({required this.data, this.schema});

  /// Validate configuration against schema
  bool isValid() {
    if (schema == null) return true;

    for (final key in schema!.keys) {
      if (!data.containsKey(key)) {
        return false;
      }
    }

    return true;
  }

  /// Get value with type casting
  T? get<T>(String key) {
    final value = data[key];
    return value is T ? value : null;
  }

  /// Check if key exists
  bool has(String key) => data.containsKey(key);
}

/// Plugin dependency graph resolver
class PluginDependencyResolver {
  final Map<String, Plugin> _plugins = {};
  final Map<String, List<String>> _dependencies = {};

  /// Add plugin to resolver
  void add(Plugin plugin) {
    _plugins[plugin.name] = plugin;
  }

  /// Set dependencies for plugin
  void setDependencies(String pluginName, List<String> deps) {
    _dependencies[pluginName] = deps;
  }

  /// Resolve plugin order (topological sort)
  List<Plugin> resolve() {
    final resolved = <Plugin>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String name) {
      if (visited.contains(name)) return;
      if (visiting.contains(name)) {
        throw CircularDependencyError(name);
      }

      visiting.add(name);

      // Visit dependencies first
      final deps = _dependencies[name] ?? [];
      for (final dep in deps) {
        if (!_plugins.containsKey(dep)) {
          throw PluginNotFoundError(dep);
        }
        visit(dep);
      }

      visiting.remove(name);
      visited.add(name);

      final plugin = _plugins[name];
      if (plugin != null) {
        resolved.add(plugin);
      }
    }

    // Visit all plugins
    for (final name in _plugins.keys) {
      visit(name);
    }

    return resolved;
  }
}

/// Exception: Circular dependency detected
class CircularDependencyError extends Error {
  final String pluginName;

  CircularDependencyError(this.pluginName);

  @override
  String toString() => 'Circular dependency detected in plugin: $pluginName';
}

/// Exception: Plugin not found
class PluginNotFoundError extends Error {
  final String pluginName;

  PluginNotFoundError(this.pluginName);

  @override
  String toString() => 'Plugin not found: $pluginName';
}

/// Exception: Plugin initialization failed
class PluginInitializationError extends Error {
  final String pluginName;
  final dynamic error;
  final StackTrace stackTrace;

  PluginInitializationError(this.pluginName, this.error, this.stackTrace);

  @override
  String toString() =>
      'Plugin $pluginName failed to initialize: $error\n$stackTrace';
}

/// Plugin registry and manager
class PluginRegistry {
  static final PluginRegistry _instance = PluginRegistry._internal();

  final List<Plugin> _plugins = [];
  final Map<String, Plugin> _pluginsByName = {};
  final PluginContext _context = PluginContext();
  bool _initialized = false;

  factory PluginRegistry() {
    return _instance;
  }

  PluginRegistry._internal();

  /// Get singleton instance
  static PluginRegistry get instance => _instance;

  /// Register a plugin
  void register(Plugin plugin) {
    if (_initialized) {
      throw StateError('Cannot register plugins after initialization');
    }

    if (_pluginsByName.containsKey(plugin.name)) {
      throw StateError('Plugin ${plugin.name} is already registered');
    }

    _plugins.add(plugin);
    _pluginsByName[plugin.name] = plugin;
  }

  /// Register multiple plugins
  void registerAll(List<Plugin> plugins) {
    for (final plugin in plugins) {
      register(plugin);
    }
  }

  /// Initialize all registered plugins
  Future<void> initialize() async {
    if (_initialized) return;

    // Resolve dependencies
    final resolver = PluginDependencyResolver();
    for (final plugin in _plugins) {
      resolver.add(plugin);
      _context.dependsOn(plugin.name);
    }
    // Declared dependencies decide the order; without this they were
    // collected and then ignored.
    for (final plugin in _plugins) {
      if (plugin.dependencies.isNotEmpty) {
        resolver.setDependencies(plugin.name, plugin.dependencies);
      }
    }

    final orderedPlugins = resolver.resolve();

    // Initialize in order
    for (final plugin in orderedPlugins) {
      try {
        await plugin.initialize(_context);
      } catch (e, st) {
        throw PluginInitializationError(plugin.name, e, st);
      }
    }

    _initialized = true;
  }

  /// Dispose all plugins (in reverse order)
  Future<void> dispose() async {
    if (!_initialized) return;

    final orderedPlugins = _plugins.reversed.toList();
    for (final plugin in orderedPlugins) {
      await plugin.dispose();
    }

    _initialized = false;
  }

  /// Get plugin by name
  Plugin? getPlugin(String name) => _pluginsByName[name];

  /// Get service by name
  T? getService<T>(String name) => _context.getService<T>(name);

  /// Get all registered plugins
  List<Plugin> get plugins => List.unmodifiable(_plugins);

  /// Check if initialized
  bool get initialized => _initialized;

  /// Get plugin context
  PluginContext get context => _context;

  /// Clear all plugins (for testing)
  void clear() {
    _plugins.clear();
    _pluginsByName.clear();
    _initialized = false;
  }
}

/// Convenience function to get plugin registry
PluginRegistry getPluginRegistry() => PluginRegistry.instance;

/// Convenience function to get service
T? getPluginService<T>(String name) =>
    PluginRegistry.instance.getService<T>(name);
