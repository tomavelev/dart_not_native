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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/app_theme.dart';
import '../src/contrast.dart' as contrast;
import '../src/event_binding.dart';
import '../src/flutter_slots.dart';
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

  /// The `scrollVersion` last obeyed for each lazy list, by list id.
  final Map<String, int?> _appliedScrollVersions = {};

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
    // A FlutterSlot this renderer drew and the tree no longer holds is done
    // with; its builder goes with it.
    FlutterSlots.instance.sync(this, tree);
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
    // The widgets are built from a tree a frame after it is rendered, so a
    // tap can arrive from the widgets of the build before: it is answered by
    // the build they were made from - see EventBindings.
    final outer = EventBindings.eventBuild;
    EventBindings.eventBuild = _shownBuild;
    try {
      handler(data);
    } finally {
      EventBindings.eventBuild = outer;
    }
    return {'success': true};
  }

  /// The number of the build the widgets on screen were made from; null
  /// before the first frame and for a tree no build produced.
  int? _shownBuild;

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
    _reportedOffsets.clear();
    _appliedScrollVersions.clear();
    FlutterSlots.instance.release(this);
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
    _shownBuild = EventBindings.buildOf(tree);
    // Read once, at the root, so every node below paints one appearance even
    // if the device flips mid-build.
    _platformIsDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    // The direction is the tree's to say, not the host's: a tree that states
    // none reads left to right on every renderer, so it does here too, even
    // inside a Flutter app whose own locale is Arabic. Everything Flutter
    // draws below - a row's order, an app bar's ends, a list tile, a text
    // field's icons, the back arrow - follows this one widget.
    return Directionality(
      textDirection: tree.props[RootProps.textDirection] == 'rtl'
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Builder(
        builder: (context) {
          final widget = buildNode(tree, context);
          if (tree.type == 'Scaffold' || tree.type == 'NavigationStack') {
            return widget;
          }
          return Material(type: MaterialType.transparency, child: widget);
        },
      ),
    );
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
        return _scaffold(p, children, context);
      case 'NavigationStack':
        return _scaffold(p, children, context);
      case 'AppBar':
      case 'NavigationBar':
        return _appBarBody(p);
      case 'Column':
        final distributes = p['mainAxisAlignment'] != null;
        return Column(
          crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
          mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
          // A column hugs its children unless it was asked to distribute them,
          // and there is nothing to distribute inside a column that hugs -
          // unless the tree says outright which it wants.
          mainAxisSize: switch (p['mainAxisSize']) {
            'max' => MainAxisSize.max,
            'min' => MainAxisSize.min,
            _ => distributes ? MainAxisSize.max : MainAxisSize.min,
          },
          spacing: _double(p['spacing']) ?? 0,
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
          crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
          mainAxisSize: _optString(p['mainAxisSize']),
          distributes: switch (p['mainAxisAlignment']) {
            null || 'start' => false,
            _ => true,
          },
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
          alignment: _wrapAlignment(_mainAxis(p['alignment'])),
          crossAxisAlignment: switch (p['crossAxisAlignment']) {
            'center' => WrapCrossAlignment.center,
            'end' => WrapCrossAlignment.end,
            _ => WrapCrossAlignment.start,
          },
          children: build(children),
        );
      case 'Expanded':
        final flex = (_double(p['flex']) ?? 1).toInt();
        // Loose lets the child be smaller than its share, which is Flutter's
        // Flexible; an Expanded is the same thing with a tight fit.
        return p['fit'] == 'loose'
            ? Flexible(flex: flex, child: _single(children, context))
            : Expanded(flex: flex, child: _single(children, context));
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
        return _image(p, children, context);
      case 'Divider':
        return _divider(p);
      case 'Loading':
        return _loading(p, children, context);
      case 'Button':
      case 'MaterialButton':
        return _button(p);
      case 'IconButton':
        return _iconButton(p);
      case 'FloatingActionButton':
        return _fab(p);
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
      case 'Box':
        return _box(p, children, context);
      case 'Stack':
        return _stack(p, children, context);
      case 'Positioned':
        // Pinning is the Stack's doing - see _stack. Outside one, a
        // Positioned is its child.
        return _single(children, context);
      case 'Scroll':
        final id = _optString(p['id']);
        return _NodeScroll(
          key: id == null ? null : ValueKey('scroll:$id'),
          renderer: this,
          props: p,
          child: _single(children, context),
        );
      case 'Icon':
        return _iconNode(p);
      case 'Canvas':
        return _box(p, children, context, canvas: true);
      case 'Dropdown':
        return _dropdown(p);
      case 'DatePicker':
      case 'TimePicker':
        // Keyed by the picker, so the same one rendered again keeps its
        // dialog - and whatever the user has scrolled to in it.
        return _NodePicker(
          key: ValueKey('picker:${_string(p['id'])}'),
          renderer: this,
          props: p,
          time: node.type == 'TimePicker',
        );
      case 'BottomBar':
        // Pinned by the Scaffold that finds it; anywhere else it is its child.
        return _single(children, context);
      case 'BottomNavigation':
        return _bottomNavigation(p);
      case 'FlutterSlot':
        return _flutterSlot(p, children, context);
      default:
        _unknownTypes.add(node.type);
        return Text('Unknown widget: ${node.type}');
    }
    // node-types:end
  }

  // ---------------------------------------------------------------------------
  // Structure
  // ---------------------------------------------------------------------------

  /// A Scaffold's children are told apart by type - the shape
  /// [UIBuilder.scaffold] builds: the app bar, the bar along the bottom, the
  /// floating action button, and the body, which is whatever is none of those.
  Widget _scaffold(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) {
    WidgetNode? appBar;
    WidgetNode? fab;
    WidgetNode? bottomBar;
    final body = <WidgetNode>[];
    for (final child in children) {
      switch (child.type) {
        case 'AppBar':
        case 'NavigationBar':
          appBar ??= child;
        case 'FloatingActionButton':
          fab ??= child;
        case 'BottomBar':
          bottomBar ??= child;
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

    // `bodyScrolls: false` is the tree saying the body lays itself out against
    // the screen. A body holding a lazy list says the same without being
    // asked: the list scrolls itself, and needs the bounded height a
    // SingleChildScrollView would take away.
    final fixed = p['bodyScrolls'] == false;
    final scrollsItself = fixed || body.any(_holdsLazyList);
    final content = body.length == 1
        ? buildNode(body.single, context)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: scrollsItself ? MainAxisSize.max : MainAxisSize.min,
            children: [for (final child in body) buildNode(child, context)],
          );

    Widget? bodyWidget = body.isEmpty
        ? null
        : fixed
        // Exactly the room that is left, not merely at most it: an Expanded,
        // a Scroll or a Stack inside has a height to divide.
        ? SizedBox.expand(child: content)
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
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: content,
              ),
            ),
          )
        : SingleChildScrollView(child: content);
    // The Scaffold has already taken the app bar and the bottom bar out of
    // the insets the body sees, so this only adds what is still uncovered.
    if (bodyWidget != null && p['safeArea'] != false) {
      bodyWidget = SafeArea(child: bodyWidget);
    }

    // What the scaffold keeps along its bottom edge is measured, for a
    // snackbar - drawn beside the scaffold, not in it - to sit above. A
    // scaffold without one of them says so once this frame is done.
    if (fab == null || bottomBar == null) {
      final noFab = fab == null;
      final noBar = bottomBar == null;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _bottomTaken.value = (
          bar: noBar ? 0 : _bottomTaken.value.bar,
          fab: noFab ? 0 : _bottomTaken.value.fab,
        );
      });
    }
    return Scaffold(
      backgroundColor: _color(p['backgroundColor']),
      appBar: appBar == null ? null : _appBar(appBar, context),
      body: bodyWidget,
      floatingActionButton: fab == null
          ? null
          : _FromBottom(
              onChanged: (taken) => _bottomTaken.value = (
                bar: _bottomTaken.value.bar,
                fab: taken,
              ),
              child: buildNode(fab, context),
            ),
      bottomNavigationBar: bottomBar == null
          ? null
          : _FromBottom(
              onChanged: (taken) => _bottomTaken.value = (
                bar: taken,
                fab: _bottomTaken.value.fab,
              ),
              child: _bottomBar(bottomBar, context),
            ),
    );
  }

  /// How far up from the scaffold's bottom edge its bottom bar and its
  /// floating button reach, as last painted; zero for one it does not have.
  final ValueNotifier<({double bar, double fab})> _bottomTaken = ValueNotifier(
    (bar: 0, fab: 0),
  );

  /// The bar across the top of a Scaffold.
  PreferredSizeWidget _appBar(WidgetNode node, BuildContext context) {
    final p = node.props;
    final children = node.children ?? const <WidgetNode>[];
    final background = _color(p['backgroundColor']);
    // The colour the app stated, else one that reads over the background it
    // stated, else Material's own.
    final foreground =
        _color(p['foregroundColor']) ??
        (background == null ? null : _textOn(background));
    // The title subtree, when there is one, is the first child; the rest are
    // the actions.
    final hasTitleNode = p['hasTitleNode'] == true && children.isNotEmpty;
    final actions = hasTitleNode ? children.sublist(1) : children;
    final centerTitle = p['centerTitle'];
    // Text and icons in the bar take its foreground unless they state a
    // colour of their own.
    return _withText(
      foreground,
      () => AppBar(
        leading: _appBarLeading(p, context),
        title: hasTitleNode
            ? buildNode(children.first, context)
            : Text(_string(p['title'])),
        actions: actions.isEmpty
            ? null
            : [for (final action in actions) buildNode(action, context)],
        centerTitle: centerTitle is bool ? centerTitle : null,
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: _double(p['elevation']),
      ),
    );
  }

  /// The button at the start of an app bar: 'back', 'close' or 'menu', drawn
  /// and announced the way Material does each.
  Widget? _appBarLeading(Map<String, dynamic> p, BuildContext context) {
    final kind = p['leading'];
    if (kind is! String) return null;
    final l10n = MaterialLocalizations.of(context);
    final (Widget icon, String tooltip) = switch (kind) {
      'close' => (const Icon(Icons.close), l10n.closeButtonTooltip),
      'menu' => (const Icon(Icons.menu), l10n.openAppDrawerTooltip),
      _ => (const BackButtonIcon(), l10n.backButtonTooltip),
    };
    final eventId = p['leadingEventId'];
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: eventId is String
          ? () => handleEvent(eventId, const {})
          : null,
    );
  }

  /// What a Scaffold pins along its bottom edge.
  Widget _bottomBar(WidgetNode node, BuildContext context) {
    final children = node.children ?? const <WidgetNode>[];
    final child = _single(children, context);
    // A NavigationBar paints under the system's inset and keeps its
    // destinations above it by itself; anything else is given a surface that
    // does the same.
    if (children.firstOrNull?.type == 'BottomNavigation') return child;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(top: false, child: child),
    );
  }

  /// Whether [node] lays its children out in the space it is given, rather
  /// than sizing itself to them - the same question the native scaffolds ask.
  static bool _fillsViewport(WidgetNode node) =>
      node.type == 'Center' ||
      ((node.type == 'Column' || node.type == 'VStack') &&
          switch (node.props['mainAxisSize']) {
            'max' => true,
            'min' => false,
            _ => node.props['mainAxisAlignment'] != null,
          });

  static bool _holdsLazyList(WidgetNode node) =>
      node.type == 'LazyList' ||
      (node.children ?? const <WidgetNode>[]).any(_holdsLazyList);

  /// A horizontal run of children.
  ///
  /// A row that says how it uses its width is Flutter's `Row`: one that asks
  /// for `mainAxisSize: 'max'`, or whose alignment distributes ([distributes]:
  /// anything but the start), is as wide as it is offered and places its
  /// children along that - which is the only way `spaceBetween` has anything
  /// to share out, or a trailing child reaches the far edge. So is one holding
  /// an [Expanded], which needs real flex semantics.
  ///
  /// A row that asks for neither - the hand-written `UIBuilder.row(children:)`
  /// - becomes a Wrap: the web renderer lets a long row shrink and spill
  /// quietly, where a Flutter Row would overflow and paint a stripe, so the
  /// content reflows instead. It used to be every row without an `Expanded`,
  /// which shrink-wrapped the ones that had asked to fill.
  Widget _row(
    List<WidgetNode> children,
    BuildContext context, {
    double? spacing,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    String? mainAxisSize,
    bool distributes = false,
  }) {
    final built = [for (final child in children) buildNode(child, context)];
    final hasFlexChild = children.any((c) => c.type == 'Expanded');

    // Stretching is a Row's too: a Wrap has no cross axis to stretch across.
    if (hasFlexChild ||
        distributes ||
        mainAxisSize == 'max' ||
        crossAxisAlignment == CrossAxisAlignment.stretch) {
      return Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: mainAxisSize == 'min'
            ? MainAxisSize.min
            : MainAxisSize.max,
        spacing: spacing ?? 0,
        children: built,
      );
    }

    // A Wrap is as wide as its longest line, which is what a row that asked
    // for nothing, or for 'min', has always been here.
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
        MainAxisAlignment.spaceAround => WrapAlignment.spaceAround,
        MainAxisAlignment.spaceEvenly => WrapAlignment.spaceEvenly,
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
            color:
                _color(p['foregroundColor']) ??
                switch (_color(p['backgroundColor'])) {
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

  Widget _text(Map<String, dynamic> p) {
    final content = _string(p['content']);
    final maxLines = _double(p['maxLines'])?.toInt();
    final family = _fontFamily(p['fontFamily']);
    final style = TextStyle(
      fontSize: _double(p['fontSize']),
      fontWeight: _fontWeight(p['fontWeight']),
      color: _color(p['color']) ?? _textInForce ?? _textColor,
      decoration: _decoration(p['decoration']),
      letterSpacing: _double(p['letterSpacing']),
      // A multiple of the font size, which is how Flutter spells it too.
      height: _double(p['lineHeight']),
      fontFamily: family.$1,
      fontFamilyFallback: family.$2,
      fontStyle: p['italic'] == true ? FontStyle.italic : null,
    );
    final textAlign = _textAlign(p['textAlign']);
    // Runs with their own style, each inheriting the rest from the node.
    final rawSpans = p['spans'];
    final spans = rawSpans is List && rawSpans.isNotEmpty
        ? TextSpan(
            children: [
              for (final span in rawSpans)
                if (span is Map)
                  TextSpan(
                    text: _string(span['text']),
                    style: TextStyle(
                      color: _color(span['color']),
                      fontSize: _double(span['fontSize']),
                      fontWeight: _fontWeight(span['fontWeight']),
                      decoration: _decoration(span['decoration']),
                      fontStyle: span['italic'] == true
                          ? FontStyle.italic
                          : null,
                    ),
                  ),
            ],
          )
        : null;

    if (p['selectable'] == true) {
      // SelectableText has no overflow of its own: it scrolls what does not
      // fit, which is the only thing a selection could reach anyway.
      return spans == null
          ? SelectableText(
              content,
              maxLines: maxLines,
              textAlign: textAlign,
              style: style,
            )
          : SelectableText.rich(
              spans,
              maxLines: maxLines,
              textAlign: textAlign,
              style: style,
            );
    }
    final overflow = switch (p['overflow']) {
      'ellipsis' => TextOverflow.ellipsis,
      'clip' => TextOverflow.clip,
      _ => null,
    };
    return spans == null
        ? Text(
            content,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
            style: style,
          )
        : Text.rich(
            spans,
            maxLines: maxLines,
            overflow: overflow,
            textAlign: textAlign,
            style: style,
          );
  }

  static TextDecoration? _decoration(Object? value) => switch (value) {
    'lineThrough' => TextDecoration.lineThrough,
    'underline' => TextDecoration.underline,
    _ => null,
  };

  static TextAlign? _textAlign(Object? value) => switch (value) {
    'left' => TextAlign.left,
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    'justify' => TextAlign.justify,
    'start' => TextAlign.start,
    'end' => TextAlign.end,
    _ => null,
  };

  /// A font family and what to fall back to.
  ///
  /// 'monospace' and 'serif' are generic names, which Android resolves and
  /// iOS does not, so each comes with the faces that are that kind of font on
  /// the platforms that need telling.
  static (String?, List<String>?) _fontFamily(Object? value) =>
      switch (value) {
        'monospace' => (
          'monospace',
          const ['Menlo', 'Consolas', 'Courier New', 'Courier'],
        ),
        'serif' => ('serif', const ['Times New Roman', 'Times', 'Georgia']),
        final String family => (family, null),
        _ => (null, null),
      };

  /// An image, from the network when [src] names one and from the app's
  /// assets otherwise.
  ///
  /// A load that fails shows the alt text rather than an exception or a blank
  /// space, which is what the other renderers do too.
  /// An image, fetched and decoded by Flutter and kept in its `ImageCache` -
  /// so a rebuild draws it again without a request, and one already decoded is
  /// painted in the same frame, with nothing shown in its place first.
  ///
  /// The node's child, if it has one, is the fallback: drawn where the alt
  /// text would have been if loading fails, and while the first frame is still
  /// on its way.
  Widget _image(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) {
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

    final fallback = children.isEmpty
        ? null
        : SizedBox(
            width: width,
            height: height,
            // The alt text below is the image's name whichever of the two is
            // showing, so the stand-in is not announced as well.
            child: ExcludeSemantics(
              child: Center(child: buildNode(children.first, context)),
            ),
          );

    Widget onError(BuildContext context, Object error, StackTrace? stack) =>
        fallback ??
        SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Text(alt, style: TextStyle(color: _textSecondaryColor)),
          ),
        );

    // Only an image with a fallback has anything to show before its first
    // frame; one without stays an empty box of its size, as it always was.
    final ImageFrameBuilder? whileLoading = fallback == null
        ? null
        : (context, child, frame, wasSynchronouslyLoaded) =>
              wasSynchronouslyLoaded || frame != null ? child : fallback;

    final image =
        src.startsWith('http://') ||
            src.startsWith('https://') ||
            src.startsWith('data:')
        ? Image.network(
            src,
            width: width,
            height: height,
            fit: fit,
            frameBuilder: whileLoading,
            errorBuilder: onError,
          )
        : Image.asset(
            src,
            width: width,
            height: height,
            fit: fit,
            frameBuilder: whileLoading,
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
    final variant = _string(p['variant'], 'primary');
    final onPressed = p['disabled'] == true ? null : _tap(p);
    final stated = _color(p['color']);
    final color = stated ?? _variantColor(variant);
    final foreground = _color(p['foregroundColor']);
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

    final text = Text(_string(p['label']));
    final codepoint = _double(p['iconCodepoint'])?.toInt();
    // The glyph takes the button's foreground through its IconTheme, and its
    // size from the text it sits beside.
    final label = codepoint == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconData(codepoint), size: fontSize + 4),
              const SizedBox(width: 8),
              Flexible(child: text),
            ],
          );

    final Widget button = switch (variant) {
      // 'outlined' is Material's name for the shape 'secondary' already had;
      // what differs is the colour, which is the primary's.
      'secondary' || 'outlined' => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground ?? color,
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
      'tertiary' => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foreground ?? color,
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
      // A quiet fill of the primary, with the primary itself for the label -
      // or the fill the app stated, with text that reads over it.
      'tonal' => FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: stated ?? color.withValues(alpha: 0.12),
          foregroundColor:
              foreground ?? (stated == null ? color : _textOn(stated)),
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
          foregroundColor: foreground ?? _textOn(color),
          minimumSize: minimumSize,
          padding: padding,
          textStyle: textStyle,
        ),
        child: label,
      ),
    };
    return p['expand'] == true ? _Expand(width: true, child: button) : button;
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
      children: [checkbox, _controlLabel(label, p)],
    );
  }

  /// The text beside a checkbox, radio or switch, greyed with the control when
  /// the tree says it is disabled - Flutter dims the control itself, and a
  /// label left at full strength reads as something that can still be tapped.
  Widget _controlLabel(String label, Map<String, dynamic> p) => Text(
    label,
    style: p['disabled'] == true
        ? TextStyle(color: _textSecondaryColor.withValues(alpha: 0.6))
        : null,
  );

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
            color: disabled
                ? _textSecondaryColor.withValues(alpha: 0.6)
                : _variantColor('primary'),
          ),
          if (label != null) ...[
            const SizedBox(width: 8),
            _controlLabel(label, p),
          ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [toggle, _controlLabel(label, p)],
    );
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
  // Free-form composition
  // ---------------------------------------------------------------------------

  /// Builds with [color] as the colour text and icons take when they state
  /// none - see [_textInForce]. Null leaves whatever is in force alone.
  T _withText<T>(Color? color, T Function() build) {
    if (color == null) return build();
    final saved = _textInForce;
    _textInForce = color;
    try {
      return build();
    } finally {
      _textInForce = saved;
    }
  }

  /// A Box, and the frame of a Canvas, which carries the same props.
  ///
  /// Each prop becomes the Flutter widget that does that one thing, wrapped
  /// from the child outwards in the order the protocol describes the box:
  /// alignment and padding inside the paint, then size, then touch, and
  /// around all of it what applies to the box as a whole - opacity, transform,
  /// margin. A prop the node does not carry adds no widget.
  Widget _box(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context, {
    bool canvas = false,
  }) {
    final ms = _double(p['animateMs'])?.toInt() ?? 0;
    final duration = ms > 0 ? Duration(milliseconds: ms) : null;
    final curve = _curve(p);

    final circle = p['shape'] == 'circle';
    final fill = _color(p['color']);
    final gradient = _gradient(p['gradient']);
    final borderWidth =
        _double(p['borderWidth']) ?? (p['borderColor'] == null ? 0.0 : 1.0);
    final shadow = _shadow(p['shadow']);
    final radius = circle ? null : _radii(p);
    final clip = p['clip'] == true;
    final painted =
        fill != null ||
        gradient != null ||
        shadow != null ||
        radius != null ||
        borderWidth > 0 ||
        circle ||
        // Container only clips to a decoration, so a box that clips has one
        // even when it paints nothing.
        clip;

    // Text over a fill the app chose is made legible against it, as it is in
    // a card. A see-through fill is left alone: what the text is read against
    // is then mostly whatever lies under the box.
    final legible = fill != null && fill.a >= 0.5 ? _textOn(fill) : null;
    Widget? content = children.isEmpty
        ? null
        : _withText(legible, () => buildNode(children.first, context));
    if (canvas) {
      // Its own layer: a game sending a frame per tick repaints the surface
      // and nothing around it.
      content = RepaintBoundary(
        child: CustomPaint(
          painter: _CommandPainter(
            commands: p['commands'] is List ? p['commands'] as List : const [],
            paints: p['paints'] is List ? p['paints'] as List : const [],
            textColor: _textInForce ?? _textColor,
          ),
          child: content,
        ),
      );
    }
    final alignment = _alignment(p['alignment']);
    if (alignment != null && content != null) {
      // The factors keep a box with no size of its own hugging its child;
      // Align alone would grow to fill whatever it is offered.
      content = Align(
        alignment: alignment,
        widthFactor: 1,
        heightFactor: 1,
        child: content,
      );
    }
    final padding = _edges(p['padding']);
    if (padding != null) content = Padding(padding: padding, child: content);
    // A Container with no child grows to fill its parent, and a box with none
    // hugs nothing instead.
    content ??= const SizedBox.shrink();

    final ratio = _double(p['aspectRatio']);
    final frame = _BoxFrame(
      decoration: painted
          ? BoxDecoration(
              color: fill,
              gradient: gradient,
              border: borderWidth > 0
                  ? Border.all(
                      color: _color(p['borderColor']) ?? _dividerColor,
                      width: borderWidth,
                    )
                  : null,
              borderRadius: radius,
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
              boxShadow: shadow == null ? null : [shadow],
            )
          : null,
      clip: clip,
      constraints: _boxConstraints(p),
      aspectRatio: ratio != null && ratio > 0 && ratio.isFinite ? ratio : null,
      duration: duration,
      curve: curve,
    );

    final touched =
        p['ripple'] == true ||
        p['tapEventId'] is String ||
        p['doubleTapEventId'] is String ||
        p['longPressEventId'] is String ||
        p['panEventId'] is String;
    Widget box = touched
        ? _NodeBox(
            renderer: this,
            props: p,
            frame: frame,
            inkShape: circle
                ? const CircleBorder()
                : radius == null
                ? null
                : RoundedRectangleBorder(borderRadius: radius),
            child: content,
          )
        : frame.wrap(content);

    final sizeEventId = p['sizeEventId'];
    if (sizeEventId is String) {
      box = _SizeReporter(
        onSize: (size) => handleEvent(sizeEventId, {
          'width': size.width,
          'height': size.height,
        }),
        child: box,
      );
    }

    final dropEventId = p['dropEventId'];
    if (dropEventId is String) {
      final target = box;
      void hover(bool over) =>
          handleEvent('${dropEventId}_hover', {'over': over});
      box = DragTarget<String>(
        onWillAcceptWithDetails: (_) {
          hover(true);
          return true;
        },
        onLeave: (_) => hover(false),
        onAcceptWithDetails: (details) {
          // A drop is also the drag leaving, and Flutter says only the first.
          hover(false);
          handleEvent(dropEventId, {'data': details.data});
        },
        builder: (_, _, _) => target,
      );
    }
    final dragData = _optString(p['dragData']);
    if (dragData != null) box = _NodeDraggable(data: dragData, child: box);

    final opacity = _double(p['opacity'])?.clamp(0.0, 1.0);
    if (opacity != null) {
      box = duration == null
          ? Opacity(opacity: opacity, child: box)
          : AnimatedOpacity(
              opacity: opacity,
              duration: duration,
              curve: curve,
              child: box,
            );
    }
    final transform = _BoxTransform.from(p['transform']);
    if (transform != null) {
      box = duration == null
          ? Transform(
              transform: transform.matrix,
              alignment: Alignment.center,
              child: box,
            )
          // Each of the four numbers moves on its own, which a Matrix4 tween
          // would not do: it takes a rotation the short way round.
          : TweenAnimationBuilder<_BoxTransform>(
              tween: _BoxTransformTween(end: transform),
              duration: duration,
              curve: curve,
              builder: (_, value, child) => Transform(
                transform: value.matrix,
                alignment: Alignment.center,
                child: child,
              ),
              child: box,
            );
    }

    if (p['ignorePointer'] == true) box = IgnorePointer(child: box);
    final semanticLabel = _optString(p['semanticLabel']);
    if (semanticLabel != null) {
      box = Semantics(label: semanticLabel, container: true, child: box);
    }
    final tooltip = _optString(p['tooltip']);
    if (tooltip != null) box = Tooltip(message: tooltip, child: box);

    final margin = _edges(p['margin']);
    if (margin != null) {
      box = duration == null
          ? Padding(padding: margin, child: box)
          : AnimatedPadding(
              padding: margin,
              duration: duration,
              curve: curve,
              child: box,
            );
    }
    final expand = p['expand'];
    if (expand == 'width' || expand == 'height' || expand == 'both') {
      box = _Expand(
        width: expand != 'height',
        height: expand != 'width',
        child: box,
      );
    }
    return box;
  }

  /// The size a box states: [width]/[height] fix an axis, the min/max pairs
  /// bound it. Null when it states none, and the box then hugs its child.
  static BoxConstraints? _boxConstraints(Map<String, dynamic> p) {
    final width = _double(p['width']);
    final height = _double(p['height']);
    final minW = _double(p['minWidth']);
    final maxW = _double(p['maxWidth']);
    final minH = _double(p['minHeight']);
    final maxH = _double(p['maxHeight']);
    if ((width ?? height ?? minW ?? maxW ?? minH ?? maxH) == null) return null;
    // A minimum above its maximum is an assertion in Flutter; the minimum
    // wins, as it does in CSS.
    final minWidth = math.max(0.0, width ?? minW ?? 0);
    final minHeight = math.max(0.0, height ?? minH ?? 0);
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: math.max(minWidth, width ?? maxW ?? double.infinity),
      minHeight: minHeight,
      maxHeight: math.max(minHeight, height ?? maxH ?? double.infinity),
    );
  }

  /// `[left, top, right, bottom]`, or one number for every edge.
  static EdgeInsets? _edges(Object? value) {
    if (value is num) return EdgeInsets.all(math.max(0, value.toDouble()));
    if (value is! List || value.length != 4) return null;
    double edge(int i) => math.max(0.0, _double(value[i]) ?? 0);
    return EdgeInsets.fromLTRB(edge(0), edge(1), edge(2), edge(3));
  }

  /// An `[x, y]` pair from -1 (left/top) to 1 (right/bottom).
  static Alignment? _alignment(Object? value) {
    if (value is! List || value.length != 2) return null;
    return Alignment(_double(value[0]) ?? 0, _double(value[1]) ?? 0);
  }

  /// A box's corners: `borderRadii` as `[topLeft, topRight, bottomRight,
  /// bottomLeft]`, or `borderRadius` for all four.
  static BorderRadius? _radii(Map<String, dynamic> p) {
    final each = p['borderRadii'];
    if (each is List && each.length == 4) {
      Radius corner(int i) =>
          Radius.circular(math.max(0.0, _double(each[i]) ?? 0));
      return BorderRadius.only(
        topLeft: corner(0),
        topRight: corner(1),
        bottomRight: corner(2),
        bottomLeft: corner(3),
      );
    }
    final all = _double(p['borderRadius']);
    return all == null || all <= 0 ? null : BorderRadius.circular(all);
  }

  /// `{type, colors, stops?, begin, end}` as a Flutter gradient.
  ///
  /// A radial one is centred on `begin` and reaches `end`: the two points say
  /// where the first colour is and where the last one lands, which is what
  /// they say for a linear one too.
  static Gradient? _gradient(Object? value) {
    if (value is! Map) return null;
    final rawColors = value['colors'];
    if (rawColors is! List) return null;
    final colors = [for (final c in rawColors) ?_color(c)];
    if (colors.length != rawColors.length || colors.isEmpty) return null;
    // Flutter wants two colours; one is a flat fill said the long way.
    if (colors.length == 1) colors.add(colors.first);
    final rawStops = value['stops'];
    final stops = rawStops is List && rawStops.length == rawColors.length
        ? [for (final s in rawStops) (_double(s) ?? 0).clamp(0.0, 1.0)]
        : null;
    if (stops != null && stops.length < colors.length) stops.add(1);
    final begin = _alignment(value['begin']);
    final end = _alignment(value['end']);
    if (value['type'] == 'radial') {
      final center = begin ?? Alignment.center;
      // Alignment units span the box in two; a radius is a fraction of its
      // shorter side, so half the distance between the points.
      final reach = end == null
          ? 0.5
          : math.sqrt(
                  math.pow(end.x - center.x, 2) + math.pow(end.y - center.y, 2),
                ) /
                2;
      return RadialGradient(
        center: center,
        radius: reach > 0 ? reach : 0.5,
        colors: colors,
        stops: stops,
      );
    }
    return LinearGradient(
      begin: begin ?? Alignment.centerLeft,
      end: end ?? Alignment.centerRight,
      colors: colors,
      stops: stops,
    );
  }

  /// `{color, blur, dx, dy}` as a shadow.
  static BoxShadow? _shadow(Object? value) {
    if (value is! Map) return null;
    return BoxShadow(
      color: _color(value['color']) ?? const Color(0x33000000),
      blurRadius: math.max(0.0, _double(value['blur']) ?? 0),
      offset: Offset(_double(value['dx']) ?? 0, _double(value['dy']) ?? 0),
    );
  }

  /// Children drawn over one another. A `Positioned` child is pinned here,
  /// where its parent data can reach the Stack; met anywhere else it is just
  /// its child.
  Widget _stack(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) => Stack(
    // Stated, it names a side; unstated it is Flutter's own default, the top
    // *start*, which follows the reading direction.
    alignment: _alignment(p['alignment']) ?? AlignmentDirectional.topStart,
    fit: p['fit'] == 'expand' ? StackFit.expand : StackFit.loose,
    clipBehavior: p['clip'] == false ? Clip.none : Clip.hardEdge,
    children: [
      for (final child in children)
        if (child.type == 'Positioned')
          _positioned(child, context)
        else
          buildNode(child, context),
    ],
  );

  Widget _positioned(WidgetNode node, BuildContext context) {
    final p = node.props;
    final left = _double(p['left']);
    final top = _double(p['top']);
    final right = _double(p['right']);
    final bottom = _double(p['bottom']);
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      // Two opposite edges already say how wide the child is; a width as well
      // would be an assertion, so the edges win.
      width: left != null && right != null ? null : _double(p['width']),
      height: top != null && bottom != null ? null : _double(p['height']),
      child: _single(node.children ?? const [], context),
    );
  }

  /// One glyph of an icon font.
  ///
  /// The codepoint only exists at run time, so the [IconData] cannot be a
  /// constant - and Flutter's release build strips an icon font down to the
  /// constants it can see. An app that builds `Icon` nodes ships with
  /// `--no-tree-shake-icons`; the build says so itself rather than dropping
  /// glyphs quietly.
  static IconData _iconData(int codepoint, [String? fontFamily]) =>
      // ignore: non_const_argument_for_const_parameter
      IconData(codepoint, fontFamily: fontFamily ?? 'MaterialIcons');

  /// The icon a button node asks for: the named one where the name is known,
  /// else the glyph at its codepoint, else a dot - visible, not absent.
  static IconData _iconOf(Map<String, dynamic> p, String fallback) {
    final name = _optString(p['icon']);
    final named = _icons[name];
    if (named != null) return named;
    final codepoint = _double(p['iconCodepoint'])?.toInt();
    if (codepoint != null) return _iconData(codepoint);
    return name == null ? _icon(fallback) : Icons.circle;
  }

  Widget _iconNode(Map<String, dynamic> p) => Icon(
    _iconData(
      (_double(p['codepoint']) ?? 0).toInt(),
      _optString(p['fontFamily']),
    ),
    size: _double(p['size']),
    // No colour of its own: the colour in force over a fill the app chose,
    // and otherwise the IconTheme's - an app bar's foreground, a button's.
    color: _color(p['color']) ?? _textInForce,
    semanticLabel: _optString(p['semanticLabel']),
  );

  Widget _iconButton(Map<String, dynamic> p) => Tooltip(
    message: _string(p['tooltip']),
    child: IconButton(
      icon: Icon(_iconOf(p, 'more_vert')),
      color: _color(p['color']) ?? _textInForce,
      iconSize: _double(p['size']),
      onPressed: p['disabled'] == true ? null : _tap(p),
    ),
  );

  Widget _fab(Map<String, dynamic> p) {
    // With a brand theme, the FAB matches the other renderers' primary;
    // with none, Flutter's own Material 3 default is left to shine.
    final themed = theme != AppTheme.fallback;
    final background =
        _color(p['backgroundColor']) ?? (themed ? _primaryColor : null);
    final foreground = themed ? _onPrimaryColor : null;
    final icon = Icon(_iconOf(p, 'add'));
    final label = _optString(p['label']);
    if (label != null) {
      return FloatingActionButton.extended(
        tooltip: _optString(p['tooltip']),
        onPressed: _tap(p),
        backgroundColor: background,
        foregroundColor: foreground,
        icon: icon,
        label: Text(label),
      );
    }
    return FloatingActionButton(
      tooltip: _optString(p['tooltip']),
      onPressed: _tap(p),
      backgroundColor: background,
      foregroundColor: foreground,
      child: icon,
    );
  }

  /// One of a list, chosen from Material's menu.
  ///
  /// A DropdownButton inside an InputDecorator - which is what Flutter's own
  /// DropdownButtonFormField is made of - rather than the form field itself:
  /// the form field keeps the selection in its State, and here the selection
  /// is the tree's.
  Widget _dropdown(Map<String, dynamic> p) {
    final items = [for (final item in (p['items'] as List? ?? const [])) '$item'];
    final index = _double(p['selectedIndex'])?.toInt();
    // An index outside the list is no selection, not an assertion.
    final selected = index != null && index >= 0 && index < items.length
        ? index
        : null;
    final enabled = p['enabled'] != false;
    return InputDecorator(
      isEmpty: selected == null,
      decoration: InputDecoration(
        labelText: _optString(p['label']),
        hintText: _optString(p['hint']),
        errorText: _optString(p['error']),
        enabled: enabled,
        border: p['outlined'] == false
            ? const UnderlineInputBorder()
            : const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selected,
          isExpanded: true,
          isDense: true,
          items: [
            for (final (i, item) in items.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: enabled
              ? (i) {
                  if (i != null) _emit(p, {'index': i});
                }
              : null,
        ),
      ),
    );
  }

  /// The destinations of an app: a NavigationBar, or a NavigationRail down
  /// the leading edge when the node asks for one.
  Widget _bottomNavigation(Map<String, dynamic> p) {
    final items = [
      for (final item in (p['items'] as List? ?? const []))
        if (item is Map) item,
    ];
    // Both of Flutter's widgets assert on fewer than two destinations, and a
    // navigation between one place is no navigation.
    if (items.length < 2) return const SizedBox.shrink();
    final selected = (_double(p['selectedIndex']) ?? 0).toInt().clamp(
      0,
      items.length - 1,
    );
    Icon icon(Map item, {bool selected = false}) => Icon(
      _iconData(
        (_double(selected ? item['selectedIcon'] ?? item['icon'] : item['icon']) ??
                0)
            .toInt(),
      ),
    );
    void select(int index) => _emit(p, {'index': index});

    if (p['rail'] != true) {
      return NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: select,
        destinations: [
          for (final item in items)
            NavigationDestination(
              icon: icon(item),
              selectedIcon: icon(item, selected: true),
              label: _string(item['label']),
            ),
        ],
      );
    }
    final rail = NavigationRail(
      selectedIndex: selected,
      onDestinationSelected: select,
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final item in items)
          NavigationRailDestination(
            icon: icon(item),
            selectedIcon: icon(item, selected: true),
            label: Text(_string(item['label'])),
          ),
      ],
    );
    // A rail fills the height it is given and has none of its own, so where
    // the height is unbounded - a scrolling body - it gets its destinations'.
    // Where it is bounded, the rail scrolls once its destinations are taller
    // than the room - seven of them on a phone held sideways - and is the
    // full height otherwise, which is the arrangement Flutter documents for
    // a rail in a scroll view.
    return LayoutBuilder(
      builder: (_, constraints) => constraints.hasBoundedHeight
          ? SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: rail),
              ),
            )
          : SizedBox(height: items.length * 72.0 + 16, child: rail),
    );
  }

  /// The widget registered for a slot, at the slot's size; the fallback child
  /// when nothing is registered under that id.
  Widget _flutterSlot(
    Map<String, dynamic> p,
    List<WidgetNode> children,
    BuildContext context,
  ) {
    final slotId = _string(p['slotId']);
    final builder = FlutterSlots.instance.builderOf(slotId);
    final width = _double(p['width']);
    final slot = SizedBox(
      width: width,
      height: _double(p['height']),
      child: builder is Widget Function(BuildContext)
          // Keyed by the slot, like the layer the native renderers use, so
          // the widget keeps its State when the nodes around it change.
          ? KeyedSubtree(
              key: ValueKey<String>('flutterSlot:$slotId'),
              child: Builder(builder: builder),
            )
          : _single(children, context),
    );
    // No width means the width it is offered.
    return width == null ? _Expand(width: true, child: slot) : slot;
  }

  /// A lazy list or scroller applies a `scrollOffset` once per
  /// `scrollVersion`; this says whether [version] is new for [id], and
  /// records it. Kept here because a list's State can be rebuilt while the
  /// list, and where it is scrolled to, stays.
  bool _takeScrollVersion(String id, int? version) {
    if (_appliedScrollVersions.containsKey(id) &&
        _appliedScrollVersions[id] == version) {
      return false;
    }
    _appliedScrollVersions[id] = version;
    return true;
  }

  /// Whether the app registered a handler for [eventId].
  ///
  /// The renderer's own events ([RendererEvents]) are only sent to an app that
  /// asked for them: nobody listening is the ordinary case, not an error.
  bool handles(String eventId) => _handlers.containsKey(eventId);

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
    100 => FontWeight.w100,
    200 => FontWeight.w200,
    300 => FontWeight.w300,
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    700 => FontWeight.w700,
    800 => FontWeight.w800,
    900 => FontWeight.w900,
    _ => null,
  };

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

  /// Parses `#rgb`, `#rrggbb` and `#aarrggbb`. Every colour in a tree comes
  /// through here, so each of them may carry an alpha.
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
    'spaceAround' => MainAxisAlignment.spaceAround,
    'spaceEvenly' => MainAxisAlignment.spaceEvenly,
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

  /// The Material Icons glyph at a codepoint prop, or null when there is none.
  static Icon? _glyph(Object? codepoint) => codepoint is num
      ? Icon(FlutterUIRenderer._iconData(codepoint.toInt()))
      : null;

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
      keyboardType: switch (p['keyboardType']) {
        'number' => TextInputType.number,
        'decimal' => const TextInputType.numberWithOptions(decimal: true),
        'email' => TextInputType.emailAddress,
        'phone' => TextInputType.phone,
        'url' => TextInputType.url,
        'multiline' => TextInputType.multiline,
        // Null lets Flutter choose from maxLines, as it did before.
        _ => null,
      },
      // Shows its value and takes focus but not typing: a field that opens a
      // picker, which is what the tap event is for.
      readOnly: p['readOnly'] == true,
      onTap: p['tappable'] == true
          ? () => widget.renderer.handleEvent('${_eventId}_tap', const {})
          : null,
      maxLength: FlutterUIRenderer._double(p['maxLength'])?.toInt(),
      textCapitalization: switch (p['textCapitalization']) {
        'words' => TextCapitalization.words,
        'sentences' => TextCapitalization.sentences,
        'characters' => TextCapitalization.characters,
        _ => TextCapitalization.none,
      },
      textAlign: FlutterUIRenderer._textAlign(p['textAlign']) ?? TextAlign.start,
      decoration: InputDecoration(
        hintText: FlutterUIRenderer._optString(p['hint'] ?? p['placeholder']),
        labelText: floating ? label : null,
        errorText: FlutterUIRenderer._optString(p['error']),
        helperText: FlutterUIRenderer._optString(p['helper']),
        prefixIcon: _glyph(p['prefixIcon']),
        suffixIcon: switch (_glyph(p['suffixIcon'])) {
          // A glyph the app listens to is a button - a clear, a show-password;
          // one it does not is decoration.
          final Icon icon when p['suffixTappable'] == true => IconButton(
            icon: icon,
            onPressed: () =>
                widget.renderer.handleEvent('${_eventId}_suffix', const {}),
          ),
          final icon => icon,
        },
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
        // The bar marks where the message starts, so it changes sides with
        // the reading direction.
        border: BorderDirectional(start: BorderSide(color: color, width: 4)),
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
        child: ValueListenableBuilder(
          valueListenable: widget.renderer._bottomTaken,
          // Above the bottom bar and the floating button, not over them, as
          // Material has it: lifted by however far they reach past where the
          // snackbar would otherwise end.
          builder: (context, taken, child) {
            final reach = math.max(taken.bar, taken.fab);
            final own = 16 + MediaQuery.paddingOf(context).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                reach == 0 ? 16 : 16 + math.max(0, reach + 8 - own),
              ),
              child: child,
            );
          },
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              color: FlutterUIRenderer._color(inverse.surface) ??
                  const Color(0xff323232),
              elevation: 6,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
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

