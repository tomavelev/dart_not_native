/// Choosing one of a few things, through the widget layer.
///
/// The bar reports a tap; what the tab shows is the app's own tree, so the
/// selection lives where the rest of the app's state does.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Mailbox extends StatefulWidget {
  const _Mailbox();

  @override
  State<_Mailbox> createState() => _MailboxState();
}

class _MailboxState extends State<_Mailbox> {
  int tab = 0;

  static const _names = ['All', 'Unread', 'Archived'];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            Tabs(
              key: const ValueKey('folders'),
              tabs: _names,
              selectedIndex: tab,
              onChanged: (index) => setState(() => tab = index),
            ),
            Text('showing ${_names[tab]}', key: const ValueKey('body')),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Mailbox())));

  WidgetNode bar() => tester.get('folders');

  test('carries its labels and which one is selected', () {
    expect(bar().props['tabs'], ['All', 'Unread', 'Archived']);
    expect(bar().props['selectedIndex'], 0);
    expect(tester.text('body'), 'showing All');
  });

  test('a tap moves the selection, and the screen with it', () async {
    await tester.emit(tester.eventIdOf('folders'), {'index': 2});

    expect(bar().props['selectedIndex'], 2);
    expect(tester.text('body'), 'showing Archived');
  });

  test('the bar never disagrees with the screen below it', () async {
    // The renderers do not keep a selection of their own: the tree says which
    // tab is selected, so a tap that the app ignores changes nothing.
    await tester.emit(tester.eventIdOf('folders'), {'index': 1});
    expect(bar().props['selectedIndex'], 1);

    await tester.emit(tester.eventIdOf('folders'), {'index': 1});
    expect(bar().props['selectedIndex'], 1);
    expect(tester.text('body'), 'showing Unread');
  });
}
