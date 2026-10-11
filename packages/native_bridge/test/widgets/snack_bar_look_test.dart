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
}
