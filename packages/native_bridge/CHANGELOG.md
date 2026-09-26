# Changelog

Versions follow [semantic versioning](https://semver.org); while the major is
0, a minor bump is where breaking changes go. `RELEASING.md` in the repository
root has the checklist and the tagging convention.

## Unreleased

Everything since 0.1.0. The headline is that the native renderers stopped being
code that had never run: both now draw the whole vocabulary on real hardware.
The lanes that would keep it that way are written and have never executed -
the repository has no remote yet, so every result below was got by hand or on
a device in the room.

### Proven, not just written

- The Android and iOS renderers run on devices - a physical Android phone (all seven
  native examples, events round-tripping) and a physical iPad (counter, design
  system, inbox with overlays and a 10k-row list).
- A device lane draws one of every node type and all ten example apps, and
  fails if the native side reports anything it could not draw. It is written
  for an Android emulator and an iOS simulator in CI, where it has never run;
  what has run is the Android half on a physical Android phone - 15 integration
  tests, green - and the iOS half on a simulator.
- Frame times are measured rather than assumed: a `FrameProbe` on each renderer
  reports what the platform actually presented. The the Android phone scrolls the 10k-row
  list at 0.7-0.8% janky frames with a 19.7ms worst frame.
- The gallery's pixel golden is gone. A tolerance was tried first, fitted to a
  two-pixel drift between engine builds on one machine; then CI drew the same
  frame on Linux and it moved 2810 pixels, 1.04% of it, because FreeType and
  CoreText draw different glyph edges. A tolerance that passes 1% of a frame
  hides a widget that moved, so the golden went instead. The tree and markup
  goldens compare structure, which is what this framework produces and what
  means the same thing on every machine.

### Native views are patched, not rebuilt

- Both native renderers diff the tree they are handed against the one on screen
  and patch what changed, falling back to a full rebuild whenever the shape
  moves. A field keeps its focus, caret and keyboard while the app re-renders.
- Rows carrying an `id` are matched by it, so a list that reorders moves the
  views it already has; a lazy list reuses the rows still in its window.

### A Flutter-shaped way to write a screen

- `package:dart_not_native/widgets.dart` gives the protocol a Flutter face -
  `StatelessWidget`, `StatefulWidget`, `setState`, `Scaffold`, `TextField`,
  `showDialog`, a routed `MaterialApp` - so a screen differs from a Flutter one
  only in its import. Every example app is written this way.
- State that outlives a screen lives in a `ValueNotifier`/`ChangeNotifier` and
  is read with `ValueListenableBuilder`; the app follows a store while it is on
  screen and lets go when it is not.
- `Tr('some.key')` resolves a translation where the text is drawn and redraws
  itself when the locale changes.

### More vocabulary

- Dialogs, bottom sheets and snackbars, with the platform back gesture closing
  the topmost one.
- Windowed long lists (`LazyList`), swipe-to-reveal row actions, and a
  `WebView` drawn with the platform's own browser view.
- A `Slider`, drawn as the platform's own and patched rather than rebuilt, so a
  drag is never interrupted; `onChanged` as the thumb moves, `onChangeEnd` when
  it is let go.
- A `GridView.count`: equal cells in equal columns, with the spacing and cell
  ratio Flutter's takes. A CSS grid on web, Flutter's own on the Flutter host,
  and a frame-positioned view on each native.
- `Tabs`: a strip of labels with one selected, drawn as Material tabs, an iOS
  segmented control or a web tab list. The selection stays in the app - the bar
  reports a tap, the next tree says what is selected.
- `InheritedWidget`, and a `Theme` on top of it: a screen reads the app's
  palette with `Theme.of(context)` rather than repeating it.
- `AnimatedOpacity` and `AnimatedContainer`: the tree says what the opacity,
  size and colour *are*, and each renderer moves from what they were - a CSS
  transition, Flutter's own implicit animations, `animate().alpha()` and a
  `ValueAnimator` on Android, `UIView.animate` on iOS. Both carry a `Curve`,
  one of the five every renderer already has.
- A `MapView`, drawn where a map costs nothing: MapKit on iOS, raster tiles on
  web (OpenStreetMap by default, attributed, and pointable at your own source).
  Android and the Flutter host draw a placeholder naming the SDK and API key
  they would need.
- A `CameraPreview`, on the same terms: `AVCapture` on iOS, `getUserMedia` on
  web, frames never reaching Dart, and a status - ready, denied, unavailable -
  instead. The app declares the permission; the view releases the camera when
  it goes away.
- A theme palette that reaches every renderer, including a dark appearance
  resolved from the platform, and iOS 26 Liquid Glass on the bar, FAB, sheet
  and dialog.
- `SwipeActions` takes `leadingActions`: buttons revealed by dragging the row
  the other way, as iOS Mail does with Mark as read. The inbox example has one.
- Fixed: on the Flutter host a `SwipeActions` row took its width from its
  child, so the actions behind a narrow one stuck out; it fills the width it
  is offered now, as the other three renderers do.
- Every filled Material icon can be named and drawn, not the curated handful:
  `Icons` and the codepoint table are generated from Flutter's own
  `icons.dart` by `tool/generate_material_icons.dart`.
- `Text` takes `maxLines` and `overflow`, so a line of unknown length can be
  cut off with an ellipsis rather than wrapping through whatever is below it.
- A long list's rows no longer have to share one height:
  `ListView.builder(itemExtentBuilder:)` gives each row its own. The renderer
  reports where it is scrolled to and Dart says which rows that is, since only
  Dart knows how tall the rows outside the window are.
- **Fixed: on iOS the rendered screen was invisible to accessibility.** A
  `FlutterView` answers `accessibilityElements` with Flutter's own semantics,
  which UIKit takes instead of the view's real subviews, so VoiceOver (and any
  automation) found an empty screen however carefully the renderer labelled it.
