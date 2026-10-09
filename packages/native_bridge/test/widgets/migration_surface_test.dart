/// What a fourth and a fifth migrated app turned out to need: a popup menu, a
/// scaffold whose drawer opens from code, named routes that replace and
/// clear, strings loaded through a delegate, and a handful of widgets that
/// only have to be there.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

/// Mounts [widget] and answers the renderer holding its tree.
InMemoryRenderer _mount(Widget widget) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  return renderer;
}

/// Lets the futures a navigation or a load is waiting on run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Taps the first node [test] is true of, through whichever event it fires.
Future<void> _tap(InMemoryRenderer renderer, bool Function(WidgetNode) test) {
  final node = findNode(renderer.tree!, test);
  if (node == null) fail('nothing to tap');
  final eventId = node.props['eventId'] ?? node.props['tapEventId'];
  return renderer.handleEvent(eventId as String, const {});
}

/// Taps the tappable box around the Text reading [label].
Future<void> _tapText(InMemoryRenderer renderer, String label) => _tap(
  renderer,
  (n) =>
      n.props.containsKey('tapEventId') &&
      walk(n).any((c) => c.type == 'Text' && c.props['content'] == label),
);

Future<void> _tapId(InMemoryRenderer renderer, String id) =>
    _tap(renderer, (n) => n.props['id'] == id);

bool _shows(InMemoryRenderer renderer, String text) =>
    hasText(renderer.tree!, text);

