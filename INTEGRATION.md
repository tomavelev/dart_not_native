# Adding dart_not_native to an app

This framework is not a widget library. You write your screen **once** as a
`NativeUIApp` that builds a serialisable widget tree, and a per-platform
renderer turns that tree into real platform UI: DOM + CSS in the browser,
Android Views, iOS UIViews. Flutter is optional - on mobile it can be reduced
to a host for the engine, and on web it is absent entirely.

That means integration is mostly about **which renderer you mount on**, and
what each platform needs before it can render.

---

## 1. Pick your path

| You want | Renderer | Flutter engine? | Effort |
|---|---|---|---|
| A web app, no canvas, real DOM | `WebUIRenderer` | no | low - §4 |
| A mobile app, the whole screen from the shared app | `FlutterUIRenderer` | yes | low - §5 |
| One framework screen inside an existing Flutter app | `NativeUIAppHost` | yes | low - §7 |
| A mobile app drawing real Android/iOS views | `AndroidNativeRenderer` / `iOSNativeRenderer` | yes (host only) | medium - §6 |

The first three are exercised by the test suite and the examples. The fourth
renders through the platform's own view system; the plugin wires it for you,
but it has not been exercised on a device - §6 says what that means.

**No native code is required for any of this.** The FFI bridge
(`NativeBridge.initialize('libbridge.so')`) is a separate, optional feature
for calling into C - ignore it unless you want it.

---

## 2. Add the dependency

The package is not on pub.dev yet, so depend on it by path:

```yaml
# pubspec.yaml
dependencies:
  dart_not_native:
    path: ../dart_not_native/packages/native_bridge
```

**TODO: publish the repository and put its URL here.** Once it is hosted, a
git dependency is the shape below - but the URL is not live yet, so the path
dependency above is the only one that works today.

```yaml
dependencies:
  dart_not_native:
    git:
      url: <repository URL - not published yet>
      path: packages/native_bridge
```

```bash
flutter pub get
```

Three entry points, so you import one library per target:

| Import | Use it in | Contains |
|---|---|---|
| `package:dart_not_native/core.dart` | your app/screen code | `NativeUIApp`, `UIBuilder`, `WidgetNode`, design system, router, i18n, storage interfaces, `SystemBack` |
| `package:dart_not_native/web.dart` | the web entry point | everything in `core.dart` plus `runWebApp`, `WebUIRenderer`, style kits, `LocalStorageService`, `BrowserHistoryAdapter` |
| `package:dart_not_native/run_app.dart` | `main()`, on any target | `runNativeApp`, and the right renderer for the platform |
| `package:dart_not_native/material.dart` | the Flutter host | everything in `core.dart` plus Flutter's Material, the plugins, `SystemBackChannel` |

Your screens import **only `core.dart`**. That is what keeps one screen
runnable on every target.

---

## 3. Write the screen once

```dart
// lib/app/counter_app.dart
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
          onPressed: () => setState(() => count++),
        ),
      );
}
```

Rules of the road:

- `build()` returns a tree, never a Flutter widget. Style with `UIBuilder`
  (including `UIBuilder.image`, whose `alt` is both the accessible name and
  what shows when the image cannot be loaded),
  `DSButton`/`DSCard`/`DSAlert`… or the platform-flavoured
  `AndroidUIBuilder`/`iOSUIBuilder`.
- Hand interactive nodes a callback - `onPressed`, `onChanged`,
  `onSubmitted` - and the builder registers it for you. The string form is
  still there when you want it: pass `eventId: 'increment'` and register the
  handler in `init()` with `on('increment', …)`, which is what you need for an
  event nothing in the tree fires, or one node driving another's handler.
- Give nodes an `id` when a test or an e2e flow needs to find them - the web
  renderer turns `id` into the DOM element id. Give repeated rows one too; see
  §9.
