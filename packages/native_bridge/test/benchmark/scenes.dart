/// Screens the benchmarks render.
library;

import 'package:dart_not_native/core.dart';

/// A realistic app screen: app bar, input row, list rows, summary.
WidgetNode todoScene({
  required int items,
  int completed = 0,
  String draft = '',
  int firstId = 1,
  bool keyedRows = false,
}) => UIBuilder.scaffold(
  appBar: UIBuilder.appBar(title: 'My Todos'),
  body: UIBuilder.column(
    crossAxisAlignment: 'stretch',
    children: [
      UIBuilder.padding(
        all: 16,
        child: UIBuilder.row(
          spacing: 8,
          children: [
            UIBuilder.expanded(
              child: UIBuilder.textField(
                hint: 'Add a new todo...',
                eventId: 'new_todo',
                initialValue: draft,
              ),
            ),
            UIBuilder.iconButton(
              icon: 'add',
              eventId: 'add',
              tooltip: 'Add Todo',
            ),
          ],
        ),
      ),
      for (var i = firstId; i < firstId + items; i++)
        _padding(
          keyedRows ? 'todo_row_$i' : null,
          child: UIBuilder.row(
            spacing: 8,
            children: [
              WidgetNode(
                type: 'Checkbox',
                props: {
                  'eventId': 'toggle',
                  'checked': i <= completed,
                  'data': {'id': i},
                  'id': 'todo_${i}_done',
                },
              ),
              UIBuilder.expanded(
                child: UIBuilder.text(
                  'Todo item $i',
                  fontSize: 16,
                  decoration: i <= completed ? 'lineThrough' : null,
                  color: i <= completed ? '#9e9e9e' : null,
                  id: 'todo_${i}_title',
                ),
              ),
              UIBuilder.iconButton(
                icon: 'delete',
                eventId: 'delete',
                tooltip: 'Delete item $i',
                data: {'id': i},
              ),
            ],
          ),
        ),
      UIBuilder.text(
        '$completed of $items completed',
        color: '#757575',
        id: 'todo_summary',
      ),
    ],
  ),
);

/// A dense screen: every Material component the style kits build.
WidgetNode componentsScene({int sections = 8}) => UIBuilder.column(
  crossAxisAlignment: 'stretch',
  children: [
    for (var s = 0; s < sections; s++) ...[
      DSButton.primary(label: 'Primary $s', eventId: 'p$s'),
      DSButton.secondary(label: 'Secondary $s', eventId: 's$s'),
      DSCard.elevated(
        content: UIBuilder.text('Card body $s'),
        title: 'Card $s',
      ),
      DSBadge.solid(label: 'New'),
      DSAlert.info(message: 'Heads up $s', title: 'Info'),
      DSCheckbox.input(eventId: 'c$s', checked: s.isEven, label: 'Checked'),
      DSToggle.input(eventId: 't$s', enabled: s.isOdd, label: 'Toggle'),
      DSDivider.horizontal(),
      AndroidUIBuilder.listView(
        children: [
          for (var i = 0; i < 3; i++)
            AndroidUIBuilder.listItem(text: 'Item $i', subtitle: 'Subtitle'),
        ],
      ),
    ],
  ],
);

/// A row wrapper, optionally carrying the id that identifies it across
/// renders. Without one the renderer can only align rows by position, so an
/// insertion at the front shifts - and rebuilds - everything after it.
WidgetNode _padding(String? id, {required WidgetNode child}) {
  final padding = UIBuilder.padding(all: 8, child: child);
  if (id == null) return padding;
  return WidgetNode(
    type: padding.type,
    props: {...padding.props, 'id': id},
    children: padding.children,
  );
}

/// Number of nodes in [node], for reporting the size of a scene.
int countNodes(WidgetNode node) =>
    1 +
    (node.children ?? const <WidgetNode>[]).fold<int>(
      0,
      (sum, child) => sum + countNodes(child),
    );
