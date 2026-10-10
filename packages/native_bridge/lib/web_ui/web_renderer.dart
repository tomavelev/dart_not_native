/// Web Renderer Implementation
///
/// Renders [WidgetNode] trees to real DOM (no canvas, no Flutter). Layout
/// primitives are styled by `dnn.css`; Material components are built by a
/// pluggable [WebStyleKit] (Material Design Lite, Materialize, ...).
///
/// Re-renders are reconciled against the existing DOM: a node whose type and
/// props are unchanged keeps its element (only its children are revisited),
/// so a text field keeps focus and caret while the app re-renders around it.
/// A node whose props did change is patched where a new element would lose
/// something the user can see - a scroll offset, a drag in progress, the
/// canvas a game is drawing into - and rebuilt otherwise.

library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../src/app_theme.dart';
import '../src/contrast.dart';
import '../src/event_binding.dart';
import '../src/frame_probe.dart';
import '../src/icon_data.dart';
import '../src/icons.dart';
import '../src/render_error.dart';
import '../src/render_scheduler.dart';
import '../src/ui_renderer.dart';
import 'kits/mdl_kit.dart';
import 'web_frame_probe.dart';
import 'style_kit.dart';

/// Web implementation of [NativeUIRenderer].
class WebUIRenderer implements NativeUIRenderer, HasFrameProbe {
  final web.Element rootElement;

  /// Builds the Material components.
  final WebStyleKit kit;

  /// Whether spinners/pulses animate. Off makes screenshots deterministic.
  final bool animations;

  /// Whether the renders of one tick are coalesced into a single DOM update.
  ///
  /// On by default: an app that changes state several times before yielding
  /// pays for one pass instead of one per change. Turn it off for a host that
  /// needs the DOM updated by the time [render] returns, without awaiting.
  final bool batched;

  /// Records the browser's frame callbacks.
  @override
  late final FrameProbe frameProbe = WebFrameProbe();

  final Map<String, Function(Map<String, dynamic>)> _handlers = {};

  /// The tree the DOM currently shows, diffed against the next one.
  WidgetNode? _currentTree;

  late final RenderScheduler _scheduler = RenderScheduler(
    _flush,
    batched: batched,
  );

  /// The app's colour theme. Its primary drives the `--dnn-primary` custom
  /// property the style kits read for the app bar, primary buttons and FAB.
  final AppTheme theme;

  WebUIRenderer({
    web.Element? root,
    this.kit = const MdlKit(),
    this.animations = true,
    this.batched = true,
    this.theme = AppTheme.fallback,
  }) : rootElement =
           root ?? web.document.getElementById('app') ?? web.document.body! {
    final style = (rootElement as web.HTMLElement).style;
    _publishPalette(style);
    _trackColorScheme(style);
    _trackVisualViewport(style);
    _trackWindow();
  }

  /// Writes the palette in force onto the root as `--dnn-*` custom properties,
  /// which is the whole of how the stylesheet and the style kits are themed.
  ///
  /// Both appearances go through here: which palette is in force is decided by
  /// [AppTheme.resolve], and the properties are rewritten whenever that answer
  /// changes. `color-scheme` goes with them so the browser's own furniture -
  /// scrollbars, form controls, the canvas behind the page - follows too.
  void _publishPalette(web.CSSStyleDeclaration style) {
    final dark = theme.isDark(platformIsDark: _prefersDark);
    final palette = dark ? theme.dark : theme;
    final inverse = dark ? theme : theme.dark;
    style.setProperty('--dnn-primary', palette.primary);
    style.setProperty('--dnn-on-primary', palette.onPrimary);
    style.setProperty('--dnn-secondary', palette.secondary);
    style.setProperty('--dnn-surface', palette.surface);
    style.setProperty('--dnn-surface-variant', palette.surfaceVariant);
    style.setProperty('--dnn-background', palette.surface);
    style.setProperty('--dnn-text', palette.text);
    style.setProperty('--dnn-text-secondary', palette.textSecondary);
    style.setProperty('--dnn-divider', palette.divider);
    style.setProperty('--dnn-error', palette.error);
    style.setProperty('--dnn-success', palette.success);
    style.setProperty('--dnn-warning', palette.warning);
    style.setProperty('--dnn-info', palette.info);
    // A snackbar is drawn on the other appearance, so it reads as a message
    // over the app rather than vanishing into the surface it covers.
    style.setProperty('--dnn-inverse-surface', inverse.surface);
    style.setProperty('--dnn-inverse-text', inverse.text);
    style.setProperty('--dnn-inverse-primary', inverse.primary);
    style.setProperty('color-scheme', dark ? 'dark' : 'light');
  }

  /// What `prefers-color-scheme` last reported. Only consulted when the theme's
  /// mode is [AppThemeMode.system].
  bool _prefersDark = false;

  /// Follows the browser into and out of dark mode, for a theme that asked to.
  ///
  /// Only the custom properties change, so nothing is re-rendered: the DOM
  /// already refers to them.
  void _trackColorScheme(web.CSSStyleDeclaration style) {
    if (theme.mode != AppThemeMode.system) return;
    final query = web.window.matchMedia('(prefers-color-scheme: dark)');
    _prefersDark = query.matches;
    _publishPalette(style);
    query.addEventListener(
      'change',
      ((web.Event event) {
        _prefersDark = (event as web.MediaQueryListEvent).matches;
        _publishPalette(style);
      }).toJS,
    );
  }

  /// Publishes the visual viewport's height as `--dnn-viewport-height`, which
  /// the scaffold is sized by.
  ///
  /// This is the web's half of keyboard avoidance. An on-screen keyboard does
  /// not change `100vh` - the layout viewport keeps the size it had - so a
  /// scaffold sized that way keeps its bottom, and any field near it, under the
  /// keyboard. The visual viewport is the part actually on screen, and it does
  /// shrink. Browsers without the API (or a test host that stubs the window)
  /// fall back to the `100vh` the property's default carries.
  void _trackVisualViewport(web.CSSStyleDeclaration style) {
    final viewport = web.window.visualViewport;
    if (viewport == null) return;
    void publish(web.Event _) =>
        style.setProperty('--dnn-viewport-height', '${viewport.height}px');
    publish(web.Event('resize'));
    viewport.addEventListener('resize', publish.toJS);
  }

  /// Renders [tree], coalescing the renders of one tick into a single DOM
  /// update.
  ///
  /// The returned future completes once the DOM shows [tree], so
  /// `await render(...)` still means "the DOM is up to date".
  @override
  Future<RenderError?> render(WidgetNode tree) => _scheduler.schedule(tree);

  /// The node types this pass could not draw, filled in as the DOM is built.
  final Set<String> _unknownTypes = {};

  Future<RenderError?> _flush(WidgetNode tree) async {
    try {
      _unknownTypes.clear();
      final build = EventBindings.buildOf(tree);
      tree = _applyDirection(tree);
      _syncChildren(rootElement, [
        tree,
      ], _currentTree == null ? const [] : [_currentTree!]);
      _currentTree = tree;
      // Only now: an element the patch above removed can still speak while
      // it goes (a focused field blurs), and that is the old tree's event.
      _shownBuild = build;
      _afterSync();
      // The DOM is built by the time this returns, so an unknown type is known
      // now rather than a render later.
      return _unknownTypes.isEmpty
          ? null
          : RenderError.unknownNodeTypes({..._unknownTypes});
    } catch (e, st) {
      web.console.error('WebUIRenderer: $e\n$st'.toJS);
      return RenderError.failed('Render error: $e', cause: e, stackTrace: st);
    }
  }

  /// Whether the tree on screen reads right to left.
  bool _rtl = false;

  /// Turns the mount root to face the way [tree] says the screen reads, and
  /// answers the tree without the prop that said so.
  ///
  /// `dir` on the root is the whole of it for the browser: every flex row
  /// under it runs from the right, text starts there, and the stylesheet's
  /// logical properties (`margin-inline-start`, `inset-inline-end`) follow. It
  /// is taken off the node because it describes the screen and not the node -
  /// left on, a language switch would make the root's props differ and the
  /// whole document would be rebuilt for the sake of one attribute.
  WidgetNode _applyDirection(WidgetNode tree) {
    final rtl = tree.props[RootProps.textDirection] == 'rtl';
    _rtl = rtl;
    if (rtl) {
      rootElement.setAttribute('dir', 'rtl');
    } else if (rootElement.getAttribute('dir') == 'rtl') {
      // Only what this renderer put there: a page that set `dir` itself, on
      // this element or above it, keeps its own.
      rootElement.removeAttribute('dir');
    }
    return UIBuilder.withTextDirection(tree, null);
  }

  /// Forgets the tree the DOM is believed to show, so the next render rebuilds
  /// from scratch. For a host that replaced the root's contents itself, and
  /// for benchmarks measuring a first paint.
  void forgetRenderedTree() => _currentTree = null;

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async {
    final handler = _handlers[eventId];
    if (handler != null) {
      // The DOM is patched in the microtask after a build, before the browser
      // can deliver anything, so an event is nearly always for the latest
      // build. The exception is one raised while the patch runs; naming the
      // build the DOM shows covers it - see EventBindings.
      final outer = EventBindings.eventBuild;
      EventBindings.eventBuild = _shownBuild;
      try {
        handler(data);
      } finally {
        EventBindings.eventBuild = outer;
      }
      return {'success': true};
    }
    return {'success': false, 'error': 'Handler not found for $eventId'};
  }

  /// The number of the build the DOM shows; null before the first render and
  /// for a tree no build produced.
  int? _shownBuild;

  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {
    _handlers[eventId] = handler;
    // An app that starts listening after the first frame is still owed the
    // size it is in; it would otherwise wait for a resize that may never come.
    if (eventId == RendererEvents.viewport &&
        !_viewportDelivered &&
        _currentTree != null) {
      scheduleMicrotask(_reportViewport);
    }
  }

  /// Sends an event the renderer raises on its own account.
  ///
  /// Nothing in the tree asked for these, so nobody listening is the ordinary
  /// case rather than a mistake: it is checked here and the event dropped,
  /// where a node's event with no handler is answered as a failure.
  bool _fire(String eventId, Map<String, dynamic> data) {
    if (!_handlers.containsKey(eventId)) return false;
    handleEvent(eventId, data);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Reconciliation
  // ---------------------------------------------------------------------------

  /// Updates [host]'s children from [previous] to [nodes].
  ///
  /// The comparison is against the tree that produced the current DOM, so a
  /// node whose type and props are unchanged keeps its element and only its
  /// children are revisited - which is what lets a text field keep focus and
  /// caret while the app re-renders around it.
  void _syncChildren(
    web.Element host,
    List<WidgetNode> nodes,
    List<WidgetNode> previous,
  ) {
    // Mirrors the host's children, and is reordered alongside them so that
    // index i always names the node that produced the element at index i.
    final standing = List<WidgetNode?>.of(previous);

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      var existing = host.children.item(i);
      var before = i < standing.length ? standing[i] : null;

      // A node with an id is identified by it, so a list that gains, loses or
      // reorders an item moves the elements it already has instead of
      // rebuilding every one after the change.
      final id = node.props['id'];
      final beforeId = before?.props['id'];
      if (id is String && beforeId != id) {
        final found = _indexOfId(standing, id, from: i);
        if (found != null) {
          // The row exists further down: move its element up to here.
          final moved = host.children.item(found)!;
          host.insertBefore(moved, host.children.item(i));
          standing.insert(i, standing.removeAt(found));
          existing = moved;
          before = standing[i];
        } else if (beforeId is String) {
          // A new row among keyed ones: insert it, rather than overwriting a
          // row that is still wanted further down the list.
          final created = _create(node);
          host.insertBefore(created, host.children.item(i));
          standing.insert(i, node);
          continue;
        }
      }

      if (existing != null &&
          before != null &&
          before.type == node.type &&
          // An image is an <img> until it has a fallback and a frame around
          // both after, so one that gained or lost its child is rebuilt.
          !_imageShapeChanged(before, node) &&
          !_roleChanged(before, node)) {
        if (_propsEqual(before.props, node.props)) {
          _syncHosted(existing, node, before.children ?? const []);
          // What a box is to a screen reader depends on what is inside it,
          // and that can change under props that did not.
          if (_describedByChildren(node)) _describeBox(existing, node.props);
          continue;
        }
        // Whichever patch below keeps the element, it answers to the node's
        // id from here on; one that none of them keeps is replaced anyway.
        _syncId(existing, before, node);
        if (_patchChoice(existing, before, node)) {
          standing[i] = node;
          continue;
        }
        if (node.type == 'CameraPreview' && _cameras.containsKey(existing)) {
          // Patched, never replaced: a new element means a new getUserMedia
          // call, which means the camera stops and starts - and on some
          // browsers asks again.
          final video =
              existing.querySelector('video') as web.HTMLVideoElement?;
          final status = existing.querySelector('.dnn-camera__status');
          if (video != null && status != null) {
            if (node.props['active'] == false) {
              _stopCamera(existing);
              video.srcObject = null;
            }
            standing[i] = node;
            continue;
          }
        }
        if (node.type == 'MapView' && _patchMap(existing, node.props)) {
          standing[i] = node;
          continue;
        }
        if (node.type == 'AnimatedContainer' && existing is web.HTMLElement) {
          // Patched for the same reason the fade is: a fresh element would
          // already be at the new size and colour, with nothing to move from.
          _applyBox(existing, node.props);
          _syncHosted(existing, node, before.children ?? const []);
          standing[i] = node;
          continue;
        }
        if (node.type == 'AnimatedOpacity' && existing is web.HTMLElement) {
          // Patched, never replaced: a new element would start at the new
          // opacity and there would be nothing to transition from.
          _applyFade(existing, node.props);
          _syncHosted(existing, node, before.children ?? const []);
          standing[i] = node;
          continue;
        }
        if (node.type == 'Slider' && existing is web.HTMLInputElement) {
          // A slider is patched rather than rebuilt for the same reason a text
          // field is: replacing the element mid-drag would take the pointer
          // capture with it and the thumb would stop following the finger.
          _applySliderProps(existing, node.props);
          standing[i] = node;
          continue;
        }
        if (node.type == 'TextField' && _patchTextField(existing, node)) {
          standing[i] = node;
          continue;
        }
        if (node.type == 'LazyList' && _patchLazyList(existing, before, node)) {
          standing[i] = node;
          continue;
        }
        if ((node.type == 'Dialog' || node.type == 'BottomSheet') &&
            _patchModalTitle(existing, before, node)) {
          _syncHosted(existing, node, before.children ?? const []);
          standing[i] = node;
          continue;
        }
        if (_patchInPlace(existing, before, node)) {
          standing[i] = node;
          continue;
        }
      }

      final created = _create(node);
      if (existing != null) {
        host.replaceChild(created, existing);
        standing[i] = node;
      } else {
        host.appendChild(created);
        standing.add(node);
      }
    }

    while (host.children.length > nodes.length) {
      host.lastElementChild!.remove();
    }
  }

  /// Gives a kept element the id its node has now: a new one, a different
  /// one, or none where there was one.
  static void _syncId(web.Element existing, WidgetNode before, WidgetNode node) {
    final id = node.props['id'];
    if (id is String) {
      if (existing.id != id) existing.id = id;
    } else if (before.props['id'] is String) {
      existing.removeAttribute('id');
    }
  }

  /// Whether a node other than a box was told it is something else to a
  /// screen reader. A box patches its role with the rest of its frame; any
  /// other element was built with a role of its own that the stated one may
  /// have replaced, so it is built again rather than guessed back.
  static bool _roleChanged(WidgetNode before, WidgetNode node) =>
      node.type != 'Box' &&
      node.type != 'Canvas' &&
      before.props['semanticRole'] != node.props['semanticRole'];

  static bool _imageShapeChanged(WidgetNode before, WidgetNode node) =>
      node.type == 'Image' &&
      (before.children?.isEmpty ?? true) != (node.children?.isEmpty ?? true);

  /// The prop that carries each checkable control's state.
  static const Map<String, String> _choiceState = {
    'Checkbox': 'checked',
    'Radio': 'selected',
    'Toggle': 'enabled',
  };

  /// Ticks, unticks, disables or enables a checkbox, radio or switch in place,
  /// when that is all that changed.
  ///
  /// The element is the browser's own input, so there is nothing to rebuild:
  /// its two properties are the whole of its state. Keeping it keeps the
  /// keyboard focus on a box that was just toggled with the space bar, and
  /// lets a control that has become available again be the same control.
  /// Anything else - the label, the event id the listener closed over - is a
  /// different control, and is rebuilt as before.
  bool _patchChoice(web.Element existing, WidgetNode before, WidgetNode node) {
    final state = _choiceState[node.type];
    if (state == null) return false;
    for (final key in {...before.props.keys, ...node.props.keys}) {
      if (key == state || key == 'disabled') continue;
      if (!_valueEqual(before.props[key], node.props[key])) return false;
    }
    final input = existing.querySelector('input') as web.HTMLInputElement?;
    if (input == null) return false;
    _applyChoice(existing, input, node.props, state);
    return true;
  }

  /// What a checkable control's tree says about it: on or off, and whether it
  /// can be changed. A disabled input already refuses the click and leaves the
  /// tab order; the class is for the stylesheet, to grey the label with it.
  void _applyChoice(
    web.Element root,
    web.HTMLInputElement input,
    Map<String, dynamic> p,
    String state,
  ) {
    final disabled = p['disabled'] == true;
    input
      ..checked = p[state] == true
      ..disabled = disabled;
    // A control with no label of its own - a list tile's, whose title is a
    // text beside it - is named by what the tree says it is called.
    final name = _optStr(p['semanticLabel']);
    if (name != null) input.setAttribute('aria-label', name);
    root.classList.toggle('dnn-choice--disabled', disabled);
    // The colours the app stated, as custom properties a kit's stylesheet
    // reads in place of the brand's. A switch the app coloured is that colour
    // when it is on - its track, solid - under the thumb the app chose, or a
    // white one.
    final active = p['activeColor'];
    final isSwitch = state == 'enabled';
    _controlColor(root, 'active', active);
    _controlColor(root, 'check', p['checkColor']);
    _controlColor(
      root,
      'thumb',
      p['thumbColor'] ?? (isSwitch && active is String ? '#ffffff' : null),
    );
    _controlColor(root, 'inactive-track', p['inactiveTrackColor']);
    _controlColor(root, 'inactive-thumb', p['inactiveThumbColor']);
    // For a kit whose own stylesheet has a colour written into it, which a
    // custom property with no value cannot stand aside for.
    root.classList.toggle('dnn-control--active', active is String);
  }

  /// The look the app gave a field, as inline styles on its input - over
  /// whatever the kit's stylesheet says, and taken away again for a field
  /// that no longer says it, which then goes back to the kit's.
  ///
  /// `border` is the outline's kind. An underline is a border on one side;
  /// an outline with no colour of its own keeps the kit's and takes only the
  /// radius it was given.
  void _applyFieldLook(web.HTMLElement input, Map<String, dynamic> p) {
    final style = input.style;
    void set(String property, String? value) {
      if (value == null) {
        style.removeProperty(property);
      } else {
        style.setProperty(property, value);
      }
    }

    String? colour(Object? value) => value is String ? cssColor(value) : null;
    String? pixels(Object? value) => value is num ? '${value}px' : null;

    set('color', colour(p['textColor']));
    set('font-size', pixels(p['fontSize']));
    final weight = p['fontWeight'];
    set('font-weight', weight is num ? '${weight.toInt()}' : null);
    set('background-color', colour(p['fillColor']));
    // A field drawn as a box - filled, or outlined - needs room inside it,
    // and not every kit's field has any: Materialize's is a line under bare
    // text. The app's padding where it gave one, and otherwise a box's usual.
    final boxed = p['fillColor'] != null || p['border'] == 'outline';
    final padding = switch (p['contentPadding']) {
      [final num l, final num t, final num r, final num b] =>
        '${t}px ${r}px ${b}px ${l}px',
      _ => boxed ? '10px 12px' : null,
    };
    set('padding', padding);
    // Inside the width the field already has, or the padding makes it wider
    // than the column it is in.
    set('box-sizing', padding == null ? null : 'border-box');

    final line =
        '${_num(p['borderWidth']) ?? 1}px solid '
        '${colour(p['borderColor']) ?? 'var(--dnn-divider)'}';
    final stated = p['borderColor'] != null;
    // The one side first: taking it away after the whole border is set
    // takes that side of the whole border with it.
    set('border-bottom', null);
    switch (p['border']) {
      case 'none':
        set('border', 'none');
        set('border-radius', null);
        // The ring a kit draws round a focused field is part of its outline.
        set('box-shadow', 'none');
      case 'underline':
        set('border', 'none');
        set('border-bottom', line);
        set('border-radius', '0');
        set('box-shadow', 'none');
      case 'outline':
        set('border', stated ? line : null);
        set('border-radius', pixels(p['borderRadius']));
        set('box-shadow', null);
      default:
        set('border', null);
        set('border-radius', null);
        set('box-shadow', null);
    }
  }

  /// Sets `--dnn-control-<part>` on [element] to [color], or takes it away
  /// when the tree states none - so a control that stops being coloured goes
  /// back to the brand's.
  void _controlColor(web.Element element, String part, Object? color) {
    final style = (element as web.HTMLElement).style;
    if (color is String) {
      style.setProperty('--dnn-control-$part', cssColor(color));
    } else {
      style.removeProperty('--dnn-control-$part');
    }
  }

  /// Re-titles a dialog or sheet in place, when the title is all that changed.
  ///
  /// A modal whose own props changed was rebuilt, which threw away everything
  /// inside it - including the focus and caret of a field the user was typing
  /// in. A title that counts a selection, or names the row being confirmed,
  /// changes while the modal is open, and there is no reason for it to cost
  /// the user their place.
  ///
  /// Only the title: the dismiss listeners close over the event id they were
  /// built with, and whether the modal is dismissible decides whether they
  /// exist at all, so a change to either still rebuilds. So does a title
  /// appearing or disappearing, which moves the body along by an element.
  bool _patchModalTitle(
    web.Element existing,
    WidgetNode before,
    WidgetNode node,
  ) {
    for (final key in {...before.props.keys, ...node.props.keys}) {
      if (key == 'title') continue;
      if (!_valueEqual(before.props[key], node.props[key])) return false;
    }
    // The title is the modal's only heading.
    final heading = existing.querySelector('h2');
    final title = _optStr(node.props['title']);
    if (heading == null || title == null) return false;
    heading.textContent = title;
    return true;
  }

  /// Index of the node carrying [id] at or after [from], if any.
  static int? _indexOfId(
    List<WidgetNode?> nodes,
    String id, {
    required int from,
  }) {
    for (var i = from; i < nodes.length; i++) {
      if (nodes[i]?.props['id'] == id) return i;
    }
    return null;
  }

