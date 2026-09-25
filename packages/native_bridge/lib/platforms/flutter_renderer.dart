/// Renders a [WidgetNode] tree with Flutter widgets.
///
/// The other renderers hand the tree to a platform: Android Views, iOS
/// UIViews, DOM. This one paints it with Flutter, which is what an existing
/// Flutter app wants - the whole screen comes from the shared [NativeUIApp]
/// instead of being rewritten as widgets.
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => NativeUIAppHost(app: SettingsApp(storage: storage)),
/// ));
/// ```
///
/// The node vocabulary is the one every renderer implements, so a screen
/// written for the web DOM renderer paints here unchanged.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../src/app_theme.dart';
import '../src/contrast.dart' as contrast;
import '../src/frame_probe.dart';
import '../src/render_error.dart';
import 'flutter_frame_probe.dart';
import '../src/ui_renderer.dart';
import '../src/native_ui_app.dart';

/// Flutter implementation of [NativeUIRenderer].
///
/// Holds the latest tree and rebuilds the host when it changes. Text field
/// controllers live here rather than in the tree, so a field keeps its focus
/// and caret while the app re-renders around it; so do the scroll controllers
/// of lazy lists, so a list keeps its offset.
class FlutterUIRenderer implements NativeUIRenderer, HasFrameProbe {
  FlutterUIRenderer({this.onTreeChanged, this.theme = AppTheme.fallback});

  /// Called after every render; the host widget rebuilds from it.
  VoidCallback? onTreeChanged;

  /// Records Flutter's own frame timings, which on this target is what draws.
  @override
  late final FrameProbe frameProbe = FlutterFrameProbe();

  /// The app's colour theme; its primary is the default for the app bar,
  /// primary buttons and the FAB when a node carries no explicit colour.
  final AppTheme theme;

  /// What the device last reported, read from the `MediaQuery` at the root of
  /// every build. Only consulted when the theme's mode is
  /// [AppThemeMode.system]; a `MediaQuery` change rebuilds the host, so a
  /// device switching appearance repaints without the app doing anything.
  bool _platformIsDark = false;

  /// The palette for the appearance in force - the theme itself, or its dark
  /// counterpart. Everything painted below reads this rather than [theme].
  AppTheme get palette => theme.resolve(platformIsDark: _platformIsDark);

  /// The other appearance's palette. A snackbar is drawn on it, which is how it
  /// reads as a message *over* the app in both appearances - dark-on-light in a
  /// dark app, light-on-dark in a light one - rather than vanishing into the
  /// surface it covers.
  AppTheme get _inversePalette =>
      theme.isDark(platformIsDark: _platformIsDark) ? theme : theme.dark;

  /// The theme's palette as [Color]s, used as defaults where a node carries no
  /// explicit colour.
  Color get _primaryColor => _color(palette.primary) ?? const Color(0xff1976d2);
  Color get _onPrimaryColor => _color(palette.onPrimary) ?? Colors.white;
  Color get _secondaryColor =>
      _color(palette.secondary) ?? const Color(0xfff57c00);
  Color get _errorColor => _color(palette.error) ?? const Color(0xffd32f2f);
  Color get _successColor => _color(palette.success) ?? const Color(0xff388e3c);
  Color get _warningColor => _color(palette.warning) ?? const Color(0xfffbc02d);
  Color get _infoColor => _color(palette.info) ?? const Color(0xff0288d1);
  Color get _surfaceColor => _color(palette.surface) ?? Colors.white;
  Color get _surfaceVariantColor =>
      _color(palette.surfaceVariant) ?? const Color(0xfff5f5f5);
  Color get _textColor => _color(palette.text) ?? const Color(0xff212121);
  Color get _textSecondaryColor =>
      _color(palette.textSecondary) ?? const Color(0xff757575);
  Color get _dividerColor => _color(palette.divider) ?? const Color(0xffe0e0e0);

  /// The most recently rendered tree.
  WidgetNode? tree;

  final Map<String, Function(Map<String, dynamic>)> _handlers = {};
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _appliedValues = {};
  final Map<String, int?> _appliedVersions = {};
  final Map<String, _LazyListController> _scrollControllers = {};

  /// The visible range last sent for each lazy list, by list id.
  final Map<String, (int, int)> _reportedRanges = {};
  final Map<String, (double, double)> _reportedOffsets = {};

  /// The node types the last build could not paint.
  ///
  /// Flutter builds the widgets *after* a render returns - the host rebuilds on
  /// the next frame - so an unknown type found while building is reported by
  /// the render after it. One render late, and the alternative is never.
  final Set<String> _unknownTypes = {};

  @override
  Future<RenderError?> render(WidgetNode tree) async {
    this.tree = tree;
    // Text fields are reconciled here rather than when the widget builds: a
    // rebuild can be deferred to the next frame, and an app that changes a
    // field's value twice before then (typing, then a submit that clears it)
    // must still end up with the value it asked for.
    _syncTextFields(tree);
    onTreeChanged?.call();
    if (_unknownTypes.isEmpty) return null;
    final reported = {..._unknownTypes};
    _unknownTypes.clear();
    return RenderError.unknownNodeTypes(reported);
  }

  /// Applies every text field value the tree declares.
  void _syncTextFields(WidgetNode node) {
    if (node.type == 'TextField') {
      final eventId = node.props['eventId'];
      if (eventId is String) {
        final value = _optString(node.props['initialValue']) ?? '';
        final version = (node.props['valueVersion'] as num?)?.toInt();
        final controller = _controllers[eventId];
        // Apply the value when the app changed it - a different value, or a
        // bumped controller version from a clear() after submitting, which the
        // user's own typing never does. A stale echo of the value the field
        // already holds is left alone so typing is never overwritten.
        if (_appliedValues[eventId] != value ||
            _appliedVersions[eventId] != version) {
          _appliedValues[eventId] = value;
          _appliedVersions[eventId] = version;
          if (controller != null && controller.text != value) {
            controller.text = value;
          }
        }
      }
    }
    for (final child in node.children ?? const <WidgetNode>[]) {
      _syncTextFields(child);
    }
  }

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async {
    final handler = _handlers[eventId];
    if (handler == null) {
      return {'success': false, 'error': 'Handler not found for $eventId'};
    }
    handler(data);
    return {'success': true};
  }

  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {
    _handlers[eventId] = handler;
  }

