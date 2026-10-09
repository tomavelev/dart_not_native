/// UI Renderer Protocol
///
/// Defines the contract between Dart (client logic) and native renderers.
/// The renderer translates widget trees to native UI (Android Views, iOS UIViews, HTML/CSS).

import 'dart:convert';

import 'event_binding.dart';
import 'lazy_list.dart';
import 'material_icons.dart';
import 'render_error.dart';

/// Widget tree node that can be serialized and sent to native renderers
class WidgetNode {
  final String type; // 'Scaffold', 'AppBar', 'FloatingActionButton', etc.
  final Map<String, dynamic> props; // Widget properties
  final List<WidgetNode>? children;

  const WidgetNode({required this.type, required this.props, this.children});

  /// Convert to JSON for transmission to native renderer
  Map<String, dynamic> toJson() => {
    'type': type,
    'props': props,
    'children': children?.map((c) => c.toJson()).toList(),
  };

  /// Parse from JSON (from native renderer responses)
  factory WidgetNode.fromJson(Map<String, dynamic> json) => WidgetNode(
    type: json['type'] as String,
    props: json['props'] as Map<String, dynamic>? ?? {},
    children: (json['children'] as List?)
        ?.map((c) => WidgetNode.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  String toJsonString() => jsonEncode(toJson());
}

/// What `semanticRole` may say a node is, for a screen reader: a `heading` to
/// jump between, a `button`, an `image`, a `progress` indicator.
const Set<String> semanticRoles = {'heading', 'button', 'image', 'progress'};

/// Every node type the protocol defines.
///
/// This is the contract between an app and a renderer: an app may build any of
/// these, and a renderer is expected to draw all of them. The renderers mark
/// their dispatch with `node-types:begin`/`end` so a test can check each one
/// against this list.
const Set<String> nodeTypes = {
  // Structure
  'Scaffold', 'NavigationStack', 'AppBar', 'NavigationBar',
  // Layout
  'Column', 'VStack', 'Row', 'HStack', 'Wrap', 'Expanded', 'Center', 'Padding',
  'SizedBox', 'Spacer', 'Divider',
  // Content
  'Text', 'Image', 'Loading', 'Badge', 'Alert', 'Card',
  // Controls
  'Button', 'MaterialButton', 'IconButton', 'FloatingActionButton', 'TextField',
  'Checkbox', 'Radio', 'Toggle', 'Slider', 'Tabs',
  // Lists
  'List', 'ListView', 'ListItem', 'ListRow', 'LazyList', 'GridView',
  // Overlays
  'Overlay', 'Dialog', 'BottomSheet', 'Snackbar',
  // Gestures
  'SwipeActions',
  // Motion
  'AnimatedOpacity', 'AnimatedContainer',
  // Embedded platform content
  'WebView', 'MapView', 'CameraPreview',
  // Free-form composition: a decorated box, layers, a scroller, a glyph
  'Box', 'Stack', 'Positioned', 'Scroll', 'Icon',
  // Drawing
  'Canvas',
  // Choosing
  'Dropdown', 'DatePicker', 'TimePicker',
  // App chrome along the bottom edge
  'BottomBar', 'BottomNavigation',
  // A region a Flutter widget is painted into
  'FlutterSlot',
};

/// Props a renderer reads off the root of the tree, whatever type the root is.
///
/// They describe the screen rather than any one node, so they are stated once,
/// at the top, instead of being repeated down the tree - and because they are
/// in the tree rather than in `initialize`, they can change from one render to
/// the next.
abstract final class RootProps {
  /// `'rtl'` lays the whole screen out right to left; absent (or `'ltr'`) is
  /// left to right. An app that switches to Arabic while it runs sends `'rtl'`
  /// with its next tree and the renderer turns the screen round in place.
  ///
  /// What turns is everything that has a *start* and an *end*: a row's
  /// children run from the right, an app bar's leading button and a list
  /// row's leading sit on the right and its actions and trailing on the left,
  /// a text field's prefix and suffix swap ends, text with no `textAlign`
  /// starts at the right, the floating button moves to the bottom left, and a
  /// back arrow points the other way. A `crossAxisAlignment` of 'start' on a
  /// column is the right-hand edge.
  ///
  /// What does not turn is everything that names a side or a coordinate
  /// outright, as in Flutter: `padding` and `margin` are `[left, top, right,
  /// bottom]`, a `Positioned` node's `left` and `right` are the left and the
  /// right, an `alignment` of `[-1, 0]` is the left edge, `textAlign: 'left'`
  /// is left, and a `Canvas` draws in the coordinates it was given. The widget
  /// layer's `EdgeInsetsDirectional` and its kin are resolved against the
  /// direction before they reach the tree, which is why the tree itself only
  /// needs the physical form.
  ///
  /// [UIBuilder.withTextDirection] puts it on a tree; the widget layer's
  /// `MaterialApp` does so from the locale.
  static const String textDirection = 'textDirection';
}

/// Event ids a renderer fires on its own account, with no node asking.
///
/// A renderer sends [viewport] once it knows its size and again whenever that
/// changes, and [key] for hardware key presses where the platform has them.
abstract final class RendererEvents {
  /// `{width, height, paddingTop, paddingBottom, paddingLeft, paddingRight,
  /// keyboardInset, devicePixelRatio, textScale, dark}` - logical pixels.
  static const String viewport = 'dnn:viewport';

  /// `{key, down}`: [key] is a `KeyboardEvent.key` style name ('ArrowUp',
  /// 'Enter', ' ', 'a'), `down` false for the release.
  static const String key = 'dnn:key';

  /// `{slotId, x, y, width, height, visible}`: where a `FlutterSlot` came to
  /// rest in the window, for the host painting a Flutter widget under it.
  static const String slotRect = 'dnn:slotRect';

  /// `{state}`: 'resumed', 'inactive', 'paused' or 'detached'.
  static const String lifecycle = 'dnn:lifecycle';
}

/// Native renderer interface
/// Implementations handle platform-specific rendering (Web, Android, iOS)
abstract class NativeUIRenderer {
  /// Renders a widget tree, answering null when it drew everything asked of it
  /// and a [RenderError] when it did not - see `NativeUIApp.renderErrors`.
  Future<RenderError?> render(WidgetNode tree);

  /// Handle native event (button tap, text change, etc.)
  /// Event data comes from native side
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data);

  /// Register event handler
  void onEvent(String eventId, Function(Map<String, dynamic>) handler);
}

/// Builder helper to construct widget trees
class UIBuilder {
  /// [root] with the screen's reading direction stated on it - see
  /// [RootProps.textDirection]. [direction] is 'rtl' or 'ltr'; left to right
  /// is what a tree with nothing stated means, so it is left out rather than
  /// written, and a tree that never mentions a direction is unchanged.
  static WidgetNode withTextDirection(WidgetNode root, String? direction) {
    final stated = root.props[RootProps.textDirection];
    final wanted = direction == 'rtl' ? 'rtl' : null;
    if (stated == wanted) return root;
    return WidgetNode(
      type: root.type,
      props: {
        for (final entry in root.props.entries)
          if (entry.key != RootProps.textDirection) entry.key: entry.value,
        if (wanted != null) RootProps.textDirection: wanted,
      },
      children: root.children,
    );
  }

  /// The frame of a screen: an app bar, a body, a floating action button and
  /// a [bottomBar], each optional but the body. A renderer tells them apart by
  /// type - the app bar is the `AppBar` child, the bar along the bottom the
  /// `BottomBar` one, the button the `FloatingActionButton` - so the body is
  /// whichever child is none of those.
  ///
  /// The body scrolls when it is taller than the screen, unless [bodyScrolls]
  /// is false - which is what a body that lays itself out against the screen's
  /// height wants: one with an [expanded] in it, a [scroll] of its own, a
  /// [stack]. [safeArea] false lets the body run under the system insets.
  static WidgetNode scaffold({
    WidgetNode? appBar,
    required WidgetNode body,
    WidgetNode? floatingActionButton,
    WidgetNode? bottomBar,
    bool bodyScrolls = true,
    String? backgroundColor,
    bool safeArea = true,
  }) => WidgetNode(
    type: 'Scaffold',
    props: {
      if (!bodyScrolls) 'bodyScrolls': false,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (!safeArea) 'safeArea': false,
    },
    children: [
      if (appBar != null) appBar,
      body,
      if (floatingActionButton != null) floatingActionButton,
      if (bottomBar != null) bottomBar,
    ],
  );