/// Reports how far up from the bottom of the scaffold it is in its child
/// reaches - the bottom bar's height, or the floating button's top edge.
class _FromBottom extends SingleChildRenderObjectWidget {
  const _FromBottom({required this.onChanged, super.child});

  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFromBottom(onChanged);

  @override
  void updateRenderObject(BuildContext context, _RenderFromBottom renderObject) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderFromBottom extends RenderProxyBox {
  _RenderFromBottom(this.onChanged);

  ValueChanged<double> onChanged;
  double? _reported;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // The scaffold lays its parts out in one box; that box is the frame.
    RenderObject? frame = parent;
    while (frame != null && frame is! RenderCustomMultiChildLayoutBox) {
      frame = frame.parent;
    }
    if (frame is! RenderBox || !frame.hasSize) return;
    final taken =
        frame.size.height - localToGlobal(Offset.zero, ancestor: frame).dy;
    if (taken == _reported) return;
    _reported = taken;
    // Not now: whoever listens rebuilds, and this is the middle of a frame.
    SchedulerBinding.instance.addPostFrameCallback((_) => onChanged(taken));
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

  /// Moves the list to [offset]: where it starts, when it is not on screen
  /// yet, and a jump once the frame is laid out when it is - by then the rows
  /// that came with the ask are there, and the offset can be held to them.
  void moveTo(double offset) {
    _lastOffset = math.max(0, offset);
    if (!hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!hasClients) return;
      final position = positions.last;
      jumpTo(offset.clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }
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
    _applyScrollRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(_NodeLazyList old) {
    super.didUpdateWidget(old);
    _applyScrollRequest();
  }

  /// Moves to `scrollOffset` the first time the list is drawn with one, and
  /// again whenever `scrollVersion` is one not yet obeyed.
  void _applyScrollRequest() {
    final offset = FlutterUIRenderer._double(widget.props['scrollOffset']);
    if (offset == null) return;
    final version = FlutterUIRenderer._double(
      widget.props['scrollVersion'],
    )?.toInt();
    if (widget.renderer._takeScrollVersion(_listId, version)) {
      _controller.moveTo(offset);
    }
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

class NativeUIAppHostState extends State<NativeUIAppHost>
    with WidgetsBindingObserver {
  late final FlutterUIRenderer renderer;

  /// The viewport and the lifecycle state last sent, so each is sent when it
  /// changes rather than on every build.
  String? _sentViewport;
  String? _sentLifecycle;

  /// The route the host is on, when it is on one: a host under another
  /// screen does not report the keys pressed on the screen above it.
  ModalRoute<Object?>? _route;

  @override
  void initState() {
    super.initState();
    renderer = FlutterUIRenderer(onTreeChanged: _rebuild, theme: widget.theme);
    widget.app.mount(renderer);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
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

  // ---------------------------------------------------------------------------
  // The renderer's own events - see [RendererEvents]. Each is sent only to an
  // app that registered for it: most apps listen to none of them, and an event
  // with no handler is otherwise reported as a failure.
  // ---------------------------------------------------------------------------

  /// Sends [RendererEvents.viewport] once the size is known, and again when
  /// anything it carries changes. Called from build, which a `MediaQuery`
  /// change and a change of the host's own constraints both run.
  void _reportViewport(BuildContext context, BoxConstraints constraints) {
    if (!renderer.handles(RendererEvents.viewport)) return;
    final media = MediaQuery.of(context);
    // The room the host was given, which inside another app's layout is not
    // the whole screen; the screen where the host is not bounded.
    final size = Size(
      constraints.hasBoundedWidth ? constraints.maxWidth : media.size.width,
      constraints.hasBoundedHeight ? constraints.maxHeight : media.size.height,
    );
    final viewport = <String, dynamic>{
      'width': size.width,
      'height': size.height,
      'paddingTop': media.padding.top,
      'paddingBottom': media.padding.bottom,
      'paddingLeft': media.padding.left,
      'paddingRight': media.padding.right,
      'keyboardInset': media.viewInsets.bottom,
      'devicePixelRatio': media.devicePixelRatio,
      'textScale': media.textScaler.scale(1),
      'dark': media.platformBrightness == Brightness.dark,
    };
    final signature = viewport.values.join('|');
    if (signature == _sentViewport) return;
    // After the frame: the app re-renders in answer, and this is a build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || signature == _sentViewport) return;
      _sentViewport = signature;
      renderer.handleEvent(RendererEvents.viewport, viewport);
    });
  }

  /// Sends [RendererEvents.key] for a hardware key going down or coming up.
  ///
  /// Answers false - "not handled" - every time: the app hears about the key,
  /// and the text field or shortcut it was meant for still gets it.
  bool _onKey(KeyEvent event) {
    if (!mounted ||
        !renderer.handles(RendererEvents.key) ||
        _route?.isCurrent == false) {
      return false;
    }
    renderer.handleEvent(RendererEvents.key, {
      'key': _keyName(event),
      'down': event is! KeyUpEvent,
      if (event is KeyRepeatEvent) 'repeat': true,
    });
    return false;
  }

  /// The key's name as a browser's `KeyboardEvent.key` spells it: the
  /// character for a key that types one ('a', 'A', ' '), and a name for one
  /// that does not ('Enter', 'ArrowUp', 'Shift').
  static String _keyName(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) return ' ';
    if (key == LogicalKeyboardKey.numpadEnter) return 'Enter';
    final label = key.keyLabel;
    if (label.length == 1) {
      // A key-up carries no character, so the case comes from Shift; a
      // key-down's character already has it, and the layout's own symbols.
      final character = event.character;
      if (character != null && character.length == 1) return character;
      return HardwareKeyboard.instance.isShiftPressed
          ? label
          : label.toLowerCase();
    }
    // Flutter's labels are the browser's names with spaces in them ('Arrow
    // Up', 'Page Down'), plus a side for the modifiers, which the browser
    // leaves to `code`.
    return label
        .replaceFirst(RegExp(r' (Left|Right)$'), '')
        .replaceFirst(RegExp(r'^Numpad '), '')
        .replaceAll(' ', '');
  }

  /// Sends [RendererEvents.lifecycle] as the app comes and goes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!renderer.handles(RendererEvents.lifecycle)) return;
    final name = switch (state) {
      AppLifecycleState.resumed => 'resumed',
      AppLifecycleState.inactive => 'inactive',
      // Flutter's 'hidden' sits between inactive and paused and the protocol
      // has no word for it; to an app, not being shown is being paused.
      AppLifecycleState.hidden || AppLifecycleState.paused => 'paused',
      AppLifecycleState.detached => 'detached',
    };
    if (name == _sentLifecycle) return;
    _sentLifecycle = name;
    renderer.handleEvent(RendererEvents.lifecycle, {'state': name});
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _reportViewport(context, constraints);
      return renderer.build(context);
    },
  );
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

