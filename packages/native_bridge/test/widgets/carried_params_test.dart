/// Parameters Flutter apps set that used to be taken and dropped: a
/// `Center`'s factors, a `DataColumn`'s width, a field's caret colour and a
/// `TextPainter`'s ellipsis.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppTester show(Widget body) =>
      AppTester.widget(MaterialApp(home: Scaffold(body: body)));

  test('a Center with a factor is as tall as its child, not the room', () {
    final app = show(
      Column(
        children: [
          const Center(heightFactor: 1, child: Text('hugged')),
          Expanded(child: Container()),
        ],
      ),
    );
    expect(app.ofType('Center'), isEmpty);
    final box = app.nodes.firstWhere(
      (n) => n.type == 'Box' && n.props['alignment'] != null,
    );
    expect(box.props['expand'], 'width');
  });

  test('a fixed column is that wide, a flex one a share', () {
    final app = show(
      DataTable(
        columns: const [
          DataColumn(label: Text('Id'), columnWidth: FixedColumnWidth(60)),
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Notes'), columnWidth: FlexColumnWidth(3)),
        ],
        rows: const [
          DataRow(cells: [
            DataCell(Text('1')),
            DataCell(Text('Ada')),
            DataCell(Text('First')),
          ]),
        ],
      ),
    );
    final fixed = app.nodes.where((n) => n.props['width'] == 60 + 24.0);
    expect(fixed, isNotEmpty);
    final flexes = [
      for (final n in app.ofType('Expanded')) (n.props['flex'] as num).toInt(),
    ];
    // Per row: the measured column, then three times the average share.
    expect(flexes.length, greaterThanOrEqualTo(2), reason: '$flexes');
    expect(flexes[1], greaterThan(flexes[0]), reason: '$flexes');
  });

  test('a field says the colour of its caret', () {
    final app = show(
      const TextField(cursorColor: Color(0xFFE91E63)),
    );
    expect(app.ofType('TextField').single.props['cursorColor'], '#e91e63');
  });

  test('a painter cut short by maxLines ends its last line in the ellipsis',
      () {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'one two three four five six seven eight nine ten',
        style: TextStyle(fontSize: 20),
      ),
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    expect(painter.didExceedMaxLines, isTrue);
    expect(painter.height, closeTo(2 * 20 * 1.2, 0.01));

    final whole = TextPainter(
      text: const TextSpan(text: 'short', style: TextStyle(fontSize: 20)),
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    expect(whole.didExceedMaxLines, isFalse);
  });
}
