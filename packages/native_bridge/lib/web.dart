/// Web entry point for dart_not_native: renders apps to DOM + Material CSS.
///
/// Compile a web entry with plain dart2js (no Flutter engine, no canvas):
///
/// ```dart
/// import 'package:dart_not_native/web.dart';
///
/// void main() => runWebApp(MyApp());                       // MDL (default)
/// void main() => runWebApp(MyApp(), kit: MaterializeKit()); // Materialize
/// ```
///
/// Serve the output next to the files in `web_shell/` (index.html, dnn.css,
/// kit stylesheets and vendored CSS frameworks/fonts).
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'src/app_theme.dart';
import 'src/native_ui_app.dart';
import 'web_ui/kits/materialize_kit.dart';
import 'web_ui/kits/mdl_kit.dart';
import 'web_ui/style_kit.dart';
import 'web_ui/web_renderer.dart';

export 'core.dart';
export 'web_ui/kits/materialize_kit.dart';
export 'web_ui/kits/mdl_kit.dart';
export 'web_ui/browser_history.dart';
export 'web_ui/local_storage.dart';
export 'web_ui/secure_local_storage.dart';
export 'web_ui/style_kit.dart';
export 'web_ui/web_renderer.dart';

/// Kits selectable with `?kit=<name>`. Register custom kits here.
final Map<String, WebStyleKit> webStyleKits = {
  for (final kit in const <WebStyleKit>[MdlKit(), MaterializeKit(), PlainKit()])
    kit.name: kit,
};

/// Mount [app] into the element with id [rootId] (falls back to `<body>`).
///
/// The style kit is, in order: the `?kit=<name>` URL parameter (any kit in
/// [webStyleKits]), then [kit], then [MdlKit]. Its stylesheets and the fonts
/// are loaded before the first render so the first paint is final.
/// `?animations=off` disables spinner/pulse animations (for screenshot tests).
Future<void> runWebApp(
  NativeUIApp app, {
  WebStyleKit? kit,
  String rootId = 'app',
  AppTheme theme = AppTheme.fallback,
}) async {
  final query = Uri.base.queryParameters;
  final chosen = webStyleKits[query['kit']] ?? kit ?? const MdlKit();
  web.document.documentElement!.classList.add('dnn-kit-${chosen.name}');
  await _loadStylesheets(chosen.stylesheets);
  await _loadFonts();
  final root = web.document.getElementById(rootId) ?? web.document.body!;
  app.mount(
    WebUIRenderer(
      root: root,
      kit: chosen,
      animations: query['animations'] != 'off',
      theme: theme,
    ),
  );
}

Future<void> _loadStylesheets(List<String> hrefs) async {
  final head = web.document.head!;
  final loads = <Future<void>>[];
  for (final href in hrefs) {
    final link = web.document.createElement('link') as web.HTMLLinkElement
      ..rel = 'stylesheet'
      ..href = href;
    final done = Completer<void>();
    void finish(web.Event _) {
      if (!done.isCompleted) done.complete();
    }

    link.addEventListener('load', finish.toJS);
    link.addEventListener(
      'error',
      ((web.Event e) {
        web.console.warn('dart_not_native: failed to load $href'.toJS);
        finish(e);
      }).toJS,
    );
    head.appendChild(link);
    loads.add(done.future);
  }
  await Future.wait(loads);
}

Future<void> _loadFonts() async {
  const faces = [
    '400 16px Roboto',
    '500 16px Roboto',
    '700 16px Roboto',
    '24px "Material Icons"',
  ];
  try {
    for (final face in faces) {
      await web.document.fonts.load(face).toDart;
    }
  } catch (_) {
    // Missing fonts only affect looks; render anyway.
  }
}
