# Changelog

Versions follow [semantic versioning](https://semver.org); while the major is
0, a minor bump is where breaking changes go. `RELEASING.md` in the repository
root has the checklist and the tagging convention.

## Unreleased

Everything since 0.1.0. The headline is that the native renderers stopped being
code that had never run: both now draw the whole vocabulary on real hardware.
The lanes that compile and test it run on every pull request; none of them
boots a device, so every device result below was got by hand or on a device in
the room.

### The widget layer takes Flutter's shape (breaking)

`widgets.dart` grew from a handful of widgets to the surface a real Flutter app
uses - `Container`, `Stack`, `GestureDetector`, `Navigator.push`, `Form`,
`CustomPaint`, `ThemeData`, `MediaQuery`, `LayoutBuilder` and the rest - so a
screen migrates by changing its import. Where the old layer disagreed with
Flutter, it now agrees, and these are the places existing code has to change:

- **A `Scaffold`'s body no longer scrolls.** Put a screen taller than the
  window in a `SingleChildScrollView` or a `ListView`, as in Flutter. `ListView`
  and `GridView` now scroll themselves (they used to be a column and a grid
  inside the scrolling body).
- **`ListView.builder`** takes Flutter's `itemBuilder: (context, index)`, no
  longer needs a `key`, and no longer needs a row height: with `itemExtent`
  (or `itemExtentBuilder`, now Flutter's two-argument form) it is windowed as
  before; without one every row is built inside a scroller.
- **`Theme.of(context)` returns a `ThemeData`**, not the protocol's `AppTheme`.
  The palette is `Theme.of(context).appTheme`; `ThemeData.toAppTheme()` makes
  the one to hand to `runApp(appTheme:)`.
- **`Form`, `FormField` and `TextFormField` are Flutter's** (`GlobalKey<FormState>`,
  `validator`, `onSaved`). The framework's own form model is exported from
  `widgets.dart` as `FormModel` and `FormFieldModel`, and the field bound to it
  is `ModelTextFormField(field:)`. `forms/form.dart` itself is unchanged.
- **`Locale`** is `Locale('en', 'US')` - positional, with `languageCode`,
  `countryCode`, `scriptCode` and `toLanguageTag()`. The named `region:` and
  `script:` parameters are gone (`Locale.fromSubtags` names a script);
  `language`, `region` and `script` remain as getters.
- **`Color` carries its alpha to the renderers**: `#rrggbb` when opaque,
  `#aarrggbb` otherwise. It used to be dropped.
- **`Icon` renders an `Icon` node**, not a `Text` node holding the glyph.
- **`Card` has Flutter's metrics**: a margin of 4 and no padding of its own.
  Put a `Padding` inside it.
- **`ListTile`** is composed in Material's metrics (and its `onTap`, which was
  dropped, works); **`Divider(height:)`** is the height of the strip, not the
  margin on each side.
- **`Checkbox.onChanged`** is `ValueChanged<bool?>` and **`Radio.onChanged`**
  `ValueChanged<T?>`, as in Flutter.
- **`ButtonStyle`'s fields are `WidgetStateProperty`s**; `styleFrom` is
  unchanged in use. `MainAxisAlignment` and `CrossAxisAlignment` are enums.
- **`AnimatedContainer`** renders a `Box` node with `animateMs` (the
  `AnimatedContainer` node is still drawn, but the widget no longer builds
  it), no longer centres its child, and - like `AnimatedOpacity` - requires
  its `duration` and defaults to `Curves.linear`, as in Flutter.
- **`MaterialApp.routes`** takes Flutter's `(context) => Widget`; the
  `(context, params) => Widget` form is still accepted for a path with
  parameters, so the map is typed `Map<String, Function>`.
- **`Navigator.of(context)` returns a `NavigatorState`**; an `AppBar` gains a
  back button on a page that can be popped.
- **`TextField.textInputAction` and `maxLines` are nullable**, `decoration`
  defaults to an empty `InputDecoration`, and `FocusNode.requestFocus()` and
  `TextEditingController.text =` redraw the field without a `setState`.
- **A keyed widget's `State` is kept per page and per widget type**, so the
  same key on two routes is two states. A `State`'s `mounted` is now false
  after `dispose()`, and a `State` inside a dialog is no longer disposed on
  every rebuild.