- Anything platform-specific (storage, HTTP, camera…) is injected into the
  constructor, so the same screen runs against a real back end on device and a
  fake one in tests. The framework does not wrap device services: use the
  pub.dev packages directly (see "Device services" in `TODO.md`), keeping in
  mind that Flutter plugins do not compile into the web build.

Test it without any platform at all:

```dart
final renderer = InMemoryRenderer();
final app = CounterApp()..mount(renderer);
await renderer.handleEvent('increment', {});
// renderer.tree now holds the new frame
```

---

## 4. Web

The web target compiles with plain **dart2js** - no Flutter engine, no canvas.
The output is a `main.dart.js` plus a small static shell.

### 4.1 A web entry point

```dart
// web_main.dart  (anywhere outside lib/, e.g. web/main.dart)
import 'package:dart_not_native/run_app.dart';

import 'lib/app/counter_app.dart';

void main() => runNativeApp(CounterApp());
```

`runWebApp` from `package:dart_not_native/web.dart` is the same thing with the
web-only options spelled out (`kit:`, `rootId:`); `runNativeApp` forwards to
it.

`runWebApp` loads the style kit's stylesheets and the fonts *before* the first
paint, then mounts the app into the element with id `app` (falling back to
`<body>`).

### 4.2 Build it

```bash
dart compile js -O2 -o build/web/main.dart.js web_main.dart
cp -r <path-to-package>/web_shell/. build/web/
rm -f build/web/main.dart.js.deps
```

`web_shell/` ships everything the page needs and nothing it does not:

```
index.html                     <div id="app"> + <script defer src="main.dart.js">
dnn.css                        layout primitives (column, row, padding, text…)
kits/mdl.css, kits/materialize.css
vendor/mdl/, vendor/materialize/          the CSS frameworks
vendor/roboto/, vendor/material-icons/    self-hosted fonts, no CDN
```

Use your own `index.html` if you prefer - it needs only `<div id="app">` and
the script tag; `runWebApp` adds the stylesheets itself.

`maestro/web/build_examples.sh` in this repo is that build, scripted, and is a
fine thing to copy into your project.

### 4.3 Style kits

```dart
await runWebApp(CounterApp());                        // Material Design Lite
await runWebApp(CounterApp(), kit: const MaterializeKit());
await runWebApp(CounterApp(), kit: const PlainKit());  // dnn.css only
```

Any kit can also be selected at run time with `?kit=mdl|materialize|plain`,
and `?animations=off` freezes spinners for screenshot tests. To use your own
CSS framework, subclass `WebStyleKit` and override only the components it
styles - the renderer keeps the layout, ids, events and reconciliation.

### 4.4 Browser Back

Without this the browser's Back button leaves your page instead of popping a
route. With a `NavigationApp`:

```dart
Future<void> main() async {
  final app = MyRoutedApp();
  await runWebApp(app);

  app.nav.bindSystemBack(adapter: BrowserHistoryAdapter());
  bindBrowserBack();
}
```

Routes are then written to the URL fragment (`#/users/7`), which survives a
reload with no server-side routing, and Back pops one route at a time until
the app has nowhere left to go - only then does it leave the page.

### 4.5 Storage on web

```dart
final storage = LocalStorageService(prefix: 'myapp.');
```

It implements the same `StorageService` your screen already takes, so nothing
in the screen changes between web and mobile.

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
wrap `shared_preferences` and `flutter_secure_storage` (EncryptedSharedPreferences
and the Keychain) in a few lines.

---

## 5. Android and iOS - the Flutter host

The straightforward mobile path: `FlutterUIRenderer` paints the tree with
Flutter widgets, so the whole screen - layout, components, events - comes from
the same `NativeUIApp` your web build runs.

`NativeUIAppHost` is that renderer plus the plumbing: it mounts the app,
rebuilds when the app renders, and disposes with the widget.

```dart
// lib/main.dart
import 'package:dart_not_native/run_app.dart';

import 'app/counter_app.dart';

void main() => runNativeApp(CounterApp());
```

