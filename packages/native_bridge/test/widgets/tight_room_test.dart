/// A box laid out in a width it cannot change - a list's row, a stretched
/// column, a row's `Expanded` - is that wide whatever width it asks for, as
/// in Flutter. Anywhere else the width it states is its own.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WidgetNode boxIn(Widget body) {
    final app = AppTester.widget(MaterialApp(home: Scaffold(body: body)));
    return app.nodes.firstWhere(
      (n) => n.type == 'Box' && n.props['color'] != null,
    );
  }

  Widget sized() => Container(
    width: 120,
    height: 40,
    color: const Color(0xFF2196F3),
    child: const Text('a'),
  );

  test('a container with a width fills a list row and a stretched column', () {
    for (final body in <Widget>[
      ListView(children: [sized()]),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [sized()],
      ),
      Row(children: [Expanded(child: sized())]),
      ListView(children: [Padding(padding: const EdgeInsets.all(8), child: sized())]),
      ListView(children: [Opacity(opacity: 0.5, child: sized())]),
      ListView(children: [AnimatedOpacity(opacity: 1, duration: Duration.zero, child: sized())]),
    ]) {
      final box = boxIn(body);
      expect(box.props['width'], isNull, reason: '$body');
      expect(box.props['expand'], 'width', reason: '$body');
      expect(box.props['height'], 40);
    }
  });

  test('a cap on the width gives way too', () {
    final box = boxIn(
      ListView(
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 200),
            color: const Color(0xFF2196F3),
            child: const Text('a'),
          ),
        ],
      ),
    );
    expect(box.props['maxWidth'], isNull);
    expect(box.props['expand'], 'width');
  });

  test('a sized box with a child fills it; an empty one stays a spacer', () {
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SizedBox(width: 100, child: Text('in')),
              SizedBox(width: 30, height: 8),
            ],
          ),
        ),
      ),
    );
    final box = app.nodes.firstWhere(
      (n) => n.type == 'Box' && (n.children ?? const []).any((c) => c.type == 'Text'),
    );
    expect(box.props['width'], isNull);
    expect(box.props['expand'], 'width');
    expect(app.ofType('SizedBox').single.props['width'], 30);
  });

  test('not where it is free to be its own width', () {
    for (final body in <Widget>[
      Column(children: [sized()]),
      Row(children: [sized()]),
      ListView(children: [Center(child: sized())]),
      ListView(children: [Align(alignment: Alignment.centerLeft, child: sized())]),
      ListView(scrollDirection: Axis.horizontal, children: [sized()]),
      ListView(children: [ListTile(title: sized())]),
    ]) {
      expect(boxIn(body).props['width'], 120, reason: '$body');
    }
  });
}
