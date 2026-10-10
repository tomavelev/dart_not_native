# Adding dart_not_native to an app

This framework is not a widget library that paints. A screen is written
**once**, as a serialisable widget tree, and a per-platform renderer turns that
tree into real platform UI: DOM + CSS in the browser, Android Views, iOS
UIViews. Flutter is optional - on mobile it is reduced to a host for the Dart
VM and the plugins, and on web it is absent entirely.

There are two ways to write that tree, and they produce the same thing:

- **The widget layer** (`package:dart_not_native/widgets.dart`): Flutter's
  names, signatures and semantics - `StatelessWidget`, `setState`, `Scaffold`,
  `Navigator.push`, `Form`, `CustomPaint`, `ThemeData` - with nothing imported
  from Flutter. This is what an app is written in, and what an existing
  Flutter app migrates to (§8).
- **The protocol** (`package:dart_not_native/core.dart`): `NativeUIApp`,
  `UIBuilder` and `WidgetNode`, the tree itself. The widget layer is built on
  it; reach for it directly when writing a renderer, a test helper, or a node
  the widget layer has no widget for.

So integration is mostly about **which renderer you mount on**, and what each
platform needs before it can render.

**Status, before anything else.** Web and the Flutter renderer are covered by
the test suites. Android's native renderer has been run on a phone and on an
emulator, including three migrated production apps. **The iOS renderer as it
now stands has drawn the examples on a simulator and nothing else**: the Swift
for everything added since the earlier iOS runs - twelve node types,
right-to-left, the image cache, the `FlutterSlot` hole, the event build
number - was written on a machine with no Xcode, compiles in CI, and passed
the device check on a simulator on 2026-10-09. §6 has the detail. If iOS is
your first target, expect to be the first person who looks at a real screen
on it.

---

## 1. Pick your path

| You want | How | Flutter engine? | Section |
|---|---|---|---|
| A new app, written like a Flutter app | `runApp` from `widgets.dart` | host only on mobile, none on web | §3 |
| An existing Flutter app, moved onto native views | swap the imports, then work through the list | host only | §8 |
| A web app, no canvas, real DOM | `dart compile js` on a web entry | no | §4 |
| The tree painted by Flutter widgets instead of platform views | `runApp(..., nativeViews: false)` | yes | §5 |
| One framework screen inside an existing Flutter app | `NativeUIAppHost` | yes | §7 |

**No native code is required for any of this.** The plugin ships the Kotlin
and Swift halves. The FFI bridge (`NativeBridge.initialize('libbridge.so')`)
is a separate, older, optional feature for calling into C - ignore it unless
you want it.

---

## 2. Add the dependency

The package is not on pub.dev, so depend on it by path or by git:

```yaml
# pubspec.yaml
dependencies:
  dart_not_native:
    path: ../dart_not_native/packages/native_bridge
```

```yaml
dependencies:
  dart_not_native:
    git:
      url: https://github.com/tomavelev/dart_not_native.git
      path: packages/native_bridge
```

The three migrated apps all use the path form, with the framework checked out
beside them. Until a version is published there is nothing to pin but a commit
(`ref:` on the git form), and the widget layer is still moving - see
`packages/native_bridge/CHANGELOG.md` for what "breaking" has meant so far.

An app that used `flutter_bloc` adds the companion package the same way:

```yaml
  dart_not_native_bloc:
    path: ../dart_not_native/packages/dart_not_native_bloc
```

```bash
flutter pub get
```

One library per job:

| Import | Use it in | Contains |
|---|---|---|
| `package:dart_not_native/widgets.dart` | your screens, and `main()` | the Flutter-shaped widget layer, `runApp`, `hostApp`, `Icons`, `ThemeData`, `ValueNotifier`. Pure Dart |
| `package:dart_not_native/router.dart` | an app that routes with go_router's API | `GoRouter`, `GoRoute`, `ShellRoute`, `context.go`. Pure Dart |
| `package:dart_not_native_bloc/dart_not_native_bloc.dart` | an app that used `flutter_bloc` | `BlocProvider`, `BlocBuilder`, `BlocListener`, `context.read`; re-exports `package:bloc`. Pure Dart |
| `package:dart_not_native/web.dart` | the web entry point only | `runWebApp`, `WebUIRenderer`, style kits, `LocalStorageService`, `WebSecureStorage`, `BrowserHistoryAdapter`, `bindBrowserBack` |
| `package:dart_not_native/flutter_slot.dart` | Flutter-side code that hosts a slot by hand | `flutterSlotNode`, `FlutterSlotLayer`. **Imports Flutter** |
| `package:dart_not_native/core.dart` | renderer-level code and tests | `NativeUIApp`, `UIBuilder`, `WidgetNode`, `InMemoryRenderer`, the design system, `I18n`, storage interfaces, `SystemBack` |
| `package:dart_not_native/run_app.dart` | `main()` of a hand-written `NativeUIApp` | `runNativeApp`, and everything in `core.dart` |
| `package:dart_not_native/material.dart` | a Flutter app hosting a tree | everything in `core.dart` plus Flutter's Material, `NativeUIAppHost`, `FlutterUIRenderer`. **Imports Flutter** |

Screens import **`widgets.dart`** (and `router.dart` / the bloc package where
they use them). That is what keeps one screen runnable on every target: none
of the three imports Flutter, so the same file compiles for a Flutter host and
with plain `dart compile js`.

`widgets.dart` and `package:flutter/material.dart` define the same names, so a
file imports one or the other, never both unprefixed - §8.3 covers the cases
where a screen still needs something of Flutter's.

---

## 3. Write the screen once

```dart
// lib/main.dart
import 'package:dart_not_native/widgets.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterState();
}

class _CounterState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Counter')),
        body: Center(
          child: Text('$_count', key: const ValueKey('count')),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Increment',
          onPressed: () => setState(() => _count++),
          child: const Icon(Icons.add),
        ),
      );
}
```

This is a Flutter counter with one line changed. `runApp` mounts it and draws
it with the platform's own views - Android Views, UIViews, the DOM.

Rules of the road:

- **A `ValueKey` becomes the node's `id`.** That is what a test, a Maestro
  flow and the web renderer's DOM `id` find a node by, and what lets a renderer
  move a row instead of rebuilding it (§10).
- **A `Scaffold`'s body does not scroll**, as in Flutter. A screen taller than
  the window goes in a `SingleChildScrollView` or a `ListView`.
- **A theme goes to two places** - `runApp(appTheme:)` for the chrome the
  platform draws and `MaterialApp(theme:)` for the widgets you compose. §8.2.
- **Each widget's doc comment says what it does not do.** The node vocabulary
  is a subset of Flutter's, so a property with no place in it is either
  composed from the nodes there are, or accepted and left alone. The comments
  use the same few phrases - "accepted and not carried", "accepted and not
  consulted" - so they can be searched for. §8.9 gathers the ones that change
  what a user sees.
- Anything platform-specific (storage, HTTP, camera…) is the pub.dev package
  for it, used directly on mobile; on web, where no Flutter plugin compiles,
  it sits behind a conditional import (§8.7). The framework does not wrap
  device services - see "Device services" in `TODO.md`.

