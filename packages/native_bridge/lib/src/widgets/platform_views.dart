part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// The framework's own widgets: things Flutter has no word for, or spells
// through a plugin - a row with swipe actions, a map, a camera, a web page -
// and the design system's badge and alert.
// ---------------------------------------------------------------------------

/// An action revealed when a [SwipeActions] row is swiped aside.
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.onPressed,
    this.color = '#d32f2f',
  });

  /// The button text shown when the row is swiped open.
  final String label;

  /// Fired when the button is tapped, or when the row is swiped all the way
  /// (which fires the first action).
  final void Function() onPressed;

  /// The action button's colour, `#rrggbb`; defaults to a destructive red.
  final String color;
}

/// A row that reveals trailing [actions] when swiped towards its start, iOS
/// Mail style: a partial swipe slides [child] over to show the action buttons
/// to tap, and a full swipe fires the first action. "Towards its start" is
/// to the left where the screen reads left to right and to the right where it
/// reads right to left - the actions change sides with the reading direction. A renderer without swipe shows [child]
/// alone, so the row still works (through whatever other affordance it has).
class SwipeActions extends Widget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.leadingActions = const [],
  });
  final Widget child;

  /// Revealed at the row's trailing edge, by dragging it towards its start
  /// (to the left, in English) - where iOS Mail puts Delete.
  final List<SwipeAction> actions;

  /// Revealed at the row's leading edge, by dragging it towards its end (to
  /// the right, in English) - where iOS Mail puts Mark as read.
  final List<SwipeAction> leadingActions;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.swipeActions(
    child: owner.inSlot('child', () => child._render(owner)),
    actions: [
      for (final a in actions)
        (label: a.label, color: a.color, onPressed: a.onPressed),
    ],
    leadingActions: [
      for (final a in leadingActions)
        (label: a.label, color: a.color, onPressed: a.onPressed),
    ],
    id: _idOf(key),
  );
}

/// A live camera preview.
///
/// Framework-specific, like [MapView], and drawn where a camera costs nothing
/// but a permission: **iOS** uses `AVCapture` and **web** `getUserMedia`.
/// **Android and the Flutter host draw a placeholder** - CameraX and the
/// `camera` plugin are dependencies the app chooses.
///
/// The app declares the permission itself: `NSCameraUsageDescription` in an
/// iOS app's Info.plist (without it the system stops the app on the first
/// frame), and a browser only offers a camera on a secure origin.
///
/// [active] false stops the camera without removing the widget, which is what
/// a screen behind a dialog should do - a preview nobody is looking at still
/// costs battery, heat and the indicator light.
///
/// Frames never reach Dart. [onStatus] only says whether it started: `ready`,
/// `denied`, `unavailable`, `stopped` or `error`.
class CameraPreview extends Widget {
  const CameraPreview({
    super.key,
    this.height = 300,
    this.facing = CameraFacing.back,
    this.active = true,
    this.onStatus,
  });

  final double height;
  final CameraFacing facing;
  final bool active;
  final void Function(String status, String? message)? onStatus;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.cameraPreview(
    height: height,
    facing: facing.name,
    active: active,
    onStatus: onStatus,
    id: _idOf(key),
  );
}

/// Which camera a [CameraPreview] shows.
enum CameraFacing {
  /// The one pointing away from the user.
  back,

  /// The one pointing at them.
  front,
}

/// A pin on a [MapView].
class MapMarker {
  const MapMarker({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;
}

/// A map centred on [latitude]/[longitude].
///
/// Framework-specific, like [Tabs]: Flutter has no map of its own, and what
/// draws one differs per target. **iOS** uses MapKit, which is free and needs
/// no key. **Web** lays out raster tiles - OpenStreetMap's by default, free
/// and attributed on screen; point [tileUrl] at your own source for anything
/// but a demo. **Android and the Flutter host draw a labelled placeholder**,
/// because the Maps SDK needs a dependency *and* an API key, which is the
/// app's decision to make.
///
/// [onCameraIdle] reports where the map came to rest after a pan, never while
/// it moves: a position per frame would rebuild the whole tree per frame.
class MapView extends Widget {
  const MapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 13,
    this.height = 300,
    this.markers = const [],
    this.interactive = true,
    this.tileUrl,
    this.onCameraIdle,
  });

  final double latitude;
  final double longitude;

  /// The slippy-map scale: 0 is the world, 15 a neighbourhood, 18 a building.
  final double zoom;
  final double height;
  final List<MapMarker> markers;
  final bool interactive;

  /// Web only: the tile template, `{z}/{x}/{y}`.
  final String? tileUrl;
  final void Function(double latitude, double longitude, double zoom)?
  onCameraIdle;

