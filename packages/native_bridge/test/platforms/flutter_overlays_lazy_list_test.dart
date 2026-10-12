/// Widget tests for overlays and long lists in the Flutter renderer: dialogs,
/// sheets and snackbars drawn from the tree, and a lazy list reporting what is
/// on screen.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ten thousand rows, of which the app only ever builds a window.
class _LongListApp extends NativeUIApp {
  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Long list'),
    body: UIBuilder.lazyList(
      id: 'rows',
      itemCount: 10000,
      itemExtent: 56,
      itemBuilder: (index) => UIBuilder.text('Row $index'),
    ),
  );
}

/// A screen that opens a dialog and a sheet, and closes them on dismiss.
class _ModalApp extends NativeUIApp {
  bool dialogOpen = false;
  bool sheetOpen = false;

  @override
  WidgetNode build() => UIBuilder.overlay(
    child: UIBuilder.scaffold(
      appBar: UIBuilder.appBar(title: 'Modals'),
      body: UIBuilder.column(
        children: [
          UIBuilder.button(
            label: 'Open dialog',
            onPressed: () => setState(() => dialogOpen = true),
          ),
          UIBuilder.button(
            label: 'Open sheet',
            onPressed: () => setState(() => sheetOpen = true),
          ),
        ],
      ),
    ),
    overlays: [
      if (dialogOpen)
        UIBuilder.dialog(
          title: 'Delete?',
          content: [UIBuilder.text('This cannot be undone.')],
          actions: [
            UIBuilder.button(
              label: 'Keep',
              variant: 'tertiary',
              onPressed: () => setState(() => dialogOpen = false),
            ),
          ],
          onDismiss: () => setState(() => dialogOpen = false),
        ),
      if (sheetOpen)
        UIBuilder.bottomSheet(
          title: 'Share',
          content: [UIBuilder.text('Pick a target')],
          onDismiss: () => setState(() => sheetOpen = false),
        ),
    ],
  );
}

/// A LazyList node carrying rows [start] until [end], as the builder makes.
WidgetNode _lazyList({
  int itemCount = 10000,
  int start = 0,
  int end = 30,
  String id = 'rows',
}) => WidgetNode(
  type: 'LazyList',
  props: {
    'id': id,
    'itemCount': itemCount,
    'itemExtent': 56.0,
    'startIndex': start,
    'rangeEventId': 'range',
  },
  children: [
    for (var index = start; index < end; index++)
      WidgetNode(
        type: 'Text',
        props: {'content': 'Row $index', 'id': '$id/$index'},
      ),
  ],
);

/// A LazyList node whose rows are not all the same height: every tenth row is
/// 120 tall and the rest are 40, which is the shape of a feed with pictures.
WidgetNode _variableList({
  int itemCount = 1000,
  int start = 0,
  int end = 30,
  String id = 'rows',
}) {
  double heightOf(int index) => index % 10 == 0 ? 120.0 : 40.0;
  var offset = 0.0;
  for (var index = 0; index < start; index++) {
    offset += heightOf(index);
  }
  var total = 0.0;
  for (var index = 0; index < itemCount; index++) {
    total += heightOf(index);
  }
  return WidgetNode(
    type: 'LazyList',
    props: {
      'id': id,
      'itemCount': itemCount,
      'extents': [for (var index = start; index < end; index++) heightOf(index)],
      'startOffset': offset,
      'totalExtent': total,
      'startIndex': start,
      'rangeEventId': 'range',
    },
    children: [
      for (var index = start; index < end; index++)
        WidgetNode(
          type: 'Text',
          props: {'content': 'Row $index', 'id': '$id/$index'},
        ),
    ],
  );
}