  /// How far the child is slid towards the end of the row; 0 is closed,
  /// negative reveals the trailing actions and positive the leading ones.
  ///
  /// Towards the end, not to the left: the two bars are rows, which change
  /// sides with the reading direction, so the finger and the transform -
  /// which are in screen coordinates - are turned to match in [build]. Left
  /// as they were, a swipe in a right-to-left screen slid the row over the
  /// bar it meant to show and fired the other one's action.
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
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
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
            offset: Offset(_offset * sign, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(
                () => _offset = (_offset + d.delta.dx * sign)
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

// -----------------------------------------------------------------------------
// Boxes
// -----------------------------------------------------------------------------

/// The paint and the size of a box, around whatever is inside it.
///
/// Separate from the box's touch handling because a ripple has to be drawn
/// *inside* the paint - over the fill, under the child - while the gestures
/// are measured around it.
class _BoxFrame {
  const _BoxFrame({
    required this.decoration,
    required this.clip,
    required this.constraints,
    required this.aspectRatio,
    required this.duration,
    required this.curve,
  });

  final BoxDecoration? decoration;
  final bool clip;
  final BoxConstraints? constraints;
  final double? aspectRatio;

  /// How long a change takes to land; null for at once.
  final Duration? duration;
  final Curve curve;

  Widget wrap(Widget child) {
    final duration = this.duration;
    final ratio = aspectRatio;
    // With an aspect ratio the stated size bounds the ratio's box rather than
    // the painted one, so the ratio decides the axis the size left free.
    final own = ratio == null ? constraints : null;
    final clipBehavior = clip ? Clip.antiAlias : Clip.none;
    Widget box = duration == null
        ? Container(
            constraints: own,
            decoration: decoration,
            clipBehavior: clipBehavior,
            child: child,
          )
        : AnimatedContainer(
            duration: duration,
            curve: curve,
            constraints: own,
            decoration: decoration,
            clipBehavior: clipBehavior,
            child: child,
          );
    if (ratio == null) return box;
    box = AspectRatio(aspectRatio: ratio, child: box);
    final outer = constraints;
    if (outer == null) return box;
    return duration == null
        ? ConstrainedBox(constraints: outer, child: box)
        : AnimatedContainer(
            duration: duration,
            curve: curve,
            constraints: outer,
            child: box,
          );
  }
}

/// A box's `{rotate, scale, dx, dy}`, applied about its centre.
class _BoxTransform {
  const _BoxTransform(this.rotate, this.scale, this.dx, this.dy);

  static _BoxTransform? from(Object? value) {
    if (value is! Map) return null;
    double read(String key, double fallback) =>
        FlutterUIRenderer._double(value[key]) ?? fallback;
    return _BoxTransform(
      read('rotate', 0),
      read('scale', 1),
      read('dx', 0),
      read('dy', 0),
    );
  }

  final double rotate;
  final double scale;
  final double dx;
  final double dy;

  /// Scaled, then turned, then moved - so `dx`/`dy` are screen pixels
  /// whatever the scale and the angle.
  Matrix4 get matrix => Matrix4.translationValues(dx, dy, 0)
    ..multiply(Matrix4.rotationZ(rotate))
    ..multiply(Matrix4.diagonal3Values(scale, scale, 1));
}

class _BoxTransformTween extends Tween<_BoxTransform> {
  _BoxTransformTween({super.end});

  @override
  _BoxTransform lerp(double t) {
    final a = begin!;
    final b = end!;
    double mix(double from, double to) => from + (to - from) * t;
    return _BoxTransform(
      mix(a.rotate, b.rotate),
      mix(a.scale, b.scale),
      mix(a.dx, b.dx),
      mix(a.dy, b.dy),
    );
  }
}

/// A box that is touched: taps, a pan, a ripple.
///
/// Stateful for two reasons. A position is reported in the box's own pixels,
/// which means converting it with the box's render object; and a pan reports
/// how far it moved since the last event, which someone has to remember.
class _NodeBox extends StatefulWidget {
  const _NodeBox({
    required this.renderer,
    required this.props,
    required this.frame,
    required this.inkShape,
    required this.child,
  });

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;
  final _BoxFrame frame;

  /// The shape a ripple is clipped to: the box's own.
  final ShapeBorder? inkShape;
  final Widget child;

  @override
  State<_NodeBox> createState() => _NodeBoxState();
}

class _NodeBoxState extends State<_NodeBox> {
  /// Where the pointer last went down, in global coordinates. A double tap
  /// and a long press, and every callback of an InkWell, arrive without a
  /// position; this is the one they happened at.
  Offset? _down;

  /// Where a pan was at its last event, in the box's coordinates.
  Offset _pan = Offset.zero;

  String? _id(String key) => FlutterUIRenderer._optString(widget.props[key]);

  /// [global] in the box's own logical pixels - through the box's transform,
  /// if it has one, so a rotated box still reports where *it* was touched.
  Offset _local(Offset? global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Offset.zero;
    return global == null
        ? box.size.center(Offset.zero)
        : box.globalToLocal(global);
  }

  void _point(String? eventId, Offset? global) {
    if (eventId == null) return;
    final at = _local(global);
    widget.renderer.handleEvent(eventId, {'x': at.dx, 'y': at.dy});
  }

  void _panned(String phase, Offset? global, {Offset velocity = Offset.zero}) {
    final eventId = _id('panEventId');
    if (eventId == null) return;
    // The end of a pan has no position of its own; it ends where it last was.
    final at = global == null ? _pan : _local(global);
    final moved = phase == '_update' ? at - _pan : Offset.zero;
    _pan = at;
    widget.renderer.handleEvent('$eventId$phase', {
      'x': at.dx,
      'y': at.dy,
      'dx': moved.dx,
      'dy': moved.dy,
      'vx': velocity.dx,
      'vy': velocity.dy,
    });
  }

  @override
  Widget build(BuildContext context) {
    final tap = _id('tapEventId');
    final doubleTap = _id('doubleTapEventId');
    final longPress = _id('longPressEventId');
    final pan = _id('panEventId');
    final ripple = widget.props['ripple'] == true;

    var content = widget.child;
    if (ripple) {
      // The Material is inside the box's paint, so the splash lands on the
      // fill rather than under it; the InkWell then has to be the one that
      // hears the taps, or the splash would never start.
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: widget.inkShape,
          onTapDown: (details) => _down = details.globalPosition,
          onTapUp: (details) => _down = details.globalPosition,
          onTap: () => _point(tap, _down),
          onDoubleTap: doubleTap == null
              ? null
              : () => _point(doubleTap, _down),
          onLongPress: longPress == null
              ? null
              : () => _point(longPress, _down),
          child: content,
        ),
      );
    }
    final box = widget.frame.wrap(content);
    final tapsHere = !ripple;
    if (ripple && pan == null) return box;
    return GestureDetector(
      // A box takes touches over all of itself, painted or not.
      behavior: HitTestBehavior.opaque,
      onTapUp: tapsHere && tap != null
          ? (details) => _point(tap, details.globalPosition)
          : null,
      onDoubleTapDown: tapsHere && doubleTap != null
          ? (details) => _down = details.globalPosition
          : null,
      onDoubleTap: tapsHere && doubleTap != null
          ? () => _point(doubleTap, _down)
          : null,
      onLongPressStart: tapsHere && longPress != null
          ? (details) => _point(longPress, details.globalPosition)
          : null,
      onPanStart: pan == null
          ? null
          : (details) => _panned('_start', details.globalPosition),
      onPanUpdate: pan == null
          ? null
          : (details) => _panned('_update', details.globalPosition),
      onPanEnd: pan == null
          ? null
          : (details) => _panned(
              '_end',
              null,
              velocity: details.velocity.pixelsPerSecond,
            ),
      child: box,
    );
  }
}

/// A box that can be picked up, carrying a string.
///
/// After a long press where the pointer is a finger, so a drag can still
/// scroll the list the box is in; at once where it is a mouse, which has a
/// wheel for that.
class _NodeDraggable extends StatefulWidget {
  const _NodeDraggable({required this.data, required this.child});