- **`core.dart` no longer exports the legacy router's `Route` and
  `RouterConfig`** (they are Flutter's names in `widgets.dart` now); import
  `routing/route.dart` for them.
- `ChangeNotifier` is a `mixin class`, so `with ChangeNotifier` works.
- **Snackbars queue**, as in Flutter: `showSnackBar` while one is showing
  waits for it instead of replacing it, each bar's `closed` says how that
  bar went, `clearSnackBars` drops the ones waiting, and a controller's
  `close` takes its own bar out of the queue. A screen that relied on the
  newest message appearing at once now calls `hideCurrentSnackBar()` first,
  which is what the same screen does under Flutter - the inbox example did,
  and does.

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

### Five things that were accepted and not done

- **`onEnd`** is called on `AnimatedOpacity`, `AnimatedContainer`,
  `AnimatedScale`, `AnimatedRotation`, `AnimatedSlide`, `AnimatedPadding`
  and `AnimatedAlign`, a `duration` after a build that changed what the
  widget shows. A change on the way starts the wait again; a widget that
  leaves the tree ends nothing. It is the app's clock - no renderer reports
  an animation finishing - so it is when the animation was asked to end.
- **`WillPopScope`**, over `PopScope`: the back gesture, an app bar's arrow
  and `maybePop` ask `onWillPop` and leave on a true. On an app's first
  screen a true cannot close the app.
- **A `KeyboardListener` is no longer one of a crowd.** The one whose
  `FocusNode` was asked for focus - `requestFocus()`, or `autofocus` - hears
  alone, the most recently asked of several; and a dialog or sheet takes the
  keys from the page behind it. With no ask they all hear, as before.
- **`Image.frameBuilder` and `loadingBuilder`** are called, once per build
  and as for an image that is already there, so the frame or the background
  they put around the image is drawn. They were never called.
- **The browser's Forward button** brings back a named route, or a
  `GoRouter` page, that Back left. `SystemBack.addForwardHandler` and
  `dispatchForward` are how a router hears of it. One bug went with it: a
  forward the *app* asked for was counted as a pop the browser never
  reported, so the next Back the user pressed was swallowed.

### A plain row can be swiped on Android

- A `SwipeActions` row whose child does nothing with a touch - a plain list
  tile - could not be swiped unless the drag began over the action button
  hidden behind it. The finger went down on a view that takes no touches,
  so it was offered to the row itself, which declined it, and the drag that
  followed was never delivered. The row takes the touch now and decides for
  itself when it has become a horizontal drag. Found on an Android 17
  emulator, where a partial swipe now leaves the row open and a tap on the
  button it uncovers fires it; lists of such rows still scroll.
- A row with leading actions as well as trailing ones is patched in place
  again: the patch looked for the row's own layer where the second bar is.

### `FocusScope.nextFocus()`

- `FocusScope.of(context).nextFocus()` and `previousFocus()` send the
  keyboard to the next text field, in the order the fields are built and
  round from the last to the first, and say whether they moved. They did
  nothing and said false, so the `onSubmitted: (_) =>
  FocusScope.of(context).nextFocus()` a Flutter form is written with left
  the keyboard where it was. The field it moves on from is the one whose
  `onSubmitted` it is called from; called from anywhere else, the one whose
  `FocusNode` has the keyboard. Disabled and read-only fields, and a node
  that says `skipTraversal`, are passed over.
- Every text field has a `FocusNode` for this, one kept for its place when
  the app gave none. A field is still told about focus and blur only when
  the app gave it a node, so no field sends events it did not send before.

### `PopScope`

- A page can say it is not to be left. With `canPop: false` the back
  gesture - Android's button, the iOS edge swipe, the browser's Back - an
  app bar's back arrow and `Navigator.maybePop` leave the page where it is
  and call `onPopInvokedWithResult(false, null)`, which is where a screen
  asks whether to discard what was typed; `Navigator.pop` goes regardless,
  as in Flutter. On an app's first screen a refused gesture keeps the app
  open. A popped page hears `onPopInvokedWithResult(true, result)`,
  whether a `Navigator`, `GoRouter` or the named routes popped it. The
  widget did not exist, so a screen using it did not compile.
- `PopScope.notifyPopped(context, result)` is how a router says its page
  has gone; one of an app's own calls it from its `pop`.
- Short of Flutter's: a dialog is not a page - `barrierDismissible: false`
  is how one stays up - and there is no `WillPopScope`.

### A time of day, written as the locale writes it

- `TimeOfDay.format` writes what Flutter does for the app's locale: `3:05 PM`
  in American English, `15:05` in British, `9:30` in Spanish, `15.05` in
  Finnish, `下午 3:05` in Chinese, `15 h 05` in Canadian French, with the
  locale's own words for the halves of the day. It knew two conventions -
  twelve-hour for English, `HH:mm` for everything else. The table is
  Flutter's, generated from the SDK's `flutter_localizations` by
  `tool/generate_time_formats.dart`; a region is listed only where it
  differs from its language. **This changes what some locales show**:
  Spanish, Japanese and the other `H:mm` locales lose the leading zero, and
  Arabic, Chinese, Korean and the other twelve-hour locales gain a
  twelve-hour clock.
- `MediaQueryData.alwaysUse24HourFormat`, and
  `MediaQuery.alwaysUse24HourFormatOf`. False unless a `MediaQuery` the app
  builds says otherwise: no renderer reports the device's setting.

### `didChangeDependencies` is called when a dependency changes

- A `State` that reads an inherited widget through its own `context` -
  `Theme.of`, `MediaQuery.of`, `Localizations.localeOf`, one of the app's -
  has `didChangeDependencies` called again before a build in which it has
  changed, as in Flutter. It ran once. `InheritedWidget.updateShouldNotify`
  is what says "changed", where it was accepted and ignored: a widget that
  does not override it is taken to have changed on every build, so an
  inherited widget of the app's own should say what matters. The framework's
  own - the theme, the locale, the route, the form, the tab controller and
  the rest - each do. Nothing about what is rebuilt changes.

### The browser's Back button, with nothing to wire

- **`MaterialApp(routes:)` is in the browser's history.** Each named route
  is an entry and a fragment in the URL (`#/settings`); Back pops it; a
  reload or a link straight to a route opens it over the first one. It was
  bound to the back gesture with no history behind it, so on the web Back
  left the site and the URL never changed.
- **Back closes a page pushed with `Navigator.push`, a dialog and a
  sheet.** None of them has a name to put in the URL, but while one is open
  the app keeps one history entry of its own behind it for Back to land on.
  Where a router is already mirrored, its entries do that.
- `HistoryAdapter.platform` puts another history in the way of both - a fake
  in a test, or one that writes paths instead of fragments - and
  `HistoryAdapter.currentPath` is what an adapter says the app was opened at.
- `runApp` takes `systemBack`, as `runNativeApp` does, and false keeps the
  app out of the browser's history as well as the back gesture.
- Not done: Forward does not bring back what Back closed.

### Swipe actions follow the reading direction

- A `SwipeActions` row's trailing actions are at the end of the row and its
  leading ones at the start, whichever way the screen reads - so in Arabic
  Delete is on the left and is reached by dragging right, and a
  `Dismissible`'s `endToStart` means what it does in Flutter. The iOS
  renderer was already written to. The web and Android renderers placed and
  dragged by left and right; the Flutter host turned the two bars and not
  the drag, so a swipe in a right-to-left screen uncovered one bar and fired
  the other's action. Tested on web and the Flutter host; on an Android
  emulator a full drag each way fired the right action in both directions.

### A test harness an app can import

- `package:dart_not_native/testing.dart` exports `AppTester`: mount a screen
  on an in-memory renderer, `tap`, `toggle`, `typeInto` and `submitInto` a
  node by its key, and read the tree back. It was `test/support/app_tester.dart`
  in this repository, copied by hand into every app that used the framework;
  the class is the same, so a copy is replaced by changing the import.
  `AppTester.widget(const MyScreen())` is new, for
  `AppTester.mount(hostApp(...))`.

### The iOS plugin is a Swift package too

- `ios/dart_not_native/Package.swift` declares the plugin for Swift Package
  Manager, which Flutter is moving every plugin to and had begun warning
  about. The three Swift files moved from `ios/Classes/` to
  `ios/dart_not_native/Sources/dart_not_native/`, where SwiftPM expects
  them, and the podspec builds them from there - so an app on CocoaPods
  gets the same code it did. Built both ways on a simulator. The podspec's
  minimum is iOS 15 now, which is Flutter's own.

### The iOS renderer runs again

- Everything the Swift renderer gained on 2026-10-03 was written on a machine
  with no Xcode. It compiles (the `native.yml` lane, 2026-10-05), and on
  2026-10-09 `tool/device_check.sh ios` passed on an iPhone 18 Pro simulator
  (iOS 27.0): the five Maestro flows, `app_test.dart` (2 tests) and
  `native_renderer_test.dart` (14 tests - every example app drawn with
  nothing reported undrawn). The examples put eight of the twelve new node
  types through it: `Box`, `Stack`, `Positioned`, `Scroll`, `Icon`, `Canvas`,
  `BottomBar` and `BottomNavigation`. `Dropdown`, `DatePicker`, `TimePicker`
  and `FlutterSlot` are on none of those screens.
- Then the controls gallery was looked at, tab by tab, with every control on
  it driven, and five things were wrong that no test had said:
  - **Whatever takes the width it is offered had none in a column that
    aligns to one side.** Only a `Row` was told to fill. A `Stack` of layers
    in a box with a height drew nothing at all, a slider was a thumb with no
    track, a linear progress bar was a few points long, and a text field and
    a card were as wide as their words. The rule is the Kotlin renderer's
    `fillsWidth`, widened to boxes, layers, sliders and progress bars, and
    it holds on a patch as well as a build.
  - **The app bar took whatever height the body did not**: over a scroller
    with little in it the bar was a third of the screen, and a different
    height on each page of one app. Not only there: the components showcase,
    the design system, the sign-up form and the routing example all opened
    with it, under a device check that was green.
  - **An `Expanded` lost its room to a button beside it** - a card's star
    sat in the middle of the card.
  - **A disabled button looked like one that works.** It is drawn at
    Material's 12% and 38% now.
  - **A scroller longer than its content stretched the content** to match,
    one list tile taking all of the slack.
- `Dropdown`, `DatePicker` and `TimePicker` were opened by hand there and
  gave back what was chosen. `native_renderer_test.dart` now draws the twelve
  new node types as well (17 tests): a free-form tree, and a screen under
  each picker. Green on the simulator, and on an Android 17 emulator the
  next day, with the six agent-device flows. A `FlutterSlot` has only drawn its fallback - no
  Flutter widget has shown through the hole on iOS - and none of the three
  migrated apps has run there.

### Three real apps on an Android emulator

Three migrated Flutter apps were walked screen by screen on a Pixel 8 emulator
(API 35). What that found in the Android renderer, and fixed:

- **An event is answered by the build it was raised against.** Callback ids
  are allocated by order, so an id names a different callback once a build
  allocates a different number before it. The views may still be showing an
  earlier tree when their event arrives: a list's size report was landing on
  whichever row's tap had since been given its number, selecting a time nobody
  touched. The tree now travels with its build number, the views hand it back
  with every event, and `EventBindings` keeps the last few builds' callbacks.
  Both native renderers echo the number - the Swift compiles, and the case
  has not been tried on iOS - and the web and Flutter renderers name the build
  they are showing: the Flutter host builds its widgets a frame after a render, so a
  tap in that frame was from the build before.
- **Buttons are drawn as written**: no forced capitals or wide tracking on a
  button, a tab, a snackbar action or an extended FAB, and no shadow box
  around a text, outlined or tonal button.
- **A hugging column is as wide as what is in it wants**: a `Row`, a `Wrap`
  or a box that expands no longer collapses to the width of its narrowest
  sibling (a d-pad's middle row, a wrap cut to one line's height, a square
  board the size of the button under it).
- **A box keeps what its child states**: an image or a sized box inside a
  `Box` keeps its size; a clipped box is clipped to the rectangle it was just
  laid out at (its first outline was empty, and hid the child); a row in an
  aligned box gets the box's width, so a list tile's trailing sits at the end.
- **The app bar** centres its back arrow on the title's line, and the status
  icons are drawn light or dark to read over the bar behind them.
- **Material's own** check box, radio button and linear progress bar, built
  against the Material context; slider, tab bar, text field and dropdown take
  the app's primary where they showed the Material theme's purple.
- **Icon buttons have a 48dp target** and a ripple; a draggable box is picked
  up by a long press even when a child takes the touch; a dropdown in a row is
  as wide as what it shows; a stack clips at its own edge, not each child's;
  a shadow or a moved box is not cut off by the views above it; a dialog's
  scrim reaches the bottom of the window; the keyboard closes with the field
  it was typing into.
- **A scroller says where it is, and comes back there.** `UIBuilder.scroll`
  takes `onScroll`: the node carries a `scrollEventId` and the renderer sends
  `{offset, maxExtent, viewport}` when the scroller comes to rest and at most
  every 100 ms on the way - never once a frame. The widget layer's
  `ScrollController.offset`, its `position` and its listeners follow the
  reader from that, and every scroller's node now carries its offset, so a
  view the renderer has to make again - the page came back from under a
  pushed one, a snackbar changed the shape of the screen - starts where the
  reader was instead of at the top. A scroller without a controller keeps its
  position by its place in the tree. On Android, web and the Flutter host;
  written for iOS, compiled and not checked there. A windowed list still reports rows, not
  pixels.
- **A snackbar sits above the bottom bar and the floating button**, not over
  them, on Android, web and the Flutter host (iOS compiled, not checked).
- **A navigation rail scrolls when its destinations do not fit** - seven of
  them on a phone held sideways - on all four renderers (iOS compiled, not checked).
- **Material 3 on Android.** The Material views are built against a Material
  3 theme: buttons have round ends, the bottom navigation is 80dp with a pill
  behind the selected destination, the floating button is the rounded square,
  cards are 12dp, an app bar's title is 22sp regular. The theme is chosen by
  the palette in force rather than by the device, so an app with one theme is
  not handed dark Material views on a dark phone. The app bar stays 56dp,
  which is what Flutter's `AppBar` is under Material 3 too.
- **A dropdown puts the keyboard away** when it takes the focus from a field,
  and its arrow, its menu and a field's caret are the app's colours.
- **A card that turns dark turns its text light**: a patch that changed the
  colour in force inside a box or card left the unchanged text below painted
  for the old one - dark on dark at a launch in dark mode. It rebuilds now.
- **An `AppBar` decides its own colours, as Flutter does** (widget layer):
  its own, then `AppBarTheme`'s, then the surface under Material 3 (the
  default) and the primary under a light Material 2 theme - and always states
  them, so a page's bar and the bar of a scaffold nested in it are one app's.
  This changes the look of an app that relied on the renderers'
  primary-coloured bar; `UIBuilder.appBar` with no colour is still the
  renderer's. A button with no style states Material 3's 40 by 24 (12 on a
  text button) under a Material 3 theme.

