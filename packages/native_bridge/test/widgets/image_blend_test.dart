/// `Image.colorBlendMode` travels as the node's `blend`, by Flutter's name,
/// and only when it says something `srcIn` does not.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

Map<String, dynamic> _props(Widget widget) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  return nodesOfType(renderer.tree!, 'Image').single.props;
}

void main() {
  test('a tint blended some other way says how', () {
    final props = _props(
      Image.network(
        'https://example.com/a.png',
        color: const Color(0xFF2196F3),
        colorBlendMode: BlendMode.multiply,
      ),
    );
    expect(props['color'], isNotNull);
    expect(props['blend'], 'multiply');
  });

  test('every mode goes by its own name', () {
    for (final mode in BlendMode.values.where((m) => m != BlendMode.srcIn)) {
      final props = _props(
        Image.asset(
          'assets/a.png',
          color: const Color(0xFF000000),
          colorBlendMode: mode,
        ),
      );
      expect(props['blend'], mode.name);
    }
  });

  test('srcIn, or no mode, is the default and is not sent', () {
    for (final mode in [null, BlendMode.srcIn]) {
      final props = _props(
        Image.network(
          'https://example.com/a.png',
          color: const Color(0xFF2196F3),
          colorBlendMode: mode,
        ),
      );
      expect(props.containsKey('blend'), isFalse);
    }
  });

  test('a mode with no colour is nothing to blend', () {
    final props = _props(
      Image.network(
        'https://example.com/a.png',
        colorBlendMode: BlendMode.multiply,
      ),
    );
    expect(props.containsKey('color'), isFalse);
    expect(props.containsKey('blend'), isFalse);
  });
}