  /// The bar across the top of a [scaffold].
  ///
  /// [leading] is 'back', 'close' or 'menu' - the button at the start of the
  /// bar, drawn the platform's way - and [onLeading] is what it does.
  /// [actions] sit at the end: icon buttons, usually. [titleNode] replaces the
  /// title text with a subtree, for a title that is more than a string.
  static WidgetNode appBar({
    required String title,
    String? leading,
    void Function()? onLeading,
    String? leadingEventId,
    List<WidgetNode> actions = const [],
    WidgetNode? titleNode,
    bool? centerTitle,
    String? backgroundColor,
    String? foregroundColor,
    double? elevation,
  }) {
    if (leading != null) {
      leadingEventId = _bindTap(leadingEventId, onLeading, 'appBar.leading');
    }
    return WidgetNode(
      type: 'AppBar',
      props: {
        'title': title,
        if (leading != null) 'leading': leading,
        if (leading != null) 'leadingEventId': leadingEventId,
        if (centerTitle != null) 'centerTitle': centerTitle,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (foregroundColor != null) 'foregroundColor': foregroundColor,
        if (elevation != null) 'elevation': elevation,
        if (titleNode != null) 'hasTitleNode': true,
      },
      // The title subtree, when there is one, is the first child; the rest
      // are the actions.
      children: actions.isEmpty && titleNode == null
          ? null
          : [if (titleNode != null) titleNode, ...actions],
    );
  }

  /// Vertical layout. [crossAxisAlignment] is 'start', 'center' (default,
  /// like Flutter's Column), 'end' or 'stretch'.
  ///
  /// [mainAxisAlignment] - 'center', 'end' or 'spaceBetween' - distributes the
  /// children down the column, and only shows where the column has height to
  /// spare: a column sizes to its content unless something gives it more, so
  /// asking for it is also asking the column to fill what it is in. 'start' is
  /// the default and is left out of the tree, since it is the absence of any
  /// distributing.
  ///
  /// [mainAxisAlignment] also takes 'spaceAround' and 'spaceEvenly'.
  /// `mainAxisSize: 'max'` fills the height it is offered without
  /// distributing anything, and 'min' hugs the children even when an
  /// alignment was asked for. [spacing] is a gap between children.
  static WidgetNode column({
    required List<WidgetNode> children,
    String? crossAxisAlignment,
    String? mainAxisAlignment,
    String? mainAxisSize,
    double spacing = 0,
  }) => WidgetNode(
    type: 'Column',
    props: {
      if (crossAxisAlignment != null) 'crossAxisAlignment': crossAxisAlignment,
      if (mainAxisAlignment != null && mainAxisAlignment != 'start')
        'mainAxisAlignment': mainAxisAlignment,
      if (mainAxisSize != null) 'mainAxisSize': mainAxisSize,
      if (spacing != 0) 'spacing': spacing,
    },
    children: children,
  );

  /// Horizontal layout. [mainAxisAlignment] is 'start' (default), 'center',
  /// 'end' or 'spaceBetween'.
  ///
  /// [mainAxisAlignment] also takes 'spaceAround' and 'spaceEvenly'.
  /// [crossAxisAlignment] is 'start', 'center' (the default), 'end' or
  /// 'stretch'. `mainAxisSize: 'min'` makes the row as wide as its children
  /// rather than as wide as it is allowed.
  ///
  /// A row that says `mainAxisSize: 'max'`, or whose [mainAxisAlignment]
  /// distributes ('center', 'end' or one of the 'space…'s), is Flutter's
  /// `Row`: one line, as wide as it is offered, the children placed along it -
  /// and a child that does not fit overflows rather than moving to a second
  /// line. A row that asks for neither is the older, forgiving one: as wide as
  /// its children, and on the Flutter host it reflows onto another line when
  /// they do not fit. The widget layer's `Row` always says which it is.
  ///
  /// The children run from the start of the line to its end, so in a
  /// right-to-left screen ([RootProps.textDirection]) the first child is the
  /// rightmost.
  static WidgetNode row({
    required List<WidgetNode> children,
    String? mainAxisAlignment,
    String? crossAxisAlignment,
    String? mainAxisSize,
    double spacing = 0,
  }) => WidgetNode(
    type: 'Row',
    props: {
      if (mainAxisAlignment != null) 'mainAxisAlignment': mainAxisAlignment,
      if (crossAxisAlignment != null) 'crossAxisAlignment': crossAxisAlignment,
      if (mainAxisSize != null) 'mainAxisSize': mainAxisSize,
      'spacing': spacing,
    },
    children: children,
  );

  /// A run of children laid out horizontally that wraps onto the next line when
  /// it runs out of width. [spacing] is the gap between children on a line,
  /// [runSpacing] the gap between lines.
  /// [alignment] ('start', 'center', 'end', 'spaceBetween') places the
  /// children along each line and [crossAxisAlignment] ('start', 'center',
  /// 'end') across it.
  static WidgetNode wrap({
    required List<WidgetNode> children,
    double spacing = 0,
    double runSpacing = 0,
    String? alignment,
    String? crossAxisAlignment,
  }) => WidgetNode(
    type: 'Wrap',
    props: {
      'spacing': spacing,
      'runSpacing': runSpacing,
      if (alignment != null && alignment != 'start') 'alignment': alignment,
      if (crossAxisAlignment != null && crossAxisAlignment != 'start')
        'crossAxisAlignment': crossAxisAlignment,
    },
    children: children,
  );

  /// Makes [child] take the remaining space inside a Row or Column.
  /// `fit: 'loose'` lets the child be smaller than its share (Flutter's
  /// `Flexible`) rather than stretching it to fill.
  static WidgetNode expanded({
    required WidgetNode child,
    int flex = 1,
    String fit = 'tight',
  }) => WidgetNode(
    type: 'Expanded',
    props: {'flex': flex, if (fit != 'tight') 'fit': fit},
    children: [child],
  );

  /// Tappable button. [variant] follows the design system: 'primary',
  /// 'secondary', 'tertiary', 'success', 'error', 'warning'. [color] is an
  /// explicit `#RRGGBB` fill that overrides the variant's, for a button that
  /// wants a specific color. [data] is passed to the event handler, which lets
  /// one [eventId] serve many buttons.
  /// A button.
  ///
  /// [size] is 'sm', 'md' (the default) or 'lg' - one scale, drawn the same way
  /// by every renderer:
  ///
  /// | size | height | text | padding |
  /// |------|--------|------|---------|
  /// | sm   | 28     | 12   | 12      |
  /// | md   | 36     | 14   | 16      |
  /// | lg   | 44     | 16   | 24      |
  ///
  /// 'md' is left out of the tree, being the default a renderer draws anyway.
  ///
  /// [minHeight], [minWidth], [fontSize], [paddingHorizontal] and
  /// [paddingVertical] override the scale one value at a time, for a button
  /// that has to be a particular shape rather than one of three.
  ///
  /// Two more variants are Material's own: 'outlined' (a border, no fill) and
  /// 'tonal' (a quiet fill of the primary colour). They are what
  /// the widget layer's `ElevatedButton.styleFrom(padding:, minimumSize:,
  /// textStyle:)` turns into, which is how a Flutter-shaped app asks.
  static WidgetNode button({
    required String label,
    String? eventId,
    void Function()? onPressed,
    String variant = 'primary',
    String size = 'md',
    String? color,
    double? minHeight,
    double? minWidth,
    double? fontSize,
    double? paddingHorizontal,
    double? paddingVertical,
    Map<String, dynamic>? data,
    bool disabled = false,
    int? iconCodepoint,
    String? foregroundColor,
    bool expand = false,
    String? id,
  }) {
    // A disabled button has nothing to fire, so it needs no handler; every
    // other button still must carry one.
    if (!(disabled && eventId == null && onPressed == null)) {
      eventId = _bindTap(eventId, onPressed, id);
    }
    return WidgetNode(
      type: 'Button',
      props: {
        'label': label,
        if (eventId != null) 'eventId': eventId,
        'variant': variant,
        if (size != 'md') 'size': size,
        if (color != null) 'color': color,
        if (minHeight != null) 'minHeight': minHeight,
        if (minWidth != null) 'minWidth': minWidth,
        if (fontSize != null) 'fontSize': fontSize,
        if (paddingHorizontal != null) 'paddingHorizontal': paddingHorizontal,
        if (paddingVertical != null) 'paddingVertical': paddingVertical,
        if (data != null) 'data': data,
        'disabled': disabled,
        // A Material Icons glyph before the label.
        if (iconCodepoint != null) 'iconCodepoint': iconCodepoint,
        if (foregroundColor != null) 'foregroundColor': foregroundColor,
        // Fills the width it is offered instead of hugging its label.
        if (expand) 'expand': true,
        if (id != null) 'id': id,
      },
    );
  }

  /// Icon-only button; [icon] is a Material Icons name (e.g. 'delete').
  ///
  /// The name is resolved to a Material Icons codepoint so the native renderers
  /// draw the real glyph from the bundled font; for an icon not in that table,
  /// pass its [codepoint] directly (e.g. `Icons.rocket_launch.codePoint`).
  static WidgetNode iconButton({
    required String icon,
    int? codepoint,
    String? eventId,
    void Function()? onPressed,
    required String tooltip,
    Map<String, dynamic>? data,
    String? color,
    double? size,
    bool disabled = false,
    String? id,
  }) {
    if (!(disabled && eventId == null && onPressed == null)) {
      eventId = _bindTap(eventId, onPressed, id);
    }
    final resolved = codepoint ?? materialIconCodepoint(icon);
    return WidgetNode(
      type: 'IconButton',
      props: {
        'icon': icon,
        if (resolved != null) 'iconCodepoint': resolved,
        if (eventId != null) 'eventId': eventId,
        if (disabled) 'disabled': true,
        if (color != null) 'color': color,
        if (size != null) 'size': size,
        'tooltip': tooltip,
        if (data != null) 'data': data,
        if (id != null) 'id': id,
      },
    );
  }