void main() {
  late FlutterUIRenderer renderer;
  late List<Map<String, Map<String, dynamic>>> events;

  setUp(() {
    renderer = FlutterUIRenderer();
    events = [];
    for (final id in ['dismiss', 'action', 'range', 'tap']) {
      renderer.onEvent(id, (data) => events.add({id: data}));
    }
  });
  tearDown(() => renderer.dispose());

  /// Renders [node] on its own inside a Material app.
  Future<void> show(WidgetTester tester, WidgetNode node) async {
    await renderer.render(node);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.build)),
    );
  }

  WidgetNode screen() => UIBuilder.scaffold(
    body: UIBuilder.button(label: 'Under', eventId: 'tap'),
  );

  group('overlay', () {
    testWidgets('draws the overlays above the screen, later ones on top', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.overlay(
          child: screen(),
          overlays: [UIBuilder.text('first'), UIBuilder.text('second')],
        ),
      );

      // The overlay's own stack, not the one a page transition is drawn in.
      final stack = tester
          .widgetList<Stack>(find.byType(Stack))
          .firstWhere((stack) => stack.fit == StackFit.expand);
      expect(stack.children, hasLength(3));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('dialog', () {
    WidgetNode dialog({bool dismissible = true}) => UIBuilder.overlay(
      child: screen(),
      overlays: [
        UIBuilder.dialog(
          title: 'Delete?',
          content: [UIBuilder.text('This cannot be undone.')],
          actions: [UIBuilder.button(label: 'Delete', eventId: 'action')],
          dismissEventId: 'dismiss',
          dismissible: dismissible,
        ),
      ],
    );

    testWidgets('paints its title, content and actions', (tester) async {
      await show(tester, dialog());

      expect(find.text('Delete?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      expect(events, [
        {'action': {}},
      ]);
    });

    testWidgets('is announced as a route named by its title', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester, dialog());

      expect(
        tester.getSemantics(find.bySemanticsLabel('Delete?').first),
        matchesSemantics(label: 'Delete?', scopesRoute: true, namesRoute: true),
      );
      handle.dispose();
    });

    testWidgets('a tap on the scrim asks for dismissal, one on it does not', (
      tester,
    ) async {
      await show(tester, dialog());

      await tester.tap(find.text('This cannot be undone.'));
      expect(events, isEmpty);

      await tester.tapAt(const Offset(4, 4));
      expect(events, [
        {
          'dismiss': {'reason': 'scrim'},
        },
      ]);
      // Only asked: the dialog stays until the tree leaves it out.
      await tester.pump();
      expect(find.text('Delete?'), findsOneWidget);
    });

    testWidgets(
      'a non-dismissible dialog sends nothing and blocks the screen',
      (tester) async {
        await show(tester, dialog(dismissible: false));

        await tester.tapAt(const Offset(4, 4));
        await tester.tap(find.text('Under'), warnIfMissed: false);
        expect(events, isEmpty);
      },
    );

    testWidgets('is centred and no wider than 560', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await show(tester, dialog());

      final surface = tester.getRect(
        find
            .ancestor(of: find.text('Delete?'), matching: find.byType(Material))
            .first,
      );
      expect(surface.width, 560);
      expect(surface.center.dx, 600);
    });
  });

  group('bottom sheet', () {
    WidgetNode sheet() => UIBuilder.overlay(
      child: screen(),
      overlays: [
        UIBuilder.bottomSheet(
          title: 'Share',
          content: [UIBuilder.text('Pick a target')],
          dismissEventId: 'dismiss',
        ),
      ],
    );

    testWidgets('sits along the bottom edge', (tester) async {
      await show(tester, sheet());

      final surface = tester.getRect(
        find
            .ancestor(of: find.text('Share'), matching: find.byType(Material))
            .first,
      );
      expect(surface.bottom, 600);
      expect(surface.width, 640);
    });

    testWidgets('dragging it down asks for dismissal and springs back', (
      tester,
    ) async {
      await show(tester, sheet());
      final resting = tester.getTopLeft(find.text('Share'));

      await tester.drag(find.text('Share'), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(events, [
        {
          'dismiss': {'reason': 'swipe'},
        },
      ]);
      expect(tester.getTopLeft(find.text('Share')), resting);
    });

    testWidgets('a tap on the scrim asks for dismissal', (tester) async {
      await show(tester, sheet());

      await tester.tapAt(const Offset(4, 4));
      expect(events, [
        {
          'dismiss': {'reason': 'scrim'},
        },
      ]);
    });
  });

  group('snackbar', () {
    WidgetNode withSnackbar({String id = 'saved', int durationMs = 4000}) =>
        UIBuilder.overlay(
          child: screen(),
          overlays: [
            UIBuilder.snackbar(
              message: 'Saved',
              actionLabel: 'Undo',
              actionEventId: 'action',
              dismissEventId: 'dismiss',
              duration: Duration(milliseconds: durationMs),
              id: id,
            ),
          ],
        );

    testWidgets('paints its message and sends its action', (tester) async {
      await show(tester, withSnackbar(durationMs: 0));

      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(events, [
        {'action': {}},
      ]);
    });

    testWidgets('blocks nothing beside it', (tester) async {
      await show(tester, withSnackbar(durationMs: 0));

      await tester.tap(find.text('Under'));
      expect(events, [
        {'tap': {}},
      ]);
    });

    testWidgets('times out once however often it is rendered', (tester) async {
      await show(tester, withSnackbar());
      await tester.pump(const Duration(seconds: 2));

      // The same snackbar rendered again, as a fresh tree.
      await show(tester, withSnackbar());
      await tester.pump(const Duration(milliseconds: 1999));
      expect(events, isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(events, [
        {
          'dismiss': {'reason': 'timeout'},
        },
      ]);

      await show(tester, withSnackbar());
      await tester.pump(const Duration(seconds: 10));
      expect(events, hasLength(1));
    });

    testWidgets('a replacement with a new id starts its own timer', (
      tester,
    ) async {
      await show(tester, withSnackbar(id: 'one'));
      await tester.pump(const Duration(seconds: 3));
      await show(tester, withSnackbar(id: 'two'));
      await tester.pump(const Duration(seconds: 3));
      expect(events, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(events, hasLength(1));
    });

    testWidgets('leaving the tree cancels the timeout', (tester) async {
      await show(tester, withSnackbar());
      await tester.pump(const Duration(seconds: 1));

      await show(tester, UIBuilder.overlay(child: screen()));
      await tester.pump(const Duration(seconds: 10));
      expect(events, isEmpty);
    });

    testWidgets('a duration of zero never times out', (tester) async {
      await show(tester, withSnackbar(durationMs: 0));
      await tester.pump(const Duration(minutes: 1));
      expect(events, isEmpty);
    });

    testWidgets('takes the look it is given', (tester) async {
      await show(
        tester,
        UIBuilder.overlay(
          child: screen(),
          overlays: [
            UIBuilder.snackbar(
              message: 'Saved',
              id: 'styled',
              actionLabel: 'Undo',
              actionEventId: 'action',
              duration: Duration.zero,
              backgroundColor: '#2e7d32',
              textColor: '#fffde7',
              actionColor: '#ffeb3b',
              borderRadius: 12,
              width: 280,
            ),
          ],
        ),
      );

      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Saved'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .width,
        280,
      );
      final bar = tester.widget<Material>(
        find.ancestor(of: find.text('Saved'), matching: find.byType(Material)).first,
      );
      expect(bar.color, const Color(0xff2e7d32));
      expect(bar.borderRadius, BorderRadius.circular(12));
      expect(
        tester.widget<Text>(find.text('Saved')).style!.color,
        const Color(0xfffffde7),
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
            .style!
            .foregroundColor!
            .resolve({}),
        const Color(0xffffeb3b),
      );
    });

    testWidgets('a margin places it, and a fixed bar runs edge to edge', (
      tester,
    ) async {
      Finder bar() => find
          .ancestor(of: find.text('Saved'), matching: find.byType(Material))
          .first;
      final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;

      await show(
        tester,
        UIBuilder.overlay(
          child: screen(),
          overlays: [
            UIBuilder.snackbar(
              message: 'Saved',
              id: 'roomy',
              duration: Duration.zero,
              margin: [40, 0, 24, 30],
              elevation: 0,
            ),
          ],
        ),
      );
      final roomy = tester.getRect(bar());
      expect(roomy.left, 40);
      expect(roomy.right, screenWidth - 24);
      expect(tester.widget<Material>(bar()).elevation, 0);

      await show(
        tester,
        UIBuilder.overlay(
          child: screen(),
          overlays: [
            UIBuilder.snackbar(
              message: 'Saved',
              id: 'flush',
              duration: Duration.zero,
              fixed: true,
            ),
          ],
        ),
      );
      final flush = tester.getRect(bar());
      expect(flush.left, 0);
      expect(flush.right, screenWidth);
      expect(tester.widget<Material>(bar()).borderRadius, BorderRadius.zero);
    });

    WidgetNode snackbarOver(WidgetNode scaffold) => UIBuilder.overlay(
      child: scaffold,
      overlays: [UIBuilder.snackbar(message: 'Saved', id: 'saved')],
    );
    WidgetNode destinations() => UIBuilder.bottomBar(
      child: UIBuilder.bottomNavigation(
        eventId: 'tab',
        selectedIndex: 0,
        items: const [
          (label: 'One', icon: 0xe88a, selectedIcon: null),
          (label: 'Two', icon: 0xe88a, selectedIcon: null),
        ],
      ),
    );

    // Material shows a snackbar above the bottom bar and above the floating
    // button; the snackbar here is drawn beside the scaffold, so it has to
    // be told how far up they reach.
    testWidgets('sits above the bottom bar', (tester) async {
      await show(
        tester,
        snackbarOver(
          UIBuilder.scaffold(
            body: UIBuilder.text('body'),
            bottomBar: destinations(),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getRect(find.text('Saved')).bottom,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
    });

    testWidgets('sits above the floating button, and the bar under that', (
      tester,
    ) async {
      await show(
        tester,
        snackbarOver(
          UIBuilder.scaffold(
            body: UIBuilder.text('body'),
            floatingActionButton: UIBuilder.floatingActionButton(
              tooltip: 'Add',
              eventId: 'add',
            ),
            bottomBar: destinations(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byType(FloatingActionButton));
      expect(
        button.top,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      expect(tester.getRect(find.text('Saved')).bottom, lessThan(button.top));
    });

    testWidgets('comes back down when the bar it cleared has gone', (
      tester,
    ) async {
      await show(
        tester,
        snackbarOver(
          UIBuilder.scaffold(
            body: UIBuilder.text('body'),
            bottomBar: destinations(),
          ),
        ),
      );
      await tester.pump();
      final lifted = tester.getRect(find.text('Saved')).bottom;

      await show(tester, snackbarOver(UIBuilder.scaffold(body: UIBuilder.text('body'))));
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.text('Saved')).bottom, greaterThan(lifted));
    });
  });

  group('lazy list', () {
    ScrollController controller(WidgetTester tester) =>
        tester.widget<ListView>(find.byType(ListView)).controller!;

    List<Map<String, dynamic>> ranges() => [
      for (final event in events) ?event['range'],
    ];

    testWidgets('fills a Scaffold body without a scroll view around it', (
      tester,
    ) async {
      await show(
        tester,
        UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'Rows'),
          body: _lazyList(),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('Row 0'), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)), const Size(800, 544));
    });

    WidgetNode withProps(Map<String, dynamic> extra) {
      final list = _lazyList();
      return WidgetNode(
        type: list.type,
        props: {...list.props, ...extra},
        children: list.children,
      );
    }

    testWidgets('its padding is room the rows scroll under', (tester) async {
      await show(
        tester,
        UIBuilder.scaffold(
          body: withProps({
            'padding': [16.0, 100.0, 24.0, 40.0],
          }),
        ),
      );
      await tester.pump();

      // Inset from the edges, and the first row below the room at the top.
      final row = tester.getRect(find.text('Row 0'));
      expect(row.top, 100);
      expect(row.left, greaterThanOrEqualTo(16));
      expect(controller(tester).position.maxScrollExtent, 10000 * 56 + 140 - 600);
      // Rows are counted from the first one, not from the top of the room.
      expect(ranges().last, {'first': 0, 'last': 8});

      controller(tester).jumpTo(100 + 56 * 10);
      await tester.pump();

      expect(ranges().last['first'], 10);
    });

    testWidgets('a pull sends the refresh, and the tree ends the spinner', (
      tester,
    ) async {
      var refreshes = 0;
      renderer.onEvent('refresh', (_) => refreshes++);
      await show(
        tester,
        UIBuilder.scaffold(
          body: withProps({'refreshEventId': 'refresh', 'refreshing': false}),
        ),
      );

      await tester.fling(find.text('Row 2'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(refreshes, 1);

      await show(
        tester,
        UIBuilder.scaffold(
          body: withProps({'refreshEventId': 'refresh', 'refreshing': true}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await show(
        tester,
        UIBuilder.scaffold(
          body: withProps({'refreshEventId': 'refresh', 'refreshing': false}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(refreshes, 1);
    });

    testWidgets('says where it is in pixels, to a node that asks', (
      tester,
    ) async {
      final reports = <Map<String, dynamic>>[];
      renderer.onEvent('scrolled', reports.add);
      await show(
        tester,
        UIBuilder.scaffold(body: withProps({'scrollEventId': 'scrolled'})),
      );
      await tester.pump();
      expect(reports, isEmpty);

      controller(tester).jumpTo(700);
      await tester.pump();

      expect(reports.last['offset'], 700);
      expect(reports.last['viewport'], 600);
      expect(reports.last['maxExtent'], 10000 * 56 - 600);
      // And the rows, as before, for the window.
      expect(ranges().last['first'], 12);
    });

    testWidgets('a list whose node does not ask sends nothing', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));

      controller(tester).jumpTo(700);
      await tester.pump();

      expect(events.where((event) => event.containsKey('scrolled')), isEmpty);
    });

    testWidgets('a list with no refresh has no indicator', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));

      expect(find.byType(RefreshIndicator), findsNothing);
    });

    testWidgets('reports the visible range once per change', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));
      await tester.pump();
      expect(ranges(), [
        {'first': 0, 'last': 10},
      ]);

      controller(tester).jumpTo(560);
      await tester.pump();
      controller(tester).jumpTo(561);
      await tester.pump();
      await show(tester, UIBuilder.scaffold(body: _lazyList()));
      await tester.pump();

      expect(ranges(), [
        {'first': 0, 'last': 10},
        {'first': 10, 'last': 20},
      ]);
    });

    testWidgets('rows of their own heights are as tall as they say', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: _variableList()));
      await tester.pump();

      // 100 blocks of (120 + 9*40) over a thousand rows.
      expect(
        tester.getSize(find.byType(SingleChildScrollView)).height,
        greaterThan(0),
      );
      expect(tester.getSize(find.text('Row 0')).height, 120);
      expect(tester.getSize(find.text('Row 1')).height, 40);
      expect(tester.getSize(find.text('Row 10')).height, 120);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a window far down starts where its rows do', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _variableList(start: 40, end: 70)));
      await tester.pump();

      // Rows 0..39 are four blocks of 480.
      final top = tester.getTopLeft(find.text('Row 40')).dy;
      final listTop = tester
          .getTopLeft(find.byType(SingleChildScrollView))
          .dy;
      expect(top - listTop, 4 * 480);
    });

    testWidgets('such a list reports pixels rather than row numbers', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: _variableList()));
      await tester.pump();

      expect(ranges().single.keys.toList(), ['offset', 'viewport']);
      expect(ranges().single['offset'], 0);
    });

    testWidgets('a drag reports the rows it brought on screen', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(ranges().last['first'], greaterThan(0));
      expect(
        ranges().map((range) => (range['first'], range['last'])).toSet(),
        hasLength(ranges().length),
      );
    });

    testWidgets('rows outside the window keep their height empty', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));
      controller(tester).jumpTo(56.0 * 100);
      await tester.pump();

      expect(find.textContaining('Row'), findsNothing);
      expect(controller(tester).offset, 5600);
    });

    testWidgets('keeps its offset across a re-render', (tester) async {
      await show(tester, UIBuilder.scaffold(body: _lazyList()));
      controller(tester).jumpTo(1000);
      await tester.pump();

      await show(
        tester,
        UIBuilder.scaffold(body: _lazyList(itemCount: 20000, start: 10)),
      );
      expect(controller(tester).offset, 1000);

      // Even when the list is built anew somewhere else in the tree.
      await show(
        tester,
        UIBuilder.scaffold(
          body: UIBuilder.column(
            children: [
              UIBuilder.text('Header'),
              UIBuilder.expanded(child: _lazyList(start: 10)),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Header'), findsOneWidget);
      expect(controller(tester).offset, 1000);
    });

    testWidgets('an app moves its window as the list scrolls', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NativeUIAppHost(app: _LongListApp())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Row 0'), findsOneWidget);

      controller(tester).jumpTo(56.0 * 5000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Row 0'), findsNothing);
      expect(find.text('Row 5000'), findsOneWidget);
      expect(find.text('Row 5005'), findsOneWidget);
    });
  });

  testWidgets('an app opens and dismisses a dialog and a sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NativeUIAppHost(app: _ModalApp())),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Modals'), findsOneWidget);

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('This cannot be undone.'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsNothing);

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsNothing);

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a target'), findsOneWidget);

    await tester.drag(find.text('Share'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('swipe actions', () {
    setUp(() {
      for (final id in ['delete', 'archive', 'mark']) {
        renderer.onEvent(id, (data) => events.add({id: data}));
      }
    });

    /// A row with two actions behind it and one the other way, as a build
    /// would produce.
    WidgetNode row() => WidgetNode(
      type: 'SwipeActions',
      props: {
        'actions': [
          {'label': 'Delete', 'color': '#d32f2f', 'eventId': 'delete'},
          {'label': 'Archive', 'color': '#1976d2', 'eventId': 'archive'},
        ],
        'leadingActions': [
          {'label': 'Mark read', 'color': '#1976d2', 'eventId': 'mark'},
        ],
      },
      children: [
        WidgetNode(type: 'Text', props: {'content': 'A row'}),
      ],
    );

    /// How far the row is slid, from the transform the state applies.
    double offset(WidgetTester tester) => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.text('A row'),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform
        .getTranslation()
        .x;

    List<String> fired() => [
      for (final event in events)
        if (event.containsKey('delete')) 'delete'
        else if (event.containsKey('archive')) 'archive'
        else if (event.containsKey('mark')) 'mark',
    ];

    testWidgets('the actions sit behind the row until it is dragged', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Archive'), findsOneWidget);
      expect(offset(tester), 0);
    });

    testWidgets('a partial drag snaps the row open, firing nothing', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      await tester.drag(find.text('A row'), const Offset(-100, 0));
      await tester.pumpAndSettle();

      // Two actions of 88: open is -176.
      expect(offset(tester), -176);
      expect(fired(), isEmpty);
    });

    testWidgets('an action can be tapped once the row is open', (tester) async {
      await show(tester, UIBuilder.scaffold(body: row()));
      await tester.drag(find.text('A row'), const Offset(-100, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(fired(), ['delete']);
      expect(offset(tester), 0);
    });

    testWidgets('a short drag lets the row fall back', (tester) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      await tester.drag(find.text('A row'), const Offset(-20, 0));
      await tester.pumpAndSettle();

      expect(offset(tester), 0);
      expect(fired(), isEmpty);
    });

    testWidgets('a drag the other way opens the leading actions', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      await tester.drag(find.text('A row'), const Offset(60, 0));
      await tester.pumpAndSettle();

      // One leading action of 88.
      expect(offset(tester), 88);
      expect(fired(), isEmpty);
      expect(find.text('Mark read'), findsOneWidget);
    });

    testWidgets('a long drag the other way fires the leading action', (
      tester,
    ) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      await tester.drag(find.text('A row'), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(fired(), ['mark']);
      expect(offset(tester), 0);
    });

    testWidgets('a long drag fires the first action by itself', (tester) async {
      await show(tester, UIBuilder.scaffold(body: row()));

      await tester.drag(find.text('A row'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(fired(), ['delete']);
      expect(offset(tester), 0);
    });

    // Trailing is the end of the row, and in Arabic the end is the left.
    // The two bars are rows and changed sides on their own; the drag did
    // not, so a swipe slid the row over the bar it meant to show and fired
    // the other one's action.
    group('in a screen that reads right to left', () {
      WidgetNode rtl() =>
          UIBuilder.withTextDirection(UIBuilder.scaffold(body: row()), 'rtl');

      testWidgets('the trailing actions are on the left', (tester) async {
        await show(tester, rtl());

        expect(
          tester.getCenter(find.text('Delete')).dx,
          lessThan(tester.getCenter(find.text('Mark read')).dx),
        );
      });

      testWidgets('a drag to the right uncovers them', (tester) async {
        await show(tester, rtl());

        await tester.drag(find.text('A row'), const Offset(100, 0));
        await tester.pumpAndSettle();

        // Slid right by the width of the two trailing actions, which is
        // where they are.
        expect(offset(tester), 176);
        expect(fired(), isEmpty);
        expect(tester.getTopLeft(find.text('A row')).dx, 176);
      });

      testWidgets('a long drag to the right fires the first of them', (
        tester,
      ) async {
        await show(tester, rtl());

        await tester.drag(find.text('A row'), const Offset(320, 0));
        await tester.pumpAndSettle();

        expect(fired(), ['delete']);
        expect(offset(tester), 0);
      });

      testWidgets('a drag to the left uncovers the leading action', (
        tester,
      ) async {
        await show(tester, rtl());

        await tester.drag(find.text('A row'), const Offset(-60, 0));
        await tester.pumpAndSettle();

        expect(offset(tester), -88);
        expect(fired(), isEmpty);
      });
    });
  });
}
