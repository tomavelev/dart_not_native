/// DOM helpers for the browser tests.
library;

import 'package:dart_not_native/core.dart';
import 'package:web/web.dart' as web;

/// A fresh detached-from-previous-tests root attached to the document.
web.HTMLElement mountRoot() {
  final root = web.document.createElement('div') as web.HTMLElement;
  web.document.body!.appendChild(root);
  return root;
}

/// The node types of [element]'s rendered children, in document order.
List<String> childTypes(web.Element element) => [
  for (var i = 0; i < element.children.length; i++)
    element.children.item(i)!.getAttribute('data-type') ?? '',
];

/// The ids of the elements matching [selector] inside [host], in order.
List<String> idsOf(web.Element host, String selector) {
  final found = host.querySelectorAll(selector);
  return [
    for (var i = 0; i < found.length; i++) (found.item(i)! as web.Element).id,
  ];
}

/// Clicks the element with [id].
void click(String id) =>
    (web.document.getElementById(id)! as web.HTMLElement).click();

/// The `<input>`/`<textarea>` inside the widget with [id].
web.HTMLInputElement inputInside(String id) =>
    web.document.getElementById(id)!.querySelector('[data-part="input"], input')
        as web.HTMLInputElement;

/// A keydown event for Enter.
web.KeyboardEvent enterKey() =>
    web.KeyboardEvent('keydown', web.KeyboardEventInit(key: 'Enter'));

/// Adds an `id` prop to a node built by a builder without an `id` parameter.
WidgetNode withId(WidgetNode node, String id) => WidgetNode(
  type: node.type,
  props: {...node.props, 'id': id},
  children: node.children,
);

/// A node built from raw props, for the event ids a builder would only
/// allocate inside a running app.
WidgetNode node(
  String type,
  Map<String, dynamic> props, [
  List<WidgetNode> children = const [],
]) => WidgetNode(type: type, props: props, children: children);

/// A pointer event at a point in the window, as a mouse or a finger sends it.
web.PointerEvent pointer(
  String type,
  num x,
  num y, {
  String kind = 'mouse',
  int id = 1,
}) => web.PointerEvent(
  type,
  web.PointerEventInit(
    clientX: x.toInt(),
    clientY: y.toInt(),
    pointerId: id,
    pointerType: kind,
    button: 0,
    bubbles: true,
    cancelable: true,
  ),
);

/// A click where a pointer was, rather than the pointerless `element.click()`.
web.MouseEvent clickAt(num x, num y) => web.MouseEvent(
  'click',
  web.MouseEventInit(
    clientX: x.toInt(),
    clientY: y.toInt(),
    detail: 1,
    bubbles: true,
    cancelable: true,
  ),
);

/// Long enough for the browser to lay out and run its resize observers.
Future<void> settle([int milliseconds = 60]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

/// Lifts [root] above the view the Flutter test harness lays over the page,
/// for a test that asks the document what is under a point.
void raiseAboveHarness(web.HTMLElement root) {
  root.style
    ..position = 'relative'
    ..zIndex = '1';
}