In the widget layer (shared with every renderer): a box around a `Center` or
a `Row` fills the width it is offered, as Flutter's does; a `ListTile` is as
wide as its list; an `IconButton` takes the inherited icon colour.

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

### What a screen reader - and a device test - can find

Driving the three apps with [agent-device](https://github.com/callstack/agent-device)
showed their screens were nearly empty to anything that reads the
accessibility tree: no view had an identifier, and what was composed from
boxes - every `InkWell`, list tile, chip and drawn button - had no name and
no role. Each was a defect for TalkBack and VoiceOver before it was one for a
test. Verified on an Android 15 emulator; the DOM renderer has browser tests
for the same; **the Swift compiles and none of this has been checked on
iOS** beyond the accessibility flow the device check already had.

- **A node's `id` reaches the tree.** A widget's `Key` was already the node's
  `id`; the renderers now expose it - Android as the view's resource name
  (`resource-id` in uiautomator), iOS as `accessibilityIdentifier`, the DOM as
  `id` - on build and on every patch. It is the id as written, with no
  `<package>:id/` in front, which is what React Native and Compose do and
  what the tools match. A text field's and a dropdown's id is on the field
  itself on the native renderers; a swipe row's actions are
  `<row id>.action-<n>`.
- **A box with a tap can be activated.** It is announced as a button named by
  the text inside it (or its `semanticLabel`, or its `tooltip`), unless it
  holds another control - a card with a button in it is a clickable group, so
  that both stay reachable. A long press is offered as an action too. On the
  web the same box is `role="button"` with a tab stop, and `role="group"`
  when it holds a control.
- **`IgnorePointer` holds for a screen reader.** Nothing under it can be
  activated, by "activate" or by the keyboard, and what would have been is
  announced as unavailable.
- **New on a `Box`:** `semanticRole` (`heading`, `button`, `image`,
  `progress` - read off any node), `semanticValue`, `liveRegion`,
  `excludeSemantics`, `disabled` and `selected`. `Canvas`, `Checkbox`,
  `Radio`, `Toggle` and `Loading` take a `semanticLabel`.
- **The widget layer carries what it used to drop.** `Semantics` passes
  `header`, `button`, `image`, `liveRegion` and `excludeSemantics`, and puts a
  label on the child itself when the child is what takes the tap - as
  `Tooltip` now does with its message. `ExcludeSemantics` hides its child.
  `CheckboxListTile`, `SwitchListTile` and `RadioListTile` name their control
  by the tile's title (`labelledBy`, and `semanticLabel`, on the three
  controls). A button or icon button drawn from a box says it is a button and
  that it is off when it has no handler. A filter, choice or input chip says
  whether it is selected, as does a selected `ListTile`; a chip's delete
  button is called "Delete". The progress indicators pass their key and
  `semanticsLabel`.
