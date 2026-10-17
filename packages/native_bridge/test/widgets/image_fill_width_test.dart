/// An image given a width where it is laid out in a width it cannot change -
/// a list's row, a stretched column, a box with a width - is as wide as the
/// room in Flutter, and its node says so (`fillWidth`). Anywhere else the
/// width it states is its own.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _picture = 'https://example.com/a.png';

class _Framed extends StatelessWidget {
  const _Framed();
  @override
  Widget build(BuildContext context) => Image.network(_picture, width: 120);
}

void main() {
  bool? fills(Widget body) {
    final app = AppTester.widget(MaterialApp(home: Scaffold(body: body)));
    final image = app.ofType('Image').single;
    return image.props['fillWidth'] as bool?;
  }

  Widget image() => Image.network(_picture, width: 120);

  test('in a list, through padding and a padded container', () {
    expect(fills(ListView(children: [image()])), isTrue);
    expect(
      fills(
        ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(4),
                child: image(),
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  test('in a list built row by row', () {
    expect(
      fills(ListView.builder(itemCount: 1, itemBuilder: (_, _) => image())),
      isTrue,
    );
  });

  test('with builders of its own, which follow its load', () {
    expect(
      fills(
        ListView(
          children: [
            Image.network(
              _picture,
              width: 120,
              errorBuilder: (_, _, _) => const Text('gone'),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  test('through a widget of the app\'s own', () {
    expect(fills(ListView(children: const [_Framed()])), isTrue);
  });

  test('in a stretched column, a box with a width and a row\'s share', () {
    expect(
      fills(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [image()],
        ),
      ),
      isTrue,
    );
    expect(fills(SizedBox(width: 300, child: image())), isTrue);
    expect(fills(Row(children: [Expanded(child: image())])), isTrue);
  });

  test('as a scaffold\'s body, and in a scroller there', () {
    expect(fills(image()), isTrue);
    expect(fills(SingleChildScrollView(child: image())), isTrue);
    expect(
      fills(
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: image()),
      ),
      isNull,
    );
  });

  test('through a card and the widgets that leave a child\'s room alone', () {
    for (final wrap in <Widget Function(Widget)>[
      (c) => Card(child: c),
      (c) => Card(color: const Color(0xFFEEEEEE), child: c),
      (c) => GestureDetector(onTap: () {}, child: c),
      (c) => InkWell(onTap: () {}, child: c),
      (c) => Hero(tag: 'h', child: c),
      (c) => Semantics(label: 'a picture', child: c),
      (c) => Opacity(opacity: 0.5, child: c),
      (c) => ClipRRect(borderRadius: BorderRadius.circular(8), child: c),
      (c) => Tooltip(message: 'tip', child: c),
      (c) => Dismissible(key: const ValueKey('d'), child: c),
      (c) => Theme(data: ThemeData(), child: c),
      (c) => SafeArea(child: c),
    ]) {
      expect(fills(ListView(children: [wrap(image())])), isTrue);
    }
  });

  test('not in a list tile, whose parts are as wide as they ask', () {
    expect(
      fills(ListView(children: [ListTile(title: image())])),
      isNull,
    );
  });

  test('not where it is free to be its own width', () {
    expect(fills(Column(children: [image()])), isNull);
    expect(fills(Row(children: [image()])), isNull);
    expect(fills(ListView(children: [Center(child: image())])), isNull);
    expect(
      fills(
        ListView(
          children: [Container(alignment: Alignment.center, child: image())],
        ),
      ),
      isNull,
    );
    expect(
      fills(ListView(scrollDirection: Axis.horizontal, children: [image()])),
      isNull,
    );
  });

  test('not with a height of its own, which its width keeps to', () {
    expect(
      fills(
        ListView(
          children: [Image.network(_picture, width: 120, height: 80)],
        ),
      ),
      isNull,
    );
  });
}
