/// `Image`'s three builders follow the load as a renderer reports it: the
/// loading builder's widget stands in while the picture is on its way, the
/// error builder is asked only once it has failed, and the frame builder
/// hears of the first frame.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

class _Shown {
  _Shown(Widget widget) {
    final app = hostApp(widget)..mount(renderer);
    addTearDown(app.unmount);
  }

  final InMemoryRenderer renderer = InMemoryRenderer();

  WidgetNode get tree => renderer.tree!;
  WidgetNode get image => nodesOfType(tree, 'Image').single;
  WidgetNode? get standIn => image.children?.singleOrNull;

  /// What a renderer says once it knows how the load went.
  Future<void> report(String state) async {
    await renderer.handleEvent(image.props['eventId'] as String, {
      'state': state,
    });
    await pumpEventQueue();
  }
}

var _serial = 0;

/// A picture nothing has loaded yet, so each test starts with a wait.
String _fresh() => 'https://example.com/${_serial++}.png';

void main() {
  test('an image without a builder is not followed, and has no child', () {
    final shown = _Shown(Image.network(_fresh()));
    expect(shown.image.children, isNull);
    expect(shown.image.props.containsKey('eventId'), isFalse);
  });

  group('loadingBuilder hears how far', () {
    test('the node asks to be told, and each report is a call', () async {
      final heard = <(int, int?)>[];
      final shown = _Shown(
        Image.network(
          _fresh(),
          loadingBuilder: (context, child, progress) {
            if (progress != null) {
              heard.add((
                progress.cumulativeBytesLoaded,
                progress.expectedTotalBytes,
              ));
            }
            return const Text('…');
          },
        ),
      );
      expect(shown.image.props['progress'], isTrue);
      await shown.renderer.handleEvent(
        shown.image.props['eventId'] as String,
        {'state': 'loading', 'loaded': 4000, 'expected': 10000},
      );
      await pumpEventQueue();

      expect(heard.last, (4000, 10000));
    });

    test('an image with no loadingBuilder does not ask', () {
      final shown = _Shown(
        Image.network(_fresh(), errorBuilder: (_, _, _) => const Text('?')),
      );
      expect(shown.image.props.containsKey('progress'), isFalse);
    });
  });

  group('errorBuilder', () {
    test('is not asked while the image is on its way', () {
      var asked = 0;
      final shown = _Shown(
        Image.network(
          _fresh(),
          errorBuilder: (context, error, stack) {
            asked++;
            return const Text('?');
          },
        ),
      );

      expect(asked, 0);
      expect(hasText(shown.tree, '?'), isFalse);
      // Something still stands in, so no renderer writes the description
      // over a picture that is only late.
      expect(shown.standIn?.type, 'SizedBox');
    });

    test('is asked once the load has failed, and its widget stands in', () async {
      Object? error;
      StackTrace? trace = StackTrace.current;
      final src = _fresh();
      final shown = _Shown(
        Image.network(
          src,
          width: 40,
          height: 40,
          errorBuilder: (context, e, s) {
            error = e;
            trace = s;
            return const Text('?');
          },
        ),
      );

      await shown.report('failed');

      expect(shown.standIn?.type, 'Text');
      expect(shown.standIn?.props['content'], '?');
      // The renderer says that it failed, not why.
      expect(error, isA<ImageLoadFailure>());
      expect((error! as ImageLoadFailure).src, src);
      expect(trace, isNull);
    });

    test('is never asked for an image that loads', () async {
      var asked = 0;
      final shown = _Shown(
        Image.network(
          _fresh(),
          errorBuilder: (context, error, stack) {
            asked++;
            return const Text('?');
          },
        ),
      );

      await shown.report('loaded');
      expect(asked, 0);
    });

    test('an asset that is not there is told too', () async {
      final shown = _Shown(
        Image.asset(
          'assets/missing.png',
          errorBuilder: (context, error, stack) => const Icon(Icons.image),
        ),
      );
      expect(nodesOfType(shown.tree, 'Icon'), isEmpty);

      await shown.report('failed');
      expect(shown.standIn?.type, 'Icon');
    });

    test('can read what is above the image', () async {
      final shown = _Shown(
        MaterialApp(
          locale: const Locale('ar'),
          home: Image.network(
            _fresh(),
            errorBuilder: (context, error, stack) =>
                Text(Directionality.of(context).name),
          ),
        ),
      );

      await shown.report('failed');
      expect(hasText(shown.tree, 'rtl'), isTrue);
    });

    test('a new picture in the same place starts again', () async {
      late StateSetter rebuild;
      var src = _fresh();
      final shown = _Shown(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Image.network(
              src,
              errorBuilder: (context, error, stack) => const Text('?'),
            );
          },
        ),
      );
      await shown.report('failed');
      expect(hasText(shown.tree, '?'), isTrue);

      rebuild(() => src = _fresh());
      await pumpEventQueue();
      expect(hasText(shown.tree, '?'), isFalse);
    });
  });

  group('loadingBuilder', () {
    Widget picture(String src, List<String> calls) => Image.network(
      src,
      loadingBuilder: (context, child, progress) {
        calls.add(
          progress == null
              ? 'there'
              : 'waiting ${progress.cumulativeBytesLoaded}'
                    '/${progress.expectedTotalBytes}',
        );
        return progress == null
            ? Container(key: const ValueKey('around'), child: child)
            : const Text('loading');
      },
    );

    test('what it returns for the wait stands in the image\'s place', () {
      final calls = <String>[];
      final shown = _Shown(picture(_fresh(), calls));

      expect(calls, ['waiting 0/null']);
      expect(shown.standIn?.props['content'], 'loading');
    });

    test('and once the picture is there it wraps the image', () async {
      final calls = <String>[];
      final shown = _Shown(picture(_fresh(), calls));

      await shown.report('loaded');

      expect(calls.last, 'there');
      expect(hasText(shown.tree, 'loading'), isFalse);
      final around = nodeById(shown.tree, 'around')!;
      expect(nodesOfType(around, 'Image'), hasLength(1));
    });

    test('a picture seen before is there at once', () async {
      final src = _fresh();
      await _Shown(picture(src, [])).report('loaded');

      final calls = <String>[];
      _Shown(picture(src, calls));
      expect(calls, ['there']);
    });

    test('an asset has no wait', () {
      final calls = <String>[];
      _Shown(
        Image.asset(
          'assets/logo.png',
          loadingBuilder: (context, child, progress) {
            calls.add('$progress');
            return child;
          },
        ),
      );
      expect(calls, ['null']);
    });

    test('a failure ends the wait', () async {
      final calls = <String>[];
      final shown = _Shown(picture(_fresh(), calls));

      await shown.report('failed');
      expect(hasText(shown.tree, 'loading'), isFalse);
    });
  });

  group('frameBuilder', () {
    test('hears no frame, then the first', () async {
      final calls = <String>[];
      final shown = _Shown(
        Image.network(
          _fresh(),
          frameBuilder: (context, child, frame, sync) {
            calls.add('$frame $sync');
            return Container(key: const ValueKey('frame'), child: child);
          },
        ),
      );
      expect(calls, ['null false']);
      // The image is inside the frame while it loads: that is how it loads.
      expect(nodesOfType(nodeById(shown.tree, 'frame')!, 'Image'), hasLength(1));

      await shown.report('loaded');
      expect(calls.last, '0 false');
    });

    test('an image with nothing to fetch was there from the start', () {
      final calls = <String>[];
      _Shown(
        Image.asset(
          'assets/logo.png',
          frameBuilder: (context, child, frame, sync) {
            calls.add('$frame $sync');
            return child;
          },
        ),
      );
      expect(calls, ['0 true']);
    });

    test('the loading builder wraps what the frame builder made', () async {
      final order = <String>[];
      final shown = _Shown(
        Image.network(
          _fresh(),
          frameBuilder: (context, child, frame, sync) {
            order.add('frame');
            return child;
          },
          loadingBuilder: (context, child, progress) {
            order.add('loading');
            return child;
          },
        ),
      );
      await shown.report('loaded');
      expect(order.sublist(order.length - 2), ['frame', 'loading']);
    });
  });

  test('the same answer twice is one rebuild', () async {
    var builds = 0;
    final shown = _Shown(
      Image.network(
        _fresh(),
        frameBuilder: (context, child, frame, sync) {
          builds++;
          return child;
        },
      ),
    );
    await shown.report('loaded');
    final after = builds;
    await shown.report('loaded');
    expect(builds, after);
  });
}