- **Smaller things:** an icon nobody named no longer puts its private-use
  character in the tree, and a named one says its name instead; the app bar's
  title and a dialog's title are headings; on the web, `Loading` is a
  `progressbar` and every kit's switch is a `switch`.
- **A device lane that needs all of the above**: `e2e/agent-device/`, six
  flows over four example entry points, one of them new - the controls
  gallery, which has the node types the older examples lack. `TESTING.md`
  says how to run it and how a widget maps to a selector.
  `maestro/native/run.sh --agent-device` runs the Maestro flows through the
  same tool; three of the five Android ones pass that way.

Not exposed, and why: a `Semantics(onTap:)` (put the tap on a
`GestureDetector`); the expanded state of an `ExpansionTile`; a heading's
level (every `semanticRole: heading` is level 2 on the web); a long press on
the web, which has no keyboard or screen-reader equivalent; and on iOS, the
tap of a box that also holds another control, which stays touch-only so the
inner control is not hidden. The Flutter renderer was not touched.

### Fixed

- `Column(verticalDirection: VerticalDirection.up)` now turns the main axis
  round as well as the children: `start` is the bottom, as in Flutter. It used
  to reverse the children and still pack them against the top.
- A `GestureDetector` or `InkWell` around a child that fills - a
  `SizedBox.expand`, a `CustomPaint` with one - fills too, so the whole area
  takes the touch rather than a box hugging nothing.
