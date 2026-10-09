/// `Image.errorBuilder` in the widget layer: built once, up front, and sent
/// with the image as the fallback a renderer shows in its place.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

WidgetNode _tree(Widget widget) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  return renderer.tree!;
}

void main() {
  test('the builder\'s widget travels as the image\'s one child', () {
    Object? error;
    StackTrace? trace = StackTrace.current;
    final tree = _tree(
      Image.network(
        'https://example.com/a.png',
        width: 40,
        height: 40,
        errorBuilder: (context, e, s) {
          error = e;
          trace = s;
          return const Text('?');
        },
      ),
    );

    final image = nodesOfType(tree, 'Image').single;
    expect(image.children, hasLength(1));
    expect(image.children!.single.type, 'Text');
    expect(image.children!.single.props['content'], '?');
    // There is no real error to hand over, and the builder is told so.
    expect(error, isA<ImageLoadFailure>());
    expect((error! as ImageLoadFailure).src, 'https://example.com/a.png');
    expect(trace, isNull);
  });

  test('an asset image takes one too', () {
    final tree = _tree(
      Image.asset(
        'assets/logo.png',
        errorBuilder: (context, error, stack) => const Icon(Icons.image),
      ),
    );
    expect(nodesOfType(tree, 'Image').single.children!.single.type, 'Icon');
  });

  test('an image without a builder has no child, as before', () {
    final tree = _tree(Image.network('https://example.com/a.png'));
    expect(nodesOfType(tree, 'Image').single.children, isNull);
  });

  test('the builder can read what is above the image', () {
    final tree = _tree(
      MaterialApp(
        locale: const Locale('ar'),
        home: Image.network(
          'https://example.com/a.png',
          errorBuilder: (context, error, stack) =>
              Text(Directionality.of(context).name),
        ),
      ),
    );
    expect(hasText(tree, 'rtl'), isTrue);
  });

  test('loadingBuilder and frameBuilder are accepted and never called', () {
    var called = false;
    _tree(
      Image.network(
        'https://example.com/a.png',
        loadingBuilder: (context, child, progress) {
          called = true;
          return child;
        },
        frameBuilder: (context, child, frame, sync) {
          called = true;
          return child;
        },
      ),
    );
    expect(called, isFalse);
  });

  test('a disabled checkbox built by hand needs no handler', () {
    final renderer = InMemoryRenderer();
    final app = _Disabled()..mount(renderer);
    addTearDown(app.unmount);
    final box = nodesOfType(renderer.tree!, 'Checkbox').single;
    expect(box.props['disabled'], isTrue);
    expect(box.props['eventId'], isA<String>());
  });
}

class _Disabled extends NativeUIApp {
  @override
  WidgetNode build() => UIBuilder.checkbox(checked: true, disabled: true);
}
