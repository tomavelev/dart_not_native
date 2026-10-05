/// Lets the platform back gesture close the topmost dialog or bottom sheet.
///
/// Overlays are part of the tree the app builds, so the app - not a renderer -
/// knows which one is on top. After each build this finds the last `Dialog` or
/// `BottomSheet` in the tree and, while there is one, holds a [SystemBack]
/// handler. Registered when the first overlay appears, it is newer than the
/// router's handler and so gets the gesture first.
///
/// Back sends the overlay's `dismissEventId` with `{'reason': 'back'}`; the app
/// removes the overlay from its state as it would for a tap on the scrim. An
/// overlay that cannot be dismissed still consumes the gesture, so Back never
/// navigates the screen underneath an open modal.
library;

import 'system_back.dart';
import 'ui_renderer.dart';

class OverlayBack {
  NativeUIRenderer? _renderer;
  WidgetNode? _top;
  bool _registered = false;

  /// Node types that take the back gesture while open.
  ///
  /// The pickers are in the list for the same reason a dialog is: each is
  /// modal, and each fires its dismiss event when it is sent away.
  static const modalTypes = {'Dialog', 'BottomSheet', 'DatePicker', 'TimePicker'};

  /// Tracks the modal overlays in [tree], rendered by [renderer].
  void track(WidgetNode tree, NativeUIRenderer renderer) {
    _renderer = renderer;
    _top = topmostModal(tree);
    if (_top != null && !_registered) {
      SystemBack.addHandler(_handleBack);
      _registered = true;
    } else if (_top == null && _registered) {
      SystemBack.removeHandler(_handleBack);
      _registered = false;
    }
  }

  /// Stops taking the back gesture.
  void dispose() {
    if (_registered) SystemBack.removeHandler(_handleBack);
    _registered = false;
    _top = null;
  }

  /// The last modal overlay in [tree] in depth-first order - the one drawn on
  /// top - or null.
  static WidgetNode? topmostModal(WidgetNode tree) {
    WidgetNode? found;
    void visit(WidgetNode node) {
      if (modalTypes.contains(node.type)) found = node;
      for (final child in node.children ?? const <WidgetNode>[]) {
        visit(child);
      }
    }

    visit(tree);
    return found;
  }

  bool _handleBack() {
    final top = _top;
    if (top == null) return false;
    final eventId = top.props['dismissEventId'];
    if (top.props['dismissible'] != false && eventId is String) {
      _renderer?.handleEvent(eventId, {'reason': 'back'});
    }
    return true;
  }
}