  /// Deep equality over prop maps.
  ///
  /// Props are JSON-shaped - scalars, lists and maps - so this walks them
  /// directly rather than comparing serialised forms, which used to build one
  /// string per node on every render.
  static bool _propsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_valueEqual(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  static bool _valueEqual(Object? a, Object? b) {
    if (identical(a, b) || a == b) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_valueEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valueEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return false;
  }

  /// The element that holds a node's rendered children, if it has any.
  web.Element? _childHost(web.Element element) {
    if (element.hasAttribute('data-children')) return element;
    return element.querySelector('[data-children]');
  }

  /// Updates the children [element] hosts for [node] from [previous].
  void _syncHosted(
    web.Element element,
    WidgetNode node,
    List<WidgetNode> previous,
  ) {
    final host = _childHost(element);
    if (host == null) return;
    _syncChildren(host, node.children ?? const [], previous);
    // A row the reconciliation just built has no size yet.
    if (node.type == 'LazyList') _sizeLazyRows(element, host);
  }

  /// Work that needs the DOM to show the whole tree.
  void _afterSync() {
    // Focus only moves once the dialog is in the document; the last one
    // opened is the one on top.
    final focus = _pendingFocus;
    _pendingFocus = null;
    if (focus != null && focus.isConnected) (focus as web.HTMLElement).focus();
    _restoreFocusIfModalsClosed();
    _applyFocusAsk();
    _applyScrollAsks();
    if (!_viewportDelivered) _reportViewport();
    _clearSnackbarOfBottomBar();
    _pruneSnackbarTimers();
    _releaseGoneCameras();
  }

  /// Says how tall the scaffold's bottom bar is where a snackbar can read it.
  ///
  /// The resize observer publishes the same number, but only when the bar's
  /// size changes - and a snackbar usually arrives over a bar that has been
  /// the size it is for some time, in an overlay element made a moment ago.
  void _clearSnackbarOfBottomBar() {
    final snackbar = rootElement.querySelector('.dnn-overlay > .dnn-snackbar');
    final overlay = snackbar?.parentElement;
    final bar = overlay?.querySelector(':scope > .dnn-scaffold > .dnn-bottombar');
    if (overlay == null || bar == null) return;
    _style(
      overlay,
      '--dnn-bottombar-height',
      '${bar.getBoundingClientRect().height}px',
    );
  }

  /// Answers the field that asked for the keyboard, now that it is drawn.
  ///
  /// An explicit ask outranks the focus a modal or a restore moved, because it
  /// is the app saying where the user should be typing.
  void _applyFocusAsk() {
    final ask = _focusAsk;
    _focusAsk = null;
    if (ask == null || !ask.$1.isConnected) return;
    if (ask.$2) {
      ask.$1.focus();
    } else {
      ask.$1.blur();
    }
  }

  /// Gives focus back to where it was once the last modal has gone.
  ///
  /// Nothing to do while one is still open, and nothing to do if the element
  /// left the document with the render - focusing a detached node moves the
  /// caret to the body, which is worse than leaving it alone.
  void _restoreFocusIfModalsClosed() {
    final target = _focusBeforeModal;
    if (target == null) return;
    if (rootElement.querySelector('.dnn-modal') != null) return;

    final id = _focusBeforeModalId;
    _focusBeforeModal = null;
    _focusBeforeModalId = null;

    // The same element if it survived the render, otherwise the one that took
    // its place under the same id.
    final restored = target.isConnected
        ? target
        : id == null
        ? null
        : rootElement.querySelector('[id="$id"]');
    if (restored is web.HTMLElement) restored.focus();
  }

  /// Elements created since the counter was last reset (diagnostics only).
  int debugCreateCount = 0;

  web.Element _create(WidgetNode node) {
    debugCreateCount++;
    final element = _build(node);
    element.setAttribute('data-type', node.type);
    final id = node.props['id'];
    // The node's own element, whatever it is made of. A text field's and a
    // dropdown's is the frame around the control: the `<input>` or `<select>`
    // inside it already has an id of its own (`dnn-input-…`, `dnn-select-…`)
    // for its label to point at, and is found as `#id input` / `#id select`.
    if (id is String) element.id = id;
    _syncHosted(element, node, const []);
    // After the children, because a box that holds a button is not one.
    if (node.type == 'Box' || node.type == 'Canvas') {
      _describeBox(element, node.props, canvas: node.type == 'Canvas');
    } else {
      _applyRole(element, node.props);
    }
    return element;
  }

  // ---------------------------------------------------------------------------
  // Node builders
  // ---------------------------------------------------------------------------

  web.Element _build(WidgetNode node) {
    final p = node.props;
    // node-types:begin
    switch (node.type) {
      // Layout primitives (kit-neutral, dnn.css)
      case 'Scaffold':
        final scaffold = _host(_el('div', 'dnn-scaffold'));
        _applyScaffold(scaffold, p);
        return scaffold;
      case 'NavigationStack':
        return _host(_el('div', 'dnn-navstack'));
      case 'NavigationBar':
        final inline = p['inline'] != false;
        final bar = _el(
          'header',
          'dnn-navbar${inline ? '' : ' dnn-navbar--large'}',
        );
        bar.appendChild(
          _el('span', 'dnn-navbar__title', text: _str(p['title']))
            ..setAttribute('role', 'heading')
            ..setAttribute('aria-level', '1'),
        );
        return bar;
      case 'Column':
        final align = p['crossAxisAlignment'];
        final main = p['mainAxisAlignment'];
        final size = p['mainAxisSize'];
        final column = _host(
          _el(
            'div',
            [
              'dnn-column',
              if (align is String) 'dnn-column--$align',
              if (main is String) 'dnn-column--main-$main',
              if (size is String) 'dnn-column--size-$size',
            ].join(' '),
          ),
        );
        _gap(column, p['spacing']);
        return column;
      case 'VStack':
        final column = _host(
          _el(
            'div',
            'dnn-column ${_stackAlign(p['alignment'], vertical: true)}',
          ),
        );
        _gap(column, p['spacing']);
        return column;
      case 'Row':
        final main = p['mainAxisAlignment'];
        final cross = p['crossAxisAlignment'];
        final size = p['mainAxisSize'];
        final row = _host(
          _el(
            'div',
            [
              'dnn-row',
              if (main is String) 'dnn-row--$main',
              if (cross is String) 'dnn-row--cross-$cross',
              if (size is String) 'dnn-row--size-$size',
            ].join(' '),
          ),
        );
        _gap(row, p['spacing']);
        return row;
      case 'HStack':
        final row = _host(_el('div', 'dnn-row'));
        _style(
          row,
          'align-items',
          _stackAlign(p['alignment'], vertical: false),
        );
        _gap(row, p['spacing']);
        return row;
      case 'Wrap':
        final wrap = _host(_el('div', 'dnn-row'));
        _style(wrap, 'flex-wrap', 'wrap');
        _style(wrap, 'column-gap', '${_num(p['spacing']) ?? 0}px');
        _style(wrap, 'row-gap', '${_num(p['runSpacing']) ?? 0}px');
        // Both default to the start, which the tree leaves out. The row class
        // centres across its axis, so the cross alignment is always written.
        final along = _flexAlign(p['alignment']);
        if (along != 'flex-start') _style(wrap, 'justify-content', along);
        _style(wrap, 'align-items', _flexAlign(p['crossAxisAlignment']));
        return wrap;
      case 'Expanded':
        final loose = p['fit'] == 'loose';
        final expanded = _host(
          _el(
            'div',
            loose ? 'dnn-expanded dnn-expanded--loose' : 'dnn-expanded',
          ),
        );
        _style(expanded, 'flex', '${_num(p['flex']) ?? 1} 1 0');
        return expanded;
      case 'Center':
        return _host(_el('div', 'dnn-center'));
      case 'SwipeActions':
        return _swipeActions(p);
      case 'Padding':
        final padding = _host(_el('div', 'dnn-padding'));
        _style(padding, 'padding', _padding(p));
        return padding;
      case 'SizedBox':
        final box = _el('div', 'dnn-sizedbox');
        final height = _num(p['height']);
        final width = _num(p['width']);
        if (height != null) _style(box, 'height', '${height}px');
        if (width != null) _style(box, 'width', '${width}px');
        return box;
      case 'Spacer':
        final spacer = _el('div', 'dnn-spacer');
        _style(spacer, 'min-height', '${_num(p['minLength']) ?? 0}px');
        return spacer;
      case 'Text':
        return _text(p);
      case 'Image':
        return _image(p, hasFallback: node.children?.isNotEmpty ?? false);
      case 'Divider':
        return _divider(p);
      case 'Loading':
        return _loading(p);

      // Material components (style kit)
      case 'AppBar':
        return _appBar(p);
      case 'BottomBar':
        final bar = _host(_el('div', 'dnn-bottombar'));
        // Its height is what the floating button has to clear.
        _resizes.observe(bar);
        return bar;
      case 'BottomNavigation':
        return _bottomNavigation(p);
      case 'FloatingActionButton':
        final fab = kit.floatingActionButton(_buttonGlyph(p, Icons.add));
        final label = _optStr(p['label']);
        if (label != null) {
          // Material's extended button: the same control, drawn as a pill
          // with its purpose written beside the icon.
          fab.classList.add('dnn-fab--extended');
          fab.appendChild(_el('span', 'dnn-fab__label', text: label));
        }
        // Important, because a kit may be: Materialize colours its button
        // with a class whose rule says so, and an inline style loses to that.
        final fabStyle = (fab as web.HTMLElement).style;
        final background = _optStr(p['backgroundColor']);
        if (background != null) {
          fabStyle.setProperty(
            'background-color',
            cssColor(background),
            'important',
          );
        }
        final foreground = _optStr(p['foregroundColor']);
        if (foreground != null) {
          fabStyle.setProperty('color', cssColor(foreground), 'important');
          // The glyph too, where a kit colours it apart from its button.
          final glyphs = fab.querySelectorAll('.material-icons');
          for (var i = 0; i < glyphs.length; i++) {
            (glyphs.item(i)! as web.HTMLElement).style.setProperty(
              'color',
              cssColor(foreground),
              'important',
            );
          }
        }
        return _clickable(_tooltip(fab, p), p);
      case 'IconButton':
        final button = kit.iconButton(_buttonGlyph(p, Icons.more_vert));
        final color = _optStr(p['color']);
        if (color != null) _style(button, 'color', cssColor(color));
        final size = _num(p['size']);
        if (size != null) {
          // The glyph is the size asked for and the target keeps the 8px of
          // room around it that the 24px default has in its 40px circle.
          _style(button, 'width', '${size + 16}px');
          _style(button, 'height', '${size + 16}px');
          _style(button, 'min-width', '0');
          final glyph = button.firstElementChild;
          if (glyph != null) _style(glyph, 'font-size', '${size}px');
        }
        if (p['disabled'] == true) button.setAttribute('disabled', '');
        return _clickable(_tooltip(button, p), p);
      case 'Button':
      case 'MaterialButton':
        final color = p['color'];
        final button = kit.button(
          _str(p['label']),
          variant: _str(p['variant'], 'primary'),
          size: _str(p['size'], 'md'),
          color: color is String ? color : null,
        );
        // Whatever the app stated instead of the scale the class carries.
        final minHeight = _num(p['minHeight']);
        final minWidth = _num(p['minWidth']);
        final fontSize = _num(p['fontSize']);
        final padH = _num(p['paddingHorizontal']);
        final padV = _num(p['paddingVertical']);
        if (minHeight != null) {
          _style(button, 'height', 'auto');
          _style(button, 'min-height', '${minHeight}px');
        }
        if (minWidth != null) _style(button, 'min-width', '${minWidth}px');
        if (fontSize != null) _style(button, 'font-size', '${fontSize}px');
        if (padH != null || padV != null) {
          _style(button, 'padding', '${padV ?? 0}px ${padH ?? 0}px');
        }
        if (p['disabled'] == true) button.setAttribute('disabled', '');
        final foreground = _optStr(p['foregroundColor']);
        if (foreground != null) _style(button, 'color', cssColor(foreground));
        final glyph = _num(p['iconCodepoint']);
        if (glyph != null) {
          // Before the label, and out of the accessible name: the label
          // already says what the button does.
          final icon = _el(
            'i',
            'material-icons dnn-button__icon',
            text: _glyphText(glyph),
          )..setAttribute('aria-hidden', 'true');
          button.insertBefore(icon, button.firstChild);
          button.classList.add('dnn-button--icon');
        }
        if (p['expand'] == true) button.classList.add('dnn-button--expand');
        return _clickable(button, p);
      case 'Box':
        return _box(p);
      case 'Stack':
        final stack = _host(_el('div', 'dnn-stack'));
        _applyStack(stack, p);
        return stack;
      case 'Positioned':
        final positioned = _host(_el('div', 'dnn-positioned'));
        _applyPositioned(positioned, p, fresh: true);
        return positioned;
      case 'Scroll':
        return _scroll(p);
      case 'Icon':
        return _icon(p);
      case 'Canvas':
        return _canvas(p);
      case 'Dropdown':
        return _dropdown(p);
      case 'DatePicker':
        return _picker(p, date: true);
      case 'TimePicker':
        return _picker(p, date: false);
      case 'FlutterSlot':
        // There is no Flutter engine on this target to paint into the region,
        // so it is drawn as the room the widget would have taken: the
        // fallback inside it when the app gave one, and empty otherwise - the
        // layout around it is then the same as on a renderer that has one.
        final slot = _host(_el('div', 'dnn-flutter-slot'));
        _applySlot(slot, p, fresh: true);
        return slot;
      case 'TextField':
        return _textField(p);
      case 'Checkbox':
        final parts = kit.checkbox(_optStr(p['label']));
        _applyChoice(parts.root, parts.input, p, 'checked');
        _onChange(parts.input, p, (input) => {'checked': input.checked});
        return parts.root;
      case 'Radio':
        final parts = kit.radio(_optStr(p['label']));
        _applyChoice(parts.root, parts.input, p, 'selected');
        _onChange(parts.input, p, (_) => {'value': p['value']});
        return parts.root;
      case 'Toggle':
        final parts = kit.toggle(_optStr(p['label']));
        // A checkbox drawn as a switch is announced as a checkbox unless it
        // says otherwise, and not every kit's markup does.
        parts.input.setAttribute('role', 'switch');
        _applyChoice(parts.root, parts.input, p, 'enabled');
        _onChange(parts.input, p, (input) => {'enabled': input.checked});
        return parts.root;
      case 'GridView':
        final grid = _host(_el('div', 'dnn-grid'));
        final columns = (_num(p['crossAxisCount']) ?? 2).toInt();
        _style(grid, 'grid-template-columns', 'repeat($columns, 1fr)');
        _style(grid, 'column-gap', '${_num(p['spacing']) ?? 0}px');
        _style(grid, 'row-gap', '${_num(p['runSpacing']) ?? 0}px');
        // Every cell the same shape, which is what makes it a grid; the ratio
        // is a cell's width over its height, as in Flutter.
        final ratio = _num(p['childAspectRatio']);
        if (ratio != null && ratio > 0) {
          _style(grid, '--dnn-grid-ratio', '$ratio');
        }
        return grid;
      case 'CameraPreview':
        return _camera(p);
      case 'MapView':
        return _map(p);
      case 'AnimatedOpacity':
        final fade = _host(_el('div', 'dnn-fade'));
        _applyFade(fade, p);
        return fade;
      case 'AnimatedContainer':
        final box = _host(_el('div', 'dnn-animated-box'));
        _applyBox(box, p);
        return box;
      case 'Tabs':
        final labels = _strings(p['tabs']);
        final selected = (_num(p['selectedIndex']) ?? 0).toInt();
        final bar = kit.tabs(labels, selected);
        final eventId = p['eventId'];
        if (eventId is String) {
          for (var i = 0; i < bar.children.length; i++) {
            final index = i;
            void choose() {
              handleEvent(eventId, {..._data(p), 'index': index});
            }

            bar.children
                .item(i)!
                .addEventListener('click', ((web.Event _) => choose()).toJS);
          }
        }
        return bar;
      case 'Slider':
        final slider = kit.slider();
        _applySliderProps(slider, p);
        final eventId = p['eventId'];
        if (eventId is String) {
          // 'input' is every step of the drag, 'change' is letting go.
          void report(String suffix) {
            handleEvent('${eventId}_$suffix', {
              ..._data(p),
              'value': double.tryParse(slider.value) ?? 0,
            });
          }

          slider.addEventListener(
            'input',
            ((web.Event _) => report('change')).toJS,
          );
          slider.addEventListener(
            'change',
            ((web.Event _) => report('end')).toJS,
          );
        }
        return slider;
      case 'Card':
        final background = p['backgroundColor'];
        final parts = kit.card(
          variant: _str(p['variant'], 'elevated'),
          elevation: _num(p['elevation']) ?? 2,
          padding: _num(p['padding']) ?? 16,
          title: _optStr(p['title']),
          backgroundColor: background is String ? background : null,
        );
        _host(parts.childHost);
        return parts.root;
      case 'Badge':
        return kit.badge(
          _optStr(p['label']),
          variant: _str(p['variant'], 'solid'),
          color: _str(p['color'], theme.primary),
        );
      case 'Alert':
        final parts = kit.alert(
          type: _str(p['type'], 'info'),
          message: _str(p['message']),
          title: _optStr(p['title']),
          dismissible: p['dismissible'] == true,
        );
        parts.root.setAttribute('role', 'alert');
        final close = parts.close;
        if (close != null) {
          close.setAttribute('aria-label', 'Dismiss');
          close.addEventListener(
            'click',
            ((web.Event _) => _style(parts.root, 'display', 'none')).toJS,
          );
        }
        return parts.root;
      case 'WebView':
        final frame = _el('iframe', 'dnn-webview');
        frame.setAttribute('src', _str(p['url']));
        frame.setAttribute('title', 'Embedded web page');
        _style(frame, 'height', '${_num(p['height']) ?? 300}px');
        _style(frame, 'width', '100%');
        _style(frame, 'border', 'none');
        if (p['javaScriptEnabled'] != true) {
          // No allow-scripts, so the page is shown and not run - the same
          // choice the other renderers make when JavaScript is off.
          frame.setAttribute('sandbox', 'allow-same-origin allow-popups');
        }
        return frame;
      case 'List':
      case 'ListView':
        return _host(kit.list());
      case 'ListItem':
      case 'ListRow':
        return kit.listItem(_str(p['text']), _optStr(p['subtitle']));
      case 'LazyList':
        return _lazyList(p);

      // Overlays (kit-neutral, dnn.css)
      case 'Overlay':
        return _host(_el('div', 'dnn-overlay'));
      case 'Dialog':
        return _modal(p, kind: 'dialog');
      case 'BottomSheet':
        return _modal(p, kind: 'sheet');
      case 'Snackbar':
        return _snackbar(p);
      default:
        _unknownTypes.add(node.type);
        return _el('div', 'dnn-unknown', text: 'Unknown widget: ${node.type}');
    }
    // node-types:end
  }

  web.Element _text(Map<String, dynamic> p) {
    final spans = p['spans'];
    final text = _el(
      'span',
      'dnn-text',
      text: spans is List ? null : _str(p['content']),
    );
    _applyRunStyle(text, p);
    final align = p['textAlign'];
    if (align is String) {
      // An inline box is exactly as wide as its words, which leaves nothing
      // to align within; a block takes the width it is offered.
      _style(text, 'display', 'block');
      _style(text, 'text-align', align);
    }
    final spacing = _num(p['letterSpacing']);
    if (spacing != null) _style(text, 'letter-spacing', '${spacing}px');
    final lineHeight = _num(p['lineHeight']);
    if (lineHeight != null) _style(text, 'line-height', '$lineHeight');
    final family = _optStr(p['fontFamily']);
    if (family != null) _style(text, 'font-family', _fontFamily(family));
    if (p['selectable'] == true) {
      // Text on a page can be selected anyway, except where something around
      // it - a tappable box, a draggable one - turned that off. This turns it
      // back on, and shows the caret that says so.
      _style(text, 'user-select', 'text');
      _style(text, '-webkit-user-select', 'text');
      _style(text, 'cursor', 'text');
    }
    if (spans is List) {
      // Each run is a span of its own that states only what it changes; the
      // rest it inherits from this element, which is what the protocol says a
      // run does.
      for (final run in spans) {
        if (run is! Map) continue;
        final span = _el('span', 'dnn-text__span', text: _str(run['text']));
        _applyRunStyle(span, Map<String, dynamic>.from(run));
        text.appendChild(span);
      }
    }
    _clampLines(text, p);
    return text;
  }

  /// The styling a text node and one of its runs have in common.
  void _applyRunStyle(web.Element text, Map<String, dynamic> p) {
    final size = _num(p['fontSize']);
    if (size != null) _style(text, 'font-size', '${size}px');
    final weight = p['fontWeight'];
    if (weight != null) _style(text, 'font-weight', '$weight');
    final color = p['color'];
    if (color is String) _style(text, 'color', cssColor(color));
    if (p['italic'] == true) _style(text, 'font-style', 'italic');
    switch (p['decoration']) {
      case 'lineThrough':
        _style(text, 'text-decoration', 'line-through');
      case 'underline':
        _style(text, 'text-decoration', 'underline');
    }
  }

  /// A protocol font family as CSS: the generic names as they are, and a real
  /// family quoted, with the page's own sans-serif behind it for a machine
  /// that does not have it.
  static String _fontFamily(String family) => switch (family) {
    'monospace' ||
    'serif' ||
    'sans-serif' ||
    'cursive' ||
    'system-ui' => family,
    _ => '"${family.replaceAll('"', '')}", sans-serif',
  };

  /// Caps a text at `maxLines`, ending it with an ellipsis when asked.
  ///
  /// One line is `text-overflow`, which is what that property is for; more
  /// than one is `-webkit-line-clamp`, which every current browser supports
  /// and which nothing else does as well.
  void _clampLines(web.Element text, Map<String, dynamic> p) {
    final maxLines = (_num(p['maxLines']) ?? 0).toInt();
    if (maxLines <= 0) return;
    final ellipsis = p['overflow'] != 'clip';
    _style(text, 'overflow', 'hidden');
    if (maxLines == 1) {
      _style(text, 'white-space', 'nowrap');
      _style(text, 'text-overflow', ellipsis ? 'ellipsis' : 'clip');
      return;
    }
    // Both spellings: the standard one, and the -webkit- pair that browsers
    // which have not caught up still need.
    _style(text, 'display', '-webkit-box');
    _style(text, '-webkit-box-orient', 'vertical');
    _style(text, '-webkit-line-clamp', '$maxLines');
    _style(text, 'line-clamp', '$maxLines');
    // The clamp draws its own ellipsis; without it the box just ends.
    if (!ellipsis) _style(text, 'text-overflow', 'clip');
  }

  /// An image: an `<img>`, which the browser fetches, caches and decodes on
  /// its own account - a rebuild that keeps the `src` costs no request.
  ///
  /// With a fallback child the `<img>` sits in a frame of the stated size
  /// beside the child's host, and only one of the two shows: the fallback
  /// until the image has loaded, and for good if it fails - so the browser's
  /// broken-image glyph and the alt text never appear in its place.
  web.Element _image(Map<String, dynamic> p, {bool hasFallback = false}) {
    final image = _el('img', 'dnn-image') as web.HTMLImageElement;
    final width = _num(p['width']);
    final height = _num(p['height']);
    if (!hasFallback) {
      image
        ..src = _str(p['src'])
        // Doubles as the accessible name and as what shows if the load fails.
        ..alt = _str(p['alt']);
      if (width != null) _style(image, 'width', '${width}px');
      if (height != null) _style(image, 'height', '${height}px');
      _style(image, 'object-fit', _objectFit(_str(p['fit'], 'cover')));
      return image;
    }

    image.alt = _str(p['alt']);
    _style(image, 'object-fit', _objectFit(_str(p['fit'], 'cover')));
    final frame = _el('span', 'dnn-image-frame')
      // The frame is the image as far as a screen reader goes, whichever of
      // the two is showing inside it.
      ..setAttribute('role', 'img')
      ..setAttribute('aria-label', _str(p['alt']));
    if (width != null) _style(frame, 'width', '${width}px');
    if (height != null) _style(frame, 'height', '${height}px');
    final fallback = _host(_el('span', 'dnn-image-frame__fallback'));
    void show(bool loaded) {
      _setHidden(image, !loaded);
      _setHidden(fallback, loaded);
    }

    image
      ..addEventListener('load', ((web.Event _) => show(true)).toJS)
      ..addEventListener('error', ((web.Event _) => show(false)).toJS)
      ..src = _str(p['src']);
    // One the browser already holds is complete as soon as it is named, so
    // the fallback is never drawn in front of it.
    show(image.complete && image.naturalWidth > 0);
    frame
      ..appendChild(fallback)
      ..appendChild(image);
    return frame;
  }

  static String _objectFit(String fit) => switch (fit) {
    'contain' => 'contain',
    'fill' => 'fill',
    'none' => 'none',
    'scaleDown' => 'scale-down',
    _ => 'cover',
  };

  web.Element _divider(Map<String, dynamic> p) {
    final divider = _el('div', 'dnn-divider');
    final thickness = _num(p['thickness']) ?? 1;
    final color = p['color'];
    if (color is String) _style(divider, 'background', cssColor(color));
    if (p['orientation'] == 'vertical') {
      _style(divider, 'width', '${thickness}px');
      _style(divider, 'height', '${_num(p['height']) ?? 24}px');
      _style(divider, 'align-self', 'center');
    } else {
      _style(divider, 'height', '${thickness}px');
      _style(divider, 'margin', '${_num(p['margin']) ?? 16}px 0');
    }
    return divider;
  }

  /// Something that says work is going on, and what it is to a screen
  /// reader: a progress bar - with how far along it is when it knows, and
  /// with no value when it does not, which is how "busy" is said. A skeleton
  /// and a pulse are decoration around content, and say something only when
  /// the app gave them a name to say.
  web.Element _loading(Map<String, dynamic> p) {
    final loading = _drawLoading(p);
    final type = p['type'];
    final decoration = type == 'skeleton' || type == 'pulse';
    final name = _optStr(p['semanticLabel']);
    if (decoration && name == null) return loading;
    loading.setAttribute('role', type == 'pulse' ? 'group' : 'progressbar');
    if (name != null) loading.setAttribute('aria-label', name);
    final determinate =
        (type == 'progress-linear' || type == 'progress-circular') &&
        p['indeterminate'] != true;
    if (determinate) {
      final done = ((_num(p['value']) ?? 0) * 100).clamp(0, 100).round();
      loading
        ..setAttribute('aria-valuemin', '0')
        ..setAttribute('aria-valuemax', '100')
        ..setAttribute('aria-valuenow', '$done');
    }
    return loading;
  }

  web.Element _drawLoading(Map<String, dynamic> p) {
    final color = cssColor(_str(p['color'], theme.primary));
    final animate = animations ? ' dnn-animate' : '';
    switch (p['type']) {
      case 'progress-linear':
        final value = p['indeterminate'] == true
            ? 0.3
            : (_num(p['value']) ?? 0);
        return kit.progressLinear(value, color);
      case 'progress-circular':
        final value = p['indeterminate'] == true
            ? 0.25
            : (_num(p['value']) ?? 0);
        final degrees = (value * 360).clamp(0, 360);
        final ring = _el('div', 'dnn-progress-circular');
        _style(
          ring,
          'background',
          'conic-gradient($color ${degrees}deg, rgba(0,0,0,0.1) 0deg)',
        );
        _style(
          ring,
          'mask',
          'radial-gradient(circle, transparent 55%, black 56%)',
        );
        return ring;
      case 'skeleton':
        final skeleton = _el('div', 'dnn-skeleton dnn-pulse$animate');
        final width = _num(p['width']);
        _style(
          skeleton,
          'width',
          width == null || width.isInfinite ? '100%' : '${width}px',
        );
        _style(skeleton, 'height', '${_num(p['height']) ?? 16}px');
        return skeleton;
      case 'pulse':
        return _host(_el('div', 'dnn-pulse$animate'));
      default:
        final size = _num(p['size']) ?? 24;
        final spinner = _el('div', 'dnn-spinner$animate');
        _style(spinner, 'width', '${size}px');
        _style(spinner, 'height', '${size}px');
        _style(spinner, 'color', color);
        return spinner;
    }
  }

  // ---------------------------------------------------------------------------
  // Overlays
  // ---------------------------------------------------------------------------

  /// The surface of the dialog or sheet built last, focused once it is in the
  /// document.
  web.Element? _pendingFocus;

  /// A field that asked for, or gave up, the keyboard during this render.
  (web.HTMLElement, bool)? _focusAsk;

  /// What had focus before the first modal opened, to give it back when the
  /// last one closes.
  ///
  /// Only the first is remembered: a dialog stacked over a sheet should return
  /// the user to where they were before either, not to the sheet that is
  /// closing with it.
  web.Element? _focusBeforeModal;

  /// That element's `id`, which is what actually survives.
  ///
  /// Opening a dialog wraps the screen in an `Overlay`, so the root's type
  /// changes and the DOM underneath is rebuilt - the element that had focus is
  /// a different object by the time the dialog closes. An `id` outlives that;
  /// a control without one cannot be found again, and focus is left where the
  /// browser put it rather than moved somewhere arbitrary.
  String? _focusBeforeModalId;

  /// Numbers the ids that tie a dialog to its title.
  int _titleCount = 0;

  /// Snackbar timeouts still running, by snackbar identity.
  final Map<String, Timer> _snackbarTimers = {};

  /// Snackbars whose timeout has been sent, so rendering one again while the
  /// app has not removed it yet does not start another.
  final Set<String> _snackbarsTimedOut = {};

  /// A dialog or bottom sheet: a scrim and, beside it rather than inside it, a
  /// surface - so a tap on the surface never reaches the scrim.
  ///
  /// [kind] is 'dialog' or 'sheet'. Children go into the surface's body,
  /// which scrolls when the surface outgrows the viewport. The renderer never
  /// closes the modal: the scrim and Escape only send the dismiss event.
  web.Element _modal(Map<String, dynamic> p, {required String kind}) {
    final modal = _el('div', 'dnn-modal dnn-modal--$kind');
    final scrim = _el('div', 'dnn-scrim');
    final surface = _el('div', 'dnn-$kind')
      ..setAttribute('role', 'dialog')
      ..setAttribute('aria-modal', 'true')
      ..setAttribute('tabindex', '-1');
    final title = _optStr(p['title']);
    if (title != null) {
      final heading = _el('h2', 'dnn-${kind}__title', text: title)
        ..id = 'dnn-title-${++_titleCount}';
      surface
        ..appendChild(heading)
        ..setAttribute('aria-labelledby', heading.id);
    }
    surface.appendChild(_host(_el('div', 'dnn-${kind}__body')));
    modal
      ..appendChild(scrim)
      ..appendChild(surface);

    final eventId = p['dismissEventId'];
    if (p['dismissible'] != false && eventId is String) {
      scrim.addEventListener(
        'click',
        ((web.Event _) {
          handleEvent(eventId, {'reason': 'scrim'});
        }).toJS,
      );
      // Focus is inside the modal, so its keys reach the modal before
      // anything underneath.
      modal.addEventListener(
        'keydown',
        ((web.KeyboardEvent e) {
          if (e.key == 'Escape') handleEvent(eventId, {'reason': 'escape'});
        }).toJS,
      );
    }
    // Where the user was, so closing can put them back. A keyboard user who
    // opened a dialog from a button should land on that button again, not at
    // the top of the document.
    if (_focusBeforeModal == null) {
      _focusBeforeModal = web.document.activeElement;
      final id = _focusBeforeModal?.id;
      _focusBeforeModalId = id == null || id.isEmpty ? null : id;
    }
    _pendingFocus = surface;
    return modal;
  }

  /// A row that slides its child left to reveal trailing action buttons: a
  /// partial drag snaps open so an action can be clicked, a full drag fires the
  /// first action. The child (the `data-children` host) is opaque so the
  /// actions stay hidden until the row is dragged.
  web.Element _swipeActions(Map<String, dynamic> p) {
    final container = _el('div', 'dnn-swipe');
    _style(container, 'position', 'relative');
    _style(container, 'overflow', 'hidden');

    /// One bar of buttons, pinned to the [edge] of the row it reads towards
    /// - `inset-inline-start` leads, `inset-inline-end` trails - answering
    /// with the event ids it bound. A logical edge, so the bars change sides
    /// with the reading direction without being rebuilt.
    List<String> bar(List<dynamic> actions, String edge, String className) {
      final eventIds = <String>[];
      if (actions.isEmpty) return eventIds;
      final bar = _el('div', className);
      _style(bar, 'position', 'absolute');
      _style(bar, 'top', '0');
      _style(bar, 'bottom', '0');
      _style(bar, edge, '0');
      _style(bar, 'display', 'flex');
      for (final a in actions) {
        if (a is! Map) continue;
        final eventId = a['eventId'];
        final btn = _el('button', 'dnn-swipe__action', text: _str(a['label']));
        _style(btn, 'width', '88px');
        _style(btn, 'border', 'none');
        _style(btn, 'color', '#ffffff');
        _style(btn, 'font-weight', '600');
        _style(btn, 'cursor', 'pointer');
        final color = a['color'];
        _style(
          btn,
          'background',
          color is String ? cssColor(color) : '#d32f2f',
        );
        if (eventId is String) {
          eventIds.add(eventId);
          btn.addEventListener(
            'click',
            ((web.Event _) {
              handleEvent(eventId, const {});
            }).toJS,
          );
        }
        bar.appendChild(btn);
      }
      container.appendChild(bar);
      return eventIds;
    }

    final eventIds = bar(
      (p['actions'] as List?) ?? const [],
      'inset-inline-end',
      'dnn-swipe__actions',
    );
    final leadingIds = bar(
      (p['leadingActions'] as List?) ?? const [],
      'inset-inline-start',
      'dnn-swipe__actions dnn-swipe__actions--leading',
    );

    final fg = _host(_el('div', 'dnn-swipe__fg'));
    _style(fg, 'position', 'relative');
    _style(fg, 'background', 'var(--dnn-surface, #ffffff)');
    _style(fg, 'touch-action', 'pan-y');
    container.appendChild(fg);

    // Where the row rests when it is open each way, counted towards the end
    // of the row: negative shows the trailing actions, positive the leading
    // ones. The bars change sides with the reading direction; the pointer and
    // the transform are in screen coordinates and are turned to match, or a
    // swipe would slide the row over the bar it meant to show.
    final open = -88.0 * eventIds.length;
    final openLeading = 88.0 * leadingIds.length;
    var startX = 0.0, offset = 0.0, dragging = false;
    double sign() => _rtl ? -1 : 1;
    void setX(double x, {bool animate = false}) {
      _style(fg, 'transition', animate ? 'transform 0.2s' : 'none');
      _style(fg, 'transform', 'translateX(${x * sign()}px)');
    }

    fg.addEventListener(
      'pointerdown',
      ((web.Event e) {
        final pe = e as web.PointerEvent;
        dragging = true;
        startX = pe.clientX.toDouble();
        fg.setPointerCapture(pe.pointerId);
      }).toJS,
    );
    fg.addEventListener(
      'pointermove',
      ((web.Event e) {
        if (!dragging) return;
        final pe = e as web.PointerEvent;
        offset = ((pe.clientX.toDouble() - startX) * sign()).clamp(
          open * 1.8,
          openLeading * 1.8,
        );
        setX(offset);
      }).toJS,
    );
    void end(web.Event _) {
      if (!dragging) return;
      dragging = false;
      if (offset <= open * 1.6 && eventIds.isNotEmpty) {
        handleEvent(eventIds.first, const {});
        offset = 0;
        setX(0, animate: true);
      } else if (offset >= openLeading * 1.6 && leadingIds.isNotEmpty) {
        handleEvent(leadingIds.first, const {});
        offset = 0;
        setX(0, animate: true);
      } else if (offset <= open / 2) {
        offset = open;
        setX(open, animate: true);
      } else if (openLeading > 0 && offset >= openLeading / 2) {
        offset = openLeading;
        setX(openLeading, animate: true);
      } else {
        offset = 0;
        setX(0, animate: true);
      }
    }

    fg.addEventListener('pointerup', end.toJS);
    fg.addEventListener('pointercancel', end.toJS);
    return container;
  }

  /// A snackbar, whose timeout starts the first time it is built.
  ///
  /// The timer belongs to the snackbar's identity, not its element: a render
  /// that rebuilds the element finds the timer already running (or already
  /// sent) and leaves it be. It is cancelled once the snackbar leaves the
  /// tree, see [_pruneSnackbarTimers].
  web.Element _snackbar(Map<String, dynamic> p) {
    final message = _str(p['message']);
    final bar = _el('div', 'dnn-snackbar')
      ..setAttribute('role', 'status')
      ..setAttribute('aria-live', 'polite');
    bar.appendChild(_el('span', 'dnn-snackbar__message', text: message));

    final label = _optStr(p['actionLabel']);
    final actionId = p['actionEventId'];
    if (label != null) {
      final action = _el('button', 'dnn-snackbar__action', text: label);
      if (actionId is String) {
        action.addEventListener(
          'click',
          ((web.Event _) {
            handleEvent(actionId, {});
          }).toJS,
        );
      }
      bar.appendChild(action);
    }

    final dismissId = p['dismissEventId'];
    final key =
        _optStr(p['id']) ?? (dismissId is String ? dismissId : null) ?? message;
    bar.setAttribute('data-snackbar', key);
    final duration = (_num(p['durationMs']) ?? 0).toInt();
    if (dismissId is String &&
        duration > 0 &&
        !_snackbarTimers.containsKey(key) &&
        !_snackbarsTimedOut.contains(key)) {
      _snackbarTimers[key] = Timer(Duration(milliseconds: duration), () {
        _snackbarTimers.remove(key);
        _snackbarsTimedOut.add(key);
        handleEvent(dismissId, {'reason': 'timeout'});
      });
    }
    return bar;
  }

  /// Cancels the timers of snackbars no longer shown, and forgets the
  /// timeouts of those gone, so one shown again later times out again.
  void _pruneSnackbarTimers() {
    if (_snackbarTimers.isEmpty && _snackbarsTimedOut.isEmpty) return;
    final found = rootElement.querySelectorAll('[data-snackbar]');
    final shown = {
      for (var i = 0; i < found.length; i++)
        (found.item(i)! as web.Element).getAttribute('data-snackbar'),
    };
    _snackbarTimers.removeWhere((key, timer) {
      if (shown.contains(key)) return false;
      timer.cancel();
      return true;
    });
    _snackbarsTimedOut.retainWhere(shown.contains);
  }

  // ---------------------------------------------------------------------------
  // Lazy lists
  // ---------------------------------------------------------------------------

  /// What a lazy list's scroll handler reads, kept per viewport element so a
  /// patch can change it under listeners that are already attached.
  final Expando<_LazyListState> _lazyLists = Expando('lazyList');

  /// A scroll viewport as tall as the whole list, holding only the window.
  ///
  /// The content box is sized for every row and pushed down by padding to the
  /// window's first row, so the rows themselves stay plain children that the
  /// usual reconciliation moves. The structure is inline rather than left to
  /// the kit's stylesheets: without it the list would not scroll at all.
  web.Element _lazyList(Map<String, dynamic> p) {
    final viewport = _el('div', 'dnn-lazylist');
    _style(viewport, 'overflow-y', 'auto');
    // Rows are placed by arithmetic; the browser moving the scroll position to
    // keep a row in view would fight it.
    _style(viewport, 'overflow-anchor', 'none');
    _style(viewport, 'flex', '1 1 0');
    _style(viewport, 'min-height', '0');
    _style(viewport, 'align-self', 'stretch');
    final content = _host(_el('div', 'dnn-lazylist__content'));
    _style(content, 'display', 'flex');
    _style(content, 'flex-direction', 'column');
    _style(content, 'box-sizing', 'border-box');
    viewport.appendChild(content);

    final state = _lazyLists[viewport] = _LazyListState();
    _applyLazyListProps(state, content, p);
    _applyScrollAsk(viewport, p);

    viewport.addEventListener(
      'scroll',
      ((web.Event _) => _reportRange(viewport)).toJS,
    );
    // Fires once the list is first laid out, and whenever its height changes.
    web.ResizeObserver(
      ((JSArray<web.ResizeObserverEntry> _, web.ResizeObserver _) =>
              _reportRange(viewport))
          .toJS,
    ).observe(viewport);
    return viewport;
  }

  /// Updates a lazy list in place, so its scroll position survives the window
  /// moving under it.
  bool _patchLazyList(
    web.Element viewport,
    WidgetNode before,
    WidgetNode node,
  ) {
    final state = _lazyLists[viewport];
    final content = _childHost(viewport);
    if (state == null ||
        content == null ||
        before.props['id'] != node.props['id']) {
      return false;
    }
    _applyLazyListProps(state, content, node.props);
    _applyScrollAsk(viewport, node.props);
    _syncHosted(viewport, node, before.children ?? const []);
    // A different row count can change which rows are visible. Reported after
    // this pass, so the app's re-render does not run inside it.
    scheduleMicrotask(() => _reportRange(viewport));
    return true;
  }

  void _applyLazyListProps(
    _LazyListState state,
    web.Element content,
    Map<String, dynamic> p,
  ) {
    final extents = p['extents'];
    state
      ..eventId = _optStr(p['rangeEventId'])
      ..extent = _num(p['itemExtent']) ?? 0
      ..count = (_num(p['itemCount']) ?? 0).toInt()
      ..rowExtents = extents is List
          ? [for (final extent in extents) (_num(extent) ?? 0).toDouble()]
          : const [];
    final start = (_num(p['startIndex']) ?? 0).toInt();
    // Rows of their own heights come with the window's own heights, where the
    // window starts and how tall the whole list is; uniform rows are
    // arithmetic from the index.
    final total = state.rowExtents.isEmpty
        ? state.count * state.extent
        : _num(p['totalExtent']) ?? 0;
    final top = state.rowExtents.isEmpty
        ? start * state.extent
        : _num(p['startOffset']) ?? 0;
    _style(content, 'height', '${total}px');
    _style(content, 'padding-top', '${top}px');
  }

  /// Gives every row of a lazy list its fixed height and the full width.
  void _sizeLazyRows(web.Element viewport, web.Element content) {
    final state = _lazyLists[viewport];
    final extent = state?.extent ?? 0;
    final rowExtents = state?.rowExtents ?? const <double>[];
    for (var i = 0; i < content.children.length; i++) {
      final row = content.children.item(i)!;
      final height = i < rowExtents.length ? rowExtents[i] : extent;
      _style(row, 'height', '${height}px');
      _style(row, 'flex', '0 0 auto');
      _style(row, 'align-self', 'stretch');
      _style(row, 'box-sizing', 'border-box');
    }
  }

  /// Sends the rows now visible, when they differ from the last ones sent.
  void _reportRange(web.Element viewport) {
    final state = _lazyLists[viewport];
    if (state == null) return;
    final eventId = state.eventId;
    final height = viewport.clientHeight;
    if (eventId == null || state.count <= 0) return;
    // Not laid out, or not in the document: nothing is visible to report.
    if (height <= 0) return;

    final offset = viewport.scrollTop;
    // Rows of different heights are reported as pixels: only the Dart side
    // knows how tall the rows outside the window are, so only it can say
    // which row an offset lands on.
    if (state.rowExtents.isNotEmpty) {
      if (offset == state.offset && height == state.viewport) return;
      state
        ..offset = offset
        ..viewport = height.toDouble();
      handleEvent(eventId, {'offset': offset, 'viewport': height});
      return;
    }
    if (state.extent <= 0) return;
    final first = (offset / state.extent).floor();
    final last = math.min(
      state.count - 1,
      ((offset + height) / state.extent).ceil() - 1,
    );
    if (first == state.first && last == state.last) return;
    state
      ..first = first
      ..last = last;
    handleEvent(eventId, {'first': first, 'last': last});
  }

  // ---------------------------------------------------------------------------
  // Text fields
  // ---------------------------------------------------------------------------

  web.Element _textField(Map<String, dynamic> p) {
    final multiline = (_num(p['maxLines']) ?? 1) > 1;
    final parts = kit.textField(multiline: multiline);
    final input = parts.input;
    if (multiline) {
      input.setAttribute('rows', '${_num(p['maxLines'])!.toInt()}');
    } else {
      input.setAttribute(
        'type',
        p['obscureText'] == true ? 'password' : 'text',
      );
    }
    // Lets the renderer find the parts again when patching.
    parts.label.setAttribute('data-part', 'label');
    input.setAttribute('data-part', 'input');
    parts.error.setAttribute('data-part', 'error');

    final eventId = p['eventId'];
    _adornTextField(parts, p);
    if (eventId is String) {
      String value() => _inputValue(input);
      void emit(String suffix) {
        handleEvent('${eventId}_$suffix', {'value': value()});
      }

      // A field that opens a picker. Whether it is tappable is read when the
      // click arrives rather than now, because the field is patched in place
      // and the answer can change under a listener that is already attached.
      input.addEventListener(
        'click',
        ((web.Event _) {
          if (parts.root.hasAttribute('data-tappable')) emit('tap');
        }).toJS,
      );
      final suffix = parts.root.querySelector('button[data-part="suffix"]');
      suffix?.addEventListener('click', ((web.Event _) => emit('suffix')).toJS);

      input.addEventListener('input', ((web.Event _) => emit('change')).toJS);
      input.addEventListener('focus', ((web.Event _) => emit('focus')).toJS);
      input.addEventListener('blur', ((web.Event _) => emit('blur')).toJS);
      final advances = p['textInputAction'] == 'next';
      // Tells a touch keyboard what to put on its return key; desktop browsers
      // ignore it and Enter does the same thing either way.
      if (advances) input.setAttribute('enterkeyhint', 'next');
      input.addEventListener(
        'keydown',
        ((web.KeyboardEvent e) {
          if (e.key != 'Enter' || multiline) return;
          emit('submit');
          if (advances) _focusFieldAfter(input);
        }).toJS,
      );
    }
    _applyTextFieldProps(parts, p, initial: true);
    return parts.root;
  }

  /// Moves focus to the field after [input] in document order.
  ///
  /// Document order is the reading order of the rendered tree, which is the
  /// order the fields were declared in - so "next" means what the app meant by
  /// it without the app having to say which field that is. Nothing happens at
  /// the last field, and the keyboard closing is then the right thing anyway.
  void _focusFieldAfter(web.Element input) {
    final fields = rootElement.querySelectorAll(
      'input.dnn-textfield__input, input[data-part="input"], textarea',
    );
    for (var i = 0; i < fields.length - 1; i++) {
      if (fields.item(i) != input) continue;
      for (var next = i + 1; next < fields.length; next++) {
        final candidate = fields.item(next);
        // The attribute rather than the property, so this reads the same for an
        // input and a textarea without casting one to the other.
        if (candidate is web.HTMLElement &&
            !candidate.hasAttribute('disabled')) {
          candidate.focus();
          return;
        }
      }
    }
  }

  /// The camera streams each preview is showing, so one can be stopped when
  /// its element leaves the page.
  final Map<web.Element, web.MediaStream> _cameras = {};

  /// A live camera preview: the browser's own video element, fed by
  /// getUserMedia.
  ///
  /// Frames never touch Dart - the stream goes to the element and the browser
  /// composites it. The camera is released when the element leaves the page
  /// (see [_releaseGoneCameras]), because a preview nobody is looking at still
  /// holds the device and its light.
  web.Element _camera(Map<String, dynamic> p) {
    final frame = _el('div', 'dnn-camera');
    _style(frame, 'height', '${_num(p['height']) ?? 300}px');

    final video = web.document.createElement('video') as web.HTMLVideoElement
      ..className = 'dnn-camera__video'
      ..autoplay = true
      ..muted = true
      // Without this, iOS Safari takes a video full screen instead of showing
      // it where it was put.
      ..setAttribute('playsinline', '');
    frame.appendChild(video);

    final status = _el('div', 'dnn-camera__status');
    // Hidden until there is something to say: an empty grey box over the
    // preview while the browser thinks about it is worse than nothing.
    _setHidden(status, true);
    frame.appendChild(status);

    _startCamera(frame, video, status, p);
    return frame;
  }

  void _startCamera(
    web.Element frame,
    web.HTMLVideoElement video,
    web.Element status,
    Map<String, dynamic> p,
  ) {
    void report(String state, String? message) {
      status.textContent = message ?? '';
      _setHidden(status, message == null);
      final eventId = p['eventId'];
      if (eventId is! String) return;
      handleEvent('${eventId}_status', {
        'status': state,
        if (message != null) 'message': message,
      });
    }

    if (p['active'] == false) {
      _stopCamera(frame);
      report('stopped', null);
      return;
    }

    final media = web.window.navigator.mediaDevices;
    final constraints = web.MediaStreamConstraints(
      video: {
        'facingMode': p['facing'] == 'front' ? 'user' : 'environment',
      }.jsify()!,
      audio: false.toJS,
    );
    media
        .getUserMedia(constraints)
        .toDart
        .then(
          (stream) {
            _cameras[frame] = stream;
            video.srcObject = stream;
            report('ready', null);
          },
          onError: (Object error) {
            // A refused permission and a machine with no camera look the same from
            // here apart from the name the browser gives the error.
            final name = '$error';
            final denied = name.contains('NotAllowed');
            report(
              denied ? 'denied' : 'unavailable',
              denied
                  ? 'The camera permission was refused.'
                  : 'No camera is available here.',
            );
          },
        );
  }

  /// Stops the stream [frame] is showing, if any.
  void _stopCamera(web.Element frame) {
    final stream = _cameras.remove(frame);
    if (stream == null) return;
    final tracks = stream.getTracks().toDart;
    for (final track in tracks) {
      track.stop();
    }
  }

  /// Releases the camera behind any preview that is no longer on the page.
  ///
  /// The reconciler removes elements without telling anyone, and a dropped
  /// `<video>` keeps its stream - and the camera light - until the tab is
  /// closed.
  void _releaseGoneCameras() {
    for (final frame in _cameras.keys.toList()) {
      if (frame.isConnected) continue;
      _stopCamera(frame);
    }
  }

  /// A map made of raster tiles.
  ///
  /// There is no platform map on web, so this is the slippy-map arithmetic
  /// every web map does: the world at zoom z is 2^z tiles square, a tile is
  /// 256px, and a coordinate becomes a pixel through the Web Mercator
  /// projection. Tiles are `<img>` elements, so the browser fetches, caches
  /// and composites them - no canvas, no WebGL context, no library.
  /// Where each map is looking now: the tree's centre until a drag moves it,
  /// and the drag handlers read it rather than the props they were built with.
  final Map<web.Element, Map<String, dynamic>> _mapState = {};

  web.Element _map(Map<String, dynamic> p) {
    final frame = _el('div', 'dnn-map');
    _mapState[frame] = {...p};
    _style(frame, 'height', '${_num(p['height']) ?? 300}px');

    final tiles = _el('div', 'dnn-map__tiles');
    frame.appendChild(tiles);

    final attribution = _el(
      'div',
      'dnn-map__attribution',
      // OpenStreetMap's tiles are free and ask for this in return.
      text: '© OpenStreetMap contributors',
    );
    frame.appendChild(attribution);

    _drawMap(frame);
    if (p['interactive'] != false) _makeMapDraggable(frame);
    return frame;
  }

  /// Re-centres a map in place. Rebuilding one would throw away every tile it
  /// has and fetch them again, which is the whole reason this node is patched.
  bool _patchMap(web.Element frame, Map<String, dynamic> p) {
    final state = _mapState[frame];
    if (state == null) return false;
    state
      ..clear()
      ..addAll(p);
    _drawMap(frame);
    return true;
  }

  /// Lays the tiles and markers out for the centre and zoom [p] carries.
  void _drawMap(web.Element frame) {
    final p = _mapState[frame];
    final tiles = frame.querySelector('.dnn-map__tiles');
    if (p == null || tiles == null) return;
    final zoom = (_num(p['zoom']) ?? 13).round().clamp(0, 19);
    final latitude = _num(p['latitude']) ?? 0;
    final longitude = _num(p['longitude']) ?? 0;
    final template =
        _optStr(p['tileUrl']) ??
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    // Where the centre sits in world pixels, and therefore where the frame's
    // top-left corner does.
    final centreX = _lonToPixels(longitude, zoom);
    final centreY = _latToPixels(latitude, zoom);
    final width = frame.clientWidth > 0 ? frame.clientWidth : 640;
    final height = (_num(p['height']) ?? 300).round();
    final left = centreX - width / 2;
    final top = centreY - height / 2;

    while (tiles.firstChild != null) {
      tiles.removeChild(tiles.firstChild!);
    }

    final count = 1 << zoom;
    final firstX = (left / 256).floor();
    final firstY = (top / 256).floor();
    final lastX = ((left + width) / 256).floor();
    final lastY = ((top + height) / 256).floor();
    for (var y = firstY; y <= lastY; y++) {
      if (y < 0 || y >= count) continue;
      for (var x = firstX; x <= lastX; x++) {
        // Longitude wraps; latitude does not.
        final wrapped = ((x % count) + count) % count;
        final img = _el('img', 'dnn-map__tile');
        img
          ..setAttribute('alt', '')
          ..setAttribute('loading', 'lazy')
          ..setAttribute(
            'src',
            template
                .replaceAll('{z}', '$zoom')
                .replaceAll('{x}', '$wrapped')
                .replaceAll('{y}', '$y'),
          );
        _style(img, 'left', '${x * 256 - left}px');
        _style(img, 'top', '${y * 256 - top}px');
        tiles.appendChild(img);
      }
    }

    for (final marker in (p['markers'] as List? ?? const [])) {
      if (marker is! Map) continue;
      final dot = _el('div', 'dnn-map__marker');
      final label = marker['label'];
      if (label is String) dot.setAttribute('title', label);
      _style(
        dot,
        'left',
        '${_lonToPixels((marker['longitude'] as num?)?.toDouble() ?? 0, zoom) - left}px',
      );
      _style(
        dot,
        'top',
        '${_latToPixels((marker['latitude'] as num?)?.toDouble() ?? 0, zoom) - top}px',
      );
      tiles.appendChild(dot);
    }
  }

  /// Drag to pan, reporting where it came to rest and never while it moves.
  void _makeMapDraggable(web.Element frame) {
    var dragging = false;
    var lastX = 0.0;
    var lastY = 0.0;

    double centre(String key) =>
        (_mapState[frame]?[key] as num?)?.toDouble() ?? 0;
    int zoomOf() => ((_mapState[frame]?['zoom'] as num?)?.toDouble() ?? 13)
        .round()
        .clamp(0, 19);

    frame.addEventListener(
      'pointerdown',
      ((web.PointerEvent event) {
        dragging = true;
        lastX = event.clientX.toDouble();
        lastY = event.clientY.toDouble();
        (frame as web.HTMLElement).setPointerCapture(event.pointerId);
      }).toJS,
    );
    frame.addEventListener(
      'pointermove',
      ((web.PointerEvent event) {
        if (!dragging) return;
        final dx = event.clientX.toDouble() - lastX;
        final dy = event.clientY.toDouble() - lastY;
        lastX = event.clientX.toDouble();
        lastY = event.clientY.toDouble();
        final zoom = zoomOf();
        _mapState[frame]?['longitude'] = _pixelsToLon(
          _lonToPixels(centre('longitude'), zoom) - dx,
          zoom,
        );
        _mapState[frame]?['latitude'] = _pixelsToLat(
          _latToPixels(centre('latitude'), zoom) - dy,
          zoom,
        );
        _drawMap(frame);
      }).toJS,
    );
    void settle() {
      if (!dragging) return;
      dragging = false;
      final eventId = _mapState[frame]?['eventId'];
      if (eventId is! String) return;
      handleEvent('${eventId}_idle', {
        'latitude': centre('latitude'),
        'longitude': centre('longitude'),
        'zoom': zoomOf().toDouble(),
      });
    }

    frame.addEventListener(
      'pointerup',
      ((web.PointerEvent _) => settle()).toJS,
    );
    frame.addEventListener(
      'pointercancel',
      ((web.PointerEvent _) => settle()).toJS,
    );
  }

  static double _lonToPixels(double longitude, int zoom) =>
      (longitude + 180) / 360 * 256 * (1 << zoom);

  static double _latToPixels(double latitude, int zoom) {
    final radians = latitude * math.pi / 180;
    final mercator = math.log(math.tan(radians) + 1 / math.cos(radians));
    return (1 - mercator / math.pi) / 2 * 256 * (1 << zoom);
  }

  static double _pixelsToLon(double x, int zoom) =>
      x / (256 * (1 << zoom)) * 360 - 180;

  static double _pixelsToLat(double y, int zoom) {
    final n = math.pi - 2 * math.pi * y / (256 * (1 << zoom));
    return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  /// The opacity and the transition that carries it.
  void _applyFade(web.Element fade, Map<String, dynamic> p) {
    final duration = (_num(p['durationMs']) ?? 200).toInt();
    _style(fade, 'transition', 'opacity ${duration}ms ${_timing(p)}');
    _style(fade, 'opacity', '${_num(p['opacity']) ?? 1}');
  }

  /// The props an animated box draws from, on build and on patch.
  ///
  /// The browser does the animating: naming the properties in a `transition`
  /// means a later render that writes a different width, height or background
  /// moves there rather than jumping, which is exactly what the protocol
  /// asks for.
  void _applyBox(web.Element box, Map<String, dynamic> p) {
    final duration = (_num(p['durationMs']) ?? 200).toInt();
    final timing = _timing(p);
    _style(
      box,
      'transition',
      'width ${duration}ms $timing, height ${duration}ms $timing, '
          'background-color ${duration}ms $timing',
    );
    final width = _num(p['width']);
    final height = _num(p['height']);
    _style(box, 'width', width == null ? '' : '${width}px');
    _style(box, 'height', height == null ? '' : '${height}px');
    final color = p['color'];
    _style(box, 'background-color', color is String ? cssColor(color) : '');
    // Text over a colour the app chose reads against that colour, not against
    // the surface the theme was written for; children that state no colour of
    // their own inherit it.
    _style(box, 'color', color is String ? textOn(color) : '');
  }

  /// A protocol curve name as a CSS timing function.
  String _timing(Map<String, dynamic> p) {
    switch (p['curve']) {
      case 'linear':
        return 'linear';
      case 'ease':
        return 'ease';
      case 'easeIn':
        return 'ease-in';
      case 'easeOut':
        return 'ease-out';
      default:
        return 'ease-in-out';
    }
  }

  /// Takes or gives up the keyboard when the app asks.
  ///
  /// `autofocus` is asked once, the first time the field is drawn; a
  /// `focusVersion` is a fresh ask each time it changes, which is how a moment
  /// travels in a tree that only carries states.
  void _applyFocusRequest(
    web.Element input,
    web.Element root,
    Map<String, dynamic> p,
  ) {
    final element = input as web.HTMLElement;
    final version = p['focusVersion'];
    final seen = root.getAttribute('data-focus-version');
    if (version != null) {
      if (seen == '$version') return;
      root.setAttribute('data-focus-version', '$version');
      // Not now: a field built by this render is not in the document yet, and
      // focusing a detached element does nothing at all.
      _focusAsk = (element, p['focusRequested'] != false);
      return;
    }
    if (p['autofocus'] == true && seen == null) {
      root.setAttribute('data-focus-version', 'auto');
      _focusAsk = (element, true);
    }
  }

  /// The props a range input draws from, on build and on patch.
  void _applySliderProps(web.HTMLInputElement slider, Map<String, dynamic> p) {
    final min = _num(p['min']) ?? 0;
    final max = _num(p['max']) ?? 1;
    final divisions = _num(p['divisions']);
    slider
      ..min = '$min'
      ..max = '$max'
      // Without divisions the step is the browser's default 1, which would
      // snap a 0..1 slider to its ends; 'any' is continuous.
      ..step = divisions == null ? 'any' : '${(max - min) / divisions}'
      ..disabled = p['disabled'] == true;
    // A range input takes one colour from a page, its accent: the filled
    // part of the track and the thumb together. A kit that draws its own
    // thumb can colour that apart; `inactiveColor` has nowhere to go.
    _controlColor(slider, 'active', p['activeColor']);
    _controlColor(slider, 'thumb', p['thumbColor']);
    final value = '${_num(p['value']) ?? min}';
    // Leave the thumb where the user has it while they are dragging: an echo
    // of the value we already have would fight the drag.
    if (slider.value != value) slider.value = value;
  }

  /// Which glyphs a field carries at its ends, as one comparable value.
  static String _adornments(Map<String, dynamic> p) => [
    if (p['prefixIcon'] != null) 'prefix',
    if (p['suffixIcon'] != null)
      p['suffixTappable'] == true ? 'suffix-button' : 'suffix',
  ].join(' ');

  /// Puts the glyphs a field asked for at its ends.
  ///
  /// The kit's markup has nowhere to anchor one - the input's position inside
  /// the field depends on the label above it - so the input is wrapped in a
  /// box of its own and the glyphs are pinned to that. Only a field that has
  /// one is wrapped, which leaves every other field exactly as its kit built
  /// it.
  void _adornTextField(TextFieldParts parts, Map<String, dynamic> p) {
    final adornments = _adornments(p);
    if (adornments.isEmpty) return;
    parts.root.setAttribute('data-adornments', adornments);
    final box = _el('div', 'dnn-textfield__box');
    parts.input.parentNode!.insertBefore(box, parts.input);
    box.appendChild(parts.input);
    if (p['prefixIcon'] != null) {
      box.appendChild(
        _el(
            'i',
            'material-icons dnn-textfield__icon dnn-textfield__icon--prefix',
          )
          ..setAttribute('data-part', 'prefix')
          ..setAttribute('aria-hidden', 'true'),
      );
    }
    if (p['suffixIcon'] != null) {
      // A glyph that does something is a button, so the keyboard reaches it;
      // one that only decorates is not, so it does not.
      final tappable = p['suffixTappable'] == true;
      final suffix = _el(
        tappable ? 'button' : 'i',
        'material-icons dnn-textfield__icon dnn-textfield__icon--suffix',
      )..setAttribute('data-part', 'suffix');
      if (tappable) {
        suffix.setAttribute('type', 'button');
      } else {
        suffix.setAttribute('aria-hidden', 'true');
      }
      box.appendChild(suffix);
    }
  }

  /// Sets [name] to [value], or takes it off when there is none.
  void _attr(web.Element element, String name, String? value) {
    if (value != null) {
      element.setAttribute(name, value);
    } else if (element.hasAttribute(name)) {
      element.removeAttribute(name);
    }
  }

  /// Update a text field in place so it keeps focus and caret position.
  bool _patchTextField(web.Element root, WidgetNode node) {
    final parts = _textFieldParts(root);
    final multiline = (_num(node.props['maxLines']) ?? 1) > 1;
    if (parts == null ||
        (parts.input.tagName.toLowerCase() == 'textarea') != multiline) {
      return false;
    }
    // A glyph arriving or leaving changes what the field is made of.
    if ((root.getAttribute('data-adornments') ?? '') !=
        _adornments(node.props)) {
      return false;
    }
    _applyTextFieldProps(parts, node.props, initial: false);
    return true;
  }

  TextFieldParts? _textFieldParts(web.Element root) {
    final label = root.querySelector('[data-part="label"]');
    final input = root.querySelector('[data-part="input"]');
    final error = root.querySelector('[data-part="error"]');
    if (label == null || input == null || error == null) return null;
    return TextFieldParts(root: root, label: label, input: input, error: error);
  }

  void _applyTextFieldProps(
    TextFieldParts parts,
    Map<String, dynamic> p, {
    required bool initial,
  }) {
    // Tie the visible label to the input, and the error to it as a
    // description. Without this a screen reader reaches a field and has
    // nothing to announce but "edit text" - the label beside it is just
    // another piece of text on the page as far as it is concerned.
    final fieldId = _optStr(p['eventId']) ?? _optStr(p['id']);
    if (fieldId != null) {
      final inputId = 'dnn-input-$fieldId';
      parts.input.id = inputId;
      (parts.label as web.HTMLLabelElement).htmlFor = inputId;
      parts.error.id = 'dnn-error-$fieldId';
    }

    final labelText = _optStr(p['label']);
    parts.label.textContent = labelText ?? '';
    _setHidden(parts.label, labelText == null);
    // A label floats in the field's outline unless the app said otherwise; the
    // CSS does the moving, driven by :focus-within and :placeholder-shown, so
    // typing raises it without the renderer hearing a keystroke.
    final floating = labelText != null && p['floatingLabel'] != false;
    parts.root.classList.toggle('dnn-textfield--floating', floating);
    // A field with no visible label still needs a name; the placeholder is
    // what the user sees, so it is what gets announced.
    final hintText = _optStr(p['hint'] ?? p['placeholder']);
    if (labelText == null && hintText != null) {
      parts.input.setAttribute('aria-label', hintText);
    } else {
      parts.input.removeAttribute('aria-label');
    }

    final hint = _optStr(p['hint'] ?? p['placeholder']);
    // :placeholder-shown is how the CSS knows the field is empty, and an empty
    // placeholder is not shown at all - so a floating label with no hint gets a
    // space to stand in for one. It is invisible either way: the floating rules
    // hide the placeholder until the field has focus.
    final placeholder = hint == null || hint.isEmpty
        ? (floating ? ' ' : '')
        : hint;
    parts.input.setAttribute('placeholder', placeholder);
    if (p['enabled'] == false) {
      parts.input.setAttribute('disabled', '');
    } else {
      parts.input.removeAttribute('disabled');
    }

    final input = parts.input;
    if (input.tagName.toLowerCase() != 'textarea') {
      // On every pass, not only the first: a show-password button changes
      // this while the caret is in the field.
      final type = p['obscureText'] == true ? 'password' : 'text';
      if (input.getAttribute('type') != type) input.setAttribute('type', type);
    }
    // Which keyboard a touch device raises. `inputmode` rather than the
    // input's `type`: an email or number input refuses the selection calls a
    // patched field relies on to keep its caret, validates on its own terms,
    // and a number input drops what it cannot parse. The keyboard is all the
    // protocol asked for.
    _attr(input, 'inputmode', switch (p['keyboardType']) {
      'number' => 'numeric',
      'decimal' => 'decimal',
      'email' => 'email',
      'phone' => 'tel',
      'url' => 'url',
      _ => null,
    });
    _attr(input, 'readonly', p['readOnly'] == true ? '' : null);
    _applyFieldLook(input as web.HTMLElement, p);
    final maxLength = _num(p['maxLength']);
    _attr(
      input,
      'maxlength',
      maxLength == null ? null : '${maxLength.toInt()}',
    );
    _attr(input, 'autocapitalize', _optStr(p['textCapitalization']));
    _set(input, 'text-align', _optStr(p['textAlign']));
    _attr(parts.root, 'data-tappable', p['tappable'] == true ? '' : null);
    if (p['tappable'] == true) {
      // It behaves as a button, so it should look like one under the pointer.
      _set(input, 'cursor', p['readOnly'] == true ? 'pointer' : null);
    } else {
      _set(input, 'cursor', null);
    }

    final prefix = parts.root.querySelector('[data-part="prefix"]');
    final prefixGlyph = _num(p['prefixIcon']);
    if (prefix != null && prefixGlyph != null) {
      prefix.textContent = _glyphText(prefixGlyph);
    }
    final suffix = parts.root.querySelector('[data-part="suffix"]');
    final suffixGlyph = _num(p['suffixIcon']);
    if (suffix != null && suffixGlyph != null) {
      suffix.textContent = _glyphText(suffixGlyph);
    }
    parts.root.classList.toggle('dnn-textfield--prefix', prefix != null);
    parts.root.classList.toggle('dnn-textfield--suffix', suffix != null);

    // Apply the value when the app changed it - a different value, or a bumped
    // controller version from a clear() after submitting, which the user's own
    // typing never does. A stale echo of the value the field already holds is
    // left alone so typing is never overwritten.
    final value = _optStr(p['initialValue']) ?? '';
    final version = '${p['valueVersion'] ?? ''}';
    if (initial ||
        parts.root.getAttribute('data-value') != value ||
        parts.root.getAttribute('data-version') != version) {
      if (_inputValue(parts.input) != value) _setInputValue(parts.input, value);
      parts.root.setAttribute('data-value', value);
      parts.root.setAttribute('data-version', version);
    }

    _applyFocusRequest(parts.input, parts.root, p);

    final errorText = _optStr(p['error']);
    parts.error.textContent = errorText ?? '';
    _setHidden(parts.error, errorText == null);
    kit.setTextFieldError(parts, errorText != null);
    // Invalid, and why. A red border says nothing to a screen reader.
    if (errorText != null) {
      parts.input.setAttribute('aria-invalid', 'true');
      if (fieldId != null) {
        parts.input.setAttribute('aria-describedby', 'dnn-error-$fieldId');
      }
    } else {
      parts.input.removeAttribute('aria-invalid');
      parts.input.removeAttribute('aria-describedby');
    }

    // The helper is the line under the field while nothing is wrong with it;
    // an error takes its place. It is made the first time a field has one, so
    // a field that never does keeps the markup its kit built.
    final helperText = _optStr(p['helper']);
    var helper = parts.root.querySelector('[data-part="helper"]');
    if (helper == null && helperText != null) {
      helper = _el('div', 'dnn-textfield__helper')
        ..setAttribute('data-part', 'helper');
      parts.root.appendChild(helper);
    }
    if (helper != null) {
      helper.textContent = helperText ?? '';
      final shown = helperText != null && errorText == null;
      _setHidden(helper, !shown);
      if (fieldId != null) {
        helper.id = 'dnn-helper-$fieldId';
        if (shown) parts.input.setAttribute('aria-describedby', helper.id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Patching
  // ---------------------------------------------------------------------------

  /// What a patched node's listeners read, kept per element.
  ///
  /// A listener is attached once, when the element is built, and the element
  /// then outlives the props it was built from. So nothing below closes over
  /// an event id: each handler looks up what the node says *now*.
  final Expando<_NodeState> _nodes = Expando('node');

  /// Applies [node]'s props to the element [before] produced, for the node
  /// types whose element is worth more than a rebuild.
  ///
  /// A box that is restyled can transition to its new look and keeps the
  /// pointer that is dragging it; a canvas keeps its surface, which is what
  /// lets a game send a frame per tick; a scroller keeps its offset; a select
  /// keeps focus. Answers false when the element cannot become [node], and the
  /// caller then builds a fresh one.
  bool _patchInPlace(web.Element existing, WidgetNode before, WidgetNode node) {
    final p = node.props;
    final state = _nodes[existing];
    switch (node.type) {
      case 'Box':
        if (state == null) return false;
        state.props = p;
        _applyFrame(existing, state, fresh: false);
      case 'Canvas':
        if (state == null) return false;
        state.props = p;
        _applyFrame(existing, state, fresh: false);
        _paintCanvas(existing, state);
      case 'Stack':
        _applyStack(existing, p);
      case 'Positioned':
        _applyPositioned(existing, p, fresh: false);
      case 'FlutterSlot':
        _applySlot(existing, p, fresh: false);
      case 'Scaffold':
        _applyScaffold(existing, p);
      case 'Scroll':
        if (state == null) return false;
        state.props = p;
        _applyScroll(existing, state);
      case 'Dropdown':
        if (state == null) return false;
        state.props = p;
        _applyDropdown(existing, state);
      case 'BottomNavigation':
        if (state == null || !_sameDestinations(before.props, p)) return false;
        state.props = p;
        _applyBottomNavigation(existing, p);
      case 'DatePicker':
      case 'TimePicker':
        if (state == null || !_patchPicker(existing, state, before.props, p)) {
          return false;
        }
      default:
        return false;
    }
    _syncHosted(existing, node, before.children ?? const []);
    if (node.type == 'Box' || node.type == 'Canvas') {
      _describeBox(existing, p, canvas: node.type == 'Canvas', fresh: false);
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Structure: scaffold, app bar, bottom bar, bottom navigation
  // ---------------------------------------------------------------------------

  /// The props a scaffold draws from, on build and on patch.
  ///
  /// Which child is the app bar, the bottom bar or the button is the
  /// stylesheet's business: each carries its own class, and the body is the
  /// child that carries none of them.
  void _applyScaffold(web.Element scaffold, Map<String, dynamic> p) {
    // A body that lays itself out against the screen - an Expanded, a Scroll,
    // a Stack - needs a scaffold exactly as tall as the screen rather than at
    // least that tall, and a body that fills what is left of it.
    scaffold.classList.toggle('dnn-scaffold--fixed', p['bodyScrolls'] == false);
    // The scaffold keeps clear of the notch and the home indicator unless the
    // app wants to draw under them.
    scaffold.classList.toggle('dnn-scaffold--edge', p['safeArea'] == false);
    final background = _optStr(p['backgroundColor']);
    _set(
      scaffold,
      'background',
      background == null ? null : cssColor(background),
    );
    _set(scaffold, 'color', background == null ? null : textOn(background));
  }

  /// The bar across the top: a leading button, the title, the actions.
  ///
  /// The kit builds the bar and its title; the rest is laid out around the
  /// title in the same element (see [WebStyleKit.appBarRow]). The node's
  /// children go into one host after the title - the actions, preceded by the
  /// title subtree when there is one, which the stylesheet then stretches into
  /// the title's place.
  web.Element _appBar(Map<String, dynamic> p) {
    final bar = kit.appBar(
      _str(p['title']),
      backgroundColor: _optStr(p['backgroundColor']),
    );
    final row = kit.appBarRow(bar);
    final title = row.firstElementChild;
    // The screen's name, and where a screen reader's "next heading" lands
    // first. Said with a role rather than an <h1> so the kit's markup, and
    // what its stylesheet does to it, stay as they are.
    title
      ?..setAttribute('role', 'heading')
      ..setAttribute('aria-level', '1');

    final foreground = _optStr(p['foregroundColor']);
    if (foreground != null) _style(bar, 'color', cssColor(foreground));
    final elevation = _num(p['elevation']);
    if (elevation != null) _style(bar, 'box-shadow', kit.shadow(elevation));
    if (p['centerTitle'] == true) bar.classList.add('dnn-appbar--center');

    final leading = _optStr(p['leading']);
    if (leading != null) {
      final (icon, name) = switch (leading) {
        'close' => (Icons.close, 'Close'),
        'menu' => (Icons.menu, 'Menu'),
        _ => (Icons.arrow_back, 'Back'),
      };
      final button = kit.iconButton(_glyphText(icon.codePoint))
        ..classList.add('dnn-appbar__leading')
        // An arrow that points back points the other way in a screen that
        // reads from the right; a cross and a menu have no direction to turn.
        ..classList.toggle('dnn-appbar__leading--back', icon == Icons.arrow_back)
        ..setAttribute('aria-label', name)
        ..setAttribute('title', name);
      final eventId = p['leadingEventId'];
      if (eventId is String) {
        button.addEventListener(
          'click',
          ((web.Event _) {
            handleEvent(eventId, const {});
          }).toJS,
        );
      }
      row.insertBefore(button, title);
    }

    if (p['hasTitleNode'] == true) {
      bar.classList.add('dnn-appbar--title-node');
      // The subtree is the title now. The text stays in the tree for a
      // renderer that cannot draw one, and stays out of the way here.
      if (title != null) _setHidden(title, true);
    }
    row.appendChild(_host(_el('div', 'dnn-appbar__actions')));
    return bar;
  }

  /// The destinations of an app: a bar of them along the bottom, or a rail of
  /// them down the leading edge.
  ///
  /// Each is a real button, so Tab reaches it and Enter chooses it, and the
  /// selected one says so with `aria-current` rather than only with colour.
  web.Element _bottomNavigation(Map<String, dynamic> p) {
    final rail = p['rail'] == true;
    // A div with the role rather than a <nav>: Materialize styles every nav
    // on the page as its own top bar.
    final nav = _el(
      'div',
      rail ? 'dnn-bottomnav dnn-bottomnav--rail' : 'dnn-bottomnav',
    )..setAttribute('role', 'navigation');
    final state = _nodes[nav] = _NodeState(p);
    final items = p['items'] is List ? p['items'] as List : const [];
    for (var i = 0; i < items.length; i++) {
      final index = i;
      final item = _el('button', 'dnn-bottomnav__item')
        ..setAttribute('type', 'button');
      final indicator = _el('span', 'dnn-bottomnav__indicator');
      indicator.appendChild(
        _el('i', 'material-icons')..setAttribute('aria-hidden', 'true'),
      );
      item
        ..appendChild(indicator)
        ..appendChild(_el('span', 'dnn-bottomnav__label'));
      item.addEventListener(
        'click',
        ((web.Event _) {
          final eventId = state.props['eventId'];
          if (eventId is String) handleEvent(eventId, {'index': index});
        }).toJS,
      );
      nav.appendChild(item);
    }
    _applyBottomNavigation(nav, p);
    return nav;
  }

  /// Whether two navigation nodes can share an element: the same number of
  /// destinations, laid out the same way.
  static bool _sameDestinations(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final was = before['items'];
    final now = after['items'];
    return was is List &&
        now is List &&
        was.length == now.length &&
        (before['rail'] == true) == (after['rail'] == true);
  }

  /// Labels, glyphs and which destination is selected.
  ///
  /// Patched rather than rebuilt so that choosing a destination with the
  /// keyboard leaves focus on the button that was pressed.
  void _applyBottomNavigation(web.Element nav, Map<String, dynamic> p) {
    final items = p['items'] is List ? p['items'] as List : const [];
    final selected = (_num(p['selectedIndex']) ?? 0).toInt();
    for (var i = 0; i < items.length && i < nav.children.length; i++) {
      final item = items[i];
      final button = nav.children.item(i)!;
      if (item is! Map) continue;
      final chosen = i == selected;
      button.classList.toggle('dnn-bottomnav__item--selected', chosen);
      _attr(button, 'aria-current', chosen ? 'page' : null);
      final glyph = _num(
        chosen ? item['selectedIcon'] ?? item['icon'] : item['icon'],
      );
      final text = glyph == null ? '' : _glyphText(glyph);
      final icon = button.querySelector('i');
      final label = button.querySelector('.dnn-bottomnav__label');
      // Written only when different: a destination that did not change is not
      // a mutation worth making on every render.
      if (icon != null && icon.textContent != text) icon.textContent = text;
      final name = _str(item['label']);
      if (label != null && label.textContent != name) label.textContent = name;
    }
  }

  // ---------------------------------------------------------------------------
  // Free-form composition: box, stack, scroll, icon
  // ---------------------------------------------------------------------------

  /// A box: size, space, paint and touch around at most one child.
  web.Element _box(Map<String, dynamic> p) {
    final box = _host(_el('div', 'dnn-box'));
    _applyFrame(box, _nodes[box] = _NodeState(p), fresh: true);
    return box;
  }

  /// Everything a box's props say, written as inline style and attributes.
  ///
  /// Runs on build and again on every patch, so each property the box owns is
  /// either set or cleared - a border the app took away has to go, not linger
  /// from the render before. [fresh] skips the clearing for an element that
  /// was just made and has nothing on it yet, which is most of the cost of a
  /// screen with a few hundred boxes.
  ///
  /// The box is a one-cell grid: a child with no alignment fills the cell,
  /// which is "the child fills the box's content area", and an alignment
  /// places it instead. A canvas is the same frame around a surface.
  void _applyFrame(web.Element box, _NodeState state, {required bool fresh}) {
    final p = state.props;
    void put(String property, String? value) {
      if (value != null) {
        _style(box, property, value);
      } else if (!fresh) {
        _set(box, property, null);
      }
    }

    String? px(Object? value) {
      final number = _num(value);
      return number == null ? null : '${number}px';
    }

    // Size.
    final width = _num(p['width']);
    final height = _num(p['height']);
    final expand = p['expand'];
    final ratio = _num(p['aspectRatio']);
    // A ratio derives one axis from the other, so with neither stated there
    // is nothing to derive from: the box then takes the width it is offered,
    // as Flutter's AspectRatio does.
    final fillWidth =
        expand == 'width' ||
        expand == 'both' ||
        (ratio != null && width == null && height == null && expand == null);
    final fillHeight = expand == 'height' || expand == 'both';
    final margin = _edges(p['margin']);
    // How "fill" is spelled depends on what the box is inside - a share of a
    // row, the whole of a column's width - so the stylesheet decides, from a
    // class. It needs the margins to leave room for them.
    if (!fresh || fillWidth) box.classList.toggle('dnn-fill-w', fillWidth);
    if (!fresh || fillHeight) box.classList.toggle('dnn-fill-h', fillHeight);
    put(
      '--dnn-mx',
      fillWidth && margin != null ? '${margin.$1 + margin.$3}px' : null,
    );
    put(
      '--dnn-my',
      fillHeight && margin != null ? '${margin.$2 + margin.$4}px' : null,
    );
    put('width', px(width));
    put('height', px(height));
    put('min-width', px(p['minWidth']));
    put('max-width', px(p['maxWidth']));
    put('min-height', px(p['minHeight']));
    put('max-height', px(p['maxHeight']));
    // A stated size is the size: a row short of room overflows, as it does on
    // the other renderers, rather than quietly squashing the box.
    put('flex-shrink', width != null || height != null ? '0' : null);
    put('aspect-ratio', ratio != null && ratio > 0 ? '$ratio' : null);

    // Space.
    put('padding', _edgesCss(_edges(p['padding'])));
    put('margin', _edgesCss(margin));
    final alignment = _pair(p['alignment']);
    put('justify-items', alignment == null ? null : _gridAlignX(alignment.$1));
    put('align-items', alignment == null ? null : _gridAlign(alignment.$2));

    // Paint.
    final color = _optStr(p['color']);
    put('background-color', color == null ? null : cssColor(color));
    // Children that state no colour read against the fill, as they do on a
    // card - unless the fill is mostly see-through, when what they are really
    // on is whatever lies behind the box.
    put('color', color != null && _mostlyOpaque(color) ? textOn(color) : null);
    put('background-image', _gradient(p['gradient']));
    final borderWidth = _num(p['borderWidth']);
    final borderColor = _optStr(p['borderColor']);
    put(
      'border',
      borderWidth == null && borderColor == null
          ? null
          : '${borderWidth ?? 1}px solid '
                '${borderColor == null ? 'currentColor' : cssColor(borderColor)}',
    );
    final radii = p['borderRadii'];
    put(
      'border-radius',
      p['shape'] == 'circle'
          ? '50%'
          : radii is List && radii.length == 4
          ? radii.map((r) => '${_num(r) ?? 0}px').join(' ')
          : px(p['borderRadius']),
    );
    final shadow = p['shadow'];
    put(
      'box-shadow',
      shadow is! Map
          ? null
          : '${_num(shadow['dx']) ?? 0}px ${_num(shadow['dy']) ?? 0}px '
                '${_num(shadow['blur']) ?? 0}px '
                '${cssColor(_str(shadow['color'], '#33000000'))}',
    );
    put('overflow', p['clip'] == true ? 'hidden' : null);
    final opacity = _num(p['opacity']);
    put('opacity', opacity == null ? null : '$opacity');
    final transform = p['transform'];
    put(
      'transform',
      transform is! Map
          ? null
          // Read right to left: scaled and turned about the centre, then
          // moved, so the movement is in the parent's pixels whatever the
          // turn.
          : 'translate(${_num(transform['dx']) ?? 0}px, '
                '${_num(transform['dy']) ?? 0}px) '
                'rotate(${_num(transform['rotate']) ?? 0}rad) '
                'scale(${_num(transform['scale']) ?? 1})',
    );

    // Motion. The browser does the animating: naming the properties here
    // means the next patch that writes a different value moves there.
    final animate = _num(p['animateMs']);
    put(
      'transition',
      animate == null || animate <= 0
          ? null
          : _animatedProperties
                .map((name) => '$name ${animate.toInt()}ms ${_timing(p)}')
                .join(', '),
    );

    // What it is to someone who cannot see it, and to the pointer.
    final tap = p['tapEventId'] is String;
    final doubleTap = p['doubleTapEventId'] is String;
    final hold = p['longPressEventId'] is String || p['dragData'] is String;
    final pan = p['panEventId'] is String;
    // What it is called and what it is are said once its children are in
    // place - see [_describeBox]. The keyboard reaches it either way.
    if (!fresh || tap) _attr(box, 'tabindex', tap ? '0' : null);
    if (!fresh || p['tooltip'] != null) {
      _attr(box, 'title', _optStr(p['tooltip']));
    }
    final ignored = p['ignorePointer'] == true;
    put('pointer-events', ignored ? 'none' : null);
    // `pointer-events` only turns the mouse and the finger away. The keyboard
    // and a screen reader are turned away in [_wire], and told so here.
    // Unavailable either way: nothing reaches it, or the app drew a button
    // that is switched off (`disabled`).
    final off = ignored || p['disabled'] == true;
    if (!fresh || off) _attr(box, 'aria-disabled', off ? 'true' : null);
    // A box that is on or off - a filter chip - is a toggle button.
    final on = p['selected'];
    if (!fresh || on is bool) {
      _attr(box, 'aria-pressed', on is bool ? '$on' : null);
    }
    if (!fresh || tap || doubleTap) {
      _attr(box, 'data-tap', tap || doubleTap ? '' : null);
    }
    if (!fresh || hold || pan) {
      _attr(box, 'data-gesture', hold || pan ? '' : null);
      // A pan is the box's to follow, so the browser must not scroll with it.
      box.classList.toggle('dnn-box--pan', pan);
      // Holding a finger down must not select the text underneath or raise
      // the system's own menu.
      box.classList.toggle('dnn-box--hold', hold);
    }
    final drop = p['dropEventId'] is String;
    if (!fresh || drop) _attr(box, 'data-drop', drop ? '' : null);
    final ripple = p['ripple'] == true;
    if (!fresh || ripple) box.classList.toggle('dnn-box--ripple', ripple);

    _wire(box, state);
  }

  /// The protocol's `semanticRole` as the ARIA role that says the same.
  static const Map<String, String> _ariaRoles = {
    'heading': 'heading',
    'button': 'button',
    'image': 'img',
    'progress': 'progressbar',
  };

  /// What inside a box takes a press of its own.
  static const String _pressable =
      'button, a[href], input, select, textarea, [data-tap], [role="button"]';

  /// Whether what a box says of itself has to be looked at again when only
  /// its children changed.
  static bool _describedByChildren(WidgetNode node) {
    if (node.type != 'Box') return false;
    final p = node.props;
    return p['tapEventId'] is String ||
        p['excludeSemantics'] == true ||
        (p['tooltip'] != null && p['semanticLabel'] == null);
  }

  /// What a box, or a canvas, is to someone who cannot see it.
  ///
  /// Runs once the children are in the document, on build and on patch,
  /// because two of the answers are about them. A box that is tapped is a
  /// button - focusable, announced as something to press, named by its label
  /// or else by the text inside it - unless something inside it is pressed in
  /// its own right: a button in a button is one control to a screen reader,
  /// so a card that holds one stays a group that happens to take a click. And
  /// a tooltip names a box that has no label and says nothing itself, where
  /// it would otherwise be only a `title` on something with no role to carry
  /// it.
  ///
  /// Each attribute is set or taken off, as in [_applyFrame]; [fresh] skips
  /// the box that says none of this, which is nearly every box.
  void _describeBox(
    web.Element box,
    Map<String, dynamic> p, {
    bool canvas = false,
    bool fresh = true,
  }) {
    final tap = p['tapEventId'] is String;
    final label = _optStr(p['semanticLabel']);
    final value = _optStr(p['semanticValue']);
    final stated = _ariaRoles[p['semanticRole']];
    final tooltip = _optStr(p['tooltip']);
    final live = p['liveRegion'] == true;
    final exclude = p['excludeSemantics'] == true;
    if (fresh &&
        !tap &&
        !live &&
        !exclude &&
        label == null &&
        value == null &&
        stated == null &&
        tooltip == null) {
      return;
    }
    final host = _childHost(box) ?? box;

    // Hidden first, so that what is hidden is not what names the box below.
    // Only what this put there is taken back: an icon hides itself.
    for (var i = 0; i < host.children.length; i++) {
      final child = host.children.item(i)!;
      if (exclude) {
        if (child.getAttribute('aria-hidden') != 'true') {
          child
            ..setAttribute('aria-hidden', 'true')
            ..setAttribute('data-excluded', '');
        }
      } else if (child.hasAttribute('data-excluded')) {
        child
          ..removeAttribute('aria-hidden')
          ..removeAttribute('data-excluded');
      }
    }

    final name = label ?? (tooltip != null && !_speaks(host) ? tooltip : null);
    final holdsControl =
        tap && stated == null && host.querySelector(_pressable) != null;
    final role =
        stated ??
        (tap
            ? (holdsControl ? 'group' : 'button')
            : name == null
            ? null
            // A drawing with a name is a picture, and so is whatever a
            // tooltip had to name; a box the app named is a group of what is
            // in it.
            : (canvas || label == null ? 'img' : 'group'));
    final progress = role == 'progressbar';
    _attr(box, 'role', role);
    _attr(box, 'aria-level', role == 'heading' ? '2' : null);
    // The state is said after the name ("Upload, 40%"), as on the other
    // renderers. `aria-valuetext` is where it belongs, but only a range is
    // read its value - so anything else carries it in its name as well, or as
    // its description where the name is the text inside.
    _attr(
      box,
      'aria-label',
      name == null
          ? null
          : (value == null || progress ? name : '$name, $value'),
    );
    _attr(box, 'aria-valuetext', value);
    _attr(
      box,
      'aria-description',
      value != null && name == null && !progress ? value : null,
    );
    // "40%" is also a number a progress bar can be drawn from by whatever is
    // reading it; a value that is not a percentage is only said.
    final percent = progress && value != null && value.endsWith('%')
        ? num.tryParse(value.substring(0, value.length - 1))
        : null;
    _attr(box, 'aria-valuemin', percent == null ? null : '0');
    _attr(box, 'aria-valuemax', percent == null ? null : '100');
    _attr(box, 'aria-valuenow', percent == null ? null : '$percent');
    _attr(box, 'aria-live', live ? 'polite' : null);
  }

  /// Whether anything under [element] would be read out: text, or something
  /// with a name of its own, that is not hidden from a screen reader.
  static bool _speaks(web.Node element) {
    final children = element.childNodes;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i)!;
      if (child.nodeType == web.Node.TEXT_NODE) {
        if ((child.textContent ?? '').trim().isNotEmpty) return true;
        continue;
      }
      if (!child.isA<web.Element>()) continue;
      final inner = child as web.Element;
      if (inner.getAttribute('aria-hidden') == 'true' ||
          inner.hasAttribute('hidden')) {
        continue;
      }
      if (inner.hasAttribute('aria-label') ||
          (inner.getAttribute('alt') ?? '').isNotEmpty ||
          inner.matches('input, select, textarea') ||
          _speaks(inner)) {
        return true;
      }
    }
    return false;
  }

  /// Says what a node that is not a box was told it is: a text that is a
  /// heading, an image that is a button.
  ///
  /// Only where the element does not already say what it is - a `<button>`
  /// is a button, and a tab list is not made a heading by being told so.
  void _applyRole(web.Element element, Map<String, dynamic> p) {
    final role = _ariaRoles[p['semanticRole']];
    if (role == null || element.hasAttribute('role')) return;
    if (element.matches('button, input, select, textarea, label')) return;
    // An `<img>` is already an image, and its `alt` its name.
    if (role == 'img' && element.tagName.toLowerCase() == 'img') return;
    element.setAttribute('role', role);
    // The app bar's title is the screen's first heading; these come under it.
    if (role == 'heading') element.setAttribute('aria-level', '2');
  }

  /// What a box with `animateMs` moves between rather than jumping.
  static const _animatedProperties = [
    'width',
    'height',
    'min-width',
    'max-width',
    'min-height',
    'max-height',
    'padding',
    'margin',
    'background-color',
    'color',
    'border-color',
    'border-width',
    'border-radius',
    'box-shadow',
    'opacity',
    'transform',
  ];

  /// Whether text over [color] is really over it, rather than over whatever
  /// shows through.
  static bool _mostlyOpaque(String color) {
    final hex = color.trim();
    if (hex.length != 9 || !hex.startsWith('#')) return true;
    final alpha = int.tryParse(hex.substring(1, 3), radix: 16);
    return alpha == null || alpha >= 0x80;
  }

  /// A protocol gradient as a CSS image.
  ///
  /// `begin` and `end` are alignments. Corner to corner and edge to edge are
  /// what CSS has words for and what nearly every gradient is; anything else
  /// becomes the angle of the line between the two points, which is exact for
  /// a square box and close for the rest. A radial gradient is centred on
  /// `begin` and reaches the nearest side, which is Flutter's default radius.
  static String? _gradient(Object? gradient) {
    if (gradient is! Map) return null;
    final colors = gradient['colors'];
    if (colors is! List || colors.isEmpty) return null;
    final stops = gradient['stops'];
    final parts = [
      for (var i = 0; i < colors.length; i++)
        cssColor('${colors[i]}') +
            (stops is List && i < stops.length && stops[i] is num
                ? ' ${(stops[i] as num) * 100}%'
                : ''),
    ];
    // One colour is a fill, which CSS will not take as a gradient.
    if (parts.length == 1) parts.add(parts.first);

    final begin = _pair(gradient['begin']);
    final end = _pair(gradient['end']);
    if (gradient['type'] == 'radial') {
      final (x, y) = begin ?? (0.0, 0.0);
      return 'radial-gradient(circle closest-side at '
          '${(x + 1) * 50}% ${(y + 1) * 50}%, ${parts.join(', ')})';
    }
    final (beginX, beginY) = begin ?? (-1.0, 0.0);
    final (endX, endY) = end ?? (1.0, 0.0);
    final dx = endX - beginX;
    final dy = endY - beginY;
    final String direction;
    if (dx.abs() == 2 && dy.abs() == 2) {
      direction =
          'to ${dy > 0 ? 'bottom' : 'top'} ${dx > 0 ? 'right' : 'left'}';
    } else {
      // CSS measures from "to top", clockwise.
      direction = '${math.atan2(dx, -dy) * 180 / math.pi}deg';
    }
    return 'linear-gradient($direction, ${parts.join(', ')})';
  }

  /// Children drawn over one another, in one grid cell.
  ///
  /// Every child that is not pinned shares the cell, so the largest of them
  /// is what sizes the stack and the alignment places the rest inside it. The
  /// pinned ones are taken out of that by the stylesheet. An alignment between
  /// the named points snaps to the nearest of start, centre and end, which is
  /// all a grid can be asked for.
  void _applyStack(web.Element stack, Map<String, dynamic> p) {
    final alignment = _pair(p['alignment']);
    final expand = p['fit'] == 'expand';
    _style(
      stack,
      'justify-items',
      expand
          ? 'stretch'
          // A stack that states no alignment is Flutter's: top *start*, which
          // follows the reading direction. One that states it names a side.
          : (alignment == null ? 'start' : _gridAlignX(alignment.$1)),
    );
    _style(
      stack,
      'align-items',
      expand ? 'stretch' : _gridAlign(alignment?.$2 ?? -1.0),
    );
    _set(stack, 'overflow', p['clip'] == false ? 'visible' : null);
  }

  /// The edges a pinned child names, and the size it states.
  void _applyPositioned(
    web.Element positioned,
    Map<String, dynamic> p, {
    required bool fresh,
  }) {
    for (final edge in const [
      'left',
      'top',
      'right',
      'bottom',
      'width',
      'height',
    ]) {
      final value = _num(p[edge]);
      if (value != null) {
        _style(positioned, edge, '${value}px');
      } else if (!fresh) {
        _set(positioned, edge, null);
      }
    }
  }

  /// The room a Flutter widget would have taken.
  void _applySlot(
    web.Element slot,
    Map<String, dynamic> p, {
    required bool fresh,
  }) {
    _style(slot, 'height', '${_num(p['height']) ?? 0}px');
    final width = _num(p['width']);
    if (width != null) {
      _style(slot, 'width', '${width}px');
    } else if (!fresh) {
      _set(slot, 'width', null);
    }
    _attr(slot, 'data-slot', _optStr(p['slotId']));
  }

  /// The text that draws the icon at [codepoint]: the character itself.
  ///
  /// The tree carries the codepoint of Flutter's `MaterialIcons` font, which
  /// is what `Icons.x` holds and what the native renderers draw from. The
  /// shell's icon font is that same file, so the number is the same picture
  /// here - an outlined, rounded or sharp one as much as a filled one.
  String _glyphText(num codepoint) => String.fromCharCode(codepoint.toInt());

  /// The glyph of an icon button or a floating one.
  ///
  /// The builder resolves the name it was given, so the codepoint is what to
  /// draw. A node with a name nobody resolved shows [fallback] rather than an
  /// empty button: Flutter's font does not draw a name as a ligature.
  String _buttonGlyph(Map<String, dynamic> p, IconData fallback) =>
      _glyphText(_num(p['iconCodepoint']) ?? fallback.codePoint);

  /// One glyph of an icon font.
  ///
  /// Drawn by codepoint: it is what the tree carries, and it works for any
  /// icon font, not only the one the shell ships. With no colour of its own
  /// the glyph is text, and takes the colour of whatever it is in - an app
  /// bar, a button, a box the app painted.
  web.Element _icon(Map<String, dynamic> p) {
    final codepoint = _num(p['codepoint']);
    final icon = _el(
      'i',
      'material-icons dnn-icon',
      text: codepoint == null ? '' : _glyphText(codepoint),
    );
    final size = _num(p['size']);
    if (size != null) _style(icon, 'font-size', '${size}px');
    final color = _optStr(p['color']);
    if (color != null) _style(icon, 'color', cssColor(color));
    final family = _optStr(p['fontFamily']);
    // Flutter's name for the default is the font the class already sets,
    // which CSS knows as "Material Icons".
    if (family != null && family != 'MaterialIcons') {
      _style(icon, 'font-family', '"${family.replaceAll('"', '')}"');
    }
    final label = _optStr(p['semanticLabel']);
    if (label != null) {
      icon
        ..setAttribute('role', 'img')
        ..setAttribute('aria-label', label);
    } else {
      // A private-use character means nothing read aloud.
      icon.setAttribute('aria-hidden', 'true');
    }
    return icon;
  }

  /// A scroller: a viewport that takes the room it is given, around content
  /// as long as its child.
  ///
  /// The element is patched, never replaced, when its props change - a new
  /// one would start at the top, and "refreshing" turning off should not cost
  /// the user their place in the list.
  web.Element _scroll(Map<String, dynamic> p) {
    final viewport = _el('div', 'dnn-scroll');
    viewport.appendChild(_host(_el('div', 'dnn-scroll__content')));
    _applyScroll(viewport, _nodes[viewport] = _NodeState(p));
    _reportScroll(viewport);
    return viewport;
  }

  /// Tells the app where [viewport] has been scrolled to, if its node asks
  /// (`scrollEventId`): when it comes to rest, and at most every 100 ms on the
  /// way. The browser fires `scroll` once a frame, and a report per frame
  /// would be a rebuild per frame for an app that listens.
  void _reportScroll(web.Element viewport) {
    Timer? settle;
    double? reported;
    var reportedAt = 0.0;
    void report() {
      // Read when it fires, not when it was built: the id is a prop like any
      // other, and a later build may have changed it or taken it away.
      final p = _nodes[viewport]?.props;
      final eventId = p?['scrollEventId'];
      if (eventId is! String || !viewport.isConnected) return;
      final horizontal = p!['axis'] == 'horizontal';
      // A reversed scroller, and a sideways one that reads from the right,
      // count from their far end in negative numbers.
      final offset =
          (horizontal ? viewport.scrollLeft : viewport.scrollTop).abs();
      if (offset == reported) return;
      reported = offset;
      reportedAt = web.window.performance.now();
      final length = horizontal ? viewport.clientWidth : viewport.clientHeight;
      final content = horizontal ? viewport.scrollWidth : viewport.scrollHeight;
      handleEvent(eventId, {
        'offset': offset,
        'maxExtent': math.max(0, content - length),
        'viewport': length,
      });
    }

    viewport.addEventListener(
      'scroll',
      ((web.Event _) {
        settle?.cancel();
        settle = Timer(const Duration(milliseconds: 120), report);
        if (web.window.performance.now() - reportedAt >= 100) report();
      }).toJS,
    );
  }

  void _applyScroll(web.Element viewport, _NodeState state) {
    final p = state.props;
    final horizontal = p['axis'] == 'horizontal';
    final reverse = p['reverse'] == true;
    viewport.classList.toggle('dnn-scroll--horizontal', horizontal);
    // Reversed, the viewport lays its content out from the far end, which is
    // also where the browser then starts the scroll position - a chat that
    // opens on its newest message, with no scripting.
    viewport.classList.toggle('dnn-scroll--reverse', reverse);
    viewport.classList.toggle('dnn-scroll--shrink', p['shrinkWrap'] == true);
    final content = _childHost(viewport);
    if (content != null)
      _set(content, 'padding', _edgesCss(_edges(p['padding'])));

    // Pull-to-refresh is for a list read from the top down.
    final refreshes = p['refreshEventId'] is String && !horizontal && !reverse;
    var indicator = viewport.querySelector(':scope > .dnn-scroll__refresh');
    if (refreshes && indicator == null) {
      indicator = _el('div', 'dnn-scroll__refresh')
        ..setAttribute('aria-hidden', 'true');
      final badge = _el('div', 'dnn-scroll__badge');
      badge.appendChild(_el('div', 'dnn-spinner'));
      indicator.appendChild(badge);
      viewport.insertBefore(indicator, viewport.firstChild);
      _wirePullToRefresh(viewport, state);
    }
    if (indicator != null) {
      _setHidden(indicator, !refreshes);
      final refreshing = refreshes && p['refreshing'] == true;
      indicator.classList.toggle('dnn-scroll__refresh--on', refreshing);
      indicator
          .querySelector('.dnn-spinner')
          ?.classList
          .toggle('dnn-animate', refreshing && animations);
    }
    viewport.classList.toggle('dnn-scroll--refreshable', refreshes);
    _applyScrollAsk(viewport, p, horizontal: horizontal, reverse: reverse);
  }

  /// Pull-to-refresh, which a browser does not have for anything but the
  /// page itself.
  ///
  /// So it is done by hand, and kept small: a finger that goes down while the
  /// scroller is at its top and then moves down drags a spinner into view, at
  /// half the finger's speed; letting go past [_pullThreshold] sends the
  /// refresh event, and letting go short of it puts the spinner away. The
  /// spinner is otherwise the tree's: it shows for as long as `refreshing` is
  /// true, whoever started the refresh.
  ///
  /// Touch only - there is no such gesture with a mouse, where a wheel at the
  /// top of a list is just a wheel - and touch events rather than pointer
  /// events, because a browser that decides the finger is scrolling cancels
  /// the pointer, while a `touchmove` can still say "this one is mine".
  void _wirePullToRefresh(web.Element viewport, _NodeState state) {
    if (state.pulls) return;
    state.pulls = true;

    void show(double pull) {
      final badge = viewport.querySelector('.dnn-scroll__badge');
      if (badge == null) return;
      state.pull = pull;
      if (pull <= 0) {
        // Back to what the stylesheet and `refreshing` say.
        _set(badge, 'transform', null);
        _set(badge, 'opacity', null);
        _set(badge, 'transition', null);
        return;
      }
      _style(badge, 'transition', 'none');
      _style(badge, 'transform', 'translateY(${pull - 40}px)');
      _style(badge, 'opacity', '${math.min(1.0, pull / _pullThreshold)}');
    }

    bool live() =>
        state.props['refreshEventId'] is String &&
        state.props['refreshing'] != true &&
        viewport.classList.contains('dnn-scroll--refreshable');

    viewport.addEventListener(
      'touchstart',
      ((web.TouchEvent event) {
        final touch = event.touches.item(0);
        state.pullStart = live() && touch != null && viewport.scrollTop <= 0
            ? touch.clientY.toDouble()
            : null;
      }).toJS,
    );
    viewport.addEventListener(
      'touchmove',
      ((web.TouchEvent event) {
        final start = state.pullStart;
        final touch = event.touches.item(0);
        if (start == null || touch == null) return;
        final distance = (touch.clientY - start) / 2;
        if (distance <= 0 || viewport.scrollTop > 0) {
          // Scrolling the list after all, which is the browser's to do.
          if (viewport.scrollTop > 0) state.pullStart = null;
          show(0);
          return;
        }
        // Otherwise the browser would rubber-band, or refresh the page.
        if (event.cancelable) event.preventDefault();
        show(math.min(distance, _pullThreshold * 1.5));
      }).toJS,
      web.AddEventListenerOptions(passive: false),
    );
    void end(bool released) {
      final pulled = state.pull;
      state.pullStart = null;
      show(0);
      final eventId = state.props['refreshEventId'];
      if (released && pulled >= _pullThreshold && eventId is String && live()) {
        handleEvent(eventId, const {});
      }
    }

    viewport.addEventListener(
      'touchend',
      ((web.TouchEvent _) => end(true)).toJS,
    );
    viewport.addEventListener(
      'touchcancel',
      ((web.TouchEvent _) => end(false)).toJS,
    );
  }

  /// How far the spinner is pulled before letting go refreshes.
  static const double _pullThreshold = 64;

  /// Scroll positions asked for during this render, applied once the DOM
  /// shows the whole tree.
  final List<void Function()> _scrollAsks = [];

  /// Moves a scroller to where the app asked, when the ask is a new one.
  ///
  /// "Scroll to here" is a moment rather than a state, so it travels as an
  /// offset and a version, and the version last honoured is kept on the
  /// element - the same trick a text field's `focusVersion` uses. Not now,
  /// either: an element built by this render has no layout yet, and a scroll
  /// position set on one is simply dropped.
  void _applyScrollAsk(
    web.Element viewport,
    Map<String, dynamic> p, {
    bool horizontal = false,
    bool reverse = false,
  }) {
    final offset = _num(p['scrollOffset']);
    if (offset == null) return;
    final version = '${p['scrollVersion'] ?? 0}';
    if (viewport.getAttribute('data-scroll-version') == version) return;
    viewport.setAttribute('data-scroll-version', version);
    _scrollAsks.add(() {
      if (!viewport.isConnected) return;
      // A reversed scroller counts from its far end, in negative numbers.
      final position = reverse ? -offset : offset;
      if (horizontal) {
        // So does one that reads from the right: it starts at its right-hand
        // end, and `scrollLeft` runs negative from there. Reversed as well,
        // the two turn it back.
        viewport.scrollLeft = _rtl ? -position : position;
      } else {
        viewport.scrollTop = position;
      }
    });
  }

  void _applyScrollAsks() {
    if (_scrollAsks.isEmpty) return;
    final asks = List.of(_scrollAsks);
    _scrollAsks.clear();
    for (final ask in asks) {
      ask();
    }
  }

  // ---------------------------------------------------------------------------
  // Touch: taps, presses, pans, drag and drop, measuring
  // ---------------------------------------------------------------------------

  /// How far a pointer may wander and still be a tap or a press.
  static const double _touchSlop = 4;

  /// How long a pointer is held before it is a long press.
  static const Duration _holdTime = Duration(milliseconds: 500);

  /// How long a second tap has to arrive to make a double tap.
  static const Duration _doubleTapTime = Duration(milliseconds: 300);

  /// Attaches the listeners [state]'s props call for, each kind once.
  ///
  /// Called on build and on every patch: a box that gains a gesture gains the
  /// listener then, and one that loses a gesture keeps a listener that finds
  /// nothing to do. Most boxes are only paint and get none at all.
  void _wire(web.Element box, _NodeState state) {
    final p = state.props;
    if (!state.clicks &&
        (p['tapEventId'] is String || p['doubleTapEventId'] is String)) {
      state.clicks = true;
      box.addEventListener(
        'click',
        ((web.MouseEvent event) => _onClick(box, state, event)).toJS,
      );
      box.addEventListener(
        'keydown',
        ((web.KeyboardEvent event) {
          // Enter and Space press a button, and this is one. Only when the
          // key was pressed on the box itself: a field inside it wants its
          // own Enter and its own spaces.
          if (event.key != 'Enter' && event.key != ' ') return;
          if (event.target != box) return;
          final eventId = state.props['tapEventId'];
          if (eventId is! String) return;
          // Space would otherwise scroll the page as well.
          event.preventDefault();
          handleEvent(eventId, _centre(box));
        }).toJS,
      );
    }
    if (!state.shut && p['ignorePointer'] == true) {
      state.shut = true;
      // On the way down, before anything inside hears it: a press that came
      // from no pointer - Enter on a focused button, a screen reader's
      // activate - is refused the same as a finger is. Tab is let through so
      // the keyboard can still leave.
      void refuse(web.Event event) {
        if (state.props['ignorePointer'] != true) return;
        if (event.isA<web.KeyboardEvent>() &&
            (event as web.KeyboardEvent).key == 'Tab') {
          return;
        }
        event
          ..preventDefault()
          ..stopImmediatePropagation();
      }

      final capture = web.AddEventListenerOptions(capture: true);
      box.addEventListener('click', refuse.toJS, capture);
      box.addEventListener('keydown', refuse.toJS, capture);
    }
    if (!state.pointers &&
        (p['longPressEventId'] is String ||
            p['panEventId'] is String ||
            p['dragData'] is String)) {
      state.pointers = true;
      box.addEventListener(
        'pointerdown',
        ((web.PointerEvent event) => _onPointerDown(box, state, event)).toJS,
      );
      box.addEventListener(
        'pointermove',
        ((web.PointerEvent event) => _onPointerMove(box, state, event)).toJS,
      );
      box.addEventListener(
        'pointerup',
        ((web.PointerEvent event) => _onPointerUp(box, state, event)).toJS,
      );
      box.addEventListener(
        'pointercancel',
        ((web.PointerEvent event) => _onPointerUp(
          box,
          state,
          event,
          cancelled: true,
        )).toJS,
      );
      // The browser's own drag - of an image, of selected text - would take
      // the pointer away half way through ours.
      box.addEventListener(
        'dragstart',
        ((web.Event event) => event.preventDefault()).toJS,
      );
      // A touch that has become a drag is ours: without this the first move
      // after picking something up would scroll the page out from under it.
      // Before the pick-up it is left alone, so a list of draggable rows
      // still scrolls under a finger that does not wait.
      box.addEventListener(
        'touchmove',
        ((web.Event event) {
          if (_drag?.source == box && event.cancelable) event.preventDefault();
        }).toJS,
        web.AddEventListenerOptions(passive: false),
      );
      box.addEventListener(
        'contextmenu',
        ((web.Event event) {
          // A long press with a finger also asks for the context menu; the
          // press was the gesture, so the menu is not wanted.
          if (state.held) event.preventDefault();
        }).toJS,
      );
    }
    if (!state.observed && p['sizeEventId'] is String) {
      state.observed = true;
      _resizes.observe(box);
    }
  }

  /// A point in [box]'s own pixels, from one in the window's.
  Map<String, dynamic> _local(web.Element box, num clientX, num clientY) {
    final rect = box.getBoundingClientRect();
    return {'x': clientX - rect.left, 'y': clientY - rect.top};
  }

  /// The middle of [box]: where a press that had no pointer - the keyboard's,
  /// a screen reader's - is said to have landed.
  Map<String, dynamic> _centre(web.Element box) {
    final rect = box.getBoundingClientRect();
    return {'x': rect.width / 2, 'y': rect.height / 2};
  }

  /// Whether an event that started at [target] belongs to [box], rather than
  /// to something inside it matching [selector] that has its own use for it.
  ///
  /// Events bubble, so a tap on a button inside a tappable box reaches both.
  /// On the other renderers the innermost one wins; this is that rule.
  bool _owns(web.Element box, web.EventTarget? target, String selector) {
    if (target == null || !target.isA<web.Element>()) return true;
    final nearest = (target as web.Element).closest(selector);
    return nearest == null || nearest == box || !box.contains(nearest);
  }

  void _onClick(web.Element box, _NodeState state, web.MouseEvent event) {
    final tap = state.props['tapEventId'];
    final doubleTap = state.props['doubleTapEventId'];
    if (tap is! String && doubleTap is! String) return;
    if (!_owns(
      box,
      event.target,
      'button, a[href], input, select, textarea, label, [data-tap]',
    )) {
      return;
    }
    // The click that ends a pan, a long press or a drag is not a tap.
    if (state.swallowClick) {
      state.swallowClick = false;
      return;
    }
    // `detail` counts the pointer's clicks, so zero is a click nothing
    // pointed at: element.click(), which is how assistive technology presses.
    final point = event.detail == 0
        ? _centre(box)
        : _local(box, event.clientX, event.clientY);

    if (doubleTap is! String) {
      handleEvent(tap as String, point);
      return;
    }
    final now = event.timeStamp.toDouble();
    final last = state.lastTap;
    if (last != null && now - last < _doubleTapTime.inMilliseconds) {
      state.lastTap = null;
      state.tapTimer?.cancel();
      handleEvent(doubleTap, point);
      return;
    }
    state.lastTap = now;
    if (tap is String) {
      // A box that listens for both cannot know which this is until the
      // second tap has had its chance - the same wait Flutter imposes.
      state.tapTimer = Timer(_doubleTapTime, () {
        final eventId = state.props['tapEventId'];
        if (eventId is String) handleEvent(eventId, point);
      });
    }
  }

  void _onPointerDown(
    web.Element box,
    _NodeState state,
    web.PointerEvent event,
  ) {
    final p = state.props;
    final longPress = p['longPressEventId'] is String;
    final pan = p['panEventId'] is String;
    final draggable = p['dragData'] is String;
    if (!longPress && !pan && !draggable) return;
    // Only the main button, and only one pointer at a time.
    if (event.button != 0 || state.pointer != null) return;
    if (!_owns(box, event.target, '[data-gesture], input, select, textarea')) {
      return;
    }
    state
      ..pointer = event.pointerId
      ..touch = event.pointerType != 'mouse'
      ..downX = event.clientX.toDouble()
      ..downY = event.clientY.toDouble()
      ..lastX = event.clientX.toDouble()
      ..lastY = event.clientY.toDouble()
      ..lastTime = event.timeStamp.toDouble()
      ..vx = 0
      ..vy = 0
      ..moved = false
      ..panning = false
      ..held = false
      ..swallowClick = false;
    if (pan) {
      // So the pan carries on when the pointer leaves the box. A pointer the
      // browser does not know - a synthetic one - cannot be captured, and
      // does not need to be.
      try {
        (box as web.HTMLElement).setPointerCapture(event.pointerId);
      } catch (_) {}
    }
    // A finger picks something up by holding it, so that a swipe across a
    // list of draggable things still scrolls the list. A mouse has no such
    // conflict and drags as soon as it moves.
    if (longPress || (draggable && state.touch)) {
      state.holdTimer?.cancel();
      state.holdTimer = Timer(_holdTime, () => _onHold(box, state));
    }
  }

  void _onHold(web.Element box, _NodeState state) {
    if (state.pointer == null || state.moved) return;
    state.held = true;
    final p = state.props;
    if (p['dragData'] is String && state.touch) {
      _beginDrag(box, state, state.pointer!, state.lastX, state.lastY);
      return;
    }
    final eventId = p['longPressEventId'];
    if (eventId is String) {
      handleEvent(eventId, _local(box, state.downX, state.downY));
    }
  }

  void _onPointerMove(
    web.Element box,
    _NodeState state,
    web.PointerEvent event,
  ) {
    if (state.pointer != event.pointerId || _drag != null) return;
    final x = event.clientX.toDouble();
    final y = event.clientY.toDouble();
    final p = state.props;
    if (!state.moved) {
      final travelled = math.sqrt(
        math.pow(x - state.downX, 2) + math.pow(y - state.downY, 2),
      );
      if (travelled <= _touchSlop) return;
      state.moved = true;
      state.holdTimer?.cancel();
      if (state.held) return;
      if (p['dragData'] is String && !state.touch) {
        _beginDrag(box, state, event.pointerId, x, y);
        return;
      }
      final eventId = p['panEventId'];
      if (eventId is String) {
        state.panning = true;
        // The pan began where the pointer went down, not where it had got to
        // by the time it was clear this was a pan.
        handleEvent('${eventId}_start', {
          ..._local(box, state.downX, state.downY),
          'dx': 0.0,
          'dy': 0.0,
          'vx': 0.0,
          'vy': 0.0,
        });
        state
          ..lastX = state.downX
          ..lastY = state.downY;
      }
    }
    if (!state.panning) return;
    final eventId = p['panEventId'];
    if (eventId is! String) return;
    final dx = x - state.lastX;
    final dy = y - state.lastY;
    final now = event.timeStamp.toDouble();
    final elapsed = now - state.lastTime;
    if (elapsed > 0) {
      // Pixels per second, smoothed a little: the last pair of events before
      // a release is often a millisecond apart and says nothing on its own.
      state
        ..vx = 0.6 * (dx / elapsed * 1000) + 0.4 * state.vx
        ..vy = 0.6 * (dy / elapsed * 1000) + 0.4 * state.vy;
    }
    state
      ..lastX = x
      ..lastY = y
      ..lastTime = now;
    handleEvent('${eventId}_update', {
      ..._local(box, x, y),
      'dx': dx,
      'dy': dy,
      'vx': state.vx,
      'vy': state.vy,
    });
  }

  void _onPointerUp(
    web.Element box,
    _NodeState state,
    web.PointerEvent event, {
    bool cancelled = false,
  }) {
    if (state.pointer != event.pointerId) return;
    state.pointer = null;
    state.holdTimer?.cancel();
    // The drag has the document's pointer events and ends itself.
    if (_drag?.source == box) return;
    if (state.panning) {
      state.panning = false;
      state.swallowClick = !cancelled;
      final eventId = state.props['panEventId'];
      if (eventId is String) {
        // A pointer that stopped before it lifted was not flung.
        final rested = event.timeStamp - state.lastTime > 100;
        handleEvent('${eventId}_end', {
          ..._local(box, event.clientX, event.clientY),
          'dx': 0.0,
          'dy': 0.0,
          'vx': rested || cancelled ? 0.0 : state.vx,
          'vy': rested || cancelled ? 0.0 : state.vy,
        });
      }
    } else if (state.held) {
      state.swallowClick = !cancelled;
    }
  }

  /// The drag in progress, if there is one. One pointer, one drag.
  _Drag? _drag;

  /// Picks [box] up.
  ///
  /// Pointer events rather than the browser's drag and drop, which does not
  /// exist for touch and cannot be styled where it does exist. What follows
  /// the pointer is a copy of the box; what is under the pointer is asked of
  /// the document on every move, so a drop target is any box that says it is
  /// one - no registration, and a target built mid-drag works.
  ///
  /// The listeners go on the document for the length of the drag: a render
  /// the drag itself causes (a hover highlight, say) may replace the box that
  /// was picked up, and a listener on it would go with it and leave the copy
  /// stranded on screen.
  void _beginDrag(
    web.Element box,
    _NodeState state,
    int pointer,
    double x,
    double y,
  ) {
    final data = state.props['dragData'];
    if (data is! String || _drag != null) return;
    final rect = box.getBoundingClientRect();
    final ghost = box.cloneNode(true) as web.HTMLElement
      ..removeAttribute('id')
      ..classList.add('dnn-drag-ghost');
    // The copy lives outside the app's root, where the reconciler will not
    // sweep it up - and so outside the theme, which it is handed here.
    final theme = (rootElement as web.HTMLElement).style.cssText;
    ghost.style.cssText =
        '$theme;${ghost.style.cssText};'
        'position:fixed;left:0;top:0;margin:0;'
        'width:${rect.width}px;height:${rect.height}px;'
        // Inline, not left to the stylesheet: a copy that caught the pointer
        // would hide every drop target under it.
        'pointer-events:none;z-index:1000;';
    web.document.body?.appendChild(ghost);
    box.classList.add('dnn-box--dragging');

    final drag = _drag = _Drag(
      source: box,
      state: state,
      data: data,
      ghost: ghost,
      pointer: pointer,
      grabX: x - rect.left,
      grabY: y - rect.top,
    );
    drag
      ..onMove = ((web.PointerEvent event) => _onDragMove(event)).toJS
      ..onUp = ((web.PointerEvent event) => _endDrag(event, drop: true)).toJS
      ..onCancel = ((web.PointerEvent event) => _endDrag(
        event,
        drop: false,
      )).toJS;
    web.document
      ..addEventListener('pointermove', drag.onMove)
      ..addEventListener('pointerup', drag.onUp)
      ..addEventListener('pointercancel', drag.onCancel);
    _moveDrag(x, y);
  }

  void _onDragMove(web.PointerEvent event) {
    if (_drag?.pointer != event.pointerId) return;
    _moveDrag(event.clientX.toDouble(), event.clientY.toDouble());
  }

  /// Moves the copy to the pointer and tells the targets it entered and left.
  void _moveDrag(double x, double y) {
    final drag = _drag;
    if (drag == null) return;
    _style(
      drag.ghost,
      'transform',
      'translate(${x - drag.grabX}px, ${y - drag.grabY}px)',
    );
    // The copy lets the pointer through, so this finds what is under it.
    var over = web.document.elementFromPoint(x, y)?.closest('[data-drop]');
    // Nothing is dropped on itself.
    if (over == drag.source) over = null;
    if (over == drag.over) return;
    _hover(drag.over, false);
    drag.over = over;
    _hover(over, true);
  }

  void _hover(web.Element? target, bool over) {
    if (target == null) return;
    final eventId = _nodes[target]?.props['dropEventId'];
    if (eventId is String) handleEvent('${eventId}_hover', {'over': over});
  }

  void _endDrag(web.PointerEvent event, {required bool drop}) {
    final drag = _drag;
    if (drag == null || drag.pointer != event.pointerId) return;
    _drag = null;
    web.document
      ..removeEventListener('pointermove', drag.onMove)
      ..removeEventListener('pointerup', drag.onUp)
      ..removeEventListener('pointercancel', drag.onCancel);
    drag.ghost.remove();
    drag.source.classList.remove('dnn-box--dragging');
    drag.state
      ..pointer = null
      ..swallowClick = drop;
    final target = drag.over;
    if (target == null) return;
    _hover(target, false);
    final eventId = _nodes[target]?.props['dropEventId'];
    if (drop && eventId is String) handleEvent(eventId, {'data': drag.data});
  }

  /// Watches every element that has to know its own size: a box that reports
  /// it, a canvas that draws to it, the bottom bar the floating button clears.
  ///
  /// One observer for all of them. It fires once an element is first laid out
  /// and again whenever its size changes, which is exactly when the protocol
  /// says a size is reported.
  late final web.ResizeObserver _resizes = web.ResizeObserver(
    ((JSArray<web.ResizeObserverEntry> entries, web.ResizeObserver _) {
      for (final entry in entries.toDart) {
        _onResize(entry);
      }
    }).toJS,
  );

  void _onResize(web.ResizeObserverEntry entry) {
    final element = entry.target;
    // The border box: what the element takes up, padding and border included,
    // which is the size the app gave it.
    final boxes = entry.borderBoxSize.toDart;
    final width = boxes.isEmpty
        ? entry.contentRect.width.toDouble()
        : boxes.first.inlineSize.toDouble();
    final height = boxes.isEmpty
        ? entry.contentRect.height.toDouble()
        : boxes.first.blockSize.toDouble();

    final state = _nodes[element];
    if (state == null) {
      // The bottom bar: published on the scaffold, where the floating button
      // can read how far up it has to sit.
      final scaffold = element.parentElement;
      if (scaffold != null) {
        _style(scaffold, '--dnn-bottombar-height', '${height}px');
        // And on the overlay around the scaffold, where a snackbar - drawn
        // beside the scaffold, not in it - can read it to sit above the bar.
        final overlay = scaffold.parentElement;
        if (overlay != null && overlay.classList.contains('dnn-overlay')) {
          _style(overlay, '--dnn-bottombar-height', '${height}px');
        }
      }
      return;
    }
    // Out of the document, or hidden: it has no size, rather than a size of
    // nothing.
    if (!element.isConnected) return;
    state
      ..width = width
      ..height = height;
    if (state.surface != null &&
        (width != state.paintedWidth || height != state.paintedHeight)) {
      _paintCanvas(element, state);
    }
    final eventId = state.props['sizeEventId'];
    if (eventId is! String) return;
    if (width == state.reportedWidth && height == state.reportedHeight) return;
    state
      ..reportedWidth = width
      ..reportedHeight = height;
    handleEvent(eventId, {'width': width, 'height': height});
  }

  // ---------------------------------------------------------------------------
  // Canvas
  // ---------------------------------------------------------------------------

  /// A surface drawn by a list of commands: a box-shaped frame around a
  /// `<canvas>`, with the node's child, if it has one, laid over the top.
  ///
  /// The frame is sized like a box and the surface fills it. What the frame
  /// came to is only known once the browser has laid it out, so a canvas with
  /// a stated width and height is drawn straight away and any other is drawn
  /// when the size arrives (see [_onResize]) - and again whenever it changes.
  web.Element _canvas(Map<String, dynamic> p) {
    final frame = _el('div', 'dnn-canvas');
    final surface =
        web.document.createElement('canvas') as web.HTMLCanvasElement
          ..className = 'dnn-canvas__surface';
    frame
      ..appendChild(surface)
      ..appendChild(_host(_el('div', 'dnn-canvas__child')));
    final state = _nodes[frame] = _NodeState(p)..surface = surface;
    _applyFrame(frame, state, fresh: true);
    if (!state.observed) {
      state.observed = true;
      _resizes.observe(frame);
    }
    _paintCanvas(frame, state);
    return frame;
  }

  /// Replays the commands into the surface the canvas already has.
  ///
  /// This is the whole cost of a frame: no element is made, none is replaced.
  /// The backing store is the logical size times the device's pixel ratio, and
  /// the context is scaled by the same, so commands stay in logical pixels and
  /// the picture stays sharp on a dense screen. The store is only resized when
  /// the size really changed - assigning a canvas its own width clears it and
  /// reallocates it, which is not something to do sixty times a second.
  void _paintCanvas(web.Element frame, _NodeState state) {
    final surface = state.surface;
    if (surface == null) return;
    final p = state.props;
    // What the app stated outranks what was measured: after a patch the
    // measurement is still the old one, until the browser lays out again.
    final width = _num(p['width']) ?? state.width ?? 0;
    final height = _num(p['height']) ?? state.height ?? 0;
    if (width <= 0 || height <= 0) return;
    final ratio = math.max(1.0, web.window.devicePixelRatio.toDouble());
    final pixelWidth = (width * ratio).round();
    final pixelHeight = (height * ratio).round();
    if (surface.width != pixelWidth) surface.width = pixelWidth;
    if (surface.height != pixelHeight) surface.height = pixelHeight;
    state
      ..paintedWidth = width
      ..paintedHeight = height;

    final context = surface.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) return;
    context
      ..setTransform(ratio.toJS, 0, 0, ratio, 0, 0)
      ..clearRect(0, 0, width, height);
    final commands = p['commands'];
    final paints = p['paints'];
    if (commands is! List) return;
    // Text with no colour of its own is the theme's text, so a picture drawn
    // without one reads on a dark surface as it does on a light one.
    final dark = theme.isDark(platformIsDark: _prefersDark);
    _replayCanvasCommands(
      context,
      commands,
      paints is List ? paints : const [],
      ink: dark ? theme.dark.text : theme.text,
    );
  }

  /// Redraws every canvas, for a change no canvas can see on its own: the
  /// window moving to a screen of another density, or the page being zoomed.
  void _repaintCanvases() {
    final frames = rootElement.querySelectorAll('.dnn-canvas');
    for (var i = 0; i < frames.length; i++) {
      final frame = frames.item(i)! as web.Element;
      final state = _nodes[frame];
      if (state != null) _paintCanvas(frame, state);
    }
  }

  // ---------------------------------------------------------------------------
  // Choosing: dropdown, date and time pickers
  // ---------------------------------------------------------------------------

  /// One of a list, chosen from the browser's own menu: a `<select>`, which
  /// brings the keyboard, the screen reader and the phone's native wheel with
  /// it, dressed to match a text field.
  web.Element _dropdown(Map<String, dynamic> p) {
    final root = _el('div', 'dnn-dropdown');
    final label = _el('label', 'dnn-dropdown__label');
    final field = _el('div', 'dnn-dropdown__field');
    // `browser-default` is Materialize's word for "leave this select alone":
    // without it that stylesheet hides every select, expecting its JavaScript
    // to draw a replacement.
    final select = web.document.createElement('select') as web.HTMLSelectElement
      ..className = 'dnn-dropdown__select browser-default';
    final error = _el('div', 'dnn-dropdown__error');
    field.appendChild(select);
    root
      ..appendChild(label)
      ..appendChild(field)
      ..appendChild(error);

    final state = _nodes[root] = _NodeState(p);
    select.addEventListener(
      'change',
      ((web.Event _) {
        final now = state.props;
        final eventId = now['eventId'];
        // The hint, when it is shown, is the first option and not an item.
        final index =
            select.selectedIndex - (state.placeholder == null ? 0 : 1);
        if (eventId is! String || index < 0) return;
        handleEvent(eventId, {..._data(now), 'index': index});
      }).toJS,
    );
    _applyDropdown(root, state);
    return root;
  }

  /// The props a dropdown draws from, on build and on patch.
  ///
  /// Patched because the element is the one the user is in: choosing an item
  /// re-renders the app, and a rebuilt select would drop focus on the way.
  void _applyDropdown(web.Element root, _NodeState state) {
    final p = state.props;
    final label = root.children.item(0)!;
    final select = root.querySelector('select')! as web.HTMLSelectElement;
    final error = root.children.item(2)!;

    final fieldId = _optStr(p['eventId']) ?? _optStr(p['id']);
    if (fieldId != null) {
      select.id = 'dnn-select-$fieldId';
      (label as web.HTMLLabelElement).htmlFor = select.id;
      error.id = 'dnn-error-$fieldId';
    }
    final labelText = _optStr(p['label']);
    final hint = _optStr(p['hint']);
    label.textContent = labelText ?? '';
    _setHidden(label, labelText == null);
    // With no visible label the hint is the only name the control has.
    _attr(select, 'aria-label', labelText == null ? hint : null);
    root.classList.toggle('dnn-dropdown--underlined', p['outlined'] == false);

    // Nothing chosen yet shows the hint, as an option that cannot be chosen
    // back. Once something is chosen the option goes: it was never an item.
    final items = _strings(p['items']);
    final chosen = _num(p['selectedIndex'])?.toInt();
    final placeholder = chosen == null ? (hint ?? '') : null;
    if (select.options.length == 0 ||
        placeholder != state.placeholder ||
        !_valueEqual(items, state.items)) {
      state
        ..items = items
        ..placeholder = placeholder;
      while (select.firstChild != null) {
        select.removeChild(select.firstChild!);
      }
      if (placeholder != null) {
        select.appendChild(
          (web.document.createElement('option') as web.HTMLOptionElement)
            ..value = ''
            ..textContent = placeholder
            ..disabled = true
            ..hidden = true.toJS,
        );
      }
      for (final item in items) {
        select.appendChild(
          (web.document.createElement('option') as web.HTMLOptionElement)
            ..textContent = item,
        );
      }
    }
    final index = chosen == null ? 0 : chosen + (placeholder == null ? 0 : 1);
    if (select.selectedIndex != index) select.selectedIndex = index;
    root.classList.toggle('dnn-dropdown--empty', chosen == null);
    select.disabled = p['enabled'] == false;

    final errorText = _optStr(p['error']);
    error.textContent = errorText ?? '';
    _setHidden(error, errorText == null);
    root.classList.toggle('dnn-dropdown--error', errorText != null);
    _attr(select, 'aria-invalid', errorText == null ? null : 'true');
    _attr(
      select,
      'aria-describedby',
      errorText != null && fieldId != null ? 'dnn-error-$fieldId' : null,
    );
  }

  /// A date or time picker: the dialog's surface around the browser's own
  /// `<input type="date">` or `<input type="time">`, with Cancel and OK.
  ///
  /// It is a dialog in everything but its contents, so it is built by
  /// [_modal] and inherits what a dialog does: focus moves in and is given
  /// back, and the scrim and Escape send the dismiss event. The input is the
  /// browser's because the platform's picker is what the protocol asks for,
  /// and on a phone that input *is* the platform's picker.
  ///
  /// Whether a time reads as 24-hour is the browser's decision, from the
  /// user's locale; `use24Hour` cannot be honoured here and is not tried.
  web.Element _picker(Map<String, dynamic> p, {required bool date}) {
    final modal = _modal(p, kind: 'dialog');
    modal.classList.add('dnn-modal--picker');
    final body = modal.querySelector('.dnn-dialog__body')!
      // Its contents are the renderer's, not the node's children: left marked
      // as a child host, the reconciler would clear them away.
      ..removeAttribute('data-children');

    final input = web.document.createElement('input') as web.HTMLInputElement
      ..type = date ? 'date' : 'time'
      // `browser-default` keeps Materialize's underline-only input styling
      // off it, as it does for a select.
      ..className = 'dnn-picker__input browser-default'
      ..setAttribute('data-part', 'input');
    final actions = _el('div', 'dnn-row dnn-row--end dnn-picker__actions');
    final cancel = kit.button('', variant: 'tertiary', size: 'md')
      ..setAttribute('type', 'button')
      ..setAttribute('data-part', 'cancel');
    final confirm = kit.button('', variant: 'tertiary', size: 'md')
      ..setAttribute('type', 'button')
      ..setAttribute('data-part', 'confirm');
    actions
      ..appendChild(cancel)
      ..appendChild(confirm);
    body
      ..appendChild(input)
      ..appendChild(actions);

    final state = _nodes[modal] = _NodeState(p);
    void choose() {
      final now = state.props;
      final eventId = now['eventId'];
      if (eventId is! String) return;
      handleEvent(
        eventId,
        date ? _pickedDate(input, now) : _pickedTime(input, now),
      );
    }

    confirm.addEventListener('click', ((web.Event _) => choose()).toJS);
    input.addEventListener(
      'keydown',
      ((web.KeyboardEvent event) {
        if (event.key == 'Enter') choose();
      }).toJS,
    );
    cancel.addEventListener(
      'click',
      ((web.Event _) {
        final eventId = state.props['dismissEventId'];
        if (eventId is String) handleEvent(eventId, {'reason': 'cancel'});
      }).toJS,
    );

    _applyPicker(modal, p, date: date, was: null);
    // Into the field rather than onto the surface: the next key the user
    // presses should change the date.
    _pendingFocus = input;
    return modal;
  }

  /// `{value: 'yyyy-mm-dd'}`, kept inside the range the node allows.
  ///
  /// The input's `min` and `max` stop the browser's calendar offering a date
  /// outside them, but not a date typed by hand - and a field the user
  /// emptied has no date at all, which is answered with the one it opened on.
  Map<String, dynamic> _pickedDate(
    web.HTMLInputElement input,
    Map<String, dynamic> p,
  ) {
    var value = input.value.isEmpty ? _str(p['initial']) : input.value;
    final first = _optStr(p['first']);
    final last = _optStr(p['last']);
    // ISO dates sort as text.
    if (first != null && value.compareTo(first) < 0) value = first;
    if (last != null && value.compareTo(last) > 0) value = last;
    return {'value': value};
  }

  Map<String, dynamic> _pickedTime(
    web.HTMLInputElement input,
    Map<String, dynamic> p,
  ) {
    final parts = input.value.split(':');
    final hour = parts.length < 2 ? null : int.tryParse(parts[0]);
    final minute = parts.length < 2 ? null : int.tryParse(parts[1]);
    return {
      'hour': hour ?? (_num(p['hour']) ?? 0).toInt(),
      'minute': minute ?? (_num(p['minute']) ?? 0).toInt(),
    };
  }

  /// Labels, range and - when the app changed it - the value shown.
  void _applyPicker(
    web.Element modal,
    Map<String, dynamic> p, {
    required bool date,
    required Map<String, dynamic>? was,
  }) {
    final input =
        modal.querySelector('[data-part="input"]')! as web.HTMLInputElement;
    final title = _optStr(p['title']);
    // The heading names the dialog; the field needs a name of its own.
    input.setAttribute('aria-label', title ?? (date ? 'Date' : 'Time'));
    modal.querySelector('[data-part="cancel"]')!.textContent = _str(
      p['cancelLabel'],
      'Cancel',
    );
    modal.querySelector('[data-part="confirm"]')!.textContent = _str(
      p['confirmLabel'],
      'OK',
    );

    String two(Object? value) =>
        (_num(value) ?? 0).toInt().toString().padLeft(2, '0');
    final value = date
        ? _str(p['initial'])
        : '${two(p['hour'])}:${two(p['minute'])}';
    final before = was == null
        ? null
        : date
        ? _str(was['initial'])
        : '${two(was['hour'])}:${two(was['minute'])}';
    if (date) {
      _attr(input, 'min', _optStr(p['first']));
      _attr(input, 'max', _optStr(p['last']));
    }
    // Only when the app moved it: a re-render that says what it said before
    // must not undo what the user has picked since.
    if (value != before) input.value = value;
  }

  /// Updates an open picker without closing it over the user's choice.
  bool _patchPicker(
    web.Element modal,
    _NodeState state,
    Map<String, dynamic> before,
    Map<String, dynamic> p,
  ) {
    // The scrim and Escape closed over the dismiss event when the modal was
    // built, and a title arriving or leaving changes what it is made of.
    if (before['dismissEventId'] != p['dismissEventId'] ||
        (before['title'] == null) != (p['title'] == null)) {
      return false;
    }
    final heading = modal.querySelector('h2');
    final title = _optStr(p['title']);
    if (heading != null && title != null) heading.textContent = title;
    state.props = p;
    _applyPicker(
      modal,
      p,
      date: modal.getAttribute('data-type') == 'DatePicker',
      was: before,
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Events of the renderer's own: viewport, keys, lifecycle
  // ---------------------------------------------------------------------------

  /// Whether the app has been told its viewport at least once.
  bool _viewportDelivered = false;

  /// The viewport last sent, so a resize that changed nothing says nothing.
  Map<String, dynamic>? _viewport;

  /// Listens to the window for what no node asks for: its size, its keys and
  /// whether anyone is looking at it.
  void _trackWindow() {
    void report(web.Event _) => _reportViewport();
    web.window.addEventListener(
      'resize',
      ((web.Event event) {
        // Zooming the page is a resize too, and changes the pixel ratio every
        // canvas was drawn for.
        _repaintCanvases();
        report(event);
      }).toJS,
    );
    // The keyboard opening resizes this and not the window.
    web.window.visualViewport?.addEventListener('resize', report.toJS);
    web.window
        .matchMedia('(prefers-color-scheme: dark)')
        .addEventListener('change', report.toJS);

    web.document.addEventListener(
      'keydown',
      ((web.KeyboardEvent event) => _reportKey(event, down: true)).toJS,
    );
    web.document.addEventListener(
      'keyup',
      ((web.KeyboardEvent event) => _reportKey(event, down: false)).toJS,
    );

    web.document.addEventListener(
      'visibilitychange',
      ((web.Event _) {
        _fire(RendererEvents.lifecycle, {
          'state': web.document.hidden ? 'paused' : 'resumed',
        });
      }).toJS,
    );
    // The page is going away: closed, or navigated from. It may yet come back
    // from the browser's back/forward cache, and then it says 'resumed'.
    web.window.addEventListener(
      'pagehide',
      ((web.Event _) {
        _fire(RendererEvents.lifecycle, {'state': 'detached'});
      }).toJS,
    );
    web.window.addEventListener(
      'pageshow',
      ((web.PageTransitionEvent event) {
        if (event.persisted) {
          _fire(RendererEvents.lifecycle, {'state': 'resumed'});
        }
      }).toJS,
    );
  }

  /// Sends the viewport, when someone is listening and it is not the one
  /// they already have.
  void _reportViewport() {
    if (!_handlers.containsKey(RendererEvents.viewport)) return;
    final visual = web.window.visualViewport;
    final width = web.window.innerWidth.toDouble();
    final height = web.window.innerHeight.toDouble();
    // The layout viewport keeps its height when an on-screen keyboard opens;
    // the visual one gives up the part the keyboard covers. A pinch zoom
    // shrinks the visual viewport too, and that is not a keyboard.
    final keyboard = visual == null || visual.scale != 1
        ? 0.0
        : math.max(0.0, height - visual.height - visual.offsetTop);
    final insets = _safeAreaInsets();
    final rootSize = double.tryParse(
      web.window
          .getComputedStyle(web.document.documentElement!)
          .fontSize
          .replaceAll('px', ''),
    );
    final viewport = <String, dynamic>{
      'width': width,
      'height': height,
      'paddingTop': insets.$1,
      'paddingRight': insets.$2,
      'paddingBottom': insets.$3,
      'paddingLeft': insets.$4,
      'keyboardInset': keyboard,
      'devicePixelRatio': web.window.devicePixelRatio.toDouble(),
      // The browser's default text size is 16px; a user who raised it has
      // scaled their text by the difference.
      'textScale': rootSize == null || rootSize <= 0 ? 1.0 : rootSize / 16,
      'dark': web.window.matchMedia('(prefers-color-scheme: dark)').matches,
    };
    if (_viewport != null && _valueEqual(_viewport, viewport)) return;
    _viewport = viewport;
    _viewportDelivered = true;
    _fire(RendererEvents.viewport, viewport);
  }

  /// An element that exists to be measured: its padding is the safe-area
  /// insets, which CSS knows through `env()` and script can only read back
  /// off something that uses them.
  static web.HTMLElement? _insetProbe;

  /// The safe-area insets as top, right, bottom, left - zero wherever the
  /// browser has none, which is every browser not drawing under a notch.
  (double, double, double, double) _safeAreaInsets() {
    var probe = _insetProbe;
    if (probe == null || !probe.isConnected) {
      probe = web.document.createElement('div') as web.HTMLElement
        ..setAttribute('aria-hidden', 'true');
      probe.style.cssText =
          'position:fixed;top:0;left:0;width:0;height:0;'
          'visibility:hidden;pointer-events:none;'
          'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) '
          'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
      web.document.body?.appendChild(probe);
      _insetProbe = probe;
    }
    final style = web.window.getComputedStyle(probe);
    double px(String value) => double.tryParse(value.replaceAll('px', '')) ?? 0;
    return (
      px(style.paddingTop),
      px(style.paddingRight),
      px(style.paddingBottom),
      px(style.paddingLeft),
    );
  }

  /// Sends a key press or release, unless the key was typed into something.
  ///
  /// A key pressed in a field is text, and the field's own events report it;
  /// sending it here as well would have a game move its piece every time the
  /// user typed a `w` into the chat box. Nothing is prevented either: Tab
  /// still moves focus and Space still presses the focused button.
  void _reportKey(web.KeyboardEvent event, {required bool down}) {
    if (!_handlers.containsKey(RendererEvents.key)) return;
    final target = event.target;
    if (target != null && target.isA<web.HTMLElement>()) {
      final element = target as web.HTMLElement;
      final tag = element.tagName.toLowerCase();
      if (tag == 'input' ||
          tag == 'textarea' ||
          tag == 'select' ||
          element.isContentEditable) {
        return;
      }
    }
    _fire(RendererEvents.key, {'key': event.key, 'down': down});
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  web.Element _el(String tag, String classes, {String? text}) {
    final element = web.document.createElement(tag)..className = classes;
    if (text != null) element.textContent = text;
    return element;
  }

  /// Marks [element] as the container for a node's children.
  web.Element _host(web.Element element) {
    element.setAttribute('data-children', '');
    return element;
  }

  web.Element _tooltip(web.Element element, Map<String, dynamic> p) {
    final tooltip = _optStr(p['tooltip']);
    if (tooltip != null) {
      element.setAttribute('aria-label', tooltip);
      element.setAttribute('title', tooltip);
    }
    return element;
  }

  web.Element _clickable(web.Element element, Map<String, dynamic> p) {
    final eventId = p['eventId'];
    if (eventId is String) {
      element.addEventListener(
        'click',
        ((web.Event _) {
          handleEvent(eventId, _data(p));
        }).toJS,
      );
    }
    return element;
  }

  void _onChange(
    web.HTMLInputElement input,
    Map<String, dynamic> p,
    Map<String, dynamic> Function(web.HTMLInputElement input) payload,
  ) {
    final eventId = p['eventId'];
    if (eventId is! String) return;
    input.addEventListener(
      'change',
      ((web.Event _) {
        handleEvent(eventId, {..._data(p), ...payload(input)});
      }).toJS,
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> p) {
    final data = p['data'];
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  void _gap(web.Element element, Object? spacing) {
    final gap = _num(spacing);
    if (gap != null && gap > 0) _style(element, 'gap', '${gap}px');
  }

  String _stackAlign(Object? alignment, {required bool vertical}) {
    if (vertical) {
      return switch (alignment) {
        'center' => '',
        'trailing' => 'dnn-column--end',
        _ => 'dnn-column--start',
      };
    }
    return switch (alignment) {
      'top' => 'flex-start',
      'bottom' => 'flex-end',
      _ => 'center',
    };
  }

  void _style(web.Element element, String property, String value) {
    (element as web.HTMLElement).style.setProperty(property, value);
  }

  /// Sets an inline style, or clears it when there is no [value] - for the
  /// builders that run again on a patch and must take back what a previous
  /// render wrote. Clearing only touches a property that is set, so an
  /// element nothing was ever written to does not grow an empty `style`.
  void _set(web.Element element, String property, String? value) {
    final style = (element as web.HTMLElement).style;
    if (value != null && value.isNotEmpty) {
      style.setProperty(property, value);
    } else if (style.getPropertyValue(property).isNotEmpty) {
      style.removeProperty(property);
    }
  }

  /// `[left, top, right, bottom]`, the protocol's order for padding and
  /// margin.
  static (double, double, double, double)? _edges(Object? value) {
    if (value is! List || value.length != 4) return null;
    return (
      _num(value[0]) ?? 0,
      _num(value[1]) ?? 0,
      _num(value[2]) ?? 0,
      _num(value[3]) ?? 0,
    );
  }

  /// Those edges in CSS's order, which starts at the top.
  static String? _edgesCss((double, double, double, double)? edges) =>
      edges == null
      ? null
      : '${edges.$2}px ${edges.$3}px ${edges.$4}px ${edges.$1}px';

  /// An `[x, y]` pair: an alignment, or a gradient's end.
  static (double, double)? _pair(Object? value) {
    if (value is! List || value.length != 2) return null;
    return (_num(value[0]) ?? 0, _num(value[1]) ?? 0);
  }

  /// One axis of an alignment, -1 to 1, as the nearest thing a grid can do.
  static String _gridAlign(double value) =>
      value < -1 / 3 ? 'start' : (value > 1 / 3 ? 'end' : 'center');

  /// [_gridAlign] across the page. An alignment's x is physical - -1 is the
  /// left edge whichever way the screen reads - where a grid's `start` is the
  /// right in a right-to-left one, so the side is named outright.
  static String _gridAlignX(double value) =>
      value < -1 / 3 ? 'left' : (value > 1 / 3 ? 'right' : 'center');

  /// A protocol alignment name as a flex one.
  static String _flexAlign(Object? alignment) => switch (alignment) {
    'center' => 'center',
    'end' => 'flex-end',
    'stretch' => 'stretch',
    'spaceBetween' => 'space-between',
    'spaceAround' => 'space-around',
    'spaceEvenly' => 'space-evenly',
    _ => 'flex-start',
  };

  void _setHidden(web.Element element, bool hidden) {
    if (hidden) {
      element.setAttribute('hidden', '');
    } else {
      element.removeAttribute('hidden');
    }
  }

  String _inputValue(web.Element input) =>
      input.tagName.toLowerCase() == 'textarea'
      ? (input as web.HTMLTextAreaElement).value
      : (input as web.HTMLInputElement).value;

  void _setInputValue(web.Element input, String value) {
    if (input.tagName.toLowerCase() == 'textarea') {
      (input as web.HTMLTextAreaElement).value = value;
    } else {
      (input as web.HTMLInputElement).value = value;
    }
  }

  static String _str(Object? value, [String fallback = '']) =>
      value is String ? value : (value == null ? fallback : '$value');

  static String? _optStr(Object? value) => value is String ? value : null;

  /// The CSS padding a Padding node asks for: one value when every edge is the
  /// same, four in CSS order (top right bottom left) when they are not.
  static String _padding(Map<String, dynamic> p) {
    final uniform = _num(p['padding']);
    if (uniform != null) return '${uniform}px';
    final left = _num(p['paddingLeft']) ?? 0;
    final top = _num(p['paddingTop']) ?? 0;
    final right = _num(p['paddingRight']) ?? 0;
    final bottom = _num(p['paddingBottom']) ?? 0;
    return '${top}px ${right}px ${bottom}px ${left}px';
  }

  static List<String> _strings(Object? value) =>
      value is List ? value.map((v) => '$v').toList() : const [];

  static double? _num(Object? value) => value is num ? value.toDouble() : null;
}

/// A lazy list's current props, and the range it last reported.
class _LazyListState {
  String? eventId;
  double extent = 0;

  /// The heights of the rows in the window, when they differ from each other;
  /// empty for a list whose rows are all [extent] tall.
  List<double> rowExtents = const [];
  int count = 0;
  int? first;
  int? last;

  /// The last pixels reported, for a list of rows of different heights.
  double? offset;
  double? viewport;
}

/// What a patched node's listeners read: the props the element shows now, and
/// whatever a gesture in progress has to remember between events.
class _NodeState {
  _NodeState(this.props);

  Map<String, dynamic> props;

  /// Which kinds of listener the element already has.
  bool clicks = false;
  bool pointers = false;
  bool observed = false;
  bool pulls = false;
  bool shut = false;

  /// A canvas's surface, the size it was last measured at and the size it was
  /// last painted at.
  web.HTMLCanvasElement? surface;
  double? width;
  double? height;
  double paintedWidth = 0;
  double paintedHeight = 0;

  /// The size last sent, so the same one is not sent twice.
  double? reportedWidth;
  double? reportedHeight;

  /// The pointer a gesture is following, where it went down and where it was
  /// last seen.
  int? pointer;
  bool touch = false;
  double downX = 0;
  double downY = 0;
  double lastX = 0;
  double lastY = 0;
  double lastTime = 0;
  double vx = 0;
  double vy = 0;
  bool moved = false;
  bool panning = false;
  bool held = false;

  /// Set when a gesture ends, for the click the browser sends after it.
  bool swallowClick = false;
  Timer? holdTimer;

  /// A tap waiting to find out whether it is the first of two.
  Timer? tapTimer;
  double? lastTap;

  /// Where a pull-to-refresh started, and how far it has come.
  double? pullStart;
  double pull = 0;

  /// What a dropdown's options were built from.
  List<String> items = const [];
  String? placeholder;
}

/// A box being dragged: what it carries, the copy following the pointer and
/// the target it is over.
class _Drag {
  _Drag({
    required this.source,
    required this.state,
    required this.data,
    required this.ghost,
    required this.pointer,
    required this.grabX,
    required this.grabY,
  });

  final web.Element source;
  final _NodeState state;
  final String data;
  final web.HTMLElement ghost;
  final int pointer;

  /// Where in the box the pointer took hold, so the copy does not jump to put
  /// its corner under the finger.
  final double grabX;
  final double grabY;

  web.Element? over;

  /// The document listeners, kept so the same functions can be removed.
  late final JSFunction onMove;
  late final JSFunction onUp;
  late final JSFunction onCancel;
}

/// Replays a canvas node's [commands] into [context].
///
/// The vocabulary is `UIBuilder.canvas`'s: each command is a list whose first
/// element is its name, coordinates are logical pixels, angles are radians
/// clockwise from three o'clock, and a trailing number is an index into
/// [paints]. A command this does not know, or one with arguments missing, is
/// skipped rather than thrown on: a frame with one bad command should still
/// show the rest. [ink] is what is drawn in when nothing states a colour.
///
/// Whatever the commands save, clip or transform is undone at the end, so one
/// frame cannot leak state into the next.
void _replayCanvasCommands(
  web.CanvasRenderingContext2D context,
  List<dynamic> commands,
  List<dynamic> paints, {
  required String ink,
}) {
  double n(List<dynamic> c, int i) =>
      i < c.length && c[i] is num ? (c[i] as num).toDouble() : 0;

  Map<dynamic, dynamic>? paintAt(List<dynamic> c, int i) {
    final index = i < c.length ? c[i] : null;
    if (index is! num || index < 0 || index >= paints.length) return null;
    final paint = paints[index.toInt()];
    return paint is Map ? paint : null;
  }

  /// Fills or strokes the current path the way [paint] says.
  void draw(Map<dynamic, dynamic>? paint, {bool stroke = false}) {
    final color = paint?['color'];
    final css = cssColor(color is String ? color : ink).toJS;
    if (stroke || paint?['style'] == 'stroke') {
      final width = paint?['strokeWidth'];
      context
        ..strokeStyle = css
        // Zero is "as thin as the device draws", which here is a pixel.
        ..lineWidth = width is num && width > 0 ? width : 1
        ..lineCap = switch (paint?['cap']) {
          'round' => 'round',
          'square' => 'square',
          _ => 'butt',
        }
        ..lineJoin = switch (paint?['join']) {
          'round' => 'round',
          'bevel' => 'bevel',
          _ => 'miter',
        }
        ..stroke();
    } else {
      context
        ..fillStyle = css
        ..fill();
    }
  }

  void oval(double l, double t, double w, double h) {
    final rx = w.abs() / 2;
    final ry = h.abs() / 2;
    context
      ..moveTo(l + w / 2 + rx, t + h / 2)
      ..ellipse(l + w / 2, t + h / 2, rx, ry, 0, 0, 2 * math.pi)
      ..closePath();
  }

  /// Four arcs joined by lines, rather than `roundRect`, which a browser
  /// from a few years ago does not have.
  void roundedRect(double l, double t, double w, double h, double radius) {
    final r = math.max(0.0, math.min(radius, math.min(w.abs(), h.abs()) / 2));
    context
      ..moveTo(l + r, t)
      ..arcTo(l + w, t, l + w, t + h, r)
      ..arcTo(l + w, t + h, l, t + h, r)
      ..arcTo(l, t + h, l, t, r)
      ..arcTo(l, t, l + w, t, r)
      ..closePath();
  }

  void arc(double l, double t, double w, double h, double start, double sweep) {
    context.ellipse(
      l + w / 2,
      t + h / 2,
      w.abs() / 2,
      h.abs() / 2,
      0,
      start,
      start + sweep,
      sweep < 0,
    );
  }

  void text(List<dynamic> c) {
    final options = c.length > 4 && c[4] is Map ? c[4] as Map : const {};
    final size = options['size'] is num
        ? (options['size'] as num).toDouble()
        : 14.0;
    final family = options['family'];
    final color = options['color'];
    final maxWidth = options['maxWidth'] is num
        ? (options['maxWidth'] as num).toDouble()
        : null;
    final align = switch (options['align']) {
      'center' => 'center',
      'right' => 'right',
      _ => 'left',
    };
    context
      ..font =
          '${options['weight'] ?? 400} ${size}px '
          '${family is String ? '"$family", ' : ''}'
          "'Roboto', 'Helvetica Neue', Arial, sans-serif"
      // From its top-left corner, as the protocol says, not from the
      // baseline a canvas would otherwise use.
      ..textBaseline = 'top'
      ..textAlign = align
      ..fillStyle = cssColor(color is String ? color : ink).toJS;

    // Within a width, the text wraps and is aligned inside it; without one
    // it is a single run aligned about x.
    final lines = <String>[];
    for (final paragraph in '${c.length > 1 ? c[1] : ''}'.split('\n')) {
      if (maxWidth == null) {
        lines.add(paragraph);
        continue;
      }
      var line = '';
      for (final word in paragraph.split(' ')) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty &&
            context.measureText(candidate).width > maxWidth) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      lines.add(line);
    }
    var x = n(c, 2);
    if (maxWidth != null && align == 'center') x += maxWidth / 2;
    if (maxWidth != null && align == 'right') x += maxWidth;
    for (var i = 0; i < lines.length; i++) {
      context.fillText(lines[i], x, n(c, 3) + i * size * 1.2);
    }
  }

  context.save();
  var saved = 0;
  for (final command in commands) {
    if (command is! List || command.isEmpty) continue;
    final c = command;
    switch (c[0]) {
      case 'rect':
        context
          ..beginPath()
          ..rect(n(c, 1), n(c, 2), n(c, 3), n(c, 4));
        draw(paintAt(c, 5));
      case 'rrect':
        context.beginPath();
        roundedRect(n(c, 1), n(c, 2), n(c, 3), n(c, 4), n(c, 5));
        draw(paintAt(c, 6));
      case 'circle':
        context
          ..beginPath()
          ..arc(n(c, 1), n(c, 2), n(c, 3).abs(), 0, 2 * math.pi);
        draw(paintAt(c, 4));
      case 'oval':
        context.beginPath();
        oval(n(c, 1), n(c, 2), n(c, 3), n(c, 4));
        draw(paintAt(c, 5));
      case 'line':
        context
          ..beginPath()
          ..moveTo(n(c, 1), n(c, 2))
          ..lineTo(n(c, 3), n(c, 4));
        // A line has no inside to fill, whatever its paint says.
        draw(paintAt(c, 5), stroke: true);
      case 'arc':
        final useCentre = c.length > 7 && c[7] == true;
        context.beginPath();
        if (useCentre)
          context.moveTo(n(c, 1) + n(c, 3) / 2, n(c, 2) + n(c, 4) / 2);
        arc(n(c, 1), n(c, 2), n(c, 3), n(c, 4), n(c, 5), n(c, 6));
        if (useCentre) context.closePath();
        draw(paintAt(c, 8));
      case 'path':
        context.beginPath();
        final segments = c.length > 1 && c[1] is List ? c[1] as List : const [];
        for (final segment in segments) {
          if (segment is! List || segment.isEmpty) continue;
          final s = segment;
          switch (s[0]) {
            case 'M':
              context.moveTo(n(s, 1), n(s, 2));
            case 'L':
              context.lineTo(n(s, 1), n(s, 2));
            case 'Q':
              context.quadraticCurveTo(n(s, 1), n(s, 2), n(s, 3), n(s, 4));
            case 'C':
              context.bezierCurveTo(
                n(s, 1),
                n(s, 2),
                n(s, 3),
                n(s, 4),
                n(s, 5),
                n(s, 6),
              );
            case 'A':
              arc(n(s, 1), n(s, 2), n(s, 3), n(s, 4), n(s, 5), n(s, 6));
            case 'R':
              context.rect(n(s, 1), n(s, 2), n(s, 3), n(s, 4));
            case 'O':
              oval(n(s, 1), n(s, 2), n(s, 3), n(s, 4));
            case 'Z':
              context.closePath();
          }
        }
        draw(paintAt(c, 2));
      case 'text':
        text(c);
      case 'save':
        context.save();
        saved++;
      case 'restore':
        // Never past the frame's own save, which is not the commands' to pop.
        if (saved > 0) {
          context.restore();
          saved--;
        }
      case 'translate':
        context.translate(n(c, 1), n(c, 2));
      case 'rotate':
        context.rotate(n(c, 1));
      case 'scale':
        context.scale(n(c, 1), n(c, 2));
      case 'clipRect':
        context
          ..beginPath()
          ..rect(n(c, 1), n(c, 2), n(c, 3), n(c, 4))
          ..clip();
      case 'clipRRect':
        context.beginPath();
        roundedRect(n(c, 1), n(c, 2), n(c, 3), n(c, 4), n(c, 5));
        context.clip();
    }
  }
  for (; saved >= 0; saved--) {
    context.restore();
  }
}