  final String data;
  final Widget child;

  @override
  State<_NodeDraggable> createState() => _NodeDraggableState();
}

class _NodeDraggableState extends State<_NodeDraggable> {
  /// The box's size when the pointer went down. What follows the pointer is
  /// built in the app's overlay, where nothing would give it a size.
  Size? _size;

  static bool get _touch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.fuchsia);

  @override
  Widget build(BuildContext context) {
    final feedback = Builder(
      builder: (_) => Opacity(
        opacity: 0.85,
        child: SizedBox.fromSize(
          size: _size,
          child: Material(
            type: MaterialType.transparency,
            child: widget.child,
          ),
        ),
      ),
    );
    return Listener(
      onPointerDown: (_) => _size = context.size,
      child: _touch
          ? LongPressDraggable<String>(
              data: widget.data,
              feedback: feedback,
              child: widget.child,
            )
          : Draggable<String>(
              data: widget.data,
              feedback: feedback,
              child: widget.child,
            ),
    );
  }
}

/// Reports its child's size once it is laid out, and again when it changes.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;

  /// The size last sent. A layout that arrives at the same size - and most
  /// re-renders do - sends nothing.
  Size? _reported;
  bool _scheduled = false;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported || _scheduled) return;
    _scheduled = true;
    // After the frame: the app re-renders in answer, which it may not do in
    // the middle of a layout.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!attached || !hasSize || size == _reported) return;
      _reported = size;
      onSize(size);
    });
  }
}

