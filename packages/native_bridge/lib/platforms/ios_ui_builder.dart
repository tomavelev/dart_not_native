/// iOS widget-tree builders.
///
/// Pure Dart (no Flutter imports) so the same trees can be rendered by the
/// native iOS renderer or by the web DOM renderer.

import '../src/ui_renderer.dart';

/// Helper to build iOS-compatible widget trees
/// Similar to UIBuilder but optimized for iOS rendering (SwiftUI-friendly)
class iOSUIBuilder {
  static WidgetNode navigationStack({required WidgetNode content}) =>
      WidgetNode(type: 'NavigationStack', props: {}, children: [content]);

  static WidgetNode navigationBar({
    required String title,
    bool inline = true,
  }) => WidgetNode(
    type: 'NavigationBar',
    props: {'title': title, 'inline': inline},
  );

  static WidgetNode vStack({
    required List<WidgetNode> children,
    String alignment = 'leading',
    double spacing = 0,
  }) => WidgetNode(
    type: 'VStack',
    props: {'alignment': alignment, 'spacing': spacing},
    children: children,
  );

  static WidgetNode hStack({
    required List<WidgetNode> children,
    String alignment = 'center',
    double spacing = 0,
  }) => WidgetNode(
    type: 'HStack',
    props: {'alignment': alignment, 'spacing': spacing},
    children: children,
  );

  static WidgetNode button({required String label, required String eventId}) =>
      WidgetNode(type: 'Button', props: {'label': label, 'eventId': eventId});

  static WidgetNode list({required List<WidgetNode> children}) =>
      WidgetNode(type: 'List', props: {}, children: children);

  static WidgetNode listRow({required String text, String? subtitle}) =>
      WidgetNode(
        type: 'ListRow',
        props: {'text': text, if (subtitle != null) 'subtitle': subtitle},
      );

  static WidgetNode spacer({double minLength = 0}) =>
      WidgetNode(type: 'Spacer', props: {'minLength': minLength});

  static WidgetNode textField({
    required String placeholder,
    required String eventId,
    String? label,
    String? error,
    bool obscureText = false,
    bool enabled = true,
    String? initialValue,
  }) => WidgetNode(
    type: 'TextField',
    props: {
      'placeholder': placeholder,
      'eventId': eventId,
      if (label != null) 'label': label,
      if (error != null) 'error': error,
      'obscureText': obscureText,
      'enabled': enabled,
      if (initialValue != null) 'initialValue': initialValue,
    },
  );
}