  /// Releases the text field and lazy list controllers.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _appliedValues.clear();
    _appliedVersions.clear();
    _scrollControllers.clear();
    _reportedRanges.clear();
  }

  /// Builds the current tree, or nothing before the first render.
  ///
  /// A tree rooted in a Scaffold brings its own Material ancestor; any other
  /// root is wrapped in one, so a fragment - a settings panel, a form - can be
  /// dropped anywhere in an existing Flutter app without the Material widgets
  /// inside it asserting. An Overlay root is wrapped too, even around a
  /// Scaffold: the overlays are drawn beside the Scaffold, not inside it.
  Widget build(BuildContext context) {
    final tree = this.tree;
    if (tree == null) return const SizedBox.shrink();
    // Read once, at the root, so every node below paints one appearance even
    // if the device flips mid-build.
    _platformIsDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final widget = buildNode(tree, context);
    if (tree.type == 'Scaffold' || tree.type == 'NavigationStack') {
      return widget;
    }
    return Material(type: MaterialType.transparency, child: widget);
  }

  /// Builds one node. Public so a host can render a subtree of its own.
  Widget buildNode(WidgetNode node, BuildContext context) {
    final p = node.props;
    final children = node.children ?? const <WidgetNode>[];
    List<Widget> build(List<WidgetNode> nodes) => [
      for (final child in nodes) buildNode(child, context),
    ];

    // node-types:begin
    switch (node.type) {
      case 'Scaffold':
        return _scaffold(children, context);
      case 'NavigationStack':
        return _scaffold(children, context);
      case 'AppBar':
      case 'NavigationBar':
        return _appBarBody(p);
      case 'Column':
        final distributes = p['mainAxisAlignment'] != null;
        return Column(
          crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
          mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
          // A column hugs its children unless it was asked to distribute them,
          // and there is nothing to distribute inside a column that hugs.
          mainAxisSize: distributes ? MainAxisSize.max : MainAxisSize.min,
          children: build(children),
        );
      case 'VStack':
        return Column(
          crossAxisAlignment: _stackCrossAxis(p['alignment']),
          mainAxisSize: MainAxisSize.min,
          children: _spaced(
            build(children),
            _double(p['spacing']),
            vertical: true,
          ),
        );
      case 'Row':
        return _row(
          children,
          context,
          spacing: _double(p['spacing']),
          mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
        );
      case 'HStack':
        return _row(
          children,
          context,
          spacing: _double(p['spacing']),
          crossAxisAlignment: _hStackCrossAxis(p['alignment']),
        );
      case 'Wrap':
        return Wrap(
          spacing: _double(p['spacing']) ?? 0,
          runSpacing: _double(p['runSpacing']) ?? 0,
          children: build(children),
        );
      case 'Expanded':
        return Expanded(
          flex: (_double(p['flex']) ?? 1).toInt(),
          child: _single(children, context),
        );
      case 'Center':
        return Center(child: _single(children, context));
      case 'SwipeActions':
        return _SwipeActionsRow(
          actions: _swipeActions(p),
          leadingActions: _swipeActions(p, key: 'leadingActions'),
          surface: _surfaceColor,
          onFire: (eventId) => handleEvent(eventId, const {}),
          child: _single(children, context),
        );
      case 'Padding':
        return Padding(
          padding: _insets(p),
          child: _single(children, context),
        );
      case 'SizedBox':
        return SizedBox(
          height: _double(p['height']),
          width: _double(p['width']),
        );
      case 'Spacer':
        // A node tree has no way to say "take the remaining space" that is
        // safe in an unbounded parent, so the minimum length is honoured.
        return SizedBox(height: _double(p['minLength']) ?? 0);
      case 'Text':
        return _text(p);
      case 'Image':
        return _image(p);
      case 'Divider':
        return _divider(p);
      case 'Loading':
        return _loading(p, children, context);
      case 'Button':
      case 'MaterialButton':
        return _button(p);
      case 'IconButton':
        return Tooltip(
          message: _string(p['tooltip']),
          child: IconButton(
            icon: Icon(_icon(_string(p['icon'], 'more_vert'))),
            onPressed: _tap(p),
          ),
        );
      case 'FloatingActionButton':
        // With a brand theme, the FAB matches the other renderers' primary;
        // with none, Flutter's own Material 3 default is left to shine.
        final themed = theme != AppTheme.fallback;
        return FloatingActionButton(
          tooltip: _optString(p['tooltip']),
          onPressed: _tap(p),
          backgroundColor: _color(p['backgroundColor']) ??
              (themed ? _primaryColor : null),
          foregroundColor: themed ? _onPrimaryColor : null,
          child: Icon(_icon(_string(p['icon'], 'add'))),
        );
      case 'TextField':
        return _NodeTextField(renderer: this, props: p);
      case 'GridView':
        return GridView.count(
          crossAxisCount: (_double(p['crossAxisCount']) ?? 2).toInt(),
          mainAxisSpacing: _double(p['runSpacing']) ?? 0,
          crossAxisSpacing: _double(p['spacing']) ?? 0,
          childAspectRatio: _double(p['childAspectRatio']) ?? 1,
          // The scaffold's body already scrolls; a grid that scrolled too
          // would trap the gesture and size itself to nothing.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: build(children),
        );
      case 'MapView':
        return _mapPlaceholder(p);
      case 'CameraPreview':
        return _placeholder(
          p,
          'A camera preview needs the camera plugin on the Flutter target.',
        );
      case 'AnimatedOpacity':
        return AnimatedOpacity(
          opacity: (_double(p['opacity']) ?? 1).clamp(0.0, 1.0),
          duration: _duration(p),
          curve: _curve(p),
          child: _single(children, context),
        );
      case 'AnimatedContainer':
        return AnimatedContainer(
          width: _double(p['width']),
          height: _double(p['height']),
          color: _color(p['color']),
          duration: _duration(p),
          curve: _curve(p),
          // Centred, because that is what the other three renderers do with
          // a child that does not fill the box.
          alignment: Alignment.center,
          child: _over(p['color'], children, context).firstOrNull ??
              const SizedBox.shrink(),
        );
      case 'Tabs':
        return _tabs(p);
      case 'Slider':
        return _slider(p);
      case 'Checkbox':
        return _checkbox(p);
      case 'Radio':
        return _radio(p);
      case 'Toggle':
        return _toggle(p);
      case 'Card':
        return _card(p, children, context);
      case 'Badge':
        return _badge(p);
      case 'Alert':
        return _NodeAlert(props: p, renderer: this);
      case 'WebView':
        return _webViewPlaceholder(p);
      case 'List':
      case 'ListView':
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: build(children),
        );
      case 'ListItem':
      case 'ListRow':
        return ListTile(
          title: Text(_string(p['text'])),
          subtitle: _optString(p['subtitle']) == null
              ? null
              : Text(_string(p['subtitle'])),
        );
      case 'LazyList':
        return _NodeLazyList(
          key: ValueKey('lazyList:${_string(p['id'])}'),
          renderer: this,
          props: p,
          rows: children,
        );
      case 'Overlay':
        // Later children on top, each given the whole area rather than
        // scrolling with the screen underneath.
        return Stack(fit: StackFit.expand, children: build(children));
      case 'Dialog':
        return _dialog(p, children, context);
      case 'BottomSheet':
        return _NodeBottomSheet(renderer: this, props: p, children: children);
      case 'Snackbar':
        // Keyed by identity, so the same snackbar rendered again keeps its
        // State - and its timer - while a replacement starts a new one.
        return _NodeSnackbar(
          key: ValueKey('snackbar:${_snackbarIdentity(p)}'),
          renderer: this,
          props: p,
        );
      default:
        _unknownTypes.add(node.type);
        return Text('Unknown widget: ${node.type}');
    }
    // node-types:end
  }

  // ---------------------------------------------------------------------------
  // Structure
  // ---------------------------------------------------------------------------

  /// A Scaffold's children are, in order, an optional app bar, the body and an
  /// optional floating action button - the shape [UIBuilder.scaffold] builds.
  Widget _scaffold(List<WidgetNode> children, BuildContext context) {
    WidgetNode? appBar;
    WidgetNode? fab;
    final body = <WidgetNode>[];
    for (final child in children) {
      switch (child.type) {
        case 'AppBar':
        case 'NavigationBar':
          appBar ??= child;
        case 'FloatingActionButton':
          fab ??= child;
        default:
          body.add(child);
      }
    }

    // iOS trees nest the bar inside the stack - navigationStack(vStack([
    // navigationBar(...), ...])) - so hoist it into a real AppBar.
    if (appBar == null && body.length == 1) {
      final inner = body.single;
      final innerChildren = inner.children ?? const <WidgetNode>[];
      if ((inner.type == 'VStack' || inner.type == 'Column') &&
          innerChildren.isNotEmpty &&
          (innerChildren.first.type == 'NavigationBar' ||
              innerChildren.first.type == 'AppBar')) {
        appBar = innerChildren.first;
        body[0] = WidgetNode(
          type: inner.type,
          props: inner.props,
          children: innerChildren.sublist(1),
        );
      }
    }

    // A body holding a lazy list scrolls itself, and needs the bounded height
    // a SingleChildScrollView would take away.
    final scrollsItself = body.any(_holdsLazyList);
    final content = body.length == 1
        ? buildNode(body.single, context)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: scrollsItself ? MainAxisSize.max : MainAxisSize.min,
            children: [for (final child in body) buildNode(child, context)],
          );

    return Scaffold(
      appBar: appBar == null
          ? null
          : AppBar(
              title: Text(_string(appBar.props['title'])),
              backgroundColor: _color(appBar.props['backgroundColor']),
              foregroundColor: switch (_color(
                appBar.props['backgroundColor'],
              )) {
                final Color stated => _textOn(stated),
                _ => null,
              },
            ),
      body: body.isEmpty
          ? null
          : scrollsItself
          ? content
          : body.any(_fillsViewport)
          // A body that places its children in the space it is given - a
          // Center, or a Column distributing down its main axis - has no space
          // inside a scroll view, which is unbounded. Give it the viewport as
          // a floor and it still scrolls when the content is taller.
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: content,
                ),
              ),
            )
          : SingleChildScrollView(child: content),
      floatingActionButton: fab == null ? null : buildNode(fab, context),
    );
  }

  /// Whether [node] lays its children out in the space it is given, rather
  /// than sizing itself to them - the same question the native scaffolds ask.
  static bool _fillsViewport(WidgetNode node) =>
      node.type == 'Center' ||
      ((node.type == 'Column' || node.type == 'VStack') &&
          node.props['mainAxisAlignment'] != null);

  static bool _holdsLazyList(WidgetNode node) =>
      node.type == 'LazyList' ||
      (node.children ?? const <WidgetNode>[]).any(_holdsLazyList);

  /// A horizontal run of children.
  ///
  /// A row holding an [Expanded] needs real flex semantics, so it stays a Row.
  /// Any other row becomes a Wrap: the web renderer lets a long row shrink and
  /// spill quietly, where a Flutter Row would overflow and paint a stripe, so
  /// the content reflows instead.
  Widget _row(
    List<WidgetNode> children,
    BuildContext context, {
    double? spacing,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
  }) {
    final built = [for (final child in children) buildNode(child, context)];
    final hasFlexChild = children.any((c) => c.type == 'Expanded');

    if (hasFlexChild) {
      return Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        children: _spaced(built, spacing, vertical: false),
      );
    }

    return Wrap(
      spacing: spacing ?? 0,
      runSpacing: spacing ?? 0,
      alignment: _wrapAlignment(mainAxisAlignment),
      crossAxisAlignment: _wrapCrossAlignment(crossAxisAlignment),
      children: built,
    );
  }

  static WrapAlignment _wrapAlignment(MainAxisAlignment alignment) =>
      switch (alignment) {
        MainAxisAlignment.center => WrapAlignment.center,
        MainAxisAlignment.end => WrapAlignment.end,
        MainAxisAlignment.spaceBetween => WrapAlignment.spaceBetween,
        _ => WrapAlignment.start,
      };

  static WrapCrossAlignment _wrapCrossAlignment(CrossAxisAlignment alignment) =>
      switch (alignment) {
        CrossAxisAlignment.start => WrapCrossAlignment.start,
        CrossAxisAlignment.end => WrapCrossAlignment.end,
        _ => WrapCrossAlignment.center,
      };

  /// An app bar met outside a Scaffold still has to render something.
  Widget _appBarBody(Map<String, dynamic> p) => Material(
    color: _color(p['backgroundColor']) ?? _primaryColor,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _string(p['title']),
          style: TextStyle(
            color: switch (_color(p['backgroundColor'])) {
              final Color stated => _textOn(stated),
              _ => _onPrimaryColor,
            },
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  Widget _single(List<WidgetNode> children, BuildContext context) =>
      children.isEmpty
      ? const SizedBox.shrink()
      : buildNode(children.first, context);

  // ---------------------------------------------------------------------------
  // Leaves
  // ---------------------------------------------------------------------------

  Widget _text(Map<String, dynamic> p) => Text(
    _string(p['content']),
    maxLines: _double(p['maxLines'])?.toInt(),
    overflow: switch (p['overflow']) {
      'ellipsis' => TextOverflow.ellipsis,
      'clip' => TextOverflow.clip,
      _ => null,
    },
    style: TextStyle(
      fontSize: _double(p['fontSize']),
      fontWeight: _fontWeight(p['fontWeight']),
      color: _color(p['color']) ?? _textInForce ?? _textColor,
      decoration: switch (p['decoration']) {
        'lineThrough' => TextDecoration.lineThrough,
        'underline' => TextDecoration.underline,
        _ => null,
      },
    ),
  );

  /// An image, from the network when [src] names one and from the app's
  /// assets otherwise.
  ///
  /// A load that fails shows the alt text rather than an exception or a blank
  /// space, which is what the other renderers do too.
  Widget _image(Map<String, dynamic> p) {
    final src = _string(p['src']);
    final alt = _string(p['alt']);
    final width = _double(p['width']);
    final height = _double(p['height']);
    final fit = switch (_string(p['fit'], 'cover')) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      'none' => BoxFit.none,
      'scaleDown' => BoxFit.scaleDown,
      _ => BoxFit.cover,
    };

    Widget onError(BuildContext context, Object error, StackTrace? stack) =>
        SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Text(alt, style: TextStyle(color: _textSecondaryColor)),
          ),
        );

    final image =
        src.startsWith('http://') ||
            src.startsWith('https://') ||
            src.startsWith('data:')
        ? Image.network(
            src,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: onError,
          )
        : Image.asset(
            src,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: onError,
          );

    return Semantics(label: alt, image: true, child: image);
  }

  Widget _divider(Map<String, dynamic> p) {
    final thickness = _double(p['thickness']) ?? 1;
    final color = _color(p['color']);
    if (p['orientation'] == 'vertical') {
      return SizedBox(
        height: _double(p['height']) ?? 24,
        child: VerticalDivider(
          thickness: thickness,
          color: color,
          width: thickness,
        ),
      );
    }
    return Divider(
      thickness: thickness,
      color: color,
      height: (_double(p['margin']) ?? 16) * 2 + thickness,
    );
  }

  Widget _loading(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) {
    // A loading node with no colour follows the theme primary.
    final color = _color(p['color']) ?? _primaryColor;
    final indeterminate = p['indeterminate'] == true;
    switch (p['type']) {
      case 'progress-linear':
        return LinearProgressIndicator(
          value: indeterminate ? null : _double(p['value']) ?? 0,
          color: color,
        );
      case 'progress-circular':
        return CircularProgressIndicator(
          value: indeterminate ? null : _double(p['value']) ?? 0,
          color: color,
        );
      case 'skeleton':
        final width = _double(p['width']);
        return Container(
          width: width == null || width.isInfinite ? double.infinity : width,
          height: _double(p['height']) ?? 16,
          decoration: BoxDecoration(
            color: _dividerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      case 'pulse':
        return _single(children, context);
      default:
        final size = _double(p['size']) ?? 24;
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  Widget _button(Map<String, dynamic> p) {
    final label = Text(_string(p['label']));
    final onPressed = p['disabled'] == true ? null : _tap(p);
    final color =
        _color(p['color']) ?? _variantColor(_string(p['variant'], 'primary'));
    final scale = _buttonSize(p['size']);
    // The scale, then whatever the app stated instead of it.
    final height = _double(p['minHeight']) ?? scale.height;
    final width = _double(p['minWidth']) ?? 0;
    final fontSize = _double(p['fontSize']) ?? scale.fontSize;
    final padding = EdgeInsets.symmetric(
      horizontal: _double(p['paddingHorizontal']) ?? scale.padding,
      vertical: _double(p['paddingVertical']) ?? 0,
    );
    final minimumSize = Size(width, height);
    final textStyle = TextStyle(fontSize: fontSize);

    return switch (_string(p['variant'], 'primary')) {
      'secondary' => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
      'tertiary' => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
      _ => ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: _textOn(color),
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
    };
  }

  /// The one button scale, shared by every renderer - see [UIBuilder.button].
  static ({double height, double fontSize, double padding}) _buttonSize(
    Object? size,
  ) => switch (size) {
    'sm' => (height: 28, fontSize: 12, padding: 12),
    'lg' => (height: 44, fontSize: 16, padding: 24),
    _ => (height: 36, fontSize: 14, padding: 16),
  };

  Widget _tabs(Map<String, dynamic> p) {
    final labels = [
      for (final label in (p['tabs'] as List? ?? const [])) '$label',
    ];
    final selected = (_double(p['selectedIndex']) ?? 0).toInt();
    if (labels.isEmpty) return const SizedBox.shrink();
    // Flutter's TabBar wants a controller; the selection lives in the app, so
    // one is made here around the index the tree carries and thrown away with
    // the build.
    return DefaultTabController(
      length: labels.length,
      initialIndex: selected.clamp(0, labels.length - 1),
      child: TabBar(
        tabs: [for (final label in labels) Tab(text: label)],
        labelColor: _primaryColor,
        indicatorColor: _primaryColor,
        unselectedLabelColor: _textSecondaryColor,
        isScrollable: labels.length > 3,
        tabAlignment: labels.length > 3 ? TabAlignment.start : null,
        onTap: (index) => _emit(p, {'index': index}),
      ),
    );
  }

  Widget _slider(Map<String, dynamic> p) {
    final min = _double(p['min']) ?? 0;
    final max = _double(p['max']) ?? 1;
    final divisions = (_double(p['divisions']))?.toInt();
    final eventId = _optString(p['eventId']);
    final data = p['data'];
    void send(String suffix, double value) {
      if (eventId == null) return;
      handleEvent('${eventId}_$suffix', {
        if (data is Map) ...Map<String, dynamic>.from(data),
        'value': value,
      });
    }

    return Slider(
      // Clamped, because a value outside the range is an assertion in Flutter
      // and a silently pinned thumb everywhere else.
      value: (_double(p['value']) ?? min).clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      activeColor: _primaryColor,
      onChanged: p['disabled'] == true
          ? null
          : (value) => send('change', value),
      onChangeEnd: (value) => send('end', value),
    );
  }

  Widget _checkbox(Map<String, dynamic> p) {
    final checkbox = Checkbox(
      // The brand colour, not Material's own: a control is as much the app's
      // as a button is, and the other three renderers tint theirs too.
      activeColor: _primaryColor,
      checkColor: _onPrimaryColor,
      value: p['checked'] == true,
      onChanged: p['disabled'] == true
          ? null
          : (value) => _emit(p, {'checked': value ?? false}),
    );
    final label = _optString(p['label']);
    if (label == null) return checkbox;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [checkbox, Text(label)],
    );
  }

  Widget _radio(Map<String, dynamic> p) {
    // Drawn rather than built from Flutter's Radio: the selection lives in the
    // node's props, not in a RadioGroup ancestor the tree cannot express.
    final selected = p['selected'] == true;
    final disabled = p['disabled'] == true;
    final label = _optString(p['label']);

    return InkWell(
      onTap: disabled ? null : () => _emit(p, {'value': _string(p['value'])}),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: disabled ? _textSecondaryColor : _variantColor('primary'),
          ),
          if (label != null) ...[const SizedBox(width: 8), Text(label)],
        ],
      ),
    );
  }

  Widget _toggle(Map<String, dynamic> p) {
    final toggle = Switch(
      activeThumbColor: _primaryColor,
      activeTrackColor: _primaryColor.withValues(alpha: 0.5),
      value: p['enabled'] == true,
      onChanged: p['disabled'] == true
          ? null
          : (value) => _emit(p, {'enabled': value}),
    );
    final label = _optString(p['label']);
    if (label == null) return toggle;
    return Row(mainAxisSize: MainAxisSize.min, children: [toggle, Text(label)]);
  }

  /// The colour text takes when the tree does not state one, while a
  /// container that stated its own background is being built.
  ///
  /// The build is depth-first and synchronous, so saving and restoring around
  /// a container's children is enough - the same shape the Kotlin and Swift
  /// renderers use. A `LazyList` is the exception: its rows are built when
  /// they scroll into view, by which time nothing is in force, so rows inside
  /// a coloured card keep the theme's text colour.
  Color? _textInForce;

  /// Builds [children] with text over [background] made legible against it.
  List<Widget> _over(
    Object? background,
    List<WidgetNode> children,
    BuildContext context,
  ) {
    final stated = _color(background);
    if (stated == null) {
      return [for (final child in children) buildNode(child, context)];
    }
    final saved = _textInForce;
    _textInForce = _textOn(stated);
    try {
      return [for (final child in children) buildNode(child, context)];
    } finally {
      _textInForce = saved;
    }
  }

  /// A card title's colour: the theme's text over the theme's card, and a
  /// colour chosen for contrast over one the app stated.
  Color? _textOnCard(Map<String, dynamic> p) => switch (_color(
    p['backgroundColor'],
  )) {
    final Color stated => _textOn(stated),
    _ => null,
  };

  Widget _card(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) {
    final title = _optString(p['title']);
    final content = Padding(
      padding: EdgeInsets.all(_double(p['padding']) ?? 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _textOnCard(p),
              ),
            ),
            const SizedBox(height: 8),
          ],
          ..._over(p['backgroundColor'], children, context),
        ],
      ),
    );

    // Every variant draws the colour the app stated; only what it does
    // *besides* the fill - a border, a shadow - is the variant's.
    final fill = _color(p['backgroundColor']) ?? _surfaceVariantColor;
    return switch (_string(p['variant'], 'elevated')) {
      'outlined' => Card(
        elevation: 0,
        color: fill,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      ),
      'filled' => Card(elevation: 0, color: fill, child: content),
      _ => Card(
        elevation: _double(p['elevation']) ?? 2,
        color: fill,
        child: content,
      ),
    };
  }

  /// What the Flutter target shows where a web page would be.
  ///
  /// The other three renderers have a browser view built into the platform;
  /// Flutter's would be `webview_flutter`, a plugin the framework does not
  /// depend on - taking it would put it in every app that uses the framework,
  /// for a node most of them never build. So this says what is missing, where
  /// the page would have been, rather than drawing an empty box or the generic
  /// unknown-widget placeholder.
  ///
  /// Not reported through `renderErrors`: it is a documented limit of this
  /// target, not a surprise, and a render that reported it every time would
  /// bury the errors that are.
  Widget _webViewPlaceholder(Map<String, dynamic> p) => Container(
    height: _double(p['height']) ?? 300,
    decoration: BoxDecoration(
      color: _surfaceVariantColor,
      border: Border.all(color: _dividerColor),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      'A web view needs webview_flutter on the Flutter target.\n'
      '${_string(p['url'])}',
      textAlign: TextAlign.center,
      style: TextStyle(color: _textSecondaryColor, fontSize: 12),
    ),
  );

  /// The Flutter host has no map either: google_maps_flutter needs a
  /// dependency and an API key, which is the app's call. Same shape as the web
  /// view placeholder, and for the same reason - a missing target is a
  /// decision, not a surprise.
  Widget _mapPlaceholder(Map<String, dynamic> p) => _placeholder(
    p,
    'A map needs google_maps_flutter and an API key on the Flutter target.\n'
    '${_double(p['latitude']) ?? 0}, ${_double(p['longitude']) ?? 0}',
  );

  /// A labelled box where a target has no way to draw something.
  Widget _placeholder(Map<String, dynamic> p, String message) => Container(
    height: _double(p['height']) ?? 300,
    decoration: BoxDecoration(
      color: _surfaceVariantColor,
      border: Border.all(color: _dividerColor),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: _textSecondaryColor, fontSize: 12),
    ),
  );

  Widget _badge(Map<String, dynamic> p) {
    final color = _color(p['color']) ?? _primaryColor;
    final label = _optString(p['label']);
    if (p['variant'] == 'dot' || label == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    final outlined = p['variant'] == 'outlined';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? null : color,
        border: outlined ? Border.all(color: color) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: outlined ? color : _textOn(color),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------
  //
  // Drawn from the tree rather than through showDialog and the Navigator: an
  // overlay is the app's state, and has to appear and disappear exactly when
  // the tree says. Nothing here removes one - dismissal only sends an event.

  /// A dialog: a scrim over everything and a surface centred on it.
  Widget _dialog(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) => Stack(
    fit: StackFit.expand,
    children: [
      _scrim(p),
      LayoutBuilder(
        builder: (_, constraints) => Center(
          child: SizedBox(
            width: math.max(0, math.min(560, constraints.maxWidth - 48)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, constraints.maxHeight - 48),
              ),
              child: _modalSurface(
                p,
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 24,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _modalContent(
                      p,
                      children,
                      context,
                      titleGap: 16,
                      // A dialog's last child is its row of actions - see
                      // UIBuilder.dialog. They stay put while the content
                      // scrolls, so Confirm and Cancel are where the user
                      // expects rather than somewhere below the fold.
                      pinLastChild: children.length > 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// The scrim under a dialog or sheet. It takes every tap outside the
  /// surface, whether or not the node lets that tap dismiss it.
  Widget _scrim(Map<String, dynamic> p) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _dismiss(p, 'scrim'),
    child: const ColoredBox(color: Color(0x66000000)),
  );

  /// Announces [surface] the way a platform dialog is announced: a route of
  /// its own, named by the title.
  Widget _modalSurface(Map<String, dynamic> p, Widget surface) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: _optString(p['title']),
    child: surface,
  );

  /// The title, then the children top to bottom, scrolling when they are
  /// taller than the surface allows.
  ///
  /// With [pinLastChild], the last child is left out of the scrolling part and
  /// laid under it - which is how a dialog keeps its actions in reach of a
  /// long body. A surface with nothing to pin (a sheet, a dialog with no
  /// actions) scrolls everything, as before.
  Widget _modalContent(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context, {
    required double titleGap,
    bool pinLastChild = false,
  }) {
    final title = _optString(p['title']);
    final scrolling =
        pinLastChild ? children.sublist(0, children.length - 1) : children;
    final pinned = pinLastChild ? children.last : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: titleGap),
        ],
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in scrolling) buildNode(child, context),
              ],
            ),
          ),
        ),
        if (pinned != null) ...[
          const SizedBox(height: 16),
          buildNode(pinned, context),
        ],
      ],
    );
  }

  /// The callback sending a dialog's or sheet's dismiss event with [reason],
  /// or null when the node cannot be dismissed that way.
  VoidCallback? _dismiss(Map<String, dynamic> p, String reason) {
    final eventId = p['dismissEventId'];
    if (p['dismissible'] == false || eventId is! String) return null;
    return () => handleEvent(eventId, {'reason': reason});
  }

  /// What tells a snackbar from its replacement.
  static String _snackbarIdentity(Map<String, dynamic> p) =>
      _optString(p['id']) ??
      _optString(p['dismissEventId']) ??
      _string(p['message']);

  // ---------------------------------------------------------------------------
  // Lazy lists
  // ---------------------------------------------------------------------------

  _LazyListController _scrollControllerFor(String listId) =>
      _scrollControllers.putIfAbsent(listId, _LazyListController.new);

  /// Sends the visible range of the list [listId], unless it is the range
  /// last sent for that list.
  void _reportRange(String listId, String eventId, int first, int last) {
    if (_reportedRanges[listId] == (first, last)) return;
    _reportedRanges[listId] = (first, last);
    handleEvent(eventId, {'first': first, 'last': last});
  }

  /// Where a list of rows of their own heights is scrolled to.
  ///
  /// Only the Dart side knows how tall the rows outside the window are, so a
  /// renderer drawing them reports pixels and lets it do the arithmetic.
  void _reportOffset(
    String listId,
    String eventId,
    double offset,
    double viewport,
  ) {
    if (_reportedOffsets[listId] == (offset, viewport)) return;
    _reportedOffsets[listId] = (offset, viewport);
    handleEvent(eventId, {'offset': offset, 'viewport': viewport});
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /// The tap callback for a node, or null when it fires nothing.
  VoidCallback? _tap(Map<String, dynamic> p) {
    if (p['eventId'] is! String) return null;
    return () => _emit(p, const {});
  }

  /// Parses a SwipeActions node's `actions` into (label, color, eventId).
  List<({String label, Color color, String eventId})> _swipeActions(
      Map<String, dynamic> p, {String key = 'actions'}) {
    final raw = p[key];
    if (raw is! List) return const [];
    return [
      for (final a in raw)
        if (a is Map && a['eventId'] is String)
          (
            label: _string(a['label']),
            color: _color(a['color']) ?? _errorColor,
            eventId: a['eventId'] as String,
          ),
    ];
  }

  /// Sends the node's event with its payload plus [extra].
  void _emit(Map<String, dynamic> p, Map<String, dynamic> extra) {
    final eventId = p['eventId'];
    if (eventId is! String) return;
    final data = p['data'];
    handleEvent(eventId, {
      if (data is Map) ...Map<String, dynamic>.from(data),
      ...extra,
    });
  }

  /// The controller for the field with [eventId], created on first use with
  /// the value the tree last declared.
  TextEditingController _controllerFor(String eventId, String value) =>
      _controllers.putIfAbsent(
        eventId,
        () => TextEditingController(text: _appliedValues[eventId] ?? value),
      );

  // ---------------------------------------------------------------------------
  // Prop conversion
  // ---------------------------------------------------------------------------

  static String _string(Object? value, [String fallback = '']) =>
      value is String ? value : (value == null ? fallback : '$value');

  static String? _optString(Object? value) => value is String ? value : null;

  /// The insets a Padding node asks for: one number for every edge, or four.
  static EdgeInsets _insets(Map<String, dynamic> p) {
    final uniform = _double(p['padding']);
    if (uniform != null) return EdgeInsets.all(uniform);
    return EdgeInsets.fromLTRB(
      _double(p['paddingLeft']) ?? 0,
      _double(p['paddingTop']) ?? 0,
      _double(p['paddingRight']) ?? 0,
      _double(p['paddingBottom']) ?? 0,
    );
  }

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static FontWeight? _fontWeight(Object? value) => switch (value) {
    300 => FontWeight.w300,
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    700 => FontWeight.w700,
    _ => null,
  };

  /// Parses `#rgb`, `#rrggbb` and `#aarrggbb`.
  /// The `durationMs` a motion node carries.
  static Duration _duration(Map<String, dynamic> p) =>
      Duration(milliseconds: (_double(p['durationMs']) ?? 200).toInt());

  /// A protocol curve name as a Flutter [Curve].
  static Curve _curve(Map<String, dynamic> p) {
    switch (p['curve']) {
      case 'linear':
        return Curves.linear;
      case 'ease':
        return Curves.ease;
      case 'easeIn':
        return Curves.easeIn;
      case 'easeOut':
        return Curves.easeOut;
      default:
        return Curves.easeInOut;
    }
  }

  /// Text drawn over a colour the app stated, rather than over the surface
  /// the theme's text colour was chosen against. See `src/contrast.dart`.
  static Color _textOn(Color background) {
    final rgb = background.toARGB32() & 0xFFFFFF;
    return _color(
      contrast.textOn('#${rgb.toRadixString(16).padLeft(6, '0')}'),
    )!;
  }

  static Color? _color(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    var hex = value.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }

  Color _variantColor(String variant) => switch (variant) {
    'success' => _successColor,
    'error' => _errorColor,
    'warning' => _warningColor,
    'secondary' => _secondaryColor,
    _ => _primaryColor,
  };

  static CrossAxisAlignment _crossAxis(Object? value) => switch (value) {
    'start' => CrossAxisAlignment.start,
    'end' => CrossAxisAlignment.end,
    'stretch' => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.center,
  };

  static CrossAxisAlignment _stackCrossAxis(Object? value) => switch (value) {
    'center' => CrossAxisAlignment.center,
    'trailing' => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.start,
  };

  static CrossAxisAlignment _hStackCrossAxis(Object? value) => switch (value) {
    'top' => CrossAxisAlignment.start,
    'bottom' => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.center,
  };

  static MainAxisAlignment _mainAxis(Object? value) => switch (value) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'spaceBetween' => MainAxisAlignment.spaceBetween,
    _ => MainAxisAlignment.start,
  };

  /// Inserts [spacing] between [children], the way a CSS gap does.
  static List<Widget> _spaced(
    List<Widget> children,
    double? spacing, {
    required bool vertical,
  }) {
    if (spacing == null || spacing <= 0 || children.length < 2) return children;
    final gap = vertical ? SizedBox(height: spacing) : SizedBox(width: spacing);
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) gap,
        children[i],
      ],
    ];
  }

  /// Material icon name -> icon. Unknown names fall back to a dot, which is
  /// visible rather than silently absent.
  static IconData _icon(String name) => _icons[name] ?? Icons.circle;

  static const Map<String, IconData> _icons = {
    'add': Icons.add,
    'remove': Icons.remove,
    'delete': Icons.delete,
    'edit': Icons.edit,
    'close': Icons.close,
    'check': Icons.check,
    'search': Icons.search,
    'settings': Icons.settings,
    'home': Icons.home,
    'person': Icons.person,
    'menu': Icons.menu,
    'more_vert': Icons.more_vert,
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'refresh': Icons.refresh,
    'save': Icons.save,
    'share': Icons.share,
    'favorite': Icons.favorite,
    'star': Icons.star,
    'info': Icons.info,
    'warning': Icons.warning,
    'error': Icons.error,
  };
}

