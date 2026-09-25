/// Test harness for [NativeUIApp]s.
///
/// The example apps render a widget tree, not Flutter widgets, so this is the
/// equivalent of `WidgetTester`: mount an app on an in-memory renderer, drive
/// it the way a real renderer would (tap a node by id, type into a field) and
/// assert on the tree that comes back.
library;

import 'package:dart_not_native/core.dart';

/// Depth-first walk of [node] and its descendants.
Iterable<WidgetNode> walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* walk(child);
  }
}

class AppTester {
  AppTester(this.app) {
    app.mount(renderer);
  }

  /// Mounts [app] and returns the harness.
  static AppTester mount(NativeUIApp app) => AppTester(app);

  final NativeUIApp app;
  final InMemoryRenderer renderer = InMemoryRenderer();

  /// The most recently rendered tree.
  WidgetNode get tree => renderer.tree!;

  Iterable<WidgetNode> get nodes => walk(tree);

  /// The node with `props['id'] == id`, or null.
  WidgetNode? find(String id) =>
      nodes.where((n) => n.props['id'] == id).firstOrNull;

  /// The node with [id]; fails loudly when it is missing.
  WidgetNode get(String id) =>
      find(id) ?? (throw StateError('No node with id "$id" in the tree'));

  /// Nodes of [type], in document order.
  List<WidgetNode> ofType(String type) =>
      nodes.where((n) => n.type == type).toList();

  /// Text content of the node with [id].
  String text(String id) => get(id).props['content'] as String;

  /// Every Text node's content, in document order.
  List<String> get texts =>
      ofType('Text').map((n) => n.props['content'] as String).toList();

  bool hasText(String content) => texts.contains(content);

  /// Every event id referenced anywhere in the tree.
  Set<String> get eventIds =>
      nodes.map((n) => n.props['eventId']).whereType<String>().toSet();

  /// Taps the node with [id], sending the event and payload a real renderer
  /// would send.
  Future<void> tap(String id) async {
    final node = get(id);
    final eventId = node.props['eventId'];
    if (eventId is! String) {
      throw StateError('Node "$id" (${node.type}) has no eventId to fire');
    }
    final data = node.props['data'];
    await renderer.handleEvent(
      eventId,
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  /// Taps the first node wired to [eventId] - for nodes that carry no id.
  Future<void> tapEvent(String eventId) async {
    final node = nodes.firstWhere(
      (n) => n.props['eventId'] == eventId,
      orElse: () => throw StateError('No node fires "$eventId"'),
    );
    final data = node.props['data'];
    await renderer.handleEvent(
      eventId,
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  /// Toggles the checkbox with [id], as the renderer does on a change event.
  Future<void> toggle(String id) async {
    final node = get(id);
    final data = node.props['data'];
    await renderer.handleEvent(node.props['eventId'] as String, {
      if (data is Map) ...Map<String, dynamic>.from(data),
      'checked': node.props['checked'] != true,
    });
  }

  /// Types [value] into the text field whose event id is [eventId]; the web
  /// renderer sends `<eventId>_change` on every keystroke.
  Future<void> enterText(String eventId, String value) =>
      renderer.handleEvent('${eventId}_change', {'value': value});

  /// Presses Enter in the text field whose event id is [eventId].
  Future<void> submit(String eventId, [String? value]) =>
      renderer.handleEvent('${eventId}_submit', {'value': value ?? ''});

  /// The event id a node carries, for a node addressed by [id].
  String eventIdOf(String id) => get(id).props['eventId'] as String;

  /// Types [value] into the text field with [id], whatever event id it was
  /// given - a widget-style field allocates its own.
  Future<void> typeInto(String id, String value) =>
      enterText(eventIdOf(id), value);

  /// Presses Enter in the text field with [id].
  Future<void> submitInto(String id, [String? value]) =>
      submit(eventIdOf(id), value);

  /// Sends a raw event, for cases with no node to tap.
  Future<dynamic> emit(String eventId, [Map<String, dynamic>? data]) =>
      renderer.handleEvent(eventId, data ?? const {});
}
