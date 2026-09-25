/// Design System Components
///
/// Reusable component builders using the WidgetNode protocol.
/// Components follow design system tokens for consistency.

import 'package:dart_not_native/material.dart';
import 'tokens.dart';

// ============================================================================
// BUTTON COMPONENT
// ============================================================================

class DSButton {
  /// Primary button (solid filled)
  static WidgetNode primary({
    required String label,
    required String eventId,
    String size = 'md',
    bool disabled = false,
    bool loading = false,
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'primary',
        'size': size,
        'disabled': disabled || loading,
        'loading': loading,
      },
    );
  }

  /// Secondary button (outlined)
  static WidgetNode secondary({
    required String label,
    required String eventId,
    String size = 'md',
    bool disabled = false,
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'secondary',
        'size': size,
        'disabled': disabled,
      },
    );
  }

  /// Tertiary button (text only)
  static WidgetNode tertiary({
    required String label,
    required String eventId,
    String size = 'md',
    bool disabled = false,
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'tertiary',
        'size': size,
        'disabled': disabled,
      },
    );
  }

  /// Success button (green)
  static WidgetNode success({
    required String label,
    required String eventId,
    String size = 'md',
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'success',
        'size': size,
      },
    );
  }

  /// Error button (red, dangerous action)
  static WidgetNode error({
    required String label,
    required String eventId,
    String size = 'md',
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'error',
        'size': size,
      },
    );
  }

  /// Warning button (yellow, caution)
  static WidgetNode warning({
    required String label,
    required String eventId,
    String size = 'md',
  }) {
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        'eventId': eventId,
        'variant': 'warning',
        'size': size,
      },
    );
  }
}

// ============================================================================
// CARD COMPONENT
// ============================================================================

class DSCard {
  /// Elevated card (with shadow)
  static WidgetNode elevated({
    required WidgetNode content,
    String? title,
    double? elevation = ELEVATION_MD,
    double padding = SPACING_MD,
  }) {
    return WidgetNode(
      type: 'Card',
      props: {
        'variant': 'elevated',
        'elevation': elevation,
        'padding': padding,
        if (title != null) 'title': title,
      },
      children: [content],
    );
  }

  /// Outlined card (border only)
  static WidgetNode outlined({
    required WidgetNode content,
    String? title,
    double padding = SPACING_MD,
  }) {
    return WidgetNode(
      type: 'Card',
      props: {
        'variant': 'outlined',
        'padding': padding,
        if (title != null) 'title': title,
      },
      children: [content],
    );
  }

  /// Filled card (colored background)
  static WidgetNode filled({
    required WidgetNode content,
    String? title,
    String backgroundColor = COLOR_GRAY_100,
    double padding = SPACING_MD,
  }) {
    return WidgetNode(
      type: 'Card',
      props: {
        'variant': 'filled',
        'backgroundColor': backgroundColor,
        'padding': padding,
        if (title != null) 'title': title,
      },
      children: [content],
    );
  }
}

// ============================================================================
// BADGE / CHIP COMPONENT
// ============================================================================

class DSBadge {
  /// Solid badge
  static WidgetNode solid({
    required String label,
    String color = COLOR_PRIMARY,
  }) {
    return WidgetNode(
      type: 'Badge',
      props: {'label': label, 'variant': 'solid', 'color': color},
    );
  }

  /// Outlined badge
  static WidgetNode outlined({
    required String label,
    String color = COLOR_PRIMARY,
  }) {
    return WidgetNode(
      type: 'Badge',
      props: {'label': label, 'variant': 'outlined', 'color': color},
    );
  }

  /// Dot badge (small indicator)
  static WidgetNode dot({String color = COLOR_PRIMARY}) {
    return WidgetNode(type: 'Badge', props: {'variant': 'dot', 'color': color});
  }

  /// Success badge (green)
  static WidgetNode success({required String label}) =>
      solid(label: label, color: COLOR_SUCCESS);

  /// Error badge (red)
  static WidgetNode error({required String label}) =>
      solid(label: label, color: COLOR_ERROR);

  /// Warning badge (yellow)
  static WidgetNode warning({required String label}) =>
      solid(label: label, color: COLOR_WARNING);

  /// Info badge (blue)
  static WidgetNode info({required String label}) =>
      solid(label: label, color: COLOR_INFO);
}

// ============================================================================
// CHECKBOX COMPONENT
// ============================================================================

class DSCheckbox {
  /// Checkbox input
  static WidgetNode input({
    required String eventId,
    bool checked = false,
    bool disabled = false,
    String? label,
  }) {
    return WidgetNode(
      type: 'Checkbox',
      props: {
        'eventId': eventId,
        'checked': checked,
        'disabled': disabled,
        if (label != null) 'label': label,
      },
    );
  }
}

// ============================================================================
// RADIO BUTTON COMPONENT
// ============================================================================

class DSRadio {
  /// Radio button input
  static WidgetNode input({
    required String eventId,
    required String value,
    bool selected = false,
    bool disabled = false,
    String? label,
  }) {
    return WidgetNode(
      type: 'Radio',
      props: {
        'eventId': eventId,
        'value': value,
        'selected': selected,
        'disabled': disabled,
        if (label != null) 'label': label,
      },
    );
  }
}

// ============================================================================
// TOGGLE / SWITCH COMPONENT
// ============================================================================

class DSToggle {
  /// Toggle/Switch input
  static WidgetNode input({
    required String eventId,
    bool enabled = false,
    bool disabled = false,
    String? label,
  }) {
    return WidgetNode(
      type: 'Toggle',
      props: {
        'eventId': eventId,
        'enabled': enabled,
        'disabled': disabled,
        if (label != null) 'label': label,
      },
    );
  }
}

