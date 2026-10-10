part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// The binding: what the platform tells the app without being asked - its
// size, its keys, its lifecycle - and the things built directly on that.
// ---------------------------------------------------------------------------

/// Called once a frame has been handed to the renderer.
typedef FrameCallback = void Function(Duration timeStamp);

/// Where an app is in its life, as the platform reports it.
enum AppLifecycleState { detached, resumed, inactive, hidden, paused }

/// Flutter's entry to the binding. `ensureInitialized()` is what an app calls
/// before touching a plugin ahead of `runApp`.
///
/// On a Flutter host this starts Flutter's own binding, because that is what
/// a plugin's platform channel needs; anywhere else there is nothing to start.
abstract final class WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    platform_binding.ensureInitialized();
    return WidgetsBinding.instance;
  }
}

/// The slice of Flutter's `WidgetsBinding` an app reaches for: a callback
/// after the frame, and the app's lifecycle.
class WidgetsBinding {
  WidgetsBinding._();

  static final WidgetsBinding instance = WidgetsBinding._();

  final Stopwatch _clock = Stopwatch()..start();
  final List<FrameCallback> _postFrame = [];
  final List<WidgetsBindingObserver> _observers = [];
  bool _flushScheduled = false;

  /// The last lifecycle state the platform reported, or null before the first.
  AppLifecycleState? get lifecycleState => _lifecycleState;
  AppLifecycleState? _lifecycleState;

  /// Runs [callback] once the build in progress has been handed to the
  /// renderer - the place to show a dialog or move a scroll position from
  /// `initState`, where doing it directly would start a build inside a build.
  ///
  /// A build here is synchronous from `setState` to the render call, so
  /// "after the frame" is the next microtask; called outside a build, it runs
  /// then as well rather than waiting for a frame that may never come.
  void addPostFrameCallback(FrameCallback callback, {String? debugLabel}) {
    _postFrame.add(callback);
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    final callbacks = List<FrameCallback>.of(_postFrame);
    _postFrame.clear();
    final now = _clock.elapsed;
    for (final callback in callbacks) {
      callback(now);
    }
  }

  /// Completes after the current frame, as Flutter's does.
  Future<void> get endOfFrame {
    final done = Completer<void>();
    addPostFrameCallback((_) => done.complete());
    return done.future;
  }

  void addObserver(WidgetsBindingObserver observer) => _observers.add(observer);

  bool removeObserver(WidgetsBindingObserver observer) =>
      _observers.remove(observer);

  void _onLifecycle(String name) {
    final state = AppLifecycleState.values
        .where((value) => value.name == name)
        .firstOrNull;
    if (state == null) return;
    _lifecycleState = state;
    for (final observer in List.of(_observers)) {
      observer.didChangeAppLifecycleState(state);
    }
  }

  void _onMetrics({required bool brightnessChanged}) {
    for (final observer in List.of(_observers)) {
      observer.didChangeMetrics();
      if (brightnessChanged) observer.didChangePlatformBrightness();
    }
  }
}

/// Mixed into whatever wants to hear from the [WidgetsBinding], usually a
/// `State`: override the methods of interest, `addObserver(this)` in
/// `initState` and `removeObserver(this)` in `dispose`.
abstract mixin class WidgetsBindingObserver {
  /// The app moved to the foreground, the background, or away.
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  /// The viewport changed: a rotation, a resize, the keyboard.
  void didChangeMetrics() {}

  /// The device switched between light and dark.
  void didChangePlatformBrightness() {}

  /// Accepted so an observer written for Flutter compiles; never called -
  /// the platform does not report these to the framework.
  void didChangeLocales(List<Locale>? locales) {}
  void didChangeTextScaleFactor() {}
  void didHaveMemoryPressure() {}
  Future<bool> didPopRoute() => Future<bool>.value(false);
}

/// Hears the app's lifecycle without mixing [WidgetsBindingObserver] into a
/// `State`: Flutter's `AppLifecycleListener`.
///
/// It listens from the moment it is made until [dispose]. The callbacks are
/// the transitions Flutter names, worked out from the state before and the
/// state after: [onResume] on the way back to the foreground, [onInactive],
/// [onHide] and [onPause] on the way out, [onShow] and [onRestart] on the way
/// back in, [onDetach] at the end. A platform that reports only "resumed" and
/// "paused" still walks through the ones in between, in Flutter's order.
/// [onExitRequested] is accepted and never called: no platform here asks.
class AppLifecycleListener with WidgetsBindingObserver {
  AppLifecycleListener({
    WidgetsBinding? binding,
    this.onResume,
    this.onInactive,
    this.onHide,
    this.onShow,
    this.onPause,
    this.onRestart,
    this.onDetach,
    this.onExitRequested,
    this.onStateChange,
  }) : binding = binding ?? WidgetsBinding.instance {
    _state = this.binding.lifecycleState;
    this.binding.addObserver(this);
  }

  final WidgetsBinding binding;
  final VoidCallback? onResume;
  final VoidCallback? onInactive;
  final VoidCallback? onHide;
  final VoidCallback? onShow;
  final VoidCallback? onPause;
  final VoidCallback? onRestart;
  final VoidCallback? onDetach;
  final Future<Object?> Function()? onExitRequested;
  final ValueChanged<AppLifecycleState>? onStateChange;

