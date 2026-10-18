/// What is built from where a scroller is - a header that shrinks, a title
/// that fades in - carries a table of its props against the offset
/// (`scrollLink`), which a renderer applies from its own scroll callback, so
/// it moves in step with the finger rather than with the reports.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends StatefulWidget {
  const _Page({this.builder = false});
  final bool builder;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (!widget.builder) controller.addListener(() => setState(() {}));
  }

  Widget header(double offset) => Opacity(
    opacity: (offset / 100).clamp(0.0, 1.0),
    child: Container(
      height: (120 - offset).clamp(56.0, 120.0),
      color: const Color(0xFF2196F3),
      child: const Text('title'),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        if (widget.builder)
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) =>
                header(controller.hasClients ? controller.offset : 0),
          )
        else
          header(controller.hasClients ? controller.offset : 0),
        Expanded(
          child: ListView(
            controller: controller,
            children: [for (var i = 0; i < 50; i++) Text('row $i')],
          ),
        ),
      ],
    ),
  );
}

void main() {
  Future<AppTester> scrolled(Widget page) async {
    final app = AppTester.widget(MaterialApp(home: page));
    final scroll = app.nodes.firstWhere((n) => n.props['scrollEventId'] != null);
    await app.emit(scroll.props['scrollEventId'] as String, {
      'offset': 30.0,
      'maxExtent': 2000.0,
      'viewport': 600.0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return app;
  }

  for (final builder in [false, true]) {
    final how = builder ? 'an AnimatedBuilder' : 'setState from a listener';
    test('built from the offset through $how, the boxes carry a table', () async {
      final app = await scrolled(_Page(builder: builder));
      final scroll = app.nodes.firstWhere((n) => n.props['scrollEventId'] != null);
      final source = scroll.props['scrollLinkSource'];
      expect(source, isA<String>());

      final links = [
        for (final n in app.nodes)
          if (n.props['scrollLink'] != null) n.props['scrollLink'] as Map,
      ];
      final faded = links.firstWhere((l) => l.containsKey('opacity'));
      final shrunk = links.firstWhere((l) => l.containsKey('height'));
      expect(faded['source'], source);
      final at = (faded['at'] as List).cast<double>();
      expect(at.first, 0);
      final opacity = (faded['opacity'] as List).cast<double>();
      for (var i = 0; i < at.length; i++) {
        expect(opacity[i], closeTo((at[i] / 100).clamp(0, 1), 1e-9));
      }
      final height = (shrunk['height'] as List).cast<double>();
      expect(height.first, 120);
      expect(height.last, 56);
      // The bend where it stops shrinking, at 64, is a stop of its own.
      final heightAt = (shrunk['at'] as List).cast<double>();
      double between(double offset) {
        for (var i = 1; i < heightAt.length; i++) {
          if (offset <= heightAt[i]) {
            final t = (offset - heightAt[i - 1]) / (heightAt[i] - heightAt[i - 1]);
            return height[i - 1] + (height[i] - height[i - 1]) * t;
          }
        }
        return height.last;
      }
      for (final offset in [10.0, 50.0, 64.0, 70.0, 90.0, 200.0]) {
        expect(between(offset), closeTo((120 - offset).clamp(56, 120), 1),
            reason: 'at $offset');
      }
      // The tree itself is drawn where the scroller is now.
      final box = app.nodes.firstWhere(
        (n) => (n.props['scrollLink'] as Map?)?.containsKey('height') ?? false,
      );
      expect(box.props['height'], 90);
    });
  }

  test('a colour that changes with the offset goes stop to stop', () async {
    final controller = ScrollController();
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AnimatedBuilder(
                animation: controller,
                builder: (_, _) => Container(
                  height: 40,
                  color: Color.lerp(
                    const Color(0xFFFFFFFF),
                    const Color(0xFF000000),
                    ((controller.hasClients ? controller.offset : 0) / 100)
                        .clamp(0.0, 1.0),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [for (var i = 0; i < 50; i++) Text('$i')],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final scroll = app.nodes.firstWhere((n) => n.props['scrollEventId'] != null);
    await app.emit(scroll.props['scrollEventId'] as String, {
      'offset': 10.0,
      'maxExtent': 2000.0,
      'viewport': 600.0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final link = app.nodes
        .map((n) => n.props['scrollLink'])
        .whereType<Map>()
        .firstWhere((l) => l.containsKey('color'));
    final colors = (link['color'] as List).cast<String>();
    expect(colors.first, '#ffffffff');
    expect(colors.last, '#ff000000');
  });

  test('a page that does not read the offset carries no table', () async {
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [for (var i = 0; i < 50; i++) Text('$i')]),
        ),
      ),
    );
    final scroll = app.nodes.firstWhere((n) => n.props['scrollEventId'] != null);
    await app.emit(scroll.props['scrollEventId'] as String, {
      'offset': 30.0,
      'maxExtent': 2000.0,
      'viewport': 600.0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(app.nodes.where((n) => n.props['scrollLink'] != null), isEmpty);
    final again = app.nodes.firstWhere((n) => n.type == 'Scroll' || n.type == 'LazyList');
    expect(again.props['scrollLinkSource'], isNull);
  });

  test('a button in what is built still answers its own handler', () async {
    var taps = 0;
    final controller = ScrollController();
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AnimatedBuilder(
                animation: controller,
                builder: (_, _) => Opacity(
                  opacity: controller.hasClients
                      ? (controller.offset / 100).clamp(0.0, 1.0)
                      : 0,
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('tap'),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [for (var i = 0; i < 50; i++) Text('$i')],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    WidgetNode scroll() =>
        app.nodes.firstWhere((n) => n.props['scrollEventId'] != null);
    await app.emit(scroll().props['scrollEventId'] as String, {
      'offset': 50.0,
      'maxExtent': 2000.0,
      'viewport': 600.0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final button = app.nodes.firstWhere((n) => n.props['label'] == 'tap');
    await app.tapEvent(button.props['eventId'] as String);
    expect(taps, 1);
  });
}
