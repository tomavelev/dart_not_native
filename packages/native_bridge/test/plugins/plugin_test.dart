/// Unit tests for the plugin system: context, lifecycle, dependency order
/// and the registry.
library;

import 'package:dart_not_native/plugins/plugin.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records its lifecycle so tests can assert on ordering.
class _RecordingPlugin extends BasePlugin {
  _RecordingPlugin(this.name, {this.log, this.failOnInit = false});

  @override
  final String name;

  final List<String>? log;
  final bool failOnInit;

  @override
  String get version => '1.0.0';

  @override
  String? get description => 'Test plugin $name';

  @override
  List<String> get providedServices => ['$name.service'];

  @override
  Future<void> onInitialize(PluginContext context) async {
    if (failOnInit) throw StateError('boom');
    log?.add('init:$name');
    context.registerService('$name.service', '$name-impl');
  }

  @override
  Future<void> onDispose() async => log?.add('dispose:$name');
}

void main() {
  // The registry is a process-wide singleton.
  setUp(() => PluginRegistry.instance.clear());
  tearDown(() => PluginRegistry.instance.clear());

  group('PluginContext', () {
    test('stores and type-checks services', () {
      final context = PluginContext()..registerService<String>('greeter', 'hi');

      expect(context.getService<String>('greeter'), 'hi');
      expect(
        context.getService<int>('greeter'),
        isNull,
        reason: 'a wrong type reads as absent rather than crashing',
      );
      expect(context.getService<String>('missing'), isNull);
      expect(context.hasService('greeter'), isTrue);
      expect(context.serviceNames, ['greeter']);
      expect(context.allServices, {'greeter': 'hi'});
    });

    test('stores and type-checks configuration', () {
      final context = PluginContext()
        ..setConfig('retries', 3)
        ..setConfig('url', 'https://example.com');

      expect(context.getConfig<int>('retries'), 3);
      expect(context.getConfig<int>('url'), isNull);
      expect(context.getConfig<String>('missing'), isNull);
    });

    test('records declared dependencies', () {
      final context = PluginContext()
        ..dependsOn('storage')
        ..dependsOn('analytics');

      expect(context.dependencies, ['storage', 'analytics']);
    });
  });

  group('BasePlugin lifecycle', () {
    test('walks uninitialized to initialized to disposed', () async {
      final plugin = _RecordingPlugin('a');
      expect(plugin.state, PluginState.uninitialized);

      await plugin.initialize(PluginContext());
      expect(plugin.state, PluginState.initialized);

      await plugin.dispose();
      expect(plugin.state, PluginState.disposed);
    });

    test('exposes its context and registered services', () async {
      final plugin = _RecordingPlugin('a');
      final context = PluginContext();

      await plugin.initialize(context);

      expect(plugin.context, same(context));
      expect(context.getService<String>('a.service'), 'a-impl');
      expect(plugin.providedServices, ['a.service']);
    });

    test('initializing twice is rejected', () async {
      final plugin = _RecordingPlugin('a');
      await plugin.initialize(PluginContext());

      expect(plugin.initialize(PluginContext()), throwsStateError);
    });

    test('a failed initialization leaves the plugin in error state', () async {
      final plugin = _RecordingPlugin('bad', failOnInit: true);

      await expectLater(plugin.initialize(PluginContext()), throwsStateError);

      expect(plugin.state, PluginState.error);
    });

    test('disposing twice is harmless', () async {
      final log = <String>[];
      final plugin = _RecordingPlugin('a', log: log);
      await plugin.initialize(PluginContext());

      await plugin.dispose();
      await plugin.dispose();

      expect(log.where((e) => e.startsWith('dispose')), hasLength(1));
    });
  });

  group('PluginDependencyResolver', () {
    test('orders dependencies before their dependents', () {
      final resolver = PluginDependencyResolver()
        ..add(_RecordingPlugin('ui'))
        ..add(_RecordingPlugin('storage'))
        ..setDependencies('ui', ['storage']);

      expect(resolver.resolve().map((p) => p.name), ['storage', 'ui']);
    });

    test('resolves a chain transitively', () {
      final resolver = PluginDependencyResolver()
        ..add(_RecordingPlugin('c'))
        ..add(_RecordingPlugin('b'))
        ..add(_RecordingPlugin('a'))
        ..setDependencies('c', ['b'])
        ..setDependencies('b', ['a']);

      expect(resolver.resolve().map((p) => p.name), ['a', 'b', 'c']);
    });

    test('rejects a dependency cycle', () {
      final resolver = PluginDependencyResolver()
        ..add(_RecordingPlugin('a'))
        ..add(_RecordingPlugin('b'))
        ..setDependencies('a', ['b'])
        ..setDependencies('b', ['a']);

      expect(resolver.resolve, throwsA(isA<CircularDependencyError>()));
    });

    test('rejects a dependency that was never registered', () {
      final resolver = PluginDependencyResolver()
        ..add(_RecordingPlugin('a'))
        ..setDependencies('a', ['ghost']);

      expect(resolver.resolve, throwsA(isA<PluginNotFoundError>()));
    });

    test('errors read clearly', () {
      expect(CircularDependencyError('a').toString(), contains('a'));
      expect(PluginNotFoundError('ghost').toString(), contains('ghost'));
    });
  });

  group('PluginRegistry', () {
    test('registers and looks plugins up by name', () {
      final plugin = _RecordingPlugin('a');
      PluginRegistry.instance.register(plugin);

      expect(PluginRegistry.instance.getPlugin('a'), same(plugin));
      expect(PluginRegistry.instance.getPlugin('nope'), isNull);
      expect(PluginRegistry.instance.plugins, [plugin]);
    });

    test('refuses a duplicate name', () {
      PluginRegistry.instance.register(_RecordingPlugin('a'));

      expect(
        () => PluginRegistry.instance.register(_RecordingPlugin('a')),
        throwsStateError,
      );
    });

    test('initializes every plugin and publishes their services', () async {
      final log = <String>[];
      PluginRegistry.instance.registerAll([
        _RecordingPlugin('a', log: log),
        _RecordingPlugin('b', log: log),
      ]);

      await PluginRegistry.instance.initialize();

      expect(PluginRegistry.instance.initialized, isTrue);
      expect(log, ['init:a', 'init:b']);
      expect(getPluginService<String>('a.service'), 'a-impl');
    });

    test('refuses registration after initialization', () async {
      await PluginRegistry.instance.initialize();

      expect(
        () => PluginRegistry.instance.register(_RecordingPlugin('late')),
        throwsStateError,
      );
    });

    test('initializing twice is a no-op', () async {
      final log = <String>[];
      PluginRegistry.instance.register(_RecordingPlugin('a', log: log));

      await PluginRegistry.instance.initialize();
      await PluginRegistry.instance.initialize();

      expect(log, ['init:a']);
    });

    test('a failing plugin aborts startup with a named error', () async {
      PluginRegistry.instance.registerAll([
        _RecordingPlugin('ok'),
        _RecordingPlugin('bad', failOnInit: true),
      ]);

      await expectLater(
        PluginRegistry.instance.initialize(),
        throwsA(
          isA<PluginInitializationError>().having(
            (e) => e.pluginName,
            'pluginName',
            'bad',
          ),
        ),
      );
    });

    test('disposes in reverse registration order', () async {
      final log = <String>[];
      PluginRegistry.instance.registerAll([
        _RecordingPlugin('a', log: log),
        _RecordingPlugin('b', log: log),
      ]);
      await PluginRegistry.instance.initialize();

      await PluginRegistry.instance.dispose();

      expect(log.sublist(2), ['dispose:b', 'dispose:a']);
      expect(PluginRegistry.instance.initialized, isFalse);
    });

    test('disposing before initialization is a no-op', () async {
      final log = <String>[];
      PluginRegistry.instance.register(_RecordingPlugin('a', log: log));

      await PluginRegistry.instance.dispose();

      expect(log, isEmpty);
    });

    test('getPluginRegistry returns the singleton', () {
      expect(identical(getPluginRegistry(), PluginRegistry.instance), isTrue);
    });
  });

  group('PluginConfig', () {
    test('without a schema everything is valid', () {
      expect(PluginConfig(data: {'a': 1}).isValid(), isTrue);
    });

    test('a schema requires every declared key', () {
      final schema = {'url': 'string', 'retries': 'int'};

      expect(
        PluginConfig(
          data: {'url': 'x', 'retries': 3},
          schema: schema,
        ).isValid(),
        isTrue,
      );
      expect(
        PluginConfig(data: {'url': 'x'}, schema: schema).isValid(),
        isFalse,
      );
    });

    test('reads values with type checking', () {
      final config = PluginConfig(data: {'retries': 3, 'url': 'x'});

      expect(config.get<int>('retries'), 3);
      expect(config.get<String>('retries'), isNull);
      expect(config.has('url'), isTrue);
      expect(config.has('nope'), isFalse);
    });
  });
}
