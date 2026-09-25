/// Coalesces the renders of one tick into a single pass.
///
/// An app that changes state several times before yielding - a handler that
/// updates two fields, a loop over incoming events - would otherwise pay for
/// one full render per change. Only the last tree of a tick can be visible, so
/// only the last one is rendered.
///
/// The future returned by [schedule] completes once that tree has been
/// rendered, so `await render(...)` still means "the UI is up to date".
library;

import 'dart:async';

import 'render_error.dart';
import 'ui_renderer.dart';

class RenderScheduler {
  RenderScheduler(this._flush, {this.batched = true});

  /// Performs the actual render. Called at most once per tick.
  final Future<RenderError?> Function(WidgetNode tree) _flush;

  /// Whether to coalesce. False renders immediately, for a host that needs the
  /// UI updated by the time `render` returns without awaiting it.
  final bool batched;

  WidgetNode? _pending;
  Completer<RenderError?>? _completer;
  bool _scheduled = false;

  /// Whether a render is waiting for the next microtask.
  bool get hasPendingRender => _pending != null;

  Future<RenderError?> schedule(WidgetNode tree) {
    _pending = tree;
    final completer = _completer ??= Completer<RenderError?>();
    if (!batched) {
      _run();
      return completer.future;
    }
    if (!_scheduled) {
      _scheduled = true;
      scheduleMicrotask(_run);
    }
    return completer.future;
  }

  void _run() {
    _scheduled = false;
    final tree = _pending;
    final completer = _completer;
    _pending = null;
    _completer = null;
    if (tree == null || completer == null) return;

    _flush(tree).then(completer.complete).catchError((Object e, StackTrace st) {
      completer.complete(
        RenderError.failed('Render error: $e', cause: e, stackTrace: st),
      );
      return null;
    });
  }
}
