# dart_not_native

Write a screen once, in Dart, with Flutter's widget API - and have each
platform draw it with its own UI: Android Views, iOS UIViews, real DOM in the
browser. Flutter's engine hosts Dart and the plugins on mobile and is absent
on web; it does not paint the screen.

## TL;DR

```dart
import 'package:dart_not_native/widgets.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Hello')),
      body: const Center(child: Text('Drawn by the platform')),
    ),
  );
}
```

That is a Flutter app with one line changed - the import. The widgets are not
Flutter's: `widgets.dart` is a pure-Dart layer with Flutter's names,
signatures and semantics that builds a serialisable tree, and a renderer per
platform turns the tree into views.

```bash
flutter run --no-tree-shake-icons          # Android: MaterialToolbar, TextView, EditText…
flutter run --no-tree-shake-icons          # iOS: UIKit (see the status below)
dart compile js -O2 -o build/web/main.dart.js lib/main.dart   # web: DOM + CSS, no Flutter engine
```

The same tree can also be painted by Flutter's own widgets
(`runApp(..., nativeViews: false)`, or one screen at a time inside an existing
Flutter app), which is the renderer the test suite covers most heavily.

---

## Status

In one paragraph: **web and the Flutter renderer are tested; Android is run on
a phone and an emulator, including three migrated production apps; the iOS
renderer as it stands draws the examples on a simulator and has had none of
the three apps on it; nothing is on pub.dev.**
[TODO.md](TODO.md) and [the changelog](packages/native_bridge/CHANGELOG.md)
carry the detail, and this list is kept short so it does not drift out of step
with them.

### Today
- **One screen, four renderers** - Android Views, UIKit views, real DOM, or
  Flutter's own canvas, from the same tree. The native two patch their views
  rather than rebuild them, so a field keeps its focus and caret.
- **A Flutter-shaped widget layer wide enough to migrate onto** - layout and
  boxes (`Container`, `Stack`, `Positioned`, `Wrap`, `SafeArea`), scrolling
  (`ListView`, `GridView`, `SingleChildScrollView`, `RefreshIndicator`),
  Material controls and chrome, `Navigator.push` and named routes, Flutter's
  `Form`, `Theme.of` returning a `ThemeData`, `GestureDetector`, drag and
  drop, `CustomPaint`, `MediaQuery`/`LayoutBuilder`, implicit animations,
  tickers, right-to-left through `Directionality`, and all 8,825 Material
  icons. Each widget's doc comment says where it stops short of Flutter's.
- **Companions for the two packages most apps route and hold state with** -
  `package:dart_not_native/router.dart` is go_router's API, and
  `packages/dart_not_native_bloc` is flutter_bloc's over pure `bloc`.
- **A way to keep what only exists as a Flutter widget** - a `FlutterSlot`
  leaves a hole in the natively drawn screen for the engine underneath to
  paint an ad banner into. On the Android emulator an AdMob test banner
  showed through it at its 320×50dp and stayed put while the screen behind
  scrolled.
- **Three real apps migrated** and walked screen by screen on an Android
  emulator (Pixel 8, Android 15, debug builds): eighteen games each opened
  and played, a reminders app through its permission flow, tabs, charts,
  Arabic and dark mode, a planner's forms, dialogs and navigation rail. About
  thirty renderer bugs that only showed there were fixed. An emulator, not a
  phone. [INTEGRATION.md](INTEGRATION.md) §8 is the migration guide that
  came out of it, including the table of what looks or behaves differently.
- **Earlier, on hardware** - the example apps, 15 integration tests and five
  device flows on a physical Android phone; the iOS half on a simulator and an
  iPad. That iOS evidence predates the work above.

### Not there
- **iOS for anything recent.** The Swift for the twelve node types added
  since the last iOS run, for right-to-left, the image cache, the
  `FlutterSlot` hole, scroll reporting and the event build number compiles
  in CI, and on 2026-10-09 it passed the device check on a simulator: the
  five flows and every example app drawn with nothing left undrawn. One
  screen was then looked at - the controls gallery - and it had five layout
  bugs the green run had not shown, fixed since. None of the three migrated
  apps has run on it, and a `FlutterSlot` has only drawn its fallback.
  Assume a real screen will find more.
- **Animation you drive yourself.** No `AnimationController`, no page
  transitions; a `Hero` compiles and does not fly. Implicit animations of size, colour, opacity and
  transform are done by the renderer; a `Ticker` is a 16 ms timer.
- **Published packages.** Apps depend on the repository by path or git.
- **CI that boots a device.** The lanes compile and run the Dart suites; the
  device checks are run by hand (`tool/device_check.sh`).
