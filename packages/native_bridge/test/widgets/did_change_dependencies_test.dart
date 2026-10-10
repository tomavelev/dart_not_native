/// `State.didChangeDependencies`, called when Flutter calls it: once to
/// begin with, and again before a build in which something the state read
/// from its context has changed.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An inherited value of the app's own, which says what counts as a change.
class Config extends InheritedWidget {
  const Config({required this.url, this.note = '', required super.child});
  final String url;

  /// Not part of what a reader is told about.
  final String note;

  static Config of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Config>()!;

  @override
  bool updateShouldNotify(Config oldWidget) => oldWidget.url != url;
}

/// One that never says: the framework's default answers for it.
class Loud extends InheritedWidget {
  const Loud({required super.child});
}

/// What the reader below did, in order.
final List<String> log = [];

class Reader extends StatefulWidget {
  const Reader({super.key, this.read = _config});
  final void Function(BuildContext context) read;

  static void _config(BuildContext context) =>
      log.add('config ${Config.of(context).url}');

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.read(context);
  }

  @override
  Widget build(BuildContext context) {
    log.add('build');
    return const Text('reader');
  }
}

/// Holds what the tests change, and rebuilds when they change it.
class Host extends StatefulWidget {
  const Host({super.key, required this.builder});
  final Widget Function(HostState host) builder;

  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  String url = 'a';
  String note = '';
  ThemeData theme = ThemeData(colorSchemeSeed: const Color(0xFF009688));
  Locale locale = const Locale('en');
  int ticks = 0;

  void change(void Function() how) => setState(how);

  @override
  Widget build(BuildContext context) => widget.builder(this);
}

void main() {
  late AppTester tester;
  final hostKey = GlobalKey<HostState>();
  HostState host() => hostKey.currentState!;

  AppTester mount(Widget Function(HostState host) builder) =>
      AppTester.widget(Host(key: hostKey, builder: builder));

  setUp(log.clear);

  group('an inherited widget of the app', () {
    setUp(() {
      tester = mount(
        (host) => Config(
          url: host.url,
          note: host.note,
          child: Scaffold(body: Reader(key: ValueKey('r${host.ticks ~/ 100}'))),
        ),
      );
    });

    test('is read once to begin with, before the first build', () {
      expect(log, ['config a', 'build']);
    });

    test('a rebuild that changes nothing does not call it again', () {
      host().change(() => host().ticks++);

      expect(log, ['config a', 'build', 'build']);
    });

    test('a change the widget says matters calls it, before the build', () {
      host().change(() => host().url = 'b');

      expect(log, ['config a', 'build', 'config b', 'build']);
    });

    test('a change it says does not matter is not a change', () {
      host().change(() => host().note = 'only a note');

      expect(log, ['config a', 'build', 'build']);
    });

    test('each change is heard once', () {
      host().change(() => host().url = 'b');
      host().change(() => host().ticks++);
      host().change(() => host().url = 'c');

      expect(log.where((line) => line.startsWith('config')), [
        'config a',
        'config b',
        'config c',
      ]);
    });

    test('a new state starts again from the beginning', () {
      host().change(() => host().ticks = 100);

      expect(log.where((line) => line.startsWith('config')), [
        'config a',
        'config a',
      ]);
    });
  });

  test('a widget that does not say is taken to have changed every time', () {
    tester = mount(
      (host) => Loud(
        child: Scaffold(
          body: Reader(
            read: (context) {
              context.dependOnInheritedWidgetOfExactType<Loud>();
              log.add('loud');
            },
          ),
        ),
      ),
    );

    host().change(() => host().ticks++);

    expect(log, ['loud', 'build', 'loud', 'build']);
  });

  test('a widget that appears above a state that looked for it is a change',
      () {
    tester = mount((host) {
      final reader = Scaffold(
        body: Reader(
          // Keyed, so it is the same state once there is a Config above it.
          key: const ValueKey('reader'),
          read: (context) => log.add(
            'config ${context.dependOnInheritedWidgetOfExactType<Config>()?.url}',
          ),
        ),
      );
      return host.ticks == 0 ? reader : Config(url: 'now', child: reader);
    });
    expect(log, ['config null', 'build']);

    host().change(() => host().ticks++);

    expect(log, ['config null', 'build', 'config now', 'build']);
  });

  test('getInheritedWidgetOfExactType is a look and not a dependency', () {
    tester = mount(
      (host) => Config(
        url: host.url,
        child: Scaffold(
          body: Reader(
            read: (context) => log.add(
              'peek ${context.getInheritedWidgetOfExactType<Config>()!.url}',
            ),
          ),
        ),
      ),
    );

    host().change(() => host().url = 'b');

    expect(log, ['peek a', 'build', 'build']);
  });

  test('what a widget below the state reads is not the state\'s dependency',
      () {
    tester = mount(
      (host) => Config(
        url: host.url,
        child: Scaffold(
          body: _Outer(),
        ),
      ),
    );
    expect(log, ['outer']);

    host().change(() => host().url = 'b');

    // The Builder under it read Config; the state itself read nothing.
    expect(log, ['outer']);
  });

  group('what the framework provides', () {
    test('Theme.of', () {
      tester = mount(
        (host) => Theme(
          data: host.theme,
          child: Scaffold(
            body: Reader(
              read: (context) => log.add(
                'theme ${Theme.of(context).colorScheme.primary == host.theme.colorScheme.primary}',
              ),
            ),
          ),
        ),
      );
      host().change(() => host().ticks++);
      expect(log, ['theme true', 'build', 'build']);

      host().change(
        () => host().theme = ThemeData(
          colorSchemeSeed: const Color(0xFFE91E63),
        ),
      );

      expect(log, ['theme true', 'build', 'build', 'theme true', 'build']);
    });

    test('Localizations.localeOf, under a MaterialApp', () {
      tester = mount(
        (host) => MaterialApp(
          locale: host.locale,
          supportedLocales: const [Locale('en'), Locale('bg')],
          home: Scaffold(
            body: Reader(
              read: (context) => log.add(
                'locale ${Localizations.localeOf(context).languageCode}',
              ),
            ),
          ),
        ),
      );
      host().change(() => host().ticks++);
      expect(log, ['locale en', 'build', 'build']);

      host().change(() => host().locale = const Locale('bg'));

      expect(log.last, 'build');
      expect(log.where((line) => line.startsWith('locale')), [
        'locale en',
        'locale bg',
      ]);
    });

    test('MediaQuery.of, when the window changes', () async {
      tester = mount(
        (host) => Scaffold(
          body: Reader(
            read: (context) => log.add(
              'width ${MediaQuery.of(context).size.width.round()}',
            ),
          ),
        ),
      );
      final first = log.first;

      await tester.emit(RendererEvents.viewport, {'width': 800, 'height': 600});

      expect(log.where((line) => line.startsWith('width')), [
        first,
        'width 800',
      ]);

      await tester.emit(RendererEvents.viewport, {'width': 800, 'height': 600});
      expect(log.where((line) => line.startsWith('width')), hasLength(2));
    });
  });
}

class _Outer extends StatefulWidget {
  @override
  State<_Outer> createState() => _OuterState();
}

class _OuterState extends State<_Outer> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    log.add('outer');
  }

  @override
  Widget build(BuildContext context) =>
      Builder(builder: (context) => Text(Config.of(context).url));
}
