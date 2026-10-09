/// What every widget here that listens to a bloc shares: knowing when it has
/// left the tree, and asking for one rebuild rather than several.
library;

import 'dart:async';

import 'package:dart_not_native/widgets.dart';

/// A [State] that knows when it has left the tree.
///
/// A stream keeps delivering to a subscriber until it is cancelled, and an
/// event already on its way arrives after `dispose`; everything here that
/// listens to a bloc checks [alive] before acting on what it hears.
abstract class LiveState<T extends StatefulWidget> extends State<T> {
  bool _alive = true;
  bool get alive => _alive;

  /// Asked for a rebuild that has not reached it yet.
  bool _stale = false;

  /// Call first thing in `build`: whatever rebuild this asked for has come.
  void markBuilt() => _stale = false;

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

final List<LiveState> _asked = [];
bool _rebuildScheduled = false;

/// Asks for the tree [state] is in to be rebuilt, once, however many ask.
///
/// A rebuild here redraws from the root, so three builders watching one bloc
/// would otherwise draw the whole tree three times for one emit. They are
/// each told in the same turn of the event loop; this waits for the end of it
/// and rebuilds once.
void requestRebuild(LiveState state) {
  state._stale = true;
  _asked.add(state);
  if (_rebuildScheduled) return;
  _rebuildScheduled = true;
  scheduleMicrotask(() {
    _rebuildScheduled = false;
    final asked = _asked.toList();
    _asked.clear();
    for (final state in asked) {
      // The first rebuild redraws everything in its tree, which builds the
      // others that asked and so answers them too. One still stale after
      // that is in a different tree - a second app mounted beside this one -
      // and needs a rebuild of its own.
      if (!state.alive || !state._stale) continue;
      state._stale = false;
      state.setState(() {});
    }
  });
}
