# API Reference

The programmatic surface of dart_not_native: entry points, theming, the node
vocabulary, the widget layer by family, the router and bloc companions, the
service contracts, i18n and the plugin system.

This is a map, not a copy. The doc comments in the source are the reference -
each widget's says what it carries to the renderers and what it accepts and
leaves alone - and this file says where to look. For worked examples see
`COMPONENTS_SHOWCASE.md`, `ROUTING_GUIDE.md` and `TEXTINPUT_GUIDE.md` in the
repository root; for adopting the framework, `INTEGRATION.md`.

## Entry points

From `package:dart_not_native/widgets.dart`:

```dart
Future<void> runApp(
  Widget app, {
  bool nativeViews = true,     // false paints with the Flutter renderer instead
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
});

NativeUIApp hostApp(Widget widget, {AppTheme theme = AppTheme.fallback});
```

`runApp` mounts a widget and renders it through the platform's own views (the
DOM on web), falling back to Flutter widgets where no native renderer is
available. `hostApp` wraps a widget as the `NativeUIApp` everything else
mounts - it is what a test hands to `InMemoryRenderer`, what a web entry hands
to `runWebApp`, and what a Flutter app hands to `NativeUIAppHost`.

From `package:dart_not_native/run_app.dart`, for a hand-written `NativeUIApp`:

```dart
Future<void> runNativeApp(
  NativeUIApp app, {
  bool nativeViews = false,    // note: the opposite default to runApp
  bool systemBack = true,
  String title = '',
  AppTheme appTheme = AppTheme.fallback,
  bool debugShowRenderErrors = false,
});
```

(The Flutter build of it also takes `ThemeData? theme`, the web build
`WebStyleKit? kit` and `String rootId`.)

From `package:dart_not_native/web.dart`:

```dart
Future<void> runWebApp(
  NativeUIApp app, {
  WebStyleKit? kit,            // MdlKit() by default; overridable with ?kit=
  String rootId = 'app',
  AppTheme theme = AppTheme.fallback,
});
```

From `package:dart_not_native/material.dart`, inside a Flutter app:

```dart
NativeUIAppHost({Key? key, required NativeUIApp app, AppTheme theme = AppTheme.fallback})
```

## Theming

Two classes, for two audiences.

**`ThemeData`** (in `widgets.dart`) is Flutter's: `ColorScheme` with
`fromSeed`, `TextTheme`, `IconThemeData`, `AppBarTheme`, `ThemeExtension`,
`copyWith`. Widgets read it with `Theme.of(context)`. `ColorScheme.fromSeed`
approximates Material's tonal palettes - see its doc comment.

**`AppTheme`** is the protocol's palette, which the renderers colour their own
chrome with. They need it before the first widget is built, so an app passes
it to `runApp` and derives it from its `ThemeData`:

```dart
final light = ThemeData(colorSchemeSeed: Colors.teal);
final dark = ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark);

runApp(
  MaterialApp(theme: light, darkTheme: dark, home: const Home()),
  appTheme: light.toAppTheme(dark: dark, mode: ThemeMode.system),
);
```

`toAppTheme` maps `primary`, `onPrimary`, `secondary`, `surface` and `error`
to their namesakes, `text` to `onSurface`, `textSecondary` to
`onSurfaceVariant`, `divider` to `outlineVariant` and `surfaceVariant` to
`surfaceContainer`. `Theme.of(context).appTheme` reads the palette back.

Written by hand, colours are `#rrggbb` strings:

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
  double glassTransparency = 0.0,     // iOS 26 modal glass: 0 frosted … 1 clear
  bool glassChrome      = true,       // iOS 26 glass on the app bar and FAB
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

## The protocol

`package:dart_not_native/core.dart`. A screen is a tree of
`WidgetNode{type, props, children}`; `UIBuilder` has a static method per node
type, and `nodeTypes` in `lib/src/ui_renderer.dart` is the contract every
renderer draws - 59 types. `renderer_coverage_test.dart` reads each renderer's
dispatch out of its source and fails if one is missing.

Colours on a node are `#rrggbb`, or `#aarrggbb` with alpha. Alignments are
`[x, y]` pairs from -1 to 1. Insets are `[left, top, right, bottom]`.