  AppLifecycleState? _state;

  /// Stops listening.
  void dispose() => binding.removeObserver(this);

  // How far from the foreground a state is: the order Flutter walks them in.
  static const _depth = {
    AppLifecycleState.resumed: 0,
    AppLifecycleState.inactive: 1,
    AppLifecycleState.hidden: 2,
    AppLifecycleState.paused: 3,
    AppLifecycleState.detached: 4,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previous = _state;
    if (state == previous) return;
    _state = state;
    final from = _depth[previous ?? AppLifecycleState.resumed]!;
    final to = _depth[state]!;
    if (to > from) {
      // Away from the foreground: each step passed on the way is told.
      if (from < 1 && to >= 1) onInactive?.call();
      if (from < 2 && to >= 2) onHide?.call();
      if (from < 3 && to >= 3) onPause?.call();
      if (from < 4 && to >= 4) onDetach?.call();
    } else {
      // Back towards it.
      if (from >= 4 && to < 4) onPause?.call();
      if (from >= 3 && to < 3) onRestart?.call();
      if (from >= 2 && to < 2) onShow?.call();
      if (from >= 1 && to < 1) onResume?.call();
    }
    onStateChange?.call(state);
  }
}

/// How text is scaled by the system's accessibility setting.
class TextScaler {
  const TextScaler.linear(this.textScaleFactor);

  static const TextScaler noScaling = TextScaler.linear(1);

  final double textScaleFactor;

  /// [fontSize] as the system wants it drawn.
  double scale(double fontSize) => fontSize * textScaleFactor;

  @override
  bool operator ==(Object other) =>
      other is TextScaler && other.textScaleFactor == textScaleFactor;
  @override
  int get hashCode => textScaleFactor.hashCode;
}

/// Whether a viewport is taller than wide, or the other way about.
enum Orientation { portrait, landscape }

/// What the renderer knows about the window it draws into.
///
/// Fed by the renderer's viewport event. Before the first one arrives - and a
/// build happens before a renderer has measured anything - it is a phone in
/// portrait, 390 by 800, with no insets.
class MediaQueryData {
  const MediaQueryData({
    this.size = Size.zero,
    this.devicePixelRatio = 1.0,
    this.textScaler = TextScaler.noScaling,
    this.platformBrightness = Brightness.light,
    this.padding = EdgeInsets.zero,
    this.viewInsets = EdgeInsets.zero,
    this.viewPadding = EdgeInsets.zero,
    this.alwaysUse24HourFormat = false,
  });

  /// The window, in logical pixels.
  final Size size;
  final double devicePixelRatio;
  final TextScaler textScaler;
  final Brightness platformBrightness;

  /// The parts of the window the system draws over: the status bar, the
  /// notch, the home indicator.
  final EdgeInsets padding;

  /// The parts the system covers completely - the keyboard, at the bottom.
  final EdgeInsets viewInsets;

  /// [padding] as it is with nothing covering it. The same thing here: the
  /// renderers report the two together.
  final EdgeInsets viewPadding;

  /// Whether a time is written on the twenty-four hour clock whatever the
  /// locale's own habit - the device's "24-hour time" switch, in Flutter.
  /// No renderer reports that setting, so it is false unless a [MediaQuery]
  /// the app builds says otherwise.
  final bool alwaysUse24HourFormat;

  /// Flutter's older spelling of [textScaler].
  double get textScaleFactor => textScaler.textScaleFactor;

  Orientation get orientation =>
      size.width > size.height ? Orientation.landscape : Orientation.portrait;

  MediaQueryData copyWith({
    Size? size,
    double? devicePixelRatio,
    TextScaler? textScaler,
    Brightness? platformBrightness,
    EdgeInsets? padding,
    EdgeInsets? viewInsets,
    EdgeInsets? viewPadding,
    bool? alwaysUse24HourFormat,
  }) => MediaQueryData(
    size: size ?? this.size,
    devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    textScaler: textScaler ?? this.textScaler,
    platformBrightness: platformBrightness ?? this.platformBrightness,
    padding: padding ?? this.padding,
    viewInsets: viewInsets ?? this.viewInsets,
    viewPadding: viewPadding ?? this.viewPadding,
    alwaysUse24HourFormat: alwaysUse24HourFormat ?? this.alwaysUse24HourFormat,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaQueryData &&
      other.size == size &&
      other.devicePixelRatio == devicePixelRatio &&
      other.textScaler == textScaler &&
      other.platformBrightness == platformBrightness &&
      other.padding == padding &&
      other.viewInsets == viewInsets &&
      other.viewPadding == viewPadding &&
      other.alwaysUse24HourFormat == alwaysUse24HourFormat;

  @override
  int get hashCode => Object.hash(
    size,
    devicePixelRatio,
    textScaler,
    platformBrightness,
    padding,
    viewInsets,
    viewPadding,
    alwaysUse24HourFormat,
  );
}

/// The window's size and insets, visible to everything below.
///
/// An app rarely builds one: `MediaQuery.of(context)` answers with what the
/// renderer reported even when there is none above, and a build that read it
/// runs again when the window changes. Building one overrides the answer for
/// a subtree, as in Flutter.
class MediaQuery extends InheritedWidget {
  const MediaQuery({super.key, required this.data, required super.child});

