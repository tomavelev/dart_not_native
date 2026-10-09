/// Reading direction in the widget layer: where it comes from, what it turns
/// and what it leaves alone, and how the renderers are told.
library;

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

/// The one Box in [tree] carrying [prop].
WidgetNode _boxWith(WidgetNode tree, String prop) =>
    findNode(tree, (n) => n.type == 'Box' && n.props.containsKey(prop))!;

/// A locale an app switches while it runs.
final _locale = ValueNotifier<Locale>(const Locale('en'));

class _Switching extends StatelessWidget {
  const _Switching(this.home);
  final Widget home;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
    valueListenable: _locale,
    builder: (context, locale, _) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      home: home,
    ),
  );
}

void main() {
  setUp(() => _locale.value = const Locale('en'));

  group('the direction comes from the locale', () {
    for (final code in ['ar', 'fa', 'he', 'ps', 'sd', 'ur', 'ug', 'yi', 'dv']) {
      test('$code reads right to left', () {
        late TextDirection seen;
        final renderer = _mount(
          MaterialApp(
            locale: Locale(code),
            home: Builder(
              builder: (context) {
                seen = Directionality.of(context);
                return const Text('x');
              },
            ),
          ),
        );

        expect(seen, TextDirection.rtl);
        expect(renderer.tree!.props[RootProps.textDirection], 'rtl');
      });
    }

    test('a country does not change it', () {
      final renderer = _mount(
        const MaterialApp(locale: Locale('ar', 'EG'), home: Text('x')),
      );
      expect(renderer.tree!.props[RootProps.textDirection], 'rtl');
    });

    for (final code in ['en', 'bg', 'de', 'zh', 'ja', 'hi']) {
      test('$code reads left to right, and the tree says nothing', () {
        late TextDirection seen;
        final renderer = _mount(
          MaterialApp(
            locale: Locale(code),
            home: Builder(
              builder: (context) {
                seen = Directionality.of(context);
                return const Text('x');
              },
            ),
          ),
        );

        expect(seen, TextDirection.ltr);
        expect(
          renderer.tree!.props.containsKey(RootProps.textDirection),
          isFalse,
        );
      });
    }

    test('an app with no MaterialApp reads left to right', () {
      TextDirection? maybe;
      late TextDirection seen;
      final renderer = _mount(
        Builder(
          builder: (context) {
            maybe = Directionality.maybeOf(context);
            seen = Directionality.of(context);
            return const Text('x');
          },
        ),
      );

      expect(maybe, isNull);
      expect(seen, TextDirection.ltr);
      expect(renderer.tree!.props.containsKey(RootProps.textDirection), isFalse);
    });
  });

  test('switching language while running turns the screen round', () {
    final renderer = _mount(const _Switching(Text('x')));
    expect(renderer.tree!.props.containsKey(RootProps.textDirection), isFalse);

    _locale.value = const Locale('ar');
    expect(renderer.tree!.props[RootProps.textDirection], 'rtl');

    _locale.value = const Locale('en');
    expect(renderer.tree!.props.containsKey(RootProps.textDirection), isFalse);
  });

  test('the prop is on the root even when the root is an overlay', () async {
    late BuildContext page;
    final renderer = _mount(
      MaterialApp(
        locale: const Locale('ar'),
        home: Builder(
          builder: (context) {
            page = context;
            return const Text('x');
          },
        ),
      ),
    );

    showDialog<void>(
      context: page,
      builder: (context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 9),
        child: Text('${Directionality.of(context).name} dialog'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final tree = renderer.tree!;
    expect(tree.type, 'Overlay');
    expect(tree.props[RootProps.textDirection], 'rtl');
    // A dialog is built under what the page that opened it could see, the
    // direction included.
    expect(hasText(tree, 'rtl dialog'), isTrue);
    final padding = findNode(
      tree,
      (n) => n.type == 'Padding' && n.props['paddingRight'] == 9,
    );
    expect(padding, isNotNull);
  });

  group('an explicit Directionality', () {
    test('in MaterialApp.builder overrides the locale, as in Flutter', () {
      final renderer = _mount(
        MaterialApp(
          locale: const Locale('en'),
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const Text('x'),
        ),
      );
      expect(renderer.tree!.props[RootProps.textDirection], 'rtl');
    });

    test('and can turn an Arabic app back', () {
      final renderer = _mount(
        MaterialApp(
          locale: const Locale('ar'),
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.ltr, child: child!),
          home: const Text('x'),
        ),
      );
      expect(renderer.tree!.props.containsKey(RootProps.textDirection), isFalse);
    });

    test('at the top of an app with no MaterialApp is the screen\'s', () {
      final renderer = _mount(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Text('x'),
        ),
      );
      expect(renderer.tree!.props[RootProps.textDirection], 'rtl');
    });

    test('deep in a screen turns what is below it, not the screen', () {
      final renderer = _mount(
        MaterialApp(
          locale: const Locale('en'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsetsDirectional.only(start: 7),
              child: const Row(children: [Text('a'), Text('b')]),
            ),
          ),
        ),
      );
      final tree = renderer.tree!;

      expect(tree.props.containsKey(RootProps.textDirection), isFalse);
      expect(_boxWith(tree, 'padding').props['padding'], [0, 0, 7, 0]);
      // The renderer lays the row out left to right, so a row that runs the
      // other way is sent with its children in the opposite order.
      expect(texts(tree), ['b', 'a']);
    });
  });

  group('directional values resolve against the direction', () {
    WidgetNode build(Locale locale, Widget home) =>
        _mount(MaterialApp(locale: locale, home: home)).tree!;

    const home = Column(
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: 12, end: 3),
          child: Text('padded'),
        ),
        Align(alignment: AlignmentDirectional.centerStart, child: Text('a')),
      ],
    );

    test('start is the left in English', () {
      final tree = build(const Locale('en'), home);
      final padding = nodesOfType(tree, 'Padding').single;
      expect(padding.props['paddingLeft'], 12);
      expect(padding.props['paddingRight'], 3);
      expect(_boxWith(tree, 'alignment').props['alignment'], [-1, 0]);
    });

    test('and the right in Arabic', () {
      final tree = build(const Locale('ar'), home);
      final padding = nodesOfType(tree, 'Padding').single;
      expect(padding.props['paddingLeft'], 3);
      expect(padding.props['paddingRight'], 12);
      expect(_boxWith(tree, 'alignment').props['alignment'], [1, 0]);
    });

    test('a directional border radius turns its corners', () {
      const box = DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF000000),
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(8),
          ),
        ),
        child: Text('x'),
      );
      // Top left, top right, bottom right, bottom left.
      final ltr = _boxWith(build(const Locale('en'), box), 'borderRadii');
      final rtl = _boxWith(build(const Locale('ar'), box), 'borderRadii');
      expect(ltr.props['borderRadii'], [8, 0, 0, 0]);
      expect(rtl.props['borderRadii'], [0, 8, 0, 0]);
    });

    test('Positioned.directional puts start where the direction says', () {
      Widget stack(BuildContext context) => Stack(
        children: [
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 5,
            top: 1,
            child: const Text('x'),
          ),
        ],
      );
      final ltr = build(const Locale('en'), Builder(builder: stack));
      final rtl = build(const Locale('ar'), Builder(builder: stack));
      expect(nodesOfType(ltr, 'Positioned').single.props['left'], 5);
      expect(nodesOfType(rtl, 'Positioned').single.props['right'], 5);
      expect(
        nodesOfType(rtl, 'Positioned').single.props.containsKey('left'),
        isFalse,
      );
    });

    test('TextAlign.end is the left in Arabic, and start goes unsaid', () {
      const home = Column(
        children: [
          Text('end', textAlign: TextAlign.end),
          Text('start', textAlign: TextAlign.start),
          Text('left', textAlign: TextAlign.left),
          Text('right', textAlign: TextAlign.right),
        ],
      );
      Map<String, Object?> aligns(WidgetNode tree) => {
        for (final text in nodesOfType(tree, 'Text'))
          text.props['content'] as String: text.props['textAlign'],
      };

      expect(aligns(build(const Locale('en'), home)), {
        'end': 'right',
        'start': null,
        'left': null,
        'right': 'right',
      });
      expect(aligns(build(const Locale('ar'), home)), {
        'end': 'left',
        'start': null,
        'left': 'left',
        'right': null,
      });
    });
  });

  group('what names a side stays on that side in Arabic', () {
    WidgetNode build(Widget home) =>
        _mount(MaterialApp(locale: const Locale('ar'), home: home)).tree!;

    test('EdgeInsets', () {
      final tree = build(
        const Padding(
          padding: EdgeInsets.only(left: 12, right: 3),
          child: Text('x'),
        ),
      );
      final padding = nodesOfType(tree, 'Padding').single;
      expect(padding.props['paddingLeft'], 12);
      expect(padding.props['paddingRight'], 3);
    });

    test('Alignment', () {
      final tree = build(
        const Align(alignment: Alignment.centerLeft, child: Text('x')),
      );
      expect(_boxWith(tree, 'alignment').props['alignment'], [-1, 0]);
    });

    test('Positioned(left:)', () {
      final tree = build(
        const Stack(children: [Positioned(left: 5, top: 1, child: Text('x'))]),
      );
      expect(nodesOfType(tree, 'Positioned').single.props['left'], 5);
    });

    test('a Row keeps its children in order - the renderer turns it', () {
      final tree = build(const Row(children: [Text('a'), Text('b')]));
      expect(texts(tree), ['a', 'b']);
    });
  });

  // A bare button is the scaffold's own and each renderer puts it in its end
  // corner; one wrapped in something is laid over the body by the widget
  // layer, which therefore has to pick the corner itself.
  test('a floating button laid over the body sits at the end corner', () {
    Widget screen() => Scaffold(
      body: const Text('body'),
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(2),
        child: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      ),
    );
    WidgetNode pinned(Locale locale) => findNode(
      _mount(MaterialApp(locale: locale, home: screen())).tree!,
      (n) => n.type == 'Positioned' && n.props['bottom'] == 16,
    )!;

    expect(pinned(const Locale('en')).props['right'], 16);
    expect(pinned(const Locale('ar')).props['left'], 16);
    expect(pinned(const Locale('ar')).props.containsKey('right'), isFalse);
  });
}