  @override
  WidgetNode _render(_Owner owner) => UIBuilder.map(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    height: height,
    interactive: interactive,
    tileUrl: tileUrl,
    onCameraIdle: onCameraIdle,
    markers: [
      for (final marker in markers)
        (
          latitude: marker.latitude,
          longitude: marker.longitude,
          label: marker.label,
        ),
    ],
    id: _idOf(key),
  );
}

/// A web page embedded in the screen, drawn with the platform's own browser
/// view.
///
/// Give it a [height]: a web view has no size of its own, and a scrolling body
/// would otherwise collapse it to nothing. [javaScriptEnabled] is off by
/// default - a page that is only being read does not need to run code.
///
/// The Flutter-hosted target cannot draw one without `webview_flutter`, which
/// the framework does not depend on; it shows a placeholder saying so.
class WebView extends Widget {
  const WebView({
    super.key,
    required this.url,
    this.height = 300,
    this.javaScriptEnabled = false,
  });
  final String url;
  final double height;
  final bool javaScriptEnabled;
  @override
  WidgetNode _render(_Owner owner) => UIBuilder.webView(
    url: url,
    height: height,
    javaScriptEnabled: javaScriptEnabled,
    id: _idOf(key),
  );
}

/// A small label chip. [color] is a `#RRGGBB` string; the named constructors are
/// the semantic colors.
class Badge extends Widget {
  const Badge({
    super.key,
    required this.label,
    this.color,
    this.outlined = false,
  });
  const Badge.dot({super.key, this.color}) : label = null, outlined = false;
  final String? label;
  final String? color;
  final bool outlined;
  @override
  WidgetNode _render(_Owner owner) {
    final text = label;
    // A null colour follows the app theme's primary (filled by the renderer).
    if (text == null) return DSBadge.dot(color: color);
    if (outlined) return DSBadge.outlined(label: text, color: color);
    return DSBadge.solid(label: text, color: color);
  }
}

/// A colored alert banner. Use the named constructors for the semantic types.
class Alert extends Widget {
  const Alert.success({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'success';
  const Alert.error({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'error';
  const Alert.warning({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'warning';
  const Alert.info({
    super.key,
    required this.message,
    this.title,
    this.dismissible = true,
  }) : _type = 'info';
  final String _type;
  final String message;
  final String? title;
  final bool dismissible;
  @override
  WidgetNode _render(_Owner owner) {
    switch (_type) {
      case 'error':
        return DSAlert.error(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      case 'warning':
        return DSAlert.warning(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      case 'info':
        return DSAlert.info(
          message: message,
          title: title,
          dismissible: dismissible,
        );
      default:
        return DSAlert.success(
          message: message,
          title: title,
          dismissible: dismissible,
        );
    }
  }
}


/// A real Flutter widget inside a screen the platform draws - an ad banner, a
/// chart package: the things that only exist as Flutter widgets.
///
/// ```dart
/// import 'package:flutter/widgets.dart' as flutter;
///
/// FlutterSlot(
///   slotId: 'banner',
///   height: 50,
///   builder: (flutter.BuildContext context) => const AdBanner(),
///   fallback: const SizedBox(height: 50),
/// )
/// ```
///
/// [builder] is a Flutter `Widget Function(BuildContext)`. It is typed as an
/// [Object] because this library is pure Dart and cannot name Flutter's
/// types; the host that paints it checks the type and draws [fallback] if it
/// is anything else.
///
/// Who draws what, and the two limits of a hole in a native screen - the
/// rectangle trails a fast scroll by a frame, and a drag that starts on the
/// slot does not scroll the list around it - are in
/// `package:dart_not_native/flutter_slot.dart`. The size comes from here, not
/// from the widget: give [height], and [width] unless it should fill the width
/// it is offered.
///
/// [slotId] names the slot across builds, so give two slots on screen at once
/// two ids.
class FlutterSlot extends Widget {
  const FlutterSlot({
    super.key,
    required this.slotId,
    required this.height,
    this.width,
    required this.builder,
    this.fallback,
  });

  final String slotId;
  final double height;
  final double? width;
  final Object builder;
  final Widget? fallback;

  @override
  WidgetNode _render(_Owner owner) {
    // A page that is only being kept alive - under a pushed route, in a tab
    // that is not showing - has no hole on screen. Registering from it would
    // put the slot back every build only for the renderer to drop it again.
    if (owner._hidden == 0) FlutterSlots.instance.register(slotId, builder);
    return UIBuilder.flutterSlot(
      slotId: slotId,
      height: height,
      width: width,
      fallback: fallback == null
          ? null
          : owner.inSlot('fallback', () => fallback!._render(owner)),
    );
  }
}