That is the whole host: `runNativeApp` picks the renderer for the platform,
wires the system back gesture, and mounts the app. The same call is the web
entry point too - the conditional import gives you the DOM renderer there, so
one `main.dart` serves every target.

The app bar, the centred count and the floating action button from §3 are
painted by `FlutterUIRenderer`, and tapping the button runs the same callback
the web build runs. Pass `nativeViews: true` to render with the platform's own
views instead (§6); if that renderer is unavailable the app falls back to
Flutter rather than showing an empty screen.

If you want the app somewhere specific rather than as the whole app - a tab, a
route, a panel - skip `runNativeApp` and place a `NativeUIAppHost` yourself
(§7).

If you would rather keep your own Flutter widgets and use the app only for its
state and events, that works too - mount on `InMemoryRenderer` and read the
app's fields, which is what the examples in `lib/examples/*.dart` do.

Nothing to change in Gradle, the manifest, Xcode or the Podfile.

### 5.1 The system back gesture

The Android back button and the iOS swipe from the left screen edge reach Dart
through one channel. Dart:

`runNativeApp` wires it. An app that routes says so by mixing in
`NavigationHost`, and then back pops a route:

```dart
class MyApp extends NativeUIApp with NavigationHost {
  @override
  late final NavigationApp nav = NavigationAppBuilder()
      // …routes…
      .build();

  @override
  WidgetNode build() => nav.router.buildCurrentRoute();
}
```

Hosting the app yourself instead of calling `runNativeApp`? Then it is two
lines:

```dart
SystemBackChannel.bind();   // once, at startup
app.nav.bindSystemBack();   // NavigationHost apps
```

`bindSystemBack()` pops a route and tells the platform it consumed the
gesture; on the first screen it declines, and the platform closes the app as
the user expects. For anything else that should swallow Back - an open sheet,
a search overlay - register directly:

```dart
SystemBack.addHandler(() {
  if (!sheetIsOpen) return false;   // not mine
  closeSheet();
  return true;                      // consumed
});
```

Handlers run most-recently-registered first, so a modal beats the router
underneath it.

**The native halves ship with the package.** `DartNotNativePlugin` is created
by Flutter's generated plugin registrant on both platforms and registers the
back gesture itself - there is nothing to copy and no AppDelegate to edit.

Android needs one thing of you: the gesture hangs off an
`OnBackPressedDispatcher`, which the plain `FlutterActivity` does not own. Use
the androidx host instead, either by pointing the manifest straight at it:

```xml
<activity android:name="io.flutter.embedding.android.FlutterFragmentActivity" ... >
```

or by making your own activity extend it:

```kotlin
class MainActivity : FlutterFragmentActivity()
```

With any other host the plugin still renders; back simply keeps its default
behaviour. On iOS there is nothing to do at all.

---

## 6. Android and iOS - rendering real native views

This is the path where Flutter stops painting and the tree becomes
`MaterialToolbar`, `AppCompatTextView`, `FloatingActionButton`, `UIView`…

The native halves ship with the package. `DartNotNativePlugin` constructs the
renderer as soon as the engine attaches to an activity (Android) or the root
view controller exists (iOS), and registers its channels. So the whole
integration is on the Dart side:

```dart
void main() => runNativeApp(MyApp(), nativeViews: true);
```

That is the whole of it: the renderer is picked for the platform, initialises
itself on its first render, and falls back to Flutter rendering if the native
half is not there. Mounting one by hand works too:

```dart
import 'package:dart_not_native/platforms/android_renderer.dart';
// or  '.../ios_renderer.dart';

app.mount(AndroidNativeRenderer());
```

Both renderers speak the same channel
(`com.programtom.dart_not_native/renderer`), so only the class name differs,
and both send their events back on it - a tap, a checkbox, a keystroke reaches
the same handler it would on any other renderer.