/// A text field that keeps its controller and reports focus changes.
class _NodeTextField extends StatefulWidget {
  const _NodeTextField({required this.renderer, required this.props});

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;

  @override
  State<_NodeTextField> createState() => _NodeTextFieldState();
}

class _NodeTextFieldState extends State<_NodeTextField> {
  final FocusNode _focusNode = FocusNode();
  String get _eventId => FlutterUIRenderer._string(widget.props['eventId']);

  /// The focus ask this field has already carried out, so the same version is
  /// not obeyed twice.
  int? _focusVersion;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_reportFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFocusRequest());
  }

  @override
  void didUpdateWidget(_NodeTextField old) {
    super.didUpdateWidget(old);
    _applyFocusRequest();
  }

  /// Takes or gives up the keyboard when the app asks: once for `autofocus`,
  /// and again whenever `focusVersion` changes.
  void _applyFocusRequest() {
    if (!mounted) return;
    final p = widget.props;
    final version = FlutterUIRenderer._double(p['focusVersion'])?.toInt();
    if (version != null) {
      if (_focusVersion == version) return;
      _focusVersion = version;
      if (p['focusRequested'] == false) {
        _focusNode.unfocus();
      } else {
        _focusNode.requestFocus();
      }
      return;
    }
    if (p['autofocus'] == true && _focusVersion == null) {
      _focusVersion = -1;
      _focusNode.requestFocus();
    }
  }

  void _reportFocus() {
    if (_eventId.isEmpty) return;
    widget.renderer.handleEvent(
      '${_eventId}_${_focusNode.hasFocus ? 'focus' : 'blur'}',
      {'value': _controller.text},
    );
  }

  TextEditingController get _controller => widget.renderer._controllerFor(
    _eventId,
    FlutterUIRenderer._optString(widget.props['initialValue']) ?? '',
  );

  @override
  void dispose() {
    _focusNode
      ..removeListener(_reportFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final maxLines = (FlutterUIRenderer._double(p['maxLines']) ?? 1).toInt();

    final advances = p['textInputAction'] == 'next';
    final label = FlutterUIRenderer._optString(p['label']);
    // A label floats in the outline unless the app asked for it above the
    // field, which is the other renderers' plain-label layout; Flutter draws
    // that as a Text of its own, since InputDecoration has no place for it.
    final floating = label != null && p['floatingLabel'] != false;
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: p['enabled'] != false,
      obscureText: p['obscureText'] == true,
      maxLines: p['obscureText'] == true ? 1 : maxLines,
      textInputAction: advances ? TextInputAction.next : TextInputAction.done,
      decoration: InputDecoration(
        hintText: FlutterUIRenderer._optString(p['hint'] ?? p['placeholder']),
        labelText: floating ? label : null,
        errorText: FlutterUIRenderer._optString(p['error']),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) =>
          widget.renderer.handleEvent('${_eventId}_change', {'value': value}),
      onSubmitted: (value) {
        widget.renderer.handleEvent('${_eventId}_submit', {'value': value});
        // The app hears the submit either way; what differs is where the caret
        // goes next. nextFocus() answers false at the last field, and then the
        // keyboard closing is the right thing anyway.
        if (advances) FocusScope.of(context).nextFocus();
      },
    );
    if (label == null || floating) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: widget.renderer._textSecondaryColor,
            ),
          ),
        ),
        field,
      ],
    );
  }
}