- Device flows (`maestro/native/`) drive both native renderers and assert what
  the app did about a tap or a keystroke - the half the existing device lane
  cannot see - and what a screen reader would be handed: a checkbox, a radio
  group and a switch announced with their labels and their states. All five
  run on a physical Android phone and on an iOS simulator; they cannot run on an
  iOS device, because Maestro cannot build its driver for one.
- Forms finished: a field that has shown an error re-checks it as the user
  types (so the message clears when the value is fixed), `Form.submit` runs the
  work only when every field passes, `Form.firstInvalid` says where to look,
  and a `signup_form` example shows the three together.
- **Fixed: Android text fields stopped reporting changes to Dart in 0.1.0's
  floating-label work** - a bound field drew and focused correctly but the app
  never heard what was typed.
- Fixed: a re-render while someone was typing could write a stale value back
  into a native field and drop keystrokes; only a deliberate change by the app
  (a bumped controller version) overwrites a field being edited now.
- Fixed: on iOS, a validation message appearing while someone typed rebuilt the
  field and took the keyboard with it.
- Two iOS layout fixes found by driving the example apps on a simulator: a
  `Row` that stated `mainAxisAlignment` now distributes its children (end,
  center and spaceBetween all moved nothing before), and a `Row` takes the
  width it is offered rather than only the width its children asked for, as
  Flutter's does.
- Text over a colour the app chose is now chosen for contrast with it - white
  over a dark fill, near-black over a light one - on a card, an app bar, a
  filled button, a badge and an `AnimatedContainer`, and for the children of a
  coloured card as well as its own title. Every card variant now draws the
  `backgroundColor` it was given; before, only `filled` did on three of the
  four renderers.

### Details that make a form usable

- A focused field is kept out from under the keyboard on all four renderers.
- The return key advances through a form; the label floats into the field's
  outline where the platform has that idiom (and stays above it on iOS, which
  does not).
- An app can move the caret itself: `TextField(autofocus: true)` takes the
  keyboard when the field first appears, and a `FocusNode` asks for it (or
  gives it up) later - a failed submit sending the user to the first field that
  needs attention, say. The ask travels as a version, so it is obeyed once
  rather than every time the app re-renders.
- Fields are named to assistive technology, errors are announced rather than
  only coloured, and checkable controls say whether they are on.

### When something goes wrong

- A render answers with a structured `RenderError` rather than a string;
  `NativeUIApp.renderErrors` is a stream, and `debugShowRenderErrors` draws the
  last few over the app.
- Web secure storage can rotate its key, and stored values can be migrated
  between versions.

### Fixed

- The iOS app could not launch at all on the iOS 26 SDK: that SDK requires the
  UIScene life cycle, and the project declared no scene manifest, so `Runner`
  quit before any Dart ran. It names the engine's `FlutterSceneDelegate` now.
  The compile-only iOS CI lane could not have caught this.
- An iOS scaffold's body ran under the home indicator where the Android one
  stopped above the navigation bar. Both stop at the safe area now, so the
  same screen ends in the same place on either platform.
