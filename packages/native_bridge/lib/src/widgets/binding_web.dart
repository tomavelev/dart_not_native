/// What the widget layer asks of the platform, in a browser without Flutter.
library;

import 'package:web/web.dart' as web;

import '../../routing/history_sync.dart';
import '../../web_ui/browser_history.dart';

/// The browser's history, with its Back button wired to the app: asking for
/// it is what starts listening, and asking again does not start twice.
HistoryAdapter platformHistory() {
  bindBrowserBack();
  return BrowserHistoryAdapter();
}

/// Nothing to initialise: the DOM is there when the script runs.
void ensureInitialized() {}

/// The language the browser is set to, as a `languageCode[_countryCode]` tag.
/// `navigator.language` is a BCP 47 tag (`en-US`), so the dash becomes the
/// underscore the rest of the framework writes.
String platformLocale() {
  final language = web.window.navigator.language;
  return language.isEmpty ? 'en' : language.replaceAll('-', '_');
}