**Status, plainly:** both draw the whole node vocabulary. A test reads the
dispatch out of each source file and compares it against the protocol's own
list, so a type going missing fails the build rather than showing a
placeholder on a device.

Both have now been run on real hardware. The Kotlin compiles, ships in the
APK, and runs on a physical Android phone: every example app draws natively with
events round-tripping, 15 integration tests pass there, and five Maestro flows
drive taps and keystrokes through the real views. The Swift compiles, runs the
same five flows on an iOS simulator, and runs on a physical iPad.

What is still thin is iOS *screens*: six example apps have been looked at on a
simulator and three on an iPad, and the flows cannot be automated on an iOS
device at all, so the rest of the iOS screens are drawn-without-error rather
than seen. Expect some layout there to need adjustment; Android is the better
proven of the two.

If you would rather have the tree painted by Flutter - the renderer with the
most test coverage - that is §5, and it needs no native code at all.

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

## 7. Adding one screen to an existing Flutter app

You do not have to convert an app to adopt the framework. `NativeUIAppHost` is
a widget, so one screen can come from a `NativeUIApp` while the rest of the app
carries on as before:

```dart
Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => NativeUIAppHost(app: SettingsApp(storage: storage)),
  ),
);
```

That screen is now the same object your web build runs: same layout, same
components, same event handlers, same tests. Nothing else in your app changes.

A tree rooted in a Scaffold brings its own; any other root is wrapped in a
`Material`, so a fragment - a settings panel, a form - can also be dropped
inside a screen you already have:

```dart
Column(
  children: [
    const MyExistingHeader(),
    NativeUIAppHost(app: SignupFormApp()),
  ],
)
```

If you need the app's state rather than its tree - to drive your own widgets,
or to read a value out - mount it yourself on `InMemoryRenderer` and read the
app's fields; `lib/examples/*.dart` do exactly that.

This is the cheapest way in: share the screen now, decide about native
rendering later. The examples are laid out this way -
`lib/examples/apps/*.dart` hold the shared apps, `lib/examples/*.dart` are the
Flutter hosts, `lib/examples/web/*.dart` the web entries.

## 8. Checklist

**Web**
- [ ] `dart_not_native` in `pubspec.yaml`
- [ ] an entry that calls `runWebApp(...)`
- [ ] `dart compile js` + `web_shell/` copied next to `main.dart.js`
- [ ] `<div id="app">` in the page
- [ ] `bindBrowserBack()` if you route

**Mobile (Flutter host)**
- [ ] `dart_not_native` in `pubspec.yaml`
- [ ] `NativeUIAppHost(app: MyApp())` somewhere in your widget tree
- [ ] `SystemBackChannel.bind()` + `bindSystemBack()` if you want the system
      back gesture to pop routes
- [ ] the Android host is `FlutterFragmentActivity` (manifest or subclass)

**Mobile (native views), additionally**
- [ ] mount on `AndroidNativeRenderer` / `iOSNativeRenderer` instead

## 9. Performance notes

Three things are worth knowing, because they change what your app should do:

**Renders are coalesced.** A tick's renders become one pass - an event handler
that changes three fields costs one DOM update, not three. `render()` returns a
future that completes once the UI is up to date, so `await render(...)` still
means what it says; code that reads the DOM straight after a render without
awaiting is the only thing that needs care. A host that cannot await can opt
out with `WebUIRenderer(batched: false)` (and the same flag on the native
renderers).

**Give repeated rows an `id`.** The renderer identifies a node by its `id`, so
a list whose rows carry one moves the elements it already has when an item is
added, removed or reordered, instead of rebuilding every row after the change.
Measured on a fifty-row list, inserting at the front costs about half as much
with keyed rows as without. The id must be on the *repeated* node - the row
wrapper - not only on something inside it:

```dart
WidgetNode _row(Todo todo) => WidgetNode(
      type: 'Padding',
      props: {'padding': 8.0, 'id': 'todo_row_${todo.id}'},
      children: [ ... ],
    );
```

