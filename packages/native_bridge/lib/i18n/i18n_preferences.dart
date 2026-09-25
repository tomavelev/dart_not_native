/// Internationalization Preferences
///
/// Persist and manage user language preferences.

library;

import 'translations.dart';

/// Simple in-memory preference storage
/// (For production, implement with local storage)
class I18nPreferences {
  static final I18nPreferences _instance = I18nPreferences._internal();

  final Map<String, String> _prefs = {};

  factory I18nPreferences() {
    return _instance;
  }

  I18nPreferences._internal();

  /// Get saved preference by key
  String? get(String key) => _prefs[key];

  /// Set preference
  Future<void> set(String key, String value) async {
    _prefs[key] = value;
    // In production: save to persistent storage
  }

  /// Get preferred locale
  Future<Locale?> getPreferredLocale() async {
    final localeStr = get('preferred_locale');
    if (localeStr == null) return null;
    return Locale.fromString(localeStr);
  }

  /// Save preferred locale
  Future<void> setPreferredLocale(Locale locale) async {
    await set('preferred_locale', locale.toString());
  }

  /// Get system locale (device language)
  Future<Locale> getSystemLocale() async {
    // In a real app, get device locale from platform
    // For now, default to English
    return const Locale('en');
  }

  /// Get best available locale based on preferences
  Future<Locale> getBestLocale(List<Locale> availableLocales) async {
    // 1. Try user's preferred locale
    final preferred = await getPreferredLocale();
    if (preferred != null && availableLocales.contains(preferred)) {
      return preferred;
    }

    // 2. Try system locale
    final systemLocale = await getSystemLocale();
    if (availableLocales.contains(systemLocale)) {
      return systemLocale;
    }

    // 3. Try locale with same language
    for (final available in availableLocales) {
      if (available.language == systemLocale.language) {
        return available;
      }
    }

    // 4. Default to first available or English
    return availableLocales.isNotEmpty
        ? availableLocales.first
        : const Locale('en');
  }

  /// Clear all preferences
  Future<void> clear() async {
    _prefs.clear();
  }
}

/// Get singleton instance
I18nPreferences getI18nPreferences() => I18nPreferences();

/// Save the current locale preference
Future<void> saveLocalePreference(Locale locale) async {
  await getI18nPreferences().setPreferredLocale(locale);
}

/// Load saved locale preference
Future<Locale?> loadLocalePreference() async {
  return getI18nPreferences().getPreferredLocale();
}

/// Get best available locale from list
Future<Locale> getBestAvailableLocale(List<Locale> availableLocales) async {
  return getI18nPreferences().getBestLocale(availableLocales);
}
