/// The screens the DOM goldens capture.
///
/// Kept next to the golden test so a change in markup is reviewed against a
/// small, readable definition of the screen it belongs to.
library;

import 'package:dart_not_native/core.dart';

/// A realistic app screen: app bar, input row, list rows, summary.
final WidgetNode appShellScene = UIBuilder.scaffold(
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
                initialValue: '',
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
      UIBuilder.padding(
        all: 8,
        child: UIBuilder.row(
          spacing: 8,
          children: [
            UIBuilder.checkbox(
              eventId: 'toggle',
              checked: true,
              data: {'id': 1},
            ),
            UIBuilder.expanded(
              child: UIBuilder.text(
                'Buy milk',
                fontSize: 16,
                decoration: 'lineThrough',
                color: '#9e9e9e',
                id: 'todo_1_title',
              ),
            ),
          ],
        ),
      ),
      UIBuilder.text('1 of 1 completed', color: '#757575', id: 'todo_summary'),
    ],
  ),
  floatingActionButton: UIBuilder.floatingActionButton(
    tooltip: 'Add',
    eventId: 'add',
  ),
);

/// One of every Material component the style kits are responsible for.
final WidgetNode componentsScene = UIBuilder.column(
  crossAxisAlignment: 'stretch',
  children: [
    DSButton.primary(label: 'Primary', eventId: 'p'),
    DSButton.secondary(label: 'Secondary', eventId: 's'),
    DSButton.primary(label: 'Disabled', eventId: 'd', disabled: true),
    DSCard.elevated(content: UIBuilder.text('Card body'), title: 'Card'),
    DSBadge.solid(label: 'New'),
    UIBuilder.image(
      src: 'vendor/roboto/roboto.css',
      alt: 'A placeholder image',
      width: 64,
      height: 64,
    ),
    DSAlert.info(message: 'Heads up', title: 'Info', dismissible: true),
    DSCheckbox.input(eventId: 'c', checked: true, label: 'Checked'),
    DSRadio.input(eventId: 'r', value: 'a', selected: true, label: 'Radio'),
    DSToggle.input(eventId: 't', enabled: true, label: 'Toggle'),
    DSDivider.horizontal(),
    DSLoading.progressLinear(value: 0.5),
    AndroidUIBuilder.listView(
      children: [AndroidUIBuilder.listItem(text: 'Item', subtitle: 'Subtitle')],
    ),
    UIBuilder.textField(
      hint: 'you@example.com',
      eventId: 'email',
      label: 'Email',
      error: 'Invalid email',
    ),
  ],
);

/// Scene name -> tree. Golden names are `<scene>__<kit>`.
final Map<String, WidgetNode> goldenScenes = {
  'app_shell': appShellScene,
  'components': componentsScene,
};