  final MediaQueryData data;

  static MediaQueryData of(BuildContext context) {
    final above = context.dependOnInheritedWidgetOfExactType<MediaQuery>();
    if (above != null) return above.data;
    // No widget to depend on: the answer is the window the renderer reported,
    // and a state that read it hears when the window changes.
    final media = _ownerOf(context)._media;
    if (context is _Context) {
      context._depend(
        #windowMedia,
        media,
        (context) => context._owner._media,
        (before, after) => before != after,
      );
    }
    return media;
  }

  /// As [of]. It cannot be null here - the framework always has an answer -
  /// and the name is kept for code that asks politely.
  static MediaQueryData? maybeOf(BuildContext context) => of(context);

  static Size sizeOf(BuildContext context) => of(context).size;
  static Size? maybeSizeOf(BuildContext context) => of(context).size;
  static EdgeInsets paddingOf(BuildContext context) => of(context).padding;
  static EdgeInsets viewInsetsOf(BuildContext context) =>
      of(context).viewInsets;
  static EdgeInsets viewPaddingOf(BuildContext context) =>
      of(context).viewPadding;
  static Brightness platformBrightnessOf(BuildContext context) =>
      of(context).platformBrightness;
  static double devicePixelRatioOf(BuildContext context) =>
      of(context).devicePixelRatio;
  static TextScaler textScalerOf(BuildContext context) =>
      of(context).textScaler;
  static Orientation orientationOf(BuildContext context) =>
      of(context).orientation;
  static bool alwaysUse24HourFormatOf(BuildContext context) =>
      of(context).alwaysUse24HourFormat;

  @override
  bool updateShouldNotify(MediaQuery oldWidget) => oldWidget.data != data;
}

/// The media query as the build in progress sees it.
MediaQueryData _mediaOf(_Owner owner) =>
    owner._inherited<MediaQuery>()?.data ?? owner._media;

extension _RendererEvents on _Owner {
  /// The renderer measured its window, or the window changed.
  void _onViewport(Map<String, dynamic> data) {
    double n(String key, [double fallback = 0]) =>
        (data[key] as num?)?.toDouble() ?? fallback;
    final insets = EdgeInsets.fromLTRB(
      n('paddingLeft'),
      n('paddingTop'),
      n('paddingRight'),
      n('paddingBottom'),
    );
    final next = MediaQueryData(
      size: Size(n('width', _media.size.width), n('height', _media.size.height)),
      devicePixelRatio: n('devicePixelRatio', 1),
      textScaler: TextScaler.linear(n('textScale', 1)),
      platformBrightness: data['dark'] == true
          ? Brightness.dark
          : Brightness.light,
      padding: insets,
      viewPadding: insets,
      viewInsets: EdgeInsets.only(bottom: n('keyboardInset')),
    );
    if (next == _media) return;
    final brightnessChanged =
        next.platformBrightness != _media.platformBrightness;
    _media = next;
    WidgetsBinding.instance._onMetrics(brightnessChanged: brightnessChanged);
    _requestRebuild();
  }

  /// A hardware key went down or came up.
  void _onKey(Map<String, dynamic> data) {
    final name = data['key'];
    if (name is! String) return;
    final key = LogicalKeyboardKey._named(name);
    final character = name.length == 1 ? name : null;
    final KeyEvent event = data['down'] == false
        ? KeyUpEvent(logicalKey: key)
        : KeyDownEvent(logicalKey: key, character: character);
    for (final listener in _keyHearers()) {
      listener.handler(event);
    }
  }

  /// The listeners a key goes to, of those on screen.
  ///
  /// A dialog or a sheet has the keyboard while it is open: only listeners
  /// inside the topmost one hear, and with none of them there, nobody does -
  /// the page underneath is not steered through a dialog. Among those left,
  /// one whose [FocusNode] was asked for focus (`requestFocus`, or
  /// `autofocus`) hears alone, the most recently asked if there are several.
  /// With no such ask they all hear, which is the one-listener game this
  /// began as.
  List<_KeyListener> _keyHearers() {
    final top = _overlays.isEmpty ? null : _overlays.last;
    final inScope = [
      for (final listener in _keyListeners)
        if (identical(listener.overlay, top)) listener,
    ];
    _KeyListener? focused;
    for (final listener in inScope) {
      final asked = listener.node._askedAt;
      if (asked > 0 && asked > (focused?.node._askedAt ?? 0)) {
        focused = listener;
      }
    }
    return focused == null ? inScope : [focused];
  }
}

/// Puts the app's declared palette above everything, as a [Theme], in the
/// appearance the device is showing.
class _RootScope extends Widget {
  _RootScope({required this.theme, required this.child});

  final AppTheme theme;
  final Widget child;

  // Deriving a ThemeData is not free and the palette does not change, so each
  // appearance is derived once.
  ThemeData? _light;
  ThemeData? _dark;