| Family | Node types |
|---|---|
| Structure | `Scaffold`, `AppBar`, `NavigationStack`, `NavigationBar` |
| Layout | `Column`, `Row`, `Wrap`, `Expanded`, `Center`, `Padding`, `SizedBox`, `Spacer`, `Divider`, `VStack`, `HStack` |
| Content | `Text`, `Image`, `Loading`, `Badge`, `Alert`, `Card` |
| Controls | `Button`, `MaterialButton`, `IconButton`, `FloatingActionButton`, `TextField`, `Checkbox`, `Radio`, `Toggle`, `Slider`, `Tabs` |
| Lists | `List`, `ListView`, `ListItem`, `ListRow`, `LazyList`, `GridView` |
| Overlays | `Overlay`, `Dialog`, `BottomSheet`, `Snackbar` |
| Gestures | `SwipeActions` |
| Motion | `AnimatedOpacity`, `AnimatedContainer` |
| Embedded | `WebView`, `MapView`, `CameraPreview` |
| **Free-form** | `Box`, `Stack`, `Positioned`, `Scroll`, `Icon` |
| **Drawing** | `Canvas` |
| **Choosing** | `Dropdown`, `DatePicker`, `TimePicker` |
| **Bottom chrome** | `BottomBar`, `BottomNavigation` |
| **Flutter region** | `FlutterSlot` |

The bold rows are the twelve types added since 0.1.0. On Android they have
been drawn on an emulator - all but `DatePicker` and `TimePicker`, which no
app there opened. **On iOS all twelve are drawn by the device lane on a
simulator, and the controls gallery, a dropdown and both pickers have been
looked at by hand; a `FlutterSlot` has drawn only its fallback.**

### The newer nodes

Each `UIBuilder` method's doc comment is the specification; in brief:

| Builder | What it is |
|---|---|
| `UIBuilder.box` | One decorated box around at most one child. Size (`width`/`height`, min/max, `expand`, `aspectRatio`), space (`padding`, `margin`, `alignment`), paint (`color`, `gradient`, border, `borderRadius`/`borderRadii`, `shape: 'circle'`, `shadow`, `clip`, `opacity`, `transform`), touch (`onTap`, `onDoubleTap`, `onLongPress`, `onPan`, `ripple`), drag and drop (`dragData`, `onDrop`, `onDropHover`), measuring (`onSize`), and motion (`animateMs`, `curve`) |
| `UIBuilder.stack`, `positioned` | Children drawn over one another; a `Positioned` child is pinned to the edges it names |
| `UIBuilder.scroll` | A scroller on either axis, with `shrinkWrap`, `reverse`, pull-to-refresh (`onRefresh`, `refreshing`), a scroll-to (`scrollOffset` + `scrollVersion`) and `onScroll`: the node carries a `scrollEventId` and the renderer sends `{offset, maxExtent, viewport}` when the scroller comes to rest and at most every 100 ms on the way |
| `UIBuilder.icon` | One glyph of an icon font, by codepoint |
| `UIBuilder.canvas` | A surface drawn by a command list - `rect`, `rrect`, `circle`, `oval`, `line`, `arc`, `path`, `text`, `save`/`restore`, `translate`, `rotate`, `scale`, `clipRect`, `clipRRect` - against a table of paints. A render that changes only the commands repaints in place |
| `UIBuilder.dropdown` | One of a list, from the platform's own menu |
| `UIBuilder.datePicker`, `timePicker` | The platform's pickers, as overlays; dates are `yyyy-mm-dd` |
| `UIBuilder.bottomBar` | Pins its child along a scaffold's bottom edge |
| `UIBuilder.bottomNavigation` | The app's destinations; `rail: true` lays them down the leading edge |
| `UIBuilder.flutterSlot` | A region the Flutter engine paints - see *FlutterSlot* below |

### Props added to the older nodes

- `scaffold`: `bottomBar`, `bodyScrolls` (the widget layer's `Scaffold` sends
  false), `backgroundColor`, `safeArea`.
- `appBar`: `leading` (`'back'`, `'close'`, `'menu'`) with `onLeading`,
  `actions`, `titleNode`, `centerTitle`, `backgroundColor`,
  `foregroundColor`, `elevation`.
- `column`, `row`: `mainAxisSize`, `spaceAround`/`spaceEvenly`, `spacing`;
  `wrap`: `alignment`, `crossAxisAlignment`; `expanded`: `fit`.
- `text`: `textAlign`, `letterSpacing`, `lineHeight`, `fontFamily`, `italic`,
  `selectable`, `spans` (styled runs; no tap on a span), `maxLines`,
  `overflow`.
