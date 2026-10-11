/// A run of text that can be tapped - a link inside a paragraph. `TextSpan`
/// had no `recognizer`, so an app with one did not compile.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Map<String, dynamic>> spansOf(AppTester app) => [
    for (final span in app.ofType('Text').single.props['spans'] as List)
      Map<String, dynamic>.from(span as Map),
  ];

  test('a run with a tap recogniser carries an event, and sends it', () async {
    var terms = 0;
    final app = AppTester.widget(
      Text.rich(
        TextSpan(
          text: 'You accept the ',
          children: [
            TextSpan(
              text: 'terms',
              recognizer: TapGestureRecognizer()..onTap = () => terms++,
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
    final spans = spansOf(app);

    expect(spans.map((span) => span['text']), ['You accept the ', 'terms', '.']);
    expect(spans[0].containsKey('eventId'), isFalse);
    expect(spans[2].containsKey('eventId'), isFalse);

    await app.emit(spans[1]['eventId'] as String);

    expect(terms, 1);
  });

  test('two links in one text send two different events', () async {
    final tapped = <String>[];
    final app = AppTester.widget(
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Terms',
              recognizer: TapGestureRecognizer()
                ..onTap = () => tapped.add('terms'),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'privacy',
              recognizer: TapGestureRecognizer()
                ..onTap = () => tapped.add('privacy'),
            ),
          ],
        ),
      ),
    );
    final spans = spansOf(app);

    await app.emit(spans[2]['eventId'] as String);
    await app.emit(spans[0]['eventId'] as String);

    expect(tapped, ['privacy', 'terms']);
  });

  test('a recogniser is its own span\'s, not its children\'s', () {
    final app = AppTester.widget(
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Link',
              recognizer: TapGestureRecognizer()..onTap = () {},
              children: const [TextSpan(text: ' and not a link')],
            ),
          ],
        ),
      ),
    );
    final spans = spansOf(app);

    expect(spans[0]['eventId'], isA<String>());
    expect(spans[1].containsKey('eventId'), isFalse);
  });

  test('the root span alone can be the link', () async {
    var taps = 0;
    final app = AppTester.widget(
      Text.rich(
        TextSpan(
          text: 'All of it',
          recognizer: TapGestureRecognizer()..onTap = () => taps++,
        ),
      ),
    );

    await app.emit(spansOf(app).single['eventId'] as String);

    expect(taps, 1);
  });

  test('a keyed text keeps a link\'s event from build to build', () {
    Widget text() => Text.rich(
      key: const ValueKey('legal'),
      TextSpan(
        children: [
          const TextSpan(text: 'See the '),
          TextSpan(
            text: 'terms',
            recognizer: TapGestureRecognizer()..onTap = () {},
          ),
        ],
      ),
    );

    final first = spansOf(AppTester.widget(text()))[1]['eventId'];
    final second = spansOf(AppTester.widget(text()))[1]['eventId'];

    expect(first, second);
    expect(first, contains('legal'));
  });

  test('a text with no recogniser says nothing of events', () {
    final app = AppTester.widget(
      const Text.rich(
        TextSpan(text: 'Plain ', children: [TextSpan(text: 'runs')]),
      ),
    );

    expect(spansOf(app).any((span) => span.containsKey('eventId')), isFalse);
  });

  test('dispose is there to be called, as Flutter asks', () {
    expect(() => TapGestureRecognizer().dispose(), returnsNormally);
  });
}
