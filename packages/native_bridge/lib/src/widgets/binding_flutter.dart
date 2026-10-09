/// What the widget layer asks of the platform, on a Flutter host.
///
/// An app migrated from Flutter calls plugins - shared_preferences, a
/// database - before `runApp`, and a plugin talks over a platform channel
/// that only exists once Flutter's own binding does. So here
/// `WidgetsFlutterBinding.ensureInitialized()` has to be the real one.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' as flutter;

/// Starts Flutter's binding, so platform channels work before `runApp`.
void ensureInitialized() => flutter.WidgetsFlutterBinding.ensureInitialized();

/// The language the device is set to, as a `languageCode[_countryCode]` tag.
String platformLocale() {
  final locale = PlatformDispatcher.instance.locale;
  final country = locale.countryCode;
  return country == null || country.isEmpty
      ? locale.languageCode
      : '${locale.languageCode}_$country';
}
