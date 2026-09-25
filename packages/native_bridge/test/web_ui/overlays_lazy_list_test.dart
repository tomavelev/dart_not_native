@TestOn('browser')
/// Browser tests for dialogs, bottom sheets, snackbars and lazy lists.
///
/// Overlays only ever send events - the app removes them - so these check
/// what is sent, and when. Lazy lists are checked against real layout and
/// real scrolling, which is why the test root is given a height.
///
/// Run with: flutter test --platform chrome test/web_ui/overlays_lazy_list_test.dart
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

/// Waits for layout, the resize observers and the scroll events it causes.
Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    final frame = Completer<void>();
    web.window.requestAnimationFrame(((num _) => frame.complete()).toJS);
    await frame.future;
  }
  await Future<void>.delayed(Duration.zero);
}

web.KeyboardEvent escapeKey() => web.KeyboardEvent(
  'keydown',
  web.KeyboardEventInit(key: 'Escape', bubbles: true),
);

/// A lazy list node as an app would send it: rows [start] until [end].
WidgetNode lazyList({
  required int start,
  required int end,
  int itemCount = 1000,
  double itemExtent = 50,
}) => WidgetNode(
  type: 'LazyList',
  props: {
    'id': 'rows',
    'itemCount': itemCount,
    'itemExtent': itemExtent,
    'startIndex': start,
    'rangeEventId': 'range',
  },
  children: [
    for (var i = start; i < end; i++) UIBuilder.text('Row $i', id: 'rows/$i'),
  ],
);

/// A lazy list whose rows are not all the same height, as an app would send
/// it: rows [start] until [end], each [heightOf] tall.
WidgetNode variableList({
  required int start,
  required int end,
  int itemCount = 1000,
  double Function(int index) heightOf = _stepped,
}) {
  var offset = 0.0;
  for (var i = 0; i < start; i++) {
    offset += heightOf(i);
  }
  var total = 0.0;
  for (var i = 0; i < itemCount; i++) {
    total += heightOf(i);
  }
  return WidgetNode(
    type: 'LazyList',
    props: {
      'id': 'rows',
      'itemCount': itemCount,
      'extents': [for (var i = start; i < end; i++) heightOf(i)],
      'startOffset': offset,
      'totalExtent': total,
      'startIndex': start,
      'rangeEventId': 'range',
    },
    children: [
      for (var i = start; i < end; i++) UIBuilder.text('Row $i', id: 'rows/$i'),
    ],
  );
}

/// Every tenth row is tall, the rest are short.
double _stepped(int index) => index % 10 == 0 ? 120 : 40;

