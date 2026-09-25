# API Reference

The programmatic surface of dart_not_native — entry points, theming, the service
contracts, i18n and the plugin system. For the **widgets**, see
`COMPONENTS_SHOWCASE.md`; for **routing** and **forms**, see `ROUTING_GUIDE.md`
and `TEXTINPUT_GUIDE.md`.

## Entry points

From `package:dart_not_native/widgets.dart`:

```dart
Future<void> runApp(
  Widget app, {
  bool nativeViews = true,     // false paints with the Flutter renderer instead
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
});
```

`runApp` mounts a facade `Widget` and renders it through the platform's own
views (the DOM on web). The web entry points call `runWebApp` from
`package:dart_not_native/web.dart` instead:

```dart
Future<void> runWebApp(
  NativeUIApp app, {
  WebStyleKit? kit,            // MdlKit() by default; overridable with ?kit=
  String rootId = 'app',
  AppTheme theme = AppTheme.fallback,
});
```

## Theming — `AppTheme`

A palette carried to every renderer. Colours are `#rrggbb` strings.

```dart
const AppTheme({
  String primary        = '#1976d2',  // app bar, primary buttons, FAB
  String onPrimary      = '#ffffff',  // text/icons drawn on primary
  String secondary      = '#f57c00',  // secondary button/badge variant
  String surface        = '#ffffff',  // a scaffold's background
  String surfaceVariant = '#f5f5f5',  // cards, modal panels, a field's fill
  String text           = '#212121',  // body text and headings
  String textSecondary  = '#757575',  // labels, hints, helper lines, icons
  String divider        = '#e0e0e0',  // dividers, card outlines, field borders
  String error          = '#d32f2f',  // error variant and field error text
  String success        = '#388e3c',  // success variant
  String warning        = '#fbc02d',  // warning variant
  String info           = '#0288d1',  // info variant, and an alert's default
  AppThemeMode mode     = AppThemeMode.light,
  AppTheme? dark,                     // defaults to AppTheme.darkFallback
});

runApp(const MyApp(), appTheme: const AppTheme(primary: '#00897b'));
```

### Dark mode

The colours above are the *light* palette; `dark` is the counterpart and `mode`
picks between them:

| `mode` | what is painted |
| --- | --- |
| `AppThemeMode.light` (default) | the theme's own colours, whatever the device is doing |
| `AppThemeMode.dark` | `dark` |
| `AppThemeMode.system` | whichever the device asks for, repainting when it changes |

```dart
// Follow the device, using the built-in dark palette.
runApp(const MyApp(), appTheme: const AppTheme(mode: AppThemeMode.system));

// Follow the device, with a dark palette of your own.
runApp(const MyApp(), appTheme: const AppTheme(
  primary: '#00897b',
  mode: AppThemeMode.system,
  dark: AppTheme(primary: '#4db6ac', surface: '#101413', text: '#e6f2f0'),
));
```

`system` is answered by the platform itself - the trait collection on iOS, the
night ui-mode on Android, `prefers-color-scheme` on web,
`MediaQuery.platformBrightness` on Flutter - so an app writes nothing to follow
the device, and nothing to stay put.

The semantic colours have a dark counterpart like the rest, since a hue picked
to read on white goes muddy on a dark ground:

| | light | dark |
| --- | --- | --- |
| `success` | `#388e3c` | `#66bb6a` |
| `warning` | `#fbc02d` | `#ffca28` |
| `info` | `#0288d1` | `#4fc3f7` |
| `error` | `#d32f2f` | `#ef5350` |

A colour you pass on a node beats the theme in both appearances, so a card with
an explicit `backgroundColor` keeps it in dark mode too - leave it off to get
`surfaceVariant`.

## Storage

`StorageService` is the key–value contract an app injects (mobile apps wrap
`shared_preferences`; the web ships `LocalStorageService`). All methods are
async.

| Method | |
| --- | --- |
| `setString/Int/Double/Bool/StringList(key, value)` | write a typed value |
| `getString/Int/Double/Bool/StringList(key)` | read it back (nullable) |
| `remove(key)` · `clear()` · `containsKey(key)` | manage keys |
| `getKeys()` · `getAll()` | enumerate everything |

`SecureStorageService implements StorageService` for secrets. On the web,
`WebSecureStorage` encrypts values with the browser's own AES-GCM crypto; on
mobile an app wraps `flutter_secure_storage`.

```dart
await storage.setString('user_locale', 'en_US');
final locale = await storage.getString('user_locale');
```

## Biometrics

`BiometricsService` is the contract; `dart_not_native_local_auth` implements it
on the `local_auth` plugin.

| Member | |
| --- | --- |
| `authenticate(BiometricOptions)` → `BiometricResult` | prompt and check |
| `canCheckBiometrics()` · `deviceSupportsBiometrics()` | capability |
| `getAvailableBiometrics()` → `List<BiometricType>` | fingerprint/faceRecognition/… |
| `areBiometricsEnrolled()` · `stopAuthentication()` | state / cancel |

```dart
final result = await biometrics.authenticate(
  const BiometricOptions(reason: 'Unlock your notes'),
);
if (result.authenticated) { /* ... */ }
```

`BiometricResult` carries `authenticated`, `errorMessage`, `errorCode`.

## Internationalization — `I18n`

From `package:dart_not_native/core.dart`.

```dart
final i18n = I18n(defaultLocale: const Locale('en'))
  ..loadTranslations(const Locale('en'), {'greeting': 'Hello'})
  ..loadTranslations(const Locale('es'), {'greeting': 'Hola'});

i18n.t('greeting');                          // look up a key (dotted paths ok)
i18n.t('items', count: 3);                   // pluralised
i18n.t('welcome', params: {'name': 'Ada'});  // interpolated
i18n.setLocale(const Locale('es'));          // switch language
i18n.currentLocale;                          // the active Locale
```

`Locale` is `language` + optional `region` + `script` — `Locale.fromString('zh_Hans_CN')`
parses all three. The i18n example rebuilds from `setLocale`; see `I18N_GUIDE.md`.

## Plugins

A plugin bundles services, routes and event handlers under a stable name. Extend
`Plugin` (or `BasePlugin`), register services, and add it to the registry.

```dart
class AnalyticsPlugin extends BasePlugin {
  @override
  String get name => 'analytics';

  @override
  Future<void> initialize(PluginContext context) async {
    context.registerService<Analytics>('analytics', MyAnalytics());
  }
}
```

| Member | |
| --- | --- |
| `String get name` | stable id; the key its services register under |
| `List<String> get dependencies` | plugins that must start first |
| `initialize(PluginContext context)` | register services via `context`, do async setup |
| `dispose()` | tear down |
| `registerRoutes(router)` · `registerEventHandlers(renderer)` | contribute routes / native handlers |

The registry starts plugins in dependency order and rejects cycles or a
dependency nobody registered. The framework does **not** ship device-service
plugins — an app uses the pub.dev package directly (see `TODO.md` → *Device
services*).