- **Offline-first sync** - not here at all, deliberately (see below).
- **A screen-reader pass.** Labels, roles and states are set and asserted
  through the accessibility tree; nobody has listened to it.

---

## Quick start

### Run an example

```bash
flutter pub get
flutter run -t lib/main_native_todo.dart -d <device> --no-tree-shake-icons   # native views

maestro/web/build_examples.sh todo_example                                    # the web build
python3 -m http.server 8080 --directory build/web_examples
# open http://localhost:8080/todo_example/   (?kit=materialize for the other kit)
```

### Start an app

```yaml
# pubspec.yaml
dependencies:
  dart_not_native:
    git:
      url: https://github.com/tomavelev/dart_not_native.git
      path: packages/native_bridge
```

Write `lib/main.dart` as in the TL;DR, then:

- make `MainActivity` extend `FlutterFragmentActivity` (the system back
  gesture depends on it);
- pass `--no-tree-shake-icons` to every `flutter run` and `flutter build`
  (icons are made from codepoints at run time, and a release build fails
  without it);
- for web, compile the entry with `dart compile js` and copy
  `packages/native_bridge/web_shell/` next to the output.

[INTEGRATION.md](INTEGRATION.md) has each of those in full, and §8 of it is
the path for an app that already exists in Flutter.

### A theme, a route, some state

```dart
import 'package:dart_not_native/widgets.dart';

final light = ThemeData(colorSchemeSeed: Colors.teal);
final dark = ThemeData(
  colorSchemeSeed: Colors.teal,
  brightness: Brightness.dark,
);

Future<void> main() => runApp(
  MaterialApp(theme: light, darkTheme: dark, home: const Home()),
  title: 'My app',
  // The renderers colour their own chrome - app bar, platform buttons,
  // dialogs - from this, and need it before the first widget is built.
  appTheme: light.toAppTheme(dark: dark),
);

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Home')),
    body: Center(
      child: Text(
        '$_taps taps',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => setState(() => _taps++),
      child: const Icon(Icons.add),
    ),
  );
}
```

---

## How it is put together

```
your screens  ──  package:dart_not_native/widgets.dart      Flutter's API, pure Dart
                         │  builds
                  WidgetNode tree  (59 node types, JSON-serialisable)
                         │  rendered by one of
   ┌─────────────┬───────┴────────┬──────────────────┐
 Android Views   iOS UIViews     DOM + CSS kit     Flutter widgets
 (Kotlin plugin) (Swift plugin)  (dart2js)         (FlutterUIRenderer)
```

| Target | Drawn by | Flutter engine | Evidence |
|---|---|---|---|
| **Android** | `NativeUIRenderer.kt`: Material and platform views | hosts Dart and plugins | a phone and an emulator; three migrated apps on the emulator |
| **iOS** | `NativeUIRenderer.swift`: UIKit | hosts Dart and plugins | simulator and iPad for the earlier vocabulary; **current Swift: the examples on a simulator, one screen of them looked at** |
| **Web** | `WebUIRenderer`: DOM, styled by a CSS kit | none | browser test suite, markup goldens, Maestro flows |
| **Any Flutter host** | `FlutterUIRenderer`: Flutter widgets | paints | widget tests; every example rendered and checked for overflow |

A change rebuilds the widget tree from the root and the renderer patches what
moved. That is the cost model, and it has consequences worth reading before
writing a large screen - INTEGRATION.md §10.

### Repository layout

```
dart_not_native/
├── packages/
│   ├── native_bridge/               the framework (package name: dart_not_native)
│   │   ├── lib/
│   │   │   ├── widgets.dart         the Flutter-shaped widget layer
│   │   │   ├── src/widgets/         its parts, by family
│   │   │   ├── router.dart          go_router's API
│   │   │   ├── core.dart            the protocol: NativeUIApp, UIBuilder, WidgetNode
│   │   │   ├── web.dart             runWebApp, the DOM renderer, style kits
│   │   │   ├── material.dart        the Flutter host: NativeUIAppHost
│   │   │   ├── flutter_slot.dart    a Flutter widget inside a native screen
│   │   │   └── platforms/           the Dart side of each renderer
│   │   ├── android/                 Kotlin renderer and plugin
│   │   ├── ios/                     Swift renderer and plugin
│   │   └── web_shell/               index.html, CSS, self-hosted fonts
│   ├── dart_not_native_bloc/        flutter_bloc's widgets over pure bloc
│   └── dart_not_native_local_auth/  BiometricsService on local_auth
├── lib/examples/apps/               twelve example apps, platform-neutral
├── lib/examples/web/                their web entry points
├── lib/main_native_*.dart           dev entries: one example on native views
├── test/, integration_test/         example, golden, Flutter and device suites
├── maestro/native/, maestro/web/    device and browser flows
└── tool/                            device checks, test counting, icon generation
```