### The protocol underneath

The same screen written against the tree itself:

```dart
import 'package:dart_not_native/core.dart';

class CounterApp extends NativeUIApp {
  int count = 0;

  @override
  WidgetNode build() => UIBuilder.scaffold(
        appBar: UIBuilder.appBar(title: 'Counter'),
        body: UIBuilder.center(
          child: UIBuilder.text('$count', fontSize: 34, id: 'count'),
        ),
        floatingActionButton: UIBuilder.floatingActionButton(
          tooltip: 'Increment',
          id: 'increment',
          onPressed: () => setState(() => count++),
        ),
      );
}
```

`runNativeApp(CounterApp())` from `run_app.dart` runs it. Hand interactive
nodes a callback - `onPressed`, `onChanged`, `onSubmitted` - and the builder
allocates an event id and registers it. The string form is still there: pass
`eventId: 'increment'` and register the handler in `init()` with
`on('increment', …)`, which is what an event nothing in the tree fires needs.

Test either without any platform at all:

```dart
final renderer = InMemoryRenderer();
final app = CounterApp()..mount(renderer);
// A callback's event id is allocated by the builder; read it off the node.
final fab = renderer.tree!.children!.last;
await renderer.handleEvent(fab.props['eventId'] as String, {});
// renderer.tree now holds the new frame
```

§8.8 has the same thing for a widget-layer app.

---

## 4. Web

The web target compiles with plain **dart2js** - no Flutter engine, no canvas.
The output is a `main.dart.js` plus a small static shell.

### 4.1 A web entry point

`runApp` is the same call on web: a conditional export picks the DOM renderer
there. So a web entry can be the mobile `main()` unchanged, provided nothing
reachable from it imports Flutter (§8.7):

```dart
// lib/main_web.dart
import 'package:dart_not_native/widgets.dart';

import 'app.dart';

void main() => runApp(const MyApp());
```

`runWebApp` from `web.dart` is the same thing with the web-only options
spelled out (`kit:`, `rootId:`, `theme:`). It takes a `NativeUIApp`, so wrap a
widget with `hostApp`:

```dart
import 'package:dart_not_native/web.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;

void main() => runWebApp(hostApp(const MyApp()), kit: const MaterializeKit());
```

Either way the style kit's stylesheets and the fonts are loaded *before* the
first paint, and the app is mounted into the element with id `app` (falling
back to `<body>`).

### 4.2 Build it

```bash
dart compile js -O2 -o build/web/main.dart.js lib/main_web.dart
cp -r <path-to-package>/web_shell/. build/web/
rm -f build/web/main.dart.js.deps
```

Not `flutter build web` - that builds a Flutter web app, in which Flutter's
canvas paints the tree and there is no DOM to speak of (§8.7 says when that
is the build to want).
Compile-time configuration is `-D`, as with `--dart-define`:
`dart compile js -O2 -DAPI_BASE=/api -Ddart.vm.product=true ...`
(`dart.vm.product` is what makes `kReleaseMode` true in a dart2js build).

`web_shell/` ships everything the page needs and nothing it does not, about
1 MB in all:

```
index.html                     <div id="app"> + <script defer src="main.dart.js">
dnn.css                        layout primitives (column, row, box, stack, text…)
kits/mdl.css, kits/materialize.css
vendor/mdl/, vendor/materialize/          the CSS frameworks
vendor/roboto/                            self-hosted Roboto, no CDN
vendor/material-icons/                    Flutter's own MaterialIcons font, as WOFF2
```

Use your own `index.html` if you prefer - it needs only `<div id="app">` and
the script tag; `runWebApp` adds the stylesheets itself. Copy your own `web/`
over the shell after it, and copy by hand any asset the app loads by path:
there is no asset bundle on web.

`maestro/web/build_examples.sh` in this repository is that build, scripted.

### 4.3 Style kits

```dart
await runWebApp(hostApp(const MyApp()));                        // Material Design Lite
await runWebApp(hostApp(const MyApp()), kit: const MaterializeKit());
await runWebApp(hostApp(const MyApp()), kit: const PlainKit());  // dnn.css only
```

Any kit can also be selected at run time with `?kit=mdl|materialize|plain`,
and `?animations=off` freezes spinners for screenshot tests. To use your own
CSS framework, subclass `WebStyleKit` and override only the components it
styles - the renderer keeps the layout, ids, events and reconciliation.

### 4.4 Browser Back, the URL and deep links

What puts the app in the browser's history depends on how it routes:

**`GoRouter` (`router.dart`)** - hand it the browser's history:

```dart
// lib/main_web.dart
import 'package:dart_not_native/web.dart'
    show BrowserHistoryAdapter, bindBrowserBack;

import 'app.dart';

Future<void> main() async {
  final history = BrowserHistoryAdapter();
  await start(
    history: history,
    initialLocation: history.currentPath ?? '/', // a reload, a deep link
  );
  bindBrowserBack();
}
```

where `start` builds the router and calls
`router.attachHistory(history)` before `runApp` - `router.dart` itself cannot
import the browser and still compile for a Flutter host, which is why the
adapter is handed in. Every `go` and `push` then becomes a history entry
written to the URL fragment (`#/guests/7`), which survives a reload with no
server-side routing, and Back returns to the one before it.

**A hand-written `NavigationApp`** - `runNativeApp` binds it for an app that
mixes in `NavigationHost`; by hand it is
`app.nav.bindSystemBack(adapter: BrowserHistoryAdapter())` and
`bindBrowserBack()`.

**`MaterialApp(routes:)` and `Navigator.push`** - nothing to wire. A named
route is a history entry and a fragment in the URL, Back pops it, and a link
straight to it opens it over the first route. A page pushed with
`Navigator.push`, a dialog and a sheet leave the URL alone, and Back closes
them. Forward does not bring back what Back closed; `runApp(app,
systemBack: false)` keeps the app out of the history. `ROUTING_GUIDE.md` has the detail.

### 4.5 Storage on web

```dart
final storage = LocalStorageService(prefix: 'myapp.');
```

It implements the `StorageService` interface, so a screen that takes one does
not change between web and mobile.

For secrets, `WebSecureStorage` encrypts with the browser's own AES-GCM before
anything reaches localStorage, under a 256-bit key the browser generates and
keeps in IndexedDB as a non-extractable `CryptoKey` - script can ask it to
encrypt and decrypt, but cannot read the key out:

```dart
final secrets = WebSecureStorage();
if (await secrets.isEncryptionAvailable()) {
  await secrets.setString('token', token);
}
```

Two things to know. It needs a **secure context** - `crypto.subtle` does not
exist on plain `http://` except on localhost - and writes there throw rather
than quietly storing plaintext. And it protects the data, not the page: an
attacker with a copied localStorage dump learns nothing, but script running on
your origin can ask the browser to decrypt exactly as your code does. Keep
tokens short-lived.