  @override
  WidgetNode _render(_Owner owner) {
    final dark = theme.isDark(
      platformIsDark: owner._media.platformBrightness == Brightness.dark,
    );
    final data = dark
        ? _dark ??= ThemeData.fromAppTheme(theme.dark, dark: true)
        : _light ??= ThemeData.fromAppTheme(theme);
    return Theme(data: data, child: child)._render(owner);
  }
}

// ---------------------------------------------------------------------------
// Layout that depends on the room it is given.
// ---------------------------------------------------------------------------

/// Builds a subtree from the room it has: Flutter's `LayoutBuilder`.
///
/// Flutter lays out and builds in one pass, so its builder runs with the real
/// constraints. Here layout happens on the far side of a channel, so the
/// builder first runs against the viewport, the renderer reports the size the
/// box came to, and the builder runs again with that - once, and then again
/// only when the size changes.
///
/// The box it measures fills the room it is offered, which is what makes its
/// size the constraints: both ways normally, and only across inside a vertical
/// scroller, where the height on offer is unbounded (and `maxHeight` is
/// infinite, as it would be in Flutter).
class LayoutBuilder extends StatefulWidget {
  const LayoutBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, BoxConstraints constraints)
  builder;

  @override
  State<LayoutBuilder> createState() => _LayoutBuilderState();
}

class _LayoutBuilderState extends State<LayoutBuilder> {
  Size? _size;

  void _report(double width, double height) {
    final old = _size;
    // A renderer rounding to device pixels reports the same box as a
    // slightly different number; that is not a new layout.
    if (old != null &&
        (old.width - width).abs() < 0.5 &&
        (old.height - height).abs() < 0.5) {
      return;
    }
    if (!mounted) return;
    setState(() => _size = Size(width, height));
  }

  @override
  Widget build(BuildContext context) => _NodeWidget((owner) {
    final scrolling = owner._scrollDepth > 0;
    final room = _size ?? _mediaOf(owner).size;
    final constraints = BoxConstraints(
      maxWidth: room.width,
      maxHeight: scrolling ? double.infinity : room.height,
    );
    return UIBuilder.box(
      expand: scrolling ? 'width' : 'both',
      onSize: _report,
      id: _idOf(widget.key),
      child: owner.inSlot(
        'child',
        () => widget.builder(owner._context(), constraints)._render(owner),
      ),
    );
  });
}

// ---------------------------------------------------------------------------
// Tickers.
// ---------------------------------------------------------------------------

/// Called on every tick with the time since the ticker started.
typedef TickerCallback = void Function(Duration elapsed);

/// The future a [Ticker.start] returns: it completes when the ticker stops.
class TickerFuture implements Future<void> {
  TickerFuture._();

  final Completer<void> _done = Completer<void>();

  /// As the future itself: a ticker here is never cancelled with an error.
  Future<void> get orCancel => _done.future;

  void whenCompleteOrCancel(VoidCallback callback) =>
      _done.future.whenComplete(callback);

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Stream<void> asStream() => _done.future.asStream();
  @override
  Future<void> catchError(Function onError, {bool Function(Object)? test}) =>
      _done.future.catchError(onError, test: test);
  @override
  Future<R> then<R>(FutureOr<R> Function(void) onValue, {Function? onError}) =>
      _done.future.then(onValue, onError: onError);
  @override
  Future<void> timeout(Duration limit, {FutureOr<void> Function()? onTimeout}) =>
      _done.future.timeout(limit, onTimeout: onTimeout);
  @override
  Future<void> whenComplete(FutureOr<void> Function() action) =>
      _done.future.whenComplete(action);
}

/// Calls back about sixty times a second while it runs: the clock a game loop
/// or a hand-rolled animation is driven by.
///
/// Flutter's ticker fires once per engine frame. There is no engine here, so
/// this one is a 16 ms timer - and what a tick usually does is `setState`,
/// which is a whole build and a render message to the platform. That suits a
/// game drawing one `CustomPaint`; it does not suit a screen of five hundred
/// nodes, where an `AnimatedContainer` lets the renderer do the moving
/// instead.
class Ticker {
  Ticker(this._onTick, {this.debugLabel});

  final TickerCallback _onTick;
  final String? debugLabel;

  Timer? _timer;
  TickerFuture? _future;
  final Stopwatch _clock = Stopwatch();

  /// While true the ticker keeps time but does not call back.
  bool muted = false;

  /// Whether [start] has been called and [stop] has not.
  bool get isActive => _timer != null;

  /// Whether a tick will actually reach the callback.
  bool get isTicking => isActive && !muted;

  /// Starts ticking. The elapsed time handed to the callback starts at zero.
  TickerFuture start() {
    assert(_timer == null, 'A Ticker was started twice without a stop().');
    final future = _future = TickerFuture._();
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!muted) _onTick(_clock.elapsed);
    });
    return future;
  }

  /// Stops ticking; [start] may be called again.
  void stop({bool canceled = false}) {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _future?._complete();
    _future = null;
  }

  /// Stops for good.
  void dispose() => stop(canceled: true);
}

/// Something that makes [Ticker]s - a `State` with one of the mixins below,
/// which is what `vsync: this` hands over.
abstract class TickerProvider {
  Ticker createTicker(TickerCallback onTick);
}

