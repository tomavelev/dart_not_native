/// Helpers for asserting on [WidgetNode] trees.
///
/// The framework renders a serialized tree, not Flutter widgets, so the tree
/// itself is what tests inspect - these are the equivalent of `find.byType`
/// and `find.text` for `flutter_test`.
library;

import 'package:dart_not_native/core.dart';

/// Depth-first walk of [node] and its descendants.
Iterable<WidgetNode> walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* walk(child);
  }
}

/// First node matching [test], or null.
WidgetNode? findNode(WidgetNode root, bool Function(WidgetNode) test) {
  for (final node in walk(root)) {
    if (test(node)) return node;
  }
  return null;
}

/// All nodes matching [test].
List<WidgetNode> findNodes(WidgetNode root, bool Function(WidgetNode) test) =>
    walk(root).where(test).toList();

/// Node carrying `props['id'] == id`.
WidgetNode? nodeById(WidgetNode root, String id) =>
    findNode(root, (n) => n.props['id'] == id);

/// All nodes of [type].
List<WidgetNode> nodesOfType(WidgetNode root, String type) =>
    findNodes(root, (n) => n.type == type);

/// Every `props['content']` of the tree's Text nodes, in document order.
List<String> texts(WidgetNode root) =>
    nodesOfType(root, 'Text').map((n) => n.props['content'] as String).toList();

/// Whether any Text node renders exactly [content].
bool hasText(WidgetNode root, String content) => texts(root).contains(content);
