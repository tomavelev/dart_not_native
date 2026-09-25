/// Tests for dialogs, bottom sheets and snackbars: the nodes the builders
/// produce, and the back gesture closing the one on top.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A list screen that confirms before deleting, offers row actions in a sheet
/// and reports the deletion in a snackbar.
class _InboxApp extends NativeUIApp {
  bool sheetOpen = false;
  bool confirming = false;
  bool locked = false;
  int deleted = 0;
  final List<String> dismissals = [];

  @override
  WidgetNode build() => UIBuilder.overlay(
    child: UIBuilder.scaffold(
      appBar: UIBuilder.appBar(title: 'Inbox'),
      body: UIBuilder.button(
        label: 'Actions',
        id: 'open',
        onPressed: () => setState(() => sheetOpen = true),
      ),
    ),
    overlays: [
      if (sheetOpen)
        UIBuilder.bottomSheet(
          id: 'actions',
          content: [
            UIBuilder.button(
              label: 'Delete',
              id: 'delete',
              onPressed: () => setState(() => confirming = true),
            ),
          ],
          onDismiss: () => setState(() {
            dismissals.add('sheet');
            sheetOpen = false;
          }),
        ),
      if (confirming)
        UIBuilder.dialog(
          id: 'confirm',
          title: 'Delete message?',
          content: [UIBuilder.text('This cannot be undone.')],
          actions: [
            UIBuilder.button(
              label: 'Cancel',
              id: 'cancel',
              variant: 'tertiary',
              onPressed: () => setState(() => confirming = false),
            ),
            UIBuilder.button(
              label: 'Delete',
              id: 'confirm-delete',
              onPressed: () => setState(() {
                deleted++;
                confirming = false;
                sheetOpen = false;
              }),
            ),
          ],
          dismissible: !locked,
          onDismiss: () => setState(() {
            dismissals.add('dialog');
            confirming = false;
          }),
        ),
      if (deleted > 0)
        UIBuilder.snackbar(
          id: 'deleted-$deleted',
          message: 'Message deleted',
          actionLabel: 'Undo',
          onAction: () => setState(() => deleted--),
          onDismiss: () => setState(() => dismissals.add('snackbar')),
        ),
    ],
  );
}

WidgetNode? _find(WidgetNode node, String type) {
  if (node.type == type) return node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    final found = _find(child, type);
    if (found != null) return found;
  }
  return null;
}

