/// What the widget layer asks of the platform, where there is no platform to
/// ask: a plain Dart program, a test on the VM without `dart:ui`.
library;

/// Nothing to initialise: there is no engine behind a pure Dart program.
void ensureInitialized() {}

/// The language the device is set to, as a `languageCode[_countryCode]` tag.
/// With no device to ask, English.
String platformLocale() => 'en';
