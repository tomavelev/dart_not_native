/// Web Renderer Implementation
///
/// Renders [WidgetNode] trees to real DOM (no canvas, no Flutter). Layout
/// primitives are styled by `dnn.css`; Material components are built by a
/// pluggable [WebStyleKit] (Material Design Lite, Materialize, ...).
///
/// Re-renders are reconciled against the existing DOM: a node whose type and
/// props are unchanged keeps its element (only its children are revisited),
/// so a text field keeps focus and caret while the app re-renders around it.

library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../src/app_theme.dart';
import '../src/contrast.dart';
import '../src/frame_probe.dart';
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
      _syncChildren(rootElement, [
        tree,
      ], _currentTree == null ? const [] : [_currentTree!]);
      _currentTree = tree;
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

  /// Forgets the tree the DOM is believed to show, so the next render rebuilds
  /// from scratch. For a host that replaced the root's contents itself, and
  /// for benchmarks measuring a first paint.
  void forgetRenderedTree() => _currentTree = null;

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async {
    final handler = _handlers[eventId];
    if (handler != null) {
      handler(data);
      return {'success': true};
    }
    return {'success': false, 'error': 'Handler not found for $eventId'};
  }

  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {
    _handlers[eventId] = handler;
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

      if (existing != null && before != null && before.type == node.type) {
        if (_propsEqual(before.props, node.props)) {
          _syncHosted(existing, node, before.children ?? const []);
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
    _pruneSnackbarTimers();
    _releaseGoneCameras();
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
    if (id is String) element.id = id;
    _syncHosted(element, node, const []);
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
        return _host(_el('div', 'dnn-scaffold'));
      case 'NavigationStack':
        return _host(_el('div', 'dnn-navstack'));
      case 'NavigationBar':
        final inline = p['inline'] != false;
        final bar = _el(
          'header',
          'dnn-navbar${inline ? '' : ' dnn-navbar--large'}',
        );
        bar.appendChild(
          _el('span', 'dnn-navbar__title', text: _str(p['title'])),
        );
        return bar;
      case 'Column':
        final align = p['crossAxisAlignment'];
        final main = p['mainAxisAlignment'];
        return _host(
          _el(
            'div',
            [
              'dnn-column',
              if (align is String) 'dnn-column--$align',
              if (main is String) 'dnn-column--main-$main',
            ].join(' '),
          ),
        );
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
        final row = _host(
          _el('div', main is String ? 'dnn-row dnn-row--$main' : 'dnn-row'),
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
        return wrap;
      case 'Expanded':
        final expanded = _host(_el('div', 'dnn-expanded'));
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
        return _image(p);
      case 'Divider':
        return _divider(p);
      case 'Loading':
        return _loading(p);

      // Material components (style kit)
      case 'AppBar':
        final background = p['backgroundColor'];
        return kit.appBar(
          _str(p['title']),
          backgroundColor: background is String ? background : null,
        );
      case 'FloatingActionButton':
        return _clickable(
          _tooltip(kit.floatingActionButton(_str(p['icon'], 'add')), p),
          p,
        );
      case 'IconButton':
        return _clickable(
          _tooltip(kit.iconButton(_str(p['icon'], 'more_vert')), p),
          p,
        );
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
        return _clickable(button, p);
      case 'TextField':
        return _textField(p);
      case 'Checkbox':
        final parts = kit.checkbox(_optStr(p['label']));
        parts.input
          ..checked = p['checked'] == true
          ..disabled = p['disabled'] == true;
        _onChange(parts.input, p, (input) => {'checked': input.checked});
        return parts.root;
      case 'Radio':
        final parts = kit.radio(_optStr(p['label']));
        parts.input
          ..checked = p['selected'] == true
          ..disabled = p['disabled'] == true;
        _onChange(parts.input, p, (_) => {'value': p['value']});
        return parts.root;
      case 'Toggle':
        final parts = kit.toggle(_optStr(p['label']));
        parts.input
          ..checked = p['enabled'] == true
          ..disabled = p['disabled'] == true;
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
    final text = _el('span', 'dnn-text', text: _str(p['content']));
    final size = _num(p['fontSize']);
    if (size != null) _style(text, 'font-size', '${size}px');
    final weight = p['fontWeight'];
    if (weight != null) _style(text, 'font-weight', '$weight');
    final color = p['color'];
    if (color is String) _style(text, 'color', color);
    switch (p['decoration']) {
      case 'lineThrough':
        _style(text, 'text-decoration', 'line-through');
      case 'underline':
        _style(text, 'text-decoration', 'underline');
    }
    _clampLines(text, p);
    return text;
  }

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

  web.Element _image(Map<String, dynamic> p) {
    final image = _el('img', 'dnn-image') as web.HTMLImageElement
      ..src = _str(p['src'])
      // Doubles as the accessible name and as what shows if the load fails.
      ..alt = _str(p['alt']);
    final width = _num(p['width']);
    final height = _num(p['height']);
    if (width != null) _style(image, 'width', '${width}px');
    if (height != null) _style(image, 'height', '${height}px');
    _style(image, 'object-fit', _objectFit(_str(p['fit'], 'cover')));
    return image;
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
    if (color is String) _style(divider, 'background', color);
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

  web.Element _loading(Map<String, dynamic> p) {
    final color = _str(p['color'], theme.primary);
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

    /// One bar of buttons, pinned to [edge] ('auto 0 0 0' leads, '0 0 0 auto'
    /// trails), answering with the event ids it bound.
    List<String> bar(List<dynamic> actions, String inset, String className) {
      final eventIds = <String>[];
      if (actions.isEmpty) return eventIds;
      final bar = _el('div', className);
      _style(bar, 'position', 'absolute');
      _style(bar, 'inset', inset);
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
        _style(btn, 'background', color is String ? color : '#d32f2f');
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
      '0 0 0 auto',
      'dnn-swipe__actions',
    );
    final leadingIds = bar(
      (p['leadingActions'] as List?) ?? const [],
      '0 auto 0 0',
      'dnn-swipe__actions dnn-swipe__actions--leading',
    );

    final fg = _host(_el('div', 'dnn-swipe__fg'));
    _style(fg, 'position', 'relative');
    _style(fg, 'background', 'var(--dnn-surface, #ffffff)');
    _style(fg, 'touch-action', 'pan-y');
    container.appendChild(fg);

    // Where the row rests when it is open each way: left to show the trailing
    // actions, right to show the leading ones.
    final open = -88.0 * eventIds.length;
    final openLeading = 88.0 * leadingIds.length;
    var startX = 0.0, offset = 0.0, dragging = false;
    void setX(double x, {bool animate = false}) {
      _style(fg, 'transition', animate ? 'transform 0.2s' : 'none');
      _style(fg, 'transform', 'translateX(${x}px)');
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
        offset = (pe.clientX.toDouble() - startX).clamp(
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
    if (eventId is String) {
      String value() => _inputValue(input);
      void emit(String suffix) {
        handleEvent('${eventId}_$suffix', {'value': value()});
      }

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
    _style(box, 'background-color', color is String ? color : '');
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
    final value = '${_num(p['value']) ?? min}';
    // Leave the thumb where the user has it while they are dragging: an echo
    // of the value we already have would fight the drag.
    if (slider.value != value) slider.value = value;
  }

  /// Update a text field in place so it keeps focus and caret position.
  bool _patchTextField(web.Element root, WidgetNode node) {
    final parts = _textFieldParts(root);
    final multiline = (_num(node.props['maxLines']) ?? 1) > 1;
    if (parts == null ||
        (parts.input.tagName.toLowerCase() == 'textarea') != multiline) {
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
