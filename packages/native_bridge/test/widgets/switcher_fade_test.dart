/// `AnimatedSwitcher` and `AnimatedCrossFade`: the old child fades out under
/// the new one, which fades in.
library;

import 'dart:async';

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({super.key, required this.builder});
  final Widget Function(int value) builder;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int value = 0;
  void set(int next) => setState(() => value = next);
  @override
  Widget build(BuildContext context) => Scaffold(body: widget.builder(value));
}

class _Counter extends StatefulWidget {
  const _Counter({required this.name});
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

/// A counter with no key of its own, under a widget that has one.
class _Wrapped extends StatelessWidget {
  const _Wrapped({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => _Counter(name: name);
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('${widget.name} $taps'),
  );
}

void main() {
  const quick = Duration(milliseconds: 60);
  late AppTester tester;
  late GlobalKey<_HostState> host;

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  AppTester mount(Widget Function(int value) builder) {
    host = GlobalKey<_HostState>();
    return AppTester.widget(_Host(key: host, builder: builder));
  }

  List<double> fades() => [
    for (final node in tester.ofType('AnimatedOpacity'))
      (node.props['opacity'] as num).toDouble(),
  ];

  List<Object?> labels() => [
    for (final node in tester.ofType('Button')) node.props['label'],
  ];

  Widget switcher(int value) => AnimatedSwitcher(
    duration: quick,
    child: Text('page $value', key: ValueKey(value)),
  );

  group('AnimatedSwitcher', () {
    test('the first child is shown as it is', () {
      tester = mount(switcher);

      expect(tester.hasText('page 0'), isTrue);
      expect(fades(), isEmpty);
    });

    test('a new child starts unseen over the old one', () async {
      tester = mount(switcher);

      host.currentState!.set(1);

      expect(tester.hasText('page 0'), isTrue);
      expect(tester.hasText('page 1'), isTrue);
      expect(fades(), [1, 0], reason: 'old first, at the back');
      await wait(200);
    });

    test('then the two cross', () async {
      tester = mount(switcher);

      host.currentState!.set(1);
      await wait(45);

      expect(fades(), [0, 1]);
      expect(
        tester.ofType('AnimatedOpacity').first.props['durationMs'],
        quick.inMilliseconds,
      );
      await wait(200);
    });

    test('and the old one goes', () async {
      tester = mount(switcher);

      host.currentState!.set(1);
      await wait(200);

      expect(tester.hasText('page 0'), isFalse);
      expect(tester.hasText('page 1'), isTrue);
      expect(tester.ofType('Stack'), isEmpty);
      expect(fades(), [1], reason: 'the new child does not fade in twice');
    });

    test('the same type and key is the same child', () {
      tester = mount(
        (value) => AnimatedSwitcher(duration: quick, child: Text('n $value')),
      );

      host.currentState!.set(1);

      expect(tester.hasText('n 1'), isTrue);
      expect(tester.hasText('n 0'), isFalse);
      expect(fades(), isEmpty);
    });

    test('a child keeps its state while the old one leaves', () async {
      tester = mount(
        (value) => AnimatedSwitcher(
          duration: quick,
          child: _Wrapped(key: ValueKey(value), name: 'c$value'),
        ),
      );

      host.currentState!.set(1);
      expect(labels(), ['c0 0', 'c1 0']);
      await tester.tapEvent(
        tester.ofType('Button').last.props['eventId'] as String,
      );
      expect(labels().last, 'c1 1');
      await wait(200);

      expect(labels(), ['c1 1'], reason: 'the stack went away, not the state');
    });

    test('no duration, no fade', () {
      tester = mount(
        (value) => AnimatedSwitcher(
          duration: Duration.zero,
          child: Text('page $value', key: ValueKey(value)),
        ),
      );

      host.currentState!.set(1);

      expect(tester.hasText('page 0'), isFalse);
      expect(fades(), isEmpty);
    });

    test('a transition builder wraps what fades', () {
      tester = mount(
        (value) => AnimatedSwitcher(
          duration: quick,
          transitionBuilder: (child, animation) =>
              Padding(padding: const EdgeInsets.all(4), child: child),
          child: Text('page $value', key: ValueKey(value)),
        ),
      );

      expect(tester.ofType('Padding'), isNotEmpty);
    });

    test('a switcher taken away mid-fade leaves nothing running', () async {
      tester = mount((value) => value == 2 ? const Text('gone') : switcher(value));

      host.currentState!.set(1);
      host.currentState!.set(2);
      await wait(200);

      expect(tester.hasText('gone'), isTrue);
    });
  });

  group('AnimatedCrossFade', () {
    Widget cross(int value) => AnimatedCrossFade(
      firstChild: const Text('first'),
      secondChild: const Text('second'),
      crossFadeState: value == 0
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      duration: quick,
      reverseDuration: const Duration(milliseconds: 20),
    );

    test('shows the one it names', () {
      tester = mount(cross);

      expect(tester.hasText('first'), isTrue);
      expect(tester.hasText('second'), isFalse);
    });

    test('crosses to the other and drops the first', () async {
      tester = mount(cross);

      host.currentState!.set(1);
      expect(fades(), [1, 0]);
      await wait(45);
      expect(fades(), [0, 1]);
      await wait(200);

      expect(tester.hasText('first'), isFalse);
      expect(tester.hasText('second'), isTrue);
    });

    test('the way back takes the reverse duration', () async {
      tester = mount(cross);

      host.currentState!.set(1);
      await wait(200);
      host.currentState!.set(0);

      expect(tester.ofType('AnimatedOpacity').first.props['durationMs'], 20);
      await wait(200);
    });
  });
}