- `image`: an optional `fallback` child, drawn while loading and on failure.
- `button`: `'outlined'` and `'tonal'` variants, `iconCodepoint`,
  `foregroundColor`, `expand`; `floatingActionButton`: `label` (extended).
- `textField`: prefix and suffix icons (`<eventId>_suffix` on tap),
  `maxLength`, `textCapitalization`, `textAlign`, and the read-only tappable
  field a picker opens from.
- `checkbox`, and the `Radio` and `Toggle` nodes: `disabled`.

### Root props and renderer events

`RootProps.textDirection`: `'rtl'` on the root of the tree lays the whole
screen out right to left. `UIBuilder.withTextDirection(root, 'rtl')` puts it
there; the widget layer's `MaterialApp` does so from its locale. What has a
start and an end turns; what names a side or a coordinate (`padding`, a
`Positioned`'s `left`, an alignment's x, `textAlign: 'left'`, canvas
coordinates) does not.

`RendererEvents` are sent by a renderer on its own account:

| Event | Payload |
|---|---|
| `RendererEvents.viewport` (`dnn:viewport`) | `{width, height, paddingTop, paddingBottom, paddingLeft, paddingRight, keyboardInset, devicePixelRatio, textScale, dark}` - what `MediaQuery` answers from |
| `RendererEvents.key` (`dnn:key`) | `{key, down}` - what `KeyboardListener` hears |
| `RendererEvents.slotRect` (`dnn:slotRect`) | `{slotId, x, y, width, height, visible}` - where a `FlutterSlot` is |
| `RendererEvents.lifecycle` (`dnn:lifecycle`) | `{state}` - `resumed`, `inactive`, `paused`, `detached` |

An event is answered by the build it was raised against: the tree travels
with its build number, both native renderers hand it back with each event,
the web and Flutter renderers name the build they are showing, and
`EventBindings` keeps the last few builds' callbacks. Verified on an Android
emulator; the Swift that sends it compiles, and the stale-callback case it
is there for has not been tried on iOS.

### Errors

`NativeUIRenderer.render` answers with a `RenderError` (`kind`, `nodeTypes`,
`message`, `cause`) or null. `NativeUIApp.renderErrors` is a broadcast stream
of them, `onRenderError` a single handler, and
`runApp(..., debugShowRenderErrors: true)` draws the last few over the app.

## The widget layer

`package:dart_not_native/widgets.dart`, in parts under `lib/src/widgets/`.
Flutter's names, signatures and semantics; pure Dart.

