// A box that only listens for touches is the size of its child in Flutter, so
// one around a child that fills has to fill too - otherwise the tap target is
// whatever the content happens to hug.
import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<WidgetNode> _walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _walk(child);
  }
}

WidgetNode _tapBox(Widget widget, String key) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  return _walk(renderer.tree!).firstWhere((n) => n.props.containsKey(key));
}

class _Nothing extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_Nothing oldDelegate) => false;
}

void main() {
  test('an InkWell around a filling box fills', () {
    final box = _tapBox(
      InkWell(onTap: () {}, child: const SizedBox.expand(child: Text('x'))),
      'tapEventId',
    );
    expect(box.props['expand'], 'both');
  });

  test('a GestureDetector around a filling CustomPaint fills', () {
    final box = _tapBox(
      GestureDetector(
        onTap: () {},
        child: CustomPaint(
          painter: _Nothing(),
          child: const SizedBox.expand(),
        ),
      ),
      'tapEventId',
    );
    expect(box.props['expand'], 'both');
    expect(box.children!.single.type, 'Canvas');
  });

  test('a tap box around a child with a size of its own still hugs it', () {
    final ink = _tapBox(
      InkWell(onTap: () {}, child: const SizedBox(width: 40, height: 40)),
      'tapEventId',
    );
    expect(ink.props.containsKey('expand'), isFalse);
    final wide = _tapBox(
      GestureDetector(
        onTap: () {},
        child: const SizedBox(width: double.infinity, child: Text('x')),
      ),
      'tapEventId',
    );
    expect(wide.props['expand'], 'width');
  });
}