/// Makes its child fill what the parent offers on an axis - where the parent
/// offers something. In an unbounded parent (a row's main axis, a scroller's)
/// there is nothing to fill and the child keeps its own size, where
/// `double.infinity` would be a layout error.
class _Expand extends SingleChildRenderObjectWidget {
  const _Expand({this.width = false, this.height = false, super.child});

  final bool width;
  final bool height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderExpand(width, height);

  @override
  void updateRenderObject(BuildContext context, _RenderExpand renderObject) =>
      renderObject
        ..width = width
        ..height = height;
}

class _RenderExpand extends RenderProxyBox {
  _RenderExpand(this._width, this._height);

  bool _width;
  set width(bool value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  bool _height;
  set height(bool value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  BoxConstraints _filled(BoxConstraints from) => from.copyWith(
    minWidth: _width && from.hasBoundedWidth ? from.maxWidth : null,
    minHeight: _height && from.hasBoundedHeight ? from.maxHeight : null,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = _filled(constraints);
    return child?.getDryLayout(inner) ?? inner.smallest;
  }

  @override
  void performLayout() {
    final inner = _filled(constraints);
    final child = this.child;
    if (child == null) {
      size = inner.smallest;
      return;
    }
    child.layout(inner, parentUsesSize: true);
    size = child.size;
  }
}

// -----------------------------------------------------------------------------
// Canvas
// -----------------------------------------------------------------------------

/// Replays a Canvas node's command list - see [UIBuilder.canvas], which is
/// the specification this follows command by command.
///
/// A command it cannot make sense of - an unknown name, an argument missing -
/// is skipped, so one bad command costs that shape and not the frame.
class _CommandPainter extends CustomPainter {
  _CommandPainter({
    required this.commands,
    required this.paints,
    required this.textColor,
  });

  final List<Object?> commands;
  final List<Object?> paints;

  /// What `text` is drawn in when the command names no colour.
  final Color textColor;

  /// The paints, converted once per frame of commands rather than once per
  /// command that uses them.
  late final List<Paint> _paints = [for (final paint in paints) _paint(paint)];

  static double _n(List<Object?> args, int index, [double fallback = 0]) =>
      index < args.length
      ? FlutterUIRenderer._double(args[index]) ?? fallback
      : fallback;

  static Rect _rect(List<Object?> args, int at) =>
      Rect.fromLTWH(_n(args, at), _n(args, at + 1), _n(args, at + 2), _n(args, at + 3));

  Paint _paint(Object? spec) {
    final paint = Paint()..isAntiAlias = true;
    if (spec is! Map) return paint..color = textColor;
    return paint
      ..color = FlutterUIRenderer._color(spec['color']) ?? textColor
      ..style = spec['style'] == 'stroke'
          ? PaintingStyle.stroke
          : PaintingStyle.fill
      ..strokeWidth = FlutterUIRenderer._double(spec['strokeWidth']) ?? 1
      ..strokeCap = switch (spec['cap']) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        _ => StrokeCap.butt,
      }
      ..strokeJoin = switch (spec['join']) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        _ => StrokeJoin.miter,
      };
  }

