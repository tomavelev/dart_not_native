/// Android widget-tree builders.
///
/// Pure Dart (no Flutter imports) so the same trees can be rendered by the
/// native Android renderer or by the web DOM renderer.

import '../src/ui_renderer.dart';

/// Helper to build Android-compatible widget trees
/// Similar to UIBuilder but optimized for Android rendering
class AndroidUIBuilder {
  static WidgetNode scaffold({
    WidgetNode? appBar,
    required WidgetNode body,
    WidgetNode? floatingActionButton,
  }) => UIBuilder.scaffold(
    appBar: appBar,
    body: body,
    floatingActionButton: floatingActionButton,
  );

  static WidgetNode appBar({required String title, String? backgroundColor}) =>
      WidgetNode(
        type: 'AppBar',
        props: {
          'title': title,
          if (backgroundColor != null) 'backgroundColor': backgroundColor,
        },
      );

  static WidgetNode materialButton({
    required String label,
    required String eventId,
    String? color,
  }) => WidgetNode(
    type: 'MaterialButton',
    props: {
      'label': label,
      'eventId': eventId,
      if (color != null) 'color': color,
    },
  );

  static WidgetNode listView({required List<WidgetNode> children}) =>
      WidgetNode(type: 'ListView', props: {}, children: children);

  static WidgetNode listItem({required String text, String? subtitle}) =>
      WidgetNode(
        type: 'ListItem',
        props: {'text': text, if (subtitle != null) 'subtitle': subtitle},
      );

  static WidgetNode textField({
    required String hint,
    required String eventId,
    String? label,
    String? error,
    bool obscureText = false,
    bool enabled = true,
    String? initialValue,
    int maxLines = 1,
  }) => WidgetNode(
    type: 'TextField',
    props: {
      'hint': hint,
      'eventId': eventId,
      if (label != null) 'label': label,
      if (error != null) 'error': error,
      'obscureText': obscureText,
      'enabled': enabled,
      if (initialValue != null) 'initialValue': initialValue,
      'maxLines': maxLines,
    },
  );
}