/// Gives a `State` one [Ticker], stopped when the state is disposed.
mixin SingleTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    assert(
      _ticker == null,
      'A SingleTickerProviderStateMixin makes one ticker; use '
      'TickerProviderStateMixin for more.',
    );
    return _ticker = Ticker(onTick);
  }

  @override
  void dispose() {
    // Flutter asserts the app stopped it; a timer left running would keep
    // rebuilding a screen that is gone, so here it is simply stopped.
    _ticker?.dispose();
    super.dispose();
  }
}

/// Gives a `State` any number of [Ticker]s, stopped when it is disposed.
mixin TickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  final List<Ticker> _tickers = [];

  @override
  Ticker createTicker(TickerCallback onTick) {
    final ticker = Ticker(onTick);
    _tickers.add(ticker);
    return ticker;
  }

  @override
  void dispose() {
    for (final ticker in _tickers) {
      ticker.dispose();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Hardware keys.
// ---------------------------------------------------------------------------

/// A key as the layout names it, with Flutter's ids for the keys an app tests
/// against: arrows, the editing keys, letters and digits.
class LogicalKeyboardKey {
  const LogicalKeyboardKey(this.keyId, [this._label]);

  final int keyId;
  final String? _label;

  /// A printable name: 'A', 'Arrow Up', 'Enter'.
  String get keyLabel => _label ?? String.fromCharCode(keyId).toUpperCase();

  static const LogicalKeyboardKey backspace = LogicalKeyboardKey(
    0x100000008,
    'Backspace',
  );
  static const LogicalKeyboardKey tab = LogicalKeyboardKey(0x100000009, 'Tab');
  static const LogicalKeyboardKey enter = LogicalKeyboardKey(
    0x10000000d,
    'Enter',
  );
  static const LogicalKeyboardKey escape = LogicalKeyboardKey(
    0x10000001b,
    'Escape',
  );
  static const LogicalKeyboardKey delete = LogicalKeyboardKey(
    0x10000007f,
    'Delete',
  );
  static const LogicalKeyboardKey arrowDown = LogicalKeyboardKey(
    0x100000301,
    'Arrow Down',
  );
  static const LogicalKeyboardKey arrowLeft = LogicalKeyboardKey(
    0x100000302,
    'Arrow Left',
  );
  static const LogicalKeyboardKey arrowRight = LogicalKeyboardKey(
    0x100000303,
    'Arrow Right',
  );
  static const LogicalKeyboardKey arrowUp = LogicalKeyboardKey(
    0x100000304,
    'Arrow Up',
  );
  static const LogicalKeyboardKey end = LogicalKeyboardKey(0x100000305, 'End');
  static const LogicalKeyboardKey home = LogicalKeyboardKey(
    0x100000306,
    'Home',
  );
  static const LogicalKeyboardKey pageDown = LogicalKeyboardKey(
    0x100000307,
    'Page Down',
  );
  static const LogicalKeyboardKey pageUp = LogicalKeyboardKey(
    0x100000308,
    'Page Up',
  );
  static const LogicalKeyboardKey controlLeft = LogicalKeyboardKey(
    0x200000100,
    'Control Left',
  );
  static const LogicalKeyboardKey shiftLeft = LogicalKeyboardKey(
    0x200000102,
    'Shift Left',
  );
  static const LogicalKeyboardKey altLeft = LogicalKeyboardKey(
    0x200000104,
    'Alt Left',
  );
  static const LogicalKeyboardKey metaLeft = LogicalKeyboardKey(
    0x200000106,
    'Meta Left',
  );
  static const LogicalKeyboardKey space = LogicalKeyboardKey(0x20, 'Space');

  static const LogicalKeyboardKey digit0 = LogicalKeyboardKey(0x30);
  static const LogicalKeyboardKey digit1 = LogicalKeyboardKey(0x31);
  static const LogicalKeyboardKey digit2 = LogicalKeyboardKey(0x32);
  static const LogicalKeyboardKey digit3 = LogicalKeyboardKey(0x33);
  static const LogicalKeyboardKey digit4 = LogicalKeyboardKey(0x34);
  static const LogicalKeyboardKey digit5 = LogicalKeyboardKey(0x35);
  static const LogicalKeyboardKey digit6 = LogicalKeyboardKey(0x36);
  static const LogicalKeyboardKey digit7 = LogicalKeyboardKey(0x37);
  static const LogicalKeyboardKey digit8 = LogicalKeyboardKey(0x38);
  static const LogicalKeyboardKey digit9 = LogicalKeyboardKey(0x39);

  static const LogicalKeyboardKey keyA = LogicalKeyboardKey(0x61);
  static const LogicalKeyboardKey keyB = LogicalKeyboardKey(0x62);
  static const LogicalKeyboardKey keyC = LogicalKeyboardKey(0x63);
  static const LogicalKeyboardKey keyD = LogicalKeyboardKey(0x64);
  static const LogicalKeyboardKey keyE = LogicalKeyboardKey(0x65);
  static const LogicalKeyboardKey keyF = LogicalKeyboardKey(0x66);
  static const LogicalKeyboardKey keyG = LogicalKeyboardKey(0x67);
  static const LogicalKeyboardKey keyH = LogicalKeyboardKey(0x68);
  static const LogicalKeyboardKey keyI = LogicalKeyboardKey(0x69);
  static const LogicalKeyboardKey keyJ = LogicalKeyboardKey(0x6a);
  static const LogicalKeyboardKey keyK = LogicalKeyboardKey(0x6b);
  static const LogicalKeyboardKey keyL = LogicalKeyboardKey(0x6c);
  static const LogicalKeyboardKey keyM = LogicalKeyboardKey(0x6d);
  static const LogicalKeyboardKey keyN = LogicalKeyboardKey(0x6e);
  static const LogicalKeyboardKey keyO = LogicalKeyboardKey(0x6f);
  static const LogicalKeyboardKey keyP = LogicalKeyboardKey(0x70);
  static const LogicalKeyboardKey keyQ = LogicalKeyboardKey(0x71);
  static const LogicalKeyboardKey keyR = LogicalKeyboardKey(0x72);
  static const LogicalKeyboardKey keyS = LogicalKeyboardKey(0x73);
  static const LogicalKeyboardKey keyT = LogicalKeyboardKey(0x74);
  static const LogicalKeyboardKey keyU = LogicalKeyboardKey(0x75);
  static const LogicalKeyboardKey keyV = LogicalKeyboardKey(0x76);
  static const LogicalKeyboardKey keyW = LogicalKeyboardKey(0x77);
  static const LogicalKeyboardKey keyX = LogicalKeyboardKey(0x78);
  static const LogicalKeyboardKey keyY = LogicalKeyboardKey(0x79);
  static const LogicalKeyboardKey keyZ = LogicalKeyboardKey(0x7a);

  static const Map<String, LogicalKeyboardKey> _byName = {
    'ArrowUp': arrowUp,
    'ArrowDown': arrowDown,
    'ArrowLeft': arrowLeft,
    'ArrowRight': arrowRight,
    'Enter': enter,
    'Escape': escape,
    'Backspace': backspace,
    'Tab': tab,
    'Delete': delete,
    'Home': home,
    'End': end,
    'PageUp': pageUp,
    'PageDown': pageDown,
    'Shift': shiftLeft,
    'Control': controlLeft,
    'Alt': altLeft,
    'Meta': metaLeft,
    ' ': space,
    'Space': space,
    'Spacebar': space,
  };

  /// The key a renderer's `KeyboardEvent.key`-style [name] stands for.
  ///
  /// A letter is the same key whichever case it arrived in, as in Flutter,
  /// where the logical key of Shift+A is still `keyA`. A name outside the
  /// table gets an id of its own, so two presses of it still compare equal.
  factory LogicalKeyboardKey._named(String name) {
    final known = _byName[name];
    if (known != null) return known;
    if (name.runes.length == 1) {
      final code = name.toLowerCase().runes.first;
      return LogicalKeyboardKey(code);
    }
    return LogicalKeyboardKey(0x1100000000 + name.hashCode.abs(), name);
  }

  @override
  bool operator ==(Object other) =>
      other is LogicalKeyboardKey && other.keyId == keyId;
  @override
  int get hashCode => keyId.hashCode;
  @override
  String toString() => 'LogicalKeyboardKey#$keyId($keyLabel)';
}

/// A hardware key event. It is a [KeyDownEvent] or a [KeyUpEvent].
abstract class KeyEvent {
  const KeyEvent({required this.logicalKey, this.character});

  final LogicalKeyboardKey logicalKey;

  /// The text the press produces, when it produces one.
  final String? character;
}

class KeyDownEvent extends KeyEvent {
  const KeyDownEvent({required super.logicalKey, super.character});
}

class KeyUpEvent extends KeyEvent {
  const KeyUpEvent({required super.logicalKey}) : super(character: null);
}

/// Declared so `event is KeyRepeatEvent` compiles; the renderers report a
/// held key as repeated downs, so none is ever sent.
class KeyRepeatEvent extends KeyEvent {
  const KeyRepeatEvent({required super.logicalKey, super.character});
}

/// Hears the hardware keyboard while it is on screen.
///
/// Flutter routes keys through a focus tree and this listener hears them only
/// while its [focusNode] has focus. The protocol has no focus tree for
/// anything but text fields, so "has focus" is read from what the app asked:
/// a listener whose [focusNode] was sent `requestFocus()`, or that says
/// [autofocus], hears alone - the most recently asked, when several were.
/// With no such ask, every listener on screen hears every key, which is all
/// a game with one listener needs.
///
/// A dialog or sheet takes the keyboard while it is open: listeners on the
/// page behind it hear nothing, and one inside it does.
class KeyboardListener extends Widget {
  const KeyboardListener({
    super.key,
    required this.focusNode,
    this.autofocus = false,
    this.includeSemantics = true,
    this.onKeyEvent,
    required this.child,
  });

  final FocusNode focusNode;
  final bool autofocus;
  final bool includeSemantics;
  final ValueChanged<KeyEvent>? onKeyEvent;
  final Widget child;

  @override
  WidgetNode _render(_Owner owner) {
    final handler = onKeyEvent;
    // Once, when the listener first appears: asking again on every build
    // would take the keys back from whoever was given them since.
    if (autofocus && !focusNode._autofocused) {
      focusNode
        .._autofocused = true
        .._askedAt = ++FocusNode._asks;
    }
    // A page that is only being kept alive must not steer the one on screen.
    if (handler != null && owner._hidden == 0) {
      owner._keyListeners.add(
        _KeyListener(handler, focusNode, owner._buildingOverlay),
      );
    }
    return owner.inSlot('child', () => child._render(owner));
  }
}

/// A [KeyboardListener] the build came across: what to call, the node that
/// says whether it was asked for focus, and the dialog or sheet it is in.
class _KeyListener {
  const _KeyListener(this.handler, this.node, this.overlay);
  final void Function(KeyEvent event) handler;
  final FocusNode node;
  final _OverlayEntry? overlay;
}

// ---------------------------------------------------------------------------
// Locale and time of day.
// ---------------------------------------------------------------------------

/// The languages written right to left: the six Flutter's
/// `GlobalWidgetsLocalizations` knows - Arabic, Farsi, Hebrew, Pashto, Sindhi,
/// Urdu - and three it has no translations for and so never lists, which are
/// right-to-left all the same: Uyghur, Yiddish and Dhivehi.
const Set<String> _rtlLanguages = {
  'ar', 'fa', 'he', 'ps', 'sd', 'ur', 'ug', 'yi', 'dv',
  // Hebrew's code before 1989, which some platforms still report.
  'iw',
};

/// The direction [locale]'s language is read in.
TextDirection _directionOf(Locale locale) =>
    _rtlLanguages.contains(locale.languageCode.toLowerCase())
    ? TextDirection.rtl
    : TextDirection.ltr;

/// The reading direction of everything below it: Flutter's `Directionality`.
///
/// A [MaterialApp] provides one from its locale - right to left for Arabic,
/// Hebrew, Farsi, Urdu and the rest of [_rtlLanguages] - so most apps never
/// build one. An app that wants a direction its locale does not imply puts
/// one in `MaterialApp(builder:)`, above the pages, exactly as in Flutter.
///
/// Two things follow it. The widget layer's directional values -
/// [EdgeInsetsDirectional], [AlignmentDirectional], [BorderRadiusDirectional],
/// a [ListTile]'s padding, [TextAlign.end] - are resolved against the nearest
/// one, wherever it is. And the renderers are told the *screen's* direction,
/// once, on the root of the tree: the one around the app's pages. So a
/// `Directionality` deep in a screen turns the values below it but not the
/// renderer's own furniture there - a [Row] under it is put in the right
/// order by reversing its children, and a platform control is still drawn the
/// way the screen reads.
class Directionality extends InheritedWidget {
  const Directionality({
    super.key,
    required this.textDirection,
    required super.child,
  });

  final TextDirection textDirection;

  /// The direction in force at [context]. Left to right where nothing above
  /// says otherwise, which is where Flutter would assert: an app with no
  /// [MaterialApp] has not been asked to say.
  static TextDirection of(BuildContext context) =>
      maybeOf(context) ?? TextDirection.ltr;

  /// As [of], but null where no [Directionality] is above [context].
  static TextDirection? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<Directionality>()
      ?.textDirection;

  @override
  bool updateShouldNotify(Directionality oldWidget) =>
      oldWidget.textDirection != textDirection;

  @override
  WidgetNode _render(_Owner owner) {
    owner._outerDirection ??= textDirection;
    return super._render(owner);
  }
}

/// The locale the app is showing, visible to everything below [MaterialApp].
class _LocaleScope extends InheritedWidget {
  const _LocaleScope({
    required this.locale,
    this.resources = const {},
    required super.child,
  });
  final Locale locale;

  /// What the app's [LocalizationsDelegate]s loaded for [locale], by type.
  final Map<Type, Object?> resources;

  @override
  bool updateShouldNotify(_LocaleScope oldWidget) {
    if (oldWidget.locale != locale) return true;
    if (oldWidget.resources.length != resources.length) return true;
    for (final entry in resources.entries) {
      if (!identical(oldWidget.resources[entry.key], entry.value)) return true;
    }
    return false;
  }
}

/// Loads an app's strings for a locale: Flutter's `LocalizationsDelegate`.
///
/// A delegate written for Flutter - the one `intl` or gen-l10n generates
/// beside its `AppLocalizations` class - moves over by changing its import,
/// as long as its [load] needs nothing of Flutter's. Hand it to
/// `MaterialApp(localizationsDelegates:)` and read what it loaded with
/// `Localizations.of<T>(context, T)`, both as in Flutter.
///
/// What differs is the first frame. Flutter holds the app back until every
/// delegate has loaded; here the app is drawn at once and
/// [Localizations.of] answers null until [load] completes, when the app is
/// rebuilt. A lookup therefore needs a fallback - `?? AppLocalizations()` -
/// for that frame, and for a locale no delegate supports.
abstract class LocalizationsDelegate<T> {
  const LocalizationsDelegate();

  /// Whether this delegate has strings for [locale].
  bool isSupported(Locale locale);

  /// Loads them.
  Future<T> load(Locale locale);

  /// Whether to load again when the app is rebuilt with a new delegate in
  /// place of [old]. A change of locale always loads again.
  bool shouldReload(covariant LocalizationsDelegate<T> old);

  /// The type [Localizations.of] is asked for.
  Type get type => T;

  @override
  String toString() => '$runtimeType[$type]';
}

/// Reads the locale an app is running in, as Flutter's `Localizations` does.
///
/// The framework's own translations live in `I18n` (see [Tr]); this is the
/// part of Flutter's class that code asks a question of.
abstract final class Localizations {
  /// The app's `locale`; failing that the first of its `supportedLocales` in
  /// the device's language; failing that the device's own.
  static Locale localeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LocaleScope>()?.locale ??
      _platformLocale();

  /// As [localeOf], which always has an answer here.
  static Locale? maybeLocaleOf(BuildContext context) => localeOf(context);

  /// What the [LocalizationsDelegate] for [type] loaded for the locale the
  /// app is showing; null before it has finished loading and when the app
  /// gave no delegate of that type that supports the locale.
  static T? of<T>(BuildContext context, Type type) {
    final loaded = context
        .dependOnInheritedWidgetOfExactType<_LocaleScope>()
        ?.resources[type];
    return loaded is T ? loaded : null;
  }
}

Locale _platformLocale() {
  try {
    return Locale.fromString(platform_binding.platformLocale());
  } catch (_) {
    return const Locale('en');
  }
}

/// The locale a [MaterialApp] shows, from what it was given.
Locale _resolveLocale(Locale? locale, Iterable<Locale> supported) {
  if (locale != null) return locale;
  final device = _platformLocale();
  Locale? sameLanguage;
  for (final candidate in supported) {
    if (candidate.languageCode != device.languageCode) continue;
    if (candidate.countryCode == device.countryCode) return candidate;
    sameLanguage ??= candidate;
  }
  return sameLanguage ?? device;
}

/// Morning or afternoon.
enum DayPeriod { am, pm }

/// A time of day without a date: Flutter's `TimeOfDay`.
class TimeOfDay {
  const TimeOfDay({required this.hour, required this.minute});

  /// The time of [time], dropping its date.
  TimeOfDay.fromDateTime(DateTime time)
    : hour = time.hour,
      minute = time.minute;

  /// The time now.
  TimeOfDay.now() : this.fromDateTime(DateTime.now());

  static const int hoursPerDay = 24;
  static const int hoursPerPeriod = 12;
  static const int minutesPerHour = 60;

  /// 0 to 23.
  final int hour;

  /// 0 to 59.
  final int minute;

  DayPeriod get period => hour < hoursPerPeriod ? DayPeriod.am : DayPeriod.pm;

  /// The hour on a twelve-hour clock, where noon and midnight are 12.
  int get hourOfPeriod {
    final inPeriod = hour % hoursPerPeriod;
    return inPeriod == 0 ? hoursPerPeriod : inPeriod;
  }

  TimeOfDay replacing({int? hour, int? minute}) =>
      TimeOfDay(hour: hour ?? this.hour, minute: minute ?? this.minute);

  /// The time as the app's locale writes it: `3:05 PM` in American English,
  /// `15:05` in British, `15.05` in Finnish, `下午 3:05` in Chinese.
  ///
  /// Flutter's answer for the same locale - the pattern and the words for
  /// the halves of the day are its own, taken from `flutter_localizations`
  /// (`src/time_formats.dart`). Under
  /// [MediaQueryData.alwaysUse24HourFormat] a locale that writes a
  /// twelve-hour clock writes `HH:mm` instead, as in Flutter. The digits are
  /// always 0 to 9: Flutter writes a locale's own where it has them.
  ///
  /// A language Flutter has no localization for gets `HH:mm`.
  String format(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final language = locale.languageCode;
    final script = locale.scriptCode;
    final country = locale.countryCode;
    var (pattern, am, pm) =
        timeOfDayFormats[[language, ?script, ?country].join('_')] ??
        timeOfDayFormats[[language, ?country].join('_')] ??
        timeOfDayFormats[[language, ?script].join('_')] ??
        timeOfDayFormats[language] ??
        const ('HH:mm', 'AM', 'PM');
    if (MediaQuery.alwaysUse24HourFormatOf(context) &&
        (pattern == 'h:mm a' || pattern == 'a h:mm')) {
      pattern = 'HH:mm';
    }
    final minutes = minute.toString().padLeft(2, '0');
    final padded = hour.toString().padLeft(2, '0');
    final half = period == DayPeriod.am ? am : pm;
    return switch (pattern) {
      'h:mm a' => '$hourOfPeriod:$minutes $half',
      'a h:mm' => '$half $hourOfPeriod:$minutes',
      'H:mm' => '$hour:$minutes',
      'HH.mm' => '$padded.$minutes',
      "HH 'h' mm" => '$padded h $minutes',
      _ => '$padded:$minutes',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TimeOfDay && other.hour == hour && other.minute == minute;
  @override
  int get hashCode => Object.hash(hour, minute);
  @override
  String toString() =>
      'TimeOfDay(${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')})';
}
