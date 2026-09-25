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
};

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
  static WidgetNode scaffold({
    WidgetNode? appBar,
    required WidgetNode body,
    WidgetNode? floatingActionButton,
  }) => WidgetNode(
    type: 'Scaffold',
    props: {},
    children: [
      if (appBar != null) appBar,
      body,
      if (floatingActionButton != null) floatingActionButton,
    ],
  );

  static WidgetNode appBar({required String title}) =>
      WidgetNode(type: 'AppBar', props: {'title': title});

  /// Vertical layout. [crossAxisAlignment] is 'start', 'center' (default,
  /// like Flutter's Column), 'end' or 'stretch'.
  ///
  /// [mainAxisAlignment] - 'center', 'end' or 'spaceBetween' - distributes the
  /// children down the column, and only shows where the column has height to
  /// spare: a column sizes to its content unless something gives it more, so
  /// asking for it is also asking the column to fill what it is in. 'start' is
  /// the default and is left out of the tree, since it is the absence of any
  /// distributing.
  static WidgetNode column({
    required List<WidgetNode> children,
    String? crossAxisAlignment,
    String? mainAxisAlignment,
  }) => WidgetNode(
    type: 'Column',
    props: {
      if (crossAxisAlignment != null) 'crossAxisAlignment': crossAxisAlignment,
      if (mainAxisAlignment != null && mainAxisAlignment != 'start')
        'mainAxisAlignment': mainAxisAlignment,
    },
    children: children,
  );

  /// Horizontal layout. [mainAxisAlignment] is 'start' (default), 'center',
  /// 'end' or 'spaceBetween'.
  static WidgetNode row({
    required List<WidgetNode> children,
    String? mainAxisAlignment,
    double spacing = 0,
  }) => WidgetNode(
    type: 'Row',
    props: {
      if (mainAxisAlignment != null) 'mainAxisAlignment': mainAxisAlignment,
      'spacing': spacing,
    },
    children: children,
  );

  /// A run of children laid out horizontally that wraps onto the next line when
  /// it runs out of width. [spacing] is the gap between children on a line,
  /// [runSpacing] the gap between lines.
  static WidgetNode wrap({
    required List<WidgetNode> children,
    double spacing = 0,
    double runSpacing = 0,
  }) => WidgetNode(
    type: 'Wrap',
    props: {'spacing': spacing, 'runSpacing': runSpacing},
    children: children,
  );

  /// Makes [child] take the remaining space inside a Row or Column.
  static WidgetNode expanded({required WidgetNode child, int flex = 1}) =>
      WidgetNode(type: 'Expanded', props: {'flex': flex}, children: [child]);

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
  /// that has to be a particular shape rather than one of three. They are what
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
    String? id,
  }) {
    eventId = _bindTap(eventId, onPressed, id);
    final resolved = codepoint ?? materialIconCodepoint(icon);
    return WidgetNode(
      type: 'IconButton',
      props: {
        'icon': icon,
        if (resolved != null) 'iconCodepoint': resolved,
        'eventId': eventId,
        'tooltip': tooltip,
        if (data != null) 'data': data,
        if (id != null) 'id': id,
      },
    );
  }

  /// Checkbox; the handler receives `{'checked': bool}` plus [data].
  static WidgetNode checkbox({
    String? eventId,
    void Function(bool checked)? onChanged,
    required bool checked,
    String? label,
    Map<String, dynamic>? data,
    String? id,
  }) {
    if (onChanged != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.onToggle(eventId, onChanged);
    }
    return WidgetNode(
      type: 'Checkbox',
      props: {
        'eventId': _require(eventId, 'checkbox'),
        'checked': checked,
        if (label != null) 'label': label,
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
    String? id,
  }) => WidgetNode(
    type: 'Text',
    props: {
      'content': content,
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
  static WidgetNode image({
    required String src,
    required String alt,
    double? width,
    double? height,
    String fit = 'cover',
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
    String? id,
  }) {
    eventId = _bindTap(eventId, onPressed, id);
    final resolved = codepoint ?? materialIconCodepoint(icon);
    return WidgetNode(
      type: 'FloatingActionButton',
      props: {
        'tooltip': tooltip,
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
  }) {
    if (onChanged != null || onSubmitted != null) {
      final bindings = EventBindings.required;
      eventId = bindings.allocate(key: id);
      bindings.onText(eventId, onChanged: onChanged, onSubmitted: onSubmitted);
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
      },
    );
  }

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