- A `CustomPaint` that left the tree and came back to the same place - a chart
  that gave way to a spinner while its data loaded - painted against the
  viewport from then on: it is a new `State`, and a renderer does not repeat a
  size that has not changed. The size last reported for the surface is kept
  with the app now, and a new state starts from it.
- A `FlutterSlot` on a page that is only kept alive under another one no
  longer registers itself on every build; a ticking page on top used to make
  the slot registry add and drop it once a frame.
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
- Icons on web were the wrong pictures. `Icons.x` carries the codepoint of
  Flutter's own font, which is what the native renderers draw from; the web
  shell's icon font had the same names at other codepoints, so `Icons.home`
  drew a caps-lock key. The shell now ships Flutter's font itself
  (`MaterialIcons-Regular.otf`, rewrapped as WOFF2 by
  `tool/generate_material_icons.dart` - 423 KB, where WOFF made 557 KB of
  it; the tool needs the `brotli` command for that) and the web renderer draws every icon -
  an `Icon`, a button's, a destination's, a text field's - as the character at
  its codepoint, as the other three renderers do. That font has no ligatures
  for the names, so an icon button's name is drawn through the codepoint the
  builder resolves for it; a name the table does not know, with no `codepoint`
  beside it, draws the button's default glyph. `web_shell` is about 270 kB
  larger for it: the one font is 557 kB, the two it replaces were 293 kB.
