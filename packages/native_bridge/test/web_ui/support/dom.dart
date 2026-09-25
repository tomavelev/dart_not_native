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