// ============================================================================
// DIVIDER / SEPARATOR COMPONENT
// ============================================================================

class DSDivider {
  /// Horizontal divider
  static WidgetNode horizontal({
    String color = COLOR_GRAY_200,
    double thickness = 1.0,
    double margin = SPACING_MD,
  }) {
    return WidgetNode(
      type: 'Divider',
      props: {
        'orientation': 'horizontal',
        'color': color,
        'thickness': thickness,
        'margin': margin,
      },
    );
  }

  /// Vertical divider
  static WidgetNode vertical({
    String color = COLOR_GRAY_200,
    double thickness = 1.0,
    double height = 24.0,
  }) {
    return WidgetNode(
      type: 'Divider',
      props: {
        'orientation': 'vertical',
        'color': color,
        'thickness': thickness,
        'height': height,
      },
    );
  }
}

// ============================================================================
// LOADING / PROGRESS COMPONENT
// ============================================================================

class DSLoading {
  /// Spinner/loading indicator
  static WidgetNode spinner({
    String color = COLOR_PRIMARY,
    double size = 24.0,
  }) {
    return WidgetNode(
      type: 'Loading',
      props: {'type': 'spinner', 'color': color, 'size': size},
    );
  }

  /// Linear progress bar
  static WidgetNode progressLinear({
    double value = 0.0, // 0.0 to 1.0
    String color = COLOR_PRIMARY,
    bool indeterminate = false,
  }) {
    return WidgetNode(
      type: 'Loading',
      props: {
        'type': 'progress-linear',
        'value': value,
        'color': color,
        'indeterminate': indeterminate,
      },
    );
  }

  /// Circular progress
  static WidgetNode progressCircular({
    double value = 0.0, // 0.0 to 1.0
    String color = COLOR_PRIMARY,
    bool indeterminate = false,
  }) {
    return WidgetNode(
      type: 'Loading',
      props: {
        'type': 'progress-circular',
        'value': value,
        'color': color,
        'indeterminate': indeterminate,
      },
    );
  }

  /// Skeleton (placeholder while loading)
  static WidgetNode skeleton({
    double width = double.infinity,
    double height = 16.0,
  }) {
    return WidgetNode(
      type: 'Loading',
      props: {'type': 'skeleton', 'width': width, 'height': height},
    );
  }

  /// Pulsing animation
  static WidgetNode pulse({required WidgetNode child}) {
    return WidgetNode(
      type: 'Loading',
      props: {'type': 'pulse'},
      children: [child],
    );
  }
}

// ============================================================================
// ALERT / BANNER COMPONENT
// ============================================================================

class DSAlert {
  /// Success alert
  static WidgetNode success({
    required String message,
    String? title,
    bool dismissible = true,
  }) {
    return WidgetNode(
      type: 'Alert',
      props: {
        'type': 'success',
        'message': message,
        if (title != null) 'title': title,
        'dismissible': dismissible,
      },
    );
  }

  /// Error alert
  static WidgetNode error({
    required String message,
    String? title,
    bool dismissible = true,
  }) {
    return WidgetNode(
      type: 'Alert',
      props: {
        'type': 'error',
        'message': message,
        if (title != null) 'title': title,
        'dismissible': dismissible,
      },
    );
  }

  /// Warning alert
  static WidgetNode warning({
    required String message,
    String? title,
    bool dismissible = true,
  }) {
    return WidgetNode(
      type: 'Alert',
      props: {
        'type': 'warning',
        'message': message,
        if (title != null) 'title': title,
        'dismissible': dismissible,
      },
    );
  }

  /// Info alert
  static WidgetNode info({
    required String message,
    String? title,
    bool dismissible = true,
  }) {
    return WidgetNode(
      type: 'info',
      props: {
        'type': 'info',
        'message': message,
        if (title != null) 'title': title,
        'dismissible': dismissible,
      },
    );
  }
}

// ============================================================================
// TYPOGRAPHY HELPERS
// ============================================================================

class DSText {
  /// Heading 1
  static WidgetNode h1(String content) => UIBuilder.text(content);

  /// Heading 2
  static WidgetNode h2(String content) => UIBuilder.text(content);

  /// Heading 3
  static WidgetNode h3(String content) => UIBuilder.text(content);

  /// Body text (medium)
  static WidgetNode body(String content) => UIBuilder.text(content);

  /// Small body text
  static WidgetNode bodySm(String content) => UIBuilder.text(content);

  /// Caption/label text
  static WidgetNode caption(String content) => UIBuilder.text(content);
}

// ============================================================================
// SPACING HELPERS
// ============================================================================

class DSSpacing {
  /// Extra small spacing (4px)
  static WidgetNode xs() => UIBuilder.sizedBox(height: SPACING_XS);

  /// Small spacing (8px)
  static WidgetNode sm() => UIBuilder.sizedBox(height: SPACING_SM);

  /// Medium spacing (16px)
  static WidgetNode md() => UIBuilder.sizedBox(height: SPACING_MD);

  /// Large spacing (24px)
  static WidgetNode lg() => UIBuilder.sizedBox(height: SPACING_LG);

  /// Extra large spacing (32px)
  static WidgetNode xl() => UIBuilder.sizedBox(height: SPACING_XL);

  /// Extra extra large spacing (48px)
  static WidgetNode xxl() => UIBuilder.sizedBox(height: SPACING_XXL);
}