- The iOS app bar stopped at the safe area, leaving the strip above it painted
  in the surface colour - a blue bar under a white band. The bar reaches the
  top of the screen now and insets its own title, the way a UINavigationBar
  does, which is also what the Android bar was just taught to do.
- The Android app bar drew behind the clock and the status icons. A window has
  been edge-to-edge since Android 15, so a bar at the top of one starts at y=0
  unless it pads itself past the inset - and it now does, with a full title row
  kept under that inset so the title still sits in the middle of the bar. Found
  on an Android phone, where it failed three of the five device flows at once.
- The iOS build (a missing `override` left the Swift renderer uncompilable for
  two commits - and an iOS lane was added so it cannot happen quietly again,
  though that lane has never run either, and it only compiles: the UIScene
  failure above is exactly what it would have missed).
- Android needed a Material-themed context; without it every render threw and
  the screen stayed blank.
- A `SwitchCompat` crash on the design-system switch, blank `Expanded` content
  in a row, and the four bugs the first audit documented.

- Offline-first sync is gone rather than unimplemented. The package exported
  243 lines of sync types - a retry policy, a pending operation, a conflict
  outcome - behind which every method threw `UnimplementedError`. Exported
  types are a compatibility promise, and these were a guess made before any
  backend had argued with them, so they were removed instead of published.
  Sync belongs in a package of its own.

### Known limits

- Map and camera preview are drawn only where they cost nothing: `MapView` on
  iOS (MapKit) and web (raster tiles), `CameraPreview` on iOS (`AVCapture`) and
  web (`getUserMedia`). Android draws a placeholder naming what it would need -
  the Google Maps SDK and an API key, or CameraX - because that is a dependency
  and a key an app has to bring, not something this package can assume.
- The camera has never been seen showing an actual picture. The permission, the
  session and the failure reports are proven on a simulator and in a browser,
  which is not the same as a frame from a lens.
- Most iOS screens have not been looked at on a phone. Six of the example apps
  were driven by hand on a simulator and three on an iPad, which found and
  fixed real layout bugs; the rest are covered only by a lane that proves the
  Swift renderer draws every node type without reporting an error, which is not
  the same as the screen being right. The device flows cannot close that gap -
  Maestro cannot build its driver for a physical iOS device (see
  `maestro/native/README.md`), so it stays a by-hand job.
- Nothing has been tested with a screen reader.
- The repository is not published yet, so `repository:` and the podspec source
  still point nowhere.

## 0.1.0

First release.

### The idea

Write a screen once as a `NativeUIApp` that builds a serialisable widget tree,
and let each platform draw it with its own UI. Nothing about the screen is
specific to a target.

### Renderers

- **Web** - real DOM, styled by a pluggable CSS kit (Material Design Lite,
  Materialize, or a framework-neutral one). Compiled with dart2js: no Flutter
  engine, no canvas.
- **Flutter** - paints the tree with Flutter widgets, which is how an existing
  Flutter app adopts a screen at a time through `NativeUIAppHost`.
- **Android and iOS** - Android Views and UIViews through a plugin, with events
  coming back over the same channel.

All four draw the same 32-node vocabulary, kept in step by a test that reads
the dispatch out of every renderer.

### What comes with it

- One call to start: `runNativeApp(app)` picks the renderer for the platform,
  wires the system back gesture, and falls back to Flutter rendering if the
  platform's own renderer is unavailable.
- Interactive nodes take callbacks (`onPressed`, `onChanged`, `onSubmitted`)
  rather than event-id strings.
- The platform back gesture - Android's button and predictive back, the iOS
  edge swipe, the browser's Back button - pops a route and only leaves the app
  when there is nothing left to pop.
- A router, forms and validators, internationalisation, key-value and secure
  storage interfaces with browser implementations, a plugin system and a
  design system. Device services (HTTP, location, notifications, background
  work…) are left to the pub.dev packages built for them.
- Renders within a tick are coalesced into one pass, and nodes carrying an `id`
  are matched by it, so a list that gains or reorders an item moves the views
  it already has.

### Known limits

- The Android and iOS renderers rebuild their whole view tree on every render.
  The reconciliation the web renderer does carries over; `renderTree` in each
  carries the steps.
- Neither native renderer has been run on a device. The Kotlin compiles and
  ships in the APK; the Swift is reviewed but never compiled.
- The vocabulary has no dialogs, sheets or snackbars, and lists render every
  row rather than windowing.