  /// The paint a command names: `p` is the index at [at] of its arguments. One
  /// that names none, or one that is not there, is a plain fill.
  Paint _paintAt(List<Object?> args, int at) {
    final index = at < args.length ? args[at] : null;
    if (index is num && index >= 0 && index < _paints.length) {
      return _paints[index.toInt()];
    }
    return Paint()
      ..isAntiAlias = true
      ..color = textColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = canvas.getSaveCount();
    canvas.save();
    // The surface ends at its edges, as a platform canvas does.
    canvas.clipRect(Offset.zero & size);
    final floor = canvas.getSaveCount();
    for (final command in commands) {
      if (command is! List || command.isEmpty) continue;
      _draw(canvas, command, floor);
    }
    // Whatever the commands saved and never restored ends with the frame.
    canvas.restoreToCount(base);
  }

  void _draw(Canvas canvas, List<Object?> c, int floor) {
    switch (c.first) {
      case 'rect':
        canvas.drawRect(_rect(c, 1), _paintAt(c, 5));
      case 'rrect':
        canvas.drawRRect(
          RRect.fromRectAndRadius(_rect(c, 1), Radius.circular(_n(c, 5))),
          _paintAt(c, 6),
        );
      case 'circle':
        canvas.drawCircle(Offset(_n(c, 1), _n(c, 2)), _n(c, 3), _paintAt(c, 4));
      case 'oval':
        canvas.drawOval(_rect(c, 1), _paintAt(c, 5));
      case 'line':
        canvas.drawLine(
          Offset(_n(c, 1), _n(c, 2)),
          Offset(_n(c, 3), _n(c, 4)),
          _paintAt(c, 5),
        );
      case 'arc':
        canvas.drawArc(
          _rect(c, 1),
          _n(c, 5),
          _n(c, 6),
          c.length > 7 && c[7] == true,
          _paintAt(c, 8),
        );
      case 'path':
        final segments = c.length > 1 ? c[1] : null;
        if (segments is List) canvas.drawPath(_path(segments), _paintAt(c, 2));
      case 'text':
        _text(canvas, c);
      case 'save':
        canvas.save();
      case 'restore':
        // A restore with no save to match would undo the surface's own clip.
        if (canvas.getSaveCount() > floor) canvas.restore();
      case 'translate':
        canvas.translate(_n(c, 1), _n(c, 2));
      case 'rotate':
        canvas.rotate(_n(c, 1));
      case 'scale':
        final sx = _n(c, 1, 1);
        canvas.scale(sx, _n(c, 2, sx));
      case 'clipRect':
        canvas.clipRect(_rect(c, 1));
      case 'clipRRect':
        canvas.clipRRect(
          RRect.fromRectAndRadius(_rect(c, 1), Radius.circular(_n(c, 5))),
        );
    }
  }

