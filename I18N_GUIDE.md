# 🌍 Internationalization (i18n) Guide

Complete multi-language support system with 6 pre-built language packs, pluralization, parameter interpolation, and locale persistence.

## ✨ Features

✅ **6 Pre-Built Languages** - English, Spanish, French, German, Japanese, Chinese
✅ **Pluralization** - Automatic singular/plural/zero form selection
✅ **Parameter Interpolation** - Insert variables into translated strings
✅ **Nested Keys** - Hierarchical translation organization (app.menu.file)
✅ **Fallback Locale** - Graceful degradation when translation missing
✅ **Locale Persistence** - Save/restore user language preference
✅ **Custom Formatters** - Date and number formatting by locale
✅ **Change Listeners** - React to language changes
✅ **Cross-Platform** - Works on web, Android, iOS

## 🚀 Quick Start

### 1. Initialize I18n

```dart
import 'package:dart_not_native/i18n/translation_bundles.dart';
import 'package:dart_not_native/i18n/translations.dart';
import 'package:dart_not_native/widgets.dart';

void main() {
  // Initialize with English default
  initializeI18n(
    defaultLocale: const Locale('en'),
    fallbackLocale: const Locale('en'),
  );

  // Load translation bundles
  final i18n = getI18n();
  i18n.loadTranslations(const Locale('en'), enUS);
  i18n.loadTranslations(const Locale('es'), esES);
  i18n.loadTranslations(const Locale('fr'), frFR);

  runApp(MyApp());
}
```

### 2. Use Translations

```dart
// Simple translation
final text = t('common.ok');  // 'OK' or 'Aceptar' or 'OK'

// With parameters
final greeting = t('messages.welcome', params: {'name': 'John'});

// Pluralization
final items = tPlural('plurals.items', 5);  // '5 items'

// Fallback value
final unknown = t('nonexistent.key', defaultValue: 'N/A');
```

### 2b. Use Translations in the UI

`t(...)` returns a string, which means the screen that drew it has to be
rebuilt when the language changes - and something has to notice. `Tr` is that
string as a widget: it looks the key up where the text is drawn, and follows the
locale for you.

```dart
// Instead of Text(t('navigation.settings')) plus a listener:
AppBar(title: const Tr('navigation.settings')),

const Tr('plurals.items', count: 3),                  // '3 items'
Tr('messages.welcome', params: {'name': user.name}),
const Tr('nonexistent.key', defaultValue: 'N/A'),
```

A `Tr` works wherever a `Text` does, titles and button labels included. While
one is on screen the app follows the locale; when the screen goes, it stops. A
screen whose locale-dependent strings are *not* keys (a formatted date, say) can
follow the table directly:

```dart
ListenableBuilder(
  listenable: getI18n(),
  builder: (context, _) => Text(getI18n().formatDate(DateTime.now())),
)
```

`I18n` is a `Listenable`, so `NativeUIApp.watch(getI18n())` does the same for a
hand-written app.

### 3. Switch Language

```dart
final i18n = getI18n();

// Switch to Spanish
await i18n.setLocale(const Locale('es'));

// Every Tr on screen redraws itself in Spanish
print(t('common.ok'));  // 'Aceptar'

// Save preference
await saveLocalePreference(const Locale('es'));
```

## 📚 Core Concepts

### Locales

A locale identifies a language (and optionally region and script):

```dart
// Language only
const Locale('en');        // English
const Locale('es');        // Spanish

// Language + Region
const Locale('en', 'US');  // US English
const Locale('en', 'GB');  // British English
const Locale('zh', 'CN');  // Simplified Chinese
const Locale('zh', 'TW');  // Traditional Chinese

// Language + Script + Region - a script can only be named part by part
const Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hans',
  countryCode: 'CN',
);

// From string
Locale.fromString('en_US');       // Locale('en', 'US')
Locale.fromString('zh_Hans_CN');  // language zh, script Hans, region CN
```

`Locale` is Flutter's shape - positional `Locale('en', 'US')`, with
`languageCode`, `countryCode`, `scriptCode` and `toLanguageTag()`. The older
`language`, `region` and `script` getters are still there; the named `region:`
and `script:` constructor parameters are gone.

### The locale a `MaterialApp` shows, and right-to-left