- `Icons` had no `_outlined`, `_rounded` or `_sharp` names, on the belief that
  those glyphs live in fonts Flutter does not bundle. They do not: Flutter
  declares all 8,825 icons in the one `MaterialIcons` family, and the bundled
  file has a glyph at every one of those codepoints. `Icons` now has them all,
  so `Icons.home_outlined` compiles and draws on every renderer; a constant an
  app does not use is not compiled in. `materialIconCodepoint` keeps to the
  2,231 base names - it is a map, kept whole by any build that looks a name
  up, and the variants would add 209 kB to a 352 kB `main.dart.js`.
  `Icons.extension` is spelled as Flutter spells it (it was `extension_`).
- A keyless widget's position id doubled in length at every stateful widget
  above it, because each pushed its whole id as its step of the path. Thirty
  deep - a dozen providers, a router, a shell - that is megabytes per id, and
  a keyless `Draggable`, which writes its id into the tree, hung the page.
  Each level now adds only its own step.
- A `ListTile`'s row is as wide as the tile, so `trailing` sits at the far
  edge instead of straight after the title.
- On web, a nested scaffold's floating button is pinned to its own corner
  rather than the window's (it sat on the outer scaffold's bottom bar), and a
  dropdown beside other things in a row - a list row's trailing - is as wide
  as its choices rather than the row.

