/// Translations Management
///
/// Core internationalization system for multi-language support.

library;

import 'dart:convert';

import '../src/listenable.dart';

/// Language locale representation
class Locale {
  final String language; // 'en', 'es', 'fr', etc.
  final String? region; // 'US', 'GB', 'MX', etc. (optional)
  final String? script; // 'Hans', 'Hant', etc. for scripts (optional)

  const Locale(this.language, {this.region, this.script});

  /// Create from string like 'en_US' or 'zh_Hans_CN'
  factory Locale.fromString(String locale) {
    final parts = locale.split('_');
    if (parts.isEmpty) throw ArgumentError('Invalid locale: $locale');

    // language[_script]_region: a three-part tag carries the script in the
    // middle and the region last (zh_Hans_CN); a two-part tag is just a region
    // (en_US).
    return Locale(
      parts[0],
      script: parts.length > 2 ? parts[1] : null,
      region: parts.length > 2
          ? parts[2]
          : (parts.length > 1 ? parts[1] : null),
    );
  }

  /// Convert to string: 'en' or 'en_US' or 'zh_Hans_CN'
  @override
  String toString() {
    if (script != null && region != null) {
      return '${language}_$script\_$region';
    } else if (region != null) {
      return '${language}_$region';
    }
    return language;
  }

  /// Check if this locale matches another (e.g., 'en_US' matches 'en')
  bool matches(Locale other) {
    if (language != other.language) return false;
    if (region != null && other.region != null && region != other.region) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Locale &&
          runtimeType == other.runtimeType &&
          language == other.language &&
          region == other.region &&
          script == other.script;

  @override
  int get hashCode =>
      language.hashCode ^ (region?.hashCode ?? 0) ^ (script?.hashCode ?? 0);
}

/// Translation key-value pairs for a single locale
typedef TranslationMap = Map<String, dynamic>;

/// Translation function with parameters
typedef TranslationFunction = String Function(Map<String, dynamic> params);

/// Pluralization rule function
typedef PluralRule = int Function(int count);

/// Date/number formatter
typedef DateFormatter = String Function(DateTime date);
typedef NumberFormatter = String Function(num number);

/// Translation entry - can be string, map, or function
typedef TranslationEntry = dynamic; // String | Map | Function

/// Internationalization (i18n) Manager
///
/// A [Listenable]: a locale change is state like any other, so a screen can
/// follow it with `ListenableBuilder`, an app with `watch()`, and the [Tr]
/// widget does it for every string it draws.
class I18n implements Listenable {
  final Map<String, TranslationMap> _translations = {};
  late Locale _currentLocale;
  late Locale _fallbackLocale;
  final List<VoidCallback> _listeners = [];

  // Formatters for numbers and dates
  DateFormatter? _dateFormatter;
  NumberFormatter? _numberFormatter;

  I18n({required Locale defaultLocale, Locale? fallbackLocale}) {
    _currentLocale = defaultLocale;
    _fallbackLocale = fallbackLocale ?? const Locale('en');
  }

  /// Load translations for a locale from JSON
  void loadTranslations(Locale locale, TranslationMap translations) {
    _translations[locale.toString()] = translations;
  }

  /// Load translations from JSON string
  void loadTranslationsFromJson(Locale locale, String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    loadTranslations(locale, data);
  }

  /// Get current locale
  Locale get currentLocale => _currentLocale;

  /// Get fallback locale
  Locale get fallbackLocale => _fallbackLocale;

  /// Set current locale and notify listeners
  Future<void> setLocale(Locale locale) async {
    if (_currentLocale == locale) return;

    _currentLocale = locale;
    _notifyListeners();
  }

  /// Set locale from string
  Future<void> setLocaleFromString(String locale) {
    return setLocale(Locale.fromString(locale));
  }

  /// Get available locales
  List<Locale> get availableLocales =>
      _translations.keys.map(Locale.fromString).toList();

  /// Translate a key with optional parameters
  String t(
    String key, {
    Map<String, dynamic>? params,
    String? defaultValue,
    int? count,
  }) {
    // Try current locale first
    final translation = _getTranslation(key, _currentLocale);

    if (translation != null) {
      return _formatTranslation(translation, params, count);
    }

    // Try fallback locale
    if (_currentLocale != _fallbackLocale) {
      final fallback = _getTranslation(key, _fallbackLocale);
      if (fallback != null) {
        return _formatTranslation(fallback, params, count);
      }
    }

    // Return default or key itself
    return defaultValue ?? key;
  }