| Family | File | Contents |
|---|---|---|
| Model | `lib/widgets.dart` | `Widget`, `StatelessWidget`, `StatefulWidget`, `State`, `BuildContext`, `Key`/`ValueKey`/`GlobalKey`/`UniqueKey`, `InheritedWidget`, `ListenableBuilder`, `ValueListenableBuilder`, `runApp`, `hostApp`, `kIsWeb`, `kDebugMode`, `debugPrint` |
| Async | `lib/src/widgets/async.dart` | `Builder`, `StatefulBuilder`, `FutureBuilder`, `StreamBuilder`, `AsyncSnapshot` |
| Binding and environment | `lib/src/widgets/binding.dart` | `WidgetsFlutterBinding`, `WidgetsBinding` (`addPostFrameCallback`, observers), `AppLifecycleState`, `MediaQuery`, `LayoutBuilder`, `Ticker` and the ticker-provider mixins, `KeyboardListener`, `Directionality`, `Localizations`, `TimeOfDay` |
| Geometry and paint values | `lib/src/widgets/painting.dart` | `Color`, `Colors`, `Offset`, `Size`, `Rect`, `RRect`, `BoxConstraints`, `EdgeInsets` and `EdgeInsetsDirectional`, `Alignment` and `AlignmentDirectional`, `BorderRadius`, `Border`, `BoxShadow`, `LinearGradient`, `RadialGradient`, `BoxDecoration`, shape borders, `Matrix4`, the layout enums |
| Theme | `lib/src/widgets/theme.dart` | `ThemeData`, `ColorScheme`, `TextTheme`, `TextStyle`, `FontWeight`, `IconThemeData`, `AppBarTheme`, `ThemeExtension` |
| Layout | `lib/src/widgets/layout.dart` | `Column`, `Row`, `Flex`, `Wrap`, `Center`, `Align`, `Padding`, `Expanded`, `Flexible`, `SizedBox`, `Spacer`, `Container`, `DecoratedBox`, `ConstrainedBox`, `AspectRatio`, `FittedBox`, `SafeArea`, `ClipRRect`, `ClipOval`, `Opacity`, `Transform`, `Material`, `Stack`, `Positioned`, `IndexedStack`, `Visibility`, `Offstage`, `IgnorePointer`, `Semantics`, `Tooltip`, `CircleAvatar`, `Card`, `Divider` |
| Text and images | `lib/src/widgets/text.dart` | `Text`, `RichText`, `TextSpan`, `SelectableText`, `DefaultTextStyle`, `Icon`, `IconTheme`, `Image` (`.network`, `.asset`, `.memory`), `Theme`, and `Tr` (a translation key as a widget - framework-specific) |
| Buttons and simple controls | `lib/src/widgets/buttons.dart` | `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton`, `IconButton`, `FloatingActionButton`, `ButtonStyle`, `InkWell`, the chips, `Checkbox`, `Radio`, `Switch`, `Slider`, the progress indicators |
| Text input and forms | `lib/src/widgets/inputs.dart` | `TextField`, `TextEditingController`, `FocusNode`, `FocusScope`, `InputDecoration`, `Form`/`FormState`/`FormField`/`TextFormField` (Flutter's), `FormModel`/`FormFieldModel`/`ModelTextFormField` (the framework's own form model), `DropdownButton`, `DropdownButtonFormField`, `showDatePicker`, `showTimePicker` |
| Scrolling and lists | `lib/src/widgets/scrolling.dart` | `SingleChildScrollView`, `ListView` (+ `.builder`, `.separated`), `GridView` (+ `.count`, `.builder`, `.extent`), `ScrollController`, `RefreshIndicator`, `ListTile`, `ExpansionTile`, `CheckboxListTile`, `SwitchListTile`, `RadioListTile` |
| Navigation and chrome | `lib/src/widgets/navigation.dart` | `MaterialApp` (+ `.router`), `Navigator`/`NavigatorState`, `MaterialPageRoute`, `PageRouteBuilder`, `Scaffold`, `AppBar`, `BackButton`, `NavigationBar`, `BottomNavigationBar`, `NavigationRail`, `TabBar`/`TabBarView`/`TabController`/`DefaultTabController`, `showDialog`, `AlertDialog`, `SimpleDialog`, `showModalBottomSheet`, `ScaffoldMessenger`, `SnackBar` |
| Gestures | `lib/src/widgets/gestures.dart` | `GestureDetector`, `Draggable`, `LongPressDraggable`, `DragTarget`, `Dismissible` |
| Motion | `lib/src/widgets/motion.dart` | `Curves`, `AnimatedOpacity`, `AnimatedContainer`, `AnimatedScale`, `AnimatedRotation`, `AnimatedSlide`, and - without their animation - `AnimatedPadding`, `AnimatedAlign`, `AnimatedSwitcher`, `AnimatedSize`, `AnimatedCrossFade` |
| Drawing | `lib/src/widgets/custom_paint.dart` | `CustomPaint`, `CustomPainter`, `Canvas`, `Paint`, `Path`, `TextPainter` |
| Platform views | `lib/src/widgets/platform_views.dart` | `SwipeActions`, `WebView`, `MapView`, `CameraPreview`, `Badge`, `Alert`, `FlutterSlot` |

What is deliberately different from Flutter is collected in `INTEGRATION.md`
§8.9. The breaking changes that brought the layer to Flutter's shape are at
the top of `CHANGELOG.md`; the ones existing code meets first:

- A `Scaffold`'s body does not scroll.
- `ListView.builder(itemBuilder: (context, index) => ...)`; windowed when
  given `itemExtent` or `itemExtentBuilder`.
- `Theme.of(context)` is a `ThemeData`; the palette is `.appTheme`.
- `Form`, `FormField` and `TextFormField` are Flutter's; the framework's form
  model is `FormModel`, bound with `ModelTextFormField(field:)`.
- `Locale('en', 'US')` is positional; a script needs `Locale.fromSubtags`.

Not in the layer at all: `AnimationController` and `Tween`, `PageView`,
`CustomScrollView` and slivers, `DataTable`, `Stepper`,
`ReorderableListView`, `InteractiveViewer`, `WillPopScope`. There in name only,
so that a screen compiles: `Hero` (no flight), `MouseRegion` (no hover),
`FadeTransition` (the value when built). `PopupMenuButton` opens its menu as
a dialog.