  /// Checkbox; the handler receives `{'checked': bool}` plus [data].
  ///
  /// [disabled] draws the box as the platform draws one that cannot be
  /// changed - greyed, taking no tap and no focus - and nothing is sent for
  /// it. The same prop means the same thing on a `Radio` and a `Toggle` node
  /// (the design system's `DSRadio` and `DSToggle`, the widget layer's `Radio`
  /// and `Switch` with a null `onChanged`). It is patched like `checked`: a
  /// control that becomes available again is the same control, enabled.
  static WidgetNode checkbox({
    String? eventId,
    void Function(bool checked)? onChanged,
    required bool checked,
    String? label,
    Map<String, dynamic>? data,
    bool disabled = false,
    String? id,
  }) {
    if (onChanged != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.onToggle(eventId, onChanged);
    } else if (disabled) {
      // A disabled box has nothing to report, so it needs no handler. It is
      // still given an id: every renderer has always been handed one on a
      // checkbox, and a box that is enabled again later keeps the same node
      // shape.
      eventId ??= EventBindings.required.allocate(key: id);
    }
    return WidgetNode(
      type: 'Checkbox',
      props: {
        'eventId': _require(eventId, 'checkbox'),
        'checked': checked,
        if (label != null) 'label': label,
        if (disabled) 'disabled': true,
        if (data != null) 'data': data,
        if (id != null) 'id': id,
      },
    );
  }

