/// A real Flutter widget inside a screen the platform draws.
///
/// Some things only exist as Flutter widgets - an ad banner, a chart package.
/// A `FlutterSlot` node reserves a region for one:
///
/// ```dart
/// import 'package:dart_not_native/flutter_slot.dart';
///
/// flutterSlotNode(
///   slotId: 'banner',
///   height: 50,
///   builder: (context) => const AdBanner(),
///   fallback: UIBuilder.sizedBox(height: 50),
/// )
/// ```
///
/// What happens to it depends on who draws the screen:
///
/// * The **Flutter renderer** builds the widget right where the node is, like
///   any other.
/// * The **Android and iOS renderers** leave a see-through, touch-through hole
///   of the slot's size in their own views and report where it is. Flutter is
///   still running underneath those views - it hosts the engine - and
///   [FlutterSlotLayer] paints each registered widget at its reported
///   rectangle, so it shows through the hole. `runNativeApp(nativeViews:
///   true)` puts the layer there; nothing else is needed.
/// * A renderer with no Flutter engine (the web DOM one) draws the `fallback`.
///
/// This file imports Flutter, so import it only from code that runs under
/// Flutter. The registry itself (`FlutterSlots`) is pure Dart and part of the
/// core library.
///
/// ## Limits of the hole
///
/// The widget and the hole are drawn by two view systems that only meet
/// through a message, and it shows in two places:
///
/// * **The rectangle follows native scrolling a frame late.** The platform
///   moves the hole, then tells Dart, then Flutter repaints. During a fast
///   scroll the widget trails the hole by a frame; it lands exactly once the
///   scroll settles. A slot that does not scroll - pinned in a bottom bar,
///   say - never shows this.
/// * **Touches inside the hole go to Flutter.** That is what makes the widget
///   tappable, and it also means a scroll gesture that *starts* on the slot
///   does not scroll the native list around it: the platform's scroll view
///   never sees that touch. Start the drag anywhere else and the list
///   scrolls, slot and all.
///
/// The size comes from the tree, not from the widget: the platform lays the
/// hole out before Flutter knows it is there, so the widget is given the
/// slot's rectangle and has to fit it.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'src/flutter_slots.dart';
import 'src/ui_renderer.dart';

export 'src/flutter_slots.dart';

/// Builds the widget a slot shows.
typedef FlutterSlotBuilder = Widget Function(BuildContext context);

/// A `FlutterSlot` node showing what [builder] builds.
///
/// Registers [builder] under [slotId] and returns
/// [UIBuilder.flutterSlot] for it. Call it wherever the tree is built, every
/// time it is built - the registration lasts as long as the node stays in the
/// tree and goes with it.
///
/// [slotId] names the slot across builds, so the widget keeps its State while
/// the screen re-renders around it; two slots on screen at once need two ids.
/// [height] is required and [width] optional (the slot otherwise fills the
/// width it is offered), because the platform sizes the hole from the tree.
/// [fallback] is what a renderer without a Flutter engine draws instead.
WidgetNode flutterSlotNode({
  required String slotId,
  required double height,
  double? width,
  required FlutterSlotBuilder builder,
  WidgetNode? fallback,
}) {
  FlutterSlots.instance.register(slotId, builder);
  return UIBuilder.flutterSlot(
    slotId: slotId,
    height: height,
    width: width,
    fallback: fallback,
  );
}

/// Paints every registered slot's widget at the rectangle the platform
/// reported for it.
///
/// It goes behind the platform's views, filling the Flutter view, so its
/// coordinates are the ones the rectangles are reported in. The layer paints
/// nothing of its own and takes no touches outside the slots: a tap that
/// misses every slot falls through to whatever is under the layer.
///
/// A slot with no rectangle yet is not built - there is nowhere to put it. One
/// the platform reports as not visible is kept, State and all, but neither
/// painted nor hit, so an ad scrolled away and back does not start over.
class FlutterSlotLayer extends StatefulWidget {
  const FlutterSlotLayer({super.key, this.slots});

  /// The registry to paint; [FlutterSlots.instance] when null.
  final FlutterSlots? slots;

  @override
  State<FlutterSlotLayer> createState() => _FlutterSlotLayerState();
}

class _FlutterSlotLayerState extends State<FlutterSlotLayer> {
  late FlutterSlots _slots;

  @override
  void initState() {
    super.initState();
    _slots = (widget.slots ?? FlutterSlots.instance)..addListener(_changed);
  }

  @override
  void didUpdateWidget(FlutterSlotLayer old) {
    super.didUpdateWidget(old);
    final slots = widget.slots ?? FlutterSlots.instance;
    if (identical(slots, _slots)) return;
    _slots.removeListener(_changed);
    _slots = slots..addListener(_changed);
  }

  @override
  void dispose() {
    _slots.removeListener(_changed);
    super.dispose();
  }

  /// The registry changed: repaint, as soon as that is allowed.
  ///
  /// A builder is registered while the app builds its tree, which can happen
  /// inside a Flutter frame (the first build does), and setState is not
  /// allowed there - so the repaint waits for the frame to end.
  void _changed() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Whatever a slot's rectangle says, nothing is painted outside the view.
      clipBehavior: Clip.hardEdge,
      children: [
        for (final slotId in _slots.slotIds)
          if ((_slots.rectOf(slotId), _slots.builderOf(slotId)) case (
            final FlutterSlotRect rect,
            final FlutterSlotBuilder build,
          ))
            // Keyed by the slot, so its State survives the rectangle moving
            // and the slots around it coming and going.
            Positioned.fromRect(
              key: ValueKey<String>('flutterSlot:$slotId'),
              rect: Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height),
              // A slot repaints on its own clock - an ad animating, a chart
              // updating - and moves on the platform's. The boundary keeps
              // either from repainting the other slots.
              child: RepaintBoundary(
                child: Visibility(
                  visible: rect.visible,
                  maintainState: true,
                  child: Builder(builder: build),
                ),
              ),
            ),
      ],
    );
  }
}
