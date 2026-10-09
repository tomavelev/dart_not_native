# dart_not_native

Write a screen once, with Flutter's widget API, and let each platform draw it
with its own UI: Android Views, iOS UIViews, real DOM in the browser - or
Flutter widgets where a Flutter host is wanted.

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

`widgets.dart` is a pure-Dart layer with Flutter's names, signatures and
semantics. It builds a serialisable `WidgetNode` tree; a renderer per platform
turns the tree into views and sends events back. On Android and iOS the
Flutter engine hosts Dart and the plugins and does not paint the screen; on
web there is no Flutter engine at all.

## Status

| Renderer | State |
|---|---|
| Web (`WebUIRenderer`, dart2js) | covered by the browser test suite and markup goldens |
| Flutter (`FlutterUIRenderer`) | covered by widget tests; paints every node type |
| Android (`NativeUIRenderer.kt`) | compiles and runs: a physical phone for the original vocabulary, a Pixel 8 emulator (API 35) for three migrated production apps |
| iOS (`NativeUIRenderer.swift`) | the earlier vocabulary ran on a simulator and an iPad. **The Swift added since - twelve node types, right-to-left, the image cache, the `FlutterSlot` hole - compiles in CI and has never been run** |

Not on pub.dev. `CHANGELOG.md` has what changed and its **Known limits**; the
repository's `TODO.md` has what is open, with the evidence behind each status.

## Installation

```yaml
dependencies:
  dart_not_native:
    git:
      url: https://github.com/tomavelev/dart_not_native.git
      path: packages/native_bridge
```

or by path, with the repository checked out beside your app:

```yaml
dependencies:
  dart_not_native:
    path: ../dart_not_native/packages/native_bridge
```

`dart_not_native: ^0.1.0` is not on pub.dev, so those two are the ones that
work.

On Android and iOS, three things beyond the dependency:

- `MainActivity` extends `FlutterFragmentActivity` - the system back gesture
  hangs off an `OnBackPressedDispatcher`, which the plain `FlutterActivity`
  does not own.
- **`--no-tree-shake-icons` on every `flutter run` and `flutter build`.** An
  icon crosses to the renderer as a codepoint and its `IconData` is made at
  run time; Flutter's release build strips the icon font to the constants it
  can see, finds non-constant ones, and fails.
- `uses-material-design: true` in the pubspec, which bundles the icon font the
  native renderers draw from.

The repository's `INTEGRATION.md` is the full guide, including the migration
path for an existing Flutter app.

## Libraries

| Import | For |
|---|---|
| `package:dart_not_native/widgets.dart` | screens and `main()`: the widget layer, `runApp`, `hostApp`. Pure Dart |
| `package:dart_not_native/router.dart` | go_router's API - `GoRouter`, `GoRoute`, `ShellRoute`, `context.go` - over this widget layer. Pure Dart |
| `package:dart_not_native/web.dart` | the web entry: `runWebApp`, style kits, browser history, web storage |
| `package:dart_not_native/core.dart` | the protocol: `NativeUIApp`, `UIBuilder`, `WidgetNode`, `InMemoryRenderer`, `I18n`, storage interfaces |
| `package:dart_not_native/run_app.dart` | `runNativeApp`, for a hand-written `NativeUIApp` |
| `package:dart_not_native/material.dart` | a Flutter app hosting a tree: `NativeUIAppHost`, `FlutterUIRenderer`. Imports Flutter |
| `package:dart_not_native/flutter_slot.dart` | hosting a real Flutter widget in a natively drawn screen. Imports Flutter |
| `package:dart_not_native/native_bridge_flutter.dart` | the FFI bridge (below) |

`API_REFERENCE.md` covers the entry points, theming, the node vocabulary and
the widget layer by family.

## The widget layer

Most of what a Material app uses, under Flutter's names:

- **Model** - `StatelessWidget`, `StatefulWidget`, `State`, `Key`s,
  `InheritedWidget`, `ValueNotifier`/`ChangeNotifier` and their builders,
  `FutureBuilder`, `StreamBuilder`.
- **Layout and paint** - `Column`, `Row`, `Wrap`, `Stack`, `Positioned`,
  `Container`, `Padding`, `Align`, `SizedBox`, `Expanded`, `SafeArea`,
  `ClipRRect`, `Opacity`, `Transform`, `Card`, `BoxDecoration` with gradients
  and shadows.
- **Scrolling** - `ListView` (windowed with `itemExtent`), `GridView`,
  `SingleChildScrollView`, `RefreshIndicator`, `ListTile` and its checkbox,
  switch and radio forms, `ExpansionTile`.
- **Text, images, icons** - `Text`, `RichText`, `Image` (remote images
  cached, `errorBuilder`), every Material icon including the outlined, rounded
  and sharp styles.
- **Controls** - the four button families, `IconButton`, chips, `Checkbox`,
  `Radio`, `Switch`, `Slider`, `TextField`, Flutter's `Form` and
  `TextFormField`, `DropdownButton`, `showDatePicker`, `showTimePicker`.
- **Chrome and navigation** - `MaterialApp`, `Scaffold`, `AppBar`,
  `NavigationBar`, `BottomNavigationBar`, `NavigationRail`, `TabBar`,
  `Navigator.push`, named routes, `showDialog`, `showModalBottomSheet`,
  snackbars.
- **Touch** - `GestureDetector`, `InkWell`, `Draggable`/`DragTarget`,
  `Dismissible`, `KeyboardListener`.
