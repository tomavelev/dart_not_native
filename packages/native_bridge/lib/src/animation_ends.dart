/// When a moving node has got where it was going: what a renderer that
/// starts a node's animation the moment it applies a tree answers.
library;

import 'dart:async';

import 'ui_renderer.dart';

/// Answers the asks a tree's moving nodes make.
///
/// A node whose implicit animation is on its way carries `endEventId` and
/// `endAsk`, a number for the change it is making. A renderer that animates
/// a node from the moment it applies the tree - the browser's transitions,
/// Flutter's implicit animations - knows when that ends: the node's
/// `animateMs` (`durationMs` for a fade) later. [follow] is handed each tree
/// as it is applied, and answers each new ask `{ask}` then - or at once,
/// when the renderer is not animating.
class AnimationEnds {
  AnimationEnds(this._answer);

  final void Function(String eventId, Map<String, dynamic> data) _answer;

  /// The ask each event was last given, and the timer answering it.
  final Map<String, int> _asked = {};
  final Map<String, Timer> _timers = {};

  /// Notes the asks in [tree] that were not in the trees before it.
  void follow(WidgetNode tree, {required bool animating}) {
    final seen = <String>{};
    _walk(tree, seen, animating);
    // A node that has stopped asking - it got there, or it is gone - is
    // forgotten, so asking again with the same number is a new ask.
    _asked.removeWhere((id, _) => !seen.contains(id));
  }

  void _walk(WidgetNode node, Set<String> seen, bool animating) {
    final id = node.props['endEventId'];
    final ask = node.props['endAsk'];
    if (id is String && ask is num) {
      seen.add(id);
      if (_asked[id] != ask.toInt()) {
        _asked[id] = ask.toInt();
        _timers.remove(id)?.cancel();
        final ms = node.props['animateMs'] ?? node.props['durationMs'];
        final wait = animating && ms is num && ms > 0
            ? Duration(milliseconds: ms.toInt())
            : Duration.zero;
        _timers[id] = Timer(wait, () {
          _timers.remove(id);
          _answer(id, {'ask': ask.toInt()});
        });
      }
    }
    for (final child in node.children ?? const <WidgetNode>[]) {
      _walk(child, seen, animating);
    }
  }

  /// Stops every answer still to come.
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
