# What's left before this is production ready

An honest inventory, written from what the code and the test suite actually
show. Each item says why it matters and what "done" looks like; the ordering
inside each group is roughly the order I would do them in.

The short version, as of 2026-10-03: **the web target is close to ready, the
Flutter-hosted target is ready for internal use, the native-view target is
proven on Android, and iOS is behind its own source.** The Android renderer is
device-verified on a physical Android phone (Android 17, 2026-09-18): all
seven native example apps run with events round-tripping, including every
control (Checkbox/Radio/Toggle), overlays, the 10k-row lazy list, swipe
actions, and typing into an event-bound field. Since then the widget layer
grew to most of what a Material app uses and three migrated production apps
were walked screen by screen on a Pixel 8 emulator (API 35). iOS ran the
counter/design-system/inbox on a physical iPad and five flows on a simulator
- for the vocabulary as it was then. **The Swift for everything added since
compiles and, on 2026-10-09, drew the examples on a simulator with nobody
looking and none of the three apps on it**, so the largest single risk is still
iOS, ahead of the things nothing has built yet (map and camera on Android,
explicit animation). §6 is the list of what is open after that work.

---

## Authoring: the Flutter-shaped widget layer

`package:dart_not_native/widgets.dart` lets an example be written as a plain
Flutter app - `StatelessWidget`/`StatefulWidget`/`State.setState`, `Scaffold`,
`Column`, `TextField`, `showDialog`, `Navigator.of(context).pushNamed`, a routed
`MaterialApp` - that differs from a real Flutter app only in its import: swap
`package:dart_not_native/material.dart` (Flutter's engine) for `widgets.dart`
and the same widgets render through the native Android/iOS views or the web DOM.
It is a thin, Flutter-free layer over the `WidgetNode` protocol: widgets emit
nodes, `runApp` mounts them on a `NativeUIApp` host that keeps each `State` alive
across rebuilds, and callbacks/overlays/routing reuse the same reconciler and
event bindings the low-level API uses.

**Every example app is now written this way** (counter, calculator, todo, inbox,
the android/ios/web and design-system showcases, both text-input showcases,
routing, i18n, storage), verified by the golden, smoke and Flutter-render
suites, and the counter is device-verified on both an emulator and a simulator.
The three per-platform counter variants collapsed into one file.

**The layer took Flutter's shape on 2026-10-03.** What had been ~90 widgets
covering what the examples used became most of what a Material app uses, under
Flutter's names, signatures and semantics, so that an existing Flutter app
migrates by changing its imports rather than being rewritten: `Container`,
`Stack`, `Positioned` and the clipping and transform widgets over a new `Box`
node; `SingleChildScrollView`, a `ListView` and `GridView` that scroll
themselves, `RefreshIndicator`; `Navigator.push` with routes that keep their
`State`; Flutter's `Form`/`FormField`/`TextFormField`; `ThemeData`,
`ColorScheme.fromSeed` and `TextTheme` behind `Theme.of`; `GestureDetector`,
`Draggable`/`DragTarget`, `Dismissible`; `CustomPaint` with Flutter's
`Canvas`, `Paint`, `Path` and `TextPainter`; `MediaQuery` and `LayoutBuilder`
fed by a renderer's viewport event; `Ticker`; `KeyboardListener`;
`Directionality` and the directional geometry classes; dropdowns, date and
time pickers, bottom navigation and a rail, `TabBar`/`TabController`. The
protocol gained twelve node types to carry it (`Box`, `Stack`, `Positioned`,
`Scroll`, `Icon`, `Canvas`, `Dropdown`, `DatePicker`, `TimePicker`,
`BottomBar`, `BottomNavigation`, `FlutterSlot`), a root-level text direction
and renderer events. Two companions came with it: `router.dart`, which is
go_router's API, and `packages/dart_not_native_bloc`, which is flutter_bloc's.

Where the old layer disagreed with Flutter it now agrees, which broke existing
code in the places the changelog lists first - a `Scaffold`'s body does not
scroll, `ListView.builder` takes `(context, index)`, `Theme.of` returns a
`ThemeData`, `Form` is Flutter's and the framework's model is `FormModel`.
Each widget's doc comment says what it does not carry; INTEGRATION.md §8.9
gathers the ones a user would see, and §6 below the ones worth closing.

Proven by: the three suites, the tree goldens regenerated for every example,
and three real apps - a reminders app in twelve locales, eighteen small games,
a planner with a web build - migrated onto it and run on an Android emulator.
Not proven on iOS at all.

Entries below that this superseded are marked where they stand.

Still to do here:
- ~~Button `size` was best-effort~~ - fixed 2026-09-19. It was worse than
  best-effort: **only the web drew it**. `DSButton.primary(size: 'lg')` and
  `size: 'sm'` produced identical buttons on Flutter, Android and iOS, which is
  three renderers quietly ignoring a property the design system has always
  sent. There is one scale now - sm 28/12/12, md 36/14/16, lg 44/16/24 (height,
  text, horizontal padding) - written once in `UIBuilder.button` and drawn by
  all four, verified by eye on an emulator and a simulator.

  The facade reaches it too, in Flutter's own words:
  `ElevatedButton.styleFrom(padding:, minimumSize:, textStyle:)` and the same on
  `TextButton` become `paddingHorizontal`/`paddingVertical`, `minWidth`/
  `minHeight` and `fontSize` on the node, which every renderer honours over the
  named size. A button's padding is symmetric in the protocol, so one edge of
  each axis travels - `EdgeInsets.symmetric`, which is what button padding is,
  loses nothing. Verified by eye on both natives: a tiny button, a 260x56 one
  and a 48-high flat one, each the shape it asked for.
- ~~`Column.mainAxisAlignment` was dropped~~ - fixed 2026-09-19. The protocol
  carried it for a Row and not for a Column, so a screen that asked for its
  content to be centred got it at the top on three of the four renderers (the
  web's `Center` happened to do it anyway). The node carries it now - 'start'
  stays out, being the absence of distributing - and every renderer does the
  thing its own layout system calls for: `justify-content`, Flutter's own
  `mainAxisAlignment` with `MainAxisSize.max`, gravity or weighted spacers on
  Android, `.equalSpacing` or spacer views on iOS.

  Distributing needs space to distribute, which neither native scaffold was
  giving: both put the body in a scroll view sized to its content. A body that
  places its children in the space it is given - a `Center`, or a `Column` with
  an alignment - now gets at least the viewport (Android's `fillViewport`, a
  `greaterThanOrEqual` height constraint on iOS), and still scrolls when it is
  taller.

  That exposed a second bug, on Android, older than this work: a `SizedBox`
  built `ViewGroup.LayoutParams`, and a column keeps the params a child arrives
  with only when they are `LinearLayout.LayoutParams` - so **every SizedBox
  inside a column or row had its height silently dropped**. Invisible while the
  column hugged its children; with the column filling, the box swallowed the
  screen and pushed the row off it. Fixed at the source.

  Verified by eye on all four: the counter example is centred on an Android
  emulator, an iPhone simulator and in Chrome, and a Flutter widget test
  asserts the Column it builds.
- ~~A non-uniform `EdgeInsets`~~ - fixed 2026-09-19. `EdgeInsets.symmetric` and
  `.only` used to collapse to their *largest* edge, so
  `symmetric(horizontal: 16)` padded the top and bottom by 16 as well. The node
  now carries one number when every edge is the same and four when they are
  not, and all four renderers read both. Verified by eye on an Android emulator
  and an iPhone simulator - one probe screen per edge - because this is
  exactly the kind of change that passes its tests and looks wrong.
- The facade covers what the examples use, and as of 2026-09-20 the list of
  missing widgets is empty - `GridView`, `Slider`, `Tabs`, `InheritedWidget`
  and now **motion**, in the one form that fits the protocol. *(True of the
  examples. Three real apps asked for a great deal more, which is the
  2026-10-03 entry above; what is still missing after that is §6.)*

  **`AnimatedOpacity` landed 2026-09-20.** The protocol says what a screen
  *is*, not how it got there, so a renderer animates the difference it sees:
  the first render sets the opacity, a later one that changes it fades from
  where the view already was. A CSS transition on web, Flutter's own
  `AnimatedOpacity`, `animate().alpha()` on Android, `UIView.animate` on iOS.
  Caught mid-flight on an emulator and a simulator - one second into a
  two-second fade, the card is half there on both.

  Getting there turned up a sharp edge worth knowing about: **a new node that
  holds children has to be added to the native reconcilers' child mapping**
  (`childViews` in Kotlin, `childViews` in Swift) or the node is rebuilt
  instead of patched. Nothing fails - the screen is correct - it just jumps
  instead of animating, and a text field inside one would lose focus. That is
  how the first fade behaved, and only looking at it showed why. It is a test
  now: `renderer_coverage_test` reads both natives' `childViews` between its
  markers and fails if a motion node is missing from either.

  **`AnimatedContainer` and curves landed 2026-09-20**, which is the rest of
  the motion breadth: a box whose **size** and **colour** move, and a `Curve`
  carried by both motion nodes - `linear`, `ease`, `easeIn`, `easeOut`,
  `easeInOut`, five because that is what all four renderers already have. A
  CSS transition naming each property, Flutter's own `AnimatedContainer`, a
  `ValueAnimator` stepping the layout params and an `ArgbEvaluator` stepping
  the colour on Android, and constraint constants inside `UIView.animate` on
  iOS. Caught mid-flight on both again - one second into a two-second move the
  box is half-grown and half-blue on the emulator and the simulator.

  Two things that only showed up on a device. The child is **centred** in the
  box on all four renderers, which is a deliberate difference from Flutter
  (a `Container` passes its own constraints down) - four layout systems
  disagreeing about a child that does not fill the space is worse than one
  documented rule. *(Superseded 2026-10-03: the `AnimatedContainer` widget
  renders a `Box` node with `animateMs` and no longer centres its child, as
  Flutter's does not. The `AnimatedContainer` node is still drawn, centring
  and all, for a tree that builds it by hand.)* And on iOS, `removeAllAnimations()` in the fade's patch was
  tearing the *position* animation off a sibling that a growing box was moving,
  so the faded label snapped to where it was going while everything around it
  slid; it now removes only the fade's own `opacity` animation.

  Left: motion is size, colour and opacity. A position that moves
  independently of layout, a rotation, and a padding or alignment that eases
  are all still jumps - each would need the same treatment in four layout
  systems, and none of them is what an app reaches for first. *(Partly closed
  2026-10-03: a `Box` animates its transform as well, which is what
  `AnimatedScale`, `AnimatedRotation` and `AnimatedSlide` are built on.
  Padding, margin, alignment and borders still land at once - §6.2.)*
  **`InheritedWidget` landed 2026-09-20**, with `Theme` on top of it: a value
  handed to a subtree and read back with
  `context.dependOnInheritedWidgetOfExactType<T>()`, Flutter's name and
  Flutter's meaning minus the bookkeeping - a change rebuilds from the root
  here, so the dependency *is* the rebuild and `updateShouldNotify` is accepted
  without being consulted. `runApp(appTheme:)` now puts a `Theme` at the root,
  so a screen can read the palette the renderers draw with
  (`Theme.of(context).primary`) instead of repeating it.

  One caveat, written into the class: `Theme.of` returns the theme the app
  *declared*, not the appearance on screen. Each renderer resolves light or
  dark from the platform at render time and the widget layer is never told
  which it chose; `Theme.of(context).dark` is there for an app that needs to
  pick deliberately.

  *(Both superseded 2026-10-03. `Theme.of(context)` returns a `ThemeData`, as
  in Flutter, and the palette is `Theme.of(context).appTheme`. And the widget
  layer is told now: a renderer's viewport event carries `dark`, so
  `MaterialApp(theme:, darkTheme:, themeMode: ThemeMode.system)` hands its
  pages the theme for the appearance actually on screen.)*
  **`Tabs` landed 2026-09-20**: a strip of labels with one selected, drawn as
  each platform's own way of choosing one of a few things - Material tabs on
  Android and in Flutter (scrollable past three), a segmented control on iOS,
  a `role="tablist"` of real buttons on web. Framework-specific rather than
  Flutter-shaped, like `Tr`, and the docs say so: Flutter drives a `TabBar`
  from a `TabController`, while the selection here stays in the app like every
  other piece of state - the bar reports a tap and the next tree says which tab
  is selected, so the bar can never disagree with the screen below it. The bar
  only; the content is the app's own tree. Tapped through on an Android
  emulator and an iPhone simulator. *(2026-10-03: Flutter's own `TabBar`,
  `TabBarView`, `TabController` and `DefaultTabController` exist beside it
  now, over the same node. A tab change does not animate and there is no
  swipe between pages.)*
  **`GridView` landed 2026-09-19**: `GridView.count(crossAxisCount:,
  mainAxisSpacing:, crossAxisSpacing:, childAspectRatio:)`, equal cells in
  equal columns. Web is a CSS grid; the Flutter host is `GridView.count`
  shrink-wrapped, since the screen around it already scrolls *(until
  2026-10-03: a `Scaffold`'s body no longer scrolls, and `GridView` - now
  with `.builder`, `.extent` and the two delegates - scrolls itself)*; both natives get
  a frame-positioned view of their own (`GridLayoutView`, `GridView`), because
  a cell's size comes from the width available rather than from what is inside
  it and no stock container does that. Looked at on an Android emulator and an
  iPhone simulator (2026-09-20) - 3 square columns with a ragged last row, and
  2 columns twice as wide as tall, matching cell for cell.

  The screenshots also showed a difference that was not the grid's, now fixed
  (2026-09-20): a `Card`'s content sat at the top on Android and in the middle
  on iOS, wherever a card was given more room than its content - a grid cell, a
  row of cards of unequal height. iOS pinned its content stack to all four
  edges, so a stretched card stretched the stack, and a stretched label centres
  its text. The bottom pin is now weaker than a label's hold on its own height:
  a card that is being stretched leaves its content at the top, and a
  free-standing card still hugs it. Top is what Android, the web and Flutter
  all draw.
  **`Slider` landed 2026-09-19**: a `Slider` node in the protocol, each renderer
  drawing the platform's own (a range input, Flutter's `Slider`, Material's on
  Android, `UISlider` on iOS), `onChanged` as the thumb moves and `onChangeEnd`
  when it is let go. Both natives *patch* the slider rather than rebuild it,
  and neither writes a value back while a finger is on it - a rebuilt or
  overwritten thumb would stop following the drag. Dragged on an emulator and a
  simulator to check exactly that, including the snap to `divisions`.
- ~~Two keyless `StatefulWidget`s of the same type would share state~~ - fixed
  2026-09-19. A widget without a `Key` is now identified by where it sits: the
  path of slots from the root (a child's index, a Scaffold's `body`, the route
  or dialog being drawn) plus its type. Two counters side by side are two
  counters, and a screen on one route no longer opens on another route's
  numbers. What remains is Flutter's own rule rather than a gap: a keyless
  widget *is* its position, so a row that moves hands its state to whatever now
  stands where it stood - give rows that move a key.

---

## Platform status

✅ works and is tested on that platform · 🟡 the code exists and builds (or
should), but has never run there · ❌ missing, or a stub

| Feature | Android | iOS | Web | Notes |
|---|---|---|---|---|
| UI renderer - the vocabulary as of 2026-09-24 (47 node types) | ✅ | ✅ | ✅ | Android is device-verified on a physical Android phone (Android 17, 2026-09-18): all seven example apps run natively with events round-tripping (see 1.1). iOS caught up on 2026-09-21: six example apps driven by hand on a simulator, two layout bugs found and fixed - the screens have been *looked* at now, though on a simulator rather than a phone, and the iPad pass before it covered three of them on real hardware. Web is tested in Chrome with DOM goldens (1.1) | **The iOS ✅ is for the Swift as it was then; the file has since grown by the rows below, which have had one automated simulator run and no eyes (§6.1)**
| The twelve node types added 2026-10-03: `Box`, `Stack`, `Positioned`, `Scroll`, `Icon`, `Canvas`, `Dropdown`, `DatePicker`, `TimePicker`, `BottomBar`, `BottomNavigation`, `FlutterSlot` | ✅ | 🟡 | ✅ | Android: on a Pixel 8 emulator (API 35, debug builds), by hand, through three migrated apps walked screen by screen - boxes, stacks, scrollers, icons and dropdowns throughout; `Canvas` as a timer-driven game, the other game boards and a donut chart; bottom navigation, and its rail in landscape; a long-press drag onto a drop target; an AdMob test banner through the `FlutterSlot` hole at its 320×50dp. **`DatePicker` and `TimePicker` were not exercised: no app opened one.** Not on a phone. In the device lane since 2026-10-09 (a free-form tree and a screen under each picker), which has not yet run on Android. iOS: **on an iPhone 18 Pro simulator (iOS 27.0, 2026-10-09) the device lane draws all twelve; the controls gallery was walked by hand, which found and fixed five layout bugs (§6.1), and a dropdown and both pickers were opened and returned a choice. A `FlutterSlot` has drawn only its fallback, and no migrated app has run**. Web: browser tests per family (`box_test`, `stack_scroll_test`, `canvas_test`, `choosing_test`, `app_chrome_test`); a `FlutterSlot` draws its fallback there. The Flutter renderer has widget tests for all of them |
| Right-to-left (`RootProps.textDirection`) | ✅ | 🟡 | ✅ | Web and the Flutter host are tested (`text_direction_test`, `flutter_text_direction_test`). Android: looked at on the emulator under an Arabic locale (2026-10-03) - app bar, bottom-navigation order, list tiles, tabs, calendar and switch all mirrored; swipe actions are not (§6.3 item 6). The Swift compiles; right-to-left has not been looked at on iOS |
| Remote image cache, and an image's fallback child | 🟡 | 🟡 | ✅ | Tested on web and Flutter. Android: remote images loaded in list rows on the emulator; what the disk cache does offline or at expiry was not examined, which is why this stays 🟡. Compiled and not examined on iOS |
| An event answered by the build it was raised against | ✅ | 🟡 | ✅ | Android sends the tree's build number back with each event (found on the emulator, where a list's size report was landing on a row's tap). The Swift to do the same compiles; the stale-callback case has not been tried on iOS. The web and Flutter renderers name the build they are showing too - the Flutter host builds its widgets a frame after a render |
| System back | ✅ | 🟡 | ✅ | Native via `system_back` channel; web via browser history. Android Back verified closing an overlay on the Android phone (2026-09-18) |
| Routing, forms, i18n, design system | ✅ | ✅ | ✅ | Pure Dart, unit tested; on a device they depend on the renderer row |
| Dialogs, bottom sheets, snackbars | ✅ | ✅ | ✅ | `Overlay`/`Dialog`/`BottomSheet`/`Snackbar` nodes; Back closes the topmost one. Device-verified on iOS (iPad) and Android (2026-09-18): sheet → stacked confirm dialog → delete pops both → undo snackbar restores (1.3) |
| Long lists (`LazyList`) | ✅ | ✅ | ✅ | Windowed rows with a fixed height. Device-verified scrolling the 10k-row inbox on iOS (iPad) and Android (2026-09-18). Frame times measured on two Android devices (release): the Android phone scrolls at 0.7-0.8% jank with a 19.7ms worst frame - it holds 60Hz (1.4) |
| Storage interfaces (`StorageService`, `SecureStorageService`) | ➖ | ➖ | ✅ | Web ships `LocalStorageService` and `WebSecureStorage` (AES-GCM); on mobile the app wraps a package (2.3) |
| Web view | ✅ | ✅ | ✅ | `WebView` node, drawn with the platform's own browser view; the Flutter target shows a placeholder, since it would need `webview_flutter` (2.2) |
| Map view | ❌ | ✅ | ✅ | `MapView`: MapKit on iOS and raster tiles on web, both free and looked at on a simulator and in Chrome (2.2). Android draws a placeholder naming the SDK and API key it would need, as does the Flutter host |
| Camera preview | ❌ | 🟡 | 🟡 | `CameraPreview`: `AVCapture` on iOS and `getUserMedia` on web, frames never touching Dart. The permission, the session and the failure reports are proven on a simulator and in a browser; **neither has been seen showing a picture here** - that needs real hardware (2.2). Android draws a placeholder naming CameraX |

➖ not provided by the framework, on purpose.

Update a row when its status changes; a ✅ needs a test or a device run behind
it.

### Device services

The framework does not wrap services that draw nothing: an app uses the pub.dev
package directly. On Android and iOS a Flutter engine runs underneath, so any
Flutter plugin works. The web build is plain dart2js with no Flutter engine, so
only pure-Dart packages work there; for the rest, call the browser API through
`package:web`.

| Service | Android / iOS | Web |
|---|---|---|
| Key-value storage | `shared_preferences` | `LocalStorageService` (this package) |
| Secure storage | `flutter_secure_storage` | `WebSecureStorage` (this package) |
| HTTP | `http` or `dio` | same packages - both are pure Dart |
| Biometrics | `local_auth` | WebAuthn via `package:web` |
| Location | `geolocator` | `navigator.geolocation` via `package:web` |
| File and image picking | `file_picker`, `image_picker` | `<input type="file">` |
| Local notifications | `flutter_local_notifications` | the Notification API |
| Background work | `workmanager` | a service worker |
| Crash reporting | `sentry_flutter` | `sentry` (pure Dart) |
| Analytics | `firebase_analytics` | the vendor's JS snippet |

---

## 1. Blockers — a real app cannot ship without these

### 1.1 Run the Android and iOS renderers on a device

Both `NativeUIRenderer.kt` and `NativeUIRenderer.swift` first ran on 2026-09-13;
before that neither had ever executed (the Swift could not even be built on
Linux). The counter example now renders as native views on both — UIKit on an
iOS simulator, Android Views on an emulator — with its buttons round-tripping
taps back to Dart (iOS `⊕`/`−`: 0→3→2; Android FAB/decrement: 0→2→1). That
exercises the core layout and control nodes (NavigationStack/Scaffold,
VStack/HStack, Text, Button/MaterialButton, Spacer, AppBar/Toolbar, FAB). On
Android two more example apps were run natively: the showcase (`ListView`/
`ListItem` with titles and subtitles render) and the text-input showcase
(`TextField`/EditText renders in all four variants — hint, labelled, obscured,
disabled — and accepts typing). The rest — Checkbox, Radio, Toggle, images,
cards, the overlays and the lazy list — is still unproven on a screen, as is
everything but the counter on iOS. `renderer_coverage_test` only proves that
every node type appears in each dispatch, not that it lays out correctly or that
its events reach Dart. The Flutter-hosted path also passes `integration_test`
on both an iOS simulator and an Android emulator.

**Since 2026-09-19 a device lane draws the whole vocabulary automatically**
(§4): `integration_test/native_renderer_test.dart` hands both native renderers
one of every node type and all ten example apps and expects them to report
nothing they could not draw. It is green on an Android emulator and an iPhone
simulator, which is the first time every node type has been through the Swift
renderer at all. It says nothing about whether any of it *looks* right - the
screens below are still the only evidence of that.

Confirmed on a device: **1.2 is real.** Typing into an event-bound `TextField`
does not work — the field's own focus/change event triggers a full-tree
rebuild that drops focus and recreates the EditText, so the next keystroke goes
nowhere; and text held only in a native field (one with no Dart-side handler) is
wiped whenever any other event rebuilds the tree.

Neither ran out of the box. Two bugs the first run surfaced, now fixed:
- **Android needed a Material theme.** The renderer builds `MaterialButton`,
  `MaterialToolbar`, the FAB and cards, which throw unless their `Context`
  carries a `Theme.MaterialComponents`; the Flutter host activity's theme is
  not one, so every render threw and `renderTree` swallowed it, leaving a blank
  screen. Fixed by building Material views against a `ContextThemeWrapper` in
  `NativeUIRenderer.kt` (keeps the framework's zero-app-setup promise). Note the
  swallowed error: `NativeUIApp.render` ignores the string `render` returns, so
  a native render failure is silent — see 2.4.
- **`BackgroundTasksPlugin.kt` did not compile** — it uses WorkManager but the
  package declared no `androidx.work` dependency; added to the package
  `build.gradle`.

Until the commit that taught them to read props, neither native renderer
received any at all: Dart sends
`{type, props, children}` and both read props straight off the node, so every
title, label and event id was missing. Both now flatten the tree once per
render, and `renderer_coverage_test` pins that - but it is a sign of how much
has never been looked at on a screen.

Expect real work here: layout constraints, `Expanded` weights, scrolling
behaviour, keyboard handling, the image loading threads, and the new overlay
and lazy-list code (insets, the sheet's drag against its own scrolling, restored
scroll offsets).

**The iOS screens have been looked at (2026-09-21).** With Xcode reinstalled
and the simulator back, the four apps this section still listed as unseen -
the calculator, the todo app, the text-input showcase and the components
showcase - plus routing and the design-system showcase were driven by hand on
an iPhone 17 Pro simulator (iOS 26.4): 7+8=15 with the display patching in
place, a todo typed in and added with the field keeping focus, a checkbox
struck through, the middle row of three deleted with the other two keeping
their state, all five field variants with focus/change/submit round-tripping
and the character count updating as the keys land, the keyboard scrolling the
focused field into view, three showcase pages with the FAB counting taps, and
routing pushing /users, listing it and coming back.

Two layout bugs, both found by looking rather than by a test:

- **A row that asked to sit at the end stayed at the leading edge.** Only
  columns inserted the spacer that does that; a row set `.fill` distribution
  and pushed nothing, so the calculator's display - a `Row` with
  `MainAxisAlignment.end` - sat on the left, where Android and the web put it
  on the right. Rows and columns now share one `distribute` step, and
  `spaceBetween` puts a spacer *between* each pair rather than leaning on
  `.equalSpacing`, which distributes slack and squeezes the children when
  there is none.
- **A row was only as wide as its children.** Flutter's `Row` takes all the
  width it is offered (`mainAxisSize.max`) and Android's fills its parent, but
  a `UIStackView` aligned at one edge hands each child exactly what it asked
  for - so a card's row of an email and an *Open* button came out email-wide,
  the card shrank to match, and the space the app asked to put between them
  had nowhere to go. A row now carries a width it cannot have at a priority
  anything can beat, so it grows until the first thing that *does* have a
  width stops it. The routing app's user cards are full width and read like
  the other three renderers now.

Both fixes needed the reconciler to learn about spacers: they are a
`FlexibleSpacer` type, `childViews` filters them out, and the keyed reconcile
steps past a leading one - otherwise a stack that aligns its children patches
every row against the wrong view. Finding the second bug took tinting the row,
the label and the card in three colours and reading the frames off a
screenshot; three readings of the code had each produced a plausible wrong
answer.

**Done when:** every example app runs on an emulator and a device on both
platforms, and the events come back. *(Progress — Android is now DONE on a
physical device: on an Android phone (Android 17, 2026-09-18) all seven native example
apps ran natively with events round-tripping — counter (0→3→2), calculator
(7+8=15), todo (add via typing, checkbox flips + strikethrough in place, delete
middle keeps + moves the other keyed rows), text-input (all four field variants;
typing into the event-bound Message field kept focus and updated the char count
in place — 1.2 on a device), the design-system showcase (all 5 pages; Checkbox,
Radio and Toggle all round-trip in place — the first device proof of these on
Android), the inbox (10k-row LazyList virtualization + sheet/dialog/snackbar/undo
+ swipe-to-delete, see 1.3/1.4), and the components showcase (3 pages, counter
FAB). No new Android bugs surfaced. On a physical iPad (iOS 26.7) the counter,
the design-system showcase and the inbox all ran natively; the device pass there
surfaced and fixed three iOS bugs (a renderer-channel attach race, a dark-mode
canvas, a determinate progress ring). Still remaining: the iOS apps have been
seen on a simulator, not on a phone, and the storage and i18n examples have no
native entry point to run them from.)*

*(Progress — a second pass on the Android phone on 2026-09-24, this one automated: both
integration files and all five Android Maestro flows ran on the phone rather
than an emulator - 15 integration tests, and `a11y_android`, `counter`,
`focus`, `inbox` and `textinput_android` all green. It found a bug an emulator
had never shown, and a plain one: every app bar drew **behind** the clock and
the status icons. The window has been edge-to-edge since Android 15 and this
phone is Android 17, so a bar at the top of it starts at y=0 unless it pads
itself past the inset - which the dialog, sheet and snackbar surfaces already
did and the app bar never had. Three of the five flows failed on it, each
asserting a title that was being drawn and could not be read. Fixed, pinned by
two source-level tests, and measured back on the phone: bar 0..268, title
159..230, thirty-eight pixels either side of it.

Two things this pass confirmed on hardware rather than an emulator, both of
which the entries below had left open: the control tints (the checkbox and the
switch take the brand blue when on and the quiet grey when off, and the status
line under each round-trips) and keyboard avoidance (tapping the showcase's
Message field, the low one, lifts it from y=1976..2243 to y=1144..1411, clear
of the keyboard, with the caret in it).

The *bottom* edge turned out to need nothing, which is worth writing down
because it looks like it should: content stops above the navigation bar in
both modes, measured on the phone - the scaffold ends at y=2337 under gestures
and y=2274 under three buttons, against a 2400 screen. It clears the bar for a
reason nobody wrote down, though: `avoidKeyboard` pads from the visible
display frame, and that frame excludes the navigation bar as well as the
keyboard. Nothing else insets the bottom, so a rewrite of that function in
terms of the IME inset - which its name invites - would put the content back
under the bar. Said out loud in its doc comment now, and pinned by a test.

*(Progress — the iOS half, 2026-09-24. It could not start at all: `Runner`
quit the instant it launched, on the simulator and on the iPad, with
"Application failed to launch: UIScene life cycle is required for apps built
with this SDK". An app built against the iOS 26 SDK must adopt the scene life
cycle and this one had no `UIApplicationSceneManifest`; Flutter had been
printing the warning on every build for a while, and on this SDK it became a
refusal. Fixed by naming the engine's own `FlutterSceneDelegate`. **The
ios-build CI lane would never have caught this** - it compiles, and this
breaks at launch, which is the same gap the device flows exist to close.

Then the app bar, the same edge as Android failing the other way: iOS never
drew the title behind the clock, because the scaffold started at the safe
area - but that left the strip above the bar painted in the surface colour, a
blue bar under a white band instead of reaching the top the way a
UINavigationBar does. The column now starts at the container's top when there
is a bar to fill that strip, and the bar insets its own title against its safe
area. Title unmoved at 74..98 of 874 points, bar now starting at 0 rather
than 59. Two source-level tests beside the Android pair, each weakened to
watch it fail.

All five iOS flows pass on an iPhone 18 Pro simulator, and the release build
runs on the physical an iPad (iOS 27) - which is what proves the
launch fix on hardware, and where the blue was confirmed reaching the top by
eye. Re-run at the end of the day against the finished tree: `a11y_ios`,
`counter`, `focus`, `inbox` and `textinput_ios` all green again, which matters
because the first run predated the bottom-edge change - the layout was
measured after that, the interaction paths were not, and now both are.

Note that a *debug* build cannot be opened from the home screen on a device at
all ("Cannot create a FlutterEngine instance in debug mode without Flutter
tooling"), which looks exactly like a crash and is not one.

The bottom edge started out unlike Android's and was made to match. The
scrolling body ran to the screen's bottom edge, under the home indicator,
while the FAB stopped clear of it at 768..824 - the chrome was pinned to the
safe area and the scroll view was not, which is Apple's own model. Android
stops the whole scaffold above the navigation bar, so the two platforms
disagreed about the same screen, and a renderer that draws one screen for four
platforms should not: the scaffold's column is pinned to the safe area at the
bottom now, on both. Measured on an iPhone 18 Pro simulator, the inbox's
lowest drawn pixel moved from 874pt - the last row of the screen - to 810pt,
against a safe area that starts at 840. The keyboard still works out, because
shortening the container lifts it clear of the indicator and the inset
collapses exactly when the keyboard has taken that space.)*

The iOS flows cannot be run on the iPad at all, which is worth knowing before
anyone plans on it: Maestro drives a physical iOS device through an XCUITest
driver it builds itself, and that build fails three ways here - its bundle id
is mobile-dev-inc's and cannot be registered to another team, no profile
exists for it, and its deployment target of 14.0 is below the 15.0 this Xcode
supports (an upstream break with Xcode 26, Maestro issues #3608 and #3218).
`--apple-team-id` - undocumented in this version's help - gets past the CLI's
own complaint and into the build, where those are waiting. The first two were
tried: patching Maestro's jars cleared both, and the build then failed on
`MaestroDriverLib/Info.plist` instead, because that target compiles six
sources and the release ships one of them. The library is not in the package,
so the wall is real rather than a matter of configuration. Patch reverted. So the iOS device story is the flows on a simulator plus
the app installed and driven by hand on the iPad, and the Android one - where
the flows do run on the phone - stays the stronger of the two. Written up in
`maestro/native/README.md`.

Still open on the flows themselves: before the fix, `textinput_android`
asserted the same "TextInput Showcase" title that `focus` asserted and passed
where `focus` failed. Both run the same entry point, so the two disagreed about
one occluded title - Maestro's idea of "visible" is evidently marginal at that
degree of overlap. It has not been chased, because the fix made it moot.)*

*(Progress — three real apps on an emulator, 2026-10-03. Everything above is
about the framework's own examples. Three migrated Flutter apps - reminders,
games, a planner - were walked screen by screen on a Pixel 8 emulator (API
35), which is the first time screens nobody here designed for the renderer
went through it, and the first time the twelve new node types were on a
screen at all. What it found in the Android renderer is in the changelog under
"Three real apps on an Android emulator": an event landing on the wrong
callback once a list's window had moved (fixed by sending the build number
with the tree and back with each event), forced capitals on buttons, a hugging
column collapsing to its narrowest child, a clipped box hiding its child
behind an empty first outline, the status icons unreadable over a coloured
bar, Material's purple showing through on five controls, and the rest of
about thirty that only showed on a device.

What was seen working, across two passes that day (Android 15, debug builds,
software GPU): the games app's home grid and all eighteen games, each opened
and played a few moves; the reminders app's first-run permission flow, its
four bottom-navigation tabs, add, delete and undo, a dashboard with a canvas
donut chart and a composed month calendar, a language switch and dark mode;
the planner, over an in-memory backend - forms with validation, dropdowns,
swipe-to-delete, checkbox tiles, dialogs, bottom navigation, and the
navigation rail in landscape. Under an Arabic locale the app bar, the
bottom navigation's order, list tiles, tabs, the calendar and a switch all
mirrored. A long-press drag of a row onto a target delivered its data. A
scheduled local notification was posted by an app running on the renderer, so
plugins work under `FlutterFragmentActivity`. Remote images loaded in list
rows. An AdMob *test* banner loaded and showed through the `FlutterSlot` hole
at exactly its 320×50dp; it stayed put while the screen behind scrolled, was
covered while a pushed page was open and came back on Back, and taps elsewhere
kept working. A timer-driven game canvas ran at 506 frames in about 11 s, 17%
janky, p50 16 ms, p90 29 ms, p99 34 ms - a debug build on a software-rendered
emulator, so a sign that it runs and not a performance claim for hardware.

What nobody did: tap the ad itself; put a slot inside a scroller, so the
documented scroll lag was not exercised; open a date or time picker (no app
uses one, so those two nodes are unverified on a device); press a hardware key
(`dnn:key`); judge how pull-to-refresh feels; look at what the image disk
cache does offline or at expiry.

What that pass was not: a physical phone, an automated run, or iOS. The
Maestro flows and the integration lane were not extended to the new screens,
so nothing re-checks them. And the iOS half of all of it is Swift that has
drawn the examples on a simulator, with one screen of them looked at
(2026-10-09) -
the "Done when" above was met for the examples on 2026-09-24 and is open again
for the vocabulary as it stands. §6.1.)*

### 1.2 Diff the native view trees

Both renderers used to call `removeAllViews()` / `removeFromSuperview()` and
rebuild everything on every render, losing scroll position, text selection and
focus each time. **Both now diff (2026-09-14): a render that kept the tree's
shape patches the changed leaves in place and leaves every other view - and the
focus, caret, keyboard and scroll it holds - untouched.**

`renderTree` keeps the last normalised tree and its root view. The next render
walks the two trees together (`tryPatch`): a node whose type and props match
keeps its view and recurses into its children; a changed leaf is re-derived in
place (`patchText`/`patchButton`/`patchAppBar`/`patchTextField`); a focused text
field is left entirely alone, so typing is uninterrupted - no focus dance at
all. Any mismatch - a different type, a different child count, a prop only a
rebuild can apply - returns false and falls through to the full rebuild, which
is always correct, so the diff can only ever make a render faster, never wrong.
Verified: typing `typing` into the bio field keeps every keystroke with no
rebuild and updates its character count in place, on both an Android emulator
and an iOS simulator; the counter patches its number in place; navigation (a
shape change) still rebuilds correctly.

The full rebuild kept the focused-field preservation from the typing fix, as the
fallback for shape-changing renders (a validated field whose error appears or
disappears rebuilds, and the focus/caret restore makes typing survive that too).

**Keyed reordering landed too.** A stacking container (Column, Row, List,
VStack, HStack) now reconciles its children by `id`: `reconcileChildren` walks
the old and new children together and, when a child carries an `id`, finds the
row that already has it and moves its view up rather than rebuilding every row
after the change - the web renderer's `_syncChildren`, ported to
`LinearLayout`/`UIStackView`. A child without an `id` still matches by position.
Verified: deleting the middle of three keyed todo rows keeps the other two rows'
views and moves the last one up (Android logged `kept=2 moved=1`; iOS left the
right two rows in order), on the emulator and the simulator. An unkeyed sibling
after keyed ones (the todo's summary line) still rebuilds when the keyed rows
above it move - the same behaviour the web renderer has - so give reorderable
siblings an `id` to keep them.

**The lazy list reconciles its window too.** `LazyList` frames its windowed rows
by index rather than stacking them, so it has its own `reconcileLazyList`: the
rows are held in window order (the old row at position i produced view i), so it
matches the two windows' rows by their `<id>/<index>` keys, reuses and re-frames
the ones they share, builds only the rows scrolled newly into view, and drops
the rest. Verified scrolling the 10,000-row inbox: a window shift reuses 27 of
its 33 rows (Android instrumented `reused=27 created=6`) and the list stays
correct (Android to message 80, iOS to message 126), on the emulator and the
simulator.

More node types patch in place now: **Checkbox, Toggle and Radio** re-derive their
label, enabled and checked state (a `settingChecked`/`isOn` guard keeps the
programmatic set from firing the toggle event and looping), and **Card**
re-derives its variant, elevation, padding and title while its children are
walked through the content column (a change in whether the title is present
falls back to a rebuild, which keeps the title/child offset right). Verified:
checking a todo flips the box and strikes the title through in place, with no
loop, on the emulator and the simulator.

Still to do:
- A few leaf types still rebuild on change (Image, Badge, Alert, Loading,
  ListItem) - the same re-derive pattern applies when wanted.
- Mid-text caret still rides the rebuild path when a field's structure changes.

**Done when:** ~~typing into a field survives a re-render on both platforms~~
(done), and ~~a list of fifty rows updates without a visible rebuild~~ (done - a
stacking list patches content in place and moves rows by id on
add/remove/reorder, and the lazy list reuses the rows two scroll windows share).

### 1.3 Dialogs, sheets and snackbars — every named leftover closed (2026-09-19)

Decided as a modal layer in the tree: `UIBuilder.overlay` draws overlays above
the screen, and `dialog`, `bottomSheet` and `snackbar` are state the app adds
and removes. Renderers only send dismiss events (scrim, Escape, swipe,
timeout); `OverlayBack` in Dart gives the back gesture to the topmost modal on
every platform, and on web `RouterHistorySync` puts the browser entry back when
a dialog consumed Back. The inbox example uses all three.

Verified on a physical iPad (iOS 26.7) running the inbox: the bottom sheet
opens, a confirm dialog stacks over it, confirming pops both and deletes the
row, and the undo snackbar dismisses both ways - the 10s timeout (event
`snackbar_1.dismiss {reason: timeout}`) and the Undo action (`snackbar_2.action`)
that restores the row. Scrim-dismiss of the sheet also fires.

Left:
- ~~Run it on Android (1.1)~~ — done on an Android phone (2026-09-18): the sheet
  opens, a confirm dialog stacks over it, confirming pops both and deletes the
  row, the undo snackbar restores it, and system Back dismisses the topmost
  overlay. iOS is done.
- ~~Web does not return focus to where it was when a dialog closes~~ — fixed
  (2026-09-19). The renderer remembers what had focus before the *first* modal
  opened - a dialog over a sheet returns the user to where they were before
  either - and gives it back when the last one closes. It remembers the
  element's `id` rather than the element: opening a dialog wraps the screen in
  an `Overlay`, so the root's type changes and the DOM underneath is rebuilt,
  and the control that had focus is a different object by the time the modal
  closes. A control with no `id` cannot be found again, and focus is then left
  where the browser put it rather than moved somewhere arbitrary - documented
  and tested, rather than silently half-working.
- ~~A dialog whose own props change is rebuilt on web, so a field inside it
  loses focus~~ — fixed for the case that matters (2026-09-19). A modal whose
  *title* changed is re-titled in place, so a title that counts a selection or
  names the row being confirmed no longer costs the user their caret. A change
  to `dismissible` or the dismiss event id still rebuilds: those listeners
  close over what they were built with, and a half-patched modal would be worse
  than a rebuilt one.
- ~~`bindBrowserBack` treats the browser's Forward as Back too~~ — fixed
  (2026-09-19). `popstate` fires for both and does not say which, so each entry
  now carries a rising index and the handler compares it with the one it left:
  lower is a Back, higher is a Forward and is ignored. An entry this app did
  not write - a link, a hand-typed fragment - has no index and counts as a
  Back, which is what it did before and the safer reading of an unlabelled
  move.
- ~~Flutter scrolls a dialog's actions with its content rather than pinning
  them~~ — fixed (2026-09-19), and the web had the same bug unrecorded. A
  dialog's last child is its row of actions (see `UIBuilder.dialog`), so
  Flutter leaves it out of the scrolling part and lays it under, and the web
  sticks it to the bottom edge of the scrolling body with the surface's own
  background behind it. Confirm and Cancel stay in reach of a long body instead
  of sitting below the fold. A dialog with no actions, and a sheet, scroll
  everything as before.

  The web half is CSS, and the DOM test host does not load the stylesheet, so
  it has no test behind it - unlike the Flutter half, whose two tests both fail
  against the old behaviour (the actions sat at y=929 on a 600-tall screen).

### 1.4 Long lists — scrolling holds 60Hz on a device (2026-09-19)

`UIBuilder.lazyList` sends an item count, a fixed row height and only the rows
near the visible ones; the renderer reports the visible range and
`LazyListWindow` moves the window with overscan. The inbox example shows ten
thousand rows.

Verified on a physical iPad (iOS 26.7): the 10,000-row inbox scrolls to ~row
1809 with the visible window sliding correctly (range events track ~14 rows at
a time), and far-down rows build with their real ids (a `⋮` tap on row 1777
fired `actions_1777`). Also verified on an Android phone (Android 17, 2026-09-18):
scrolled from row 1 to the message-80s with the window sliding correctly, rows
built with their real ids and read/unread styling, and a far-down `⋮` opened its
sheet. Virtualization holds on both.

**Frame times are instrumented now (2026-09-18).** Each renderer can report the
intervals between the frames it presented - a `CADisplayLink` on iOS, the
`Choreographer` on Android, `FrameTiming` on Flutter, `requestAnimationFrame` on
web - and `FrameStats` turns those into the numbers worth quoting: mean, p50,
p95, worst, and how many ran over the display's budget. `app.frameProbe` starts
and stops it; it costs nothing until started. The arithmetic is plain Dart and
unit-tested (12 tests), which is what lets a claim about smoothness be checked
without a device. `lib/main_native_framecheck.dart` runs the 10k-row inbox,
records for ten seconds and prints one line.

The first numbers, both debug builds:

| host | idle | scrolling |
|---|---|---|
| iOS simulator (iPhone 17 Pro, iOS 26.4) | mean 16.7ms, worst 16.7, **0% janky** | mean 19.6ms, p95 50.0, worst 89.4, **8.3% janky** |
| Android emulator (Medium_Phone, software GL) | mean 16.8ms, worst 50.0, **0.7% janky** | mean 40.1ms, p95 166.7, worst 566.7, **20.2% janky** |

The idle runs are the control, and they are clean - an iOS run of 599 frames
every one of which was exactly 16.7ms - so the probe is measuring the right
thing rather than reporting noise. Which means the scrolling numbers are real
*for these hosts*: flinging the list drops frames on both.

What that does **not** say is whether a device drops them. Both hosts are debug
builds; the Android one is rendering through software GL (the emulator says so
at boot) and its 566ms worst frame is not a number any phone would produce. The
honest state is: the measurement exists and the criterion is checkable, the two
hosts I can drive both fail it, and the device answer is still open.

**Measured on two devices (2026-09-19).** Release builds, both 60Hz:

| device | idle | scrolling |
|---|---|---|
| A mid-range phone (Android 17) | 0.2% janky, worst 18.3ms | **0.7-0.8% janky**, p95 16.9, worst 19.7-33.7ms |
| An older phone (Android 12) | 0% janky, worst 16.7ms | 1.0-1.9% janky, p95 16.7, worst ~67ms |

**The list holds 60Hz.** On the Pixel p95 is 16.9ms against a 16.7ms budget and
the worst frame of a whole scroll is 19.7ms - there is no visible hitch at all.
The older Mate is a little rougher, a handful of ~67ms frames where the window
updates, but its p95 is still exactly on budget.

The emulator numbers above stand as what they are: a software-GL debug host, an
order of magnitude worse, and not evidence about any phone.

**What the emulator did surface is a real bug.** Instrumenting `renderTree`
showed each window update costing 314-440ms there, and the breakdown said why:

    reused=0 built=29 noKey=0 keyMissed=6 patchFailed=23 buildMs=288

Only 6 rows were genuinely new. 23 matched by key, had their view in hand, and
`tryPatch` refused it - because `childViews` had no case for `SwipeActions`, so
it returned nil and the row was rebuilt. Every inbox row is wrapped in one, so
the keyed reconcile §1.2 documents (`reused=27 created=6`) had been doing
nothing for this list since swipe actions landed, on **both** native
renderers. Fixed by teaching `childViews` to walk into the swipe row's
foreground layer. On the emulator: `patchFailed` 23 → 0, `reused` 0 → 23, row
building 288ms → 59ms, the whole render 314ms → 143ms.

**And on the Pixel the fix is what makes the scroll smooth.** Same fling, same
release build, only the fix differing:

| | jank | worst frame | `isSmooth()` |
|---|---|---|---|
| before | 2.1%, 2.1% (two samples, identical) | 50.5ms | false |
| after | 0.7%, 0.8% | 19.7ms, 33.7ms | true |

The Mate did not show it - 1.0% unfixed against 1.5-1.9% fixed, which is the
wrong way round and so is noise on that machine. Measuring one device and
concluding "the fix changes nothing on hardware" was wrong; the Pixel says
otherwise, twice, reproducibly. Two devices disagreeing about whether a change
matters is itself the lesson: one sample on one phone is not a result.

A second, smaller find on the way: `iconGlyphDrawable` allocated a fresh Bitmap
and rasterised the glyph on every icon build - 29 a window for a list with an
icon a row. Cached by codepoint and colour, worth about a quarter of the row
build time on the emulator.

Left:
- The Mate's ~67ms frames at window updates are the remaining roughness, and
  the Pixel's 33.7ms worst frame in one sample is the same thing smaller. If
  that ever needs chasing, the next place to look is what a window update does
  *besides* building rows - the channel round trip, or the re-frame and layout
  pass over 29 rows.
- Nothing is recorded over time, so a regression here is still invisible
  (see "Benchmarks in CI").
- ~~Rows must share one height~~ - fixed 2026-09-21. A list whose rows differ
  says so with `itemExtentBuilder`, which is asked for the height of *every*
  row rather than only the ones in the window: the list's own height, and
  which row a scroll offset lands on, are sums over all of them, and the
  renderer is holding twenty of ten thousand. `RowExtents` adds them up once
  per build and finds a row by halving.

  That inverts who does the arithmetic. A uniform list lets the renderer
  divide an offset by the row height and report the rows it can see; a varied
  one has the renderer report **pixels** - where it is scrolled to and how
  tall its viewport is - and Dart says which rows those are. The node carries
  the window's own heights, where the window starts and how tall the whole
  list is, which is everything a renderer needs to place what it has and size
  what it has not.

  What it does not do is *measure*: an app that cannot say how tall a row will
  be before it is drawn (a paragraph of unknown length, say) still has no
  answer here. Saying it is cheap in the cases that matter - a feed of cards,
  a list with the odd picture - and measuring across a channel is a different
  feature with a different failure mode (rows that shift as they are measured).

  Checked by eye on both natives with a probe of 500 rows, every fifth one
  tall: no gaps, no overlaps, and the window sliding correctly to rows 46-51
  on the emulator and 122-127 on the simulator, with the spacing between rows
  confirming each one's own height.
- A list scrolls itself, so it needs bounded height (a Scaffold body or an
  `Expanded`). On web the Scaffold rule uses CSS `:has()`.
- Maestro's web scroll does not reach a list's own viewport, so the e2e flow
  does not scroll; the browser tests do.

---

## 2. Correctness and safety

### 2.1 The four documented bugs — fixed (2026-09-16)

All four are fixed and their previously-skipped tests now run:

- `Route.extractParams` copies `defaultParams` instead of writing into it, so
  params no longer leak from one navigation into the next.
- `Locale.fromString` reads the script from the middle segment and the region
  from the last, so `zh_Hans_CN` parses as script `Hans`, region `CN`.
- `Form.undo`/`redo` guard the replay (a flag the field's own change event
  clears) so it is not recorded as a fresh edit, and stepping through history
  works both ways.
- `DSText.h1`..`caption` carry their typography tokens (size, and weight for
  the headings).

**Done:** the four `skip:` markers are gone.

### 2.2 Web views done; map and camera still open (2026-09-19)

The device-service wrappers are gone (see "Device services" above). What is left
are the things that draw: a map, a live camera preview and a web view. Their
Flutter plugins paint through Flutter's texture and platform views, which the
Android View and UIView renderers never display, so each needs a node type in
the protocol and a native view in every renderer (`MapView`/`MKMapView`,
`PreviewView`/`AVCaptureVideoPreviewLayer`, `WebView`/`WKWebView`, and an
`<iframe>` or a JS map on web).

**The web view landed (2026-09-19).** `UIBuilder.webView(url:)`, or the facade
`WebView`, draws a page in the platform's own browser view: `WKWebView` on iOS,
Android's `WebView`, an `<iframe>` on web. None of the three needs a dependency
or a key - only the INTERNET permission, which the plugin's own manifest now
declares (as `webview_flutter` does) so an app still needs no setup.

`height` is required for the same reason a lazy list needs one, and
`javaScriptEnabled` is off by default: a page that is only being read does not
need to run code, and it is the default `webview_flutter` takes. On web that
switch is the iframe's `sandbox` - no `allow-scripts` means shown, not run.

The Flutter-hosted target draws a placeholder naming `webview_flutter` and the
URL, rather than an empty box. Taking that plugin would put it in every app
using the framework for a node most never build; the placeholder is a
documented limit, so it is deliberately *not* reported through `renderErrors` -
a render that reported it every frame would bury the errors that are surprises.

Verified on an Android emulator and an iOS simulator: a real page renders inline
at the height asked for, with app content above and below it. The iOS half was
blank at first and the navigation delegate said why - `didFinish` with
`size=(0.0, 420.0)`: the page had loaded perfectly into a view zero points wide,
because a Column centres its children and a `WKWebView` has no intrinsic width.
It is wrapped in a frame that takes its superview's width now. Worth remembering
for the other embedded views: they will have the same no-intrinsic-size problem,
and it fails silently.

**Map: drawn where it is free (2026-09-20).** Neither map nor camera can be
drawn on all four the way the web view can:

| | iOS | Android | Web | Flutter |
|---|---|---|---|---|
| Map | MKMapView, free | Google Maps SDK **+ an API key** | a JS library or tiles | `google_maps_flutter` + key |
| Camera | AVCapture **+ a usage string and permission** | CameraX dependency **+ permission** | `getUserMedia` | `camera` plugin |

So the `MapView` node is drawn on the two targets that ask for nothing:

- **iOS** is MapKit. A slippy `zoom` converts to a map *rect* rather than a
  region - a region is a span in degrees that MapKit refits to the view's
  shape, so a square span on an oblong map zooms out and the map reports back a
  zoom the app never asked for. Map points convert exactly, both ways, and the
  probe proves it: ask for 14, get 14 back.
- **Web** lays out raster tiles as `<img>` elements - OpenStreetMap's by
  default, attributed on screen because that is what they cost, and
  `tileUrl` points a real app at its own source. No canvas, no WebGL context,
  no library: the browser fetches, caches and composites.
- **Android and the Flutter host draw a labelled placeholder**, the same shape
  the web view's has, saying which dependency and key are missing.

The map is patched in place on both - a rebuilt map throws away its tiles and
fetches them again - and it reports where it came to rest, never where it
passed through: a position per frame would render the whole tree per frame.

**Camera: the same treatment (2026-09-20).** `CameraPreview` is drawn on the
two targets where a camera costs nothing but a permission - `AVCapture` on iOS
and `getUserMedia` on web - and placeholders on Android and the Flutter host.

Frames never reach Dart on either: iOS feeds an `AVCaptureVideoPreviewLayer`
straight from the capture session, and web hands the stream to a `<video>`.
`onStatus` reports only whether it started - `ready`, `denied`, `unavailable`,
`stopped`. The view owns the session and stops it when it leaves the window
(iOS) or the page (web, swept after each render), and `active: false` stops it
without taking the node out of the tree, because a preview nobody is looking at
still costs battery, heat and the indicator light.

The app declares the permission, not the framework: the example app's
Info.plist gained `NSCameraUsageDescription`, and a browser only offers a
camera on a secure origin. A consuming app has to do the same.

**Verified as far as this machine allows**, which is not all the way:

- iOS, on the simulator: the prompt appears with the usage string, *Allow*
  reaches the session and reports `unavailable - This device has no camera`
  (a simulator has none), and *Don't Allow* reports `denied`. So the
  permission, the session and both failure reports are proven; **a live
  picture is not** - that needs a physical device, like §1.1.
- Web, in the test browser: it refuses rather than prompting, so the `denied`
  path is asserted automatically along with the element shape. A **live
  picture was not captured either**: a headless screenshot runs on virtual
  time, which the fake camera device never satisfies, and capturing a real
  browser window here would have meant photographing the whole desktop.

So: on both targets the plumbing is proven and the picture is not. Ten minutes
with a phone and a laptop browser would close that, and nothing in the code is
waiting on it.

The camera is deliberately *not* in the device lane: a permission dialog in
front of an automated run is a lane that needs someone to tap Allow.

**Still open:** the Android and Flutter halves of both map and camera, which
are the same decision as ever - a dependency plus a key, or a permission.

### 2.3 Storage and crypto — rotation and migration landed (2026-09-19)

- On Android and iOS the framework provides no `StorageService`; each app
  wraps `shared_preferences` / `flutter_secure_storage` itself. If every app
  ends up writing the same twenty lines, ship them as a small optional package.
- **Key versioning and rotation landed (2026-09-19).** A stored value is
  `k<version>:<iv>:<cipher>`, so it names the key that wrote it; a two-field
  value from before this belongs to the first key, which is where it still
  lives, so nothing had to be migrated. `rotateKey()` generates a new key,
  re-encrypts everything this store holds and removes the old one, answering
  the new version. The order matters: the new key is written and made current
  *first*, values move one at a time (each still naming the key that wrote it),
  and the old key goes only once they have all moved - so an interrupted
  rotation leaves every value readable and finishes on the next run. A value
  whose key really is gone now says which version it wanted, instead of
  reporting the same "tampered with" as a corrupted byte.

  Writing this surfaced a constraint worth knowing: stores sharing a `keyName`
  share the *key*, and the `prefix` only separates their values - so rotating
  one re-encrypts its own values and then removes a key the other is still
  naming. Documented on the constructor and on `rotateKey`; give stores that
  should rotate independently their own `keyName`.
- **A migration story (2026-09-19).** `storage.migrate([...])` runs the
  numbered steps a store has not run yet, oldest first, over any
  `StorageService` including the encrypted one. The version is recorded after
  *each* step rather than at the end, so a run that is interrupted - the app
  killed, a step throwing - resumes where it stopped instead of replaying what
  succeeded, and a step that throws stops the run and reaches the caller rather
  than letting an app carry on against data it does not understand. A fresh
  store is at 0, so every step runs on a new install too, which keeps a key's
  shape decided in one place instead of in both a migration and a first-run
  path.

### 2.4 Error surfaces — structured, streamed and showable (2026-09-19)

A render failure is no longer silent (2026-09-13). `render()` returns the
renderer's error string, and `NativeUIApp.render` now reads it: a non-null
result (or a thrown error) goes to `onRenderError`, which a host or test can
set, and which otherwise prints in debug. This is what caught the Android
Material-theme crash (1.1) - every render was throwing and the string was being
dropped, so the screen was blank with nothing logged. The native renderers also
collect the node types they could not draw during a render and return them, so
an unknown type reports itself through the same path rather than only drawing a
placeholder.

**Errors are structured, streamed and showable now (2026-09-19).** The three
things this section was still missing:

- **Structured.** `render()` answers with a `RenderError` rather than a string:
  a `kind` (`unknownNodeType` or `renderFailed`), the `nodeTypes` it could not
  draw, the `message`, and the thrown `cause` and stack trace where there was
  one. A host that wants to know *which* types are missing reads a set instead
  of parsing prose. The native halves send `{unknownTypes: [...]}` or
  `{error: ...}` over the channel, and `RenderError.fromChannel` still reads the
  bare string older halves returned, so a stale plugin degrades to a readable
  failure rather than to nothing.
- **Streamed.** `NativeUIApp.renderErrors` is a broadcast stream, so a debug
  overlay, a crash reporter and a test can all watch at once instead of
  competing for the single `onRenderError` slot. That callback is still there
  for a host that wants to handle rather than watch; with neither, the debug
  print stands.
- **Showable.** `runApp(..., debugShowRenderErrors: true)` draws the last three
  distinct problems over the app. The banner is a `Snackbar` node - every
  renderer already draws one, it blocks nothing, and `OverlayBack` leaves it
  alone because it is not modal - so no renderer needed new code for it. It
  re-renders once when the set of messages changes and not again, since the
  render it schedules meets the same unknown type and would otherwise never
  settle.

The Flutter and web renderers report unknown types now too, where before only
the native halves did: web in the same breath (it builds the DOM inside the
render), Flutter one render later (it builds after render returns, so the
alternative was never). Both native halves also report from the *patch* path,
which builds a lazy list's newly visible rows and could meet an unknown type
as readily as a rebuild. Verified on the Android emulator with an app whose
tree carries a node type nobody can draw: the placeholder appears in place, the
banner reads `Unknown node type(s): Hologram`, and the error count holds steady
rather than climbing.

Left: nothing routes these anywhere by default - an app that wants them in a
crash reporter still wires that itself - and the banner is a development
affordance, not a production error screen.

---

## 3. Gaps a real app will hit early

- **What three real apps hit, closed (2026-10-03).** The entries below were
  written from the examples. Migrating a reminders app, a games collection and
  a planner asked for things none of the examples had, and these are the ones
  that are closed - each on web and the Flutter renderer by test, on Android
  by the emulator pass unless it says otherwise, and on iOS **not at all: the
  Swift compiles and has drawn the examples, and none of what is below has
  been checked there**.

  - **Free-form composition.** `Container`, `Stack`, `Positioned`, clips,
    opacity, transforms, gradients, borders and shadows, over one `Box` node
    and a `Stack`. Before this a screen was made of named components or it
    was not made.
  - **Scrolling as Flutter means it.** A `Scaffold`'s body does not scroll;
    `SingleChildScrollView`, `ListView` and `GridView` do, on either axis,
    with pull-to-refresh and a `ScrollController` that can send a scroller
    somewhere.
  - **Navigation that keeps state.** `Navigator.push` with a result, pages
    beneath kept alive, an app bar that gains its own back button, bottom
    navigation and a rail, and `router.dart` for an app built on go_router.
  - **Touch.** Taps with their position, double taps, long presses, pans,
    drag and drop, a `Dismissible`.
  - **Drawing.** `CustomPaint` over a `Canvas` node that replays a command
    list - which is what a chart, a calendar and every game board became.
  - **Choosing.** A dropdown and the platform's date and time pickers.
  - **Knowing the window.** `MediaQuery` and `LayoutBuilder`, from a
    `dnn:viewport` event each renderer sends; app lifecycle and hardware keys
    the same way.
  - **Right-to-left.** The reminders app was right-to-left in Arabic under
    Flutter and came out left-to-right here. The root of the tree carries the
    direction now and every renderer turns the screen from it;
    `Directionality`, `EdgeInsetsDirectional` and their kin resolve against
    it. Android: seen on the emulator under an Arabic locale - app bar,
    bottom-navigation order, list tiles, tabs, calendar and switch mirrored.
  - **Images.** Remote images are cached instead of fetched on every rebuild,
    and `Image.errorBuilder` supplies a fallback. Android: remote images
    loaded in list rows on the emulator; the disk cache's behaviour offline
    and at expiry was not examined.
  - **A Flutter widget in a native screen.** `FlutterSlot`, for the ad banner
    the games app could not redraw. On the emulator an AdMob test banner
    showed through the hole at its 320×50dp, pinned; tapping the ad was not
    tested.
  - **State management that is already written.** `dart_not_native_bloc`.
  - **The app's own theme.** `ThemeData` with a seeded `ColorScheme`, read
    through `Theme.of` and handed to the renderers with `toAppTheme`.
  - **Icons.** Every style of every Material icon, and the same glyph on web
    as everywhere else.
  - **A keyless widget's id** no longer doubles in length at every stateful
    widget above it - thirty deep it was megabytes, and hung a page.

  What those apps still work around is §6.

- **Theming — a palette reaches every renderer (2026-09-17).**
  `runApp`/`runNativeApp`/`runWebApp` take an `AppTheme` of `primary`,
  `onPrimary`, `secondary`, `surface` and `error`, carried to every renderer
  (native via the `initialize` message, web via `--dnn-*` custom properties,
  Flutter via its widget defaults). `primary` drives the app bar, primary
  buttons and FAB; `onPrimary` their text/icon; `secondary`/`error` those button
  and badge variants; `surface` scaffolds and cards; `error` also a field's error
  text. The design-system `Badge` and progress indicators follow `primary` too
  (they leave the colour off the node), while the other semantic colours
  (success/warning) stay fixed, and the Flutter FAB keeps its Material 3
  default when no theme is set. Verified end-to-end on an Android emulator (a teal
  primary, black onPrimary and cream surface all render); browser and widget
  tests behind the mechanism. The palette has since grown `surfaceVariant`,
  `text`, `textSecondary` and `divider` - see the dark-theme entry below, which
  is what needed them. Left: the design-system `Alert` still uses its own
  info/success/error/warning palette rather than the theme.
- **Dark theme across all four renderers (2026-09-18).** An `AppTheme` now
  carries both appearances: its own colours are the light palette, `dark` is the
  counterpart (the built-in one unless the app supplies its own), and `mode`
  (`light` / `dark` / `system`) says which to paint. `system` asks the device -
  the trait collection on iOS, the night ui-mode on Android,
  `prefers-color-scheme` on web, `MediaQuery.platformBrightness` on Flutter - and
  every renderer repaints when the answer changes, with no app involvement.
  The palette grew the four slots that made this possible: `surfaceVariant`
  (cards, modal panels, a field's fill - lighter than the surface in dark and
  darker in light, so it cannot be derived), `text`, `textSecondary` and
  `divider`. Every colour the renderers used to hardcode now comes from one of
  them, so there is a single place to change an appearance. Snackbars are drawn
  on the *other* appearance, Material's inverse-surface trick, so a message
  still reads as being over the app.

  What each renderer needed: **iOS** stops pinning its container to `.light` and
  pins it to the appearance in force instead, which also hands the system
  controls it does not paint - a switch, a field's rounded border - the right
  look; **Android** picks the dark `Theme.MaterialComponents` wrapper to match,
  since a MaterialButton takes its ripple and disabled colours from the theme;
  **web** publishes the whole token set on the root element and lets the
  existing `--dnn-*` variables do the rest, with no second stylesheet;
  **Flutter** derives a `ThemeData` per appearance so the Material widgets the
  renderer does not colour itself agree with the ones it does.

  Both native renderers force a full rebuild when the appearance changes, since
  a colour is not a prop and the diff would otherwise keep every view it had,
  still in the old palette. Dart triggers that render from
  `didChangePlatformBrightness`, which Flutter still receives while it is only
  hosting the engine.

  Verified on an iOS simulator (iPhone 17 Pro, iOS 26.4) running the
  design-system showcase, whose five pages are the widest colour exercise:
  `xcrun simctl ui ... appearance dark` repaints the live app - dark canvas,
  light text, the lightened primary on the app bar and FAB, raised cards
  distinguishable from the surface - and back again. 13 tests behind the
  mechanism (7 Flutter, 6 DOM) plus the `AppTheme` unit tests.

  The device pass also caught a real bug it was made to catch: `DSCard.filled`
  and `DSDivider` defaulted their colour to a hardcoded light grey and always
  sent it as a prop, so the renderer's theme fallback could never run and a
  filled card stayed near-white under dark text. Both now leave the colour off
  the node unless the caller passes one, the same fix `Badge` and the progress
  indicators had.

  **The status colours followed (2026-09-18).** `success`, `warning` and `info`
  joined `error` in the palette, so all four are per-appearance: the light set
  is what it always was (`#388e3c` / `#fbc02d` / `#0288d1`), and the dark set
  lightens them (`#66bb6a` / `#ffca28` / `#4fc3f7`), because a deep green or a
  mid blue picked to read on white goes muddy on a dark ground. Every site that
  hardcoded one - each renderer's `variantColor`, the four `Alert` types, the
  button and badge variants, the swipe action's default red - now reads the
  palette, so no *use site* in a renderer names a colour any more. The hex that
  is left is the palette's own defaults, which is what a colour the app has not
  set falls back to, and the two contrast constants (`ON_LIGHT`/`ON_DARK`) that
  `lib/src/contrast.dart` also carries. An app can set its own per appearance,
  the same way it sets the rest.

  The device pass caught one more thing the palette could not reach: the Android
  `Alert`'s Dismiss button was a bare `MaterialButton`, so it took the Material
  theme's own accent - a purple belonging to neither the alert nor the app - and
  the switch to the dark wrapper only made it brighter. It is now flat in the
  alert's colour, like every other button the renderer draws.

  **The checkable controls followed too (2026-09-18).** A bare `Checkbox`,
  `RadioButton`, `SwitchCompat` or `UISwitch` draws itself in the platform's own
  accent - UIKit's blue, Material's purple - which belongs to neither the app
  nor its theme, and neither follows a palette anywhere. All four renderers now
  tint theirs: the brand primary when the control is on, the quiet text colour
  when it is off (an unchecked box in the brand colour reads as if it were
  already checked), and the divider colour when it is disabled. Android uses a
  `ColorStateList` per state; iOS bakes the colour into the SF Symbol
  (`.alwaysOriginal`), since one `tintColor` cannot say two things; Flutter sets
  `activeColor` / `activeThumbColor`; the web's plain kit already read
  `--dnn-primary` through `accent-color`, so it needed nothing (the MDL and
  Materialize kits keep their own vendor palettes, which is their point). The
  same pass fixed the iOS control *labels*, which were taking the button's tint
  and rendering as blue links rather than body text.

  Left: the design-system `Alert` draws its own 10%-tint background from the
  status colour rather than taking a token (which works in both appearances,
  but is not the theme's to change). The Android half was verified on the
  emulator only until 2026-09-24, when an Android phone showed the checkbox and the
  switch taking the brand blue when on and the quiet grey when off, with
  "Newsletter: on" and "Dark mode: on" following underneath - so the tint and
  the event behind it are both device-proven now.

  **Text over a colour the app chose (2026-09-20).** A card with an explicit
  `backgroundColor` used to get the theme's text over it, which is fine until
  the card is navy: the theme's near-black was chosen against the *surface*,
  not against whatever the app picked, and a label nobody can read is not a
  style. Every renderer now derives the text colour from the stated background
  by WCAG relative luminance - white over a dark colour, the palette's own
  `#212121` over a light one - wherever an app states a fill: a card's
  `backgroundColor`, an `AppBar`'s, a filled `Button`'s `color`, a `Badge`'s,
  an `AnimatedContainer`'s. One rule, four copies (`lib/src/contrast.dart` for
  the two Dart renderers, and a transcription in Kotlin and Swift), with its
  own test for the rule itself.

  The renderer's own text is the easy half. The *children* of a coloured card
  are nodes it does not draw, so each native keeps a "text colour in force"
  while it renders or patches inside one, which `renderText`/`patchText` fall
  back to instead of the theme's; web needs none of that, since an inherited
  CSS `color` already reaches every child that did not state its own; Flutter
  uses the same field as the natives. Text that *does* state a colour keeps it
  everywhere. One gap: a `LazyList`'s rows build when they scroll into view,
  after the card that holds them has been built, so rows inside a coloured
  card keep the theme's text colour.

  The same pass fixed a smaller thing it uncovered: only the `filled` card
  variant used `backgroundColor` on Android, iOS and Flutter, so an elevated
  or outlined card the app coloured was drawn in the theme's surface on three
  renderers out of four and in the app's colour on the web. Every variant now
  draws the colour it was given; the variant decides what happens *besides*
  the fill - a border, a shadow.

  Verified by eye on an emulator and a simulator with a probe screen of pale
  and dark tiles - two app bars, six cards, two buttons, two badges, two boxes
  - and it caught what tests could not: on iOS the button's title was still
  white on yellow, because the edit had landed on the patch path and not the
  render path.

  **An `Alert` is dismissed the same way everywhere now (2026-09-18).** The iOS
  renderer had ignored the `dismissible` prop since it was written, so an alert
  meant to be closeable simply could not be closed there - one renderer of four
  drawing no affordance at all, with the node type present in the dispatch and
  the coverage test happy, which is how it went unnoticed. Android drew one, but
  as a "Dismiss" text button under the message, where the web (`×`) and Flutter
  (`Icons.close`) put a close icon at the trailing edge. Both now do what the
  other two do: a close glyph in the alert's own colour at the trailing edge,
  carrying the same "Dismiss" accessibility label, removing the view locally
  rather than reporting to Dart. The alert became a row on both to hold it, so
  the message no longer shares a column with the button. Verified on an iOS
  simulator and an Android emulator against the showcase's four alerts: the two
  that ask for it get the button, the two passing `dismissible: false` do not,
  and tapping one closes that alert and closes the gap behind it.
- **iOS 26 Liquid Glass on the app bar and FAB (2026-09-17).** On iOS 26+ the
  app bar and the floating action button render as `UIGlassEffect` surfaces -
  the bar a translucent branded-tint glass the content scrolls through, the FAB
  an interactive glass pill (`isInteractive`, capsule corner) that lenses under
  touch - instead of flat fills. Everything is behind `if #available(iOS 26, *)`
  with the previous opaque fill as the fallback, so the iOS 15 deployment target
  still builds and older devices and Android are unchanged; `patchAppBar` retints
  the glass and finds the now-nested title. Verified on a physical iPad (iOS 26.7):
  the glass bar over the scrolling inbox, and the FAB deforming under press on the
  counter while still incrementing.
- **Liquid Glass on the modal sheet and dialog, with a transparency knob
  (2026-09-18).** The bottom sheet and dialog surfaces are now `UIGlassEffect`
  too (untinted, the content on top staying crisp), and `AppTheme` carries a
  `glassTransparency` (0 solid frost … 1 barely there) that fades the frost and
  lightens the modal scrim in step, so an app tunes how see-through the modals
  are - the inbox example sets 0.6. Under iOS 26 the modal scrim also drops from
  0.4 to a light 0.15 base, since the glass carries the separation. Verified on a
  physical iPad: the list shows through the frosted sheet and dialog while their
  own text stays legible.
- **A `glassChrome` opt-out for the bar and FAB (2026-09-18).** `AppTheme` carries
  a `glassChrome` (default true); set it false for the flat brand-colour fill on
  the app bar and FAB even on iOS 26 - a solid branded app bar, say - while the
  modal glass stays on its own `glassTransparency`. `patchAppBar` already handles
  the flat case (no glass layer to retint). Verified on a physical iPad: with the
  counter opted out, the bar and FAB render solid, no lensing. Left: glass still
  has no effect below iOS 26 or on Android.
- **Swipe actions across all four renderers (2026-09-18).** A facade
  `SwipeActions(child, actions: [SwipeAction(label, color, onPressed)])` reveals
  trailing buttons when a row is dragged left, iOS Mail style: a partial drag
  snaps open to tap an action, a full drag fires the first. It is one
  `SwipeActions` node type each renderer builds - iOS a hand-rolled
  `SwipeActionsView` (the lazy list is a custom `UIScrollView`, not a
  `UITableView`, so there is no system swipe to lean on), Android a
  `SwipeActionsLayout` (`FrameLayout` intercepting horizontal drags via
  `onInterceptTouchEvent` so taps and vertical scroll still pass through),
  web a pointer-drag translate on the child, Flutter a `Stack`+`Transform`
  reveal (its `Dismissible` has no tappable-button reveal). The child is backed
  by the surface colour so the actions stay hidden until swiped. The inbox wraps
  its rows with a Delete that reuses the existing delete+undo. Verified: root,
  package and browser suites green; Android/Flutter/web compile (Android APK
  built). The iOS half did **not** compile as landed - the "iOS Swift built"
  claim here was wrong - and was fixed on 2026-09-18 by giving
  `SwipeActionsView.gestureRecognizerShouldBegin` the `override` keyword UIView's
  own declaration requires; `flutter build ios --simulator` passes now, and the
  new CI `ios-build` lane keeps it that way. **Device-verified on Android (the Android phone,
  2026-09-18):** a partial left-drag snaps open to reveal the red Delete button
  without firing, a full left-drag fires the Delete (row removed + undo
  snackbar), and the row's `⋮` button stays tappable. **Device-verified on iOS too (2026-09-21)**, on a
  simulator: a left drag on a far-down inbox row reveals the red Delete, and
  tapping it removes the row and offers the undo - the first time the gesture
  has been through the Swift renderer at all.

  **And tested now (2026-09-22), not just looked at.** Six browser tests drive
  the gesture with real pointer events and five widget tests drag it in
  Flutter: the actions sit behind the row, a partial drag snaps it open
  without firing, an action can be tapped once it is open, a short drag falls
  back, and a long drag fires the first action by itself. `inbox.yaml` adds
  the device half - a drag reveals the Delete on an emulator and a simulator.
  That the *tap* fires is left to the two test suites: on a device the row
  snaps shut between one Maestro command and the next, and a tap aimed at
  where the action was lands on the row behind it.

  Writing the widget test turned up a real difference: the Flutter host's
  swipe row took its width from its child, so a narrow child left the actions
  behind it sticking out. It fills the width it is offered now, like the row
  the other three renderers draw.

  **Leading actions landed 2026-09-22.** `SwipeActions(leadingActions:)`
  reveals buttons at the *other* edge on a right drag - where iOS Mail puts
  Mark as read - with the same rules as the trailing ones: a partial drag
  snaps it open, a long one fires the first action outright. All four
  renderers draw both bars; the inbox now carries a Read/Unread one, which is
  the example the entry asked for.

  Three browser tests and two widget tests cover the new direction, and
  `inbox.yaml` drags a row both ways on a device. Looked at on both: the blue
  Unread button appears at the leading edge on the simulator and tapping it
  puts the message back to unread (the title goes 6667 → 6668), and on the
  emulator a long right drag marks one read outright.
- **Keyboard avoidance across all four renderers (2026-09-18).** A focused
  field no longer sits under the on-screen keyboard. Each target needed its own
  answer, because only Flutter had one already: **iOS** pins the rendered
  container to the host view with a bottom constraint and shortens it by however
  much of the host the keyboard covers, in step with the keyboard's own
  animation, then scrolls the first responder into view inside its nearest
  scroll view (UIKit does neither by itself, and a plain `UIScrollView` ignores
  the first responder); **Android** pads the container's bottom by the measured
  overlap and calls `requestRectangleOnScreen` on the focused view, measuring
  rather than trusting the IME inset so that `adjustResize` and edge-to-edge -
  which need different answers - both come out right; **web** publishes the
  visual viewport's height as `--dnn-viewport-height` and sizes the scaffold by
  it, since `100vh` does not shrink for a keyboard; **Flutter** already had it
  from `Scaffold.resizeToAvoidBottomInset`, now pinned by a test so a later
  change cannot drop it. The container shrinking is what lifts a bottom sheet or
  dialog too, since both are anchored inside it. Verified on both, running the
  text-input showcase natively and focusing its Message field - the one low
  enough for the keyboard to reach: on an iOS simulator (iPhone 17 Pro, iOS
  26.4) and on an Android emulator (Medium_Phone, API 37) the keyboard opens,
  the field lifts clear of it, typing round-trips with the character count
  patched in place, and dismissing restores the full height. Reverting the iOS
  half and repeating the tap focuses the field and moves nothing, which is the
  behaviour this replaces. The Android half has had its physical-device pass
  since 2026-09-24: on an Android phone, tapping the Message field lifts it from
  y=1976..2243 to y=1144..1411, clear of the keyboard and with the caret in it.
  The helper line under it ("Characters: 0") is still partly behind the
  keyboard, which is the fixed-12 margin below. Left: the same pass on an iOS
  phone rather than a simulator; a field inside
  a *scrolled* modal sheet, which nothing exercises yet; and the margin above
  the keyboard is a fixed 12, not the field's own helper text, so a tall field's
  helper line can still sit under the keyboard.
- **The return key advances through a form (2026-09-19).** A `TextField` takes
  a `textInputAction`: `done` closes the keyboard, `next` moves to the field
  after it. What "next" means is the reading order of the tree, so an app never
  names the field - and the last field has nowhere to go, where closing the
  keyboard is the right thing anyway. A disabled field is stepped over, and a
  multi-line field keeps its newline key whatever the action says.

  Each platform wants it asked for differently: iOS sets `returnKeyType` and
  moves the first responder itself, since UIKit has no traversal to lean on
  (`nextFocusedView` is for focus engines, not a return key); Android sets
  `IME_ACTION_NEXT` and hands the action back to the platform, whose own
  traversal is already the reading order; web sets `enterkeyhint` and focuses
  the next input in document order; Flutter sets `TextInputAction.next` and
  calls `nextFocus()`. The submit event still fires everywhere, so an app that
  listens for it hears the same thing either way.

  Verified on an Android emulator and an iOS simulator with the text-input
  showcase, whose first two fields now ask to advance: the keyboard's return key
  reads as "next" on both, pressing it moves the caret to the email field and
  leaves the keyboard up.

  The iOS half needed two goes. Hanging the advance off `editingDidEndOnExit`
  looked right and never fired - by then the field is already resigning, and the
  keyboard is on its way out. It belongs in `textFieldShouldReturn`, which runs
  *before* the resign, so advancing is a plain change of first responder rather
  than a fight with one.

  Left: this is the "next field" behaviour, not general focus traversal - there
  is still no way to say what follows what.
- **The app can move the caret itself (2026-09-22).** `TextField` takes an
  `autofocus` and a `FocusNode`: the first takes the keyboard when the field
  appears (a search screen, a one-question form), the second asks for it - or
  gives it up - whenever the app decides. `TextFormField` takes the node too,
  so a form can send the user to the field that needs attention; the sign-up
  example does exactly that, and the text-input showcase has a pair of buttons
  that focus and dismiss.

  A tree carries states, and "focused" is not one: a field that simply *was*
  focused would take the caret back on every unrelated re-render. The ask
  travels as a version instead - the same trick `valueVersion` uses - so a
  number that changed since the last render is one ask, obeyed once. `autofocus`
  is the same thing with a fixed version, answered the first time the field is
  drawn and never again. Every renderer defers the actual focus to after the
  view is in the document/window, because focusing a detached view does nothing
  at all (and that was the first way each of the four got it wrong).

  Both natives answer the ask on the *patch* path as well as when building the
  view: a second failed submit changes nothing about the field except the
  version, so a renderer that only looked at build time would do nothing - the
  case a form hits most. A source-level test pins that on both, and falsifying
  it (deleting either call) fails it.

  Verified on a physical Android phone (Android 17) on 2026-09-24: `focus.yaml`
  passes there, and by hand the name field takes the caret with its label
  floated and the keyboard up. Before that, by hand on an Android emulator
  (Medium_Phone, API 37) and an iOS
  simulator (iPhone 17 Pro, iOS 26.4), running the sign-up form and the
  text-input showcase natively: submitting the empty form opens the keyboard
  with the caret in Full name, typing lands there, submitting again moves the
  caret to Email, and the showcase's two buttons focus the name field (status
  flips to "Focused", the keyboard comes up) and dismiss it again (status
  "Not focused", keyboard gone).

  Left: only a *named* field can be asked for - there is still no "focus the
  next one" without the keyboard's return key, and no focus order an app can
  declare.
- **Accessibility — the named controls now, the listening still not
  (2026-09-19).** Tooltips, image alt text and the overlays already carried
  semantics (dialog roles and modality, a live region for snackbars). What was
  missing was the thing a form is made of:

  - **A text field had no name.** The visible label was a separate piece of
    text as far as assistive technology was concerned, so a field was reached
    and announced as "edit text". Web ties them with `for`/`id`; iOS sets the
    field's `accessibilityLabel` from the label rather than leaning on the
    placeholder; Android points the label's `labelFor` at the field. A field
    with no visible label is named by its placeholder instead, since that is
    what the user sees.
  - **An error was a colour.** A red border says nothing. Web marks the field
    `aria-invalid` and points `aria-describedby` at the message; iOS puts it in
    the field's `accessibilityHint`. Both come off again when the field is
    valid.
  - **A checkable control did not say whether it was on.** On iOS the state
    lives in the button's *image*, which a screen reader cannot read, so the
    `.selected` trait carries it now - on build and on the patch path, which
    re-derives the state.

  Eight tests assert what assistive technology would actually find on web.

  **The natives are checked now too (2026-09-21).** `maestro/native/flows/
  a11y_android.yaml` and `a11y_ios.yaml` read the platform's own accessibility
  tree and assert what a screen reader would be handed: a checkbox, a radio
  group and a switch, each announced with its label *and its state*, and each
  state moving when the control is tapped. That is the part that used to be
  unverifiable - on iOS the state lives in the button's image, where nothing
  can read it, so the `.selected` trait carries it, and the flow asserts the
  trait rather than the picture. Falsified by expecting the wrong state, which
  fails on both. Still not covered: a text field's *name* on Android, which
  comes from `labelFor` and does not appear in the tree.

  **On iOS none of it reached anything (fixed 2026-09-21).** A `FlutterView`
  answers `accessibilityElements` with Flutter's own semantics, and UIKit takes
  that list *instead of* the view's real subviews - so every native view this
  renderer draws was invisible to the accessibility tree. The labels, hints and
  traits above were all being set, and VoiceOver would have found an empty
  screen. `controller.view.accessibilityElements = [container]` puts the
  subtree back; the whole screen now appears in the tree, which is also what
  made the device flows below possible. Found by pointing Maestro at the app
  and getting back nothing but the app's own name.

  Left, and the honest state: **nothing has been tested with a screen reader**,
  which is still the only way to know whether any of this *sounds* right. Focus
  order is the platform's own (the reading order of the tree) rather than
  anything an app can state.
- **Forms — bound to text fields (2026-09-17).** *(Renamed 2026-10-03: `Form`,
  `FormField` and `TextFormField` are Flutter's widgets now. The model this
  entry describes is exported from `widgets.dart` as `FormModel` and
  `FormFieldModel`, and the field bound to it is `ModelTextFormField(field:)`.
  Read the names below with that in mind.)* `TextFormField(field:)` binds a
  `FormField` to a facade `TextField`: it shows the field's value, label, hint
  and validation error, reports edits with `setValue`, and validates on submit
  (and blur). It rebuilds itself when a validator reports an error, so a submit
  that calls `form.validate()` shows every field's error without the app
  rebuilding. `Form`/`FormField`/`FormBuilder`/validators are now exported from
  `widgets.dart`.

  **Finished 2026-09-21**, and the finishing turned up two regressions worth
  more than the feature. What was asked for:

  - **An error goes as the value is fixed.** Once a field has shown one, every
    edit re-checks it, so the message clears while someone is typing instead of
    standing until the next submit. A field that has never failed is still not
    validated per keystroke - the first check is the blur or the submit, which
    is where being told is useful. A validation that is overtaken by a later
    one no longer repaints (the answer it carries is stale).
  - **`Form.submit(onValid)`**: validate everything, show every error at once,
    and run the work only if there is nothing to show. `Form.firstInvalid`
    names the field to point at, in screen order.
  - **A whole-screen example**: `signup_form` - four fields that depend on each
    other (the confirmation matches whatever the password holds now), a submit,
    a failure message and a success state. It is in the catalogue, so the
    smoke tests, the tree golden and both device lanes cover it.

  What running it on a device turned up:

  - **Android text fields had stopped reporting what was typed.** The floating
    label work (2026-09-19) deleted the one line in the
    `TextWatcher` that sends `<eventId>_change`, so for two days every bound
    field on Android looked perfect - drew, focused, kept its caret - and told
    the app nothing. Nothing failed: the device lane checks what a renderer
    *draws*, not what it reports, and the Android device pass predates the
    regression. `renderer_coverage_test` now reads the body of each native's
    text-change handler and fails if it stops sending the event; falsified by
    deleting the line again, which names Android.
  - **A stale echo ate keystrokes on both natives.** The value in the tree
    follows the user's own typing a beat behind, and both renderers treated
    "the value differs" as the app having changed it - so a re-render mid-word
    wrote the older value back and dropped whatever had been typed since
    ("Ada Lovelace" arrived as "Ad"). Only a bumped controller version counts
    as the app's doing now, which is what the version was added for.
  - **An error appearing mid-typing rebuilt the iOS field.** The error label
    was only built when there was a message, so a validator answering while
    someone typed changed the field's own view tree - a rebuild, which takes
    the keyboard and the first responder with it. The label is always there
    now, hidden when there is nothing to say, and the patch path sets its text.
    Android has always had this through `TextInputLayout`.

  Verified by hand on an emulator and a simulator: submit with nothing filled
  in shows four errors and names the first, typing a valid name clears its
  error as the letters land, and a full name or email arrives whole.
- **Icons now use Flutter's Material Icons font (2026-09-14), fixing the FAB.**
  The native renderers draw icons as real glyphs from `MaterialIcons-Regular.otf`
  - the font `uses-material-design: true` already bundles into every build - so
  the icon set is the full ~2,000 Material glyphs at Flutter/web fidelity, not
  the old dozen approximate system drawables (which is why the text-input FAB
  showed a dark `presence_online` dot). `UIBuilder.iconButton`/
  `floatingActionButton` resolve the name to a codepoint (`materialIconCodepoint`,
  a curated table; a caller can pass any `codepoint` directly for icons outside
  it) and send it alongside the name. Android draws the glyph to a tinted
  drawable, iOS sets it as a button title in the icon font. The name stays in the
  tree, so the web renderer's ligature path is unchanged. iOS no longer keeps an
  SF Symbol fallback (2026-09-18): it only mapped ~22 names - the rest a
  placeholder dot - and never rendered in practice since every facade icon
  carries a codepoint and the font is always bundled, so it was dead code that
  would only ever have drawn an off-brand icon; a codepoint-less button is now
  left glyphless instead, and the FAB defaults to the add codepoint so a
  childless FAB still shows its `+`. ~~Left: grow the curated
  name→codepoint table~~ - done 2026-09-21: `tool/generate_material_icons.dart`
  reads Flutter's own `icons.dart` and writes both tables, so every one of the
  2,231 filled Material icons can be named (`Icons.shopping_cart`) and drawn,
  with the codepoints that match the font `uses-material-design: true` bundles.
  ~~The rounded, sharp, outlined and two-tone variants are left out on purpose:
  they live in fonts Flutter does not bundle, so their numbers would draw
  whatever happens to sit there in the filled one.~~ - wrong, and put right
  2026-10-03: Flutter keeps every style in the one `MaterialIcons` font, so
  `Icons` now has all 8,825 names and the web shell ships that same font
  instead of mapping codepoints back to another font's ligatures. Ten of them checked by eye
  on an emulator and a simulator - a magnifier, a heart, a house, a cog, a
  cart, a calendar, a cloud, a padlock, a bell and a figure, all the right way
  round. Left: `renderText`-embedded inline icons if wanted.
- **Text that does not fit is cut off now (2026-09-21).** `Text(maxLines:,
  overflow: TextOverflow.ellipsis)`, Flutter's own spelling, on all four
  renderers: `text-overflow` for one line and a line clamp for more on web,
  Flutter's own `Text` on the Flutter host, `maxLines` with `TruncateAt.END`
  on Android, `numberOfLines` with `.byTruncatingTail` on iOS. An overflow
  with no cap means one line, as in Flutter.

  This was the thing keeping the inbox's preview lines short by hand - a
  sentence of unknown length would wrap and push a fixed-height row out of
  shape. The example now carries previews as long as real ones and ends them
  with an ellipsis; checked on an emulator and a simulator, where the rows
  keep their height and the text ends in `…`.

  Not carried: Flutter's `fade` and `visible`. A fade is a gradient mask that
  UIKit, Android's TextView and CSS each spell differently enough that the
  same text would look like three different things.
- **Floating labels - real on three renderers, deliberately not on the fourth
  (2026-09-19).** A field's label used to be static text above the box
  everywhere, while the example calling itself "Floating Label Input" showed a
  plain label. Now a label floats by default, as Flutter's own `TextField`
  does:

  - **Web** does it in CSS, with no JavaScript: the renderer puts
    `dnn-textfield--floating` on the field and keeps a placeholder there, and
    `:focus-within` and `:placeholder-shown` raise the label. That is why a
    floating field with no hint carries a single space - an empty placeholder
    is never "shown", so the label would start raised over an empty field.
  - **Android** uses the real thing, a Material `TextInputLayout`: the label is
    its hint, the error is drawn by the layout (so a validation message no
    longer changes the field's view tree and a patch keeps the caret), and the
    app's hint text becomes the placeholder that appears once the label is out
    of the way.
  - **The Flutter host** already floated `InputDecoration.labelText`; what is
    new is that it honours the opt-out, drawing a label of its own above the
    field.
  - **iOS keeps the label above the field**, whatever the tree says. UIKit has
    no floating label - it is a Material pattern - and iOS forms label a field
    above it or with the placeholder alone. This is the one renderer that does
    not float, and both the protocol and the Swift say so.

  `floatingLabel: false` (`FloatingLabelBehavior.never` through the
  Flutter-shaped facade) puts the label back above the field on all four. Only
  the opt-out travels in the tree: absent means floating.

  Verified on the Android emulator with the text-input showcase - the label
  floats and animates, typing keeps focus and caret through the patch path,
  and an invalid email draws the layout's own error. Two things came out of
  that run and are worth knowing: a `TextInputLayout` built in code takes
  neither the theme's outlined style nor a box set on it afterwards (the box
  simply never drew), so the field wears Material's filled box; and it draws no
  box at all until the editor's own background is cleared, which takes the
  editor's padding with it, so the room the floated label needs is stated in
  the renderer.

  Left: the animation itself is only ever checked by eye - six browser tests
  assert the hooks the stylesheet selects on and four read the shipped CSS for
  the rules that move the label, but nothing asserts that it *moved*.
- **State beyond one screen - a store outside the tree (2026-09-19).**
  `setState` holds what one screen owns, and that was the only pattern there
  was. It cannot hold what two screens share: a routed app rebuilds a screen on
  the way back and disposes its `State`, so a favourite marked on a user's page
  was gone by the time the home page counted them.

  `ValueNotifier`, `ValueListenable`, `ChangeNotifier` and `Listenable` now live
  in the core, with Flutter's own names, signatures and semantics - an equal
  value is not a change, a value mutated in place is not one either. A screen
  follows one with `ValueListenableBuilder` (or `ListenableBuilder`); a
  hand-written `NativeUIApp` calls `watch(store)`. Both are Flutter-compatible,
  so a screen written against the facade compiles against Flutter unchanged,
  which is the promise the rest of the widget layer makes.

  The subscription belongs to the *tree*, not to a widget: the framework
  rebuilds from the root and diffs, so one listener per listenable is all a
  rebuild needs. That also sidesteps the identity problem two keyless builders
  of the same type would otherwise have (the bullet above about keys), and it
  means a store is let go the moment the screen reading it leaves - and every
  store when the app unmounts, so a torn-down app is never asked to render.

  The routing example shows the shape: `routingFavourites` is written on a
  user's page and counted on the home page. Verified on the Android emulator
  through the native views - favourite Bob, go home, "Favourites: 1".

  Left: nothing persists a store across launches; that is `StorageService`'s
  job and the app's to wire. (This entry used to say there was no
  `InheritedWidget` and a store had to be a top-level value or passed down.
  There is one now - see "Hand a subtree a value" below - so a store can be
  handed to a subtree and read with `dependOnInheritedWidgetOfExactType`,
  which is what `Theme` is built on. The example still passes it down.)
- **i18n at the builder level - `Tr` (2026-09-19).** The translation table was
  complete and the screens did the work: every string went through the app's own
  `i18n.t('key')`, and the screen kept a listener so a `setLocale` somewhere else
  repainted it. Both are the framework's job now.

  `Tr('common.ok')` is a string from the table as a widget: it looks the key up
  where the text is drawn - params, plurals and a `defaultValue` included - and
  registers the locale as something this build depends on, so a language change
  redraws it. It works wherever a `Text` does, titles and button labels
  included, since the facade now reads the string out of either.

  `I18n` is a `Listenable` too, so a screen with locale-dependent strings that
  are *not* keys (a formatted date) can follow it with `ListenableBuilder`, and
  a hand-written app with `watch(getI18n())` - the same store plumbing as the
  bullet above.

  The i18n example lost its `State` entirely: it existed only to hold that
  listener. Its rendered tree is unchanged, which the goldens assert. Verified
  on the Android emulator: tapping ESPAÑOL repaints every row and the app bar
  title through the native views.

  Left: `getI18n()` before `initializeI18n` now says what to call rather than
  naming a private field, but there is still no compile-time check that a key
  exists - a missing one shows up on screen as the key itself, which is
  `I18n.t`'s long-standing behaviour and better than a crash in release.

---

## 4. Operational

- **Publish the repository - done (2026-09-26).** Hosted at
  `https://github.com/tomavelev/dart_not_native`. Both pubspecs carry
  `repository:` (and the package one `issue_tracker:`), the podspec `source`
  points at the git tag rather than a local path, and the integration guide
  offers a git dependency. What is left is pub.dev: `dart pub publish
  --dry-run` passed on everything but those URLs, so the package itself is
  publishable whenever a version is cut - see RELEASING.md. As of 2026-10-03
  three apps consume the framework, all by path, with the repository checked
  out beside them; what that costs them is §6.5.
- **CI landed (2026-09-16).** `.github/workflows/ci.yml` runs the lanes on
  every push and PR: `flutter analyze` plus the Dart/Flutter/DOM suites,
  `integration_test` on the Linux desktop host, an Android debug build that
  compiles the Kotlin renderer and every plugin's Android half, and — added
  2026-09-18 — an `ios-build` lane on `macos-latest` that runs
  `flutter build ios --simulator --debug --no-codesign`, compiling
  `NativeUIRenderer.swift` and every plugin's iOS half. That lane exists because
  its absence let the Swift renderer sit broken: the swipe-actions commit
  left `SwipeActionsView.gestureRecognizerShouldBegin` without an
  `override`, a hard compile error, and nothing noticed for two commits. It has
  run since 2026-09-26, when the repository was published: the first push found
  five red lanes, none of them in the framework - an executable bit, a
  `flutter test integration_test` that cannot start a second desktop app in one
  invocation, a flow that assumed a screen height, an unportable pixel golden
  and no timeouts anywhere. The web e2e (Maestro) and benchmark recording are
  still manual. Two device lanes
  were added on 2026-09-19 - see "A device lane in CI" below. Analyze gates on
  errors and warnings, not the pre-existing style infos.
- **A device lane in CI — landed (2026-09-19).** `integration_test/
  native_renderer_test.dart` mounts one tree holding *one of every node type*
  the protocol defines, a second for the iOS-flavoured half
  (NavigationStack/VStack/HStack/List/ListRow), and then all ten example apps,
  on whichever native renderer the device has - and a native render answers
  with what it could not draw. On a desktop host every one of them skips, so
  the Linux lane says "skipped" rather than passing on nothing.

  Two CI lanes run it: `android-device` boots an emulator
  (`reactivecircus/android-emulator-runner`, KVM enabled or the boot times
  out), and the existing `ios-build` lane now boots a simulator and runs it
  there too - the iOS half is the least device-verified one, so that is the
  lane that matters most for it.

  Verified by running both locally: 14 tests green on a Pixel-class emulator
  (Android 16) and on an iPhone 17 Pro simulator (iOS 26.4). **That is the
  first time every node type has been drawn by the Swift renderer.**

  It earns its place: reintroducing this session's `TextInputLayout`
  `LayoutParams` bug turns the run red. Worth knowing *how*, though - the
  exception is thrown from `LinearLayout.measureVertical` on the layout pass,
  not from `renderTree`, so the renderer's own try/catch never sees it and the
  app dies. The lane goes red because the process is gone, not because a test
  reported a message. Errors the renderer *can* catch (an unknown node type, a
  throw during the render itself) fail cleanly with their text.

  What it does not check: that anything *looks* right. "The native side
  reported no error" is a long way from "the screen is correct"; that is still
  eyes on a device, which is what §1.1 records.
- **Version and release discipline - written down and enforced (2026-09-19).**
  The CHANGELOG had one entry, 0.1.0, whose "Known limits" were by now all
  wrong: it said the native renderers had never run on a device and the
  vocabulary had no dialogs, sheets or snackbars. Everything since is now
  written up under `Unreleased`, with the limits that are still real (map and
  camera, nobody has looked at most iOS screens, no screen-reader pass, the
  repository is unpublished).

  `RELEASING.md` holds the convention: what is versioned (the framework, not
  the example app at the root), the 0.x reading of semver (a minor is where
  breaking changes go, and widening the node vocabulary is one), branch names,
  the `v0.2.0` tag on the commit that sets the version, and the checklist -
  every lane green including the two device lanes, CHANGELOG moved under its
  heading, three version fields changed together.

  Three fields, because a pub consumer reads the pubspec, a CocoaPods consumer
  the podspec and a Gradle consumer the build file, and nothing generates one
  from another. `packages/native_bridge/test/release_test.dart` fails when they
  disagree, when a library version carries an app-style `+1` build suffix, or
  when the CHANGELOG has never heard of the version in the pubspec.

  Not done, deliberately: no version has been cut. 0.2.0 is a three-file edit
  and a tag away, but the release it belongs to cannot be published until the
  repository is hosted (the item above), so the work sits under `Unreleased`
  where it can still be edited.
- **Device flows - a tap and a keystroke, through the real views
  (2026-09-21).** `maestro/native/` drives both native renderers on a device:
  `run.sh android|ios` builds and installs the entry point a flow names, then
  runs it. The counter flow taps its way from 0 to 3 and back; the text-input
  flows type into a bound field and expect the app to have counted the
  characters and validated the address.

  This closes the gap the device lane leaves. `native_renderer_test.dart` asks
  both renderers to draw every node type and listens for errors, which says
  nothing about whether anything it drew *works* - and that gap cost two days:
  the floating-label commit dropped the line that sends an Android text
  field's change event, and every bound field there went on drawing, focusing
  and keeping its caret while the app heard nothing. `textinput_android.yaml`
  fails on that in eight seconds.

  Maestro reads the platform's accessibility tree - the same one a screen
  reader uses - so a flow only passes if the views are *announced* as well as
  drawn. That is how the iOS renderer turned out to be invisible to
  accessibility entirely (see §3); the first iOS run came back with nothing
  but the app's name in it.

  `inbox.yaml` scrolls the ten-thousand-row list a long way and checks that
  the rows which arrive are the real ones - their own numbers, their own
  senders, and an actions button that opens *that* row's sheet - then scrolls
  back and finds row 1 where it left it. That is §1.4's virtualization claim,
  which until now had been checked by hand on a Pixel and an iPad and never
  since. Writing it also caught two things about driving these screens: a
  `Delete` assertion passed without a sheet at all, because every row has a
  Delete of its own behind the swipe, and Maestro's `back` is an edge swipe on
  iOS, which a modal sheet has no reason to answer - the flow taps the scrim,
  which is what a person does.

  It found a bug of its own on the first green run: the counter's Decrement
  and Reset buttons were missing on iOS, because the "a row takes the width it
  is offered" fix from the same day had no upper bound - inside a `Center`,
  which hands a child whatever it asks for, the row took all 10,000 points and
  put its children off screen. A row is capped at the window's width now, once
  it has a window to measure against.

  Both device lanes were taken out of CI on 2026-09-26 and live in
  `tool/device_check.sh` instead: they cost tens of minutes against about three
  for everything else, and they were the only lanes that ever hung. They are
  run by hand now, which RELEASING.md makes a condition of cutting a version.
- **Benchmarks - recorded, and the parts that survive a change of machine are
  asserted (2026-09-19).** `test/benchmark/` printed numbers into a log nobody
  kept, and a number cannot gate a build anyway: the runner owns as much of it
  as the code does.

  Two halves now. **Recorded:** every report also prints a `BENCH_JSON {...}`
  line, a `benchmarks` CI lane keeps them as an artifact, and
  `packages/native_bridge/test/benchmark/BASELINE.md` holds one full run with
  the machine it came from
  (an Apple Silicon Mac, Flutter 3.47.2) so a later run has something to be compared with.
  **Asserted, on every commit:** `scaling_test.dart` checks the shape of the
  curve - four times the rows costs about four times as much, not sixteen, so
  an accidental O(n²) fails wherever it runs - and
  `test/web_ui/render_cost_test.dart` checks the two promises the web renderer
  makes about its own work: re-rendering an unchanged tree costs a fraction of
  drawing one (~7x), the elements survive a re-render, and five renders in one
  tick cost about one. Each was weakened to watch it fail: switching the
  reconciler off breaks the first two, switching batching off breaks the third,
  and a quadratic step in the scene builder breaks the scaling test.

  Two things the numbers themselves say, both easy to assume wrong: patching a
  screen where one row changed is only about **1.8x** cheaper than painting it
  from scratch - most of a re-render is walking and comparing the tree, not
  touching the DOM - and keys pay for themselves on a front insert (0.40 ms
  against 0.50 ms). The 1.8x ratio is recorded rather than asserted: a first
  attempt at gating on it passed alone and failed inside the full browser
  suite, which is precisely the flaky test this design is meant to avoid.
- **Offline-first sync removed rather than published (2026-09-26).**
  `backend_sync_plugin.dart` was 243 lines declaring a sync queue - a retry
  policy, a pending operation that serialises itself, a conflict outcome, a
  network-status stream - and behind them 11 methods that threw
  `UnimplementedError`. No test, no example and no other file in the project
  ever called one. It was exported publicly from `native_bridge_flutter.dart`.

  That export is why it went. Publishing the package makes those types a
  compatibility promise, and they were a guess: a shape settled before a line
  of sync existed and before any real backend disagreed with it. Owing semver
  to a guess is worse than owing nothing. The API surface of a package about
  to be published is also the wrong place to keep a sketch.

  The thinking was not thrown away - the three write modes it distinguished
  (optimistic, blocking, queued) are a genuinely good decision, and a pending
  operation being a serialisable record rather than a closure is what lets a
  queue survive a process death. That, and the questions it never answered -
  where the queue persists, why the API is `static` on an `abstract class` and
  therefore untestable, what `operation` actually is, how conflicts resolve -
  are written up outside this repository as the seed of a separate package.

  Left: when sync is built it belongs in its own package, designed against a
  real backend. The plugin system is how it would be dropped in.
- **The pixel golden is gone, and why it had to be (2026-09-26).** A golden of
  the counter as the Flutter renderer paints it stopped passing on the very
  machine that wrote it: two pixels of the floating action button came out two
  parts in 255 lighter one engine build apart. `matchesGoldenFile` compares
  byte for byte, so 0.0007% of one frame was a red suite.

  The first answer was a tolerance - fail on how *far* a pixel moved (4 in
  255) and on how *much* of the frame moved (0.01%), so antialiasing is
  forgiven and a widget that moved is not. Both bounds were asserted by tests
  that drove frames either side of them, and each bound was deleted to watch
  its own test fail. It was a good answer to the question being asked.

  It was the wrong question. Those bounds were fitted to a drift measured
  between two versions of one engine on one machine. The first CI run put the
  same golden on Linux, where it drifted by **2810 pixels, 1.04% of the
  frame**, because FreeType and CoreText do not draw the same glyph edges at
  all. Nothing survives that: a tolerance wide enough to pass 1% of a frame
  would hide a widget that moved, so it would assert nothing while looking
  like it asserted something.

  So the golden, its comparator and the comparator's own tests are deleted.
  What is lost is less than it sounds - the suite draws with the test font,
  whose every glyph is the same box, so the picture only ever pinned where
  things were and how big, never which glyph. Swapping `Icons.add` for
  `Icons.remove` left it byte for byte identical. Identity was always the tree
  goldens' job, and structure is what this framework actually produces.

  The lesson is the benchmarks' lesson in pixels, arrived at the hard way: a
  number that belongs to the machine cannot be asserted, only recorded. A
  picture belongs to the rasteriser the same way.

---

## 5. Documentation — cleaned up (2026-09-17), again (2026-09-19), and brought up to the widget layer (2026-10-03)

**2026-10-03.** The docs described the framework as it was before the widget
layer took Flutter's shape. Brought up to date: both READMEs (the root one
still had a table saying Android and iOS were "Flutter + optional FFI"; the
package one described only the FFI bridge), `INTEGRATION.md` - which gained
§8, a migration guide for an existing Flutter app, written from the three
migrations - `API_REFERENCE.md`, and the smaller guides where a rename or a
changed signature had made them false. One claim was found wrong rather than
stale: `ROUTING_GUIDE.md` said the browser's Back button pops named routes
with nothing to wire, and it does not (§6.3 item 11). Every snippet written
or kept was analysed against the current API.

The earlier passes:

The first pass removed ~38 stale markdown files: the "✅ Complete!" / "Summary"
build-completion artifacts, the contradicting roadmaps, the plugin
implementation guides for the removed device services, and the feature guides
that taught the deleted low-level `UIBuilder`/`NativeUIApp` API or referenced
removed examples.

It kept four guides as "still accurate" that were not. The second pass checked
them against the code and removed seven more files:

- **`OFFLINE_FIRST.md`** (488 lines) documented `BackendSync.optimisticUpdate`,
  `ConflictResolver` and `LocalCache`. None of them existed:
  `backend_sync_plugin.dart` declared the types a sync queue would need and
  performed no sync, as its own first line said. Both READMEs showed the same
  imaginary API; they say what is actually there now. (The plugin file itself
  went on 2026-09-26 - see the entry below.)
- **`STATE_MANAGEMENT_GUIDE.md`** (800 lines) taught Redux, Provider and GetX.
  Those need Flutter, and the widget layer here is deliberately Flutter-free, so
  none of it could be followed; the framework's own answer is the `ValueNotifier`
  / `ListenableBuilder` support in §3, which the README documents.
- **`DEPLOYMENT_GUIDE.md`** (572 lines) was generic Flutter release advice with
  no mention of this framework, and its web section recommended
  `flutter build web --web-renderer html` - a flag this Flutter no longer has,
  for a web target that is not Flutter web at all.
- **`MAESTRO_WINDOWS_INSTALL.md`** (288 lines) configured one machine's Maestro
  install, hard-coded to `C:\Users\progr\...`. The flows have their own README.
- **`TEXTINPUT_COMPLETE.md`**, **`TEXTINPUT_SHOWCASE_SUMMARY.md`** and
  **`SHOWCASE_COMPLETE.md`** were the previous pass's own leftovers: a second
  `TextField` reference and two showcase summaries, all covered by the guides
  beside them. The one thing only the reference explained - the controller's
  version counter - moved into `TEXTINPUT_GUIDE.md`, which also gained the
  return-key and floating-label properties that landed since.

The three published ones mattered most: `STATE_MANAGEMENT_GUIDE`,
`DEPLOYMENT_GUIDE` and `MAESTRO_WINDOWS_INSTALL` all sat inside
`packages/native_bridge/` and would have shipped to pub.dev.

The kept set: the two READMEs, `INTEGRATION.md`, `TESTING.md`, `RELEASING.md`,
this file, the example references (`EXAMPLES_DIRECTORY`, `COMPONENTS_SHOWCASE`,
`SHOWCASE_GUIDE`), the guides that are true (`I18N_GUIDE`, `ROUTING_GUIDE`,
`TEXTINPUT_GUIDE`, `API_REFERENCE`), the benchmark baseline and
`maestro/web/README.md`. Every markdown link in the repository was checked;
`I18N_GUIDE` had been pointing at a `FEATURE_ROADMAP.md` deleted in the first
pass, and its stale roadmap section (listing state management as "next", which
landed today) is gone.

Fresh facade-based guides replaced the removed ones: `ROUTING_GUIDE.md`
(named routes, params, history), `TEXTINPUT_GUIDE.md` (text fields + validated
forms via `FormBuilder`/`TextFormField`), and `packages/native_bridge/API_REFERENCE.md`
(entry points, theming, storage, biometrics, i18n, the plugin system).

---

## 6. Open after the migration work (2026-10-03)

What is known to be open now that three real apps run on the widget layer.
Every item traces to the code, a doc comment or the changelog - the place is
named - and the order inside each group is the order I would do them in.

### 6.1 iOS: the gallery has been looked at; the three apps have not

**The iOS renderer as it stands passes the device check on a simulator, and
one screen of the new vocabulary has been looked at.** The last iOS anyone
watched before that - five flows on a
simulator, the release build on an iPad, 2026-09-24 - was the 47-node
vocabulary. Since then
`ios/dart_not_native/Sources/dart_not_native/NativeUIRenderer.swift` gained about 2,100 lines and
`ios/dart_not_native/Sources/dart_not_native/NativeUIViews.swift`, 2,040 lines, is new; all of it was written
on a machine with no Xcode. The source-level tests in
`renderer_coverage_test.dart` read the Swift for the dispatch and for a
handful of behaviours; they do not compile it. The `native.yml` lane does, and
on 2026-10-05 it built all of it for the simulator.

On 2026-10-09 `tool/device_check.sh ios` ran on an iPhone 18 Pro simulator
(iOS 27.0) and passed: the five Maestro flows (`a11y_ios`, `counter`, `focus`,
`inbox`, `textinput_ios`), `app_test.dart` (2 tests) and
`native_renderer_test.dart` (14 tests: one of every node type in the lane's
tree, the navigation vocabulary, and each of the twelve example apps drawn
with nothing reported undrawn). The examples' trees hold eight of the twelve
new node types - `Box`, `Stack`, `Positioned`, `Scroll`, `Icon`, `Canvas`,
`BottomBar`, `BottomNavigation` - so those have been through the Swift.
`Dropdown`, `DatePicker`, `TimePicker` and `FlutterSlot` have not.

That was a renderer saying it drew everything, not a person saying it drew
it right, and the difference showed the same day. The controls gallery was
walked on that simulator - three tabs, every control driven - and five things
were wrong that the green run had not said: a `Stack` of layers that drew
nothing, a slider with no track, a progress bar a few points long and a field
and a card as wide as their words (one cause: only a `Row` was told to take
the width of a column that aligns to one side); an app bar a third of the
screen tall over a short page; a card's star in the middle of the card; a
disabled button that looked enabled; a list tile stretched to fill a short
scroller. All five are fixed in the Swift (changelog, "The iOS renderer runs
again"). The dropdown, the date picker and the time picker were opened by
hand and returned what was chosen.

The opening screen of seven other examples - components showcase, design
system, sign-up form, routing, todo, calculator, text input - was then
screenshotted with the Swift as it was before those fixes and as it is after,
and the two compared (2026-10-10). Nothing got worse. Four of the seven had
the same tall app bar the gallery did, a third to half of the screen, and the
green device check had passed over every one of them; the todo's field and
the text-input showcase's fields were as narrow as their placeholders. The
calculator is pixel for pixel what it was. That is one screen of each, not
the apps walked.

The device lane's tree has the twelve new node types now:
`native_renderer_test.dart` draws a free-form tree and a screen under each
picker (17 tests), green on the simulator. **Those three tests have not run
on Android** - there was no emulator to run them on - so the first Android
run of `device_check.sh` is also their first.

What is still a claim about text on iOS: right-to-left, the image cache, a
`FlutterSlot` with a real Flutter widget behind it (the lane draws only its
fallback), drag and drop, the scroll reports, and every screen but the
gallery. In order:

1. ~~`flutter build ios --simulator --debug --no-codesign`~~ - done by the
   `native.yml` lane, 2026-10-05, which repeats it whenever the renderers
   change.
2. ~~`tool/device_check.sh ios` on a simulator: the five flows, then the
   integration lane.~~ - green, 2026-10-09, as above.
3. The three migrated apps on a simulator, screen by screen, as was done on
   the Android emulator - those passes found about thirty bugs there and iOS
   has had none of it.

Where to look first, because it is code whose behaviour cannot be judged by
reading it:

- **`DnnBoxView`** - one view carrying size, padding, gradient, border,
  shadow, clip, transform, four gestures, `UIDragInteraction` drag and drop
  and animated changes. The Android counterpart is where several of the
  emulator pass's bugs were: a clip outline that was empty on first layout, a box
  losing its child's stated size, a row in an aligned box not getting the
  box's width.
- **The `FlutterSlot` hole** - `DnnFlutterSlotView` has to be see-through and
  touch-through, `DnnRootContainerView.hitTest` has to let those touches fall
  to the Flutter view underneath, and `dnn:slotRect` has to report the
  rectangle in the Flutter view's coordinates. Any one of the three wrong and
  an ad is invisible, untappable or in the wrong place.
- **`DnnCanvasDrawingView`** - the Core Graphics replay of the command list.
  Angles are y-down, where Core Graphics' `clockwise` means the opposite of
  what it says; text is drawn from its top-left corner with an alignment
  relative to `maxWidth`.
- **`DnnScrollView`** - pull-to-refresh, and the scroll-to that is obeyed
  once per `scrollVersion`.
- **Right-to-left** - iOS forces `semanticContentAttribute` on every view,
  where Android sets one property on the root. Every hand-positioned view
  (grid cells, the lazy list's rows, swipe actions, the stack) has to agree.
- **The pickers and the dropdown** - the picker code branches on iOS 13.4
  and 14 for its style, and `DnnDropdownView` on iOS 14 for its menu, so
  there are paths a single simulator will not take.
- **`DnnTabBar` / `DnnRailView`** - bottom navigation against the safe area,
  which is where the app bar and the scaffold both needed a second go.
- **The patch path.** A node that holds children has to be in the Swift
  reconciler's `childViews` or it is rebuilt instead of patched, and nothing
  fails when it is missing - a field inside it just loses focus. The coverage
  test pins this for the motion nodes only.

The build number is in the same state as the rest: **the Swift that sends it
back with each event compiles and has not been tried against that case** (changelog, "An
event is answered by the build it was raised against"). Until it has run, the
stale-callback bug fixed on Android - a list's size report landing on a row's
tap after the window moved - is not known to be fixed there. The same goes for
the scroll reports, the snackbar's position and the scrolling rail that
Android gained on the emulator: written for iOS, compiled, not checked.

**Done when:** the Swift builds (done), `device_check.sh ios` is green (done,
2026-10-09), the device lane's tree includes the new node types (done,
2026-10-09, and unrun on Android), and the three apps have been looked at on
a simulator.

### 6.2 What the widget layer accepts and does not do

Flutter's API is there so that code compiles; these are the places where it
compiles and then does less. Each is stated in the widget's own doc comment
(`lib/src/widgets/<file>.dart`). Ordered by how likely a migrated app is to
notice.

1. **No `AnimationController`.** `Animation` exists for signatures and stands
   still (`motion.dart`); there is no `Tween`, no `AnimatedBuilder` driven by
   a controller. A `Ticker` is a 16 ms timer whose tick, if it calls
   `setState`, is a full rebuild and a message to the platform
   (`binding.dart`). Anything explicit - a progress ring that eases, a shake,
   a staggered entrance - has to be restated as an implicit animation or a
   canvas. The real answer is probably a node that carries a timeline to the
   renderer, as `animateMs` carries an end state.
2. **No page transitions.** `MaterialPageRoute` shows its page at once;
   `PageRouteBuilder.transitionsBuilder` is accepted and never called
   (`navigation.dart`); `router.dart` has no `pageBuilder`. A `Hero` is its
   child and nothing more.
3. **`onEnd` is never called** on any implicit animation - see the protocol
   gap in §6.3.
4. **Implicit animation is size, colour, opacity and transform only.**
   Padding, margin, alignment and borders land at once, so `AnimatedPadding`
   and `AnimatedAlign` do not animate; `AnimatedSwitcher`, `AnimatedCrossFade`
   and `AnimatedSize` show the new child with no transition (`motion.dart`).
   All curves collapse to the five every renderer has.
5. **A `ScrollController` hears scrolling a step behind, and on a windowed
   list not at all.** A scroller reports its offset when it comes to rest and
   at most every 100 ms on the way (verified on the Android emulator,
   2026-10-03), so `offset` and listeners follow the reader - enough for a
   "back to top" button or loading more near the end, not for moving
   something in step with the drag. A windowed `ListView` reports rows, not
   pixels: its controller still hears the app's moves only, and its
   `maxScrollExtent` comes from the stated row heights. `animateTo` arrives
   at once (`scrolling.dart`). No scroll notifications.
6. **Widgets that are not there**, which fail at compile time: `PageView`,
   `CustomScrollView` and every sliver, `DataTable`, `Stepper`,
   `ReorderableListView`, `InteractiveViewer`, `PopScope`. (`Hero`,
   `MouseRegion` and `PopupMenuButton` were on this list until 2026-10-04;
   the first two are now there in name, the third opens a dialog.)
7. **`TextPainter` cannot measure.** Widths are 0.55 x the font size per
   character (`custom_paint.dart`). Text on a canvas is placed correctly
   because the box travels with it; a painter that *fits* things around
   measured text - a chart's axis labels, a word game's tiles - is working
   from an estimate.
8. **`Dismissible` reveals an action rather than sliding the row away**, and
   does nothing for a vertical direction; a `Draggable`'s `feedback` and
   `childWhenDragging` are not drawn and only `onDragCompleted` is called;
   `GestureDetector`'s `onTapDown`/`onTapUp`/`onTap` fire together after the
   tap (`gestures.dart`).
9. **`TabBarView` does not swipe**, and a tab change does not animate.
10. **Snackbars are not queued**: the newest replaces the one showing. Their
    colour, shape, margin and `behavior` are not carried (`navigation.dart`).
11. **`Scaffold.drawer` is a sheet**, opened by a menu button the app bar
    gains - not a panel from the side. A scaffold nested in another's body is
    composed from a column and a stack.
12. **Canvas paint is flat colour.** Shaders (so gradients), mask filters,
    blend modes, `clipPath` and `saveLayer` paints are not carried;
    `Path.addRRect` adds the plain rectangle and `arcToPoint` a straight line.
13. **`Image.loadingBuilder` and `frameBuilder` are never called**, and
    `errorBuilder` is called once, up front. `color` tinting is not applied
    (`text.dart`).
14. **Focus is text fields only.** `FocusScope.nextFocus()` does nothing
    (`inputs.dart`); every `KeyboardListener` on screen hears every key
    (`binding.dart`).
15. **`TimeOfDay.format` knows two conventions**: twelve-hour for English,
    twenty-four for everything else.
16. **`State.didChangeDependencies` runs once**, and `updateShouldNotify` is
    not consulted (`lib/widgets.dart`).

### 6.3 Protocol gaps

Things no widget can do because no node can say them. Each needs a prop or an
event, and then the same work in four renderers.

1. **No animation-finished event.** A renderer animates the difference
   between two trees and never reports the end, which is why `onEnd` is dead
   (`AnimatedOpacity`'s doc comment). The first thing an explicit-animation
   design needs.
2. **No colours on `Toggle`, `Checkbox`, `Radio`, `Slider` or
   `FloatingActionButton`.** The widgets accept `activeColor`,
   `backgroundColor` and the rest and carry none of them (`buttons.dart`);
   every one is drawn in the theme's primary. An app whose brand needs one
   green switch cannot have it.
3. **`LazyList` has no refresh and no padding.** A `RefreshIndicator` over a
   windowed list is "its child and no more", and the list's padding is a
   `Padding` node around it rather than scrolling content inset
   (`scrolling.dart`). The lists long enough to be windowed are the ones most
   likely to want pull-to-refresh.
4. **Text spans cannot be tapped.** `spans` are styled runs; `TextSpan` has
   no `recognizer` and a `WidgetSpan` is left out of the line (`text.dart`).
   "By continuing you accept the *terms*" has to be a `Row`.
5. **Only the screen has a direction.** `RootProps.textDirection` is one prop
   on the root. A `Directionality` deep in a screen turns the widget layer's
   values and rows below it, not the platform's own controls there
   (changelog; `_screenDirection` in `lib/widgets.dart`). An LTR code field
   in an Arabic form is not expressible.
6. **Swipe actions are not mirrored.** `SwipeActions` is "swiped left" for
   its trailing actions in every direction - Android places the two bars with
   `Gravity.LEFT` and `Gravity.RIGHT` - and `Dismissible` maps `endToStart`
   onto it without consulting the direction. In Arabic the delete is on the
   wrong side.
7. **Drag and drop reports only the drop.** No start, no end over nothing
   (`Draggable`'s doc comment), so a board cannot highlight the piece being
   moved or put it back.
8. **A text field's look does not travel.** `TextField.style`, and
   `InputDecoration`'s `border`, `filled`, `fillColor` and `contentPadding`,
   are accepted and not carried (`inputs.dart`).
9. **No pixel offset back from a `LazyList`.** `Scroll` reports
   `{offset, maxExtent, viewport}` through its `scrollEventId` now; `LazyList`
   still reports its visible range of rows and nothing finer, which is the
   remainder of §6.2 item 5.
10. **`NavigationRail`'s `leading`, `trailing` and `extended`** are not drawn.
11. **`MaterialApp(routes:)` and `Navigator.push` are not in the browser's
    history.** `_MaterialAppState` binds the back gesture with no history
    adapter and `runWebApp` binds none for a widget host, so on web the
    browser's Back button leaves the page and the URL never changes. Only
    `GoRouter.attachHistory` mirrors. `ROUTING_GUIDE.md` said otherwise until
    2026-10-03.
12. ~~**The device lane's "one of every node type" is 47 of 59.**~~ Closed
    2026-10-09: `integration_test/native_renderer_test.dart` draws the twelve
    new types as well - a free-form tree and a screen under each picker -
    green on an iOS simulator and **not yet run on Android**. What is left of
    it: no Maestro flow touches any of them (the agent-device flows do, on
    Android only), and the lane's `FlutterSlot` has no Flutter widget behind
    it, so it draws the fallback.

### 6.4 What the Android emulator passes left open (2026-10-03)

What this section used to list as under way has landed and was seen on the
emulator: a scroller comes back where it was when a pushed page is popped,
and reports its offset; a snackbar sits above the scaffold's bottom bar and
floating button; a navigation rail scrolls when its items do not fit; Android
draws Material 3 shapes and metrics (40dp stadium buttons, 80dp bottom
navigation with its pill, the Material 3 floating button, 12dp cards, the app
bar staying at 56dp as Flutter's does); the widget layer's `AppBar` resolves
its colours as Flutter does and always sends them. The changelog's "Three
real apps on an Android emulator" has each. What is left:

1. **A windowed list's offset.** `LazyList` reports rows, not pixels (§6.3
   item 9), so a `ScrollController` on a `ListView` with `itemExtent` does not
   follow the reader.
2. **A snackbar does not know a nested scaffold's floating button.** A
   scaffold nested in another's body is composed, its button with it, and the
   snackbar clears only what the outer scaffold owns.
3. **`ElevatedButton` is drawn as a filled primary button** where Flutter's
   Material 3 draws a tonal one on the surface.
4. **A disabled button's look on Android** has not been settled against
   Flutter's.
5. **`useMaterial3: false` still gets Material 3 shapes on Android.** The
   widget layer honours the flag for the app bar's colours; the Material views
   are built against a Material 3 theme regardless.
6. **Not verified on any device:** `dnn:key` hardware keys, how
   pull-to-refresh feels under a finger, the Material date and time pickers
   (no migrated app opens one), a tap on an ad inside a `FlutterSlot`, a slot
   inside a scroller, and the image disk cache offline or at expiry.

All of the above was an emulator. §6.5 item 8 is the phone.

### 6.5 Publishing, and living with apps that depend on this

1. **Cut a version.** The pubspec still says 0.1.0 and everything since -
   including a section of breaking changes - sits under `Unreleased`. By
   RELEASING.md's own rule this is 0.2.0. Three apps depend on "whatever is
   in the checkout", which is no version at all.
2. **pub.dev.** The apps depend by path (`../dart_not_native/packages/
   native_bridge`), so each of their build machines needs this repository
   checked out beside them at a compatible commit; a git dependency with a
   `ref:` is the stopgap. `dart_not_native_bloc` is `publish_to: none` until
   the main package is hosted, and depends on it by path itself.
3. **CI for the consuming apps.** Nothing here builds an app that depends on
   the framework, so a breaking change in the widget layer is found when
   somebody next builds one of the three. The cheap version is a lane that
   checks out one of them and runs `flutter analyze` and its tests against
   the commit under test.
4. ~~**CI does not run `packages/dart_not_native_bloc`.**~~ `ci.yml` analyses
   it and runs its suite since 2026-10-09, and `tool/count_tests.sh` counts
   it.
5. **Ship the test harness.** `test/support/app_tester.dart` is copied into
   every consuming app because it is not exported. It wants to be a public
   testing library.
6. **`--no-tree-shake-icons` on every build.** Forgetting it fails a release
   build inside Flutter's icon tree shaker (`_iconData` in
   `lib/platforms/flutter_renderer.dart` says why). Either stop making
   `IconData` at run time on the paths a release build can see, or document
   the failure where it will be searched for - INTEGRATION.md §5.2 does the
   second.
7. **The gen-l10n bridge is written per app.** Ten lines, the same ten in
   two of the three apps, and mobile-only because the generated code imports
   Flutter. A documented pattern today (INTEGRATION.md §8.4); a candidate for
   a small generator or a companion package.
8. **Run the device checks on a phone again.** The physical-device evidence
   (2026-09-24) is all from before this work. `tool/device_check.sh android`
   on the phone - which will also be the first Android run of the three
   tests §6.3 item 12 added.

---

## What is already solid

Worth stating, so the list above is read in proportion:

- The protocol, the router, forms, i18n, overlays, lazy lists, storage
  contracts, the plugin system and the design system are covered by 1917 tests
  (1008 in the package, 388 for the example apps and goldens, 478 in the browser,
  43 in the bloc package,
  counted 2026-10-09), plus 19 integration tests that run on a real Android and
  a real iOS - two of them the Flutter-hosted app, seventeen the native
  renderers drawing the whole node vocabulary and every example app. (Three of
  the seventeen - the free-form tree and the two pickers, added 2026-10-09 -
  have run on an iOS simulator only.)
- The web DOM renderer is tested in a real browser, including markup goldens
  for three style kits, reconciliation behaviour, the back button, overlays
  and a scrolling lazy list.
- The Flutter renderer paints every node type, and every example app in the
  catalogue (eleven) is rendered through it and checked for overflow at phone
  size.
- The widget layer is exercised family by family
  (`test/apps/flutter_facade_test.dart`, `packages/native_bridge/test/widgets/`,
  `packages/native_bridge/test/router/`), and three production apps have
  test suites of their own written against it.
- Rendering is coalesced per tick and reconciled structurally, with benchmarks
  behind the numbers.
- Integration is a dependency and one call, on every target - plus, on
  mobile, one activity base class and one build flag (INTEGRATION.md §5).
