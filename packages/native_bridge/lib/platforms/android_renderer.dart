/// Android Native Renderer
/// Converts widget trees to native Android Views via platform channel

import 'package:flutter/services.dart';
import '../src/app_theme.dart';
import '../src/frame_probe.dart';
import '../src/render_error.dart';
import 'native_frame_probe.dart';
import '../src/render_scheduler.dart';
import '../src/ui_renderer.dart';

export 'android_ui_builder.dart';

/// Android implementation of native UI renderer
/// Renders widget trees to Android Views
class AndroidNativeRenderer implements NativeUIRenderer, HasFrameProbe {
  static const platform = MethodChannel(
    'com.programtom.dart_not_native/renderer',
  );

  /// Records the frames the *native* views present - Flutter is only
  /// hosting the engine here, so its own timings would measure an idle
  /// screen.
  @override
  FrameProbe get frameProbe => NativeFrameProbe(platform);

  final Map<String, Function(Map<String, dynamic>)> eventHandlers = {};

  /// Whether the renders of one tick are coalesced into one message.
  final bool batched;

  /// The app's colour theme, sent to the native side with `initialize`.
  final AppTheme theme;

  AndroidNativeRenderer({this.batched = true, this.theme = AppTheme.fallback}) {
    // The native side reports what its views did; every handler lives here, so
    // this is the whole of the return path.
    platform.setMethodCallHandler(_onNativeCall);
  }

  /// Handles a call from the native renderer.
  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method != 'event') return null;
    final arguments = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
    final eventId = arguments['eventId'] as String?;
    if (eventId == null) return null;
    final data =
        (arguments['data'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value),
        ) ??
        <String, dynamic>{};
    return handleEvent(eventId, data);
  }

  /// Initialize the renderer and setup event channel
  static Future<void> initialize() async {
    try {
      await platform.invokeMethod('initialize');
      print('AndroidNativeRenderer initialized');
    } catch (e) {
      print('Failed to initialize AndroidNativeRenderer: $e');
    }
  }

  /// Renders [tree], coalescing the renders of one tick into one message.
  ///
  /// The native side diffs the tree it receives against the one on screen and
  /// patches only what changed (`renderTree` in
  /// `android/src/main/kotlin/.../NativeUIRenderer.kt`), falling back to a full
  /// rebuild when the shape changes.
  ///
  /// Each render still crosses the platform channel and walks the whole tree,
  /// so a burst of state changes sending one message instead of five is the
  /// difference between one diff and five.
  @override
  Future<RenderError?> render(WidgetNode tree) => _scheduler.schedule(tree);

  late final RenderScheduler _scheduler = RenderScheduler(
    _send,
    batched: batched,
  );

  bool _initialized = false;

  /// Whether the native half of this renderer is present and ready.
  ///
  /// A host that never constructed it, or a build without the plugin, answers
  /// with a missing-plugin error - which is what lets a caller fall back to
  /// another renderer instead of showing an empty screen.
  Future<bool> isAvailable() async {
    if (_initialized) return true;
    try {
      await platform.invokeMethod('initialize', theme.toJson());
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<RenderError?> _send(WidgetNode tree) async {
    try {
      // Initialising on the first render removes a call the app would
      // otherwise have to make in the right order.
      if (!_initialized) {
        await platform.invokeMethod('initialize', theme.toJson());
        _initialized = true;
      }
      final json = tree.toJson();
      // The native half answers with what it could not draw, structured; see
      // RenderError.fromChannel, which also reads the bare string older halves
      // returned.
      return RenderError.fromChannel(await platform.invokeMethod('render', json));
    } catch (e, stackTrace) {
      return RenderError.failed('Render error: $e', cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<dynamic> handleEvent(String eventId, Map<String, dynamic> data) async {
    final handler = eventHandlers[eventId];
    if (handler != null) {
      handler(data);
      return {'success': true};
    }
    return {'success': false, 'error': 'Handler not found for $eventId'};
  }

  /// Register event handler for native UI events
  @override
  void onEvent(String eventId, Function(Map<String, dynamic>) handler) {
    eventHandlers[eventId] = handler;
  }

  /// Setup to receive events from native side
  /// This should be called in the app to bridge native events to Dart
  static Future<void> setupEventChannel() async {
    const eventChannel = EventChannel('com.programtom.dart_not_native/events');
    eventChannel.receiveBroadcastStream().listen((event) {
      // Events are received as: {'eventId': 'increment', 'data': {...}}
      // The app should forward these to the renderer
      print('Event from native: $event');
    });
  }
}
