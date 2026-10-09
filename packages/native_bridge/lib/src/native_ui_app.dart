/// NativeUIApp - platform-neutral application shell.
///
/// Holds app state, builds a [WidgetNode] tree and reacts to renderer events.
/// It is pure Dart, so the same app can be mounted on the web DOM renderer,
/// a native Android/iOS renderer, or driven from a Flutter widget.
///
/// ```dart
/// class CounterApp extends NativeUIApp {
///   int count = 0;
///
///   @override
///   void init() => on('increment', (_) => setState(() => count++));
///
///   @override
///   WidgetNode build() => UIBuilder.scaffold(
///         appBar: UIBuilder.appBar(title: 'Counter'),
///         body: UIBuilder.center(child: UIBuilder.text('Count: $count')),
///         floatingActionButton: UIBuilder.floatingActionButton(
///           tooltip: 'Increment',
///           eventId: 'increment',
///         ),
///       );
/// }
/// ```

import 'dart:async';

import 'event_binding.dart';
import 'listenable.dart';
import 'overlays.dart';
import 'frame_probe.dart';
import 'render_error.dart';
import 'ui_renderer.dart';

abstract class NativeUIApp {
  NativeUIRenderer? _renderer;

  /// Callbacks handed to builders during [build], kept across renders so a
  /// rebuild replaces behaviour without registering handlers again.
  final EventBindings _bindings = EventBindings();

  /// Gives the back gesture to the topmost dialog or sheet while one is open.
  final OverlayBack _overlayBack = OverlayBack();

  /// Called after every render; Flutter hosts use it to trigger setState.
  void Function()? onChanged;

  /// Called when a render reports a problem - an unknown node type, a native
  /// exception, an error thrown while rendering.
  ///
  /// One callback, for the host that wants to handle errors rather than watch
  /// them; [renderErrors] is the stream for everything else. With neither set,
  /// the default prints in debug builds, so a failed native render is not
  /// silent - a renderer that throws used to leave a blank screen with nothing
  /// logged anywhere.
  void Function(RenderError error)? onRenderError;

  final StreamController<RenderError> _renderErrorsController =
      StreamController<RenderError>.broadcast();

  /// Every problem a render has reported since the app was mounted.
  ///
  /// A broadcast stream, so a debug overlay, a crash reporter and a test can
  /// all watch at once without taking the one [onRenderError] slot from each
  /// other. Listening is enough to silence the debug print: something is
  /// evidently handling them.
  Stream<RenderError> get renderErrors => _renderErrorsController.stream;

  /// Draws render errors over the app instead of only logging them.
  ///
  /// For development, and off by default. A native renderer's errors otherwise
  /// only reach a log the developer has to be watching, which is how an unknown
  /// node type can sit unnoticed behind a placeholder for a whole session.
  ///
  /// The banner is a `Snackbar` node - already drawn by every renderer, and
  /// non-modal, so it blocks nothing and does not take the back gesture.
  bool debugShowRenderErrors = false;

  /// The distinct messages the banner is showing, oldest first.
  final List<String> _bannerMessages = [];

  /// A banner over [tree] naming what the last render could not do.
  ///
  /// The tree stops being the root when it is wrapped, so what it said about
  /// the screen as its root - the reading direction - is said by the wrapper.
  WidgetNode _withErrorBanner(WidgetNode tree) => UIBuilder.withTextDirection(
        _bannerOver(UIBuilder.withTextDirection(tree, null)),
        tree.props[RootProps.textDirection] as String?,
      );

  WidgetNode _bannerOver(WidgetNode tree) => UIBuilder.overlay(
        child: tree,
        overlays: [
          UIBuilder.snackbar(
            message: _bannerMessages.join('\n'),
            // It is not going anywhere on its own: the problem is still there,
            // and a banner that faded would be worse than no banner.
            duration: const Duration(days: 1),
            id: 'dnn_render_errors',
          ),
        ],
      );


  NativeUIRenderer get renderer =>
      _renderer ?? (throw StateError('$runtimeType is not mounted'));

  /// Records how smoothly this app's screen actually draws - see [FrameProbe].
  ///
  /// The measurement belongs to whatever is drawing, so this is the mounted
  /// renderer's own probe; a renderer that cannot see its frames (or an app that
  /// is not mounted) answers [FrameProbe.unavailable], whose `stop` returns null
  /// rather than a plausible zero.
  FrameProbe get frameProbe {
    final mounted = _renderer;
    // Cast rather than lean on promotion: the local's type is the renderer
    // interface, which HasFrameProbe is deliberately not part of.
    return mounted is HasFrameProbe
        ? (mounted as HasFrameProbe).frameProbe
        : FrameProbe.unavailable;
  }

  bool get isMounted => _renderer != null;