- **Drawing and motion** - `CustomPaint` with Flutter's `Canvas`, `Paint` and
  `Path`; `AnimatedContainer`, `AnimatedOpacity`, `AnimatedScale`,
  `AnimatedRotation`, `AnimatedSlide`; `Ticker`.
- **Environment** - `ThemeData`/`ColorScheme`/`TextTheme`, `MediaQuery`,
  `LayoutBuilder`, `Directionality` and the directional geometry classes,
  `Localizations.localeOf`, `WidgetsBindingObserver`.

It is a subset and says where it stops. A property the protocol has no place
for is either composed from the nodes there are or accepted and left alone,
and the widget's doc comment says which - in the same few phrases ("accepted
and not carried", "accepted and not consulted"), so they can be searched for.
The ones that change what a user sees are gathered in `INTEGRATION.md` §8.9:
no page transitions, no `AnimationController`, `Dismissible` reveals an
action, `TextPainter` metrics are estimated, snackbars are not queued.

## Companions

- **`package:dart_not_native/router.dart`** - go_router's API. No `Page`s or
  transitions, no `StatefulShellRoute`, no navigator keys, no `onExit`;
  otherwise it behaves as go_router does unless a doc comment says so.
- **`dart_not_native_bloc`** (`packages/dart_not_native_bloc` in the
  repository) - flutter_bloc's widgets over the pure-Dart `bloc` package.
  `buildWhen` decides which state a builder is given, not whether it runs.
- **`FlutterSlot`** - a region of a natively drawn screen that the Flutter
  engine underneath paints into, for what only exists as a Flutter widget.
  Keep it out of scrollers: its rectangle follows native scrolling a frame
  late, and touches inside it go to Flutter.

## Web

```bash
dart compile js -O2 -o build/web/main.dart.js lib/main_web.dart
cp -r <this package>/web_shell/. build/web/
```

Plain dart2js, not `flutter build web`. `web_shell/` is the page, the layout
stylesheet, two Material CSS kits and self-hosted fonts - about 1 MB, nothing
from a CDN. Nothing reachable from the web entry may import Flutter or a
Flutter plugin.

## The protocol

Underneath the widget layer, and usable directly:

```dart
import 'package:dart_not_native/run_app.dart';

void main() => runNativeApp(CounterApp());

class CounterApp extends NativeUIApp {
  int count = 0;

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Counter'),
    body: UIBuilder.center(child: UIBuilder.text('$count', id: 'count')),
    floatingActionButton: UIBuilder.floatingActionButton(
      tooltip: 'Increment',
      onPressed: () => setState(() => count++),
    ),
  );
}
```

`example/` is this app. The tree is 59 node types; a test reads the dispatch
out of all four renderers' sources and fails if one stops handling a type.

## The FFI bridge

Older than the renderers, separate from them and optional: call into C by
method name, with the same Dart on every target.

```dart
import 'package:dart_not_native/native_bridge_flutter.dart';

void main() {
  NativeBridge.initialize('libbridge.so');
  // ...
}

final int result = NativeBridge.callMethod('increment_counter');
```

| Platform | What `initialize` does | Where a call goes |
|---|---|---|
| Android | `DynamicLibrary.open(libraryName)` | the library's `call_native(methodName, args)` |
| iOS | `DynamicLibrary.process()` - the symbols are looked up in the app binary, and the name is not used | the same `call_native` |
| Web | nothing | in-memory Dart functions in `platforms/web_bridge.dart` |

The C side is one dispatcher:

```c
int32_t call_native(const char* method_name, const char* args) {
  if (strcmp(method_name, "increment_counter") == 0) return increment_counter();
  if (strcmp(method_name, "get_counter") == 0) return get_counter();
  return -1; // unknown method
}
```

`NativeStatefulWidget` (a Flutter widget, from `native_stateful_widget.dart`)
binds a label, an action button and a reset button to three such methods:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `nativeMethodName` | String | required | Method to call on action |
| `label` | String | required | Display label |
| `initialMethodName` | String | `'get_value'` | Method to load initial value |
| `resetMethodName` | String | `'reset_value'` | Method to call on reset |
| `onValueChanged` | `ValueChanged<int>?` | null | Callback on value change |
| `actionButtonLabel` | String | `'Invoke'` | Action button text |
| `resetButtonLabel` | String | `'Reset'` | Reset button text |
| `showResetButton` | bool | true | Show/hide reset button |

Limits: the return type is `int32`, arguments are one string the C side
parses, and the web half only knows the methods written into
`web_bridge.dart`, with state that lives in memory and is lost on reload.

## Not here: offline-first sync

This package has no sync, and no types for one. It carried a sketch of them
once - a queue of pending operations, a retry policy, a sync status, a
conflict outcome - behind which every method threw `UnimplementedError`. They
were removed rather than published, because exported types are a compatibility
promise and these were a guess made before any backend had argued with them.

An app that has to work offline today keeps its own state with
`StorageService` (or `SecureStorageService`) and talks to its own backend. The
plugin system is how a sync would be dropped in later without the app
changing, and it belongs in a package of its own.

## License

Copyright 2026 Toma Velev.

Licensed under the [Apache License, Version 2.0](LICENSE). Commercial and
closed-source use is allowed; redistribution carries the [NOTICE](NOTICE)
file, which also lists the vendored fonts and CSS frameworks in `web_shell/`
and their own licences.
