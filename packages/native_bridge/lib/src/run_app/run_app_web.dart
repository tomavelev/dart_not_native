/// Web implementation of [runNativeApp]: DOM plus a Material CSS kit.
library;

import '../../web.dart';

// Deliberately not re-exported: the analyzer resolves this conditional export
// to the non-web branch, so a web entry relying on it would show errors in an
// editor even though dart2js compiles it. Web-specific classes come from
// `package:dart_not_native/web.dart`, imported directly.

/// Mounts [app] on the web DOM renderer.
///
/// [nativeViews] and [title] are accepted so one call site compiles for every
/// target; on web the DOM *is* the native UI, and the tab title comes from the
/// page shell, so neither changes anything here. [theme] is the Flutter host's
/// `ThemeData` and means nothing to the DOM, which is styled by [kit] and
/// [appTheme]; it is accepted for the same reason.
///
/// Every parameter `runApp` passes must be here, or a web entry point does not
/// compile - which is how `debugShowRenderErrors` and `theme` broke the web
/// examples without any suite noticing.
Future<void> runNativeApp(
  NativeUIApp app, {
  bool nativeViews = false,
  bool systemBack = true,
  WebStyleKit? kit,
  String rootId = 'app',
  String title = '',
  Object? theme,
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
}) async {
  app.debugShowRenderErrors = debugShowRenderErrors;
  final routed = app;
  if (routed is NavigationHost) {
    // A routed app repaints when the route changes, whatever moved it - an
    // in-app button, or the browser's Back button.
    routed.nav.router.onRouteChange((_) => routed.render());
  }

  // An app that asked to be left out of the back gesture is left out of the
  // browser's history too: a page embedded in someone else's site has no
  // business writing entries into it. Before the app is mounted, since a
  // `MaterialApp(routes:)` reaches for the history as it starts.
  if (!systemBack) HistoryAdapter.platform ??= const NoHistoryAdapter();

  await runWebApp(app, kit: kit, rootId: rootId, theme: appTheme);

  if (systemBack && routed is NavigationHost) {
    routed.nav.bindSystemBack(adapter: BrowserHistoryAdapter());
    bindBrowserBack();
  }
}