---

## State that outlives a screen

`setState` holds what one screen owns. Anything two screens share - a signed-in
user, a cart, a favourites list - lives in a store outside the tree and is read
where it is needed:

```dart
final favourites = ValueNotifier<Set<String>>({});

// The screen that writes it:
ElevatedButton(
  onPressed: () => favourites.value = {...favourites.value, user.id},
  child: const Text('Add favourite'),
)

// Any other screen, on any route:
ValueListenableBuilder<Set<String>>(
  valueListenable: favourites,
  builder: (context, ids, _) => Text('${ids.length} favourites'),
)
```

The app follows a store while it is on screen and lets go when it is not.
`ChangeNotifier`, `ListenableBuilder` and `InheritedWidget` are there too, with
Flutter's own names and signatures. An app that used flutter_bloc keeps its
blocs: `dart_not_native_bloc` has `BlocProvider`, `BlocBuilder`,
`BlocListener` and `context.read`.

See `lib/examples/apps/routing_example_app.dart`, where a user is favourited on
their own page and counted on the home page.

---

## Web (DOM + CSS)

Web builds do not ship the Flutter engine. The entry point is compiled with
plain dart2js, and `WebUIRenderer` builds real DOM and patches it in place on
every re-render (so a focused text field keeps its caret).

```dart
// lib/examples/web/calculator_example.dart
import 'package:dart_not_native/web.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;

import '../apps/calculator_app.dart';

void main() => runWebApp(hostApp(const CalculatorApp()));
```

```bash
maestro/web/build_examples.sh          # dart compile js + web shell, per example
```

Nothing reachable from a web entry may import Flutter or a Flutter plugin;
platform seams sit behind conditional imports. INTEGRATION.md §4 and §8.7.

### Style kits

How the Material components look is a *style kit*:

| Kit | `?kit=` | CSS framework |
|-----|---------|---------------|
| `MdlKit` (default) | `mdl` | Material Design Lite 1.3.0 |
| `MaterializeKit` | `materialize` | Materialize CSS 1.0.0 |
| `PlainKit` | `plain` | framework CSS only (`dnn.css`) |

The renderer owns layout, reconciliation and events; a kit only builds the
components (button, card, text field, app bar, list...) and names the
stylesheets to load. A new kit subclasses `WebStyleKit` and overrides only
what its framework styles - see
`packages/native_bridge/lib/web_ui/style_kit.dart`. Pick one in code
(`runWebApp(app, kit: MaterializeKit())`) or per page load with `?kit=<name>`.

Stylesheets and fonts are vendored under
`packages/native_bridge/web_shell/vendor/` - nothing is fetched from a CDN.
The icon font there is Flutter's own `MaterialIcons` family, so
`Icons.home_outlined` is the same glyph on every renderer.

### Tests

`maestro/web/run.sh generate|verify|check` runs Maestro flows for every
example in headless Chrome, once per kit, with per-kit screenshot baselines.
See [maestro/web/README.md](maestro/web/README.md).

---

## Examples

Eleven, under `lib/examples/apps/` - counter, calculator, todo, inbox,
sign-up form, text input, routing, storage, i18n, the design system and the
components showcase. All are written against `widgets.dart`.
[EXAMPLES_DIRECTORY.md](EXAMPLES_DIRECTORY.md) walks through each.

```bash
flutter run -t lib/main_native_inbox.dart -d <device> --no-tree-shake-icons
```

The three migrated apps live in repositories of their own and are the larger
worked examples; INTEGRATION.md §8 quotes from them.

---

## Offline-first (not here)

There is no sync in this package, and no types for one either. There used to
be a sketch - a pending-operation queue, a retry policy, a sync status - with
nothing behind it: every method threw `UnimplementedError`, and nothing in the
project ever called them. Publishing that would have turned a guess into
public API, and a shape fixed before any real backend argued with it is a bad
thing to owe compatibility to.

An app that has to work offline today keeps its own state with
`StorageService` and talks to its own backend. When sync is built it belongs in
its own package, designed against something real rather than in advance.

---

## Documentation