/// An alert the user can dismiss.
class _NodeAlert extends StatefulWidget {
  const _NodeAlert({required this.props, required this.renderer});

  final Map<String, dynamic> props;

  /// For the palette: an alert's colour is the theme's semantic one, which the
  /// renderer resolves for the appearance in force.
  final FlutterUIRenderer renderer;

  @override
  State<_NodeAlert> createState() => _NodeAlertState();
}

class _NodeAlertState extends State<_NodeAlert> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final p = widget.props;
    final color = switch (p['type']) {
      'success' => widget.renderer._successColor,
      'error' => widget.renderer._errorColor,
      'warning' => widget.renderer._warningColor,
      _ => widget.renderer._infoColor,
    };
    final title = FlutterUIRenderer._optString(p['title']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  ),
                Text(FlutterUIRenderer._string(p['message'])),
              ],
            ),
          ),
          if (p['dismissible'] == true)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
              onPressed: () => setState(() => _dismissed = true),
            ),
        ],
      ),
    );
  }
}

/// A bottom sheet that can be dragged down to ask for its dismissal.
class _NodeBottomSheet extends StatefulWidget {
  const _NodeBottomSheet({
    required this.renderer,
    required this.props,
    required this.children,
  });

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;
  final List<WidgetNode> children;

  @override
  State<_NodeBottomSheet> createState() => _NodeBottomSheetState();
}