  /// A value chosen by dragging along a track.
  ///
  /// [value] is where the thumb sits, between [min] and [max]. [divisions]
  /// snaps it to that many equal steps, as Flutter's `Slider` does; without it
  /// the value is continuous.
  ///
  /// [onChanged] fires as the thumb moves and [onChangeEnd] when it is let go,
  /// which is the one to save on: a slider dragged across a screen sends a
  /// great many values and only the last is a decision.
  static WidgetNode slider({
    required double value,
    String? eventId,
    void Function(double value)? onChanged,
    void Function(double value)? onChangeEnd,
    double min = 0,
    double max = 1,
    int? divisions,
    bool disabled = false,
    String? id,
  }) {
    if (onChanged != null || onChangeEnd != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.onSlide(
        eventId,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
    } else if (!disabled) {
      // A disabled slider has nothing to report, so it needs no handler; one
      // that can be dragged must have somewhere to send the value.
      eventId = _require(eventId, 'slider');
    }
    return WidgetNode(
      type: 'Slider',
      props: {
        if (eventId != null) 'eventId': eventId,
        'value': value,
        'min': min,
        'max': max,
        if (divisions != null) 'divisions': divisions,
        'disabled': disabled,
        if (id != null) 'id': id,
      },
    );
  }

  /// Children laid out in [crossAxisCount] equal columns, row by row.
  ///
  /// [childAspectRatio] is a cell's width divided by its height, as in
  /// Flutter's `GridView.count`: 1 makes squares, 2 makes cells twice as wide
  /// as they are tall. Every cell is the same size, which is what separates a
  /// grid from a [wrap].
  ///
  /// The grid sizes to its rows rather than scrolling: a screenful of cells is
  /// reached through the scaffold's own scrolling, and a list long enough to
  /// need windowing is a [lazyList].
  static WidgetNode grid({
    required List<WidgetNode> children,
    int crossAxisCount = 2,
    double spacing = 0,
    double runSpacing = 0,
    double childAspectRatio = 1,
  }) => WidgetNode(
    type: 'GridView',
    props: {
      'crossAxisCount': crossAxisCount,
      'spacing': spacing,
      'runSpacing': runSpacing,
      'childAspectRatio': childAspectRatio,
    },
    children: children,
  );

  /// A strip of labels, one of them selected.
  ///
  /// The bar only: what the selected tab shows is the app's own tree, swapped
  /// when [onChanged] fires. That keeps the selection where every other piece
  /// of state in this framework lives - in the app - rather than inside a
  /// controller the renderers would each have to own.
  ///
  /// Each renderer draws its platform's way of choosing one of a few things:
  /// Material tabs on Android and in Flutter, a segmented control on iOS, a
  /// tab strip on web.
  static WidgetNode tabs({
    required List<String> tabs,
    required int selectedIndex,
    String? eventId,
    void Function(int index)? onChanged,
    String? id,
  }) {
    if (onChanged != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.on(
        eventId,
        (data) => onChanged((data['index'] as num?)?.toInt() ?? 0),
      );
    }
    return WidgetNode(
      type: 'Tabs',
      props: {
        'eventId': _require(eventId, 'tabs'),
        'tabs': tabs,
        'selectedIndex': selectedIndex,
        if (id != null) 'id': id,
      },
    );
  }

  /// A box whose size and colour move when they change.
  ///
  /// The protocol says what a screen *is*, so a renderer animates the
  /// difference it sees: the first render sets the box, and every later one
  /// that changes [width], [height] or [color] moves from where it was over
  /// [duration], along [curve].
  ///
  /// What it carries is size and colour. Padding, alignment and borders are
  /// not animated - a change to those lands at once - because each would need
  /// the same treatment in four layout systems and none of them is what an
  /// app reaches for first.
  ///
  /// [curve] is 'linear', 'ease', 'easeIn', 'easeOut' or 'easeInOut'; each
  /// renderer maps it onto its own (a CSS timing function, a Flutter `Curve`,
  /// an Android `Interpolator`, a UIKit animation option).
  static WidgetNode animatedContainer({
    required WidgetNode child,
    double? width,
    double? height,
    String? color,
    Duration duration = const Duration(milliseconds: 200),
    String curve = 'easeInOut',
  }) => WidgetNode(
    type: 'AnimatedContainer',
    props: {
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (color != null) 'color': color,
      'durationMs': duration.inMilliseconds,
      'curve': curve,
    },
    children: [child],
  );

  /// Fades [child] to [opacity] over [duration] whenever the value changes.
  ///
  /// The protocol says what a screen *is*, not how it got there, so a renderer
  /// animates the difference it sees: the first render sets the opacity, and
  /// every later one that changes it fades from where it was. A renderer that
  /// rebuilt the view instead would jump, which is why each of them patches
  /// this node in place.
  static WidgetNode animatedOpacity({
    required WidgetNode child,
    required double opacity,
    Duration duration = const Duration(milliseconds: 200),
    String curve = 'easeInOut',
  }) => WidgetNode(
    type: 'AnimatedOpacity',
    props: {
      'opacity': opacity,
      'durationMs': duration.inMilliseconds,
      'curve': curve,
    },
    children: [child],
  );

  static WidgetNode center({required WidgetNode child}) =>
      WidgetNode(type: 'Center', props: {}, children: [child]);

  /// A row that reveals trailing [actions] when swiped left: a partial swipe
  /// shows the action buttons to tap, a full swipe fires the first one. Each
  /// action is `(label, color, onPressed)`; the onPressed becomes an event id.
  static WidgetNode swipeActions({
    required WidgetNode child,
    required List<({String label, String color, void Function() onPressed})>
        actions,
    List<({String label, String color, void Function() onPressed})>
        leadingActions = const [],
    String? id,
  }) {
    List<Map<String, dynamic>> nodesFor(
      List<({String label, String color, void Function() onPressed})> from,
      String prefix,
    ) => [
      for (final (i, a) in from.indexed)
        {
          'label': a.label,
          'color': a.color,
          'eventId': _bindTap(
            null,
            a.onPressed,
            id == null ? null : '$id.$prefix$i',
          ),
        },
    ];
    final actionNodes = nodesFor(actions, 'a');
    final leadingNodes = nodesFor(leadingActions, 'l');
    return WidgetNode(
      type: 'SwipeActions',
      props: {
        'actions': actionNodes,
        if (leadingNodes.isNotEmpty) 'leadingActions': leadingNodes,
        if (id != null) 'id': id,
      },
      children: [child],
    );
  }

  /// Text. Styling is optional: [color] is a CSS/hex color, [fontWeight] a
  /// CSS weight (400, 700...), [decoration] 'lineThrough' or 'underline'.
  /// A run of text.
  ///
  /// [maxLines] caps how many lines it may take, and [overflow] says what
  /// happens to what does not fit: 'ellipsis' ends the last line with `…`,
  /// 'clip' cuts it off. Without [maxLines] the text wraps as far as it likes,
  /// which is what every renderer already did.
  static WidgetNode text(
    String content, {
    double? fontSize,
    int? fontWeight,
    String? color,
    String? decoration,
    int? maxLines,
    String? overflow,
    String? textAlign,
    double? letterSpacing,
    double? lineHeight,
    String? fontFamily,
    bool italic = false,
    bool selectable = false,
    List<Map<String, dynamic>>? spans,
    String? id,
  }) => WidgetNode(
    type: 'Text',
    props: {
      'content': content,
      // 'left', 'center', 'right' or 'justify'; 'start' is the absence of one.
      if (textAlign != null) 'textAlign': textAlign,
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
      // A multiple of the font size, as CSS `line-height` and Flutter's
      // `TextStyle.height` both spell it.
      if (lineHeight != null) 'lineHeight': lineHeight,
      // A family name, or the generic 'monospace' / 'serif'.
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (italic) 'italic': true,
      if (selectable) 'selectable': true,
      // Runs with their own style: each is `{text, color?, fontSize?,
      // fontWeight?, decoration?, italic?}` and inherits the rest from the
      // node. `content` stays the whole string, for a renderer or a test that
      // only wants the words.
      if (spans != null) 'spans': spans,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight,
      if (color != null) 'color': color,
      if (decoration != null) 'decoration': decoration,
      if (maxLines != null) 'maxLines': maxLines,
      if (overflow != null) 'overflow': overflow,
      if (id != null) 'id': id,
    },
  );

  /// An image.
  ///
  /// [src] is a URL (`http://`, `https://`, `data:`) or a path the platform
  /// resolves against its own assets. [fit] follows CSS `object-fit`:
  /// 'cover' (default), 'contain', 'fill', 'none' or 'scaleDown'.
  ///
  /// [alt] is what a screen reader announces, and what a renderer shows if the
  /// image cannot be loaded - so it is required rather than optional.
  ///
  /// [fallback] is drawn *instead of* the [alt] text wherever a renderer would
  /// have shown it: while the image is on its way, and for good if it never
  /// arrives. It travels as the node's one child and takes the image's place -
  /// its [width] and [height] where they are stated - so an avatar can fall
  /// back to initials or a logo to a glyph without the app stacking one over
  /// the other and never learning which of them is showing. [alt] is still
  /// what a screen reader is told. A node with no child behaves as it always
  /// has.
  ///
  /// A remote image is cached by whatever draws it - the browser, Flutter's
  /// image cache, and on the native renderers a decoded-bitmap cache in memory
  /// over the platform's HTTP cache on disk - so a rebuild does not fetch it
  /// again, and one already in memory is drawn at once, with no fallback in
  /// between.
  static WidgetNode image({
    required String src,
    required String alt,
    double? width,
    double? height,
    String fit = 'cover',
    WidgetNode? fallback,
    String? id,
  }) => WidgetNode(
    type: 'Image',
    props: {
      'src': src,
      'alt': alt,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      'fit': fit,
      if (id != null) 'id': id,
    },
    children: fallback == null ? null : [fallback],
  );

  /// A web page embedded in the screen.
  ///
  /// Drawn with the platform's own browser view - `WKWebView`, Android's
  /// `WebView`, an `<iframe>` on the web. The Flutter-hosted target cannot draw
  /// one without `webview_flutter`, which the framework does not depend on, so
  /// it shows a placeholder saying so rather than pretending.
  ///
  /// [height] is needed for the same reason a lazy list needs one: a web view
  /// has no size of its own, and a scaffold's body scrolls, so one left to its
  /// own devices would collapse to nothing.
  ///
  /// [javaScriptEnabled] is off by default, which is the safer default and the
  /// one `webview_flutter` takes: a page that only needs to be read does not
  /// need to run code, and turning it on for a page you do not control gives it
  /// the run of the view.
  static WidgetNode webView({
    required String url,
    double height = 300,
    bool javaScriptEnabled = false,
    String? id,
  }) => WidgetNode(
    type: 'WebView',
    props: {
      'url': url,
      'height': height,
      'javaScriptEnabled': javaScriptEnabled,
      if (id != null) 'id': id,
    },
  );

  /// A map centred on [latitude]/[longitude] at [zoom].
  ///
  /// Drawn by the platform where the platform has one: MapKit on iOS, which is
  /// free and needs no key. On web there is no platform map, so the renderer
  /// lays out raster tiles from [tileUrl] - OpenStreetMap's by default, which
  /// is free, asks for attribution (the renderer draws it) and asks that heavy
  /// use go elsewhere, so a shipped app should point [tileUrl] at its own tile
  /// source. Android and the Flutter host draw a placeholder: the Maps SDK
  /// needs a dependency *and* an API key, which is a decision for the app
  /// rather than the framework (see TODO.md §2.2).
  ///
  /// [zoom] is the slippy-map scale every web map uses - 0 is the world, 15 a
  /// neighbourhood, 18 a building - and iOS converts it to a region.
  ///
  /// With [onCameraIdle], the map reports where it ended up *after* a pan or a
  /// zoom settles, never during: a position per frame would render the whole
  /// tree per frame.
  static WidgetNode map({
    required double latitude,
    required double longitude,
    double zoom = 13,
    double height = 300,
    List<({double latitude, double longitude, String? label})> markers =
        const [],
    bool interactive = true,
    String? tileUrl,
    String? eventId,
    void Function(double latitude, double longitude, double zoom)? onCameraIdle,
    String? id,
  }) {
    if (onCameraIdle != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.on('${eventId}_idle', (data) {
        final lat = (data['latitude'] as num?)?.toDouble() ?? latitude;
        final lng = (data['longitude'] as num?)?.toDouble() ?? longitude;
        final level = (data['zoom'] as num?)?.toDouble() ?? zoom;
        onCameraIdle(lat, lng, level);
      });
    }
    return WidgetNode(
      type: 'MapView',
      props: {
        'latitude': latitude,
        'longitude': longitude,
        'zoom': zoom,
        'height': height,
        'interactive': interactive,
        if (tileUrl != null) 'tileUrl': tileUrl,
        if (eventId != null) 'eventId': eventId,
        if (markers.isNotEmpty)
          'markers': [
            for (final marker in markers)
              {
                'latitude': marker.latitude,
                'longitude': marker.longitude,
                if (marker.label != null) 'label': marker.label,
              },
          ],
        if (id != null) 'id': id,
      },
    );
  }

  /// A live camera preview.
  ///
  /// Drawn where a camera costs nothing but a permission: `AVCapture` on iOS
  /// and `getUserMedia` on web. Android needs the CameraX dependency and the
  /// Flutter host the `camera` plugin, so both draw a placeholder (TODO.md
  /// §2.2).
  ///
  /// The app still has to ask for the permission in its own manifest: an iOS
  /// app needs `NSCameraUsageDescription` in Info.plist or the system kills it
  /// on the first frame, and a browser only offers the camera on a secure
  /// origin (https, or localhost).
  ///
  /// [facing] is 'back' or 'front'. [active] false stops the camera without
  /// taking the node out of the tree, which is what a screen behind a dialog
  /// should do - a preview nobody is looking at still costs battery and heat.
  ///
  /// Frames never reach Dart. The camera renders to its own surface, and
  /// [onStatus] only says whether it started: 'ready', 'denied' (the permission
  /// was refused), 'unavailable' (no camera on this device) or 'error'.
  static WidgetNode cameraPreview({
    double height = 300,
    String facing = 'back',
    bool active = true,
    String? eventId,
    void Function(String status, String? message)? onStatus,
    String? id,
  }) {
    if (onStatus != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.on('${eventId}_status', (data) {
        onStatus('${data['status'] ?? 'error'}', data['message'] as String?);
      });
    }
    return WidgetNode(
      type: 'CameraPreview',
      props: {
        'height': height,
        'facing': facing,
        'active': active,
        if (eventId != null) 'eventId': eventId,
        if (id != null) 'id': id,
      },
    );
  }

  static WidgetNode floatingActionButton({
    required String tooltip,
    String? eventId,
    void Function()? onPressed,
    String icon = 'add',
    int? codepoint,
    String? label,
    String? id,
  }) {
    eventId = _bindTap(eventId, onPressed, id);
    final resolved = codepoint ?? materialIconCodepoint(icon);
    return WidgetNode(
      type: 'FloatingActionButton',
      props: {
        'tooltip': tooltip,
        // Text beside the icon: Material's extended button, a pill rather
        // than a circle.
        if (label != null) 'label': label,
        'eventId': eventId,
        'icon': icon,
        if (resolved != null) 'iconCodepoint': resolved,
        if (id != null) 'id': id,
      },
    );
  }

  /// Space around [child].
  ///
  /// [all] sets every edge; [left], [top], [right] and [bottom] override it one
  /// at a time, so `padding(all: 8, top: 24, child: ...)` reads as it looks.
  ///
  /// Uniform padding travels as one number and anything else as four, so a
  /// tree says which it meant and a renderer never has to guess from a single
  /// value what the app asked for.
  static WidgetNode padding({
    double all = 0,
    double? left,
    double? top,
    double? right,
    double? bottom,
    required WidgetNode child,
  }) {
    final l = left ?? all;
    final t = top ?? all;
    final r = right ?? all;
    final b = bottom ?? all;
    final uniform = l == t && t == r && r == b;
    return WidgetNode(
      type: 'Padding',
      props: uniform
          ? {'padding': l}
          : {
              'paddingLeft': l,
              'paddingTop': t,
              'paddingRight': r,
              'paddingBottom': b,
            },
      children: [child],
    );
  }

  static WidgetNode sizedBox({double? height, double? width}) => WidgetNode(
    type: 'SizedBox',
    props: {
      if (height != null) 'height': height,
      if (width != null) 'width': width,
    },
  );

  /// A text field, optionally with a [label] above or inside its outline.
  ///
  /// With [floatingLabel] - the default, and what Flutter does - the label sits
  /// in the field's outline and rises out of the way as soon as there is
  /// something to read: Material's `TextInputLayout` on Android, a CSS label on
  /// web, `InputDecoration.labelText` on the Flutter host. The native iOS
  /// renderer keeps the label above the field whatever this says, because UIKit
  /// has no floating label and iOS forms do not use one.
  ///
  /// Pass `floatingLabel: false` for a plain label above the field on every
  /// renderer.
  static WidgetNode textField({
    required String hint,
    String? eventId,
    void Function(String value)? onChanged,
    void Function(String value)? onSubmitted,
    String? id,
    String? label,
    String? error,
    bool obscureText = false,
    bool enabled = true,
    String? initialValue,
    int maxLines = 1,
    String textInputAction = 'done',
    bool floatingLabel = true,
    bool autofocus = false,
    int? focusVersion,
    bool focusRequested = true,
    String? keyboardType,
    bool readOnly = false,
    void Function()? onTap,
    String? helper,
    int? prefixIconCodepoint,
    int? suffixIconCodepoint,
    void Function()? onSuffixTap,
    int? maxLength,
    String? textCapitalization,
    String? textAlign,
  }) {
    if (onChanged != null ||
        onSubmitted != null ||
        onTap != null ||
        onSuffixTap != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.onText(eventId, onChanged: onChanged, onSubmitted: onSubmitted);
      if (onTap != null) bindings.onTap('${eventId}_tap', onTap);
      if (onSuffixTap != null) bindings.onTap('${eventId}_suffix', onSuffixTap);
    }
    return WidgetNode(
      type: 'TextField',
      props: {
        'hint': hint,
        'eventId': _require(eventId, 'textField'),
        if (id != null) 'id': id,
        if (label != null) 'label': label,
        // Absent means floating, which is the default; only the opt-out is
        // recorded, so a tree carries the flag exactly when it says something.
        if (label != null && !floatingLabel) 'floatingLabel': false,
        // Focus the field the first time it is drawn, and again whenever the
        // app asks: the version is what a renderer compares, the same trick a
        // controller's value uses, because "focus this" is a moment rather
        // than a state and a tree only carries states.
        if (autofocus) 'autofocus': true,
        if (focusVersion != null) 'focusVersion': focusVersion,
        if (focusVersion != null && !focusRequested) 'focusRequested': false,
        if (error != null) 'error': error,
        'obscureText': obscureText,
        'enabled': enabled,
        if (initialValue != null) 'initialValue': initialValue,
        'maxLines': maxLines,
        // What the keyboard's return key says and does: 'done' closes it,
        // 'next' moves to the field after this one. A renderer that cannot
        // find a next field falls back to closing, so 'next' is never a dead
        // key.
        'textInputAction': textInputAction,
        // 'text' (the default, left out), 'number', 'decimal', 'email',
        // 'phone', 'url' or 'multiline': which keyboard the platform raises.
        if (keyboardType != null && keyboardType != 'text')
          'keyboardType': keyboardType,
        // Shows its value and takes focus but not typing: a field that opens
        // a picker. `<eventId>_tap` fires when it is tapped.
        if (readOnly) 'readOnly': true,
        if (onTap != null) 'tappable': true,
        if (helper != null) 'helper': helper,
        if (prefixIconCodepoint != null) 'prefixIcon': prefixIconCodepoint,
        // A glyph at the end of the field; `<eventId>_suffix` fires on a tap,
        // which is how a clear or a show-password button is made.
        if (suffixIconCodepoint != null) 'suffixIcon': suffixIconCodepoint,
        if (onSuffixTap != null) 'suffixTappable': true,
        if (maxLength != null) 'maxLength': maxLength,
        // 'none', 'words', 'sentences' or 'characters'.
        if (textCapitalization != null)
          'textCapitalization': textCapitalization,
        if (textAlign != null) 'textAlign': textAlign,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Free-form composition
  //
  // Everything above names a component. These name the pieces components are
  // made of, for the screen no component describes: a tile with a border and a
  // shadow, a badge pinned over a corner, a game board.
  //
  // Colours here and everywhere else are `#rrggbb` or `#aarrggbb`.
  // Alignments are `[x, y]` pairs from -1 (left/top) to 1 (right/bottom).
  // ---------------------------------------------------------------------------

  /// A box: size, space, paint and touch around at most one [child].
  ///
  /// **Size.** [width]/[height] fix it; the min/max pairs bound it; [expand]
  /// ('width', 'height' or 'both') fills what the parent offers on that axis;
  /// [aspectRatio] (width / height) derives the free axis from the other.
  /// With none of these the box hugs its child.
  ///
  /// **Space.** [padding] is inside the paint, [margin] outside it, each as
  /// `[left, top, right, bottom]`. [alignment] places the child inside a box
  /// larger than it; without one the child fills the box's content area.
  ///
  /// **Paint.** [color] or [gradient] fills; [borderWidth]/[borderColor]
  /// outline; [borderRadius] rounds every corner, or [borderRadii] rounds each
  /// (`[topLeft, topRight, bottomRight, bottomLeft]`); `shape: 'circle'` makes
  /// it round; [shadow] is `{color, blur, dx, dy}`. [clip] cuts the child to
  /// the shape. [opacity] fades the box and its child together. [transform] is
  /// `{rotate (radians), scale, dx, dy}`, applied about the centre.
  ///
  /// [gradient] is `{type: 'linear'|'radial', colors: [...], stops: [...]?,
  /// begin: [x, y], end: [x, y]}`.
  ///
  /// **Touch.** [onTap], [onDoubleTap] and [onLongPress] fire with
  /// `{x, y}` - the point, in the box's own logical pixels. [onPan] fires
  /// `<id>_start`, `<id>_update` and `<id>_end` with `{x, y, dx, dy, vx, vy}`:
  /// position, movement since the last event, and (on end) velocity in
  /// pixels per second. [ripple] asks for the platform's touch feedback.
  ///
  /// **Drag and drop.** A box with [dragData] can be picked up (after a long
  /// press where the platform distinguishes) and a box with [onDrop] receives
  /// the string another box carried. `<dropEventId>_hover` fires with
  /// `{over: bool}` as a drag enters and leaves.
  ///
  /// **Measuring.** [onSize] fires with `{width, height}` when the box is laid
  /// out and whenever that changes, which is how a screen learns how much room
  /// it was given.
  ///
  /// **Motion.** With [animateMs], a change to size, colour, opacity or
  /// transform moves there over that long instead of landing at once.
  ///
  /// **Accessibility.** A box that takes a tap is announced as a button named
  /// by the text inside it; [semanticLabel] names it instead, and names a box
  /// that holds no text at all (an icon, a drawing). [semanticRole] says what
  /// it is where the renderer cannot tell - one of [semanticRoles]; it is
  /// read off *any* node, not only a box. [semanticValue] is the state said
  /// after the name ("40%"). [liveRegion] has a change to the box's content
  /// announced without the reader moving to it, and [excludeSemantics] hides
  /// everything inside the box, leaving its own label. [disabled] says a
  /// button drawn from a box is switched off - it has no tap to be found by,
  /// so without this it is only some dimmed text. [selected] makes it
  /// something that is on or off (a filter chip) and says which. [tooltip] stands in
  /// for a missing label. The node's [id] is exposed as the element's
  /// identifier: Android's resource name, iOS's accessibility identifier, the
  /// DOM `id` - what a device test's `id` selector matches.
  static WidgetNode box({
    WidgetNode? child,
    double? width,
    double? height,
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
    String? expand,
    double? aspectRatio,
    List<double>? padding,
    List<double>? margin,
    List<double>? alignment,
    String? color,
    Map<String, dynamic>? gradient,
    double? borderWidth,
    String? borderColor,
    double? borderRadius,
    List<double>? borderRadii,
    String? shape,
    Map<String, dynamic>? shadow,
    bool clip = false,
    double? opacity,
    Map<String, dynamic>? transform,
    void Function(double x, double y)? onTap,
    void Function(double x, double y)? onDoubleTap,
    void Function(double x, double y)? onLongPress,
    void Function(String phase, Map<String, dynamic> data)? onPan,
    bool ripple = false,
    String? dragData,
    void Function(String data)? onDrop,
    void Function(bool over)? onDropHover,
    void Function(double width, double height)? onSize,
    int? animateMs,
    String? curve,
    String? semanticLabel,
    String? semanticRole,
    String? semanticValue,
    bool liveRegion = false,
    bool excludeSemantics = false,
    bool disabled = false,
    bool? selected,
    String? tooltip,
    bool ignorePointer = false,
    String? id,
  }) {
    double n(Map<String, dynamic> d, String k) =>
        (d[k] as num?)?.toDouble() ?? 0;
    String? bind(
      String suffix,
      void Function(Map<String, dynamic>)? handler, {
      List<String> phases = const [''],
    }) {
      if (handler == null) return null;
      final bindings = EventBindings.required;
      final eventId = bindings.allocate(key: id == null ? null : '$id.$suffix');
      for (final phase in phases) {
        bindings.on(
          '$eventId$phase',
          phase.isEmpty ? handler : (data) => handler({...data, 'phase': phase}),
        );
      }
      return eventId;
    }

    final tap = bind('tap', onTap == null ? null : (d) => onTap(n(d, 'x'), n(d, 'y')));
    final doubleTap = bind(
      'doubleTap',
      onDoubleTap == null ? null : (d) => onDoubleTap(n(d, 'x'), n(d, 'y')),
    );
    final longPress = bind(
      'longPress',
      onLongPress == null ? null : (d) => onLongPress(n(d, 'x'), n(d, 'y')),
    );
    final pan = bind(
      'pan',
      onPan == null
          ? null
          : (d) => onPan('${d['phase']}'.substring(1), d),
      phases: const ['_start', '_update', '_end'],
    );
    final drop = bind(
      'drop',
      onDrop == null ? null : (d) => onDrop('${d['data'] ?? ''}'),
    );
    if (drop != null && onDropHover != null) {
      EventBindings.required.on(
        '${drop}_hover',
        (d) => onDropHover(d['over'] == true),
      );
    }
    final size = bind(
      'size',
      onSize == null ? null : (d) => onSize(n(d, 'width'), n(d, 'height')),
    );
    return WidgetNode(
      type: 'Box',
      props: {
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (minWidth != null) 'minWidth': minWidth,
        if (maxWidth != null) 'maxWidth': maxWidth,
        if (minHeight != null) 'minHeight': minHeight,
        if (maxHeight != null) 'maxHeight': maxHeight,
        if (expand != null) 'expand': expand,
        if (aspectRatio != null) 'aspectRatio': aspectRatio,
        if (padding != null) 'padding': padding,
        if (margin != null) 'margin': margin,
        if (alignment != null) 'alignment': alignment,
        if (color != null) 'color': color,
        if (gradient != null) 'gradient': gradient,
        if (borderWidth != null) 'borderWidth': borderWidth,
        if (borderColor != null) 'borderColor': borderColor,
        if (borderRadius != null) 'borderRadius': borderRadius,
        if (borderRadii != null) 'borderRadii': borderRadii,
        if (shape != null) 'shape': shape,
        if (shadow != null) 'shadow': shadow,
        if (clip) 'clip': true,
        if (opacity != null) 'opacity': opacity,
        if (transform != null) 'transform': transform,
        if (tap != null) 'tapEventId': tap,
        if (doubleTap != null) 'doubleTapEventId': doubleTap,
        if (longPress != null) 'longPressEventId': longPress,
        if (pan != null) 'panEventId': pan,
        if (ripple) 'ripple': true,
        if (dragData != null) 'dragData': dragData,
        if (drop != null) 'dropEventId': drop,
        if (size != null) 'sizeEventId': size,
        if (animateMs != null) 'animateMs': animateMs,
        if (curve != null) 'curve': curve,
        if (semanticLabel != null) 'semanticLabel': semanticLabel,
        if (semanticRole != null) 'semanticRole': semanticRole,
        if (semanticValue != null) 'semanticValue': semanticValue,
        if (liveRegion) 'liveRegion': true,
        if (excludeSemantics) 'excludeSemantics': true,
        if (disabled) 'disabled': true,
        if (selected != null) 'selected': selected,
        if (tooltip != null) 'tooltip': tooltip,
        if (ignorePointer) 'ignorePointer': true,
        if (id != null) 'id': id,
      },
      children: [if (child != null) child],
    );
  }

  /// Children drawn over one another, first at the back.
  ///
  /// A child that is a [positioned] node is pinned to the edges it names; the
  /// rest sit at [alignment] and are what the stack sizes itself to (`fit:
  /// 'expand'` instead makes them fill it). [clip] false lets a child draw
  /// outside the stack's bounds.
  static WidgetNode stack({
    required List<WidgetNode> children,
    List<double> alignment = const [-1, -1],
    String fit = 'loose',
    bool clip = true,
    String? id,
  }) => WidgetNode(
    type: 'Stack',
    props: {
      'alignment': alignment,
      if (fit != 'loose') 'fit': fit,
      if (!clip) 'clip': false,
      if (id != null) 'id': id,
    },
    children: children,
  );

  /// Pins [child] inside a [stack]: each of [left], [top], [right], [bottom]
  /// is a distance from that edge, and two opposite edges stretch the child
  /// between them. [fill] is all four at zero. Outside a stack it is its child.
  static WidgetNode positioned({
    required WidgetNode child,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
    bool fill = false,
  }) => WidgetNode(
    type: 'Positioned',
    props: {
      if (fill || left != null) 'left': left ?? 0,
      if (fill || top != null) 'top': top ?? 0,
      if (fill || right != null) 'right': right ?? 0,
      if (fill || bottom != null) 'bottom': bottom ?? 0,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    },
    children: [child],
  );

  /// Scrolls [child] along [axis] ('vertical' or 'horizontal').
  ///
  /// It takes the room it is given on its axis, so give it bounded room: the
  /// body of a scaffold whose own scrolling is off, or an [expanded].
  /// [shrinkWrap] makes it as long as its child instead, and then it does not
  /// scroll - which is what a list inside another scroller wants.
  ///
  /// [scrollOffset] with [scrollVersion] moves it from code - see the props.
  ///
  /// [onScroll] hears where the reader has got to: the node then carries a
  /// `scrollEventId`, and the renderer sends it `{offset, maxExtent,
  /// viewport}` in logical pixels - the distance from the start (from the far
  /// end when [reverse]), how far that can go, and how long the scroller is
  /// on its axis. It is sent when the scroller comes to rest and at most
  /// about every 100 ms while it moves, never once per frame, so it is right
  /// for remembering a position and for "near the end, load more", and not
  /// for moving something in step with a finger.
  ///
  /// [onRefresh] adds pull-to-refresh where the platform has the gesture; the
  /// spinner stays for as long as the tree says [refreshing].
  static WidgetNode scroll({
    required WidgetNode child,
    String axis = 'vertical',
    List<double>? padding,
    bool shrinkWrap = false,
    bool reverse = false,
    void Function()? onRefresh,
    bool refreshing = false,
    double? scrollOffset,
    int? scrollVersion,
    void Function(double offset, double? maxExtent, double? viewport)?
    onScroll,
    String? id,
  }) {
    String? refresh;
    if (onRefresh != null) {
      final bindings = EventBindings.required;
      refresh = bindings.allocate(key: id == null ? null : '$id.refresh');
      bindings.onTap(refresh, onRefresh);
    }
    String? scrolled;
    if (onScroll != null) {
      final bindings = EventBindings.required;
      scrolled = bindings.allocate(key: id == null ? null : '$id.scroll');
      bindings.on(scrolled, (data) {
        final offset = (data['offset'] as num?)?.toDouble();
        if (offset == null) return;
        onScroll(
          offset,
          (data['maxExtent'] as num?)?.toDouble(),
          (data['viewport'] as num?)?.toDouble(),
        );
      });
    }
    return WidgetNode(
      type: 'Scroll',
      props: {
        if (axis != 'vertical') 'axis': axis,
        if (padding != null) 'padding': padding,
        if (shrinkWrap) 'shrinkWrap': true,
        if (reverse) 'reverse': true,
        if (refresh != null) 'refreshEventId': refresh,
        if (refresh != null) 'refreshing': refreshing,
        // Where to scroll to, and a version that says when: "scroll there" is
        // a moment rather than a state, so a renderer jumps to the offset on
        // the first render and whenever the version it sees is a new one -
        // the same trick a text field's focusVersion uses.
        if (scrollOffset != null) 'scrollOffset': scrollOffset,
        if (scrollOffset != null) 'scrollVersion': scrollVersion ?? 0,
        if (scrolled != null) 'scrollEventId': scrolled,
        if (id != null) 'id': id,
      },
      children: [child],
    );
  }

  /// One glyph of an icon font - Material Icons unless [fontFamily] says
  /// otherwise. [color] defaults to the surrounding text colour, [size] to 24.
  static WidgetNode icon({
    required int codepoint,
    double? size,
    String? color,
    String? fontFamily,
    String? semanticLabel,
    String? id,
  }) => WidgetNode(
    type: 'Icon',
    props: {
      'codepoint': codepoint,
      if (size != null) 'size': size,
      if (color != null) 'color': color,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (semanticLabel != null) 'semanticLabel': semanticLabel,
      if (id != null) 'id': id,
    },
  );

  /// A surface drawn by a list of [commands].
  ///
  /// The tree says what the picture *is*; a renderer replays it into its own
  /// canvas - Android's `Canvas`, Core Graphics, a `<canvas>` element, a
  /// Flutter `CustomPaint`. A render that changes only the commands repaints
  /// the surface in place, so a game can send a frame per tick.
  ///
  /// Each command is a list whose first element is its name. Coordinates are
  /// logical pixels from the top left; angles are radians, clockwise from
  /// three o'clock. `p` is an index into [paints].
  ///
  /// | command | arguments |
  /// |---|---|
  /// | `rect` | l, t, w, h, p |
  /// | `rrect` | l, t, w, h, radius, p |
  /// | `circle` | cx, cy, r, p |
  /// | `oval` | l, t, w, h, p |
  /// | `line` | x1, y1, x2, y2, p |
  /// | `arc` | l, t, w, h, start, sweep, useCenter, p |
  /// | `path` | segments, p |
  /// | `text` | string, x, y, {size, color, weight, align, maxWidth, family} |
  /// | `save`, `restore` | |
  /// | `translate` | dx, dy |
  /// | `rotate` | radians |
  /// | `scale` | sx, sy |
  /// | `clipRect` | l, t, w, h |
  /// | `clipRRect` | l, t, w, h, radius |
  ///
  /// Path segments: `['M', x, y]`, `['L', x, y]`, `['Q', cx, cy, x, y]`,
  /// `['C', c1x, c1y, c2x, c2y, x, y]`, `['A', l, t, w, h, start, sweep]`
  /// (an arc of the oval in that rectangle, joined with a line), `['R', l, t,
  /// w, h]` (a rectangle), `['O', l, t, w, h]` (an oval) and `['Z']`.
  ///
  /// A paint is `{color, style: 'fill'|'stroke', strokeWidth, cap:
  /// 'butt'|'round'|'square', join: 'miter'|'round'|'bevel'}`; `style`
  /// defaults to fill. `text` is drawn from its top-left corner; `align`
  /// ('left', 'center', 'right') is relative to `maxWidth` when there is one,
  /// and otherwise to `x`.
  ///
  /// [width]/[height] fix the surface; [expand] fills the parent as a [box]
  /// does. [onSize] reports the size it was actually given, which is what a
  /// painter that scales to its surface draws against. The touch callbacks
  /// are a [box]'s.
  static WidgetNode canvas({
    required List<List<Object?>> commands,
    List<Map<String, dynamic>> paints = const [],
    double? width,
    double? height,
    String? expand,
    double? aspectRatio,
    void Function(double width, double height)? onSize,
    void Function(double x, double y)? onTap,
    void Function(String phase, Map<String, dynamic> data)? onPan,
    WidgetNode? child,
    String? semanticLabel,
    String? id,
  }) {
    final frame = box(
      width: width,
      height: height,
      expand: expand,
      aspectRatio: aspectRatio,
      onSize: onSize,
      onTap: onTap,
      onPan: onPan,
      // A picture has no text for a reader to find; a canvas with a label is
      // announced as an image of that name, and one without is skipped.
      semanticLabel: semanticLabel,
      id: id,
    );
    return WidgetNode(
      type: 'Canvas',
      props: {...frame.props, 'paints': paints, 'commands': commands},
      children: [if (child != null) child],
    );
  }

  /// One of a list of [items], chosen from the platform's own menu: a
  /// `Spinner`-style exposed menu on Android, a pull-down on iOS, a `<select>`
  /// on web. The handler receives the chosen index.
  static WidgetNode dropdown({
    required List<String> items,
    required int? selectedIndex,
    String? eventId,
    void Function(int index)? onChanged,
    String? label,
    String? hint,
    String? error,
    bool enabled = true,
    bool outlined = true,
    String? id,
  }) {
    if (onChanged != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.on(
        eventId,
        (data) => onChanged((data['index'] as num?)?.toInt() ?? 0),
      );
    }
    return WidgetNode(
      type: 'Dropdown',
      props: {
        'items': items,
        if (selectedIndex != null) 'selectedIndex': selectedIndex,
        if (enabled) 'eventId': _require(eventId, 'dropdown'),
        if (label != null) 'label': label,
        if (hint != null) 'hint': hint,
        if (error != null) 'error': error,
        'enabled': enabled,
        if (!outlined) 'outlined': false,
        if (id != null) 'id': id,
      },
    );
  }

  /// The platform's date picker, as an overlay (see [overlay]).
  ///
  /// Dates are `yyyy-mm-dd`. [onPicked] receives the chosen one; [onDismiss]
  /// runs when the picker is closed without choosing. Like every overlay it is
  /// in the tree while it is open and the app removes it on either event.
  static WidgetNode datePicker({
    required String initial,
    required String first,
    required String last,
    required void Function(String date) onPicked,
    required void Function() onDismiss,
    String? title,
    String? confirmLabel,
    String? cancelLabel,
    required String id,
  }) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: id);
    bindings.on(eventId, (data) => onPicked('${data['value']}'));
    return WidgetNode(
      type: 'DatePicker',
      props: {
        'initial': initial,
        'first': first,
        'last': last,
        'eventId': eventId,
        if (title != null) 'title': title,
        if (confirmLabel != null) 'confirmLabel': confirmLabel,
        if (cancelLabel != null) 'cancelLabel': cancelLabel,
        ...?_dismiss(null, onDismiss, id),
        'id': id,
      },
    );
  }

  /// The platform's time picker, as an overlay. [hour] is 0-23; [onPicked]
  /// receives the chosen hour and minute. [use24Hour] null follows the device.
  static WidgetNode timePicker({
    required int hour,
    required int minute,
    required void Function(int hour, int minute) onPicked,
    required void Function() onDismiss,
    bool? use24Hour,
    String? title,
    String? confirmLabel,
    String? cancelLabel,
    required String id,
  }) {
    final bindings = EventBindings.required;
    final eventId = bindings.allocate(key: id);
    bindings.on(
      eventId,
      (data) => onPicked(
        (data['hour'] as num?)?.toInt() ?? hour,
        (data['minute'] as num?)?.toInt() ?? minute,
      ),
    );
    return WidgetNode(
      type: 'TimePicker',
      props: {
        'hour': hour,
        'minute': minute,
        'eventId': eventId,
        if (use24Hour != null) 'use24Hour': use24Hour,
        if (title != null) 'title': title,
        if (confirmLabel != null) 'confirmLabel': confirmLabel,
        if (cancelLabel != null) 'cancelLabel': cancelLabel,
        ...?_dismiss(null, onDismiss, id),
        'id': id,
      },
    );
  }

  /// Pins [child] along the bottom edge of a [scaffold], above the system's
  /// own inset. A scaffold finds it among its children by type.
  static WidgetNode bottomBar({required WidgetNode child}) =>
      WidgetNode(type: 'BottomBar', props: {}, children: [child]);

  /// The destinations of an app, one selected: Material's bottom navigation
  /// on Android, a tab bar on iOS. Usually the child of a [bottomBar].
  ///
  /// Each item is `(label, icon, selectedIcon)`, the icons being Material
  /// Icons codepoints. `rail: true` lays the same destinations out down the
  /// leading edge, for a wide window.
  static WidgetNode bottomNavigation({
    required List<({String label, int icon, int? selectedIcon})> items,
    required int selectedIndex,
    String? eventId,
    void Function(int index)? onChanged,
    bool rail = false,
    String? id,
  }) {
    if (onChanged != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.on(
        eventId,
        (data) => onChanged((data['index'] as num?)?.toInt() ?? 0),
      );
    }
    return WidgetNode(
      type: 'BottomNavigation',
      props: {
        'eventId': _require(eventId, 'bottomNavigation'),
        'items': [
          for (final item in items)
            {
              'label': item.label,
              'icon': item.icon,
              if (item.selectedIcon != null) 'selectedIcon': item.selectedIcon,
            },
        ],
        'selectedIndex': selectedIndex,
        if (rail) 'rail': true,
        if (id != null) 'id': id,
      },
    );
  }

  /// A region the Flutter engine paints, inside a screen the platform draws.
  ///
  /// For the widget that only exists as a Flutter widget - an ad banner, a
  /// chart package. The renderers that have no Flutter engine draw [fallback]
  /// instead (web, and tests); the Flutter renderer builds the widget where
  /// the node is; the Android and iOS renderers leave a see-through,
  /// touch-through hole of this size and report where it is
  /// ([RendererEvents.slotRect]), and the Flutter view underneath paints the
  /// widget registered under [slotId] into that rectangle.
  ///
  /// The size has to come from the tree, because the platform lays the hole
  /// out before Flutter knows it is there: give [height] (and [width], or let
  /// it fill the width it is offered).
  static WidgetNode flutterSlot({
    required String slotId,
    required double height,
    double? width,
    WidgetNode? fallback,
  }) => WidgetNode(
    type: 'FlutterSlot',
    props: {
      'slotId': slotId,
      'height': height,
      if (width != null) 'width': width,
      'id': 'slot_$slotId',
    },
    children: [if (fallback != null) fallback],
  );

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------

  /// Draws [overlays] above [child], later ones on top.
  ///
  /// Overlays are state like anything else: the app puts a dialog in the list
  /// while it is open and leaves it out once dismissed. A renderer never
  /// removes one on its own - a tap on the scrim, Escape, a swipe or the
  /// snackbar's timeout only sends the overlay's dismiss event.
  static WidgetNode overlay({
    required WidgetNode child,
    List<WidgetNode> overlays = const [],
  }) => WidgetNode(type: 'Overlay', props: {}, children: [child, ...overlays]);

  /// A modal dialog over a scrim.
  ///
  /// [content] is laid out top to bottom under the [title]; [actions] - usually
  /// buttons - sit in a row at the end. [onDismiss] runs for a tap on the
  /// scrim, Escape on web and the platform back gesture, with nothing to say
  /// which; a dialog with neither [onDismiss] nor [dismissEventId], or with
  /// [dismissible] false, only closes through its actions.
  static WidgetNode dialog({
    String? title,
    List<WidgetNode> content = const [],
    List<WidgetNode> actions = const [],
    void Function()? onDismiss,
    String? dismissEventId,
    bool dismissible = true,
    String? id,
  }) => WidgetNode(
    type: 'Dialog',
    props: {
      if (title != null) 'title': title,
      'dismissible': dismissible,
      ...?_dismiss(dismissEventId, onDismiss, id),
      if (id != null) 'id': id,
    },
    children: [
      column(crossAxisAlignment: 'stretch', children: content),
      if (actions.isNotEmpty)
        row(mainAxisAlignment: 'end', spacing: 8, children: actions),
    ],
  );

  /// A modal sheet rising from the bottom edge, holding [content] top to
  /// bottom. Dismissed like [dialog], and by swiping it down where the platform
  /// has the gesture.
  static WidgetNode bottomSheet({
    String? title,
    required List<WidgetNode> content,
    void Function()? onDismiss,
    String? dismissEventId,
    bool dismissible = true,
    String? id,
  }) => WidgetNode(
    type: 'BottomSheet',
    props: {
      if (title != null) 'title': title,
      'dismissible': dismissible,
      ...?_dismiss(dismissEventId, onDismiss, id),
      if (id != null) 'id': id,
    },
    children: content,
  );

  /// A transient message along the bottom edge, which does not block the
  /// screen.
  ///
  /// After [duration] the renderer sends the dismiss event, once per snackbar
  /// however often the tree is rendered meanwhile; [Duration.zero] keeps it up
  /// until the app removes it. [actionLabel] with [onAction] adds one button,
  /// such as "Undo". Give each new message its own [id], so a renderer can
  /// tell a replacement from the same snackbar rendered again.
  static WidgetNode snackbar({
    required String message,
    String? actionLabel,
    void Function()? onAction,
    String? actionEventId,
    void Function()? onDismiss,
    String? dismissEventId,
    Duration duration = const Duration(seconds: 4),
    String? id,
  }) {
    if (onAction != null) {
      final bindings = EventBindings.required;
      actionEventId = bindings.allocate(key: id == null ? null : '$id.action');
      bindings.onTap(actionEventId, onAction);
    }
    return WidgetNode(
      type: 'Snackbar',
      props: {
        'message': message,
        if (actionLabel != null) 'actionLabel': actionLabel,
        if (actionEventId != null) 'actionEventId': actionEventId,
        ...?_dismiss(dismissEventId, onDismiss, id),
        'durationMs': duration.inMilliseconds,
        if (id != null) 'id': id,
      },
    );
  }

  /// The `dismissEventId` prop, allocated for [onDismiss] when one is given.
  static Map<String, String>? _dismiss(
    String? eventId,
    void Function()? onDismiss,
    String? id,
  ) {
    if (onDismiss != null) {
      assert(eventId == null, 'Pass either dismissEventId or onDismiss.');
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id == null ? null : '$id.dismiss');
      bindings.onTap(eventId, onDismiss);
    }
    return eventId == null ? null : {'dismissEventId': eventId};
  }

  // ---------------------------------------------------------------------------
  // Long lists
  // ---------------------------------------------------------------------------

  /// A scrolling list of [itemCount] rows, of which only the rows near the
  /// visible ones are built.
  ///
  /// [itemExtent] is how tall every row is; rows that differ say so through
  /// [itemExtentBuilder] instead, which is asked for the height of *every*
  /// row - including the ones outside the window - because the list's own
  /// height, and which row a scroll offset lands on, are sums over all of
  /// them. Pass exactly one of the two.
  ///
  /// [itemBuilder] is called for the rows in the window alone, on every build.
  /// The list scrolls itself, so give it bounded height: make it the
  /// Scaffold's body (which then does not scroll around it) or put it in an
  /// [expanded]. Rows without an `id` get `'<id>/<index>'`, so a renderer
  /// moves a row's view rather than rebuilding every row when the window
  /// shifts.
  ///
  /// Must be built inside [NativeUIApp.build]: the window lives with the app
  /// between builds, under [id].
  static WidgetNode lazyList({
    required String id,
    required int itemCount,
    required WidgetNode Function(int index) itemBuilder,
    double? itemExtent,
    double Function(int index)? itemExtentBuilder,
    int overscan = 10,
    int initialCount = 30,
    double? scrollOffset,
    int? scrollVersion,
  }) {
    assert(
      (itemExtent == null) != (itemExtentBuilder == null),
      'Give a lazy list one row height (itemExtent) or a height per row '
      '(itemExtentBuilder), not both and not neither.',
    );
    final extents = itemExtentBuilder == null
        ? null
        : RowExtents(itemCount, itemExtentBuilder);
    final bindings = EventBindings.required;
    final window = bindings.retain(
      'lazyList:$id',
      () => LazyListWindow(initialCount: initialCount),
    );
    final (start, end) = window.clampTo(itemCount);

    final rangeEventId = bindings.allocate(key: '$id.range');
    bindings.on(rangeEventId, (data) {
      final (first, last) = extents == null
          ? _reportedRows(data)
          : _rowsAtPixels(data, extents);
      if (first < 0) return;
      final moved = window.update(
        first: first,
        last: last,
        itemCount: itemCount,
        overscan: overscan,
      );
      if (moved) bindings.invalidate();
    });

    return WidgetNode(
      type: 'LazyList',
      props: {
        'id': id,
        'itemCount': itemCount,
        if (itemExtent != null) 'itemExtent': itemExtent,
        // Rows of their own heights: the window's own heights, where the
        // window starts, and how tall the whole list is - which is everything
        // a renderer needs to place what it has and size what it has not.
        if (extents != null) ...{
          'extents': extents.slice(start, end),
          'startOffset': extents.offsetOf(start),
          'totalExtent': extents.total,
        },
        'startIndex': start,
        'rangeEventId': rangeEventId,
        // As on a scroll node: jump to this offset when the version is new.
        if (scrollOffset != null) 'scrollOffset': scrollOffset,
        if (scrollOffset != null) 'scrollVersion': scrollVersion ?? 0,
      },
      children: [
        for (var index = start; index < end; index++)
          _keyed(itemBuilder(index), '$id/$index'),
      ],
    );
  }

  /// The rows a renderer says are visible, when it counted them itself.
  static (int, int) _reportedRows(Map<String, dynamic> data) {
    final first = data['first'];
    final last = data['last'];
    if (first is! num || last is! num) return (-1, -1);
    return (first.toInt(), last.toInt());
  }

  /// The rows a viewport is showing, worked out from where it is scrolled to.
  ///
  /// A renderer drawing rows of different heights reports pixels instead of
  /// row numbers, because it only holds the rows in the window and cannot say
  /// what lies above them.
  static (int, int) _rowsAtPixels(
    Map<String, dynamic> data,
    RowExtents extents,
  ) {
    final offset = data['offset'];
    final viewport = data['viewport'];
    if (offset is! num || viewport is! num) return (-1, -1);
    final first = extents.indexAt(offset.toDouble());
    final last = extents.indexAt(offset.toDouble() + viewport.toDouble());
    return (first, last);
  }

  static WidgetNode _keyed(WidgetNode node, String id) =>
      node.props.containsKey('id')
      ? node
      : WidgetNode(
          type: node.type,
          props: {...node.props, 'id': id},
          children: node.children,
        );

  /// Resolves the event id of a tappable node: either the one given, or one
  /// allocated for [onPressed].
  static String _bindTap(
    String? eventId,
    void Function()? onPressed,
    String? id,
  ) {
    if (onPressed == null) return _require(eventId, 'this node');
    assert(
      eventId == null,
      'Pass either eventId or onPressed, not both: onPressed allocates its own.',
    );
    final bindings = EventBindings.required;
    final allocated = bindings.allocate(key: id);
    bindings.onTap(allocated, onPressed);
    return allocated;
  }

  static String _require(String? eventId, String what) =>
      eventId ??
      (throw ArgumentError('$what needs either an eventId or a callback'));
}
