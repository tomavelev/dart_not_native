/// Unit tests for the app shell: mount, event dispatch and re-render.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tree.dart';

/// Minimal app exercising the shell: one counter, one event.
class _CounterApp extends NativeUIApp {
  int count = 0;
  int initCalls = 0;

  @override
  void init() {
    initCalls++;
    on(
      'increment',
      (data) => setState(() => count += (data['by'] as int?) ?? 1),
    );
  }

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Counter'),
    body: UIBuilder.center(child: UIBuilder.text('$count', id: 'count')),
    floatingActionButton: UIBuilder.floatingActionButton(
      tooltip: 'Increment',
      eventId: 'increment',
    ),
  );
}

/// An app whose screen is drawn from a store outside it, the way state shared
/// by several screens has to be.
class _WatchingApp extends NativeUIApp {
  _WatchingApp(this.store);
  final ValueNotifier<int> store;

  @override
  void init() => watch(store);

  @override
  WidgetNode build() =>
      UIBuilder.center(child: UIBuilder.text('${store.value}', id: 'count'));
}

/// A renderer whose render always reports [error], to exercise the error path.
class _FailingRenderer implements NativeUIRenderer {
  _FailingRenderer(this.error);
  final RenderError error;

  /// The last tree it was asked to draw, and how many it has seen.
  WidgetNode? lastTree;
  int renders = 0;

  @override
  Future<RenderError?> render(WidgetNode tree) async {
    lastTree = tree;
    renders++;
    return error;
  }

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async =>
      {'success': false};

  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {}
}

