/// The Flutter-shaped facade, family by family: the behaviours that carry
/// logic rather than a prop passed through.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart'
    show RendererEvents, SystemBack, WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

/// A counter whose count is its State, to see whether a State survived.
class _Counter extends StatefulWidget {
  const _Counter(this.name, {super.key});
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  static final List<String> log = [];

  @override
  void didUpdateWidget(_Counter oldWidget) =>
      log.add('${oldWidget.name}->${widget.name}');

  @override
  void dispose() => log.add('dispose ${widget.name}');

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${widget.name}=$count', key: ValueKey('${widget.name}_text')),
      ElevatedButton(
        key: ValueKey('${widget.name}_inc'),
        onPressed: () => setState(() => count++),
        child: const Text('+'),
      ),
    ],
  );
}

/// Rebuilds with whatever [build] returns; `rebuild` is setState from outside.
class _Host extends StatefulWidget {
  const _Host(this.build);
  final Widget Function(BuildContext context, _HostState state) build;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  static _HostState? last;
  int value = 0;
  void rebuild(VoidCallback fn) => setState(fn);
  @override
  void initState() => last = this;
  @override
  Widget build(BuildContext context) => widget.build(context, this);
}

AppTester _mount(Widget Function(BuildContext context, _HostState state) build) =>
    AppTester.mount(hostApp(_Host(build)));

extension on AppTester {
  /// Fires one of a box's own events - `tapEventId`, `sizeEventId`...
  Future<void> fire(String id, String prop, [Map<String, dynamic>? data]) =>
      emit(get(id).props[prop] as String, data ?? const {});

  WidgetNode firstOf(String type) => ofType(type).first;
}