**Hot reload repaints.** Editing a `build()` re-renders the screen, on the
Flutter renderer and on the platform's own views alike, so the edit-and-look
loop works the way it does in an ordinary Flutter app.

**There is no animation loop.** Nothing renders per frame; a render happens
when the app changes state. Animate with CSS on web (the framework's own
spinners do, which is why they run at the display's refresh rate without
touching Dart) and with Flutter's animation widgets on a Flutter host. Driving
an animation from `setState` will work but will not be smooth, and on the
native view renderers - which rebuild the view tree per render - it will not be
usable at all.

## 10. Troubleshooting

| Symptom | Cause |
|---|---|
| `Unknown widget: X` on the page | the renderer has no case for that node type; check the type string |
| Web page renders unstyled | `web_shell/` was not copied, or the page has no `<div id="app">` |
| `Handler not found for <eventId>` | the node's `eventId` has no `on(...)` in `init()` |
| A text field loses focus while typing | the app re-renders with a different `initialValue` than the user typed; only set it when the app means to change the value |
| Back closes the app instead of popping | `SystemBackChannel.bind()` / `bindBrowserBack()` missing, or `MainActivity` still extends `FlutterActivity` |
| `Render error: MissingPluginException` on mobile | the plugin did not register - check the dependency is in `pubspec.yaml` and rebuild, since plugin registration is generated at build time |
| Back closes the app on Android only | the host is still `FlutterActivity`, which owns no `OnBackPressedDispatcher` - see §5.1 |
| A native-view screen shows placeholders | the Kotlin/Swift renderers cover fewer node types than the web and Flutter ones - see §6 |

---

## 11. Fewer steps than this

Most of the remaining work here is packaging, not architecture. Two of the
biggest reductions are done:

- ~~**Ship the native halves as a plugin.**~~ Done: `DartNotNativePlugin` is
  registered automatically on both platforms, so §5.1 and §6 no longer involve
  copying files or editing hosts.
- ~~**A Flutter renderer for the tree.**~~ Done: `FlutterUIRenderer` and
  `NativeUIAppHost` paint the whole screen from the shared app, which is what
  makes §5 and §7 a one-liner.
- ~~**One-line bootstrap.**~~ Done: `runNativeApp(app)` picks the renderer for
  the platform, wires the back gesture and mounts the app, and falls back to
  Flutter rendering when the platform's own renderer is unavailable.
- ~~**Widen the native renderers.**~~ Done: Android and iOS now draw the whole
  vocabulary, and `renderer_coverage_test.dart` keeps all four renderers in
  step.
- ~~**Callbacks instead of event ids.**~~ Done: `onPressed`, `onChanged` and
  `onSubmitted` register themselves during the build, so most apps no longer
  need an `init()` at all.

Still worth doing, in rough order of what each would save:

1. **A build command for web:** `dart run dart_not_native:build_web
   web_main.dart` that compiles and copies the shell, replacing §4.2.
2. **One import.** A `package:dart_not_native/dart_not_native.dart` barrel that
   conditionally exports the right set, so nobody has to choose between
   `core.dart`, `web.dart` and `material.dart`.
3. **pub.dev.** The repository is hosted at https://github.com/tomavelev/dart_not_native, so §2 can offer a git
   dependency; pub.dev would make it `flutter pub add dart_not_native`.
   The podspec's `homepage` and the `repository:` field of both pubspecs want
   that URL too.
4. **Diff the native view trees.** Both rebuild the whole hierarchy on every
   render - `removeAllViews()` on Android, `removeFromSuperview()` on iOS -
   which costs milliseconds per render and loses scroll position, selection and
   caret each time. The web renderer's reconciliation carries over directly;
   `renderTree` in each file carries a TODO with the steps. It needs a device
   to develop against, which is why it has not been done here.