On Android and iOS the framework ships no implementation of either interface;
use `shared_preferences` and `flutter_secure_storage` directly, or wrap them in
a few lines.

---

## 5. Android and iOS - what the host needs

`runApp` from `widgets.dart` draws with the platform's own views by default
(`nativeViews: true`), and falls back to painting the same tree with Flutter
widgets if the native renderer is unavailable - on a desktop host, say -
rather than showing an empty screen. `runApp(..., nativeViews: false)` asks
for the Flutter renderer outright. (`runNativeApp`, the entry for a
hand-written `NativeUIApp`, has the opposite default: Flutter widgets unless
`nativeViews: true`.)

The Flutter engine is still there under the native views: it runs Dart, hosts
every plugin, repaints on hot reload, and paints whatever a `FlutterSlot`
holds (§8.6).

Nothing changes in Gradle, Xcode or the Podfile. Three things do need doing.

### 5.1 `MainActivity` extends `FlutterFragmentActivity`

The Android back button and the iOS swipe from the left edge reach Dart
through one channel, and `runApp` wires it: back closes the topmost dialog or
sheet, then pops a page, and only leaves the app when there is nothing left
to pop.

On Android the gesture hangs off an `OnBackPressedDispatcher`, which the plain
`FlutterActivity` does not own. Make your activity the androidx host:

```kotlin
class MainActivity : FlutterFragmentActivity()
```

or point the manifest straight at it:

```xml
<activity android:name="io.flutter.embedding.android.FlutterFragmentActivity" ... >
```

With any other host the plugin still renders; back simply keeps its default
behaviour and closes the app. Plugins that need the activity get it through
the same `ActivityAware` binding as before - the migrated apps use
`google_mobile_ads`, `google_sign_in`, `flutter_local_notifications` and
`flutter_secure_storage` under it. On iOS there is nothing to do.

For anything else that should swallow Back, register directly (`SystemBack`
is in `core.dart`; there is no `PopScope`):

```dart
SystemBack.addHandler(() {
  if (!searchIsOpen) return false;   // not mine
  closeSearch();
  return true;                       // consumed
});
```

Handlers run most-recently-registered first.

### 5.2 `--no-tree-shake-icons`, on every build

```bash
flutter run --no-tree-shake-icons
flutter build apk --release --no-tree-shake-icons
flutter build appbundle --no-tree-shake-icons
flutter build ios --no-tree-shake-icons
```

Flutter's release build strips the Material Icons font down to the `IconData`
constants it can see in the compiled program. Here an icon crosses to the
renderer as a codepoint and the `IconData` is made at run time, so there are
no constants to see - and a release build **fails**, by Flutter's own check,
rather than shipping an app with missing glyphs. The flag keeps the whole
font. Put it in the CI job as well as the README; all three migrated apps
have it in both.

The pubspec still needs `uses-material-design: true`, which is what bundles
the font the native renderers draw from.

### 5.3 `android:supportsRtl="true"`, for an app with a right-to-left language

```xml
<application android:supportsRtl="true" ...>
```

A view only resolves to right-to-left in an app that declares this, and a
Flutter app's manifest does not unless somebody added it. The Android renderer
raises the flag itself when a tree asks for right to left, so a screen turns
without it - but that is the renderer patching `applicationInfo` at run time
on your behalf, and the manifest is where the platform expects to be told.
Declare it.

### 5.4 Hosting it yourself

Skip `runApp` and place a `NativeUIAppHost` (§7) when the app should be a tab,
a route or a panel of a Flutter app rather than the whole of it. Then the back
gesture is two lines of your own:

```dart
SystemBackChannel.bind();   // once, at startup
```

plus `app.nav.bindSystemBack()` for a `NavigationHost` app.

---

## 6. The native renderers - what has run where

The native halves ship with the package. `DartNotNativePlugin` constructs the
renderer as soon as the engine attaches to an activity (Android) or the root
view controller exists (iOS), and registers its channels; both speak the same
channel (`com.programtom.dart_not_native/renderer`) and send their events back
on it. Mounting one by hand works too:

```dart
import 'package:dart_not_native/platforms/android_renderer.dart';
// or  '.../ios_renderer.dart';

app.mount(AndroidNativeRenderer());
```

Both dispatch the whole node vocabulary - 59 types. A test reads the dispatch
out of each source file and compares it against the protocol's own list, so a
type going missing fails the build rather than showing a placeholder on a
device. That test reads source; it does not compile anything.

**Android.** The Kotlin compiles, ships in the APK and runs. On a physical
phone: every example app, 15 integration tests and five Maestro flows, before
this body of work. Since then, three migrated Flutter apps were walked screen
by screen on a Pixel 8 emulator (API 35), which put the new node types -
boxes, stacks, scrollers, canvas, dropdowns, pickers, bottom navigation - in
front of real screens, and is where the bugs listed under "Three real apps on
an Android emulator" in the changelog - about thirty, none of which showed
anywhere but on a device - were found and fixed.

What was seen working there (Android 15, debug builds, 2026-10-03): a games
app's home grid and eighteen games, each opened and played a few moves,
including a timer-driven canvas; a reminders app's first-run permission flow,
four bottom-navigation tabs, add, delete and undo, a dashboard with a canvas
donut chart and a composed month calendar, a language switch and dark mode; a
planner's forms with validation, dropdowns, swipe-to-delete, checkbox tiles,
dialogs, bottom navigation and the navigation rail in landscape. Under an
Arabic locale the app bar, the bottom navigation's order, list tiles, tabs,
the calendar and a switch all mirrored. A long-press drag of a row onto a
target delivered its data. A scheduled local notification was posted by an
app running on the renderer, so plugins work under `FlutterFragmentActivity`.
Remote images loaded in list rows. An AdMob test banner showed through a
`FlutterSlot` (§8.6).

What was not: that pass was an emulator, by hand - the new nodes have not been
on a physical phone, and the Maestro flows and the integration lane predate
them. No app opened a date or time picker, so those two nodes and the Material
pickers behind them are unverified on a device; so are `dnn:key` hardware
keys, how pull-to-refresh feels under a finger, what the image disk cache
does offline or at expiry, and the `disabled` drawing of checkable controls.

**iOS.** The renderer that ran - five Maestro flows on a simulator, the app on
a physical iPad, six example apps looked at by hand - is the one from before
this work. **Everything added since is Swift that has been written and never
compiled**: the twelve new node types, the extended props on the old ones,
right-to-left, the decoded-image cache, the `FlutterSlot` hole and its
rectangle reports, scroll reporting, and sending the build number back with
each event (the fix for a callback id landing on the wrong row - running on
Android, text on iOS). It may not build as it stands. The
first job on a Mac is `flutter build ios --simulator --no-tree-shake-icons`,
then `tool/device_check.sh ios`; `TODO.md` §6.1 lists where to look first.

If you would rather have the tree painted by Flutter - the renderer with the
most test coverage, and the one that needs no native code at all - that is
`nativeViews: false`.

### Signing, and where your own identifiers live

Nothing that identifies *you* is in the repository. A build for a physical iOS
device needs an Apple Developer team, and that is per developer, so it lives in
a file git ignores:

```bash
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
# then put your team id in it
```

`Debug.xcconfig` and `Release.xcconfig` pull it in with `#include?`, which
means "if it is there" - so a simulator build, which needs no team, works from
a fresh clone with no setup at all.

Devices are named on the command line rather than written down anywhere:

```bash
flutter test integration_test -d <serial-or-udid>
maestro/native/run.sh android --device <serial>
maestro test --udid <udid> --apple-team-id <team>   # a real iOS device
```

---

## 7. Adding one screen to an existing Flutter app

You do not have to convert an app to adopt the framework. `NativeUIAppHost` is
a Flutter widget that paints a tree with `FlutterUIRenderer`, so one screen
can come from the framework while the rest of the app carries on as before:

```dart
import 'package:dart_not_native/material.dart';        // Flutter + NativeUIAppHost
import 'package:dart_not_native/widgets.dart' as dnn;  // the screen's own layer

Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => NativeUIAppHost(app: dnn.hostApp(const SettingsScreen())),
  ),
);
```

`SettingsScreen` is a `widgets.dart` widget, in a file of its own that imports
only `widgets.dart`; `hostApp` wraps it as the `NativeUIApp` the host mounts.
That screen is now the same object a web build runs: same layout, same event
handlers, same tests.

A tree rooted in a Scaffold brings its own; any other root is wrapped in a
`Material`, so a fragment - a settings panel, a form - can be dropped inside a
screen you already have.

This is the cheapest way in: share a screen now, decide about native rendering
later. It is Flutter painting, so none of §5 or §6 applies.

---

## 8. Migrating an existing Flutter app

Three production apps have been moved this way - a reminders app in twelve
locales, Arabic among them, with local notifications; a collection of
eighteen small games with an ad banner; and a planner with go_router,
flutter_bloc and a web build. What follows is the order that worked, and what
each step turned up. Two more have since been moved - a food-reference app in
eighty locales with a drawer, named routes, a barcode scanner and a Flutter
web build, walked through on the same emulator, and a small terminal client
seen only at its sign-in form - and what they needed is in the layer now.

The promise is narrower than "change the import and ship". It is: a screen
compiles after its import changes, behaves as Flutter's would unless a doc
comment says otherwise, and the places where it *looks* different are known
(§8.9). Things that are not there at all fail at compile time, which is the
useful way to fail.

### 8.1 Swap the imports

In every file that builds UI:

```dart
// before
import 'package:flutter/material.dart';
// after
import 'package:dart_not_native/widgets.dart';
```

Then read the analyzer's list. What it reports falls into three kinds:

- **A widget this layer does not have.** `PageView`,
  `AnimationController` and `Tween`, `CustomScrollView` and slivers,
  `DataTable`, `Stepper`, `ReorderableListView`, `InteractiveViewer`,
  `PopScope` are the common ones. Each needs a decision:
  restructure with what there is (§8.5), or keep the real Flutter widget in a
  `FlutterSlot` (§8.6).
- **A non-widget Flutter API** - `Clipboard`, `HapticFeedback`, `rootBundle`.
  Still available; §8.3.
- **A third-party widget package.** §8.5.

A name of your own that collides with the layer's - an `AppTheme` class is the
likely one, since the protocol's palette is called that - is hidden at the
import: `import 'package:dart_not_native/widgets.dart' hide AppTheme;`.

### 8.2 The theme goes to two places

```dart
final light = ThemeData(colorSchemeSeed: Colors.teal);
final dark = ThemeData(
  colorSchemeSeed: Colors.teal,
  brightness: Brightness.dark,
);

Future<void> main() => runApp(
  MaterialApp(
    theme: light,
    darkTheme: dark,
    themeMode: ThemeMode.system,
    home: const Home(),
  ),
  title: 'My app',
  appTheme: light.toAppTheme(dark: dark, mode: ThemeMode.system),
);
```

Two audiences. Your widgets read `Theme.of(context)`, which is a `ThemeData`
exactly as in Flutter - `colorScheme`, `textTheme`, `extension<T>()`. The
renderers, which colour the app bar, the platform's buttons, dialogs and the
scaffold, read the protocol's small `AppTheme` palette, and they need it at
start-up, before any widget has been built. A `MaterialApp(theme:)` further
down cannot reach back to that moment, so the app says it twice;
`toAppTheme` derives the palette from the `ThemeData` so the colours are
declared once. Forget the `appTheme:` and the platform's controls are the
default blue over your teal widgets. The widget layer's `AppBar` is the one
exception: it resolves its colours as Flutter does - its own, then
`AppBarTheme`'s, then surface and onSurface under Material 3 or the primary
under a light Material 2 theme - and always sends them. A hand-written
`UIBuilder.appBar` with no colour keeps the renderer's default.

`title:` belongs on `runApp` for the same reason - the platform host wants it
before the first build - and `MaterialApp.title` is accepted and not used.

`ColorScheme.fromSeed` approximates Material's tonal palettes (right
lightness, saturation within a few percent). Pin an exact brand colour by
passing the role: `ColorScheme.fromSeed(seedColor: brand, primary: brand)`.

`Theme.of(context).appTheme` is the palette, for the rare screen that wants
the renderers' own colours.

### 8.3 Keep the Flutter APIs that are not widgets

On mobile the Flutter engine is running, so everything of Flutter's that is
not a widget still works. Import it narrowly, so its names do not collide with
the layer's:

```dart
import 'package:dart_not_native/widgets.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
```

`package:flutter/foundation.dart` (`compute`, `listEquals`) and
`package:flutter/services.dart` (`rootBundle`, `SystemChrome`) are the usual
two. Where a Flutter *widget* type has to be named - a `FlutterSlot`'s builder
- prefix it: `import 'package:flutter/widgets.dart' as flutter;`.

`WidgetsFlutterBinding.ensureInitialized()` exists in `widgets.dart` and, on a
Flutter host, starts Flutter's real binding - so a `main()` that initialises
plugins before `runApp` keeps working as written.

Every such import makes the file mobile-only. That is fine for an app with no
web target and the thing to isolate for one that has (§8.7).

### 8.4 Plugins, localisation, routing, state

**Plugins keep working on mobile**, unchanged: they talk to the engine, not to
the widget tree. The migrated apps kept notifications, sign-in, secure
storage, shared preferences, the ad SDK and the timezone database as they
were. The exception is
a plugin whose product *is a widget* - a map, a camera preview, an ad banner,
a web view. The framework has nodes of its own for three of those
(`WebView`, `MapView`, `CameraPreview`; see their doc comments for which
platforms draw them), and the rest go in a `FlutterSlot`.

**A delegate of your own keeps working.** `LocalizationsDelegate` and
`Localizations.of<T>(context, T)` are in `widgets.dart`, and
`MaterialApp(localizationsDelegates:)` loads the delegates that are this
library's for the app's locale, and again when it changes. So the classic
`intl` arrangement - an `AppLocalizations` class with a static `load`, a
delegate that calls it and an `of(context)` that looks it up - moves over by
changing the import of the file it is in. Two things to do by hand:

- `of` answers null until the load has completed. Flutter holds the first
  frame back for it; here the app is drawn at once. Fall back
  (`?? AppLocalizations()`), and if the fallback would show placeholders,
  `await` the default language's load in `main()` before `runApp`.
- Take Flutter's delegates out of the list or leave them - they are passed
  over either way. `GlobalMaterialLocalizations` localises Flutter's widgets,
  and there are none.

**gen-l10n** stays the source of truth: ARB files, `flutter gen-l10n`, the
generated `AppLocalizations` classes. What goes is the lookup: the generated
`AppLocalizations.of(context)` and delegate are written against Flutter's
`BuildContext` and `Localizations`, in a file gen-l10n owns, so their import
cannot be changed by hand. The generated classes are plain objects, though,
and gen-l10n emits a top-level `lookupAppLocalizations(Locale)`; a ten-line
bridge reads the locale the framework's `MaterialApp` is showing and looks
the strings up directly:

```dart
// lib/l10n/l10n.dart - hand-written; gen-l10n leaves it alone
import 'dart:ui' as ui;

import 'package:dart_not_native/widgets.dart';

import 'app_localizations.dart';

const ui.Locale fallbackLocale = ui.Locale('en');
final Map<String, AppLocalizations> _cache = {};

/// The generated strings for [locale]; the fallback's for a language the app
/// does not ship (`lookupAppLocalizations` throws for one).
AppLocalizations lookupL10n(Locale locale) {
  final code = locale.languageCode;
  return _cache[code] ??= lookupAppLocalizations(
    AppLocalizations.supportedLocales.any((l) => l.languageCode == code)
        ? ui.Locale(code)
        : fallbackLocale,
  );
}

extension AppL10n on BuildContext {
  AppLocalizations get l10n => lookupL10n(Localizations.localeOf(this));
}
```

Screens then say `context.l10n.title` where they said
`AppLocalizations.of(context)!.title`. `MaterialApp(locale:,
supportedLocales:)` decides what `Localizations.localeOf` answers, and with no
`locale` it is the first supported locale in the device's language - and,
failing that, the device's own locale, supported or not, which is why the
bridge has a fallback. Three things to know:

- Choose the fallback. Flutter falls back to the *first* supported locale and
  gen-l10n lists them alphabetically, so an app shipping `bg` and `en` was
  showing Bulgarian to a German phone. The bridge is where that gets decided
  on purpose.
- **Right-to-left follows the locale.** `MaterialApp` lays the screen out
  right to left for ar, fa, he, ps, sd, ur, ug, yi and dv, and
  `EdgeInsetsDirectional`, `AlignmentDirectional` and `TextAlign.start`
  resolve against it. Only the screen's direction reaches the renderers: a
  `Directionality` deep in a screen turns the values and rows below it, not
  the platform's own controls there.
- The generated code imports Flutter, so this bridge is mobile-only. An app
  with a web target keeps its strings in the framework's own table instead
  (`I18n` and the `Tr` widget - `I18N_GUIDE.md`), or in plain Dart maps.

There are no Material strings to localise - no "OK" the framework draws for
you - except inside the platform's own date and time pickers, which speak the
device's language.

**go_router → `package:dart_not_native/router.dart`.** Remove the `go_router`
dependency and change the import; `GoRouter`, `GoRoute`, `ShellRoute`,
`GoRouterState`, `redirect`, `refreshListenable`, `errorBuilder`,
`context.go/push/pop/replace` and the named variants are there with
go_router's signatures, and `MaterialApp.router(routerConfig:)` takes it.
The deviations, all stated in the library's doc comment:

- no `pageBuilder`, `Page`s or transitions; no `StatefulShellRoute`; no
  navigator keys; no `onExit`;
- a path parameter matches one whole segment - inline patterns
  (`:id(\d+)`) are not supported;
- with a browser history attached, **`push` changes the URL too** (in
  go_router only `go` does by default) - Back is the only way a browser user
  has to leave a pushed page, so it has to be an entry.

**flutter_bloc → `dart_not_native_bloc`.** Replace the `flutter_bloc`
dependency with `dart_not_native_bloc` and change the import; it re-exports
`package:bloc`, so `Bloc`, `Cubit` and `Emitter` come with it. `BlocProvider`
(and `.value`), `RepositoryProvider`, the three `Multi*` forms, `BlocBuilder`,
`BlocListener`, `BlocConsumer`, `BlocSelector`, `context.read/watch/select`.
One difference underneath:

- `buildWhen` decides which state a builder is *given*, not whether its
  function runs. A change anywhere rebuilds the tree from the root (§10), so a
  builder may run again with the state it already had. Keep builders pure, as
  Flutter also asks, and it is not visible. `context.select` is `watch` with
  the selector applied, for the same reason: the same value, without the
  saving.

`provider`, `flutter_riverpod` and other packages whose widgets extend
Flutter's have no counterpart here. `ValueNotifier`/`ChangeNotifier` with
`ValueListenableBuilder`/`ListenableBuilder`, and `InheritedWidget`, are in
`widgets.dart` with Flutter's signatures.

### 8.5 Third-party widget packages: redraw them

A package that exports Flutter widgets - a chart, a calendar, a shimmer, an
SVG icon set - cannot be used: its widgets extend Flutter's `Widget`, and this
tree is not made of those. For most of them the answer is to draw it again
with what the layer has, which is less work than it sounds because the
painting API is Flutter's:

```dart
class Donut extends CustomPainter {
  const Donut(this.fraction, this.color);
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Offset.zero & size,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(Donut old) => old.fraction != fraction;
}

CustomPaint(
  size: const Size(120, 120),
  painter: Donut(0.4, Theme.of(context).colorScheme.primary),
)
```

A painter written for Flutter usually moves over as it is. The canvas records
a command list that each renderer replays into its own canvas, so what does
not survive is what a command list cannot say: shaders, mask filters, blend
modes, `clipPath`, `saveLayer` paints, and `TextPainter` measuring real glyphs
(§8.9). In the migrated apps: the reminders app's donut chart is a
`CustomPaint` and its month calendar is boxes; the games draw snake, frog and
hangman on a `CustomPaint` and build the other boards from `Container`,
`Stack`, `Positioned` and `GestureDetector`; the planner's seating screen is
`Draggable` and `DragTarget`.

### 8.6 What only exists as a Flutter widget: `FlutterSlot`

Some things cannot be redrawn - an ad SDK's banner is the canonical one. A
`FlutterSlot` reserves a rectangle in the natively drawn screen and the
Flutter engine, still running underneath, paints the real widget into it:

```dart
import 'package:dart_not_native/widgets.dart';
import 'package:flutter/widgets.dart' as flutter;

class Banner extends StatelessWidget {
  const Banner({super.key});

  // One function for the life of the app, so the slot's registration does
  // not change on every rebuild of the screen around it.
  static flutter.Widget _buildAd(flutter.BuildContext context) =>
      const flutter.Placeholder(); // AdWidget(ad: banner), in a real app

  @override
  Widget build(BuildContext context) => Scaffold(
        body: const Center(child: Text('The screen')),
        bottomNavigationBar: SafeArea(
          child: FlutterSlot(
            slotId: 'banner',
            width: 320,
            height: 50,
            builder: _buildAd,
            fallback: const SizedBox(width: 320, height: 50),
          ),
        ),
      );
}
```

`builder` is a Flutter `Widget Function(BuildContext)`; it is typed `Object`
because `widgets.dart` is pure Dart and cannot name Flutter's types. Who draws
what:

- the **Android and iOS renderers** leave a see-through, touch-through hole of
  the slot's size and report where it is; `runApp` puts a `FlutterSlotLayer`
  behind the native views, which paints the widget at that rectangle;
- the **Flutter renderer** builds the widget right where the node is;
- a renderer with no Flutter engine - **web** - draws `fallback`, which is
  also what a test on `InMemoryRenderer` finds as the node's child.

The limits, which are why it is for the exception and not the rule:

- **The size comes from the tree, not the widget.** The platform lays the hole
  out before Flutter knows it is there. `height` is required; the widget is
  given the rectangle and has to fit it.
- **The rectangle follows native scrolling a frame late.** The platform moves
  the hole, tells Dart, and Flutter repaints. In a fast scroll the widget
  trails the hole by a frame and lands once the scroll settles.
- **Touches inside the hole go to Flutter.** That makes the widget tappable,
  and it means a drag that *starts* on the slot does not scroll the native
  list around it.

So **keep a slot pinned** - in a `bottomNavigationBar`, above or below a
scroller, never inside one - and neither limit shows. Give two slots on screen
at once two `slotId`s. The worked example is the games app's AdMob banner.
On the Android emulator (a Pixel 8, Android 15) an AdMob *test* banner loaded
and was visible through the hole at exactly its 320×50dp slot; it stayed put
while the screen behind it scrolled, was covered while a pushed page was open
and came back on Back, and taps elsewhere on the screen kept working. Tapping
the ad itself was not tested. The slot was pinned, so the scroll lag above was
not exercised either. That is one emulator, not a range of devices, and the
iOS hole has only drawn its fallback, in the device lane: no Flutter widget
has shown through it there.

### 8.7 A web target

Everything above that mentions Flutter is mobile-only, so a web build is a
matter of keeping those files out of reach of the web entry. `dart compile js`
fails on the first `package:flutter/...` or plugin import it can reach - which
is the check; there is no separate lint.

The pattern is a conditional import per platform seam:

```dart
// lib/token_storage.dart
export 'token_storage_io.dart'
    if (dart.library.js_interop) 'token_storage_web.dart';
```

with `token_storage_io.dart` using `flutter_secure_storage` and
`token_storage_web.dart` using `package:web` or the framework's
`WebSecureStorage`. Both declare the same functions; the screens import the
seam. Then: a web entry point of its own (§4.1), `dart compile js` (§4.2),
`GoRouter.attachHistory` for Back and deep links (§4.4), and `kIsWeb` from
`widgets.dart` where behaviour differs.

A `FlutterSlot`'s `builder` names a Flutter type, so the widget that builds
one sits behind a seam too; on web the seam's other half returns the fallback.

**When the seams would be most of the app**, there is a second web build.
An app that reads SQLite, shares through the platform's sheet and caches in
`shared_preferences` on every other screen has no seam to cut along. For
that app `flutter build web` is the build: `runApp` sees Flutter's web
runtime (`dart:ui_web`) and paints the tree through the Flutter renderer -
canvas, not DOM - while every Flutter plugin works as it does in any Flutter
web app, and a `FlutterSlot` builds its widget where the node is. What you
give up is what the DOM build is for: real elements, the browser's own text
and controls, a megabyte instead of several. Add `--no-tree-shake-icons`, as
on mobile. One migrated app is built this way; it was opened in headless
Chrome as far as its first two screens, which is not a pass through the app.

### 8.8 Tests: `hostApp` and `InMemoryRenderer`, not `pumpWidget`

`flutter_test`'s `WidgetTester` pumps Flutter widgets, and these are not
those. The equivalent is to mount the app on a renderer that keeps the tree in
memory, fire the events a real renderer would send, and assert on the tree
that comes back:

```dart
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tapping Add counts', () async {
    final tester = AppTester.widget(const Counter());
    expect(tester.text('count'), '0');   // the Text with ValueKey('count')
    await tester.tap('add');             // the button with ValueKey('add')
    expect(tester.text('count'), '1');
  });
}
```

`AppTester` is in `package:dart_not_native/testing.dart` - about 120 lines
over `InMemoryRenderer`: find a node by id or type, `tap`, `toggle`,
`typeInto`, `submitInto`, `emit` a raw event. Extend it with the finders your
screens need. (It used to be a file to copy out of this repository, which is
what all three migrated apps did; a copy is replaced by changing the import.)
`test`/`expect` still come from `flutter_test`, and so does the test runner.

What changes in practice:

- **Give the things a test touches a `ValueKey`.** There is no `find.text`
  that taps; a node is addressed by its id.
- **No `pump`.** `await` the tap and the tree is current. A `Future` the screen is waiting on is awaited the
  ordinary way.
- **It tests the tree, not the picture.** That a node says `color: '#ff0000'`
  is asserted; that a renderer draws it red is the renderer's test. Layout
  bugs - an overflow, a collapsed column - are invisible here, and are what
  the device pass is for.
- `LayoutBuilder` and `MediaQuery` get their size from a renderer event; a
  test that depends on one sends it
  (`RendererEvents` is in `core.dart`):
  `await tester.emit(RendererEvents.viewport, {'width': 400, 'height': 800})`.

### 8.9 What looks or behaves differently from Flutter

Compiled from the widget doc comments, which are the authority and say more.
Left out: parameters that are simply accepted and not carried because the
control is the platform's own (a `Switch`'s colours, an `InputDecoration`'s
border) - there are many, each documented on the field.

