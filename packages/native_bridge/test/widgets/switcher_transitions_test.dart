/// An `AnimatedSwitcher`'s `transitionBuilder` moves its child: built with
/// the animation at its start and then at its end, the transition widgets in
/// it go from the one value to the other. And the animation values a
/// builder uses - `Tween`, `CurvedAnimation` - which were not there.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
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
  void next() => setState(() => value++);
  @override
  Widget build(BuildContext context) => widget.builder(value);
}

void main() {
  Future<void> wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('Tween and CurvedAnimation', () {
    test('a tween goes between numbers, offsets and colours', () {
      expect(Tween<double>(begin: 0, end: 10).transform(0.25), 2.5);
      expect(
        Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .transform(0.5),
        const Offset(0.5, 0),
      );
      expect(
        ColorTween(
          begin: const Color(0xFF000000),
          end: const Color(0xFFFFFFFF),
        ).transform(0.5),
        const Color(0xFF808080),
      );
      expect(IntTween(begin: 0, end: 3).transform(0.5), 2);
    });

    test('animate and a curve evaluate at where the animation is', () {
      final curved = CurvedAnimation(
        parent: kAlwaysDismissedAnimation,
        curve: Curves.easeIn,
      );
      expect(curved.value, 0);
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(kAlwaysCompleteAnimation);
      expect(slide.value, Offset.zero);
      expect(
        Tween<double>(begin: 0, end: 2)
            .chain(CurveTween(curve: Curves.linear))
            .transform(0.5),
        1,
      );
    });
  });

  group('a switch', () {
    final key = GlobalKey<_HostState>();

    WidgetNode? moved(AppTester app, String text) {
      bool holds(WidgetNode n) =>
          (n.type == 'Text' && n.props['content'] == text) ||
          (n.children ?? const <WidgetNode>[]).any(holds);
      return app.nodes
          .where((n) => n.props['transform'] is Map && holds(n))
          .lastOrNull;
    }

    test('scales its new child up from nothing', () async {
      final app = AppTester.widget(
        _Host(
          key: key,
          builder: (value) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Text('n$value', key: ValueKey(value)),
          ),
        ),
      );
      key.currentState!.next();
      await wait(0);
      expect((moved(app, 'n1')!.props['transform'] as Map)['scale'], 0);

      await wait(60);
      final grown = moved(app, 'n1');
      expect((grown?.props['transform'] as Map?)?['scale'] ?? 1, 1);
      expect(
        app.nodes.any((n) => n.props['animateMs'] == 200),
        isTrue,
        reason: 'the box moves there over the switch\'s duration',
      );
    });

    test('slides it in by a tween through a curve', () async {
      final app = AppTester.widget(
        _Host(
          key: key,
          builder: (value) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: child,
            ),
            child: Text('s$value', key: ValueKey(value)),
          ),
        ),
      );
      // The slide is in widths of the child, so it waits to know one.
      for (final node in app.nodes.toList()) {
        final id = node.props['sizeEventId'];
        if (id is String) await app.emit(id, {'width': 100.0, 'height': 20.0});
      }
      key.currentState!.next();
      await wait(0);
      for (final node in app.nodes.toList()) {
        final id = node.props['sizeEventId'];
        if (id is String) await app.emit(id, {'width': 100.0, 'height': 20.0});
      }
      expect((moved(app, 's1')!.props['transform'] as Map)['dx'], 100);
      await wait(60);
      expect(moved(app, 's1')?.props['transform'], anyOf(isNull, {'dx': 0.0, 'dy': 0.0}));
    });

    test('with no builder it still fades', () async {
      final app = AppTester.widget(
        _Host(
          key: key,
          builder: (value) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text('f$value', key: ValueKey(value)),
          ),
        ),
      );
      key.currentState!.next();
      await wait(0);
      expect(
        app.ofType('AnimatedOpacity').map((n) => n.props['opacity']),
        contains(0),
      );
    });
  });
}
