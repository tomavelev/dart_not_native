/// `Stepper` and `DataTable`. Neither was there, so an app with a checkout
/// in steps or a table of records did not compile.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('a Stepper', () {
    late List<String> heard;
    setUp(() => heard = []);

    Widget stepper({
      int current = 0,
      StepperType type = StepperType.vertical,
      ControlsWidgetBuilder? controls,
      bool listens = true,
      StepState second = StepState.indexed,
    }) => _app(
      Stepper(
        type: type,
        currentStep: current,
        onStepTapped: listens ? (index) => heard.add('tapped $index') : null,
        onStepContinue: listens ? () => heard.add('continue') : null,
        onStepCancel: listens ? () => heard.add('cancel') : null,
        controlsBuilder: controls,
        steps: [
          const Step(title: Text('Address'), content: Text('Where to')),
          Step(
            title: const Text('Payment'),
            subtitle: const Text('Card or cash'),
            content: const Text('How to pay'),
            state: second,
          ),
          const Step(title: Text('Confirm'), content: Text('All correct?')),
        ],
      ),
    );

    test('shows every step\'s title, and the open step\'s content', () {
      final app = AppTester.widget(stepper(current: 1));

      expect(app.texts, containsAll(['Address', 'Payment', 'Confirm']));
      expect(app.hasText('Card or cash'), isTrue);
      expect(app.hasText('How to pay'), isTrue);
      expect(app.hasText('Where to'), isFalse);
      expect(app.hasText('All correct?'), isFalse);
      // Numbered from one.
      expect(app.texts, containsAll(['1', '2', '3']));
    });

    test('Continue and Cancel call the app, which moves the step', () async {
      final app = AppTester.widget(stepper());
      final buttons = app.ofType('Button');

      expect(buttons.map((b) => b.props['label']), ['Continue', 'Cancel']);
      await app.tapEvent(buttons.first.props['eventId'] as String);
      await app.tapEvent(buttons.last.props['eventId'] as String);

      expect(heard, ['continue', 'cancel']);
    });

    test('the next step opens and the last closes, each in its time', () async {
      final current = ValueNotifier(0);
      final app = AppTester.widget(
        _app(
          ValueListenableBuilder<int>(
            valueListenable: current,
            builder: (_, step, _) => Stepper(
              currentStep: step,
              steps: const [
                Step(title: Text('Address'), content: Text('Where to')),
                Step(title: Text('Payment'), content: Text('How to pay')),
              ],
            ),
          ),
        ),
      );
      final sizing = app.nodes.where((n) => n.props['animateSize'] == true);
      expect(sizing.map((n) => n.props['animateMs']), [200, 200]);
      current.value = 1;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Both are on the screen while one closes and the other opens.
      expect(app.hasText('Where to'), isTrue);
      expect(app.hasText('How to pay'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(app.hasText('Where to'), isFalse);
      expect(app.hasText('How to pay'), isTrue);
    });

    test('with nothing listening, the buttons are off', () {
      final app = AppTester.widget(stepper(listens: false));

      expect(
        app.ofType('Button').map((b) => b.props['disabled']),
        [true, true],
      );
    });

    test('a step\'s head is tapped; a disabled step\'s is not', () async {
      final app = AppTester.widget(stepper(second: StepState.disabled));
      final taps = [
        for (final node in app.nodes)
          if (node.props['tapEventId'] is String)
            node.props['tapEventId'] as String,
      ];

      // The first and the third, not the one that is off.
      expect(taps, hasLength(2));
      await app.emit(taps.last);
      expect(heard, ['tapped 2']);
    });

    test('a complete step shows a tick, and an error an exclamation', () {
      expect(
        AppTester.widget(stepper(second: StepState.complete)).texts,
        isNot(contains('2')),
      );
      expect(
        AppTester.widget(stepper(second: StepState.error)).hasText('!'),
        isTrue,
      );
    });

    test('controlsBuilder replaces the buttons, and is told the step', () {
      ControlsDetails? given;
      final app = AppTester.widget(
        stepper(
          current: 2,
          controls: (context, details) {
            given = details;
            return const Text('My own buttons');
          },
        ),
      );

      expect(app.hasText('My own buttons'), isTrue);
      expect(app.ofType('Button'), isEmpty);
      expect(given!.stepIndex, 2);
      expect(given!.isActive, isTrue);
      expect(given!.onStepContinue, isNotNull);
    });

    test('a horizontal one shows the same steps and the open content', () {
      final app = AppTester.widget(
        stepper(current: 2, type: StepperType.horizontal),
      );

      expect(app.texts, containsAll(['Address', 'Payment', 'Confirm']));
      expect(app.hasText('All correct?'), isTrue);
      expect(app.hasText('Where to'), isFalse);
    });
  });

  group('a DataTable', () {
    late List<String> heard;
    setUp(() => heard = []);

    Widget table({
      int? sorted,
      bool ascending = true,
      bool selectable = false,
      Set<int> selected = const {},
      bool selectAll = false,
    }) => _app(
      DataTable(
        sortColumnIndex: sorted,
        sortAscending: ascending,
        onSelectAll: selectAll ? (all) => heard.add('all $all') : null,
        columns: [
          DataColumn(
            label: const Text('Name'),
            onSort: (index, up) => heard.add('sort $index $up'),
          ),
          const DataColumn(label: Text('Age'), numeric: true),
        ],
        rows: [
          for (final (index, (name, age)) in const [
            ('Ada', '36'),
            ('Linus', '54'),
          ].indexed)
            DataRow(
              selected: selected.contains(index),
              onSelectChanged: selectable
                  ? (value) => heard.add('row $index $value')
                  : null,
              cells: [
                DataCell(Text(name)),
                DataCell(Text(age), onTap: () => heard.add('cell $age')),
              ],
            ),
        ],
      ),
    );

    test('shows its headings and every row\'s cells', () {
      final app = AppTester.widget(table());

      expect(
        app.texts,
        containsAllInOrder(['Name', 'Age', 'Ada', '36', 'Linus', '54']),
      );
      expect(app.ofType('Checkbox'), isEmpty);
    });

    test('every row has a share of the width for each column', () {
      final app = AppTester.widget(table());
      final rows = app.ofType('Row').where(
        (row) =>
            (row.children ?? const []).where((c) => c.type == 'Expanded').length ==
            2,
      );

      // The heading and the two rows of data.
      expect(rows, hasLength(3));
    });

    test('a column with longer cells has the larger share', () {
      final app = AppTester.widget(
        _app(
          DataTable(
            columns: const [
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Qty'), numeric: true),
              DataColumn(label: CircularProgressIndicator()),
            ],
            rows: const [
              DataRow(
                cells: [
                  DataCell(Text('A rather long line of description')),
                  DataCell(Text('3')),
                  DataCell(CircularProgressIndicator()),
                ],
              ),
            ],
          ),
        ),
      );
      final shares = [
        for (final cell in app.ofType('Row').first.children!)
          cell.props['flex'] as int,
      ];

      expect(shares[0], greaterThan(shares[1] * 3));
      // The one that cannot be measured has the average of the others.
      expect(shares[2], ((shares[0] + shares[1]) / 2).round());
    });

    test('a heading that sorts is tapped: ascending first, then turned round',
        () async {
      var app = AppTester.widget(table());
      String sortTap(AppTester app) => app.nodes
          .firstWhere((node) => node.props['tapEventId'] is String)
          .props['tapEventId'] as String;

      await app.emit(sortTap(app));
      expect(heard, ['sort 0 true']);

      app = AppTester.widget(table(sorted: 0));
      await app.emit(sortTap(app));
      expect(heard.last, 'sort 0 false');
    });

    test('the sorted column shows which way', () {
      int arrows(AppTester app) => app.ofType('Icon').length;

      expect(arrows(AppTester.widget(table())), 0);
      expect(arrows(AppTester.widget(table(sorted: 0))), 1);
    });

    test('a cell with a tap is tapped', () async {
      final app = AppTester.widget(table());
      final taps = [
        for (final node in app.nodes)
          if (node.props['tapEventId'] is String)
            node.props['tapEventId'] as String,
      ];

      // The sorting heading, then the two age cells.
      expect(taps, hasLength(3));
      await app.emit(taps.last);
      expect(heard, ['cell 54']);
    });

    test('selectable rows gain checkboxes, one of them for all', () async {
      final app = AppTester.widget(table(selectable: true, selected: {1}));
      final boxes = app.ofType('Checkbox');

      expect(boxes, hasLength(3));
      expect(boxes.map((box) => box.props['checked']), [false, false, true]);

      await app.emit(boxes[1].props['eventId'] as String, {'checked': true});
      expect(heard, ['row 0 true']);
    });

    test('the heading\'s checkbox selects the rows that are not', () async {
      final app = AppTester.widget(table(selectable: true, selected: {1}));

      await app.emit(
        app.ofType('Checkbox').first.props['eventId'] as String,
        {'checked': true},
      );

      expect(heard, ['row 0 true']);
    });

    test('or calls onSelectAll, when the app has one', () async {
      final app = AppTester.widget(
        table(selectable: true, selectAll: true),
      );

      await app.emit(
        app.ofType('Checkbox').first.props['eventId'] as String,
        {'checked': true},
      );

      expect(heard, ['all true']);
    });

    test('with every row selected, the heading\'s box is ticked', () {
      final app = AppTester.widget(table(selectable: true, selected: {0, 1}));

      expect(app.ofType('Checkbox').first.props['checked'], isTrue);
    });
  });
}
