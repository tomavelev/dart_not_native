/// Flutter implementation of [runNativeApp]: Flutter widgets by default, the
/// platform's own views on request.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../platforms/android_renderer.dart';
import '../../platforms/flutter_renderer.dart';
import '../../platforms/ios_renderer.dart';
import '../../platforms/system_back_channel.dart';
import '../../routing/navigation_app.dart';
import '../app_theme.dart';
import '../native_ui_app.dart';
import '../ui_renderer.dart';

/// Mounts [app] and runs it.
///
/// By default the tree is painted with Flutter widgets, which covers every
/// node type. Pass [nativeViews] to render with the platform's own view system
/// instead - Android Views, iOS UIViews. If that renderer is unavailable, the
/// app falls back to Flutter widgets rather than showing nothing.
///
/// [systemBack] wires the Android back button and the iOS edge swipe; an app
/// built on a [NavigationHost] pops a route, and anything else can register
/// with `SystemBack` directly.
Future<void> runNativeApp(
  NativeUIApp app, {
  bool nativeViews = false,
  bool systemBack = true,
  ThemeData? theme,
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  app.debugShowRenderErrors = debugShowRenderErrors;

  if (app is NavigationHost) {
    // A routed app repaints when the route changes, whatever moved it - an
    // in-app button, the platform gesture, or the browser's history.
    app.nav.router.onRouteChange((_) => app.render());
  }

  if (systemBack) {
    SystemBackChannel.bind();
    if (app is NavigationHost) app.nav.bindSystemBack();
  }

  final native = nativeViews ? await _availableNativeRenderer(appTheme) : null;
  if (native != null) {
    app.mount(native);
    // The platform draws the app; Flutter hosts the engine behind it, and
    // repaints it on hot reload. It still carries the themes, so the Scaffold
    // behind the native views is not a white flash under a dark app.
    runApp(
      MaterialApp(
        title: title,
        theme: theme ?? _materialTheme(appTheme, Brightness.light),
        darkTheme: _materialTheme(appTheme.dark, Brightness.dark),
        themeMode: _themeMode(appTheme),
        home: _NativeViewsHost(app: app),
      ),
    );
    return;
  }

  runApp(
    MaterialApp(
      title: title,
      theme: theme ?? _materialTheme(appTheme, Brightness.light),
      darkTheme: _materialTheme(appTheme.dark, Brightness.dark),
      themeMode: _themeMode(appTheme),
      home: NativeUIAppHost(app: app, theme: appTheme),
    ),
  );
}

/// Flutter's own `ThemeMode`, from the app theme's.
ThemeMode _themeMode(AppTheme appTheme) => switch (appTheme.mode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };

/// A [ThemeData] carrying [palette], so the Material widgets the renderer does
/// not colour itself - a Scaffold's background, a dialog's surface, the default
/// text - match the ones it does.
///
/// Only consulted for the appearance it describes: the caller pairs the light
/// palette with [Brightness.light] and the theme's dark counterpart with
/// [Brightness.dark], and `themeMode` picks between them.
ThemeData _materialTheme(AppTheme palette, Brightness brightness) {
  final surface = _parse(palette.surface);
  final text = _parse(palette.text);
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _parse(palette.primary) ?? const Color(0xff1976d2),
      brightness: brightness,
      primary: _parse(palette.primary),
      onPrimary: _parse(palette.onPrimary),
      secondary: _parse(palette.secondary),
      surface: surface,
      onSurface: text,
      error: _parse(palette.error),
    ),
    scaffoldBackgroundColor: surface,
  );
}

/// `#rrggbb` to a [Color]; null for anything else, so a bad value falls back to
/// the Material default rather than painting something arbitrary.
Color? _parse(String? value) {
  if (value == null || !value.startsWith('#')) return null;
  final digits = value.substring(1);
  if (digits.length != 6 && digits.length != 8) return null;
  final parsed = int.tryParse(digits, radix: 16);
  if (parsed == null) return null;
  return Color(digits.length == 6 ? 0xff000000 | parsed : parsed);
}

/// The platform's own renderer, if this platform has one and it answers.
///
/// A build without the plugin, or a host that never constructed the native
/// renderer, answers no - and the caller paints with Flutter instead of
/// showing an empty screen.
Future<NativeUIRenderer?> _availableNativeRenderer(AppTheme appTheme) async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final renderer = AndroidNativeRenderer(theme: appTheme);
      if (await renderer.isAvailable()) return renderer;
    case TargetPlatform.iOS:
      final renderer = iOSNativeRenderer(theme: appTheme);
      if (await renderer.isAvailable()) return renderer;
    default:
      break;
  }
  debugPrint('dart_not_native: no native renderer here, painting with Flutter');
  return null;
}

/// What Flutter shows while the platform's own views draw the app: nothing,
/// plus the hot reload hook those views would otherwise miss.
class _NativeViewsHost extends StatefulWidget {
  const _NativeViewsHost({required this.app});

  final NativeUIApp app;

  @override
  State<_NativeViewsHost> createState() => _NativeViewsHostState();
}

class _NativeViewsHostState extends State<_NativeViewsHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.app.render();
  }

  /// The device switched between light and dark.
  ///
  /// Nothing in the tree changes for that, so the native renderer would never
  /// hear about it: it is Flutter that gets the callback, even though Flutter
  /// is only hosting the engine here. Re-rendering gives the renderer the
  /// occasion to notice its own trait collection moved and repaint the palette.
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    widget.app.render();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