/// A thousand rows, of which the app builds only the window.
class _RowsApp extends NativeUIApp {
  @override
  WidgetNode build() => UIBuilder.lazyList(
    id: 'rows',
    itemCount: 1000,
    itemExtent: 50,
    itemBuilder: (index) => UIBuilder.text('Row $index'),
  );
}

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<Map<String, dynamic>> dismissed;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    dismissed = [];
    renderer.onEvent('dismiss', dismissed.add);
  });

  tearDown(() => root.remove());

  WidgetNode withOverlays(List<WidgetNode> overlays) => UIBuilder.overlay(
    child: UIBuilder.scaffold(
      appBar: UIBuilder.appBar(title: 'Inbox'),
      body: UIBuilder.text('screen'),
    ),
    overlays: overlays,
  );

  group('dialogs', () {
    WidgetNode confirm({bool dismissible = true}) => UIBuilder.dialog(
      id: 'confirm',
      title: 'Delete message?',
      content: [UIBuilder.text('This cannot be undone.')],
      actions: [
        UIBuilder.button(label: 'Cancel', eventId: 'cancel', id: 'cancel'),
      ],
      dismissEventId: 'dismiss',
      dismissible: dismissible,
    );

    test('draw above the screen as an accessible modal', () async {
      await renderer.render(withOverlays([confirm()]));

      final overlay = root.querySelector('[data-type="Overlay"]')!;
      expect(childTypes(overlay), ['Scaffold', 'Dialog']);

      final surface = root.querySelector('[role="dialog"]')!;
      expect(surface.getAttribute('aria-modal'), 'true');
      final title = web.document.getElementById(
        surface.getAttribute('aria-labelledby')!,
      );
      expect(title!.textContent, 'Delete message?');
      expect(surface.textContent, contains('This cannot be undone.'));
      expect(childTypes(surface.querySelector('[data-children]')!), [
        'Column',
        'Row',
      ], reason: 'content under the title, then the actions');
      expect(web.document.activeElement, surface, reason: 'focus moves in');
    });

    test(
      'a tap on the scrim sends dismiss, one on the surface does not',
      () async {
        await renderer.render(withOverlays([confirm()]));

        (root.querySelector('[role="dialog"]')! as web.HTMLElement).click();
        expect(dismissed, isEmpty);

        (root.querySelector('.dnn-scrim')! as web.HTMLElement).click();
        expect(dismissed, [
          {'reason': 'scrim'},
        ]);
      },
    );

    test('Escape sends dismiss', () async {
      await renderer.render(withOverlays([confirm()]));

      web.document.activeElement!.dispatchEvent(escapeKey());

      expect(dismissed, [
        {'reason': 'escape'},
      ]);
    });

    test('are never removed by the renderer itself', () async {
      await renderer.render(withOverlays([confirm()]));

      (root.querySelector('.dnn-scrim')! as web.HTMLElement).click();

      expect(web.document.getElementById('confirm'), isNotNull);
    });

    test('a dialog that is not dismissible sends nothing', () async {
      await renderer.render(withOverlays([confirm(dismissible: false)]));

      (root.querySelector('.dnn-scrim')! as web.HTMLElement).click();
      root.querySelector('[role="dialog"]')!.dispatchEvent(escapeKey());

      expect(dismissed, isEmpty);
    });
  });

  group('bottom sheets', () {
    test('hold their content in a modal dismissed like a dialog', () async {
      await renderer.render(
        withOverlays([
          UIBuilder.bottomSheet(
            id: 'actions',
            content: [UIBuilder.text('Archive'), UIBuilder.text('Delete')],
            dismissEventId: 'dismiss',
          ),
        ]),
      );

      final surface = root.querySelector('[role="dialog"]')!;
      expect(surface.getAttribute('aria-modal'), 'true');
      expect(surface.className, contains('dnn-sheet'));
      expect(childTypes(surface.querySelector('[data-children]')!), [
        'Text',
        'Text',
      ]);

      (root.querySelector('.dnn-scrim')! as web.HTMLElement).click();
      surface.dispatchEvent(escapeKey());
      expect(dismissed, [
        {'reason': 'scrim'},
        {'reason': 'escape'},
      ]);
    });
  });

  group('snackbars', () {
    WidgetNode deleted({
      Duration duration = const Duration(milliseconds: 60),
      String actionLabel = 'Undo',
    }) => UIBuilder.snackbar(
      id: 'deleted',
      message: 'Message deleted',
      actionLabel: actionLabel,
      actionEventId: 'undo',
      dismissEventId: 'dismiss',
      duration: duration,
    );

    test('are announced politely, and their action sends its event', () async {
      final undone = <Map<String, dynamic>>[];
      renderer.onEvent('undo', undone.add);
      await renderer.render(withOverlays([deleted(duration: Duration.zero)]));

      final bar = web.document.getElementById('deleted')!;
      expect(bar.getAttribute('role'), 'status');
      expect(bar.getAttribute('aria-live'), 'polite');
      expect(bar.textContent, contains('Message deleted'));

      (bar.querySelector('button')! as web.HTMLElement).click();

      expect(undone, [<String, dynamic>{}]);
      expect(root.querySelector('.dnn-scrim'), isNull, reason: 'non-modal');
    });

    test('time out once however often they are rendered', () async {
      await renderer.render(withOverlays([deleted()]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await renderer.render(withOverlays([deleted()]));
      // Changed props rebuild the element; the timer is the snackbar's.
      await renderer.render(withOverlays([deleted(actionLabel: 'UNDO')]));

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(dismissed, [
        {'reason': 'timeout'},
      ]);

      await renderer.render(withOverlays([deleted()]));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(dismissed, hasLength(1));
    });

    test('with no duration stay until the app removes them', () async {
      await renderer.render(withOverlays([deleted(duration: Duration.zero)]));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(dismissed, isEmpty);
    });

    test('removed before their timeout never send it', () async {
      await renderer.render(withOverlays([deleted()]));
      await renderer.render(withOverlays([]));

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(dismissed, isEmpty);
    });
  });

  group('lazy lists', () {
    late List<Map<String, dynamic>> ranges;

    setUp(() {
      ranges = [];
      renderer.onEvent('range', ranges.add);
      root.style
        ..setProperty('height', '200px')
        ..setProperty('display', 'flex')
        ..setProperty('flex-direction', 'column');
    });

    web.HTMLElement viewport() =>
        root.querySelector('[data-type="LazyList"]')! as web.HTMLElement;

    double topOf(String id) =>
        web.document.getElementById(id)!.getBoundingClientRect().top -
        viewport()
            .querySelector('[data-children]')!
            .getBoundingClientRect()
            .top;

    test('are as tall as every row, with each row at its offset', () async {
      await renderer.render(lazyList(start: 10, end: 20));

      final content =
          viewport().querySelector('[data-children]')! as web.HTMLElement;
      expect(content.getBoundingClientRect().height, 50000);
      expect(viewport().getBoundingClientRect().height, 200);
      expect(topOf('rows/10'), 500);
      expect(topOf('rows/11'), 550);
      expect(
        web.document.getElementById('rows/11')!.getBoundingClientRect().height,
        50,
      );
    });

    test('rows of their own heights sit at their own offsets', () async {
      // Rows 0..9 are 120 + 9*40 = 480 tall; row 10 starts there.
      await renderer.render(variableList(start: 10, end: 20));

      final content =
          viewport().querySelector('[data-children]')! as web.HTMLElement;
      // 100 blocks of 480 over a thousand rows.
      expect(content.getBoundingClientRect().height, 48000);
      expect(topOf('rows/10'), 480);
      expect(topOf('rows/11'), 600);
      expect(
        web.document.getElementById('rows/10')!.getBoundingClientRect().height,
        120,
      );
      expect(
        web.document.getElementById('rows/11')!.getBoundingClientRect().height,
        40,
      );
    });

    test('a list of such rows reports pixels, not row numbers', () async {
      await renderer.render(variableList(start: 0, end: 20));
      await settle();

      // Only the Dart side knows how tall the rows outside the window are.
      expect(ranges, [
        {'offset': 0, 'viewport': 200},
      ]);
    });

    test('report the visible rows once per change', () async {
      await renderer.render(lazyList(start: 0, end: 20));
      await settle();
      expect(ranges, [
        {'first': 0, 'last': 3},
      ]);

      viewport().scrollTop = 500;
      await settle();
      viewport().dispatchEvent(web.Event('scroll'));
      expect(ranges.last, {'first': 10, 'last': 13});
      expect(ranges, hasLength(2), reason: 'the same range is not resent');

      viewport().scrollTop = 520;
      await settle();
      expect(ranges.last, {'first': 10, 'last': 14});
    });

    test('keep their scroll position when the window moves', () async {
      await renderer.render(lazyList(start: 0, end: 30));
      await settle();
      final before = viewport();
      before.scrollTop = 1000;
      await settle();

      await renderer.render(lazyList(start: 15, end: 45));

      expect(identical(viewport(), before), isTrue);
      expect(viewport().scrollTop, 1000);
      expect(web.document.getElementById('rows/0'), isNull);
      expect(topOf('rows/20'), 1000);
    });

    test('an app moves its window as the list scrolls', () async {
      final app = _RowsApp()..mount(renderer);
      await settle();
      expect(web.document.getElementById('rows/400'), isNull);

      viewport().scrollTop = 20000;
      await settle();
      await settle();

      expect(web.document.getElementById('rows/400'), isNotNull);
      expect(web.document.getElementById('rows/0'), isNull);
      expect(topOf('rows/400'), 20000);
      expect(viewport().scrollTop, 20000);
      app.unmount();
    });
  });
}
