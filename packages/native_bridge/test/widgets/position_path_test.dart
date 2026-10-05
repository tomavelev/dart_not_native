/// Where a keyless widget sits is spelled as a path, one step per stateful
/// widget above it. Each step must add its own length and no more: pushing a
/// widget's whole position as its step doubled the path at every level, so an
/// app thirty stateful widgets deep - a dozen providers, a router, a shell -
/// built megabyte ids, and a keyless `Draggable` wrote one into the tree.
library;

import 'package:dart_not_native/core.dart' show InMemoryRenderer, WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart' as tree;

class _Level extends StatefulWidget {
  const _Level(this.depth, this.leaf);
  final int depth;
  final Widget leaf;
  @override
  State<_Level> createState() => _LevelState();
}

class _LevelState extends State<_Level> {
  @override
  Widget build(BuildContext context) =>
      widget.depth == 0 ? widget.leaf : _Level(widget.depth - 1, widget.leaf);
}

WidgetNode _mount(Widget widget) {
  final renderer = InMemoryRenderer();
  hostApp(widget).mount(renderer);
  return renderer.tree!;
}

String _token(WidgetNode root) => tree
    .walk(root)
    .map((n) => n.props['dragData'])
    .whereType<String>()
    .single;

void main() {
  const leaf = Draggable<int>(data: 1, feedback: Text('f'), child: Text('c'));

  test('a keyless id grows by a step per level, not by doubling', () {
    final shallow = _token(_mount(const _Level(5, leaf))).length;
    final deep = _token(_mount(const _Level(35, leaf))).length;
    // Thirty more levels of a short type name: linear is a few hundred
    // characters, doubling would be a billion times the shallow one.
    expect(deep - shallow, lessThan(30 * 40));
    expect(deep, lessThan(2000));
  });

  test('siblings at the same depth still get ids of their own', () {
    final root = _mount(
      const _Level(
        8,
        Column(
          children: [
            Draggable<int>(data: 1, feedback: Text('f'), child: Text('a')),
            Draggable<int>(data: 2, feedback: Text('f'), child: Text('b')),
          ],
        ),
      ),
    );
    final tokens = tree
        .walk(root)
        .map((n) => n.props['dragData'])
        .whereType<String>()
        .toList();
    expect(tokens.length, 2);
    expect(tokens.toSet().length, 2);
  });

  test('a ListTile row is as wide as the tile, so trailing is at the edge', () {
    final root = _mount(
      const ListTile(title: Text('t'), trailing: Icon(Icons.delete)),
    );
    final row = tree.walk(root).firstWhere((n) => n.type == 'Row');
    expect(row.props['mainAxisSize'], 'max');
  });
}
