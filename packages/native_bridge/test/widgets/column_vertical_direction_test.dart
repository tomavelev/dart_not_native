// `verticalDirection: VerticalDirection.up` reverses a Column's main axis:
// the children, and with them which end `start` is.
import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

WidgetNode _column(Widget widget) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  WidgetNode? find(WidgetNode node) {
    if (node.type == 'Column') return node;
    for (final child in node.children ?? const <WidgetNode>[]) {
      final found = find(child);
      if (found != null) return found;
    }
    return null;
  }

  return find(renderer.tree!)!;
}

List<Object?> _texts(WidgetNode column) =>
    [for (final child in column.children!) child.props['content']];

void main() {
  test('up from start stacks from the bottom', () {
    final column = _column(
      const SizedBox(
        height: 100,
        child: Column(
          verticalDirection: VerticalDirection.up,
          children: [Text('first'), Text('second')],
        ),
      ),
    );
    expect(_texts(column), ['second', 'first']);
    expect(column.props['mainAxisAlignment'], 'end');
  });

  test('up from end stacks from the top', () {
    final column = _column(
      const Column(
        verticalDirection: VerticalDirection.up,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [Text('first'), Text('second')],
      ),
    );
    expect(_texts(column), ['second', 'first']);
    expect(column.props['mainAxisAlignment'] ?? 'start', 'start');
  });

  test('down is left as it was', () {
    final column = _column(
      const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [Text('first'), Text('second')],
      ),
    );
    expect(_texts(column), ['first', 'second']);
    expect(column.props['mainAxisAlignment'], 'center');
  });
}