class _NodeBottomSheetState extends State<_NodeBottomSheet> {
  /// How far the sheet is dragged below its resting place.
  double _offset = 0;
  bool _dragging = false;

  void _dragEnd(DragEndDetails details, VoidCallback dismiss) {
    final height = context.size?.height ?? 0;
    if (_offset > height / 4 || (details.primaryVelocity ?? 0) > 700) {
      dismiss();
    }
    // Springs back either way: the sheet goes when the app removes it.
    setState(() {
      _offset = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.renderer;
    final p = widget.props;
    final dismiss = renderer._dismiss(p, 'swipe');

    final sheet = TweenAnimationBuilder<double>(
      tween: Tween(end: _offset),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
      child: GestureDetector(
        onVerticalDragStart: dismiss == null
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: dismiss == null
            ? null
            : (details) => setState(
                () => _offset = math.max(0, _offset + details.delta.dy),
              ),
        onVerticalDragEnd: dismiss == null
            ? null
            : (details) => _dragEnd(details, dismiss),
        child: renderer._modalSurface(
          p,
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: renderer._modalContent(
                  p,
                  widget.children,
                  context,
                  titleGap: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        renderer._scrim(p),
        LayoutBuilder(
          builder: (_, constraints) => Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: constraints.maxHeight * 0.9,
              ),
              child: SizedBox(width: double.infinity, child: sheet),
            ),
          ),
        ),
      ],
    );
  }
}

/// A snackbar, which sends its dismiss event once its duration is up.
class _NodeSnackbar extends StatefulWidget {
  const _NodeSnackbar({super.key, required this.renderer, required this.props});

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;

