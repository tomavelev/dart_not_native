/// A snackbar's look: its fill, its message's colour, its action's and how
/// round it is. `SnackBar.backgroundColor` and `shape`, and
/// `SnackBarAction.textColor`, were accepted and sent nowhere.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Map<String, dynamic>> shown(SnackBar bar) async {
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('show'),
              onPressed: () =>
                  ScaffoldMessenger.of(context).showSnackBar(bar),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );
    await app.tap('show');
    return app.ofType('Snackbar').single.props;
  }

  test('says nothing of a look it was not given', () async {
    final props = await shown(const SnackBar(content: Text('Saved')));

    expect(props['message'], 'Saved');
    for (final key in [
      'backgroundColor',
      'textColor',
      'actionColor',
      'borderRadius',
    ]) {
      expect(props.containsKey(key), isFalse, reason: key);
    }
  });

  test('carries its fill, its message\'s colour and its action\'s', () async {
    final props = await shown(
      SnackBar(
        backgroundColor: const Color(0xFF2E7D32),
        content: const Text(
          'Saved',
          style: TextStyle(color: Color(0xFFFFFDE7)),
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFFFFEB3B),
          onPressed: () {},
        ),
      ),
    );

    expect(props['backgroundColor'], '#2e7d32');
    expect(props['textColor'], '#fffde7');
    expect(props['actionColor'], '#ffeb3b');
  });

  test('a rounded shape is its radius, and a stadium as round as it gets',
      () async {
    final rounded = await shown(
      const SnackBar(
        content: Text('Saved'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
    final stadium = await shown(
      const SnackBar(content: Text('Saved'), shape: StadiumBorder()),
    );

    expect(rounded['borderRadius'], 12);
    expect(stadium['borderRadius'], 999);
  });

  test('a width is carried, and none is none', () async {
    final narrow = await shown(
      const SnackBar(content: Text('Saved'), width: 280),
    );
    final plain = await shown(const SnackBar(content: Text('Saved')));

    expect(narrow['width'], 280);
    expect(plain.containsKey('width'), isFalse);
  });

  test('a margin, a fixed bar and an elevation are carried', () async {
    final floating = await shown(
      const SnackBar(
        content: Text('Saved'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(40, 0, 24, 30),
        elevation: 0,
      ),
    );
    final fixed = await shown(
      const SnackBar(
        content: Text('Saved'),
        behavior: SnackBarBehavior.fixed,
      ),
    );

    expect(floating['margin'], [40.0, 0.0, 24.0, 30.0]);
    expect(floating['elevation'], 0);
    expect(floating.containsKey('fixed'), isFalse);
    expect(fixed['fixed'], isTrue);
    expect(fixed.containsKey('margin'), isFalse);
    expect(fixed.containsKey('elevation'), isFalse);
  });

  group('over a nested scaffold\'s bottom bar', () {
    Future<Map<String, dynamic>> shownOver(
      Widget bottom, {
      bool button = false,
      SnackBar bar = const SnackBar(content: Text('Hi')),
      double? measured,
    }) async {
      final app = AppTester.widget(
        MaterialApp(
          home: Scaffold(
            body: Scaffold(
              bottomNavigationBar: bottom,
              floatingActionButton: button
                  ? FloatingActionButton(
                      onPressed: () {},
                      child: const Icon(Icons.add),
                    )
                  : null,
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('show'),
                  onPressed: () =>
                      ScaffoldMessenger.of(context).showSnackBar(bar),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        ),
      );
      if (measured != null) {
        // The renderer says how tall the bar came out.
        final bar = app.nodes.lastWhere(
          (n) => n.props['sizeEventId'] != null,
        );
        await app.emit(bar.props['sizeEventId'] as String, {
          'width': 360.0,
          'height': measured,
        });
      }
      await app.tap('show');
      return app.ofType('Snackbar').single.props;
    }

    const destinations = [
      NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.search), label: 'Find'),
    ];

    test('the bar is told to stay above a navigation bar', () async {
      final props = await shownOver(
        const NavigationBar(destinations: destinations),
      );

      expect(props['margin'], [16.0, 0.0, 16.0, 96.0]);
    });

    test('at the height the navigation bar says it has', () async {
      final props = await shownOver(
        const NavigationBar(destinations: destinations, height: 64),
      );

      expect(props['margin'], [16.0, 0.0, 16.0, 80.0]);
    });

    test('any other bar is taken to be the usual height', () async {
      final props = await shownOver(
        const SizedBox(height: 56, child: Text('a bar of the app\'s own')),
      );

      expect(props['margin'], [16.0, 0.0, 16.0, 72.0]);
    });

    test('once the bar has been measured, at the height it came to',
        () async {
      final props = await shownOver(
        const SizedBox(height: 56, child: Text('a bar of the app\'s own')),
        measured: 73,
      );

      expect(props['margin'], [16.0, 0.0, 16.0, 89.0]);
    });

    test('and above the button as well when there are both', () async {
      final props = await shownOver(
        const NavigationBar(destinations: destinations),
        button: true,
      );

      expect(props['margin'], [16.0, 0.0, 16.0, 160.0]);
    });
  });

  group('over a nested scaffold\'s floating button', () {
    Future<Map<String, dynamic>> shownOverNested(
      SnackBar bar, {
      bool button = true,
    }) async {
      final app = AppTester.widget(
        MaterialApp(
          home: Scaffold(
            body: Scaffold(
              floatingActionButton: button
                  ? FloatingActionButton(
                      onPressed: () {},
                      child: const Icon(Icons.add),
                    )
                  : null,
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('show'),
                  onPressed: () =>
                      ScaffoldMessenger.of(context).showSnackBar(bar),
                  child: const Text('Show'),
                ),
              ),
            ),
          ),
        ),
      );
      await app.tap('show');
      return app.ofType('Snackbar').single.props;
    }

    test('the bar is told to stay above it', () async {
      final props = await shownOverNested(const SnackBar(content: Text('Hi')));

      expect(props['margin'], [16.0, 0.0, 16.0, 80.0]);
    });

    test('on top of a margin of its own', () async {
      final props = await shownOverNested(
        const SnackBar(
          content: Text('Hi'),
          margin: EdgeInsets.fromLTRB(40, 0, 24, 30),
        ),
      );

      expect(props['margin'], [40.0, 0.0, 24.0, 94.0]);
    });

    test('a fixed bar takes no notice of a button', () async {
      final props = await shownOverNested(
        const SnackBar(content: Text('Hi'), behavior: SnackBarBehavior.fixed),
      );

      expect(props.containsKey('margin'), isFalse);
    });

    test('and with no button there is nothing to clear', () async {
      final props = await shownOverNested(
        const SnackBar(content: Text('Hi')),
        button: false,
      );

      expect(props.containsKey('margin'), isFalse);
    });
  });
}
