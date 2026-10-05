/// Tests for building a tree with callbacks instead of event-id strings.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

/// A counter written without an `init()`: every handler is bound where the
/// node is built.
class _CallbackApp extends NativeUIApp {
  int count = 0;
  String draft = '';
  final List<String> submitted = [];
  bool agreed = false;

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Callbacks'),
    body: UIBuilder.column(
      children: [
        UIBuilder.text('$count', id: 'count'),
        UIBuilder.button(
          label: 'Increment',
          id: 'increment',
          onPressed: () => setState(() => count++),
        ),
        UIBuilder.checkbox(
          checked: agreed,
          id: 'agree',
          onChanged: (value) => setState(() => agreed = value),
        ),
        UIBuilder.textField(
          hint: 'Say something',
          id: 'field',
          initialValue: draft,
          onChanged: (value) => setState(() => draft = value),
          onSubmitted: (value) => setState(() {
            submitted.add(value);
            draft = '';
          }),
        ),
      ],
    ),
    floatingActionButton: UIBuilder.floatingActionButton(
      tooltip: 'Increment',
      onPressed: () => setState(() => count++),
    ),
  );
}

void main() {
  late _CallbackApp app;
  late InMemoryRenderer renderer;

  setUp(() {
    app = _CallbackApp();
    renderer = InMemoryRenderer();
    app.mount(renderer);
  });

  /// Fires the node with [id] the way a renderer would.
  Future<dynamic> fire(String id, [Map<String, dynamic> data = const {}]) {
    final node = nodeById(renderer.tree!, id)!;
    return renderer.handleEvent(node.props['eventId'] as String, data);
  }

  group('binding', () {
    test('a button callback runs and re-renders', () async {
      await fire('increment');

      expect(app.count, 1);
      expect(nodeById(renderer.tree!, 'count')!.props['content'], '1');
    });

    test('the node still carries a plain string event id', () {
      final button = nodeById(renderer.tree!, 'increment')!;

      expect(button.props['eventId'], isA<String>());
      expect(button.props['eventId'], isNotEmpty);
    });

    test('a node without an id gets one from its position', () {
      final fab = findNode(
        renderer.tree!,
        (n) => n.type == 'FloatingActionButton',
      )!;

      expect(fab.props['eventId'], isA<String>());
    });

    test('a checkbox callback receives its new state', () async {
      final checkbox = nodeById(renderer.tree!, 'agree')!;

      await renderer.handleEvent(checkbox.props['eventId'] as String, {
        'checked': true,
      });

      expect(app.agreed, isTrue);
      expect(nodeById(renderer.tree!, 'agree')!.props['checked'], isTrue);
    });

    test('a text field binds change and submit separately', () async {
      final field = nodeById(renderer.tree!, 'field')!;
      final eventId = field.props['eventId'] as String;

      await renderer.handleEvent('${eventId}_change', {'value': 'hello'});
      expect(app.draft, 'hello');

      await renderer.handleEvent('${eventId}_submit', {'value': 'hello'});
      expect(app.submitted, ['hello']);
      expect(app.draft, isEmpty);
    });
  });

  group('stability across renders', () {
    test('event ids do not move, so renderers keep their elements', () async {
      String idsOf(WidgetNode tree) => walk(
        tree,
      ).map((n) => n.props['eventId']).whereType<String>().join(',');
      final before = idsOf(renderer.tree!);

      await fire('increment');

      expect(idsOf(renderer.tree!), before);
    });

    test('a rebuild replaces the callback rather than stacking them', () async {
      await fire('increment');
      await fire('increment');

      expect(app.count, 2, reason: 'two taps, two increments');
    });

    test(
      'the callback the latest build registered is the one that runs',
      () async {
        // The closure captures `count` afresh on every build; if an older
        // closure were still registered the count would not follow the app.
        await fire('increment');
        app.setState(() => app.count = 10);

        await fire('increment');

        expect(app.count, 11);
      },
    );
  });

  group('mixing with explicit event ids', () {
    test('a string event id still works and is left alone', () async {
      final app = _ExplicitApp()..mount(renderer);

      await renderer.handleEvent('explicit', {});

      expect(app.taps, 1);
      expect(
        nodeById(renderer.tree!, 'button')!.props['eventId'],
        'explicit',
        reason: 'the id the app chose is the id the node carries',
      );
    });

    test('a node with neither an id nor a callback is rejected', () {
      expect(() => UIBuilder.button(label: 'x'), throwsArgumentError);
    });
  });

  group('an event from the tree of an earlier build', () {
    // Ids given by order name a different callback once a build gives out a
    // different number before them. A renderer whose views may still show
    // the earlier tree says which build its event is for.
    late _ShiftingApp shifting;
    late InMemoryRenderer shown;

    setUp(() {
      shifting = _ShiftingApp();
      shown = InMemoryRenderer();
      shifting.mount(shown);
    });

    test('is answered by the callback its id named in that build', () async {
      final first = shown.tree!;
      final second = nodeById(first, 'second')!.props['eventId'] as String;
      final build = EventBindings.buildOf(first);
      expect(build, isNotNull);

      // A button now comes before the two: every id by order has moved on.
      shifting.setState(() => shifting.extra = true);
      expect(
        nodeById(shown.tree!, 'first')!.props['eventId'],
        second,
        reason: 'the id that was the second button\'s is the first one\'s now',
      );

      EventBindings.eventBuild = build;
      try {
        await shown.handleEvent(second, const {});
      } finally {
        EventBindings.eventBuild = null;
      }
      expect(shifting.pressed, ['second']);

      // Without a build named it is the latest tree's, as it always was.
      await shown.handleEvent(second, const {});
      expect(shifting.pressed, ['second', 'first']);
    });

    test('an id that build never gave out is answered by the latest', () async {
      final build = EventBindings.buildOf(shown.tree!);
      shifting.setState(() => shifting.extra = true);
      final third = nodeById(shown.tree!, 'second')!.props['eventId'] as String;

      EventBindings.eventBuild = build;
      try {
        await shown.handleEvent(third, const {});
      } finally {
        EventBindings.eventBuild = null;
      }
      expect(shifting.pressed, ['second']);
    });
  });

  group('outside a build', () {
    test('a callback outside a build fails with a clear message', () {
      expect(
        () => UIBuilder.button(label: 'x', onPressed: () {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('outside of a build'),
          ),
        ),
      );
    });
  });
}

class _ExplicitApp extends NativeUIApp {
  int taps = 0;

  @override
  void init() => on('explicit', (_) => setState(() => taps++));

  @override
  WidgetNode build() =>
      UIBuilder.button(label: 'Tap', eventId: 'explicit', id: 'button');
}

/// Buttons whose event ids come from the order they are built in, with one
/// more in front of them once [extra] is set.
class _ShiftingApp extends NativeUIApp {
  bool extra = false;
  final List<String> pressed = [];

  @override
  WidgetNode build() => UIBuilder.column(
    children: [
      if (extra)
        UIBuilder.button(label: 'Extra', onPressed: () => pressed.add('extra')),
      _keyed('first'),
      _keyed('second'),
    ],
  );

  /// The node is findable by [name]; its event id is still by order.
  WidgetNode _keyed(String name) {
    final button = UIBuilder.button(
      label: name,
      onPressed: () => pressed.add(name),
    );
    return WidgetNode(
      type: button.type,
      props: {...button.props, 'id': name},
      children: button.children,
    );
  }
}
