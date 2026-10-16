/// A `Container` around a scroll view fills the room it is offered, as the
/// scroll view itself does in Flutter. It used to hug the list, which on the
/// web then grew to its full length and never scrolled.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? expandOf(Widget list) {
    final app = AppTester.widget(
      Column(
        children: [
          Expanded(
            child: Container(
              key: const ValueKey('paint'),
              color: const Color(0xFFE0E0E0),
              child: list,
            ),
          ),
        ],
      ),
    );
    return app.get('paint').props['expand'] as String?;
  }

  test('a list fills it', () {
    expect(
      expandOf(
        ListView.builder(itemCount: 9, itemBuilder: (_, i) => Text('$i')),
      ),
      'both',
    );
    expect(expandOf(ListView(children: const [Text('a')])), 'both');
    expect(expandOf(const CustomScrollView()), 'both');
  });

  test("one that shrink-wraps, or a single child's scroll view, does not", () {
    expect(
      expandOf(ListView(shrinkWrap: true, children: const [Text('a')])),
      isNot('both'),
    );
    expect(
      expandOf(const SingleChildScrollView(child: Text('a'))),
      isNot('both'),
    );
  });
}