## Router - `package:dart_not_native/router.dart`

go_router's names and signatures over this widget layer; pure Dart.

```dart
final router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) => signedIn ? null : '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/guests/:id',
          builder: (context, state) => GuestScreen(state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

runApp(MaterialApp.router(routerConfig: router));
```

| | |
|---|---|
| `GoRouter(routes:, initialLocation:, redirect:, refreshListenable:, errorBuilder:, redirectLimit:)` | a `ChangeNotifier` and a `RouterConfig` |
| `go`, `goNamed`, `push`, `pushNamed`, `replace`, `pop`, `canPop`, `refresh`, `namedLocation` | on the router and, through `GoRouterHelper`, on `BuildContext` |
| `GoRoute(path:, name:, builder:, redirect:, routes:)`, `ShellRoute(builder:, routes:)` | the route table |
| `GoRouterState` | `pathParameters`, `uri`, `matchedLocation`, `extra`, `error` |
| `attachHistory(HistoryAdapter)` | keeps the platform's history in step - on web, `BrowserHistoryAdapter()` from `web.dart`, followed by `bindBrowserBack()` |

Not there: `pageBuilder`/`Page`s and transitions, `StatefulShellRoute`,
navigator keys, `onExit`, inline path patterns. Unlike go_router, `push`
writes a history entry too.

## Bloc - `package:dart_not_native_bloc/dart_not_native_bloc.dart`

A separate package (`packages/dart_not_native_bloc`), depending on the
pure-Dart `bloc` and re-exporting it. `BlocProvider` (+ `.value`),
`RepositoryProvider`, `MultiBlocProvider`, `MultiRepositoryProvider`,
`MultiBlocListener`, `BlocBuilder`, `BlocListener`, `BlocConsumer`,
`BlocSelector`, and `context.read<T>()`, `watch<T>()`, `select(...)`.

`buildWhen` decides which state a builder is given, not whether its function
runs, and `select` is `watch` with the selector applied: the tree rebuilds
from the root on any change, so neither prunes work.

## FlutterSlot

```dart
FlutterSlot(
  slotId: 'banner',
  height: 50,
  width: 320,                       // optional; fills the width otherwise
  builder: buildAd,                 // a Flutter Widget Function(BuildContext)
  fallback: const SizedBox(height: 50),
)
```

The widget is in `widgets.dart` (`builder` is typed `Object`, since that
library cannot name Flutter's types). `package:dart_not_native/flutter_slot.dart`
- which imports Flutter - has the protocol-level `flutterSlotNode(...)`, the
`FlutterSlotLayer` that paints registered widgets at their reported
rectangles, and the full account of the two limits: the rectangle follows
native scrolling a frame late, and touches inside it go to Flutter.

## Testing

`InMemoryRenderer` (in `core.dart`) keeps the latest tree and dispatches
events to it:

```dart
final renderer = InMemoryRenderer();
hostApp(const MyScreen()).mount(renderer);
renderer.tree;                                  // the WidgetNode tree
await renderer.handleEvent(eventId, {});        // what a renderer would send
```

`AppTester` in `package:dart_not_native/testing.dart` is a small harness over
it (find by id, `tap`, `toggle`, `typeInto`, `submitInto`, `emit`), and
`AppTester.widget(const MyScreen())` is the two lines above in one.

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
`WebSecureStorage` encrypts values with the browser's own AES-GCM crypto and
can rotate its key; on mobile an app wraps `flutter_secure_storage`.
`storage.migrate([...])` runs numbered migration steps over any
`StorageService`.

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

From `package:dart_not_native/core.dart`. The framework's own translation
table; an app that keeps Flutter's gen-l10n instead reads
`Localizations.localeOf(context)` and looks its generated classes up directly
(`INTEGRATION.md` §8.4).

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

`Locale` is Flutter's shape: `Locale('en', 'US')`, with `languageCode`,
`countryCode`, `scriptCode` and `toLanguageTag()`;
`Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')`
names a script and `Locale.fromString('zh_Hans_CN')` parses one. In the widget
layer `Tr('some.key')` draws a translation and redraws when the locale
changes. See `I18N_GUIDE.md`.

## Plugins

A plugin bundles services, routes and event handlers under a stable name.
Extend `Plugin` (or `BasePlugin`), register services, and add it to the
registry. The plugin classes are exported by `material.dart`.

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