The widget layer's `MaterialApp` takes `locale` and `supportedLocales` as
Flutter's does, and `Localizations.localeOf(context)` answers with the app's
`locale`; failing that the first of its `supportedLocales` in the device's
language; failing that the device's own.

That locale also decides the reading direction. For Arabic, Persian, Hebrew,
Pashto, Sindhi and Urdu (Flutter's six) and Uyghur, Yiddish and Dhivehi, the
whole screen is laid out right to left: rows run from the right, an app bar's
leading and actions swap ends, the floating button moves to the bottom left,
and `EdgeInsetsDirectional`, `AlignmentDirectional` and `TextAlign.start`
resolve against it. What names a side stays on it - `EdgeInsets.only(left:)`
is still the left. Override it from `MaterialApp.builder` with a
`Directionality`, as in Flutter.

One limit: only the *screen's* direction reaches the renderers. A
`Directionality` deep in a screen turns the values and rows below it, not the
platform's own controls there. And one platform note: the Android and iOS
halves of right-to-left are built and pinned by source-level tests; the
changelog records no device run for Android, and the iOS Swift has not been
compiled.

Nothing ties the two systems together automatically: the `I18n` table has its
own current locale (`getI18n().setLocale`), and `MaterialApp(locale:)` is
what turns the screen. An app switching language sets both.

### An app that already uses gen-l10n

An existing Flutter app keeps its ARB files and `flutter gen-l10n`, and does
not need the `I18n` table at all. The generated `AppLocalizations` classes are
plain objects; a few lines read `Localizations.localeOf(context)` and look
them up with the generated `lookupAppLocalizations`. `MaterialApp`'s
`localizationsDelegates` is accepted and ignored. The bridge, and its two
catches (choose the fallback locale on purpose; the generated code imports
Flutter, so it is mobile-only), are in `INTEGRATION.md` §8.4.

### Translation Structure

Translations are organized hierarchically:

```dart
{
  'common': {
    'ok': 'OK',
    'cancel': 'Cancel',
  },
  'forms': {
    'email': 'Email',
    'password': 'Password',
  },
  'errors': {
    'required': 'This field is required',
    'invalidEmail': 'Invalid email',
  },
}
```

Access with dot notation:
```dart
t('common.ok');           // 'OK'
t('forms.email');         // 'Email'
t('errors.required');     // 'This field is required'
```

### Pluralization Rules

Automatic form selection based on count:

```dart
'plurals': {
  'items': {
    'zero': 'No items',
    'one': '1 item',
    'other': '{count} items',
  }
}

tPlural('plurals.items', 0);   // 'No items'
tPlural('plurals.items', 1);   // '1 item'
tPlural('plurals.items', 5);   // '5 items'
```

Supported plural forms: `zero`, `one`, `two`, `few`, `many`, `other`

### Parameter Interpolation

Insert variables into translations:

```dart
'messages': {
  'welcome': 'Welcome, {name}!',
  'greeting': 'Good {time}, {name}',
}

t('messages.welcome', params: {'name': 'John'});
// → 'Welcome, John!'

t('messages.greeting', params: {
  'name': 'Alice',
  'time': 'morning',
});
// → 'Good morning, Alice'
```

## 🔧 API Reference

### Initialization

```dart
initializeI18n({
  required Locale defaultLocale,
  Locale? fallbackLocale,
});
```

Initialize the global i18n instance.

### Getting Instance

```dart
I18n getI18n()                    // Get global i18n
I18nPreferences getI18nPreferences() // Get preferences manager
```

### Loading Translations

```dart
i18n.loadTranslations(
  const Locale('en'),
  enUS,  // Translation map
);

i18n.loadTranslationsFromJson(
  const Locale('en'),
  jsonString,
);
```

### Translation Methods

```dart
// Simple translation
String t(
  String key,
  {
    Map<String, dynamic>? params,
    String? defaultValue,
  },
)

// Pluralized translation
String tPlural(
  String key,
  int count,
  {
    Map<String, dynamic>? params,
    String? defaultValue,
  },
)

// Global shortcuts
t('common.ok')
tPlural('items', 5)
```

### Locale Management

```dart
// Get/set current locale
Locale get currentLocale
Future<void> setLocale(Locale locale)
Future<void> setLocaleFromString(String locale)

// Get available locales
List<Locale> get availableLocales

// Get fallback locale
Locale get fallbackLocale
```

### Formatting

```dart
// Format date
String formatDate(DateTime date)
void setDateFormatter(DateFormatter formatter)

// Format number
String formatNumber(num number)
void setNumberFormatter(NumberFormatter formatter)
```

### Listeners

```dart
// Listen to locale changes
void addListener(Function() callback)
void removeListener(Function() callback)
```

### Preferences

```dart
// Singleton instance
I18nPreferences getI18nPreferences()

// Save/load user preference
Future<void> saveLocalePreference(Locale locale)
Future<Locale?> loadLocalePreference()

// Get best locale from available list
Future<Locale> getBestAvailableLocale(List<Locale> locales)
```

## 📦 Pre-Built Language Packs

### Included Languages

| Locale | Language | Included |
|--------|----------|----------|
| en | English | ✅ |
| es | Spanish | ✅ |
| fr | French | ✅ |
| de | German | ✅ |
| ja | Japanese | ✅ |
| zh | Chinese (Simplified) | ✅ |

### String Coverage

Each language pack includes:
- 17 **common** strings (OK, Cancel, Save, etc.)
- 8 **navigation** strings (Home, Settings, Profile, etc.)
- 10 **error** messages (validation errors, network errors, etc.)
- 12 **form** labels (Email, Password, Name, etc.)
- 10 **message** strings (Welcome, Thank you, etc.)
- 3 **plural** examples (items, users, messages)
- 7 **time** strings (relative timestamps)

**Total: 67 pre-translated strings per language**

### Example: English Pack

```dart
{
  'common': {
    'ok': 'OK',
    'cancel': 'Cancel',
    'save': 'Save',
    // ... 14 more
  },
  'navigation': {
    'home': 'Home',
    'settings': 'Settings',
    // ... 6 more
  },
  // ... more sections
}
```

## 🎯 Common Patterns

### Multi-Language App

```dart
void main() {
  initializeI18n(
    defaultLocale: const Locale('en'),
  );

  final i18n = getI18n();
  
  // Load all supported languages
  i18n.loadTranslations(const Locale('en'), enUS);
  i18n.loadTranslations(const Locale('es'), esES);
  i18n.loadTranslations(const Locale('fr'), frFR);

  runApp(MyApp());
}

class SettingsPage {
  Widget buildLanguageSelector() {
    return Column(
      children: [
        for (final locale in i18n.availableLocales)
          ListTile(
            title: Text(getLanguageName(locale)),
            onTap: () async {
              await i18n.setLocale(locale);
              await saveLocalePreference(locale);
            },
          ),
      ],
    );
  }
}
```

### Reactive UI Updates

```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late I18n i18n;

  @override
  void initState() {
    super.initState();
    i18n = getI18n();
    
    // Listen to locale changes
    i18n.addListener(() {
      setState(() {
        // Rebuild with new translations
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: t('app.title'),  // Translatable title
      home: HomePage(),
    );
  }
}
```

### Form Validation Messages

```dart
class LoginForm {
  void validateEmail(String email) {
    if (email.isEmpty) {
      showError(t('errors.required'));
    } else if (!isValidEmail(email)) {
      showError(t('errors.invalidEmail'));
    }
  }

  void validatePassword(String password) {
    if (password.length < 8) {
      showError(t('errors.passwordTooShort'));
    }
  }
}
```

### Pluralized Notifications

```dart
void showNotifications(int count) {
  // Automatically shows correct form:
  // "No messages" / "1 message" / "5 messages"
  showMessage(tPlural('plurals.messages', count));
}
```

### Nested Translations

```dart
// Custom translation structure
final myTranslations = {
  'settings': {
    'appearance': {
      'theme': 'Theme',
      'language': 'Language',
      'fontSize': 'Font Size',
    },
    'privacy': {
      'dataCollection': 'Data Collection',
      'tracking': 'Tracking',
    },
  },
};

i18n.loadTranslations(const Locale('en'), myTranslations);

// Access nested values
t('settings.appearance.theme');   // 'Theme'
t('settings.privacy.tracking');   // 'Tracking'
```

### Custom Date/Number Formatting

```dart
// Set custom formatters
i18n.setDateFormatter((date) {
  return '${date.day}/${date.month}/${date.year}';
});

i18n.setNumberFormatter((number) {
  return number.toStringAsFixed(2);
});

i18n.formatDate(DateTime.now());      // '11/09/2026'
i18n.formatNumber(1234.5);             // '1234.50'
```

### Persist User Language

```dart
// On app start, restore saved preference
Future<void> initializeApp() async {
  final savedLocale = await loadLocalePreference();
  if (savedLocale != null) {
    await i18n.setLocale(savedLocale);
  }
}

// When user changes language
Future<void> changeLanguage(Locale locale) async {
  await i18n.setLocale(locale);
  await saveLocalePreference(locale);
}
```

## 🔌 Integration with Other Features

### With Routing

```dart
// Navigate with translated labels
app.navigate('/settings', params: {
  'title': t('navigation.settings'),
});
```

### With Design System

```dart
// Use translated text in components
final button = DSButton.primary(
  label: t('common.save'),
  eventId: 'save',
);

final alert = DSAlert.success(
  message: t('messages.saveSuccess'),
);
```

### With State Management

`I18n` is a `Listenable`, so it is followed like any other store:

```dart
// Tell something else when the language changes
i18n.addListener(() => analytics.setLanguage(i18n.currentLocale.languageCode));

// Re-render when the locale changes
@override
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: getI18n(),
    builder: (context, _) => Text(t('common.ok')),
  );
}
```

For a key, `const Tr('common.ok')` is the same thing in one widget.

## 📋 Best Practices

### 1. Use Hierarchical Keys

```dart
// Good
t('forms.email');
t('errors.required');
t('navigation.settings');

// Avoid
t('email');
t('required_error');
t('nav_settings');
```

### 2. Store Translations as Constants

```dart
// Bad - inline strings
UIBuilder.text('Email');
UIBuilder.text('Password');

// Good - use translation keys
UIBuilder.text(t('forms.email'));
UIBuilder.text(t('forms.password'));
```

### 3. Use Plurals Correctly

```dart
// Good - let i18n handle singular/plural
showMessage(tPlural('items', count));

// Avoid - manual string building
if (count == 1) {
  showMessage('1 item');
} else {
  showMessage('$count items');
}
```

### 4. Provide Defaults

```dart
// Good - fallback when key not found
t('custom.key', defaultValue: 'Custom Label');

// Less ideal - breaks if key missing
t('custom.key');  // Returns 'custom.key' as fallback
```

### 5. Separate Concerns

```dart
// Create separate translation files per feature
const appTranslations = {...};
const authTranslations = {...};
const settingsTranslations = {...};

// Load them all
i18n.loadTranslations(locale, {...appTranslations, ...authTranslations});
```

## 🧪 Testing

### Test Translations

```dart
test('translate english to spanish', () {
  i18n.setLocale(const Locale('es'));
  expect(t('common.ok'), equals('Aceptar'));
});

test('pluralization works correctly', () {
  expect(tPlural('items', 0), contains('No'));
  expect(tPlural('items', 1), contains('1'));
  expect(tPlural('items', 5), contains('5'));
});

test('parameters interpolate correctly', () {
  const params = {'name': 'John'};
  final result = t('messages.welcome', params: params);
  expect(result, contains('John'));
});
```

## 🌐 Adding New Languages

### Step 1: Create Translation Map

```dart
const ptBR = {
  'common': {
    'ok': 'OK',
    'cancel': 'Cancelar',
    // ... all strings
  },
  // ... all sections
};
```

### Step 2: Load Translations

```dart
i18n.loadTranslations(const Locale('pt', 'BR'), ptBR);
```

### Step 3: Make Available

```dart
// Add to language selector
final languages = [
  ('en', 'English'),
  ('es', 'Español'),
  ('pt_BR', 'Português'),
];
```

## 📁 Files

```
packages/native_bridge/lib/i18n/
├── translations.dart        (I18n, Locale, t(), Tr's lookup)
├── translation_bundles.dart (6 language packs)
└── i18n_preferences.dart    (Persistence layer)

lib/examples/apps/
└── i18n_example_app.dart    (The demo app, written against widgets.dart)

I18N_GUIDE.md (This file)
```

## 🎉 Summary

A **complete internationalization system** with:

✅ 6 pre-built language packs (67 strings each)
✅ Pluralization with multiple forms
✅ Parameter interpolation
✅ Locale persistence
✅ Custom formatters
✅ Change listeners
✅ Fallback handling
✅ Cross-platform support

**Ready for multi-language global apps!** 🌍
