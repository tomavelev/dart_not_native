/// The inbox: a ten-thousand-row list, row actions in a sheet, a confirmed
/// delete and an undo snackbar - driven the way a renderer would.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/inbox_example_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

void main() {
  late NativeUIApp app;
  late AppTester tester;

  WidgetNode list() => tester.ofType('LazyList').single;

  /// The id of the first visible row's actions button, e.g. 'actions_1'.
  String firstActions() => tester.ofType('IconButton').first.props['id'] as String;

  Future<void> reportVisible(int first, int last) => tester.emit(
    list().props['rangeEventId'] as String,
    {'first': first, 'last': last},
  );

  Future<void> dismiss(String type, String reason) {
    final overlay = tester.ofType(type).single;
    return tester.emit(overlay.props['dismissEventId'] as String, {
      'reason': reason,
    });
  }

  setUp(() {
    SystemBack.clearHandlers();
    tester = AppTester.mount(app = hostApp(const InboxApp()));
  });

  tearDown(() {
    app.unmount();
    SystemBack.clearHandlers();
  });

  group('the list', () {
    test('holds ten thousand messages but builds a window of them', () {
      expect(list().props['itemCount'], 10000);
      expect(list().children, hasLength(30));
      expect(tester.hasText('Message 1'), isTrue);
      expect(tester.hasText('Message 31'), isFalse);
    });

    test('scrolling far down brings those rows in', () async {
      await reportVisible(7000, 7010);

      expect(tester.hasText('Message 7001'), isTrue);
      expect(tester.hasText('Message 1'), isFalse);
      expect(tester.find('actions_7001'), isNotNull);
    });

    test('the unread count is in the title', () {
      expect(
        tester.ofType('AppBar').single.props['title'],
        'Inbox (6667 unread)',
      );
    });
  });

  group('deleting', () {
    test('opens the sheet, asks, deletes and offers undo', () async {
      await tester.tap('actions_2');
      expect(tester.text('sheet_title'), 'Message 2');

      await tester.tap('sheet_delete');
      expect(tester.ofType('Dialog').single.props['title'], 'Delete message?');

      await tester.tap('confirm_ok');
      expect(tester.ofType('Dialog'), isEmpty);
      expect(tester.ofType('BottomSheet'), isEmpty);
      expect(
        tester.ofType('Snackbar').single.props['message'],
        'Message deleted',
      );
      expect(list().props['itemCount'], 9999);
      expect(tester.hasText('Message 2'), isFalse);
    });

    test('undo puts the message back where it was', () async {
      await tester.tap('actions_2');
      await tester.tap('sheet_delete');
      await tester.tap('confirm_ok');

      final snackbar = tester.ofType('Snackbar').single;
      await tester.emit(snackbar.props['actionEventId'] as String);

      expect(list().props['itemCount'], 10000);
      expect(tester.hasText('Message 2'), isTrue);
      expect(tester.ofType('Snackbar'), isEmpty);
    });

    test('cancel keeps the message and the sheet', () async {
      await tester.tap('actions_2');
      await tester.tap('sheet_delete');
      await tester.tap('confirm_cancel');

      expect(tester.ofType('Dialog'), isEmpty);
      expect(tester.ofType('BottomSheet'), hasLength(1));
      expect(list().props['itemCount'], 10000);
    });

    test('each deletion is a new snackbar', () async {
      Future<String> deleteFirst() async {
        await tester.tap(firstActions());
        await tester.tap('sheet_delete');
        await tester.tap('confirm_ok');
        return tester.ofType('Snackbar').single.props['id'] as String;
      }

      expect(await deleteFirst(), isNot(await deleteFirst()));
    });

    test('the snackbar timing out leaves the deletion in place', () async {
      await tester.tap('actions_2');
      await tester.tap('sheet_delete');
      await tester.tap('confirm_ok');

      await dismiss('Snackbar', 'timeout');

      expect(tester.ofType('Snackbar'), isEmpty);
      expect(list().props['itemCount'], 9999);
    });
  });

  group('dismissing', () {
    test('a tap on the scrim closes the sheet', () async {
      await tester.tap('actions_2');
      await dismiss('BottomSheet', 'scrim');
      expect(tester.ofType('BottomSheet'), isEmpty);
    });

    test('back closes the dialog first, then the sheet', () async {
      await tester.tap('actions_2');
      await tester.tap('sheet_delete');

      expect(SystemBack.dispatch(), isTrue);
      expect(tester.ofType('Dialog'), isEmpty);
      expect(tester.ofType('BottomSheet'), hasLength(1));

      expect(SystemBack.dispatch(), isTrue);
      expect(tester.ofType('BottomSheet'), isEmpty);

      expect(SystemBack.dispatch(), isFalse);
    });

    test('marking as read closes the sheet and updates the row', () async {
      await tester.tap('actions_1');
      await tester.tap('sheet_toggle_read');

      expect(tester.ofType('BottomSheet'), isEmpty);
      // Message 1 (unread) became read, so the unread count drops by one.
      expect(
        tester.ofType('AppBar').single.props['title'],
        'Inbox (6666 unread)',
      );
    });
  });
}