  /// Translate with pluralization
  String plural(
    String key,
    int count, {
    Map<String, dynamic>? params,
    String? defaultValue,
  }) {
    params ??= {};
    params['count'] = count;

    return t(key, params: params, defaultValue: defaultValue, count: count);
  }

  /// Format date using current locale
  String formatDate(DateTime date) {
    if (_dateFormatter != null) {
      return _dateFormatter!(date);
    }

    // Default formatting
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Format number using current locale
  String formatNumber(num number) {
    if (_numberFormatter != null) {
      return _numberFormatter!(number);
    }

    return number.toString();
  }

  /// Set custom date formatter
  void setDateFormatter(DateFormatter formatter) {
    _dateFormatter = formatter;
  }

  /// Set custom number formatter
  void setNumberFormatter(NumberFormatter formatter) {
    _numberFormatter = formatter;
  }

  /// Listen to locale changes
  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Whether anyone is following the locale.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Notify all listeners of locale change
  ///
  /// Over a copy, so a listener that stops listening while being called - a
  /// screen leaving the tree - does not disturb this round.
  void _notifyListeners() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  /// Get translation from map, supporting nested keys (a.b.c)
  dynamic _getTranslation(String key, Locale locale) {
    final localeKey = locale.toString();
    final translations = _translations[localeKey];

    if (translations == null) {
      // Try without region
      if (locale.region != null) {
        return _getTranslation(key, Locale(locale.language));
      }
      return null;
    }

    final parts = key.split('.');
    dynamic current = translations;

    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }

      if (current == null) return null;
    }

    return current;
  }

  /// Format translation with parameters and pluralization
  String _formatTranslation(
    dynamic translation,
    Map<String, dynamic>? params,
    int? count,
  ) {
    if (translation is String) {
      return _interpolateString(translation, params);
    }

    if (translation is Map) {
      // Handle pluralization
      if (count != null) {
        final pluralKey = _getPluralKey(count);
        final pluralValue = translation[pluralKey];

        if (pluralValue != null) {
          return _interpolateString(pluralValue.toString(), params);
        }
      }

      // Try 'other' key as default
      if (translation.containsKey('other')) {
        return _interpolateString(translation['other'].toString(), params);
      }
    }

    if (translation is Function) {
      return translation(params ?? {});
    }

    return translation.toString();
  }

  /// Interpolate variables in string: "Hello {name}" → "Hello John"
  String _interpolateString(String template, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) {
      return template;
    }

    String result = template;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', value.toString());
    });

    return result;
  }

  /// Get plural key based on count ('zero', 'one', 'two', 'few', 'many', 'other')
  String _getPluralKey(int count) {
    if (count == 0) return 'zero';
    if (count == 1) return 'one';
    if (count == 2) return 'two';
    if (count >= 3 && count <= 10) return 'few';
    if (count >= 11) return 'many';
    return 'other';
  }
}

/// Global i18n instance
late I18n _globalI18n;
bool _globalI18nSet = false;

/// Initialize global i18n instance
void initializeI18n({required Locale defaultLocale, Locale? fallbackLocale}) {
  _globalI18n = I18n(
    defaultLocale: defaultLocale,
    fallbackLocale: fallbackLocale,
  );
  _globalI18nSet = true;
}

/// Get global i18n instance
I18n getI18n() {
  if (!isI18nInitialized) {
    throw StateError(
      'No translations are loaded. Call initializeI18n(defaultLocale: ...) '
      'and loadTranslations(...) before translating anything.',
    );
  }
  return _globalI18n;
}

/// Whether [initializeI18n] has been called.
///
/// The global is late, and reading it before it is set throws a message about
/// a private field rather than about translations - so anything that resolves
/// a key checks this first.
bool get isI18nInitialized => _globalI18nSet;

/// Shorthand for global translate
String t(
  String key, {
  Map<String, dynamic>? params,
  String? defaultValue,
  int? count,
}) {
  return _globalI18n.t(
    key,
    params: params,
    defaultValue: defaultValue,
    count: count,
  );
}

/// Shorthand for plural
String tPlural(
  String key,
  int count, {
  Map<String, dynamic>? params,
  String? defaultValue,
}) {
  return _globalI18n.plural(
    key,
    count,
    params: params,
    defaultValue: defaultValue,
  );
}