  @override
  State<_NodeSnackbar> createState() => _NodeSnackbarState();
}

class _NodeSnackbarState extends State<_NodeSnackbar> {
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    // Started once per State, which the key ties to the snackbar's identity:
    // rendering it again neither restarts nor repeats the timer.
    final durationMs = FlutterUIRenderer._double(widget.props['durationMs']);
    if (durationMs != null && durationMs > 0) {
      _timeout = Timer(Duration(milliseconds: durationMs.toInt()), () {
        final eventId = widget.props['dismissEventId'];
        if (eventId is String) {
          widget.renderer.handleEvent(eventId, {'reason': 'timeout'});
        }
      });
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final actionLabel = FlutterUIRenderer._optString(p['actionLabel']);
    final actionEventId = p['actionEventId'];
    final inverse = widget.renderer._inversePalette;

    // Aligned rather than filling the area, so taps beside it reach the
    // screen: a snackbar blocks nothing but itself.
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              color: FlutterUIRenderer._color(inverse.surface) ??
                  const Color(0xff323232),
              elevation: 6,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          FlutterUIRenderer._string(p['message']),
                          style: TextStyle(
                            color: FlutterUIRenderer._color(inverse.text) ??
                                Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (actionLabel != null)
                      TextButton(
                        onPressed: actionEventId is String
                            ? () => widget.renderer.handleEvent(
                                actionEventId,
                                const {},
                              )
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              FlutterUIRenderer._color(inverse.primary) ??
                                  const Color(0xff90caf9),
                        ),
                        child: Text(actionLabel),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A scroll controller that starts a new scroll position where the last one
/// left off, so a list rebuilt from scratch keeps its offset.
class _LazyListController extends ScrollController {
  // The offset is kept here rather than in PageStorage, which is keyed by
  // where the list sits in the widget tree and has no say in which list it is.
  _LazyListController() : super(keepScrollOffset: false) {
    addListener(() {
      if (hasClients) _lastOffset = positions.last.pixels;
    });
  }

  double _lastOffset = 0;

  @override
  double get initialScrollOffset => _lastOffset;
}

/// A long list of fixed-height rows, of which the tree carries a window.
///
/// Reports the visible rows after the first layout, on scroll and when the
/// viewport or the row count changes; the renderer drops a report that
/// repeats the last one.
class _NodeLazyList extends StatefulWidget {
  const _NodeLazyList({
    super.key,
    required this.renderer,
    required this.props,
    required this.rows,
  });

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;
  final List<WidgetNode> rows;

  @override
  State<_NodeLazyList> createState() => _NodeLazyListState();
}

class _NodeLazyListState extends State<_NodeLazyList> {
  late final _LazyListController _controller;

  String get _listId => FlutterUIRenderer._string(widget.props['id']);

  int get _itemCount => math
      .max(0, (FlutterUIRenderer._double(widget.props['itemCount']) ?? 0))
      .toInt();

  double get _itemExtent =>
      FlutterUIRenderer._double(widget.props['itemExtent']) ?? 0;

  /// The heights of the rows in the window, when they differ from each other.
  List<double> get _rowExtents {
    final extents = widget.props['extents'];
    if (extents is! List) return const [];
    return [
      for (final extent in extents)
        FlutterUIRenderer._double(extent) ?? 0,
    ];
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.renderer._scrollControllerFor(_listId)
      ..addListener(_report);
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _report() {
    if (!mounted) return;
    // The app may re-render in response, which must not happen mid-build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _report());
      return;
    }
    final eventId = widget.props['rangeEventId'];
    final extent = _itemExtent;
    final position = _controller.hasClients ? _controller.positions.last : null;
    if (eventId is! String ||
        position == null ||
        !position.hasPixels ||
        !position.hasViewportDimension) {
      return;
    }

    final offset = math.max(0.0, position.pixels);
    if (_rowExtents.isNotEmpty) {
      widget.renderer._reportOffset(
        _listId,
        eventId,
        offset,
        position.viewportDimension,
      );
      return;
    }
    if (extent <= 0) return;
    final first = (offset / extent).floor();
    final last = math.min(
      _itemCount - 1,
      ((offset + position.viewportDimension) / extent).ceil() - 1,
    );
    widget.renderer._reportRange(_listId, eventId, first, last);
  }

  @override
  void dispose() {
    _controller.removeListener(_report);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = _itemExtent;
    final rowExtents = _rowExtents;
    final start = (FlutterUIRenderer._double(widget.props['startIndex']) ?? 0)
        .toInt();
    final rows = widget.rows;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _report();
        return false;
      },
      child: rowExtents.isEmpty
          ? ListView.builder(
              controller: _controller,
              itemCount: _itemCount,
              itemExtent: extent > 0 ? extent : null,
              itemBuilder: (context, index) {
                final row = index - start;
                // Rows outside the window hold their place until it moves to
                // them.
                if (row < 0 || row >= rows.length) {
                  return SizedBox(height: extent);
                }
                return widget.renderer.buildNode(rows[row], context);
              },
            )
          // Rows of their own heights: the list is one tall box, with the rows
          // it holds placed at the offset the tree gave them. A ListView
          // cannot do this - it would have to measure the rows it does not
          // have - so the scrolling is a plain one over a sized column.
          : SingleChildScrollView(
              controller: _controller,
              child: SizedBox(
                height: FlutterUIRenderer._double(widget.props['totalExtent']),
                child: Column(
                  children: [
                    SizedBox(
                      height:
                          FlutterUIRenderer._double(
                            widget.props['startOffset'],
                          ) ??
                          0,
                    ),
                    for (var i = 0; i < rows.length; i++)
                      SizedBox(
                        height: i < rowExtents.length ? rowExtents[i] : null,
                        width: double.infinity,
                        child: widget.renderer.buildNode(rows[i], context),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Hosts a [NativeUIApp] in a Flutter widget tree.
///
/// Mounts the app on a [FlutterUIRenderer], rebuilds whenever it renders, and
/// disposes the renderer with the widget. This is the whole integration for an
/// existing Flutter app: push it like any other screen.
class NativeUIAppHost extends StatefulWidget {
  const NativeUIAppHost({
    super.key,
    required this.app,
    this.theme = AppTheme.fallback,
  });

  final NativeUIApp app;
  final AppTheme theme;

  @override
  State<NativeUIAppHost> createState() => NativeUIAppHostState();
}

class NativeUIAppHostState extends State<NativeUIAppHost> {
  late final FlutterUIRenderer renderer;

  @override
  void initState() {
    super.initState();
    renderer = FlutterUIRenderer(onTreeChanged: _rebuild, theme: widget.theme);
    widget.app.mount(renderer);
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload replaces build() but changes no state, so nothing would ask
    // the app to paint again. Rendering here makes an edit show up the way it
    // does in an ordinary Flutter app.
    widget.app.render();
  }

  void _rebuild() {
    if (!mounted) return;
    // A render can arrive while this frame is already building (the first one
    // does, from mount above), so the rebuild is deferred to the next frame.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() {});
    } else {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (mounted) setState(() {});
        })
        // A render sent from a post-frame callback - a lazy list reporting
        // its range - would otherwise wait for a frame nothing asked for.
        ..scheduleFrame();
    }
  }

  @override
  void dispose() {
    renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => renderer.build(context);
}

/// A row that slides [child] left to reveal trailing action buttons: a partial
/// drag snaps open so an action can be tapped, a full drag fires the first one.
/// [child] is backed by [surface] so the actions stay hidden until swiped.
class _SwipeActionsRow extends StatefulWidget {
  const _SwipeActionsRow({
    required this.actions,
    required this.surface,
    required this.onFire,
    required this.child,
    this.leadingActions = const [],
  });

  final List<({String label, Color color, String eventId})> actions;

  /// Revealed by dragging the row the other way, at its leading edge.
  final List<({String label, Color color, String eventId})> leadingActions;
  final Color surface;
  final void Function(String eventId) onFire;
  final Widget child;

  @override
  State<_SwipeActionsRow> createState() => _SwipeActionsRowState();
}

class _SwipeActionsRowState extends State<_SwipeActionsRow> {
  static const double _actionWidth = 88;

  /// How far the child is slid left; 0 is closed, negative reveals the actions.
  double _offset = 0;

  double get _open => -_actionWidth * widget.actions.length;
  double get _openLeading => _actionWidth * widget.leadingActions.length;
  // A drag well past the open position fires the first action outright.
  double get _fullSwipe => _open * 1.6;
  double get _fullSwipeLeading => _openLeading * 1.6;

  void _fire(String eventId) {
    widget.onFire(eventId);
    setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty && widget.leadingActions.isEmpty) {
      return widget.child;
    }
    Widget bar(
      List<({String label, Color color, String eventId})> actions,
      MainAxisAlignment alignment,
    ) => Positioned.fill(
      child: Row(
        mainAxisAlignment: alignment,
        children: [
          for (final a in actions)
            GestureDetector(
              onTap: () => _fire(a.eventId),
              child: Container(
                width: _actionWidth,
                color: a.color,
                alignment: Alignment.center,
                child: Text(
                  a.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return ClipRect(
      child: Stack(
        children: [
          if (widget.leadingActions.isNotEmpty)
            bar(widget.leadingActions, MainAxisAlignment.start),
          bar(widget.actions, MainAxisAlignment.end),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(
                () => _offset = (_offset + d.delta.dx)
                    .clamp(_open * 1.8, _openLeading * 1.8),
              ),
              onHorizontalDragEnd: (_) {
                if (_offset <= _fullSwipe && widget.actions.isNotEmpty) {
                  _fire(widget.actions.first.eventId);
                } else if (_offset >= _fullSwipeLeading &&
                    widget.leadingActions.isNotEmpty) {
                  _fire(widget.leadingActions.first.eventId);
                } else {
                  setState(() {
                    if (_offset <= _open / 2) {
                      _offset = _open;
                    } else if (_openLeading > 0 && _offset >= _openLeading / 2) {
                      _offset = _openLeading;
                    } else {
                      _offset = 0;
                    }
                  });
                }
              },
              // As wide as it is offered, like the row the other three
              // renderers draw: a Stack takes its size from this child, and a
              // narrow one would leave the actions behind it sticking out.
              child: Container(
                color: widget.surface,
                width: double.infinity,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