| Document | Purpose |
|----------|---------|
| **[INTEGRATION.md](INTEGRATION.md)** | Adding the framework to an app; **§8 is the migration guide for an existing Flutter app** |
| **[TODO.md](TODO.md)** | What is left before this is production ready, with the evidence behind each status |
| **[packages/native_bridge/CHANGELOG.md](packages/native_bridge/CHANGELOG.md)** | What changed, including what broke |
| **[packages/native_bridge/API_REFERENCE.md](packages/native_bridge/API_REFERENCE.md)** | Entry points, theming, the node vocabulary, the widget layer by family, router, bloc, storage, i18n, plugins |
| **[COMPONENTS_SHOWCASE.md](COMPONENTS_SHOWCASE.md)** | The widgets most screens use, with examples |
| **[ROUTING_GUIDE.md](ROUTING_GUIDE.md)** | `Navigator.push`, named routes, `GoRouter`, the back gesture |
| **[TEXTINPUT_GUIDE.md](TEXTINPUT_GUIDE.md)** | Text fields, and forms with validation |
| **[I18N_GUIDE.md](I18N_GUIDE.md)** | The `I18n` table and `Tr`; locale and right-to-left |
| **[EXAMPLES_DIRECTORY.md](EXAMPLES_DIRECTORY.md)** | Every example app and how it is wired |
| **[TESTING.md](TESTING.md)** | The test layers and how to run them |
| **[RELEASING.md](RELEASING.md)** | Versions, tags and the release checklist |
| **[packages/native_bridge/README.md](packages/native_bridge/README.md)** | The framework package |
| **[LICENSE](LICENSE)** / **[NOTICE](NOTICE)** | Apache 2.0, and the attribution to carry with it |

---

## Development

```bash
flutter test                                                # examples, goldens, Flutter widgets
cd packages/native_bridge && flutter test                   # framework unit tests
cd packages/native_bridge && flutter test --platform chrome test/web_ui   # DOM
cd packages/dart_not_native_bloc && flutter test            # the bloc companion

tool/device_check.sh android        # flows + integration tests on a device
tool/device_check.sh ios            # needs a Mac; see the iOS status above
```

[TESTING.md](TESTING.md) explains each layer.

### Build for production

```bash
flutter build apk --release --no-tree-shake-icons
flutter build appbundle --no-tree-shake-icons
flutter build ios --no-tree-shake-icons
dart compile js -O2 -o build/web/main.dart.js lib/main_web.dart   # then copy web_shell/
```

`flutter build web` builds something else: a Flutter web app, in which the
same tree is painted by Flutter's canvas instead of the DOM. It is the web
build for an app whose plugins plain dart2js cannot link
([INTEGRATION.md](INTEGRATION.md) §8.7).

---

## FAQ

**Q: Is this Flutter?**
A: The API is; the pixels are not. On mobile a Flutter engine runs your Dart
and your plugins while the platform's own views draw the screen. On web there
is no Flutter at all.

**Q: Can I use it with an existing Flutter app?**
A: Three ways: migrate the app (INTEGRATION.md §8), host one framework screen
inside it with `NativeUIAppHost` (§7), or keep one Flutter widget inside a
migrated screen with `FlutterSlot` (§8.6).

**Q: Do Flutter plugins work?**
A: On Android and iOS, yes - they talk to the engine, not to the widget tree.
A plugin whose product is a widget (an ad banner, a chart) needs a
`FlutterSlot` or redrawing. On web no Flutter plugin compiles; use a pure-Dart
package or the browser API through `package:web`.

**Q: Will a third-party widget package work?**
A: No - its widgets extend Flutter's. Redraw it with `CustomPaint` and boxes,
whose API is Flutter's, or put it in a `FlutterSlot`.

**Q: What looks different from the Flutter version of my app?**
A: The controls are the platform's own, so they look like the platform. Beyond
that there is a list: no page transitions, `Dismissible` reveals an action
instead of sliding away, a snackbar's look is the platform's, and more - the table in
INTEGRATION.md §8.9.

**Q: How does offline-first work?**
A: It does not; see above.

**Q: Is the FFI bridge still here?**
A: Yes - `NativeBridge.initialize` / `callMethod`, for calling into C. It is
separate from the renderers, optional, and documented in
`packages/native_bridge/README.md`.

---

## Roadmap

- ✅ Four renderers over one tree; native views patched, not rebuilt
- ✅ A Flutter-shaped widget layer, with go_router and flutter_bloc companions
- ✅ Three production apps migrated and run on an Android emulator
- ✅ Storage, including secure storage on web with key rotation
- ⏳ iOS: compile the current Swift, then run it
- ⏳ Explicit animation and page transitions
- ⏳ Publishing to pub.dev; CI for apps that consume the framework
- ⏳ Offline-first sync, as a package of its own

What is left, in order and with the reasoning, is [TODO.md](TODO.md).

---

## License

Copyright 2026 Toma Velev.

Licensed under the [Apache License, Version 2.0](LICENSE). You may use this
framework in commercial and closed-source products; if you redistribute it, or
a product built on it, carry the [NOTICE](NOTICE) file with it.

The web target self-hosts Roboto, Material Icons, Material Design Lite and
Materialize; their licences travel with them in
`packages/native_bridge/web_shell/vendor/` and are listed in NOTICE.