void main() {
  setUp(() {
    _CounterState.log.clear();
    SystemBack.clearHandlers();
  });

  group('foundation', () {
    test('a State is handed its new widget, and is unmounted when it goes',
        () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: state.value < 2
              ? Builder(
                  builder: (context) {
                    return _Counter('v${state.value}');
                  },
                )
              : const Text('gone'),
        ),
      );
      await tester.tap('v0_inc');
      _HostState.last!.rebuild(() => _HostState.last!.value = 1);
      // Every rebuild of the parent makes a new widget for the same State.
      expect(_CounterState.log, ['v0->v0', 'v0->v1']);
      expect(tester.text('v1_text'), 'v1=1');

      _HostState.last!.rebuild(() => _HostState.last!.value = 2);
      expect(_CounterState.log.last, 'dispose v1');
    });

    test('mounted is false once a State has been disposed', () {
      final key = GlobalKey<_CounterState>();
      _mount(
        (context, state) => Scaffold(
          body: state.value == 0 ? _Counter('a', key: key) : const Text('x'),
        ),
      );
      final counter = key.currentState!;
      expect(counter.mounted, isTrue);
      expect(key.currentContext!.mounted, isTrue);
      final context = counter.context;

      _HostState.last!.rebuild(() => _HostState.last!.value = 1);

      expect(counter.mounted, isFalse);
      expect(context.mounted, isFalse);
      expect(key.currentState, isNull);
    });

    test('a context finds what was above it from a callback, after the build',
        () async {
      final tester = _mount(
        (context, state) => Theme(
          data: ThemeData(colorSchemeSeed: Colors.teal),
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const ValueKey('read'),
                onPressed: () => state.rebuild(
                  () => state.value = Theme.of(context).colorScheme.primary.value,
                ),
                child: const Text('read'),
              ),
            ),
          ),
        ),
      );
      await tester.tap('read');
      expect(
        _HostState.last!.value,
        ThemeData(colorSchemeSeed: Colors.teal).colorScheme.primary.value,
      );
    });

    test('a post-frame callback runs after the build that asked for it',
        () async {
      final order = <String>[];
      _mount((context, state) {
        if (state.value == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => order.add('post'));
        }
        order.add('build');
        return const Scaffold(body: Text('x'));
      });
      expect(order, ['build']);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['build', 'post']);
    });

    test('FutureBuilder waits, then shows the data', () async {
      final answer = Completer<String>();
      final tester = _mount(
        (context, state) => Scaffold(
          body: FutureBuilder<String>(
            future: answer.future,
            builder: (context, snapshot) => Text(
              snapshot.hasData
                  ? snapshot.data!
                  : snapshot.connectionState.name,
              key: const ValueKey('out'),
            ),
          ),
        ),
      );
      expect(tester.text('out'), 'waiting');
      answer.complete('done!');
      await Future<void>.delayed(Duration.zero);
      expect(tester.text('out'), 'done!');
    });

    test('MediaQuery follows the renderer\'s viewport event', () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: Text(
            '${MediaQuery.sizeOf(context).width.round()}'
            'x${MediaQuery.of(context).size.height.round()}'
            ' ${MediaQuery.of(context).padding.top.round()}'
            ' ${MediaQuery.of(context).platformBrightness.name}',
            key: const ValueKey('mq'),
          ),
        ),
      );
      expect(tester.text('mq'), '390x800 0 light');
      await tester.emit(RendererEvents.viewport, {
        'width': 1024,
        'height': 768,
        'paddingTop': 24,
        'dark': true,
      });
      expect(tester.text('mq'), '1024x768 24 dark');
    });

    test('LayoutBuilder builds against the viewport, then the size reported',
        () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: LayoutBuilder(
            key: const ValueKey('lb'),
            builder: (context, constraints) => Text(
              constraints.maxWidth > 600 ? 'wide' : 'narrow',
              key: const ValueKey('layout'),
            ),
          ),
        ),
      );
      expect(tester.text('layout'), 'narrow');
      expect(tester.get('lb').props['expand'], 'both');
      await tester.fire('lb', 'sizeEventId', {'width': 900.0, 'height': 500.0});
      expect(tester.text('layout'), 'wide');
    });

    test('LayoutBuilder in a vertical scroller fills the width only', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: LayoutBuilder(
              key: const ValueKey('lb'),
              builder: (context, constraints) => Text(
                '${constraints.maxHeight}',
                key: const ValueKey('h'),
              ),
            ),
          ),
        ),
      );
      expect(tester.get('lb').props['expand'], 'width');
      expect(tester.text('h'), 'Infinity');
    });

    test('a KeyboardListener hears the renderer\'s key events', () async {
      final heard = <String>[];
      final tester = _mount(
        (context, state) => Scaffold(
          body: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                heard.add('up');
              }
              if (event.logicalKey == LogicalKeyboardKey.keyA) {
                heard.add(event is KeyUpEvent ? 'a-up' : 'a-down');
              }
            },
            child: const Text('game'),
          ),
        ),
      );
      await tester.emit(RendererEvents.key, {'key': 'ArrowUp', 'down': true});
      await tester.emit(RendererEvents.key, {'key': 'A', 'down': true});
      await tester.emit(RendererEvents.key, {'key': 'a', 'down': false});
      expect(heard, ['up', 'a-down', 'a-up']);
    });

    test('the lifecycle event reaches a WidgetsBindingObserver', () async {
      final observer = _Lifecycle();
      WidgetsBinding.instance.addObserver(observer);
      addTearDown(() => WidgetsBinding.instance.removeObserver(observer));
      final tester = _mount((context, state) => const Scaffold(body: Text('x')));
      await tester.emit(RendererEvents.lifecycle, {'state': 'paused'});
      expect(observer.states, [AppLifecycleState.paused]);
    });

    test('TimeOfDay formats by the app\'s language', () {
      final tester = AppTester.mount(
        hostApp(
          MaterialApp(
            locale: const Locale('de'),
            home: Builder(
              builder: (context) => Scaffold(
                body: Text(
                  const TimeOfDay(hour: 15, minute: 5).format(context),
                  key: const ValueKey('time'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.text('time'), '15:05');
      const three = TimeOfDay(hour: 15, minute: 5);
      expect(three.hourOfPeriod, 3);
      expect(three.period, DayPeriod.pm);
      expect(three, const TimeOfDay(hour: 15, minute: 5));
      expect(const Locale('en', 'US').toLanguageTag(), 'en-US');
      expect(const Locale('en', 'US').toString(), 'en_US');
    });
  });

  group('painting on the wire', () {
    test('an opaque colour is #rrggbb and a translucent one #aarrggbb', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: Column(
            children: [
              Container(key: const ValueKey('solid'), color: Colors.red),
              Container(
                key: const ValueKey('faded'),
                color: Colors.black.withValues(alpha: 0.5),
              ),
              Text(
                'x',
                key: const ValueKey('ink'),
                style: TextStyle(color: Colors.white.withOpacity(0.25)),
              ),
            ],
          ),
        ),
      );
      expect(tester.get('solid').props['color'], '#f44336');
      expect(tester.get('faded').props['color'], '#80000000');
      expect(tester.get('ink').props['color'], '#40ffffff');
    });

    test('ColorScheme.fromSeed keeps the seed\'s hue and sane surfaces', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.teal);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      final hue = HSLColor.fromColor(light.primary).hue;
      expect(hue, inInclusiveRange(150, 200));
      expect(light.surface.computeLuminance(), greaterThan(0.9));
      expect(dark.surface.computeLuminance(), lessThan(0.05));
    });

    test('a border on one side is a thin box over that edge', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: Container(
            height: 40,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.blue, width: 2)),
            ),
            child: const Text('row'),
          ),
        ),
      );
      final stack = tester.firstOf('Stack');
      final edge = stack.children!.last;
      expect(edge.type, 'Positioned');
      expect(edge.props['bottom'], 0);
      expect(edge.props['height'], 2.0);
      expect(edge.children!.single.props['color'], '#2196f3');
    });

    test('a decoration becomes the box\'s paint', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: Container(
            key: const ValueKey('card'),
            width: 120,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey, width: 1),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: const Text('x'),
          ),
        ),
      );
      final props = tester.get('card').props;
      expect(props['width'], 120.0);
      expect(props['padding'], [8.0, 8.0, 8.0, 8.0]);
      expect(props['margin'], [0.0, 4.0, 0.0, 0.0]);
      expect(props['borderRadius'], 12.0);
      expect(props['borderWidth'], 1.0);
      expect(props['shadow'], containsPair('blur', 6.0));
    });

    test('Icon is an Icon node', () {
      final tester = _mount(
        (context, state) => const Scaffold(
          body: Icon(Icons.add, key: ValueKey('i'), size: 18, semanticLabel: 'Add'),
        ),
      );
      final icon = tester.get('i');
      expect(icon.type, 'Icon');
      expect(icon.props['codepoint'], Icons.add.codePoint);
      expect(icon.props['semanticLabel'], 'Add');
    });
  });

  group('theme', () {
    test('MaterialApp picks the dark theme when the device goes dark',
        () async {
      final light = ThemeData(colorSchemeSeed: Colors.teal);
      final dark = ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      );
      final tester = AppTester.mount(
        hostApp(
          MaterialApp(
            theme: light,
            darkTheme: dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Text(
                  Theme.of(context).brightness.name,
                  key: const ValueKey('b'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.text('b'), 'light');
      await tester.emit(RendererEvents.viewport, {
        'width': 390,
        'height': 800,
        'dark': true,
      });
      expect(tester.text('b'), 'dark');
      expect(light.toAppTheme(dark: dark).dark.surface, isNot('#ffffff'));
    });

    test('DefaultTextStyle reaches the text below it', () {
      final tester = _mount(
        (context, state) => const Scaffold(
          body: DefaultTextStyle(
            style: TextStyle(fontSize: 20, color: Colors.red),
            child: Text(
              'x',
              key: ValueKey('t'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
      final props = tester.get('t').props;
      expect(props['fontSize'], 20.0);
      expect(props['color'], '#f44336');
      expect(props['fontWeight'], 700);
    });

    test('Text.rich sends its runs as spans', () {
      final tester = _mount(
        (context, state) => const Scaffold(
          body: Text.rich(
            TextSpan(
              text: 'Hello ',
              children: [
                TextSpan(
                  text: 'world',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            key: ValueKey('rich'),
          ),
        ),
      );
      final props = tester.get('rich').props;
      expect(props['content'], 'Hello world');
      expect(props['spans'], [
        {'text': 'Hello '},
        {'text': 'world', 'fontWeight': 700},
      ]);
    });
  });

  group('state kept while hidden', () {
    test('IndexedStack keeps the children that are not showing', () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: Column(
            children: [
              IndexedStack(
                index: state.value,
                children: const [_Counter('a'), _Counter('b')],
              ),
              ElevatedButton(
                key: const ValueKey('flip'),
                onPressed: () => state.rebuild(() => state.value = 1 - state.value),
                child: const Text('flip'),
              ),
            ],
          ),
        ),
      );
      await tester.tap('a_inc');
      await tester.tap('a_inc');
      expect(tester.find('b_text'), isNull);

      await tester.tap('flip');
      expect(tester.text('b_text'), 'b=0');
      expect(tester.find('a_text'), isNull);

      await tester.tap('flip');
      expect(tester.text('a_text'), 'a=2');
      expect(_CounterState.log.where((e) => e.startsWith('dispose')), isEmpty);
    });

    test('a hidden child does not take a visible one\'s event', () async {
      // Both pages key their button the same; only the visible one may hear.
      var first = 0;
      var second = 0;
      final tester = _mount(
        (context, state) => Scaffold(
          body: IndexedStack(
            index: 0,
            children: [
              ElevatedButton(
                key: const ValueKey('save'),
                onPressed: () => first++,
                child: const Text('one'),
              ),
              ElevatedButton(
                key: const ValueKey('save'),
                onPressed: () => second++,
                child: const Text('two'),
              ),
            ],
          ),
        ),
      );
      await tester.tap('save');
      expect((first, second), (1, 0));
    });

    test('TabBarView shows the selected tab and keeps the others', () async {
      final tester = _mount(
        (context, state) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Tabs'),
              bottom: const TabBar(
                key: ValueKey('bar'),
                tabs: [Tab(text: 'One'), Tab(text: 'Two')],
              ),
            ),
            body: const TabBarView(children: [_Counter('one'), _Counter('two')]),
          ),
        ),
      );
      expect(tester.get('bar').props['tabs'], ['One', 'Two']);
      await tester.tap('one_inc');
      await tester.emit(tester.eventIdOf('bar'), {'index': 1});
      expect(tester.get('bar').props['selectedIndex'], 1);
      expect(tester.text('two_text'), 'two=0');
      await tester.emit(tester.eventIdOf('bar'), {'index': 0});
      expect(tester.text('one_text'), 'one=1');
    });
  });

  group('Navigator', () {
    Widget home(void Function(Object? result) onResult) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Column(
          children: [
            const _Counter('home'),
            ElevatedButton(
              key: const ValueKey('open'),
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (context) => const _Detail()),
                );
                onResult(result);
              },
              child: const Text('open'),
            ),
          ],
        ),
      ),
    );

    test('push shows the page, pop answers the future, state beneath is kept',
        () async {
      Object? result = 'unset';
      final tester = AppTester.mount(
        hostApp(MaterialApp(home: home((value) => result = value))),
      );
      await tester.tap('home_inc');
      await tester.tap('open');

      expect(tester.hasText('Detail body'), isTrue);
      expect(tester.find('home_text'), isNull);
      // A page that can be popped grows a back button.
      expect(tester.firstOf('AppBar').props['leading'], 'back');

      await tester.tap('done');
      await Future<void>.delayed(Duration.zero);
      expect(result, 'picked');
      expect(tester.text('home_text'), 'home=1');
      expect(tester.firstOf('AppBar').props.containsKey('leading'), isFalse);
    });

    test('the platform back gesture pops, with a null result', () async {
      Object? result = 'unset';
      final tester = AppTester.mount(
        hostApp(MaterialApp(home: home((value) => result = value))),
      );
      expect(SystemBack.dispatch(), isFalse);
      await tester.tap('open');
      expect(SystemBack.dispatch(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(result, isNull);
      expect(tester.hasText('Detail body'), isFalse);
      expect(SystemBack.dispatch(), isFalse);
    });

    test('pop closes a dialog before it pops a page', () async {
      final tester = AppTester.mount(
        hostApp(MaterialApp(home: home((_) {}))),
      );
      await tester.tap('open');
      await tester.tap('ask');
      expect(tester.ofType('Dialog'), hasLength(1));
      await tester.tap('no');
      expect(tester.ofType('Dialog'), isEmpty);
      expect(tester.hasText('Detail body'), isTrue);
    });

    test('popUntil goes back to the first route', () async {
      late BuildContext top;
      final tester = AppTester.mount(
        hostApp(
          MaterialApp(
            home: Builder(
              builder: (context) {
                top = context;
                return const Scaffold(body: Text('first'));
              },
            ),
          ),
        ),
      );
      final navigator = Navigator.of(top);
      for (final name in ['second', 'third']) {
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(builder: (_) => Scaffold(body: Text(name))),
          ),
        );
      }
      expect(tester.hasText('third'), isTrue);
      expect(navigator.canPop(), isTrue);
      navigator.popUntil((route) => route.isFirst);
      expect(tester.hasText('first'), isTrue);
      expect(navigator.canPop(), isFalse);
    });

    test('a pop with nothing of its own goes to the RouterConfig', () async {
      final router = _StackRouter();
      late BuildContext inner;
      final tester = AppTester.mount(
        hostApp(
          MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => child!,
          ),
        ),
      );
      router.onBuild = (context) => inner = context;
      router.push('b');
      expect(tester.hasText('page b'), isTrue);
      expect(Navigator.of(inner).canPop(), isTrue);
      Navigator.of(inner).pop('bye');
      expect(router.lastResult, 'bye');
      expect(tester.hasText('page a'), isTrue);
      expect(Navigator.of(inner).canPop(), isFalse);
    });
  });

  group('AppBar colours', () {
    // What the bar under [theme] is sent as, beside one that states [fill]
    // and [ink] outright: the two should be the same bar.
    void expectBar(
      ThemeData theme, {
      required Color Function(ColorScheme scheme) fill,
      required Color Function(ColorScheme scheme) ink,
      AppBar Function()? bar,
    }) {
      Map<String, dynamic> colours(AppBar Function(ColorScheme) make) {
        final tester = AppTester.mount(
          hostApp(
            Theme(
              data: theme,
              child: Builder(
                builder: (context) => Scaffold(
                  appBar: make(Theme.of(context).colorScheme),
                  body: const Text('x'),
                ),
              ),
            ),
          ),
        );
        final props = tester.firstOf('AppBar').props;
        return {
          'backgroundColor': props['backgroundColor'],
          'foregroundColor': props['foregroundColor'],
        };
      }

      final stated = colours(
        (scheme) => AppBar(
          title: const Text('t'),
          backgroundColor: fill(scheme),
          foregroundColor: ink(scheme),
        ),
      );
      expect(stated['backgroundColor'], isNotNull);
      expect(
        colours((_) => bar?.call() ?? AppBar(title: const Text('t'))),
        stated,
      );
    }

    test('Material 3, which is the default, is the surface', () {
      expect(ThemeData().useMaterial3, isTrue);
      expectBar(
        ThemeData(),
        fill: (scheme) => scheme.surface,
        ink: (scheme) => scheme.onSurface,
      );
      expectBar(
        ThemeData.dark(),
        fill: (scheme) => scheme.surface,
        ink: (scheme) => scheme.onSurface,
      );
    });

    test('Material 2 is the primary in a light theme, the surface in a dark',
        () {
      expectBar(
        ThemeData(useMaterial3: false),
        fill: (scheme) => scheme.primary,
        ink: (scheme) => scheme.onPrimary,
      );
      expectBar(
        ThemeData.dark(useMaterial3: false),
        fill: (scheme) => scheme.surface,
        ink: (scheme) => scheme.onSurface,
      );
    });

    test('the theme\'s appBarTheme outranks both, and the bar itself that',
        () {
      const teal = Color(0xFF008080);
      const white = Color(0xFFFFFFFF);
      const black = Color(0xFF000000);
      final themed = ThemeData(
        appBarTheme: const AppBarTheme(
          backgroundColor: teal,
          foregroundColor: white,
        ),
      );
      expectBar(themed, fill: (_) => teal, ink: (_) => white);
      expectBar(
        themed,
        fill: (_) => black,
        ink: (_) => white,
        bar: () => AppBar(title: const Text('t'), backgroundColor: black),
      );
    });
  });

  group('Scaffold', () {
    test('the body never scrolls, and a nested scaffold is composed', () {
      final tester = _mount(
        (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Shell')),
          bottomNavigationBar: NavigationBar(
            key: const ValueKey('nav'),
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
          body: Scaffold(
            body: const Text('feature'),
            floatingActionButton: FloatingActionButton(
              key: const ValueKey('fab'),
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );
      final scaffolds = tester.ofType('Scaffold');
      expect(scaffolds, hasLength(1));
      expect(scaffolds.single.props['bodyScrolls'], isFalse);
      // The inner button is laid over the inner body, not handed to the frame.
      expect(
        scaffolds.single.children!.where((n) => n.type == 'FloatingActionButton'),
        isEmpty,
      );
      expect(tester.get('fab').type, 'FloatingActionButton');
      expect(tester.ofType('Stack'), isNotEmpty);
      final bar = scaffolds.single.children!.last;
      expect(bar.type, 'BottomBar');
      expect(bar.children!.single.type, 'BottomNavigation');
      expect(tester.get('nav').props['items'], hasLength(2));
    });

    test('a non-text title travels as a subtree', () {
      final tester = _mount(
        (context, state) => Scaffold(
          appBar: AppBar(
            title: const Row(children: [Icon(Icons.star), Text('Starred')]),
            actions: [
              IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            ],
          ),
          body: const Text('x'),
        ),
      );
      final bar = tester.firstOf('AppBar');
      expect(bar.props['hasTitleNode'], isTrue);
      expect(bar.children!.first.type, 'Row');
      expect(bar.children!.last.type, 'IconButton');
    });
  });

  group('scrolling', () {
    test('ListView.builder with a row height is windowed, keyless', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: ListView.builder(
            itemCount: 10000,
            itemExtent: 48,
            itemBuilder: (context, index) => Text('Row $index'),
          ),
        ),
      );
      final list = tester.firstOf('LazyList');
      expect(list.props['itemCount'], 10000);
      expect(list.children!.length, lessThan(100));
      expect(list.props['id'], matches(RegExp(r'^\w+$')));
    });

    test('ListView.builder without one builds every row in a scroller', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: ListView.builder(
            itemCount: 40,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) => Text('Row $index'),
          ),
        ),
      );
      expect(tester.ofType('LazyList'), isEmpty);
      final scroll = tester.firstOf('Scroll');
      expect(scroll.props['padding'], [8.0, 8.0, 8.0, 8.0]);
      expect(scroll.children!.single.children, hasLength(40));
    });

    test('a list inside a scroller, or told never to scroll, is laid out', () {
      final tester = _mount(
        (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [Text('a'), Text('b')],
                ),
                ListView.builder(
                  itemCount: 3,
                  itemExtent: 20,
                  itemBuilder: (context, index) => Text('n$index'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.ofType('Scroll'), hasLength(1));
      expect(tester.ofType('LazyList'), isEmpty);
      expect(tester.hasText('n2'), isTrue);
    });

    test('RefreshIndicator hands its refresh to the scroller beneath',
        () async {
      final done = Completer<void>();
      var refreshes = 0;
      final tester = _mount(
        (context, state) => Scaffold(
          body: RefreshIndicator(
            onRefresh: () {
              refreshes++;
              return done.future;
            },
            child: ListView(children: const [Text('row')]),
          ),
        ),
      );
      WidgetNode scroll() => tester.firstOf('Scroll');
      expect(scroll().props['refreshing'], isFalse);
      await tester.emit(scroll().props['refreshEventId'] as String);
      expect(refreshes, 1);
      expect(scroll().props['refreshing'], isTrue);
      done.complete();
      await Future<void>.delayed(Duration.zero);
      expect(scroll().props['refreshing'], isFalse);
    });

    test('a ScrollController moves the scroller with a version', () {
      final controller = ScrollController();
      final tester = _mount(
        (context, state) => Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const Text('long'),
          ),
        ),
      );
      expect(controller.hasClients, isTrue);
      // Where it is, said from the start; a renderer obeys it once a version.
      expect(tester.firstOf('Scroll').props['scrollOffset'], 0.0);
      expect(tester.firstOf('Scroll').props['scrollVersion'], 0);
      controller.jumpTo(240);
      expect(tester.firstOf('Scroll').props['scrollOffset'], 240.0);
      expect(tester.firstOf('Scroll').props['scrollVersion'], 1);
    });

    test('a ScrollController follows the reader, and tells its listeners',
        () async {
      final controller = ScrollController();
      final heard = <double>[];
      controller.addListener(() => heard.add(controller.offset));
      final tester = _mount(
        (context, state) => Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Text('long ${state.value}'),
          ),
        ),
      );
      final scroll = tester.firstOf('Scroll');
      await tester.emit(scroll.props['scrollEventId'] as String, {
        'offset': 320.0,
        'maxExtent': 900.0,
        'viewport': 500.0,
      });

      expect(controller.offset, 320.0);
      expect(heard, [320.0]);
      expect(controller.position.maxScrollExtent, 900.0);
      expect(controller.position.viewportDimension, 500.0);

      // The next tree says where the scroller is, under the version it
      // already obeyed: nothing moves, and a view made again starts there.
      _HostState.last!.rebuild(() => _HostState.last!.value++);
      await Future<void>.delayed(Duration.zero);
      expect(tester.firstOf('Scroll').props['scrollOffset'], 320.0);
      expect(tester.firstOf('Scroll').props['scrollVersion'], 0);
    });

    test('a scroller under a pushed page comes back where it was', () async {
      // No controller: the position is kept for the scroller by its place.
      final tester = AppTester.mount(
        hostApp(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: SingleChildScrollView(
                  child: ElevatedButton(
                    key: const ValueKey('open'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (context) => const _Detail()),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.firstOf('Scroll');
      await tester.emit(before.props['scrollEventId'] as String, {
        'offset': 410.0,
      });
      await tester.tap('open');
      expect(tester.hasText('Detail body'), isTrue);

      await tester.tap('done');
      await Future<void>.delayed(Duration.zero);
      final after = tester.firstOf('Scroll');
      expect(after.props['scrollOffset'], 410.0);
      // A new version: "go there", for a renderer that kept the old view.
      expect(
        after.props['scrollVersion'],
        isNot(before.props['scrollVersion']),
      );
    });

    test('GridView.extent takes its columns from the width it is given',
        () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: GridView.extent(
            maxCrossAxisExtent: 200,
            children: [for (var i = 0; i < 6; i++) Text('cell $i')],
          ),
        ),
      );
      expect(tester.firstOf('GridView').props['crossAxisCount'], 2);
      final box = tester.ofType('Box').firstWhere(
        (node) => node.props.containsKey('sizeEventId'),
      );
      await tester.emit(box.props['sizeEventId'] as String, {
        'width': 1000.0,
        'height': 600.0,
      });
      expect(tester.firstOf('GridView').props['crossAxisCount'], 5);
    });
  });

  group('forms and inputs', () {
    test('Form.validate shows each field\'s error; save hands the values on',
        () async {
      final formKey = GlobalKey<FormState>();
      String? saved;
      final tester = _mount(
        (context, state) => Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                TextFormField(
                  key: const ValueKey('email'),
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      (value ?? '').contains('@') ? null : 'Not an email',
                  onSaved: (value) => saved = value,
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('plan'),
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  ],
                  validator: (value) => value == null ? 'Choose one' : null,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.get('email').props['keyboardType'], 'email');
      expect(tester.get('email').props.containsKey('error'), isFalse);

      expect(formKey.currentState!.validate(), isFalse);
      expect(tester.get('email').props['error'], 'Not an email');
      expect(tester.get('plan').props['error'], 'Choose one');

      await tester.typeInto('email', 'a@b.co');
      // The error goes as soon as the value is right.
      expect(tester.get('email').props.containsKey('error'), isFalse);
      await tester.emit(tester.eventIdOf('plan'), {'index': 1});
      expect(tester.get('plan').props['selectedIndex'], 1);

      expect(formKey.currentState!.validate(), isTrue);
      formKey.currentState!.save();
      expect(saved, 'a@b.co');

      formKey.currentState!.reset();
      expect(tester.get('email').props['initialValue'], '');
      expect(tester.get('plan').props.containsKey('selectedIndex'), isFalse);
    });

    test('DropdownButton reports the value of the item chosen', () async {
      final tester = _mount(
        (context, state) => Scaffold(
          body: DropdownButton<int>(
            key: const ValueKey('dd'),
            value: state.value,
            items: const [
              DropdownMenuItem(value: 0, child: Text('Zero')),
              DropdownMenuItem(value: 7, child: Text('Seven')),
            ],
            onChanged: (value) => state.rebuild(() => state.value = value!),
          ),
        ),
      );
      expect(tester.get('dd').props['items'], ['Zero', 'Seven']);
      expect(tester.get('dd').props['selectedIndex'], 0);
      await tester.emit(tester.eventIdOf('dd'), {'index': 1});
      expect(_HostState.last!.value, 7);
      expect(tester.get('dd').props['selectedIndex'], 1);
    });

    test('a controller is a ChangeNotifier, and clear() redraws the field',
        () async {
      final controller = TextEditingController(text: 'abc');
      var heard = 0;
      controller.addListener(() => heard++);
      final tester = _mount(
        (context, state) => Scaffold(
          body: TextField(
            key: const ValueKey('f'),
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: controller.clear,
              ),
            ),
          ),
        ),
      );
      await tester.typeInto('f', 'abcd');
      expect(controller.text, 'abcd');
      expect(heard, 1);
      expect(tester.get('f').props['prefixIcon'], Icons.search.codePoint);
      await tester.emit('${tester.eventIdOf('f')}_suffix');
      expect(tester.get('f').props['initialValue'], '');
      expect(tester.get('f').props['valueVersion'], 1);
    });

    test('showDatePicker answers with the date the platform picked',
        () async {
      DateTime? picked;
      final tester = _mount(
        (context, state) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('pick'),
            onPressed: () async {
              picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2026, 3, 4),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
            },
            child: const Text('pick'),
          ),
        ),
      );
      await tester.tap('pick');
      final picker = tester.firstOf('DatePicker');
      expect(picker.props['initial'], '2026-03-04');
      await tester.emit(picker.props['eventId'] as String, {'value': '2026-05-06'});
      await Future<void>.delayed(Duration.zero);
      expect(picked, DateTime(2026, 5, 6));
      expect(tester.ofType('DatePicker'), isEmpty);
    });
  });

  group('buttons', () {
    test('a text child is the platform button; anything else is composed',
        () async {
      var presses = 0;
      final tester = _mount(
        (context, state) => Scaffold(
          body: Column(
            children: [
              FilledButton.tonal(
                key: const ValueKey('tonal'),
                onPressed: () {},
                child: const Text('Tonal'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('outlined'),
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              ElevatedButton(
                key: const ValueKey('busy'),
                onPressed: () => presses++,
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ),
        ),
      );
      expect(tester.get('tonal').props['variant'], 'tonal');
      expect(tester.get('outlined').props['variant'], 'outlined');
      expect(tester.get('outlined').props['iconCodepoint'], Icons.add.codePoint);

      final busy = tester.get('busy');
      expect(busy.type, 'Box');
      expect(walk(busy).any((n) => n.type == 'Loading' && n.props['size'] == 16.0), isTrue);
      await tester.fire('busy', 'tapEventId');
      expect(presses, 1);
    });
  });

  group('gestures', () {
    test('a drag reaches the pan and the axis handlers', () async {
      final seen = <String>[];
      final tester = _mount(
        (context, state) => Scaffold(
          body: GestureDetector(
            key: const ValueKey('pad'),
            onTapDown: (details) => seen.add('down ${details.localPosition.dx}'),
            onTap: () => seen.add('tap'),
            onPanUpdate: (details) => seen.add('pan ${details.delta.dx}'),
            onHorizontalDragEnd: (details) =>
                seen.add('fling ${details.primaryVelocity}'),
            child: const Text('pad'),
          ),
        ),
      );
      await tester.fire('pad', 'tapEventId', {'x': 5.0, 'y': 6.0});
      final pan = tester.get('pad').props['panEventId'] as String;
      await tester.emit('${pan}_update', {'x': 9.0, 'y': 6.0, 'dx': 4.0, 'dy': 0.0});
      await tester.emit('${pan}_end', {'x': 9.0, 'y': 6.0, 'vx': 300.0, 'vy': 0.0});
      expect(seen, ['down 5.0', 'tap', 'pan 4.0', 'fling 300.0']);
    });

    test('what a Draggable carries comes out of the DragTarget as itself',
        () async {
      final payload = _Payload('card 7');
      _Payload? dropped;
      var completed = false;
      final tester = _mount(
        (context, state) => Scaffold(
          body: Column(
            children: [
              Draggable<_Payload>(
                key: const ValueKey('card'),
                data: payload,
                feedback: const Text('dragging'),
                onDragCompleted: () => completed = true,
                child: const Text('card'),
              ),
              DragTarget<_Payload>(
                key: const ValueKey('slot'),
                onWillAcceptWithDetails: (details) => details.data.name.isNotEmpty,
                onAcceptWithDetails: (details) => dropped = details.data,
                builder: (context, candidates, rejected) => Text(
                  candidates.isEmpty ? 'empty' : 'hovering',
                  key: const ValueKey('slot_text'),
                ),
              ),
            ],
          ),
        ),
      );
      final token = tester.get('card').props['dragData'] as String;
      final drop = tester.get('slot').props['dropEventId'] as String;
      await tester.emit('${drop}_hover', {'over': true});
      expect(tester.text('slot_text'), 'hovering');
      await tester.emit(drop, {'data': token});
      expect(identical(dropped, payload), isTrue);
      expect(completed, isTrue);
      expect(tester.text('slot_text'), 'empty');

      dropped = null;
      await tester.emit(drop, {'data': 'not a token'});
      expect(dropped, isNull);
    });

    test('Dismissible is a swipe action that asks, then dismisses', () async {
      final dismissed = <DismissDirection>[];
      final tester = _mount(
        (context, state) => Scaffold(
          body: Dismissible(
            key: const ValueKey('row'),
            direction: DismissDirection.endToStart,
            background: Container(color: Colors.red, child: const Text('Remove')),
            confirmDismiss: (_) async => true,
            onDismissed: dismissed.add,
            child: const Text('row'),
          ),
        ),
      );
      final swipe = tester.get('row');
      expect(swipe.type, 'SwipeActions');
      final action = (swipe.props['actions'] as List).single as Map;
      expect(action['label'], 'Remove');
      expect(action['color'], '#f44336');
      await tester.emit(action['eventId'] as String);
      await Future<void>.delayed(Duration.zero);
      expect(dismissed, [DismissDirection.endToStart]);
    });
  });
}

class _Lifecycle with WidgetsBindingObserver {
  final List<AppLifecycleState> states = [];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

class _Payload {
  _Payload(this.name);
  final String name;
}

class _Detail extends StatelessWidget {
  const _Detail();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail')),
    body: Column(
      children: [
        const Text('Detail body'),
        ElevatedButton(
          key: const ValueKey('done'),
          onPressed: () => Navigator.pop(context, 'picked'),
          child: const Text('done'),
        ),
        ElevatedButton(
          key: const ValueKey('ask'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sure?'),
              actions: [
                TextButton(
                  key: const ValueKey('no'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('No'),
                ),
              ],
            ),
          ),
          child: const Text('ask'),
        ),
      ],
    ),
  );
}

/// A router with a page stack of its own, the way a router package has one.
class _StackRouter extends ChangeNotifier implements RouterConfig {
  final List<String> pages = ['a'];
  Object? lastResult;
  void Function(BuildContext context)? onBuild;

  void push(String page) {
    pages.add(page);
    notifyListeners();
  }

  @override
  bool canPop() => pages.length > 1;

  @override
  void pop<T extends Object?>([T? result]) {
    lastResult = result;
    pages.removeLast();
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: this,
    builder: (context, _) {
      onBuild?.call(context);
      return Scaffold(body: Text('page ${pages.last}'));
    },
  );
}