void main() {
  group('PopupMenuButton', () {
    late List<String> log;

    Widget menu({int? initial, bool enabled = true}) => MaterialApp(
      home: Scaffold(
        body: PopupMenuButton<int>(
          key: const ValueKey('menu'),
          initialValue: initial,
          enabled: enabled,
          onOpened: () => log.add('opened'),
          onSelected: (value) => log.add('selected $value'),
          onCanceled: () => log.add('canceled'),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 50, child: Text('50 lines')),
            PopupMenuItem(
              value: 100,
              onTap: () => log.add('tapped 100'),
              child: const Text('100 lines'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 200,
              enabled: false,
              child: Text('200 lines'),
            ),
          ],
        ),
      ),
    );

    setUp(() => log = []);

    test('is the three dots until it is tapped', () {
      final renderer = _mount(menu());
      final button = nodeById(renderer.tree!, 'menu')!;
      expect(button.type, 'IconButton');
      expect(button.props['icon'], 'more_vert');
      expect(nodesOfType(renderer.tree!, 'Dialog'), isEmpty);
    });

    test('opens a dialog of its entries', () async {
      final renderer = _mount(menu());
      await _tapId(renderer, 'menu');
      expect(log, ['opened']);
      expect(nodesOfType(renderer.tree!, 'Dialog'), hasLength(1));
      expect(_shows(renderer, '50 lines'), isTrue);
      expect(_shows(renderer, '200 lines'), isTrue);
    });

    test('a choice closes it, calls the entry and then the menu', () async {
      final renderer = _mount(menu());
      await _tapId(renderer, 'menu');
      await _tapText(renderer, '100 lines');
      await _settle();
      expect(log, ['opened', 'tapped 100', 'selected 100']);
      expect(nodesOfType(renderer.tree!, 'Dialog'), isEmpty);
    });

    test('closing it without a choice is a cancel', () async {
      final renderer = _mount(menu());
      await _tapId(renderer, 'menu');
      final dialog = nodesOfType(renderer.tree!, 'Dialog').single;
      await renderer.handleEvent(
        dialog.props['dismissEventId'] as String,
        const {},
      );
      await _settle();
      expect(log, ['opened', 'canceled']);
    });

    test('a disabled entry takes no tap', () async {
      final renderer = _mount(menu());
      await _tapId(renderer, 'menu');
      final row = findNode(
        renderer.tree!,
        (n) =>
            n.props.containsKey('tapEventId') &&
            walk(n).any((c) => c.props['content'] == '200 lines'),
      );
      expect(row, isNull);
    });

    test('the entry for the initial value is ticked', () async {
      final renderer = _mount(menu(initial: 100));
      await _tapId(renderer, 'menu');
      final ticks = findNodes(
        renderer.tree!,
        (n) =>
            n.type == 'Icon' && n.props['codepoint'] == Icons.check.codePoint,
      );
      expect(ticks, hasLength(1));
    });

    test('a child takes the place of the dots', () async {
      final renderer = _mount(
        MaterialApp(
          home: Scaffold(
            body: PopupMenuButton<int>(
              onSelected: (value) => log.add('selected $value'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 1, child: Text('One')),
              ],
              child: const Text('Pick'),
            ),
          ),
        ),
      );
      expect(nodesOfType(renderer.tree!, 'IconButton'), isEmpty);
      await _tapText(renderer, 'Pick');
      await _tapText(renderer, 'One');
      await _settle();
      expect(log, ['selected 1']);
    });

    test('showMenu completes with the value chosen', () async {
      late BuildContext context;
      final renderer = _mount(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold(body: Text('page'));
            },
          ),
        ),
      );
      final chosen = showMenu<String>(
        context: context,
        items: const [
          PopupMenuItem(value: 'a', child: Text('Alpha')),
          PopupMenuItem(value: 'b', child: Text('Beta')),
        ],
      );
      await _settle();
      await _tapText(renderer, 'Beta');
      expect(await chosen, 'b');
    });
  });

  group('named routes', () {
    late BuildContext context;

    Widget page(String name) => Builder(
      builder: (c) {
        context = c;
        return Scaffold(body: Text('page $name'));
      },
    );

    Widget app() => MaterialApp(
      routes: {
        '/': (_) => page('root'),
        '/a': (_) => page('a'),
        '/b': (_) => page('b'),
      },
    );

    test('home is the root route of an app that also has routes', () {
      final renderer = _mount(
        MaterialApp(home: page('home'), routes: {'/a': (_) => page('a')}),
      );
      expect(_shows(renderer, 'page home'), isTrue);
    });

    test('pushReplacementNamed leaves nothing to go back to', () async {
      final renderer = _mount(app());
      Navigator.of(context).pushReplacementNamed('/a');
      await _settle();
      expect(_shows(renderer, 'page a'), isTrue);
      expect(Navigator.of(context).canPop(), isFalse);
    });

    test('pushNamedAndRemoveUntil clears the history', () async {
      final renderer = _mount(app());
      await Navigator.of(context).pushNamed('/a');
      expect(Navigator.of(context).canPop(), isTrue);
      await Navigator.of(context).pushNamedAndRemoveUntil('/b', (_) => false);
      expect(_shows(renderer, 'page b'), isTrue);
      expect(Navigator.of(context).canPop(), isFalse);
    });

    test('and stops at the route its predicate names', () async {
      final renderer = _mount(app());
      await Navigator.of(context).pushNamed('/a');
      await Navigator.of(context).pushNamed('/b');
      await Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/a', ModalRoute.withName('/'));
      expect(_shows(renderer, 'page a'), isTrue);
      Navigator.of(context).pop();
      await _settle();
      expect(_shows(renderer, 'page root'), isTrue);
      expect(Navigator.of(context).canPop(), isFalse);
    });

    test('a named route asked for from a pushed page covers it', () async {
      final renderer = _mount(app());
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page('pushed')));
      await _settle();
      expect(_shows(renderer, 'page pushed'), isTrue);
      Navigator.of(context).pushNamed('/a');
      await _settle();
      expect(_shows(renderer, 'page a'), isTrue);
      Navigator.of(context).pop();
      await _settle();
      expect(_shows(renderer, 'page pushed'), isTrue);
    });

    test('and one that replaces a pushed page takes its place', () async {
      final renderer = _mount(app());
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page('pushed')));
      await _settle();
      Navigator.of(context).pushReplacementNamed('/b');
      await _settle();
      expect(_shows(renderer, 'page b'), isTrue);
      Navigator.of(context).pop();
      await _settle();
      expect(_shows(renderer, 'page root'), isTrue);
    });

    test('the route knows its name and what it was pushed with', () async {
      _mount(app());
      expect(ModalRoute.of(context)?.settings.name, '/');
      await Navigator.of(context).pushNamed('/a', arguments: 'flag.png');
      final settings = ModalRoute.of(context)!.settings;
      expect(settings.name, '/a');
      expect(settings.arguments, 'flag.png');
    });
  });

  group('ScaffoldState', () {
    late BuildContext inside;
    final key = GlobalKey<ScaffoldState>();

    Widget screen({ValueChanged<bool>? onDrawerChanged}) => MaterialApp(
      routes: {
        '/': (_) => Scaffold(
          key: key,
          onDrawerChanged: onDrawerChanged,
          drawer: Drawer(
            child: Column(
              children: [
                DrawerHeader(child: const Text('Header')),
                const Text('Destinations'),
              ],
            ),
          ),
          body: Builder(
            builder: (c) {
              inside = c;
              return const Text('body');
            },
          ),
        ),
        '/other': (_) => const Scaffold(body: Text('other')),
      },
    );

    test('Scaffold.of opens the drawer as a sheet', () async {
      final renderer = _mount(screen());
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), isEmpty);
      Scaffold.of(inside).openDrawer();
      await _settle();
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), hasLength(1));
      expect(_shows(renderer, 'Destinations'), isTrue);
      expect(Scaffold.of(inside).isDrawerOpen, isTrue);
    });

    test('so does a GlobalKey, and closeDrawer closes it', () async {
      final changes = <bool>[];
      final renderer = _mount(screen(onDrawerChanged: changes.add));
      key.currentState!.openDrawer();
      await _settle();
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), hasLength(1));
      key.currentState!.closeDrawer();
      await _settle();
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), isEmpty);
      expect(key.currentState!.isDrawerOpen, isFalse);
      expect(changes, [true, false]);
    });

    test('opening it twice shows one', () async {
      final renderer = _mount(screen());
      Scaffold.of(inside).openDrawer();
      Scaffold.of(inside).openDrawer();
      await _settle();
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), hasLength(1));
    });

    test('a drawer does not follow the app to another page', () async {
      final renderer = _mount(screen());
      Scaffold.of(inside).openDrawer();
      await _settle();
      Navigator.of(inside).pushReplacementNamed('/other');
      await _settle();
      expect(_shows(renderer, 'other'), isTrue);
      expect(nodesOfType(renderer.tree!, 'BottomSheet'), isEmpty);
    });

    test('Scaffold.of above every scaffold says so', () {
      late BuildContext above;
      _mount(
        MaterialApp(
          home: Builder(
            builder: (c) {
              above = c;
              return const Scaffold(body: Text('body'));
            },
          ),
        ),
      );
      expect(Scaffold.maybeOf(above), isNull);
      expect(() => Scaffold.of(above), throwsStateError);
    });
  });

  group('LocalizationsDelegate', () {
    late List<String> loads;

    Widget app(ValueNotifier<Locale> locale) => ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (context, value, _) => MaterialApp(
        locale: value,
        supportedLocales: const [Locale('en'), Locale('bg')],
        // Flutter's own delegates are in an app's list too; anything that is
        // not this library's is passed over.
        localizationsDelegates: [_StringsDelegate(loads), Object()],
        home: Builder(
          builder: (context) => Scaffold(
            body: Text(
              Localizations.of<_Strings>(context, _Strings)?.hello ??
                  'not loaded',
            ),
          ),
        ),
      ),
    );

    setUp(() => loads = []);

    test('of answers null until the delegate has loaded', () async {
      final renderer = _mount(app(ValueNotifier(const Locale('en'))));
      expect(_shows(renderer, 'not loaded'), isTrue);
      await _settle();
      expect(_shows(renderer, 'hello in en'), isTrue);
      expect(loads, ['en']);
    });

    test('a change of locale loads again, once', () async {
      final locale = ValueNotifier(const Locale('en'));
      final renderer = _mount(app(locale));
      await _settle();
      locale.value = const Locale('bg');
      // The old strings stay up while the new ones load.
      expect(_shows(renderer, 'hello in en'), isTrue);
      await _settle();
      expect(_shows(renderer, 'hello in bg'), isTrue);
      expect(loads, ['en', 'bg']);
    });

    test('a locale the delegate does not support loads nothing', () async {
      final renderer = _mount(app(ValueNotifier(const Locale('de'))));
      await _settle();
      expect(_shows(renderer, 'not loaded'), isTrue);
      expect(loads, isEmpty);
    });
  });

  group('AppLifecycleListener', () {
    test('names the transitions between the states it is told', () async {
      final renderer = _mount(const MaterialApp(home: Scaffold()));
      final log = <String>[];
      final listener = AppLifecycleListener(
        onInactive: () => log.add('inactive'),
        onHide: () => log.add('hide'),
        onPause: () => log.add('pause'),
        onRestart: () => log.add('restart'),
        onShow: () => log.add('show'),
        onResume: () => log.add('resume'),
        onStateChange: (state) => log.add('-> ${state.name}'),
      );
      addTearDown(listener.dispose);

      await renderer.handleEvent(RendererEvents.lifecycle, {
        'state': 'resumed',
      });
      log.clear();
      await renderer.handleEvent(RendererEvents.lifecycle, {'state': 'paused'});
      expect(log, ['inactive', 'hide', 'pause', '-> paused']);

      log.clear();
      await renderer.handleEvent(RendererEvents.lifecycle, {
        'state': 'resumed',
      });
      expect(log, ['restart', 'show', 'resume', '-> resumed']);

      log.clear();
      listener.dispose();
      await renderer.handleEvent(RendererEvents.lifecycle, {'state': 'paused'});
      expect(log, isEmpty);
    });
  });

  group('widgets that only have to be there', () {
    test('Hero and MouseRegion draw their child as it is', () {
      final plain = _mount(const MaterialApp(home: Scaffold(body: Text('x'))));
      final wrapped = _mount(
        const MaterialApp(
          home: Scaffold(
            body: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Hero(tag: 'x', child: Text('x')),
            ),
          ),
        ),
      );
      expect(wrapped.tree!.toJson(), plain.tree!.toJson());
    });

    test('FadeTransition shows its child at the animation\'s value', () {
      final shown = _mount(
        const MaterialApp(
          home: Scaffold(
            body: FadeTransition(
              opacity: AlwaysStoppedAnimation(1),
              child: Text('x'),
            ),
          ),
        ),
      );
      expect(
        findNode(shown.tree!, (n) => n.props.containsKey('opacity')),
        isNull,
      );
      final faded = _mount(
        const MaterialApp(
          home: Scaffold(
            body: FadeTransition(
              opacity: AlwaysStoppedAnimation(0.25),
              child: Text('x'),
            ),
          ),
        ),
      );
      expect(
        findNode(faded.tree!, (n) => n.props['opacity'] == 0.25),
        isNotNull,
      );
    });

    test('estimateBrightnessForColor tells a dark fill from a light one', () {
      expect(
        ThemeData.estimateBrightnessForColor(const Color(0xFF000000)),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(const Color(0xFFFFFFFF)),
        Brightness.light,
      );
      expect(
        ThemeData.estimateBrightnessForColor(const Color(0xFF1B5E20)),
        Brightness.dark,
      );
      expect(
        ThemeData.estimateBrightnessForColor(const Color(0xFFFFEB3B)),
        Brightness.light,
      );
    });

    test(
      'a decoration\'s icon is drawn before the field, taps and all',
      () async {
        var taps = 0;
        final renderer = _mount(
          MaterialApp(
            home: Scaffold(
              body: TextField(
                decoration: InputDecoration(
                  icon: IconButton(
                    key: const ValueKey('scan'),
                    icon: const Icon(Icons.camera),
                    onPressed: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        );
        final row = findNode(
          renderer.tree!,
          (n) =>
              n.type == 'Row' &&
              n.props['mainAxisSize'] != 'min' &&
              n.children!.first.props['id'] == 'scan',
        )!;
        expect(
          walk(row.children!.last).any((n) => n.type == 'TextField'),
          isTrue,
        );
        await _tapId(renderer, 'scan');
        expect(taps, 1);
      },
    );

    test('a text field takes Flutter\'s cursor and selection parameters', () {
      final renderer = _mount(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              cursorColor: Color(0xFF00FF00),
              enableInteractiveSelection: false,
            ),
          ),
        ),
      );
      expect(nodesOfType(renderer.tree!, 'TextField'), hasLength(1));
    });
  });
}

class _Strings {
  const _Strings(this.hello);
  final String hello;
}

class _StringsDelegate extends LocalizationsDelegate<_Strings> {
  const _StringsDelegate(this.loads);
  final List<String> loads;

  @override
  bool isSupported(Locale locale) =>
      const ['en', 'bg'].contains(locale.languageCode);

  @override
  Future<_Strings> load(Locale locale) async {
    loads.add(locale.languageCode);
    return _Strings('hello in ${locale.languageCode}');
  }

  @override
  bool shouldReload(_StringsDelegate old) => false;
}