### What migrating real apps onto it found

- **Right-to-left screens.** The framework had no notion of reading direction,
  so an app that was right-to-left in Arabic under Flutter came out
  left-to-right. The tree's root now carries `textDirection: 'rtl'`
  (`RootProps.textDirection`, put there by `UIBuilder.withTextDirection`;
  absent means left to right) and every renderer turns the screen round from
  that one prop, live: `dir="rtl"` on the web root with the stylesheet's
  start-and-end rules made logical, a `Directionality` on the Flutter host,
  `layoutDirection` on Android, a forced `semanticContentAttribute` on iOS.
  Rows run from the right, an app bar's leading and actions and a list tile's
  leading and trailing swap ends, a text field's prefix and suffix swap, the
  floating button moves to the bottom left and the app bar's back arrow
  points the other way. What names a side stays on it, as in Flutter:
  `padding` and `margin`, a `Positioned`'s `left`, an `alignment`'s x,
  `textAlign: 'left'`, canvas coordinates.
- In the widget layer, `Directionality` and `Directionality.of`/`maybeOf`;
  `MaterialApp` takes the direction from its locale (ar, fa, he, ps, sd, ur -
  Flutter's six - and ug, yi, dv), overridable from its `builder` as in
  Flutter; `EdgeInsetsDirectional`, `AlignmentDirectional`,
  `BorderRadiusDirectional` and `TextAlign.start`/`end` resolve against the
  direction they are built under instead of always left to right;
  `Positioned.directional` is new. Only the screen's direction reaches the
  renderers: a `Directionality` deep in a screen turns the values and the
  rows below it, not the platform's own controls there.
- **Breaking, on web:** a `Box` or `Stack` alignment's x is written as
  `left`/`right` rather than `start`/`end`, because it is physical; a `Stack`
  with no alignment is still top-start. **Breaking, on the Flutter host:** a
  tree that states no direction is drawn left to right even inside a Flutter
  app whose own `Directionality` is right-to-left - the direction is the
  tree's to say.
- **A `Row` is a row when it says so (breaking on the Flutter host).** There,
  a row with no `Expanded` in it was drawn as a `Wrap` and so was only as
  wide as its children, which put the two ends of a `spaceBetween` row side
  by side and left a trailing child in the middle. A row that says
  `mainAxisSize: 'max'` or carries a distributing `mainAxisAlignment` is now
  Flutter's `Row` - one line, full width, overflowing rather than reflowing -
  and the widget layer's `Row` says `'max'` wherever its width is bounded, as
  Flutter's default does. Only a row that asks for neither still reflows; a
  run of buttons that is meant to take a second line is a `Wrap`, which is
  what two of the examples became. On web, padding or a box around such a row
  now takes the width it is offered (it used to hug, leaving the row nothing
  to fill), and an `Expanded` in a row gives a max-size column the row's
  height instead of none.
- **Remote images are cached on Android, and an image can say what to show
  instead.** The Android renderer fetched a URL again on every rebuild and
  kept nothing; remote images now share the decoded-bitmap cache assets
  already had (keyed by URL and target size), sit over an HTTP cache on disk
  that the plugin installs itself if the app has none, are fetched once
  however many views ask, are decoded off the main thread, and are drawn at
  once - no alt text in between - when they are already in memory. iOS gains
  the same decoded-image cache over `URLCache`. An `Image` node takes an
  optional child (`UIBuilder.image(fallback:)`), drawn in place of the alt
  text while the image loads and if it fails, on all four renderers; the
  widget layer's `Image.errorBuilder` is how to give one - built once, up
  front, with an `ImageLoadFailure`, since a renderer cannot call back into a
  build. `loadingBuilder` and `frameBuilder` are accepted and not called.
- **`disabled` on a checkbox, radio and switch** is documented
  (`UIBuilder.checkbox(disabled:)`) and drawn the same everywhere: the label
  greys with the control on Flutter, Android and iOS, the web marks it for
  the stylesheet, and on web the three are now patched in place - ticked,
  unticked, disabled, enabled - instead of rebuilt, so a box toggled from the
  keyboard keeps the focus.
- On the Android emulator, right-to-left was looked at under an Arabic
  locale - app bar, bottom-navigation order, list tiles, tabs, calendar and
  switch all mirrored - and remote images loaded in list rows. What the disk
  cache does offline or at expiry was not examined, and nothing records the
  disabled controls on a device. The Swift compiles and none of this has
  been looked at on iOS.

### Two more apps, and what they needed

A food-reference app (about forty screens, eighty locales through `intl`, a
drawer, named routes, a barcode scanner, a Flutter web build) and a small
terminal-sessions client were moved onto the layer. Both analyze clean, their
test suites pass and their debug APKs build. On the Android emulator (Pixel 8,
Android 15) the first was walked through its search screen, a list, a detail
page, the drawer and navigation from it, the first-launch notice and the
barcode scanner - a Flutter widget in a `FlutterSlot` filling a native page,
showing the emulator's camera - and its `flutter build web` was opened in
headless Chrome as far as the search screen. The second was only seen at its
sign-in form: nothing past it was reached without a server and a key, so its
popup menus are covered by the tree tests alone. No iOS, no phone.
What they asked for that was not there:

- **`PopupMenuButton`, `PopupMenuItem`, `CheckedPopupMenuItem`,
  `PopupMenuDivider` and `showMenu`.** No platform here has a menu that takes
  arbitrary rows, so the menu is a dialog of them. `onOpened`, an entry's
  `onTap`, `onSelected` and `onCanceled` are called as in Flutter; the entry
  for `initialValue` is ticked; where the menu goes and what its surface looks
  like are accepted and not carried.
- **`Scaffold` has a state.** `Scaffold.of(context)`, `Scaffold.maybeOf` and a
  `GlobalKey<ScaffoldState>` reach `openDrawer`, `closeDrawer`,
  `isDrawerOpen` and their `endDrawer` twins; `onDrawerChanged` is called.
  `Drawer` and `DrawerHeader` exist. A drawer closes when the app moves to
  another page - it used to stay, a sheet over the page that replaced its
  own.
- **Named routes replace and clear.** `pushReplacementNamed`,
  `pushNamedAndRemoveUntil`, `popAndPushNamed` and `ModalRoute.withName`, on
  `Navigator` and `NavigatorState`. `pushNamed` returns Flutter's
  `Future<T?>`. A named route asked for while a pushed page is on screen is
  now pushed over it - it used to change the named history underneath, where
  nobody could see it. `ModalRoute.of(context).settings` carries the named
  route's `name` and the `arguments` it was reached with. With `routes`,
  `MaterialApp.home` is the route `/` (it was ignored, and an app with both
  and no `/` threw).
- **`LocalizationsDelegate` and `Localizations.of<T>`.**
  `MaterialApp.localizationsDelegates` is no longer ignored: the delegates
  that are this library's are loaded for the app's locale, again when it
  changes, and `Localizations.of<T>(context, T)` answers what they loaded -
  so an `intl`-style `AppLocalizations.of(context)` moves over with its
  import. It answers null until the load completes, where Flutter holds the
  first frame back; Flutter's own delegates in the same list are passed over.
- **`AppLifecycleListener`**, over the binding's observers.
- **Widgets that only have to be there:** `Hero` (no flight - pages have no
  transition), `MouseRegion` and `SystemMouseCursors` (no renderer reports
  hover), `FadeTransition` (the animation's value when built),
  `ModalRoute.buildTransitions` (never called),
  `ThemeData.estimateBrightnessForColor`, and `cursorColor`,
  `enableInteractiveSelection` and the other caret parameters of `TextField`
  and `TextFormField` (accepted and not carried).
- **`flutter build web` is a build.** `run_app.dart` picked the DOM renderer
  whenever the program ran in a browser, Flutter's bootstrap or not. A
  program with `dart:ui_web` - a Flutter web build - now takes the Flutter
  entry point and is painted by the Flutter renderer, with its Flutter
  plugins working as in any Flutter web app. `dart compile js` is the DOM
  build, as before. This is the web target for an app whose plugins plain
  dart2js cannot link.
- **`InputDecoration.icon` is drawn.** It was dropped, and with it whatever
  it did when tapped - a search field's scan button. It is laid out before
  the field, as any widget, with the field taking the rest of the row.
- **Android: a `Padding` around a row or a text field fills its column.** In
  a column that does not stretch, the padding hugged its content, which gave
  the row inside no width to fill and the `Expanded` in it none to take: a
  field beside a button was drawn a few dp wide. Found on the emulator; the
  iOS and DOM renderers were not checked for the same.

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
- The package is not on pub.dev. The repository is public and both pubspecs
  and the podspec point at it, so a git dependency works; `dart pub publish
  --dry-run` reports no warnings, so releasing is a decision rather than a
  task.

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
