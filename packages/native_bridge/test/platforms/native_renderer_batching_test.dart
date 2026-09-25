/// Tests that the native renderers coalesce a tick's renders into one message.
///
/// Each render crosses a platform channel and rebuilds the native view tree,
/// so this is the difference between one rebuild and one per state change.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/android_renderer.dart';
import 'package:dart_not_native/platforms/ios_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.programtom.dart_not_native/renderer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  // A fresh renderer per test: they remember whether the native side has been
  // initialised, so sharing one would hide the first-render behaviour.
  final factories = <String, NativeUIRenderer Function()>{
    'AndroidNativeRenderer': AndroidNativeRenderer.new,
    'iOSNativeRenderer': iOSNativeRenderer.new,
  };

  WidgetNode tree(String label) => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: label),
    body: UIBuilder.text(label, id: 'label'),
  );

  factories.forEach((name, create) {
    group(name, () {
      late NativeUIRenderer renderer;

      setUp(() => renderer = create());

      test(
        'the first render initialises the native side, then renders',
        () async {
          await renderer.render(tree('one'));

          expect(calls.map((c) => c.method), ['initialize', 'render']);
        },
      );

      test('later renders do not initialise again', () async {
        await renderer.render(tree('one'));
        calls.clear();

        await renderer.render(tree('two'));

        expect(calls.map((c) => c.method), ['render']);
      });

      test('a burst in one tick sends only the last tree', () async {
        renderer.render(tree('first'));
        renderer.render(tree('second'));
        await renderer.render(tree('third'));

        final renders = calls.where((c) => c.method == 'render').toList();
        expect(renders, hasLength(1));
        // The channel decodes to loosely typed maps, so the tree is read the
        // way the native side reads it.
        final sent = renders.single.arguments as Map;
        final appBar = (sent['children'] as List).first as Map;
        expect((appBar['props'] as Map)['title'], 'third');
      });

      test('renders in separate ticks each send a message', () async {
        await renderer.render(tree('first'));
        await renderer.render(tree('second'));

        expect(calls.where((c) => c.method == 'render'), hasLength(2));
      });

      test(
        'the future completes only once the message has been sent',
        () async {
          final pending = renderer.render(tree('one'));

          expect(calls, isEmpty, reason: 'the send is deferred to the flush');
          await pending;
          expect(calls.map((c) => c.method), ['initialize', 'render']);
        },
      );

      test('a platform failure is reported, not thrown', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
              throw PlatformException(code: 'boom');
            });

        final error = await renderer.render(tree('one'));
        expect(error, isNotNull);
        expect(error!.kind, RenderErrorKind.renderFailed);
        expect(error.message, startsWith('Render error'));
        // The thrown object is kept, so a host can inspect it rather than
        // re-parse the message it was flattened into.
        expect(error.cause, isA<PlatformException>());
      });

      test('an unknown node type comes back as the types, not a sentence',
          () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
              if (call.method == 'render') {
                return {
                  'unknownTypes': ['Hologram', 'Sparkline'],
                };
              }
              return null;
            });

        final error = await renderer.render(tree('one'));
        expect(error!.kind, RenderErrorKind.unknownNodeType);
        expect(error.nodeTypes, {'Hologram', 'Sparkline'});
      });
    });
  });

  _eventsFromNative();

  test('an unbatched renderer sends every render', () async {
    final renderer = AndroidNativeRenderer(batched: false);

    renderer.render(tree('first'));
    renderer.render(tree('second'));
    await Future<void>.delayed(Duration.zero);

    expect(
      calls.where((c) => c.method == 'render'),
      hasLength(2),
      reason: 'unbatched renders reach the platform immediately',
    );
  });
}

/// The other half of the channel: events the native views produce.
void _eventsFromNative() {
  group('events from the native side', () {
    late AndroidNativeRenderer renderer;

    setUp(() => renderer = AndroidNativeRenderer());

    /// Delivers an event the way the native renderer sends it.
    Future<void> sendFromNative(
      String eventId,
      Map<String, Object?> data,
    ) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('event', {'eventId': eventId, 'data': data}),
            ),
            null,
          );
    }

    test('reach the handler the app registered', () async {
      final received = <Map<String, dynamic>>[];
      renderer.onEvent('increment', received.add);

      await sendFromNative('increment', {'by': 2});

      expect(received, [
        {'by': 2},
      ]);
    });

    test('an event with no payload still arrives', () async {
      var calls = 0;
      renderer.onEvent('tap', (_) => calls++);

      await sendFromNative('tap', {});

      expect(calls, 1);
    });

    test('an event nobody handles is ignored, not fatal', () async {
      await sendFromNative('nobody_listens', {});

      expect(true, isTrue, reason: 'no exception escaped');
    });
  });
}
