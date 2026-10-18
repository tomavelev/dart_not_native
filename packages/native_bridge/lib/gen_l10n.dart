/// gen-l10n's generated strings, looked up for the locale an app shows.
///
/// gen-l10n stays the source of truth - ARB files, `flutter gen-l10n`, the
/// generated `AppLocalizations` - and what this replaces is the lookup the
/// generated file writes against Flutter's `Localizations`. The bridge an app
/// keeps beside the generated file is then two declarations:
///
/// ```dart
/// // lib/l10n/l10n.dart - hand-written; gen-l10n leaves it alone
/// import 'dart:ui' as ui;
///
/// import 'package:dart_not_native/gen_l10n.dart';
/// import 'package:dart_not_native/widgets.dart';
///
/// import 'app_localizations.dart';
///
/// final appL10n = GeneratedL10n(
///   lookupAppLocalizations,
///   supportedLocales: AppLocalizations.supportedLocales,
///   fallback: const ui.Locale('en'),
/// );
///
/// extension AppL10n on BuildContext {
///   AppLocalizations get l10n => appL10n.of(this);
/// }
/// ```
///
/// and screens say `context.l10n.title`. The generated code imports Flutter,
/// and so does this library: it is for the Android and iOS targets. A web
/// target keeps its strings in `I18n` (see `I18N_GUIDE.md`).
library;

import 'dart:ui' as ui;

import 'widgets.dart' as w;

/// The strings [lookup] gives for each locale an app shows, each looked up
/// once.
///
/// A locale is matched against [supportedLocales] by language, script and
/// country, then language and script, then language alone; a language the
/// app does not ship gets [fallback] - for which gen-l10n's
/// `lookupAppLocalizations` would throw. Flutter falls back to the first
/// supported locale, and gen-l10n lists them alphabetically, so say which:
/// left out, it is English where the app has it, else the first.
class GeneratedL10n<T> {
  GeneratedL10n(
    this.lookup, {
    required this.supportedLocales,
    ui.Locale? fallback,
  }) : fallback =
           fallback ??
           supportedLocales.firstWhere(
             (locale) => locale.languageCode == 'en',
             orElse: () => supportedLocales.first,
           );

  /// gen-l10n's `lookupAppLocalizations`.
  final T Function(ui.Locale locale) lookup;
  final List<ui.Locale> supportedLocales;
  final ui.Locale fallback;

  final Map<String, T> _cache = {};

  /// The strings for the locale [context] is shown in.
  T of(w.BuildContext context) => forLocale(w.Localizations.localeOf(context));

  /// The strings for [locale], or for the nearest supported locale.
  T forLocale(w.Locale locale) {
    final key = [
      locale.languageCode,
      locale.scriptCode ?? '',
      locale.countryCode ?? '',
    ].join('-');
    return _cache[key] ??= lookup(_supported(locale));
  }

  ui.Locale _supported(w.Locale locale) {
    bool same(ui.Locale a, {bool script = true, bool country = true}) =>
        a.languageCode == locale.languageCode &&
        (!script || a.scriptCode == locale.scriptCode) &&
        (!country || a.countryCode == locale.countryCode);
    for (final match in [
      (ui.Locale a) => same(a),
      (ui.Locale a) => same(a, country: false) && a.countryCode == null,
      (ui.Locale a) =>
          same(a, script: false, country: false) &&
          a.scriptCode == null &&
          a.countryCode == null,
      (ui.Locale a) => same(a, script: false, country: false),
    ]) {
      for (final supported in supportedLocales) {
        if (match(supported)) return supported;
      }
    }
    return fallback;
  }
}