void main() {
  group('render errors (2.4)', () {
    test('a renderer error reaches onRenderError, with its parts', () async {
      final app = _CounterApp();
      final errors = <RenderError>[];
      app.onRenderError = errors.add;

      app.mount(_FailingRenderer(
        RenderError.unknownNodeTypes({'Sparkline'}),
      ));
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single.kind, RenderErrorKind.unknownNodeType);
      // The point of the type: the caller reads the types, rather than
      // reaching for a substring of the sentence.
      expect(errors.single.nodeTypes, {'Sparkline'});
      expect(errors.single.message, 'Unknown node type(s): Sparkline');
    });

    test('a successful render reports nothing', () async {
      final app = _CounterApp();
      final errors = <RenderError>[];
      app.onRenderError = errors.add;

      app.mount(InMemoryRenderer());
      await pumpEventQueue();

      expect(errors, isEmpty);
    });

    test('renderErrors carries them to more than one listener', () async {
      final app = _CounterApp();
      final first = <RenderError>[];
      final second = <RenderError>[];
      app.renderErrors.listen(first.add);
      app.renderErrors.listen(second.add);

      app.mount(_FailingRenderer(RenderError.failed('native blew up')));
      await pumpEventQueue();

      // A broadcast stream, so a debug overlay and a crash reporter can both
      // watch without taking the single callback from one another.
      expect(first.single.message, 'native blew up');
      expect(second.single.message, 'native blew up');
    });

    test('the stream carries errors even when a callback is set', () async {
      final app = _CounterApp();
      final watched = <RenderError>[];
      final handled = <RenderError>[];
      app.renderErrors.listen(watched.add);
      app.onRenderError = handled.add;

      app.mount(_FailingRenderer(RenderError.failed('native blew up')));
      await pumpEventQueue();

      expect(handled, hasLength(1));
      expect(watched, hasLength(1));
    });

    test('the debug banner shows what went wrong, over the app', () async {
      final app = _CounterApp()..debugShowRenderErrors = true;

      app.mount(_FailingRenderer(
        RenderError.unknownNodeTypes({'Sparkline'}),
      ));
      await pumpEventQueue();

      final renderer = app.renderer as _FailingRenderer;
      final tree = renderer.lastTree!;
      expect(tree.type, 'Overlay');
      // A Snackbar: every renderer draws one, it blocks nothing, and
      // OverlayBack leaves it alone because it is not modal.
      final banner = tree.children!.last;
      expect(banner.type, 'Snackbar');
      expect(banner.props['message'], contains('Sparkline'));
    });

    test('the banner is off unless asked for', () async {
      final app = _CounterApp();

      app.mount(_FailingRenderer(RenderError.failed('boom')));
      await pumpEventQueue();

      expect((app.renderer as _FailingRenderer).lastTree!.type, isNot('Overlay'));
    });

    test('a repeated error does not re-render forever', () async {
      final app = _CounterApp()..debugShowRenderErrors = true;
      final renderer = _FailingRenderer(RenderError.failed('same every time'));

      app.mount(renderer);
      await pumpEventQueue();
      final settled = renderer.renders;
      await pumpEventQueue();

      // The render the banner schedules meets the same error again; if that
      // scheduled another, this would climb without end.
      expect(renderer.renders, settled);
    });

    test('unmounting closes the stream', () async {
      final app = _CounterApp();
      var closed = false;
      app.renderErrors.listen(null, onDone: () => closed = true);

      app.mount(InMemoryRenderer());
      app.unmount();
      await pumpEventQueue();

      expect(closed, isTrue);
    });
  });

  group('NativeUIApp', () {
    late _CounterApp app;
    late InMemoryRenderer renderer;

    setUp(() {
      app = _CounterApp();
      renderer = InMemoryRenderer();
    });

    String countText() =>
        nodeById(renderer.tree!, 'count')!.props['content'] as String;

    test('is not mounted before mount()', () {
      expect(app.isMounted, isFalse);
      expect(() => app.renderer, throwsStateError);
      // render() before mount is a no-op rather than a crash.
      app.render();
      expect(renderer.tree, isNull);
    });

    test('mount runs init once and renders the first frame', () {
      app.mount(renderer);

      expect(app.isMounted, isTrue);
      expect(app.initCalls, 1);
      expect(renderer.tree, isNotNull);
      expect(countText(), '0');
    });

    test('setState re-renders and notifies onChanged', () {
      var changes = 0;
      app.onChanged = () => changes++;

      app.mount(renderer);
      expect(changes, 1, reason: 'the initial render notifies too');

      app.setState(() => app.count = 41);
      expect(countText(), '41');
      expect(changes, 2);
    });

    test('renderer events reach handlers with their payload', () async {
      app.mount(renderer);

      final result = await renderer.handleEvent('increment', {'by': 5});

      expect(result['success'], isTrue);
      expect(app.count, 5);
      expect(countText(), '5');
    });

    test('unknown events are reported, not thrown', () async {
      app.mount(renderer);

      final result = await renderer.handleEvent('does_not_exist', {});

      expect(result['success'], isFalse);
      expect(result['error'], contains('does_not_exist'));
    });

    test('every event id in the tree has a handler', () async {
      app.mount(renderer);

      final eventIds = walk(
        renderer.tree!,
      ).map((n) => n.props['eventId']).whereType<String>().toSet();
      expect(eventIds, isNotEmpty);

      for (final eventId in eventIds) {
        final result = await renderer.handleEvent(eventId, {});
        expect(result['success'], isTrue, reason: '$eventId has no handler');
      }
    });

    test('a remount rebinds to the new renderer', () {
      app.mount(renderer);
      final second = InMemoryRenderer();

      app.mount(second);
      app.setState(() => app.count = 7);

      expect(second.tree, isNotNull);
      expect(nodeById(second.tree!, 'count')!.props['content'], '7');
      expect(app.initCalls, 2);
    });
  });

  group('watching a store', () {
    late ValueNotifier<int> store;
    late _WatchingApp app;
    late InMemoryRenderer renderer;

    setUp(() {
      store = ValueNotifier<int>(0);
      app = _WatchingApp(store);
      renderer = InMemoryRenderer();
    });

    String countText() =>
        nodeById(renderer.tree!, 'count')!.props['content'] as String;

    test('a change outside the app redraws it', () {
      app.mount(renderer);
      expect(countText(), '0');

      store.value = 7;

      expect(countText(), '7');
    });

    test('watching twice still draws once', () {
      app.mount(renderer);
      var renders = 0;
      app.onChanged = () => renders++;

      app.watch(store);
      store.value = 1;

      expect(renders, 1);
    });

    test('unwatch lets go', () {
      app.mount(renderer);

      app.unwatch(store);
      store.value = 3;

      expect(countText(), '0');
      expect(store.hasListeners, isFalse);
    });

    test('unmount lets go of every store', () {
      // A store outlives the app, so a forgotten listener would keep asking a
      // torn-down app to render - on a renderer it no longer has.
      app.mount(renderer);

      app.unmount();

      expect(store.hasListeners, isFalse);
      expect(() => store.value = 9, returnsNormally);
    });
  });

  group('InMemoryRenderer', () {
    test('keeps only the latest tree', () async {
      final renderer = InMemoryRenderer();

      await renderer.render(UIBuilder.text('first'));
      await renderer.render(UIBuilder.text('second'));

      expect(renderer.tree!.props['content'], 'second');
    });

    test('render reports success by returning no error', () async {
      expect(await InMemoryRenderer().render(UIBuilder.text('x')), isNull);
    });

    test('the last handler registered for an id wins', () async {
      final renderer = InMemoryRenderer();
      final calls = <String>[];
      renderer.onEvent('tap', (_) => calls.add('first'));
      renderer.onEvent('tap', (_) => calls.add('second'));

      await renderer.handleEvent('tap', {});

      expect(calls, ['second']);
    });
  });
}