  /// Attach to [renderer], run [init] and render the first frame.
  void mount(NativeUIRenderer renderer) {
    _renderer = renderer;
    init();
    render();
  }

  /// Register event handlers and kick off any initial loading.
  ///
  /// Only needed for events a builder cannot bind for you - anything built
  /// with `onPressed`, `onChanged` and friends registers itself.
  void init() {}

  /// Build the widget tree for the current state.
  WidgetNode build();

  /// Register [handler] for events emitted by nodes with [eventId].
  void on(String eventId, void Function(Map<String, dynamic> data) handler) {
    renderer.onEvent(eventId, handler);
  }

  /// Apply [fn] and re-render.
  void setState(void Function() fn) {
    fn();
    render();
  }

  /// The stores this app follows, and the listener watching each.
  final Map<Listenable, VoidCallback> _watched = {};

  /// Re-renders whenever [listenable] changes.
  ///
  /// State that outlives one screen - a signed-in user, a cart - lives in a
  /// [ChangeNotifier] or [ValueNotifier] outside the app rather than in a
  /// field, and this is how the app hears about it. Watching the same
  /// listenable twice is harmless, and [unmount] lets go of all of them, so an
  /// app never keeps a store rendering a screen that is gone.
  ///
  /// ```dart
  /// @override
  /// void init() => watch(favourites);
  /// ```
  ///
  /// The widget layer has [ValueListenableBuilder] for the same job.
  void watch(Listenable listenable) {
    if (_watched.containsKey(listenable)) return;
    void onChange() => render();
    listenable.addListener(onChange);
    _watched[listenable] = onChange;
  }

  /// Stops following [listenable]. Unwatching one never watched does nothing.
  void unwatch(Listenable listenable) {
    final listener = _watched.remove(listenable);
    if (listener != null) listenable.removeListener(listener);
  }

  /// Render the current state (no-op until mounted).
  void render() {
    final renderer = _renderer;
    if (renderer == null) return;
    // build() runs inside the binding scope, so a builder given a callback
    // can register it and put the resulting id in the node.
    var tree = _bindings.runBuild(renderer, build, invalidate: render);
    if (debugShowRenderErrors && _bannerMessages.isNotEmpty) {
      tree = _withErrorBanner(tree);
    }
    _overlayBack.track(tree, renderer);
    // So a renderer can say which build an event of its is for.
    _bindings.tag(tree);
    // render() answers with a RenderError (or null), and may reject; either way
    // the problem is surfaced rather than dropped on the floor.
    renderer.render(tree).then(
      (error) {
        if (error != null) _reportRenderError(error);
      },
      onError: (Object e, StackTrace stackTrace) => _reportRenderError(
        RenderError.failed('$e', cause: e, stackTrace: stackTrace),
      ),
    );
    onChanged?.call();
  }

  void _reportRenderError(RenderError error) {
    _renderErrorsController.add(error);
    _showInBanner(error);
    final handler = onRenderError;
    if (handler != null) {
      handler(error);
      return;
    }
    // Nobody asked to hear about it either way, so say it where a developer
    // will see it. assert bodies run in debug only, so this is loud in
    // development and silent in release without a print reaching production.
    if (_renderErrorsController.hasListener) return;
    assert(() {
      // ignore: avoid_print
      print('dart_not_native: render failed: ${error.message}');
      return true;
    }());
  }

  /// Adds [error] to the debug banner, and re-renders once to put it on screen.
  ///
  /// Only when the set of messages actually changed: the render this schedules
  /// hits the same unknown node type and reports it again, and a banner that
  /// re-rendered for every repeat would never stop.
  void _showInBanner(RenderError error) {
    if (!debugShowRenderErrors) return;
    if (_bannerMessages.contains(error.message)) return;
    _bannerMessages.add(error.message);
    // Three is enough to see a pattern without burying the app.
    if (_bannerMessages.length > 3) _bannerMessages.removeAt(0);
    scheduleMicrotask(render);
  }

  /// Releases what the app holds outside itself: the back gesture an open
  /// dialog or sheet was taking, the stores it was [watch]ing, and anyone
  /// listening for render errors.
  void unmount() {
    _overlayBack.dispose();
    for (final entry in _watched.entries) {
      entry.key.removeListener(entry.value);
    }
    _watched.clear();
    _renderErrorsController.close();
    _renderer = null;
  }
}

/// Renderer that keeps the latest tree in memory and dispatches events.
///
/// Useful for hosting a [NativeUIApp] where no native renderer exists (e.g. a
/// Flutter fallback UI) and in tests.
class InMemoryRenderer implements NativeUIRenderer {
  final Map<String, Function(Map<String, dynamic>)> _handlers = {};

  /// The most recently rendered tree.
  WidgetNode? tree;

  @override
  Future<RenderError?> render(WidgetNode tree) async {
    this.tree = tree;
    return null;
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
}