void main() {
  late _InboxApp app;
  late InMemoryRenderer renderer;

  Future<void> tap(String type, [String? label]) async {
    WidgetNode? search(WidgetNode node) {
      if (node.type == type &&
          (label == null || node.props['label'] == label)) {
        return node;
      }
      for (final child in (node.children ?? const <WidgetNode>[]).reversed) {
        final found = search(child);
        if (found != null) return found;
      }
      return null;
    }

    final node = search(renderer.tree!)!;
    await renderer.handleEvent(node.props['eventId'] as String, {});
  }

  setUp(() {
    SystemBack.clearHandlers();
    app = _InboxApp();
    renderer = InMemoryRenderer();
    app.mount(renderer);
  });

  tearDown(() {
    app.unmount();
    SystemBack.clearHandlers();
  });

  group('builders', () {
    test('overlay puts the screen first and overlays after it', () {
      app.setState(() => app.sheetOpen = true);
      expect(renderer.tree!.type, 'Overlay');
      expect(renderer.tree!.children!.map((c) => c.type), [
        'Scaffold',
        'BottomSheet',
      ]);
    });

    test('a dialog is a title, its content, then a row of actions', () {
      app.setState(() => app.confirming = true);
      final dialog = _find(renderer.tree!, 'Dialog')!;

      expect(dialog.props['title'], 'Delete message?');
      expect(dialog.props['dismissible'], isTrue);
      expect(dialog.props['dismissEventId'], 'cb:confirm.dismiss');
      expect(dialog.children!.map((c) => c.type), ['Column', 'Row']);
      expect(dialog.children![1].props['mainAxisAlignment'], 'end');
      expect(dialog.children![1].children!.map((c) => c.props['label']), [
        'Cancel',
        'Delete',
      ]);
    });

    test('a dialog without actions has no action row', () {
      final node = UIBuilder.dialog(
        title: 'Saved',
        content: [UIBuilder.text('ok')],
        dismissEventId: 'close',
      );
      expect(node.children!.map((c) => c.type), ['Column']);
      expect(node.props['dismissEventId'], 'close');
    });

    test('a dialog nobody can dismiss carries no dismiss event', () {
      final node = UIBuilder.dialog(title: 'Working', dismissible: false);
      expect(node.props.containsKey('dismissEventId'), isFalse);
      expect(node.props['dismissible'], isFalse);
    });

    test('a bottom sheet holds its content as children', () {
      app.setState(() => app.sheetOpen = true);
      final sheet = _find(renderer.tree!, 'BottomSheet')!;
      expect(sheet.children!.single.props['label'], 'Delete');
      expect(sheet.props['dismissEventId'], 'cb:actions.dismiss');
    });

    test('a snackbar carries its message, action and duration', () async {
      app.setState(() => app.deleted = 1);
      final snackbar = _find(renderer.tree!, 'Snackbar')!;

      expect(snackbar.props, {
        'message': 'Message deleted',
        'actionLabel': 'Undo',
        'actionEventId': 'cb:deleted-1.action',
        'dismissEventId': 'cb:deleted-1.dismiss',
        'durationMs': 4000,
        'id': 'deleted-1',
      });

      await renderer.handleEvent(snackbar.props['actionEventId'] as String, {});
      expect(app.deleted, 0);
    });

    test('a snackbar that stays until removed has a zero duration', () {
      final node = UIBuilder.snackbar(
        message: 'Offline',
        duration: Duration.zero,
      );
      expect(node.props['durationMs'], 0);
      expect(node.props.containsKey('dismissEventId'), isFalse);
    });

    test('the node types are part of the protocol', () {
      expect(
        nodeTypes,
        containsAll(['Overlay', 'Dialog', 'BottomSheet', 'Snackbar']),
      );
    });
  });

  group('the whole flow', () {
    test('open the sheet, confirm, delete, undo', () async {
      await tap('Button', 'Actions');
      await tap('Button', 'Delete');
      expect(_find(renderer.tree!, 'Dialog'), isNotNull);

      await tap('Button', 'Delete');
      expect(app.deleted, 1);
      expect(_find(renderer.tree!, 'Dialog'), isNull);
      expect(_find(renderer.tree!, 'BottomSheet'), isNull);
      expect(_find(renderer.tree!, 'Snackbar'), isNotNull);
    });
  });

  group('the back gesture', () {
    test('is not taken while nothing is open', () {
      expect(SystemBack.hasHandlers, isFalse);
      expect(SystemBack.dispatch(), isFalse);
    });

    test('closes an open sheet', () {
      app.setState(() => app.sheetOpen = true);

      expect(SystemBack.dispatch(), isTrue);
      expect(app.sheetOpen, isFalse);
      expect(app.dismissals, ['sheet']);
    });

    test('closes only the topmost overlay', () {
      app.setState(() {
        app.sheetOpen = true;
        app.confirming = true;
      });

      expect(SystemBack.dispatch(), isTrue);
      expect(app.dismissals, ['dialog']);
      expect(app.sheetOpen, isTrue);

      expect(SystemBack.dispatch(), isTrue);
      expect(app.dismissals, ['dialog', 'sheet']);
    });

    test('is released once the last overlay closes', () {
      app.setState(() => app.sheetOpen = true);
      SystemBack.dispatch();

      expect(SystemBack.hasHandlers, isFalse);
      expect(SystemBack.dispatch(), isFalse);
    });

    test('is consumed but changes nothing for a locked dialog', () {
      app.setState(() {
        app.confirming = true;
        app.locked = true;
      });

      expect(SystemBack.dispatch(), isTrue);
      expect(app.confirming, isTrue);
      expect(app.dismissals, isEmpty);
    });

    test('is offered to the overlay before a handler registered earlier', () {
      var routerPopped = false;
      SystemBack.clearHandlers();
      SystemBack.addHandler(() => routerPopped = true);
      app.setState(() => app.sheetOpen = true);

      SystemBack.dispatch();

      expect(app.sheetOpen, isFalse);
      expect(routerPopped, isFalse);
    });

    test('ignores snackbars', () {
      app.setState(() => app.deleted = 1);
      expect(SystemBack.hasHandlers, isFalse);
    });

    test('is released when the app is unmounted', () {
      app.setState(() => app.sheetOpen = true);
      app.unmount();
      expect(SystemBack.hasHandlers, isFalse);
    });
  });
}
