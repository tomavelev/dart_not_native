/// Cells in a grid, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GridView.count(
          key: const ValueKey('gallery'),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 4,
          childAspectRatio: 1.5,
          children: [
            for (var i = 0; i < 7; i++)
              Text('cell $i', key: ValueKey('cell_$i')),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Gallery())));

  WidgetNode grid() => tester.ofType('GridView').single;

  test('carries its shape: columns, gaps and the cell ratio', () {
    expect(grid().props['crossAxisCount'], 3);
    // Flutter's names cross the protocol as the axis each one separates:
    // crossAxisSpacing is between the columns, mainAxisSpacing between rows.
    expect(grid().props['spacing'], 4.0);
    expect(grid().props['runSpacing'], 8.0);
    expect(grid().props['childAspectRatio'], 1.5);
  });

  test('every child is a cell, in order', () {
    expect(grid().children, hasLength(7));
    expect(
      grid().children!.map((c) => c.props['content']).toList(),
      [for (var i = 0; i < 7; i++) 'cell $i'],
    );
  });

  test('a ragged last row is still just children', () {
    // Seven cells in threes: the renderers lay out two full rows and one of
    // one, rather than the tree saying anything about rows.
    expect(tester.find('cell_6'), isNotNull);
  });
}