| In Flutter | Here |
|---|---|
| `PopupMenuButton` drops a menu from the button | **A dialog** listing the entries, in the dialog's place. The callbacks are Flutter's; the entry for `initialValue` is ticked |
| `Hero` flies between pages; `MouseRegion` follows the pointer | Both draw their child and nothing else |
| A pushed page slides or fades in | **No page transitions.** A pushed page replaces what its navigator shows. `PageRouteBuilder.transitionsBuilder` and `go_router`'s `pageBuilder` are accepted-and-unused / absent. Pages beneath keep their `State` |
| `Dismissible`: the row slides away under the finger | The swipe **reveals an action** behind the row, in the colour and words of `background`; a full swipe or a tap on it dismisses. `onDismissed` and `confirmDismiss` are called as in Flutter. Vertical directions do nothing |
| `AnimatedSwitcher`, `AnimatedCrossFade`, `AnimatedSize` animate between children or sizes | The new child or size is simply shown. **No transition** |
| `AnimatedContainer` animates every property | Size, colour, opacity and transform move; padding, margin, alignment and border land at once. `AnimatedPadding` and `AnimatedAlign` land at once |
| `onEnd` fires when an implicit animation finishes | Accepted and never called - renderers do not report an animation finishing |
| `AnimationController`, `Tween`, `AnimatedBuilder` driven by one | No `AnimationController`. `Animation` exists for signatures and stands still. A `Ticker` is a 16 ms timer; each tick that calls `setState` is a full rebuild and a message to the platform (§10) |
| Forty-odd `Curves` | Five reach the renderers: `linear`, `ease`, `easeIn`, `easeOut`, `easeInOut`. The rest are aliases of the nearest - `bounceOut` and `elasticOut` are `easeOut` |
| `TextPainter` measures real glyphs | **Metrics are estimated**: 0.55 × font size per character (double for CJK and emoji), 1.2 × per line. The text is drawn by the platform with real glyphs, aligned within the estimated box. `didExceedMaxLines` is always false |
| `CustomPainter.shouldRepaint` gates repainting | Not consulted; `paint` runs on every build and a renderer repaints when the commands changed. Shaders, mask filters, blend modes, `clipPath` and layer paints are not carried; `Path.addRRect` adds the plain rectangle; `foregroundPainter` shares the one surface |
| `TimeOfDay.format` follows each locale's conventions | As Flutter, from Flutter's own table: the pattern and the AM/PM words of each of its locales, and `MediaQueryData.alwaysUse24HourFormat`. The digits are always 0-9, and no renderer reports the device's 24-hour switch |
| Snackbars queue | Queued, as in Flutter: a new one waits for the ones before it, and `hideCurrentSnackBar`, `removeCurrentSnackBar` and `clearSnackBars` do what they say. The bar is the platform's - message and one action; colour, shape, margin and `behavior` are not carried |
| `ScrollController.offset` follows the finger; listeners hear scrolling | Follows a step behind: the renderer reports the offset when the scroller comes to rest and at most every 100 ms on the way, not once a frame. A windowed list (`itemExtent`) reports rows, not pixels, so there `offset` is still the last place *the app* sent it. `jumpTo` works; `animateTo` arrives at once. No scroll notifications |
| `ListView.builder` measures rows and builds lazily | Windowed only with `itemExtent` or `itemExtentBuilder`; without one every row is built. `RefreshIndicator` does not attach to a windowed list |
| `TabBarView` swipes between pages; tab changes animate | No swipe, no animation; the tab strip is how a tab is chosen. Hidden tabs keep their `State` |
| `GestureDetector`: `onTapDown`, then `onTapUp`, then `onTap` | All three fire together once the tap has happened. Pan, horizontal and vertical drags are one drag. `behavior` is not carried |
| `Draggable` shows `feedback`; reports start, end, cancel | The platform lifts a picture of the child; only `onDragCompleted` is called |
| `KeyboardListener` hears keys while its node has focus | Every listener in the visible tree hears every key |
| `Image.errorBuilder` runs when loading fails; `loadingBuilder` during | `errorBuilder` is called once, up front, and its result is shown while loading and on failure. `loadingBuilder` and `frameBuilder` are never called. `color` tinting is not applied |
| `RichText` with `WidgetSpan`, tappable spans | Text runs only: a `WidgetSpan` is left out, and `TextSpan` has no `recognizer` |
| `TextOverflow.fade` | Drawn as `clip` |
| `Scaffold.drawer` slides in from the side | Shown as a sheet, opened by the menu button the app bar gains or by `Scaffold.of(context).openDrawer()`, and closed when the app moves to another page. A scaffold nested in another's body is composed from a column and a stack |
| `FloatingActionButton` takes colours, `mini`, a location | The platform's button in the theme's colours, in the platform's place |
| `NavigationRail` `leading`, `trailing`, `extended` | Accepted and not drawn |
| `Container` with a border whose sides differ, several shadows | Thin boxes over the edges; the first shadow only; no `spreadRadius` |
| `InheritedWidget.updateShouldNotify`, `didChangeDependencies` on change | As Flutter, for a `State`: `didChangeDependencies` runs again before a build in which something the state read through its own `context` has changed, and `updateShouldNotify` says whether it has. It does not prune the rebuild - everything still rebuilds from the root |
| `LayoutBuilder` runs once with real constraints | Runs against the viewport first, then again when the renderer reports the box's size |
| `showDatePicker`/`showTimePicker` take a `builder` and a `locale` | The platform's own picker, in the device's language |
| Text fields: `style`, `autocorrect`, most of `InputDecoration`'s look | The platform's own field in its theme. Label, hint, helper, error, prefix and suffix icons travel |

On iOS specifically, a text field's label sits above the field rather than
floating into it - UIKit has no floating label.

---

## 9. Checklist

**Any target**
- [ ] `dart_not_native` in `pubspec.yaml` (path or git)
- [ ] screens import `widgets.dart`, never `package:flutter/material.dart`
- [ ] `runApp(app, title:, appTheme: theme.toAppTheme(dark:, mode:))` and the
      same themes on `MaterialApp`
- [ ] a `ValueKey` on rows that move and on whatever a test touches

**Android and iOS**
- [ ] `MainActivity` extends `FlutterFragmentActivity`
- [ ] `--no-tree-shake-icons` on every `flutter run` and `flutter build`,
      including CI
- [ ] `uses-material-design: true` in the pubspec
- [ ] `android:supportsRtl="true"` if the app ships a right-to-left language
- [ ] plugin imports and `package:flutter/...` imports are narrow (`show`) or
      prefixed
- [ ] any `FlutterSlot` is pinned, not inside a scroller
- [ ] iOS: built and looked at on a Mac before anyone relies on it (§6)

**Web, additionally**
- [ ] a web entry from which no Flutter or plugin import is reachable
- [ ] `dart compile js` + `web_shell/` copied next to `main.dart.js`
- [ ] `<div id="app">` in the page
- [ ] `GoRouter.attachHistory(BrowserHistoryAdapter())` + `bindBrowserBack()`
      if Back and deep links matter

**A migrated app, additionally**
- [ ] gen-l10n bridge in place; `AppLocalizations.of(context)` gone
- [ ] `go_router` → `router.dart`, `flutter_bloc` → `dart_not_native_bloc`
- [ ] widget tests rewritten on `hostApp` + `InMemoryRenderer`
- [ ] every screen looked at on a device against §8.9

---

## 10. Performance: the cost model

One fact explains most of what follows: **a change rebuilds the widget tree
from the root.** `setState` anywhere - or a notifier a builder follows -
runs every `build` on the page, produces a whole new node tree, and hands it
to the renderer, which diffs it against the last one and patches the views
that changed. There is no per-widget dirty tracking and no element tree. On
mobile the new tree crosses a platform channel as one message.

That is cheap enough to be the design - at the protocol level the benchmark
baseline has a fifty-row screen building in tens of microseconds and
re-rendering on web in 0.1-0.3 ms
(`packages/native_bridge/test/benchmark/BASELINE.md`; the widget layer and the
platform channel on top of that are not benchmarked) - and the diff is what
keeps a text field's caret and a list's scroll position. But it changes what
an app should do:

**Do not create state in a stateless `build`.** In Flutter a
`StatelessWidget.build` runs when its parent rebuilds; here it runs on every
change in the app. A `TextEditingController()`, a `Future`, a `Timer`, a
`ScrollController` made in `build` is made again each time - a `FutureBuilder`
handed a fresh future restarts, a field handed a fresh controller loses its
text. Flutter's own advice, but here breaking it shows immediately. Make them
in a `State`'s `initState`.

**Builders run more often than they did.** `buildWhen`, `context.select`,
`updateShouldNotify` and `shouldRepaint` do not prune work (§8.4, §8.9). Keep
`build` free of side effects and of anything expensive; compute in a handler
and store the result.

**Key the rows that move.** A widget without a key *is* its position, as in
Flutter: delete the first of three keyless stateful rows and the second
inherits its state. A `ValueKey` on the repeated widget keeps each row's
`State` with its data, and becomes the node `id` a renderer matches by - so a
reorder moves the views it has rather than rebuilding every row after the
change. Measured on a fifty-row list on web, inserting at the front costs
0.40 ms keyed against 0.50 ms unkeyed.

**Give a long list a row height.** `ListView.builder(itemExtent: 56, ...)` is
windowed - ten thousand rows cost what thirty do, and the example inbox held
60 Hz scrolling on a phone.
Without a height every row is built and sent on every rebuild; fine for
dozens, not for thousands. Flutter measures rows to window them; a renderer on
the far side of a channel is holding twenty rows of ten thousand and cannot.

**A timer tick is a rebuild and a channel message.** A `Ticker` here is a
16 ms timer, and a tick that calls `setState` builds the tree and sends it.
That suits a game drawing one `CustomPaint` - a change that touches only a
canvas's commands repaints the surface in place - and it does not suit
animating a screen of five hundred nodes. For that, state the end and let the
renderer move: with `AnimatedContainer`, `AnimatedOpacity`, `AnimatedScale`,
`AnimatedRotation` and `AnimatedSlide` the tree says where things end up and
the platform animates the difference. A once-a-second countdown is no trouble
either way.

**For a game that moves every frame, draw on a canvas.** One `CustomPaint`
whose painter reads the game state, driven by a ticker, with a
`GestureDetector` or `KeyboardListener` around it - which is how the migrated
snake and frog games are built. A board of a few hundred `Container`s is fine
for a game that changes when it is tapped; rebuilt sixty times a second it is
the same picture at many times the cost.

**Renders are coalesced.** Several `setState`s in one tick are one build and
one render. In the protocol layer `render()` returns a future that completes
once the UI is up to date.

**Hot reload repaints.** Editing a `build()` re-renders the screen on the
Flutter renderer and on the platform's own views alike. Kotlin and Swift
changes need a rebuild.

---

## 11. Troubleshooting

| Symptom | Cause |
|---|---|
| A release build fails in the icon tree shaker | `--no-tree-shake-icons` is missing - §5.2 |
| The platform buttons, or a hand-built `UIBuilder.appBar`, are the default blue | the theme went to `MaterialApp` only; pass `appTheme: theme.toAppTheme()` to `runApp` - §8.2 |
| Back closes the app on Android | `MainActivity` still extends `FlutterActivity`, which owns no `OnBackPressedDispatcher` - §5.1 |
| The browser's Back button leaves the page | no history attached: `GoRouter.attachHistory` + `bindBrowserBack()`; `MaterialApp(routes:)` and `Navigator.push` need nothing - §4.4 |
| `dart compile js` fails on `dart:ui` or a plugin | a Flutter or plugin import is reachable from the web entry; put it behind a conditional import - §8.7 |
| Both `package:flutter/material.dart` and `widgets.dart` define `X` | a file imports both unprefixed; use `show` or a prefix on the Flutter one - §8.3 |
| A screen taller than the window is cut off | a `Scaffold`'s body does not scroll; wrap it in a `SingleChildScrollView` |
| A long list is slow, or a rebuild stutters with it on screen | `ListView.builder` without `itemExtent` builds every row - §10 |
| A field loses its text, or a `FutureBuilder` keeps restarting | its controller or future is created in a `build` - §10 |
| Rows swap state when one is deleted | the rows have no `Key` - §10 |
| An Arabic screen is laid out left to right | `MaterialApp(locale:)` is not the Arabic locale, or a `Directionality` further up says otherwise |
| An ad or other slot widget lags behind while scrolling | a `FlutterSlot` inside a scroller; pin it - §8.6 |
| `Unknown widget: X` / a placeholder on the page | the renderer has no case for that node type - with the iOS renderer, see §6 |
| Web page renders unstyled | `web_shell/` was not copied, or the page has no `<div id="app">` |
| Icons on web are boxes or wrong pictures | an old `web_shell/` - it must be the one shipping `MaterialIcons-Regular.woff2` |
| `Render error: MissingPluginException` on mobile | the plugin did not register - check the dependency is in `pubspec.yaml` and rebuild, since plugin registration is generated at build time |
| `Handler not found for <eventId>` | protocol layer: the node's `eventId` has no `on(...)` in `init()` |

`runApp(..., debugShowRenderErrors: true)` draws what a renderer could not do
over the app, instead of only logging it.

---

## 12. Fewer steps than this

Most of the remaining work here is packaging, not architecture. Done so far:

- ~~**Ship the native halves as a plugin.**~~ `DartNotNativePlugin` is
  registered automatically on both platforms.
- ~~**A Flutter renderer for the tree.**~~ `FlutterUIRenderer` and
  `NativeUIAppHost`.
- ~~**One-line bootstrap.**~~ `runApp` / `runNativeApp` pick the renderer,
  wire the back gesture and mount the app.
- ~~**Widen the native renderers.**~~ Both dispatch the whole vocabulary, and
  `renderer_coverage_test.dart` keeps all four renderers in step.
- ~~**Callbacks instead of event ids.**~~
- ~~**Diff the native view trees.**~~ Both patch rather than rebuild.
- ~~**A Flutter-shaped layer wide enough to migrate onto.**~~ §8.

Still worth doing, in rough order of what each would save an adopter:

1. **Compile and run iOS.** Everything in §6.
2. **pub.dev.** A git or path dependency works; a published version would
   give an app something to pin and make it `flutter pub add dart_not_native`.
   `dart_not_native_bloc` is `publish_to: none` until then.
3. ~~**Ship the test harness.**~~ `AppTester` is
   `package:dart_not_native/testing.dart` since 2026-10-10.
4. **A build command for web:** `dart run dart_not_native:build_web
   lib/main_web.dart` that compiles and copies the shell, replacing §4.2.
5. **Not needing `--no-tree-shake-icons`,** or failing with a message that
   names the flag.
6. **One import.** A `package:dart_not_native/dart_not_native.dart` barrel that
   conditionally exports the right set, so nobody has to choose between
   `core.dart`, `web.dart` and `material.dart`.