  static Path _path(List<Object?> segments) {
    final path = Path();
    for (final s in segments) {
      if (s is! List || s.isEmpty) continue;
      switch (s.first) {
        case 'M':
          path.moveTo(_n(s, 1), _n(s, 2));
        case 'L':
          path.lineTo(_n(s, 1), _n(s, 2));
        case 'Q':
          path.quadraticBezierTo(_n(s, 1), _n(s, 2), _n(s, 3), _n(s, 4));
        case 'C':
          path.cubicTo(
            _n(s, 1),
            _n(s, 2),
            _n(s, 3),
            _n(s, 4),
            _n(s, 5),
            _n(s, 6),
          );
        case 'A':
          // Joined to the path with a line, not started afresh.
          path.arcTo(_rect(s, 1), _n(s, 5), _n(s, 6), false);
        case 'R':
          path.addRect(_rect(s, 1));
        case 'O':
          path.addOval(_rect(s, 1));
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  /// `text`: drawn from its top-left corner at (x, y). `align` is relative to
  /// `maxWidth` when there is one - the text is laid out in a box that wide,
  /// starting at x - and otherwise to x itself: centred on it, or ending at
  /// it.
  void _text(Canvas canvas, List<Object?> c) {
    if (c.length < 4) return;
    final options = c.length > 4 && c[4] is Map ? c[4] as Map : const {};
    final maxWidth = FlutterUIRenderer._double(options['maxWidth']);
    final align = options['align'];
    final family = FlutterUIRenderer._fontFamily(options['family']);
    final painter = TextPainter(
      text: TextSpan(
        text: '${c[1] ?? ''}',
        style: TextStyle(
          fontSize: FlutterUIRenderer._double(options['size']) ?? 14,
          color: FlutterUIRenderer._color(options['color']) ?? textColor,
          fontWeight: FlutterUIRenderer._fontWeight(options['weight']),
          fontFamily: family.$1,
          fontFamilyFallback: family.$2,
        ),
      ),
      // Coordinates are from the left whatever the locale, so the text is
      // laid out that way too.
      textDirection: TextDirection.ltr,
      textAlign: switch (align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => TextAlign.left,
      },
    );
    if (maxWidth != null && maxWidth > 0) {
      painter.layout(minWidth: maxWidth, maxWidth: maxWidth);
    } else {
      painter.layout();
    }
    final x = _n(c, 2);
    final left = maxWidth != null && maxWidth > 0
        ? x
        : switch (align) {
            'center' => x - painter.width / 2,
            'right' => x - painter.width,
            _ => x,
          };
    painter.paint(canvas, Offset(left, _n(c, 3)));
    painter.dispose();
  }

  // A render makes a new tree, and with it new lists: the same lists mean
  // the same picture, and anything else is repainted. Comparing them element
  // by element would cost a frame's worth of work to save one.
  @override
  bool shouldRepaint(_CommandPainter old) =>
      !identical(old.commands, commands) ||
      !identical(old.paints, paints) ||
      old.textColor != textColor;
}

// -----------------------------------------------------------------------------
// Scrolling
// -----------------------------------------------------------------------------

/// A scroller, which keeps its offset while the app re-renders around it and
/// runs the pull-to-refresh spinner for as long as the tree says.
class _NodeScroll extends StatefulWidget {
  const _NodeScroll({
    super.key,
    required this.renderer,
    required this.props,
    required this.child,
  });

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;
  final Widget child;

  @override
  State<_NodeScroll> createState() => _NodeScrollState();
}

class _NodeScrollState extends State<_NodeScroll> {
  late final ScrollController _controller;
  final GlobalKey<RefreshIndicatorState> _indicator = GlobalKey();

  /// Open while a refresh is under way; completing it puts the spinner away.
  Completer<void>? _refresh;

  /// The scroll ask already carried out, so one version moves the list once.
  int? _scrollVersion;
  bool _scrolled = false;

  double? get _askedOffset =>
      FlutterUIRenderer._double(widget.props['scrollOffset']);

  @override
  void initState() {
    super.initState();
    final offset = _askedOffset;
    if (offset != null) {
      _scrolled = true;
      _scrollVersion = FlutterUIRenderer._double(
        widget.props['scrollVersion'],
      )?.toInt();
    }
    // The first ask is where the scroller starts, with no jump to see.
    _controller = ScrollController(initialScrollOffset: offset ?? 0);
    _followTree();
  }

  @override
  void didUpdateWidget(_NodeScroll old) {
    super.didUpdateWidget(old);
    _applyScrollRequest();
    _followTree();
  }

  /// Jumps to `scrollOffset` when `scrollVersion` is one not yet obeyed.
  void _applyScrollRequest() {
    final offset = _askedOffset;
    if (offset == null) return;
    final version = FlutterUIRenderer._double(
      widget.props['scrollVersion'],
    )?.toInt();
    if (_scrolled && version == _scrollVersion) return;
    _scrolled = true;
    _scrollVersion = version;
    // After the frame, when the content that came with the ask has been laid
    // out and the offset can be held to what is really there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      _controller.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  /// Brings the spinner in line with the tree's `refreshing`.
  void _followTree() {
    if (widget.props['refreshing'] != true) {
      _refresh?.complete();
      _refresh = null;
      return;
    }
    if (_refresh != null) return;
    // The tree says a refresh is running and nobody pulled: the app started
    // it. The spinner is shown for it, and [_onRefresh] sends nothing.
    _refresh = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _refresh != null) _indicator.currentState?.show();
    });
  }

  Future<void> _onRefresh() {
    final running = _refresh;
    if (running != null) return running.future;
    final started = _refresh = Completer<void>();
    final eventId = widget.props['refreshEventId'];
    if (eventId is String) widget.renderer.handleEvent(eventId, const {});
    return started.future;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final horizontal = p['axis'] == 'horizontal';
    final shrinkWrap = p['shrinkWrap'] == true;
    final refreshes =
        p['refreshEventId'] is String && !horizontal && !shrinkWrap;
    final scroller = SingleChildScrollView(
      controller: _controller,
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      reverse: p['reverse'] == true,
      padding: FlutterUIRenderer._edges(p['padding']),
      physics: shrinkWrap
          // As long as its child and going nowhere: the scroller around it
          // gets the gesture.
          ? const NeverScrollableScrollPhysics()
          // Content shorter than the viewport must still be pullable.
          : refreshes
          ? const AlwaysScrollableScrollPhysics()
          : null,
      child: widget.child,
    );
    final reported = p['scrollEventId'] is! String
        ? scroller
        : NotificationListener<ScrollNotification>(
            onNotification: _onScrolled,
            child: scroller,
          );
    if (!refreshes) return reported;
    return RefreshIndicator(
      key: _indicator,
      color: widget.renderer._primaryColor,
      onRefresh: _onRefresh,
      child: reported,
    );
  }

  /// When the offset was last reported, and what it was.
  final Stopwatch _sinceReport = Stopwatch();
  double? _reportedOffset;

  /// Tells the app where the scroller is: when it comes to rest, and at most
  /// every 100 ms on the way - a report per frame would be a rebuild per
  /// frame for an app that listens.
  bool _onScrolled(ScrollNotification notification) {
    // A scroller inside this one sends its own.
    if (notification.depth != 0) return false;
    final atRest = notification is ScrollEndNotification;
    if (!atRest && notification is! ScrollUpdateNotification) return false;
    if (!atRest &&
        _sinceReport.isRunning &&
        _sinceReport.elapsedMilliseconds < 100) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.pixels == _reportedOffset) return false;
    _reportedOffset = metrics.pixels;
    _sinceReport
      ..reset()
      ..start();
    final eventId = widget.props['scrollEventId'];
    if (eventId is String) {
      widget.renderer.handleEvent(eventId, {
        'offset': metrics.pixels,
        'maxExtent': metrics.maxScrollExtent,
        'viewport': metrics.viewportDimension,
      });
    }
    return false;
  }
}

