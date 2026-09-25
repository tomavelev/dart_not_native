/// Lets a widget tree carry callbacks instead of event-id strings.
///
/// The protocol a renderer speaks is string-based: a node names an `eventId`,
/// and the app registers a handler for that name. Written by hand that means
/// every button appears twice - once in `build`, once in `init` - and nothing
/// checks that the two agree.
///
/// A builder called with a callback instead allocates an id, registers the
/// callback under it for the duration of the build, and puts the id in the
/// node. The wire format is unchanged; only the authoring is.
///
/// ```dart
/// @override
/// WidgetNode build() => UIBuilder.button(
///       label: 'Increment',
///       onPressed: () => setState(() => count++),
///     );
/// ```
///
/// Ids are derived from the node's own `id` when it has one, and otherwise
/// from the order of the call within the build. Both are stable from one
/// render to the next, which matters: an id that changed every render would
/// change the node's props and make every renderer rebuild the element.
library;

import 'ui_renderer.dart';

class EventBindings {
  /// The bindings collecting callbacks for the build that is running, if any.
  static EventBindings? current;

  /// Callbacks of the current build, by full event id.
  final Map<String, void Function(Map<String, dynamic>)> _callbacks = {};

  /// Event ids already registered with the renderer. The registered function
  /// looks the callback up on each event, so a rebuild replaces behaviour
  /// without registering anything again.
  final Set<String> _registered = {};

  /// State a builder keeps from one build to the next, by key.
  final Map<String, Object> _retained = {};

  /// Keys of [_retained] used by the build that is running.
  final Set<String> _touched = {};

  NativeUIRenderer? _renderer;
  void Function()? _invalidate;
  int _counter = 0;

  /// Runs [build] with this instance installed, collecting its callbacks.
  ///
  /// [invalidate] is what a builder's own handler calls to have the tree built
  /// again - a lazy list whose visible rows moved, say.
  WidgetNode runBuild(
    NativeUIRenderer renderer,
    WidgetNode Function() build, {
    void Function()? invalidate,
  }) {
    final previous = current;
    current = this;
    _renderer = renderer;
    _invalidate = invalidate;
    _counter = 0;
    _callbacks.clear();
    _touched.clear();
    try {
      return build();
    } finally {
      current = previous;
      // State no builder asked for this time belongs to a node that is gone.
      _retained.removeWhere((key, _) => !_touched.contains(key));
    }
  }

  /// State kept under [key] across builds, created by [create] the first time.
  ///
  /// It lives as long as each build asks for it: a node left out of one build
  /// starts afresh when it comes back.
  T retain<T extends Object>(String key, T Function() create) {
    _touched.add(key);
    return _retained.putIfAbsent(key, create) as T;
  }

  /// Builds the tree again, for a handler whose state change is not the app's.
  void invalidate() => _invalidate?.call();

  /// The bindings for the running build, or a clear error when a builder was
  /// called with a callback outside one.
  static EventBindings get required =>
      current ??
      (throw StateError(
        'A builder was given a callback outside of a build. Callbacks are '
        'bound while NativeUIApp.build() runs; pass an eventId instead when '
        'building a node elsewhere.',
      ));

  /// Allocates the event id a node will carry.
  ///
  /// [key] is the node's own id when it has one, so the event id does not move
  /// when the node does - a row inserted above it keeps every row's handlers
  /// pointing at the same rows.
  String allocate({String? key}) => 'cb:${key ?? _counter++}';

  /// Registers [handler] for [eventId] for the rest of this build.
  void on(String eventId, void Function(Map<String, dynamic>) handler) {
    _callbacks[eventId] = handler;
    if (_registered.add(eventId)) {
      _renderer!.onEvent(eventId, (data) => _callbacks[eventId]?.call(data));
    }
  }

  /// Binds a tap: the node fires [eventId] with no payload of its own.
  void onTap(String eventId, void Function() handler) =>
      on(eventId, (_) => handler());

  /// Binds a checkbox or switch, whose event carries its new state under
  /// [field].
  void onToggle(
    String eventId,
    void Function(bool value) handler, {
    String field = 'checked',
  }) => on(eventId, (data) => handler(data[field] == true));

  /// Binds a slider's events: the renderer sends `<eventId>_change` as the
  /// thumb moves and `<eventId>_end` when it is released.
  void onSlide(
    String eventId, {
    void Function(double value)? onChanged,
    void Function(double value)? onChangeEnd,
  }) {
    double read(Map<String, dynamic> data) =>
        (data['value'] as num?)?.toDouble() ?? 0;
    if (onChanged != null) {
      on('${eventId}_change', (data) => onChanged(read(data)));
    }
    if (onChangeEnd != null) {
      on('${eventId}_end', (data) => onChangeEnd(read(data)));
    }
  }

  /// Binds the text field events derived from [eventId]: the renderer sends
  /// `<eventId>_change`, `_submit`, `_focus` and `_blur`.
  void onText(
    String eventId, {
    void Function(String value)? onChanged,
    void Function(String value)? onSubmitted,
    void Function()? onFocus,
    void Function()? onBlur,
  }) {
    if (onChanged != null) {
      on('${eventId}_change', (data) => onChanged(_value(data)));
    }
    if (onSubmitted != null) {
      on('${eventId}_submit', (data) => onSubmitted(_value(data)));
    }
    if (onFocus != null) on('${eventId}_focus', (_) => onFocus());
    if (onBlur != null) on('${eventId}_blur', (_) => onBlur());
  }

  static String _value(Map<String, dynamic> data) =>
      data['value'] as String? ?? '';
}
