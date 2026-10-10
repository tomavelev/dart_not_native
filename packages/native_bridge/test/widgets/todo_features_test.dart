/// Four things the widget layer accepted and did not do: `WillPopScope`,
/// a `KeyboardListener` that knows it is not the only one, an `Image`'s
/// frame and loading builders, and an implicit animation's `onEnd`.
library;

import 'dart:async';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late BuildContext _context;

class _Capture extends StatelessWidget {
  const _Capture({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    _context = context;
    return child;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AppTester tester;

  setUp(SystemBack.clearHandlers);
  tearDown(() {
    tester.app.unmount();
    SystemBack.clearHandlers();
  });

  group('WillPopScope', () {
    var answer = false;
    var asked = 0;

    Widget page(String name, {bool ask = true}) => WillPopScope(
      onWillPop: ask
          ? () async {
              asked++;
              return answer;
            }
          : null,
      child: _Capture(
        child: Scaffold(body: Text(name, key: const ValueKey('page'))),
      ),
    );

    Future<void> push(Widget page) async {
      unawaited(
        Navigator.of(_context).push<void>(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      );
      await settle();
    }

    setUp(() async {
      answer = false;
      asked = 0;
      tester = AppTester.widget(
        const _Capture(
          child: Scaffold(body: Text('Home', key: ValueKey('page'))),
        ),
      );
    });

    test('asks on the back gesture, and stays on a no', () async {
      await push(page('Editor'));

      expect(SystemBack.dispatch(), isTrue);
      await settle();

      expect(asked, 1);
      expect(tester.text('page'), 'Editor');
    });

    test('leaves on a yes', () async {
      await push(page('Editor'));
      answer = true;

      SystemBack.dispatch();
      await settle();

      expect(asked, 1);
      expect(tester.text('page'), 'Home');
    });

    test('asks on maybePop too', () async {
      await push(page('Editor'));

      expect(await Navigator.of(_context).maybePop(), isTrue);
      await settle();

      expect(asked, 1);
      expect(tester.text('page'), 'Editor');
    });

    test('is not asked when the app pops the page itself', () async {
      await push(page('Editor'));

      Navigator.of(_context).pop();
      await settle();

      expect(asked, 0);
      expect(tester.text('page'), 'Home');
    });

    test('with no onWillPop is not in the way', () async {
      await push(page('Editor', ask: false));

      SystemBack.dispatch();
      await settle();

      expect(tester.text('page'), 'Home');
    });
  });

  group('KeyboardListener', () {
    final heard = <String>[];

    Widget listener(String name, FocusNode node, {bool autofocus = false}) =>
        KeyboardListener(
          focusNode: node,
          autofocus: autofocus,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) heard.add(name);
          },
          child: Text(name),
        );

    Future<void> press() =>
        tester.emit(RendererEvents.key, {'key': 'a', 'down': true});

    setUp(heard.clear);

    test('alone, hears every key', () async {
      tester = AppTester.widget(Scaffold(body: listener('game', FocusNode())));

      await press();

      expect(heard, ['game']);
    });

    test('with nobody asked for focus, they all hear', () async {
      tester = AppTester.widget(
        Scaffold(
          body: Column(
            children: [
              listener('one', FocusNode()),
              listener('two', FocusNode()),
            ],
          ),
        ),
      );

      await press();

      expect(heard, ['one', 'two']);
    });

    test('the one asked for focus hears alone', () async {
      final second = FocusNode();
      tester = AppTester.widget(
        Scaffold(
          body: Column(
            children: [listener('one', FocusNode()), listener('two', second)],
          ),
        ),
      );
      second.requestFocus();
      await settle();

      await press();

      expect(heard, ['two']);
    });

    test('and the last one asked, when two were', () async {
      final first = FocusNode();
      final second = FocusNode();
      tester = AppTester.widget(
        Scaffold(
          body: Column(
            children: [listener('one', first), listener('two', second)],
          ),
        ),
      );
      second.requestFocus();
      first.requestFocus();
      await settle();

      await press();
      expect(heard, ['one']);

      heard.clear();
      first.unfocus();
      await settle();
      await press();
      expect(heard, ['two']);
    });

    test('autofocus is an ask, made once', () async {
      final other = FocusNode();
      tester = AppTester.widget(
        Scaffold(
          body: Column(
            children: [
              listener('auto', FocusNode(), autofocus: true),
              listener('other', other),
            ],
          ),
        ),
      );
      await press();
      expect(heard, ['auto']);

      heard.clear();
      other.requestFocus();
      await settle();
      await press();

      expect(heard, ['other'], reason: 'a rebuild does not take it back');
    });

    test('a dialog takes the keys from the page behind it', () async {
      tester = AppTester.widget(
        _Capture(child: Scaffold(body: listener('page', FocusNode()))),
      );
      unawaited(
        showDialog<void>(
          context: _context,
          builder: (_) => AlertDialog(content: listener('dialog', FocusNode())),
        ),
      );
      await settle();

      await press();
      expect(heard, ['dialog']);

      heard.clear();
      Navigator.of(_context).pop();
      await settle();
      await press();
      expect(heard, ['page']);
    });

    test('a dialog with no listener in it means nobody hears', () async {
      tester = AppTester.widget(
        _Capture(child: Scaffold(body: listener('page', FocusNode()))),
      );
      unawaited(
        showDialog<void>(
          context: _context,
          builder: (_) => const AlertDialog(title: Text('Sure?')),
        ),
      );
      await settle();

      await press();

      expect(heard, isEmpty);
    });
  });

  group('Image', () {
    const picture = NetworkImage('https://example.invalid/a.png');

    test('frameBuilder is called as for an image already there', () {
      final calls = <String>[];
      tester = AppTester.widget(
        Scaffold(
          body: Image(
            image: picture,
            frameBuilder: (context, child, frame, sync) {
              calls.add('$frame $sync');
              return Container(key: const ValueKey('frame'), child: child);
            },
          ),
        ),
      );

      expect(calls, ['0 true']);
      expect(tester.find('frame'), isNotNull);
      expect(tester.ofType('Image'), hasLength(1));
    });

    test('loadingBuilder is called with no progress, around the frame', () {
      final order = <String>[];
      tester = AppTester.widget(
        Scaffold(
          body: Image(
            image: picture,
            frameBuilder: (context, child, frame, sync) {
              order.add('frame');
              return child;
            },
            loadingBuilder: (context, child, progress) {
              order.add('loading $progress');
              return Container(key: const ValueKey('loaded'), child: child);
            },
          ),
        ),
      );

      expect(order, ['frame', 'loading null']);
      expect(tester.find('loaded'), isNotNull);
      expect(tester.ofType('Image'), hasLength(1));
    });

    test('with neither, the image is as it was', () {
      tester = AppTester.widget(
        const Scaffold(body: Image(image: picture, semanticLabel: 'A')),
      );

      expect(tester.ofType('Image').single.props['alt'], 'A');
    });
  });

  group('onEnd', () {
    const quick = Duration(milliseconds: 30);
    final ended = <String>[];
    final hostKey = GlobalKey<_ValueHostState>();

    Future<void> wait([int ms = 90]) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    AppTester mount(Widget Function(double value) builder) =>
        AppTester.widget(_ValueHost(key: hostKey, builder: builder));

    void set(double value) => hostKey.currentState!.set(value);

    setUp(ended.clear);

    test('the first build ends nothing', () async {
      tester = mount(
        (value) => AnimatedOpacity(
          opacity: value,
          duration: quick,
          onEnd: () => ended.add('opacity'),
        ),
      );

      await wait();

      expect(ended, isEmpty);
    });

    test('a change is ended once, after the duration', () async {
      tester = mount(
        (value) => AnimatedOpacity(
          opacity: value,
          duration: quick,
          onEnd: () => ended.add('opacity'),
        ),
      );

      set(0.5);
      expect(ended, isEmpty, reason: 'not before the time is up');
      await wait();

      expect(ended, ['opacity']);
    });

    test('a rebuild that changes nothing ends nothing', () async {
      tester = mount(
        (value) => AnimatedOpacity(
          opacity: 1,
          duration: quick,
          onEnd: () => ended.add('opacity'),
        ),
      );

      set(0.5);
      await wait();

      expect(ended, isEmpty);
    });

    test('a change on the way starts the wait again', () async {
      tester = mount(
        (value) => AnimatedOpacity(
          opacity: value,
          duration: const Duration(milliseconds: 80),
          onEnd: () => ended.add('opacity'),
        ),
      );

      set(0.5);
      await wait(40);
      set(0.2);
      await wait(60);
      expect(ended, isEmpty, reason: 'the second change is still running');
      await wait(80);

      expect(ended, ['opacity']);
    });

    test('a widget that goes away ends nothing', () async {
      tester = mount(
        (value) => value > 1.5
            ? const Text('gone')
            : AnimatedOpacity(
                opacity: value,
                duration: quick,
                onEnd: () => ended.add('opacity'),
              ),
      );

      set(0.5);
      set(2);
      await wait();

      expect(ended, isEmpty);
    });

    test('each kind of implicit animation ends', () async {
      tester = mount(
        (value) => Column(
          children: [
            AnimatedContainer(
              width: 40 + value * 10,
              height: 40,
              duration: quick,
              onEnd: () => ended.add('container'),
            ),
            AnimatedContainer(
              color: value > 0.6 ? const Color(0xFF2196F3) : null,
              duration: quick,
              onEnd: () => ended.add('colour'),
            ),
            AnimatedScale(
              scale: value,
              duration: quick,
              onEnd: () => ended.add('scale'),
            ),
            AnimatedRotation(
              turns: value,
              duration: quick,
              onEnd: () => ended.add('rotation'),
            ),
            AnimatedSlide(
              offset: Offset(value, 0),
              duration: quick,
              onEnd: () => ended.add('slide'),
            ),
            AnimatedPadding(
              padding: EdgeInsets.all(value * 8),
              duration: quick,
              onEnd: () => ended.add('padding'),
            ),
            AnimatedAlign(
              alignment: Alignment(value - 1, 0),
              duration: quick,
              onEnd: () => ended.add('align'),
            ),
          ],
        ),
      );

      set(0.5);
      await wait();

      // From 1 to 0.5 every one of them moved, the colour from blue to none.
      expect(ended.toSet(), {
        'container',
        'colour',
        'scale',
        'rotation',
        'slide',
        'padding',
        'align',
      });

      // From 0.5 to 0.4 the colour is still none: it alone has nothing to end.
      ended.clear();
      set(0.4);
      await wait();
      expect(ended, isNot(contains('colour')));
      expect(ended, contains('scale'));
    });
  });
}

class _ValueHost extends StatefulWidget {
  const _ValueHost({super.key, required this.builder});
  final Widget Function(double value) builder;

  @override
  State<_ValueHost> createState() => _ValueHostState();
}

class _ValueHostState extends State<_ValueHost> {
  double _value = 1;

  void set(double value) => setState(() => _value = value);

  @override
  Widget build(BuildContext context) => Scaffold(body: widget.builder(_value));
}