// -----------------------------------------------------------------------------
// Pickers
// -----------------------------------------------------------------------------

/// Flutter's date or time picker dialog, shown for as long as the node is in
/// the tree.
///
/// The dialogs close themselves with `Navigator.pop`, which here would pop
/// the screen the app is on. So the dialog gets a Navigator of its own, whose
/// one route answers a pop by sending the event and staying where it is: like
/// every overlay, the picker goes when the app takes it out of the tree.
class _NodePicker extends StatefulWidget {
  const _NodePicker({
    super.key,
    required this.renderer,
    required this.props,
    required this.time,
  });

  final FlutterUIRenderer renderer;
  final Map<String, dynamic> props;

  /// A time picker rather than a date picker.
  final bool time;

  @override
  State<_NodePicker> createState() => _NodePickerState();
}

class _NodePickerState extends State<_NodePicker> {
  static String _two(int value) => value.toString().padLeft(2, '0');

  /// What the dialog popped with: a date, a time, or nothing for Cancel and
  /// for a tap on the scrim.
  void _onResult(Object? result) {
    final p = widget.props;
    final eventId = p['eventId'];
    final renderer = widget.renderer;
    if (result is DateTime && eventId is String) {
      renderer.handleEvent(eventId, {
        'value': '${result.year.toString().padLeft(4, '0')}-'
            '${_two(result.month)}-${_two(result.day)}',
      });
    } else if (result is TimeOfDay && eventId is String) {
      renderer.handleEvent(eventId, {
        'hour': result.hour,
        'minute': result.minute,
      });
    } else {
      final dismissEventId = p['dismissEventId'];
      if (dismissEventId is String) {
        renderer.handleEvent(dismissEventId, {'reason': 'cancel'});
      }
    }
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Widget _dialog(BuildContext context) {
    // Read when the dialog builds rather than when its route was made, so it
    // shows what the tree says now.
    final p = widget.props;
    final title = FlutterUIRenderer._optString(p['title']);
    final confirm = FlutterUIRenderer._optString(p['confirmLabel']);
    final cancel = FlutterUIRenderer._optString(p['cancelLabel']);
    if (widget.time) {
      final hour = (FlutterUIRenderer._double(p['hour']) ?? 0).toInt();
      final minute = (FlutterUIRenderer._double(p['minute']) ?? 0).toInt();
      final dialog = TimePickerDialog(
        initialTime: TimeOfDay(
          hour: hour.clamp(0, 23),
          minute: minute.clamp(0, 59),
        ),
        helpText: title,
        confirmText: confirm,
        cancelText: cancel,
      );
      final use24Hour = p['use24Hour'];
      if (use24Hour is! bool) return dialog;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24Hour),
        child: dialog,
      );
    }
    final today = DateUtils.dateOnly(DateTime.now());
    var first = _date(p['first']) ?? DateTime(today.year - 100);
    var last = _date(p['last']) ?? DateTime(today.year + 100);
    // Flutter asserts on a range that runs backwards, and on an initial date
    // outside it; a tree that says either still gets a picker.
    if (last.isBefore(first)) (first, last) = (last, first);
    var initial = _date(p['initial']) ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return DatePickerDialog(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: title,
      confirmText: confirm,
      cancelText: cancel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final barrierLabel = MaterialLocalizations.of(
      context,
    ).modalBarrierDismissLabel;
    return Navigator(
      onGenerateInitialRoutes: (_, _) => [
        // Something under the picker's route: the scrim asks the Navigator
        // whether it *may* pop, and the first route of a Navigator may not.
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        _PickerRoute(
          barrierLabel: barrierLabel,
          onResult: _onResult,
          pageBuilder: (context, _, _) => _dialog(context),
        ),
      ],
    );
  }
}

/// The route a picker dialog sits on: a scrim, no transition, and a pop that
/// reports instead of leaving.
class _PickerRoute extends RawDialogRoute<Object?> {
  _PickerRoute({
    required super.pageBuilder,
    required super.barrierLabel,
    required this.onResult,
  }) : super(
         barrierDismissible: true,
         barrierColor: const Color(0x66000000),
         transitionDuration: Duration.zero,
       );

  final ValueChanged<Object?> onResult;

  /// False is the answer a route gives when it dealt with the pop itself and
  /// is staying - what a route with local history says. Calling super is
  /// what would take the route away, so it is not called.
  @override
  // ignore: must_call_super
  bool didPop(Object? result) {
    onResult(result);
    return false;
  }
}
