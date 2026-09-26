# dart_not_native - Unified Cross-Platform Framework

A complete framework for building cross-platform apps (Android, iOS, Web) from a single Dart codebase. One dependency, one import, automatic platform detection.

## TL;DR

```dart
import 'package:dart_not_native/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Hello')),
        body: Center(child: Text('Works everywhere!')),
      ),
    );
  }
}
```

**That's it.** Same code, three platforms, two rendering engines:

```bash
flutter run                        # Android (Flutter native, 50MB)
flutter run                        # iOS (Flutter native, 80MB)
maestro/web/build_examples.sh      # Web (DOM + Material CSS, ~150KB of JS) ✨
```

On web the UI is real HTML styled by a Material CSS framework - Material
Design Lite or Materialize, picked by a *style kit* - rendered by
`WebUIRenderer`, with no Flutter engine and no canvas. See
[Web (DOM + Material CSS)](#web-dom--material-css).

---

## What's Included

Status in one line: the four renderers draw the whole vocabulary, Android is
proven on a phone, iOS is proven on a simulator and thin on one, and nothing
is published yet. [TODO.md](TODO.md) and
[the changelog](packages/native_bridge/CHANGELOG.md) carry the detail; this
list is deliberately short so it does not drift out of step with them.

### ✅ Today
- **One screen, four renderers** - real Android Views, real UIKit views, real
  DOM, or Flutter's own canvas, from the same widget tree. The native two are
  patched rather than rebuilt, so a field keeps its focus and caret.
- **A Flutter-shaped API** - `StatelessWidget`, `setState`, `Scaffold`,
  `TextField`, `showDialog`, a routed `MaterialApp`. A screen differs from a
  Flutter one only in its import.
- **The things an app hits early** - forms with validation, routing, i18n, a
  theme with a dark appearance, dialogs/sheets/snackbars, windowed long lists,
  swipe actions, secure storage on every platform.
- **Run on real hardware** - all five device flows and the integration suite
  pass on a physical Android phone; the iOS half passes on a simulator and the app
  runs on an iPad.
- **Optional native code** - FFI bridge and a plugin architecture.

### ⏳ Not there yet
- **Offline-first sync** - not here at all, and deliberately so (see
  *Offline-First* below). It belongs in its own package.
- **Published packages** - nothing is on pub.dev, and the CI lanes are written
  but have never executed, because the repository has no remote yet.
- **iOS screens on a phone** - six example apps have been looked at on a
  simulator and three on an iPad; the rest are drawn-without-error rather than
  seen.

---

## Quick Start

### Pure Flutter App (No Native Code)
```bash
flutter run lib/examples/todo_example.dart              # Android/iOS
maestro/web/build_examples.sh todo_example              # Web (DOM build)
```

Works identically on all platforms with **zero platform-specific code**.

### With Optional Native Code
```bash
flutter run lib/main.dart    # Counter with FFI demo
```

Shows how to add native C code for performance when needed.

---

## Project Structure

```
dart_not_native/
├── lib/
│   ├── main.dart                       # Demo counter (with FFI)
│   ├── examples/
│   │   ├── todo_example.dart          # Pure Flutter - no native
│   │   └── calculator_example.dart    # Pure Flutter - no native
│   ├── screens/                        # Demo screens
│   └── native/                         # App-specific native code
│
├── packages/native_bridge/             # Reusable framework (publish to pub.dev)
│   ├── lib/
│   │   ├── native_bridge.dart         # Platform detection
│   │   ├── platforms/
│   │   │   ├── mobile_bridge.dart     # FFI (Android/iOS)
│   │   │   └── web_bridge.dart        # In-memory (Web)
│   │   └── plugins/
│   └── README.md
│
├── android/app/
│   ├── src/main/cpp/bridge.c          # Optional native code
│   ├── CMakeLists.txt                 # Native build config
│   └── build.gradle.kts               # Android config
│
├── web/
│   └── index.html                     # Material Design Lite CSS
│
├── Documentation/
│   ├── README.md (this file)
│   ├── INTEGRATION.md                # Adding the framework to an app
│   ├── EXAMPLES_DIRECTORY.md         # Every example, and how to run it
│   ├── TESTING.md                    # The test layers
│   └── TODO.md                       # What's left before production
```

---

## Key Features

### 1. Single Codebase, Three Platforms

| Platform | How It Works | When to Use |
|----------|--------------|------------|
| **Android** | Flutter + optional FFI | All apps |
| **iOS** | Flutter + optional FFI | All apps |
| **Web** | Flutter Web + Material CSS | PWAs, dashboards |

**Same UI code everywhere. Platform detection is automatic.**

### 2. No Native Code Required

```dart
// Most apps: Pure Flutter
void main() {
  runApp(MyApp()); // Works on all platforms
}

// Advanced apps: Optional native code
void main() {
  NativeBridge.initialize('liboptimized.so');
  runApp(MyApp()); // Same app, with native performance
}
```

### 3. Offline-First (not here)

There is no sync in this package, and no types for one either. There used to
be a sketch - a pending-operation queue, a retry policy, a sync status - with
nothing behind it: every method threw `UnimplementedError`, and nothing in the
project ever called them. Publishing that would have turned a guess into
public API, and a shape fixed before any real backend argued with it is a bad
thing to owe compatibility to.

An app that has to work offline today keeps its own state with
`StorageService` and talks to its own backend. When sync is built it belongs in
its own package, designed against something real rather than in advance.

### 4. Plugin System

Add features without changing app code:

```dart
void main() {
  NativeBridge.use(BackendSyncPlugin(...));
  NativeBridge.use(LocalStoragePlugin(...));
  runApp(MyApp()); // Same app, enhanced
}
```

### 5. State that outlives a screen

`setState` holds what one screen owns. Anything two screens share - a signed-in
user, a cart, a favourites list - cannot live there: routing away rebuilds the
screen and disposes its `State`. Put it in a store outside the tree and read it
where it is needed:

```dart
final favourites = ValueNotifier<Set<String>>({});

// The screen that writes it:
ElevatedButton(
  onPressed: () => favourites.update((ids) => {...ids, user.id}),
  child: const Text('Add favourite'),
)

// Any other screen, on any route:
ValueListenableBuilder<Set<String>>(
  valueListenable: favourites,
  builder: (context, ids, _) => Text('${ids.length} favourites'),
)
```

The app follows a store while it is on screen and lets go when it is not, so a
route left behind stops redrawing. `ChangeNotifier` is there for state with
behaviour of its own, and a hand-written `NativeUIApp` uses `watch(store)`
instead of the builder. These are Flutter's own names and signatures, so this
code compiles unchanged against Flutter - like the rest of the widget layer.

See `lib/examples/apps/routing_example_app.dart`, where a user is favourited on
their own page and counted on the home page.

---

## Web (DOM + Material CSS)

Web builds do not ship the Flutter engine. An app's state, widget tree and
event handlers live in a pure-Dart `NativeUIApp`; on web `runWebApp()` mounts
it on `WebUIRenderer`, which builds real DOM and patches it in place on every
re-render (so a focused text field keeps its caret).

```dart
// lib/examples/web/calculator_example.dart
import 'package:dart_not_native/web.dart';
import '../apps/calculator_app.dart';

void main() => runWebApp(CalculatorApp());
```

```bash
maestro/web/build_examples.sh          # dart compile js + web shell, per example
```

### Style kits

How the Material components look is a *style kit*. Two ship with the
framework, and the door is open for more:

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

### Tests

`maestro/web/run.sh generate|verify|check` runs Maestro flows for every
example in headless Chrome, once per kit, with per-kit screenshot baselines.
See [maestro/web/README.md](maestro/web/README.md).

---

## Examples Included

Eleven, under `lib/examples/apps/` - counter, calculator, todo, inbox,
sign-up form, text input, routing, storage, i18n, the design system and the
components showcase. [EXAMPLES_DIRECTORY.md](EXAMPLES_DIRECTORY.md) walks
through each. Three quick ones:

### 1. Todo App (Pure Flutter)
```bash
flutter run lib/examples/todo_example.dart
```
Add/delete todos. Works identically on Android, iOS, Web. Zero native code.

### 2. Calculator (Pure Flutter)
```bash
flutter run lib/examples/calculator_example.dart
```
Simple calculator. Works everywhere.

### 3. Counter with FFI (Optional Native)
```bash
flutter run lib/main.dart
```
Demonstrates optional native code. Shows both Platform Channels and FFI.

---

## Philosophy

1. **Start simple** - Pure Flutter for most apps
2. **Add complexity gradually** - Plugins for persistence/sync, native for performance
3. **Same code everywhere** - Android, iOS, Web identical
4. **No lock-in** - Mix with your own code anytime

**Build fast. Optimize later.**

---

## Documentation

| Document | Purpose |
|----------|---------|
| **[INTEGRATION.md](INTEGRATION.md)** | Adding the framework to an app: web, Android, iOS |
| **[EXAMPLES_DIRECTORY.md](EXAMPLES_DIRECTORY.md)** | Every example app and how it is wired |
| **[COMPONENTS_SHOWCASE.md](COMPONENTS_SHOWCASE.md)** | The widget reference (the `widgets.dart` facade) |
| **[ROUTING_GUIDE.md](ROUTING_GUIDE.md)** | Named routes, route parameters and the history stack |
| **[TEXTINPUT_GUIDE.md](TEXTINPUT_GUIDE.md)** | Text fields, and forms with validation |
| **[TESTING.md](TESTING.md)** | The test layers and how to run them |
| **[TODO.md](TODO.md)** | What is left before this is production ready |
| **[I18N_GUIDE.md](I18N_GUIDE.md)** | Internationalization |
| **[packages/native_bridge/README.md](packages/native_bridge/README.md)** | The framework package |
| **[packages/native_bridge/API_REFERENCE.md](packages/native_bridge/API_REFERENCE.md)** | The programmatic API: entry points, theming, storage, i18n, plugins |
| **[LICENSE](LICENSE)** / **[NOTICE](NOTICE)** | Apache 2.0, and the attribution to carry with it |

---

## Development

### Run Examples
```bash
# Pure Flutter examples
flutter run lib/examples/todo_example.dart
flutter run lib/examples/calculator_example.dart

# With native code (Android/iOS only)
flutter run lib/main.dart

# Web (DOM + Material CSS)
maestro/web/build_examples.sh todo_example
python3 -m http.server 8080 --directory build/web_examples
# open http://localhost:8080/todo_example/  (?kit=materialize for the other kit)
```

### Add Dependencies
```bash
flutter pub get
```

### Build for Production
```bash
# Android
flutter build apk
flutter build appbundle

# iOS
flutter build ios

# Web
flutter build web
```

---

## Next Steps

1. **See the examples** - browse `EXAMPLES_DIRECTORY.md`, then run `lib/examples/todo_example.dart`
2. **Add it to an app** - `INTEGRATION.md`
3. **Keep state across screens** - the `ValueNotifier` section above
4. **What's left for production** - `TODO.md`

---

## FAQ

**Q: Do I need native code?**  
A: No. Pure Flutter works great. Native is optional.

**Q: Will my code work on all platforms?**  
A: Yes. Same code on Android, iOS, Web (if you don't use platform-specific APIs).

**Q: How does offline-first work?**  
A: It does not. There is no sync here and no types for one; an app that must
work offline keeps its own state through `StorageService` and talks to its own
backend. Sync, when it exists, will be its own package.

**Q: Can I use this framework with existing Flutter apps?**  
A: Yes. It's additive—use what you need.

**Q: When should I use native code?**  
A: Only for performance-critical code (ML, heavy computation, existing C libraries).

---

## Roadmap

- ✅ Cross-platform Flutter support
- ✅ Optional FFI bridge (Android/iOS)
- ✅ Web support with Material CSS
- ✅ Native UI renderers (Android Views, UIKit), proven on a device
- ✅ Storage, including secure storage on web with key rotation
- ✅ State beyond one screen - `ValueNotifier` stores, `InheritedWidget`, `Theme`
- ⏳ Offline-first sync, as a package of its own
- ⏳ Publishing to pub.dev, and CI that has actually run

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

---

## Support

- Read the docs above
- Check examples in `lib/examples/`
- See `packages/native_bridge/README.md` for framework details

---

**Build once. Run everywhere.**
