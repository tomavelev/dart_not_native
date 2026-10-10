/// A text field's look, on its way to a renderer: the style of what is
/// typed, the fill, the outline and the room inside. `TextField.style` and
/// `InputDecoration`'s `filled`, `fillColor`, `border` and `contentPadding`
/// were accepted and sent nowhere.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const green = Color(0xFF2E7D32);
const cream = Color(0xFFFFF8E1);

void main() {
  Map<String, dynamic> props(Widget field) =>
      AppTester.widget(Scaffold(body: field)).ofType('TextField').single.props;

  const look = [
    'textColor',
    'fontSize',
    'fontWeight',
    'fillColor',
    'border',
    'borderColor',
    'borderWidth',
    'borderRadius',
    'contentPadding',
  ];

  test('a field that says nothing about its look sends nothing about it', () {
    final sent = props(
      const TextField(decoration: InputDecoration(labelText: 'Name')),
    );

    expect(sent.keys.where(look.contains), isEmpty);
  });

  test('the style of what is typed', () {
    final sent = props(
      const TextField(
        style: TextStyle(
          color: green,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    expect(sent['textColor'], '#2e7d32');
    expect(sent['fontSize'], 20);
    expect(sent['fontWeight'], 600);
  });

  group('the fill', () {
    test('is the colour given, when the field is filled', () {
      final sent = props(
        const TextField(
          decoration: InputDecoration(filled: true, fillColor: cream),
        ),
      );

      expect(sent['fillColor'], '#fff8e1');
    });

    test('is a faint wash when filled with no colour', () {
      final sent = props(
        const TextField(decoration: InputDecoration(filled: true)),
      );

      expect(sent['fillColor'], isA<String>());
      expect((sent['fillColor'] as String).length, 9, reason: 'has an alpha');
    });

    test('is not sent for a colour on a field that is not filled, as in '
        'Flutter', () {
      final sent = props(
        const TextField(decoration: InputDecoration(fillColor: cream)),
      );

      expect(sent.containsKey('fillColor'), isFalse);
    });
  });

  group('the outline', () {
    test('none', () {
      final sent = props(
        const TextField(decoration: InputDecoration(border: InputBorder.none)),
      );

      expect(sent['border'], 'none');
      expect(sent.containsKey('borderColor'), isFalse);
    });

    test('an underline', () {
      final sent = props(
        const TextField(
          decoration: InputDecoration(border: UnderlineInputBorder()),
        ),
      );

      expect(sent['border'], 'underline');
    });

    test('a box, with its radius', () {
      final sent = props(
        TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

      expect(sent['border'], 'outline');
      expect(sent['borderRadius'], 12);
      expect(
        sent.containsKey('borderColor'),
        isFalse,
        reason: 'a side nobody chose is the renderer\'s to colour',
      );
    });

    test('a side the app chose travels with its colour and width', () {
      final sent = props(
        const TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: green, width: 2),
            ),
          ),
        ),
      );

      expect(sent['borderColor'], '#2e7d32');
      expect(sent['borderWidth'], 2);
    });

    test('enabledBorder is the one a field has at rest, and wins', () {
      final sent = props(
        const TextField(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: green),
            ),
          ),
        ),
      );

      expect(sent['border'], 'underline');
      expect(sent['borderColor'], '#2e7d32');
    });
  });

  test('the room inside', () {
    final sent = props(
      const TextField(
        decoration: InputDecoration(
          contentPadding: EdgeInsets.fromLTRB(20, 8, 4, 6),
        ),
      ),
    );

    expect(sent['contentPadding'], [20, 8, 4, 6]);
  });

  test('a TextFormField sends the same', () {
    final sent = props(
      TextFormField(
        style: const TextStyle(color: green),
        decoration: const InputDecoration(filled: true, fillColor: cream),
      ),
    );

    expect(sent['textColor'], '#2e7d32');
    expect(sent['fillColor'], '#fff8e1');
  });
}
