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

### A pointer between two pixels (web)

- **Every pan, drag and long press on the web threw on a pointer whose
  position was not a whole number**, and did nothing. The coordinates were
  read through `MouseEvent.clientX`, which is typed an integer; a browser
  reports a finger, and a mouse on a zoomed page or a dense screen, in
  fractions of a pixel. They are read as numbers now. The tests made
  pointer events at whole pixels, which is why none of them saw it.

### Four more widgets

- `Table`, with `TableRow`, `TableCell`, `TableBorder` and the column
  widths. A column is a stated width or a share of the rest: nothing here
  measures a cell, so `IntrinsicColumnWidth` is a share too.
- `ReorderableListView` and `.builder`, on the platform's drag and drop.
  The whole row is what is held; the rows do not part to show where it
  will land.
- `InteractiveViewer` and `TransformationController`. A finger pans the
  child. Two fingers do not zoom it - no renderer reports a pinch - so the
  scale is what the controller says.
- `CustomScrollView` and the slivers apps use: `SliverList`,
  `SliverFixedExtentList`, `SliverGrid`, `SliverToBoxAdapter`,
  `SliverPadding`, `SliverSafeArea`, `SliverFillRemaining`,
  `SliverVisibility`, `SliverOpacity`, `SliverPersistentHeader`,
  `SliverAppBar` and `FlexibleSpaceBar`, with the list and builder
  delegates. A sliver is the boxes it would lay out: every child is built,
  and a pinned or floating bar scrolls away with the rest.
- All built in the widget layer; the protocol is as it was.

### A snackbar takes the look it is given

- `SnackBar.backgroundColor` and `shape`, the colour of its content's text
  and `SnackBarAction.textColor` are drawn, on all four renderers. They
  were accepted and sent nowhere. So are `width` (a narrower bar, in the
  middle), `margin`, `elevation` and `behavior`: a fixed bar runs edge to
  edge along the bottom, square, on the bottom bar when there is one.
- A floating bar stays above a floating button that belongs to a scaffold
  nested in another's body, which no renderer knows is there.

### Disabled buttons on the web

- Under MDL a disabled outlined or text button is its faded words, not a
  grey block; under Materialize a disabled tonal button keeps a fill.
  A text button is written in the app's primary under both.

### A swipe back on iOS

A page pushed on a `Navigator` can be swiped back from the leading edge on
iOS, the page following the finger with the one beneath it a third of the way
behind, as iOS's own navigation does; let go past half way or flung, it is
popped, and otherwise it comes back with its `State` as it was. The root
carries `RootProps.backSwipeEventId` while the page on top can be popped - not
a full-screen dialog, not one a `PopScope` holds - and the renderer raises it
with `{phase}`: `'start'`, after which each tree carries the page beneath as
`RootProps.beneath`, built from the same place so it keeps its `State`; then
`'commit'`, which pops with no page transition of its own, or `'cancel'`. A
drawer at the leading edge has that edge instead. Seen on an iOS simulator.
Android has the system's own back gesture, and the browser its own; neither
draws this. The Flutter host draws it too, on iOS. `BackSwipeStack` offers
it to a router of an app's own, and `router.dart`'s `GoRouter` stacks its
pages in one - a page pushed inside a `ShellRoute` included. Where the page
a swipe takes off is not the whole screen - inside a `ShellRoute`'s frame,
or a `BackSwipeStack` of an app's own inside a scaffold - its node says so
(`RootProps.backSwipePage`) and `beneath` is just the page under it: the
renderer moves that page alone, the page beneath drawn in its place, and the
frame's bars stay still, as in Flutter. A `Hero` with `transitionOnUserGestures` flies with
the swipe on iOS (`heroGestures`), as far as the page has moved, to its
counterpart on the page beneath - in the Flutter host as well. Seen on an
iOS simulator.

### `Focus`

A `Focus` widget: a box that is a stop for the Tab key, outlined while it has
focus (`:focus-visible`), that its `FocusNode`'s `requestFocus()` gives focus
and `unfocus()` takes it from, and that tells `onFocusChange` - and the node's
`hasFocus` - when focus comes into it and when it leaves altogether
(`focusEventId`, `focusable`, `focusSkip`, `focusVersion`). On the web, in the
Flutter host and on Android, seen on an Android emulator; iOS keeps its
controls' own keyboard focus, and a `Focus` there is its child.

### `IntrinsicColumnWidth` measures

A `Table`'s cells are measured where the widget layer can tell their width:
text by `TextPainter`, a `SizedBox`, `Container` or `Icon` that states one,
and padding, alignment, rows and columns of those. An `IntrinsicColumnWidth`
is as wide as its widest cell, and `MaxColumnWidth` and `MinColumnWidth`
compare what can be measured; a column none of whose cells can be measured
shares the width as before.

### `TextPainter` past Latin

Hebrew, Arabic, Devanagari, Bengali, Tamil and Thai are measured with the
widths of the Noto fonts Android draws them in, read by
`tool/generate_glyph_widths.dart` from the Android SDK's API 22 platform; a
CJK character or a Hangul syllable is an em, an emoji 1.245 em, and a mark,
a joiner or a variation selector that takes no room is nothing - each was
0.55 or 1.1 em. An Arabic letter is measured standing alone.

### More of a transition read

A route's `transitionsBuilder` is read through an `AnimatedBuilder` or a
`ListenableBuilder` - it is built at the animation's two ends - and a
`Transform`'s translation, scale and turn are read as the page's move; a
`KeyedSubtree` is passed through rather than ending the reading. A
`SizeTransition` reveals the page (`reveal`, `revealAxis`, `revealAlign`):
every renderer clips it to the share shown, growing from where its alignment
says - seen on an iOS simulator and an Android emulator, and tested in the
browser and the Flutter host.

### `AnimationController`

An `AnimationController` - `forward`, `reverse`, `animateTo`, `animateBack`,
`repeat` (with `reverse`, `period` and `count`), `fling`, `stop`, `reset`,
`value =`, status listeners and the `TickerFuture` each run returns - drives
`FadeTransition`, `ScaleTransition`, `RotationTransition`, `SlideTransition`,
`SizeTransition` and an `AnimatedBuilder`, through a `CurvedAnimation` or a
tween's `animate` too. The screen does not tick: a run is one tree built at
the value it ends at, carrying how long it takes and its curve, and the
renderer moves the screen there; in an `AnimatedBuilder` every box built - an
`Opacity`, a `Transform`, a `Container`'s colour or size - moves over the
run, and `value` read outside a build is where the run is by the clock. A run started while the screen is built, from
`initState`, is drawn at its start first, so an entrance is seen; a slide
whose child has not been measured yet stays out of sight until it has, and
then slides from where it starts. Each lap of `repeat` is a run of its own,
and without `reverse` the value goes straight back between laps. Seen on an
iOS simulator, an Android emulator and in Chrome: a pulse, a spin, a page
whose square slides in from `initState`, and a button that turns and fades a
box through an `AnimatedBuilder`. On the emulator, which was drawing frames
of up to three seconds at the time, the page's push held its main thread
past the end of the slide's run, so the square arrived in place; on the
simulator and in Chrome it slid in.

Two renderer fixes it needed: iOS turns a box by the angle when it changes
by half a turn or more, since UIKit moves between two matrices and a whole
turn is no change to one (a `RotationTransition` repeating stood still); and
the Flutter host builds a box that says `animateMs: 0` as one that moves, so
a later tree that gives it a time moves it from where it was rather than
building it afresh at its end.

### Staggered runs, and listeners that hear every frame

`Interval` and `TweenSequence` (with `TweenSequenceItem`) are there. A run
of a controller is cut where one made from it turns - an interval's start
and end, the hand-over between two tweens of a sequence - and each leg is a
tree of its own, moving to the next turn over its share of the run along
the interval's curve: a staggered entrance plays one part after another, and
a pulse goes through every keyframe. They are found where an interval or a
sequence is made straight from the controller (`CurvedAnimation`,
`drive(CurveTween(...))`, `TweenSequence(...).animate`); one curved by
another curve first is drawn at the run's ends, as before. An implicit
animation given an `Interval` runs along its curve over the whole duration.

A listener the app adds with `addListener` hears every frame of a run (16
ms), with `value` where the run is. One that rebuilds - `setState` from the
listener, then `value` read in `build` - makes the run drawn a frame at a
time from then on, as in Flutter: a tree each frame, where before it saw the
run's two ends. The framework's own listeners - the transitions', an
`AnimatedBuilder`'s - still hear a run start and end.

### A pinned `SliverAppBar` collapses

A pinned `SliverAppBar` first among the slivers and taller than its toolbar
- an `expandedHeight` - collapses as the view scrolls, down to its toolbar
and `bottom`, over the content rather than above it, so the content scrolls
under it with the finger. A `FlexibleSpaceBar` in it does what Flutter's
does on the way (`FlexibleSpaceBarSettings`): its background drifts up a
quarter of the way (`CollapseMode.parallax`, or with the bar for `pin`) and
fades out over the last toolbar's height, and its title shrinks from
`expandedTitleScale` against its start. It is built from the offset, so it
moves each frame (`scrollLink`). Seen on an iOS simulator, an Android
emulator and in Chrome.

### A bounce and an elastic are themselves

`Curves.bounceIn`, `bounceOut`, `bounceInOut`, `elasticIn`, `elasticOut`
and `elasticInOut` were the nearest of the five named paces; each now moves
as Flutter's does, overshoot and all, with `ElasticInCurve`,
`ElasticOutCurve` and `ElasticInOutCurve` taking their `period`. A curve no
cubic draws travels as its shape - `samples(...)`, its value at 64 even
steps - which the web draws as a CSS `linear()` easing, Android through an
interpolator, the Flutter host as a curve, and iOS by turning each straight
animation UIKit makes into keyframes along the samples (numbers, points,
sizes, rects and transforms). Seen on an iOS simulator, an Android emulator
and in Chrome: a box that bounces to its width and one that overshoots its
scale.

### Parameters that were taken and dropped

A `Center` with a `widthFactor` or `heightFactor` is as long as its child
along that axis, as an `Align` already was. A `DataColumn`'s `columnWidth`
sizes it: a `FixedColumnWidth` is that many pixels, a `FlexColumnWidth` a
share against the others' measured widths. A text field's `cursorColor`
colours its caret - CSS `caret-color`, the field's tint on iOS, the cursor
drawable on Android from Android 10, Flutter's own in the host - and a
`TextFormField` hands it on; seen on an iOS simulator and an Android
emulator. `TextPainter` ends the last line `maxLines`
leaves in its `ellipsis`, and `didExceedMaxLines` says whether it cut. The
rest of what the widget layer takes and does not carry is the platform's
own on purpose - a ripple's colours, a menu's elevation, a dialog's insets -
and says so where it is declared.

### iOS: a scaffold body that is its own height

A body that is plainly its own height in Flutter - a field, a text, a
button or a row, through any padding - is drawn at that height on iOS, where
it was stretched to the bottom of the screen: a field as a page's body was
as tall as the page. A body that fills, or might, is pinned between the bars
as before.

### A floating app bar, one that snaps, and one that stretches

A `SliverAppBar(floating: true)` first among the slivers floats over the
content: it goes up and away as the view scrolls down and comes back as soon
as it scrolls up, each frame - kept by the renderer from the scrolling
itself (`scrollFloat` on the bar's box, with the scroller named as for
`scrollLink`). With `snap`, a bar left part of the way when the scrolling
stops goes the rest, in or out. A pinned, collapsing bar with `stretch` is
taller than its full height by as far as the view is pulled past its top -
iOS's bounce; the tables a scroll offset is followed by start below 0 for
it. Seen on an iOS simulator, an Android emulator and in Chrome (the
stretch on iOS, where the scrolling bounces).

### Following a scroll offset costs one build again

The tables of the last report are kept and used again while the tree keeps
its shape and every followed box shows what its table says for the offset;
only a change of either builds the dozen and more samples again. A page of
two hundred list tiles that rebuilds from a listener went from 22 ms a
report to under half a millisecond.

### More of a page transition read

A `transitionsBuilder` that wraps the page in padding, an alignment, a size,
a clip, a decoration, semantics, a theme, a `Builder` or a `StatelessWidget`
of the app's own is read through them, as through an `AnimatedBuilder`; a
`Stack` or a stateful widget in the way still ends the reading.

### `Focus` on iOS

A `Focus` box takes focus on iOS too - it becomes the first responder,
which a hardware keyboard's keys go to - asked for it by `requestFocus` or
`autofocus`, outlined while it has it, and telling its node when focus
comes and goes. Seen on an iOS simulator.

### Kerning, and an app's own font

`TextPainter` counts Roboto's kerning between printable ASCII characters
(read from the font's `GPOS` table by `tool/generate_glyph_widths.dart`), so
"AV" and "To" measure as drawn. `TextPainter.registerFont` measures a
`fontFamily` of the app's own with its own widths and kerning, which
`dart run dart_not_native:font_widths --family <name> --regular <file>
[--bold <file>]` writes from the font files, with a `register<Family>()` to
call in `main`.

### A jump ends a fling

`ScrollController.jumpTo` and `animateTo` during a fling were carried on past
where they were sent by the fling still going - on iOS a few points, on
Android to the end of the list. A jump or a travel now ends a fling first, as
in Flutter, on both. Seen on an iOS simulator and an Android emulator.

### Checked on iOS

On an iOS simulator, with what Android gained on the emulator in mind: an
event names the build it was raised against and is answered by it - taps
raised against the build before Dart's latest, on a list whose ids moved
every build, opened the row tapped; scroll reports come as a scroller moves
and when it stops, a jump is obeyed again after a drag, and a list comes
back where it was from under a pushed page; pull-to-refresh draws the
spinner and waits for `onRefresh`; a floating snackbar clears the floating
button and the tab bar; a rail too long for the screen scrolls.

### Ligatures are measured

`TextPainter` counts Roboto's standard ligatures - `fi`, `fl`, `ffi`, `ffl`,
read from the font's `GSUB` `liga` feature - as the one glyph each is drawn
as, a few per cent of an em narrower than its letters ("office" at 100
points is 8.3 narrower), the longest at each place first as a shaper takes
them. Only letters of one style with no letter spacing are joined, as
Android joins them. `registerFont` takes an app font's own (`ligatures:`,
`boldLigatures:`), which `font_widths` now writes.

### The device lane

`integration_test/native_renderer_test.dart` lays a real Flutter widget
over a `FlutterSlot`'s hole and checks it is drawn where the renderer says
the hole is, on an iOS simulator and an Android emulator. Maestro flows for
the controls gallery's three tabs (`gallery_touch`, `gallery_choose`,
`gallery_feedback`) run on both platforms, where only the agent-device
flows on Android reached those node types.

### Long lists of rows of their own heights are windowed

A `ListView.builder` or `ListView.separated` of more than 60 rows that say no
height of their own (no `itemExtent`) is built a window at a time, as one
with a height has been: the renderer lays the rows it holds out at their own
heights, one under another, and says what they came to (`measureEventId` on
the `LazyList` node); a row not measured yet is as tall as those that have
been, on average, and the list's length and where an offset lands are
worked out from those. A `CustomScrollView` whose slivers include a builder
`SliverList` (or `SliverFixedExtentList`) is one such list, the other
slivers rows of it - unless one is pinned part-way down. A list of a
thousand rows of five heights scrolled down and back on an iOS simulator,
an Android emulator and in Chrome, each row at its height with no gap.
A row whose height changes after it is laid out - a picture that arrives -
is measured again, and when the heights above the screen are put right the
row first on screen stays where it is, on all four renderers. A jump to a
far offset still lands by the guesses.

### A widget in a line of text is live on iOS and Android

A `WidgetSpan` is its widget's own view, laid over the room the text keeps
for it each time the text lays out - from `NSLayoutManager` on iOS, from
the text's `Layout` on Android, where a text with widgets in it is a frame
holding the text and them. A network image in one loads, and a button or a
checkbox in one answers and changes; before, it was a picture of the widget
as it first laid out. Seen on an iOS simulator and an Android emulator.

### Intervals behind curves, and implicit animations with one

An `Interval` behind another curve - `CurvedAnimation(parent:
CurvedAnimation(...), curve: Interval(...))`, or a `CurveTween` - cuts a
controller's run where that curve gets to the interval's ends. An implicit
animation given an `Interval` - `AnimatedOpacity(curve: Interval(0.5, 1))` -
holds what it shows until the interval starts, and then moves over its share
of the duration along the interval's own curve.

### Each leg of a run goes at its own pace

A leg of a controller's run went along the one curve its animation names,
which is its pace only when the leg covers that whole curve. It now goes at
the pace Flutter draws it at: the run's own curve, then each
`CurvedAnimation` and `CurveTween` in front of the transition, over just the
part of them the leg covers - the rest of an `easeIn` after an `Interval`
behind it begins, the first half of a curve a run to the middle covers, an
interval cut by a `TweenSequence` beside it. Where that is not a named curve
it travels as its shape, `samples(...)`, as a bounce does. An `Interval`
chained after a curve (`CurveTween(curve: Interval(...)).chain(CurveTween(curve:
Curves.easeIn))`) cuts the run where that curve gets to the interval's ends;
before, the cut was dropped. Tested; not looked at on a device.

### A colour follows the scroll offset too

A box's colour built from `ScrollController.offset` goes from stop to stop
of its table each frame, mixed channel by channel, on every renderer -
seen on an iOS simulator and an Android emulator, tested in the browser
and the Flutter host.

### `GeneratedL10n`

`package:dart_not_native/gen_l10n.dart` looks gen-l10n's strings up for the
locale an app shows - matched by language, script and country, each looked
up once, a language the app does not ship given the fallback it names - so
the bridge an app kept beside the generated file is two declarations
(INTEGRATION.md §8.4). Mobile-only, as the generated code is.

### What is built from a scroll offset moves with the finger

A header that shrinks as the list scrolls, a title that fades in, a picture
that moves slower than the page - whatever a build makes from
`ScrollController.offset`, through `setState` from a listener or an
`AnimatedBuilder` on the controller, now moves each frame where it is a
box's opacity, size, translation, scale or turn. The widget layer builds the
same widgets at a dozen offsets, and at the middle of any two between which
they bend, compares the trees, and gives each box that changes a table
(`scrollLink`); the scroller is named for it (`scrollLinkSource`), and each
renderer puts the boxes where the table says from its own scroll callback -
a `ScrollMemory` listener on Android, the scroll view's layout on iOS, the
`scroll` event in the browser, a `ScrollNotification` in the Flutter host -
without a message to Dart. The reports and the rebuilds go on as before
underneath. What changes in other ways - words, colours, a tree of another
shape - follows the reports. Seen on an iOS simulator, an Android emulator
and in Chrome; tested in the Flutter host.

Two fixes it needed: `ScrollController.hasClients` is true for a widget
built above its scroller, which asked before the scroller had been built
that time and was told no; and on Android a scroller that moves on the
screen while the finger is on it - under a header that shrinks - holds the
drag where the finger is, rather than reading the move as the finger's and
scrolling back once a frame.

### A `Container` with a width fills a width it cannot change

A `Container`, `SizedBox` or `ConstrainedBox` given a width, or a cap on it,
laid out where the width cannot change - a vertical list's row, a stretched
column, a row's `Expanded`, through the widgets that hand it on - is as wide
as that room, as in Flutter, whose constraints from above win. An empty
`SizedBox` stays a spacer. It was its own width before, and on iOS under an
`AnimatedOpacity` as wide as the room.

### A `Stepper`'s step opens and closes

A step's content opens below its heading and the one before it closes, over
200 ms along `fastOutSlowIn`, fading as it goes - Flutter's `AnimatedCrossFade`
between nothing and the content, as Flutter's stepper has.

### A `DataTable`'s columns follow their cells

A column's share of the table's width is its widest cell, measured as an
`IntrinsicColumnWidth` is - text, stated sizes, padding - with room for a
sorting heading's arrow and a cell's edit icon. A column that cannot be
measured gets the average of those that can. The table is still as wide as
what it is in, where Flutter's is exactly as wide as its columns; a short
column stays short and a long one gets the room. Seen on an iOS simulator,
an Android emulator and in Chrome.

### An image given a width fills a width it cannot change

An `Image` with a width and no height, laid out where Flutter gives it a
width it cannot change - a vertical list's row, a stretched column, a
`Container` or `SizedBox` with a width or one given its own, a row's
`Expanded`, with any padding between - is as wide as that room and as tall
as the picture at that width (`fillWidth` on the node), as in Flutter.
Anywhere else - centred, aligned, in a row - its own width is kept. The
widget layer says which by following what each parent hands its child
(`_Owner._tightWidth`); a widget it does not know leaves the image as it
was. A `Scaffold`'s body is such a room, and so is a vertical
`SingleChildScrollView`; a `Card`, a `Hero`, a `Dismissible` and the widgets
that leave their child's room alone - `GestureDetector`, `InkWell`,
`Semantics`, `Opacity`, a clip, `Tooltip`, `SafeArea`, `Theme` and any
inherited widget, the implicit animations - hand it on; a `ListTile`'s parts
are as wide as they ask, as in Flutter. On the web a card holding such an
image drops the kits' reading width and is as wide as the room. It was drawn
three ways before: at its width at the start on iOS and the web, and the
box's width with the picture shrunk in the middle on Android. Seen on an
iOS simulator, an Android emulator and in Chrome.

### No icon flag for a release build

`--no-tree-shake-icons` is no longer needed. The Flutter renderer looks a
codepoint up among a constant `IconData` for every glyph of the Material
Icons font (`lib/platforms/material_glyphs.dart`, generated by
`tool/generate_material_icons.dart`), so the release build's tree shaker
sees them all, keeps them all - for the native renderers, which draw from
the same file, too - and has no `IconData` made at run time to fail on. A
codepoint the font does not have is a dot. An icon in a font of the app's
own is drawn as its character in that font. A release APK of the controls
gallery was built without the flag and drawn natively on an Android
emulator, every icon in place.

### Fixes this round

- **A gallery flow missed its snackbar.** The controls gallery's "Draft
  saved" snackbar now stays ten seconds, long enough for a flow driving the
  emulator to reach Undo; the agent-device flow failed two full runs in a
  row on the default four.

- **A text field's icons on iOS were the wrong way round right to left.** A
  field turned right to left shows its `leftView` on the right by itself,
  and the renderer swapped the prefix and the suffix as well, putting them
  back where they started - in an Arabic screen and in a `Directionality`
  island alike. What iOS works out from the direction while building a
  view - a field's affixes, the back chevron, where text starts - now
  follows an island's direction too.
- **Android page moves started before the page was drawn.** The clock of a
  push's slide began before the new tree was rendered and laid out, which on
  a debug build could take longer than the whole move: the page appeared in
  place. A page move and a hero's flight now start on the frame after the
  page is first drawn, as a route's own transition already waited for its
  layout.

### The page beneath moves too

A route's transition is now also asked what its `secondaryAnimation` does to
its page - what being covered does to it - and the page beneath moves that
way as another is pushed over it, and back as that one is popped: the
Cupertino-style parallax, written with a `PageRouteBuilder` or a route's own
`buildTransitions`. Both pages move together on all four renderers, the one
in its own right on top (`page` and `picture` on `RootProps.pageTransition`,
now both at once). Over a page that leaves its own move to the renderer, that
move is said in the same terms so the two go together. Seen on an iOS
simulator, an Android emulator and in Chrome.

### `GoRoute.pageBuilder` and `ShellRoute.pageBuilder`

`GoRoute` takes go_router's `pageBuilder`, returning a
`CustomTransitionPage` (its `transitionsBuilder`, `transitionDuration` and
`reverseTransitionDuration`), a `NoTransitionPage` or a `MaterialPage` -
`Page`, `MaterialPage` and `CupertinoPage` are in `widgets.dart`. A custom
page moves by its transition as a `PageRouteBuilder` does, the page beneath
by its own, and a `NoTransitionPage` is simply there.
`announcePageTransition` takes the transitions for a router of an app's own.
A `ShellRoute` takes one too (`ShellRoutePageBuilder`, its `builder` now
optional): its page's transition moves the whole frame when a navigation
enters the shell from outside or leaves it, while a move between two of the
shell's own routes is the inner page's, as in go_router.

### A hero's placeholder, and a shuttle laid out as it flies

What `placeholderBuilder` builds stands in the hero's room while it flies
(`heroPlaceholder`, now sent with every tree); it was accepted and not
called. That is the arriving hero's room and, in the picture of the page it
left, the room of the hero it flies from, each with its own placeholder, as
in Flutter. The `heroSize` it is handed is `Size.zero` - the renderer lays it
out to the room. A hero's room is its child's: a box that is only a hero
could be stretched wider than its child on iOS, Android and the web, and the
placeholder and the flight's two ends were the stretched box's. A
`flightShuttleBuilder`'s shuttle is laid out at each size the flight passes
through, so its words keep their size, where it used to be drawn once and
stretched; a hero with no shuttle is still a picture of itself, stretched.
Seen on an iOS simulator, an Android emulator, in Chrome and in the Flutter
host's tests.

### Widgets in a line of text, and words that can be held

- A `WidgetSpan` is its widget in the line, its middle on the middle of the
  text: the widget itself in the browser and the Flutter host, a picture of
  it on iOS and Android, where a tap on the picture is a tap on the first
  thing in it that takes one. It used to be left out.
- A span with a `LongPressGestureRecognizer` sends its event when held
  (`longPressEventId`), on all four renderers.
- `SelectableText.rich` is here, and its links can be tapped and held - on
  iOS too, where a selectable text's links did nothing.

Seen on an iOS simulator, an Android emulator and in Chrome.

### A `Directionality` deep in a screen turns the platform's controls

A `Directionality` that reads the other way from what is around it tells the
renderer so on its child's node (`layoutDirection`), and the platform's own
controls below it run that way - a row of them from the right, a switch
mirrored, a field's text from the other side - where only the widget layer's
own values turned before. A `Row` inside one is no longer sent reversed: the
renderer lays it out. Seen on an iOS simulator, an Android emulator (which
lays nothing out right to left in an app that has not declared it can, so
the renderer declares it) and in Chrome.

### A drawer slides in from the side

`Scaffold.drawer` and `endDrawer` are panels from the start and end edge, the
height of the screen and as wide as the `Drawer` says (304 unless it says),
over a scrim, closed by a tap on it, Back or a swipe towards the edge (`side`
and `width` on a `BottomSheet` node). They were sheets from the bottom. A
drawer's content is laid out to the panel's height, so a `ListView` in it
scrolls there. A swipe in from the edge opens one too: a drag that starts
within 20 pixels of the edge and moves in from it raises `drawerEdgeEventId`
(`endDrawerEdgeEventId`) on the `Scaffold` node, unless
`drawerEnableOpenDragGesture` says not, and the panel then follows the finger,
let go open past half way or flung inwards and shut otherwise, as Flutter's.
The drag is watched at the renderer's root rather than on the scaffold, which
is drawn again as the drawer arrives and took a gesture of its own with it on
iOS, Android, the web and the Flutter host alike. On Android with gesture
navigation the 20 pixels start where the system's back strip ends, as in
Flutter; on iOS it is a pan that may only begin by an edge, so a tap there
still reaches what is beneath. Seen on an iOS simulator, an Android emulator
and in Chrome.

### An image given only a width

An `Image` with a `width` and no `height` is as tall as that width makes the
picture in its own proportions, as Flutter's is. Android showed the bitmap at
its own height in pixels, smaller than it should have been; iOS took the
picture's height in points, and reserved a tall space of no particular
height before it arrived, where it now reserves none. Seen on an iOS
simulator and an Android emulator.

### `TextPainter` measures with Roboto's widths

A character is as wide as it is in Roboto - regular, or bold from weight 600
up - plus the style's `letterSpacing`, for Latin, Greek, Cyrillic and their
punctuation (`lib/src/glyph_widths.dart`, generated from the Flutter SDK's
font files by `tool/generate_glyph_widths.dart`); 0.55 of the font size was
the estimate for every one. The text goes to the renderer broken into the
lines it was measured as, and is not broken again: SF on iOS, a few per cent
wider, stands out past the measured box rather than wrapping. A canvas text's
`letterSpacing` is drawn now. Seen on an iOS simulator, an Android emulator
and in Chrome.

### Times in a locale's own digits, and the device's clock

`TimeOfDay.format` writes the digits a locale writes numbers in, as Flutter
does from `intl` - `۱۵:۰۵` in Persian, Bengali's, Egyptian Arabic's
(`timeDigitZeros`, generated with the time formats). Every renderer reports
the device's 24-hour setting with its window (`use24Hour`), which is
`MediaQueryData.alwaysUse24HourFormat`; a browser has no such setting and
reports its language's clock.

### A text field's states, and the words around it

`InputDecoration`'s `focusedBorder`, `errorBorder` and `disabledBorder` are
drawn in their own colour and width on all four renderers - the kind is the
resting border's - and `hintStyle`, `labelStyle` and `helperStyle` give the
hint, the label and the helper their colour, size and weight. A focused
field in error has the error's outline. On Android the hint takes its colour
only. Seen on an iOS simulator, an Android emulator and in Chrome, on fields
with their labels above them; an Android field with a floating label -
Material's box, which takes the colours and widths through its own state
lists - was not looked at.

### `AnimatedSize` follows a child that changes by itself

A box that moves to its size now moves when its child changes size between
renders - a picture arriving - in the browser and on iOS, as it already did
on Android and in the Flutter host. Seen on all three. In the browser the
child is held at its size, both ways, while the box moves over it.

### Smaller things, this round

- Rich text in the browser lost what was inside the boxes of a widget in its
  line; a long press and a drawer's swipe there read the pointer through
  the integer-typed `clientX` - the fault "A pointer between two pixels"
  describes, made again in new code - and did nothing for a real finger or
  mouse. Both found looking, both fixed, and the tests now press between
  pixels.
- A page moving over another in the browser keeps a background of its own;
  it was painted over with the body's colour for the move.
- An Android drawer opened while the app rendered again slid in twice.

### A drag carries its feedback, and says where it ended

`Draggable.feedback` was accepted and not drawn: what followed the finger was
a copy of the child. It is now what the app said (`dragFeedback`), held by
the point the child was taken by, as Flutter's default anchor holds it - an
element under the pointer in the browser, the drag shadow on Android, the
lifted preview on iOS, Flutter's own in the host. `onDragEnd`,
`onDraggableCanceled` and a target's `DragTargetDetails` were given zeros;
they now have where the picture's top left was and how fast the pointer was
going. Seen on an Android emulator and in Chrome. On iOS it builds, but the
simulator cannot be made to hold and drag from here.

### A tap is heard as it happens

`onTapDown`, `onTapUp` and `onTap` fired together, after the tap. `onTapDown`
is now called as the finger lands (`tapDownEventId`), and `onTapCancel` -
never called before - when the press turns out not to be a tap: it moved past
Flutter's slop, a scroller or a long press took it, or it was let go off the
box. Seen on an iOS simulator, an Android emulator and in Chrome.

### `Dismissible.onUpdate`

Called with Flutter's `DismissUpdateDetails` - the direction, how far as a
part of the row, whether the threshold is passed and whether it was at the
last update - as the finger moves the row, and when it is let go, towards
where it is going. Seen on an Android emulator.

### A route's own transition

`PageRouteBuilder.transitionsBuilder` was accepted and never called: every
page moved the renderer's way. A route's transition - a `transitionsBuilder`,
or the `buildTransitions` of a route of the app's own, which `buildPage` (now
public) lets it write - is now asked what it does to the page at the start of
its animation: how faded, moved, scaled and turned the transition widgets it
returns leave it. The new page moves from there to its place over the page
beneath, and on the way back the picture of it moves back there over the page
it uncovers (`page` and `picture` on `RootProps.pageTransition`), along the
curve the transition names. A builder that returns the page as it is - and a
`PageRouteBuilder` without one, as in Flutter - does not move it.
`Animation.drive` and `ReverseAnimation` are here. Seen on an iOS simulator,
an Android emulator, in Chrome and in the Flutter host: a fade, a slide up,
and a scale with a whole turn.

### Heroes arc, and fly their shuttle

In a `MaterialApp` a hero flies along Flutter's Material arc
(`MaterialRectArcTween`), as Flutter's does, and in a straight line elsewhere;
`createRectTween` says which by the tween it makes. `RectTween` and
`MaterialRectArcTween` are new, with Flutter's numbers. `flightShuttleBuilder`
is called on the tree that turns the page, and what it builds flies in the
hero's place - its own, or else the one the hero it flies from has. Seen on
an iOS simulator, an Android emulator, in Chrome and in the Flutter host.
Short of Flutter: the animation the shuttle is handed stands at its end
(and, until the entry above, it was drawn once and stretched).

### Pinned headers stack

Two pinned headers further down a `CustomScrollView` stack, each under those
before it, as Flutter's do; the later one used to cover the earlier. Seen on
an iOS simulator, an Android emulator and in Chrome - the Flutter host's
`PinnedHeaderSliver` always stacked.

### A whole `Matrix4`

A matrix that skews, tilts in perspective or turns out of the screen's plane
- or turns or scales about a point other than the middle - now travels whole
(`transform.matrix`, with the point it works about in `origin`): CSS
`matrix3d`, Flutter's own `Transform`, the canvas's matrix on Android, a
`CATransform3D` on iOS. Seen on all four, the same as Flutter's. On Android
it moves the picture, not where touches land.

This changes what existing code draws: a `Transform` with a `Matrix4` works
about its `alignment` and `origin` - the top left, where they say nothing, as
in Flutter - so `Transform(transform: Matrix4.rotationZ(a))` turns about its
corner where it used to turn about its middle. `Container.transformAlignment`
is carried.

### The browser says how far an image has come

With a `loadingBuilder`, the web renderer fetches the picture itself a piece
at a time, says how many bytes have come and how many there are, and shows
what came. A server that does not let the page read the picture (no CORS)
leaves it to the `<img>`, which says nothing on the way. Seen in Chrome.

### Smaller things, this time

- A `Container` around a `ListView`, `GridView`, `CustomScrollView`,
  `PageView` or `TabBarView` fills the room it is offered, as the scroll view
  does in Flutter. In the browser such a list grew to its full length and
  did not scroll.
- In the browser a list on a page that slid back into place - a tab returned
  to - started from the top: an element moved among its siblings is now put
  back scrolled where it was.
- A page moving over another in the browser is given the page's colour, so
  the one beneath does not show through where the page paints nothing.

### Curves are Flutter's

Only five paces reached a renderer, so `Curves.fastOutSlowIn` was an
ease-in-out and `Curves.easeOutBack` lost its overshoot. Every curve that is
a cubic Bézier in Flutter now travels as that cubic (`cubic(a,b,c,d)`), with
Flutter's numbers, and so does any `Cubic` an app makes: a CSS
`cubic-bezier`, an Android `PathInterpolator`, UIKit's cubic timing, Flutter's
own. The bounces, springs and three-point curves are still the nearest of the
five. `Cubic.flipped` is the cubic turned end for end.

### `animateTo` takes the time it is given

`ScrollController.animateTo` travelled by each platform's own smooth scroll,
at its own pace. The renderer is now told the duration and the curve
(`scrollMs`, `scrollCurve`) and moves the scroller a frame at a time - a
windowed list hears every step, as it does under a finger, and a finger put
down on the way takes over. Seen on an iOS simulator, an Android emulator and
in Chrome: two seconds, linear, is two seconds.

### Transitions beyond the fade

An `AnimatedSwitcher`'s `transitionBuilder` was called with a finished
animation, so whatever it returned faded. It is now built with the animation
at its start and then at its end, and `FadeTransition`, `ScaleTransition`,
`SlideTransition`, `RotationTransition` and `SizeTransition` move between the
two. The last four were not here, and nor were `Tween`, `ColorTween`,
`IntTween`, `CurveTween`, `CurvedAnimation`, `Animatable.animate` and
`chain` - a builder written for Flutter now compiles and moves. Seen on an
iOS simulator, an Android emulator and in Chrome.

### `TabBarView` slides, and follows the finger

A `TabBarView` is now a `PageView` kept in step with its `TabController`: the
page follows a finger and the tab beside it is chosen when it is let go, and
a tab chosen on the bar slides into view over the controller's
`animationDuration` (`animateTo` takes a duration and curve of its own).
Seen on an iOS simulator, an Android emulator and in Chrome.

### A dismissed row closes behind it

`Dismissible.resizeDuration` has Flutter's 300 ms: once the row has slid
away, the room it took closes over that time, `onResize` is called on the
way, and then `onDismissed`, as in Flutter - where it used to be called as
soon as the row had gone and the gap stayed until the app took the row out.
A null `resizeDuration` keeps the old way. By its tests only.

### Two fingers turning

`ScaleUpdateDetails.rotation` was always zero. While two fingers are down a
pan now also carries `rotation`, how far the line between them has turned,
on all four renderers. In Chrome and the Flutter host's tests; not on a
phone, which cannot be given two fingers from here.

### A header pinned further down stays

A pinned `SliverPersistentHeader` or `SliverAppBar` that was not first among
the slivers scrolled away. It is now a `sticky` box: once the list has
scrolled past it, it stays at the top of the view, over the rows going under
it, until the list comes back down - CSS `position: sticky` in the browser, a
`PinnedHeaderSliver` in the Flutter host, the box moved down as the scroller
moves on iOS and Android. Seen on an iOS simulator, an Android emulator and
in Chrome. Two such headers stack under each other, as Flutter's do (see
"Pinned headers stack").

### Layers and blends on a canvas

A `Paint`'s `blendMode` is carried, and `saveLayer` is a layer - what is drawn
until the matching `restore` is laid over the canvas at the paint's opacity,
in its blend, so shapes that overlap inside it are not darker where they do.
`drawColor` takes its blend too. Seen on an iOS simulator, an Android emulator
and in Chrome; by pixel in Chrome and the Flutter host.

### How far an image has come

`loadingBuilder` was handed nothing loaded and no total, always. Android, iOS
and the Flutter host now say how many bytes have come - and how many there
are, when the server said - a few times a second, and the builder is called
with each - and the browser too, since (see "The browser says how far an
image has come"). Seen on an iOS simulator and an Android emulator with a
server sending a picture in twenty pieces.

### `Matrix4` is a matrix

`Matrix4` held one turn, one scale and a shift, and composed them as if order
did not matter. It is now Flutter's sixteen numbers, column by column, with
`multiply`, `entry`, `setEntry`, `storage`, `getTranslation` and the rest,
and calls compose in the order made - a translate after a scale is scaled, as
in Flutter. What a box is given is read out of it: the shift, the turn and a
scale along each axis, which the renderers now carry (`scaleY`), so
`Transform.scale(scaleX: 2, scaleY: 0.5)` stretches where it used to average.
A skew and a perspective travel whole (see "A whole `Matrix4`").

### Smaller things

- `AnimatedSize.onEnd` is called when the renderer says a move to the
  child's new size has got there (`sizeEndEventId`).
- On iOS a box scaled to nothing - a switch's child going - shrank at once:
  UIKit cannot animate to a scale of zero, so it goes to very nearly zero.

### `onEnd` is the renderer's word

An implicit animation's `onEnd` was a timer the app set for the duration it
asked for, which ran from the build rather than from the moment the renderer
started moving. A node on its way now carries `endEventId` and `endAsk`, a
number for the change, and the renderer answers `{ask}` once the move has
finished: iOS from `UIView.animate`'s completion, Android from its animator,
the browser and the Flutter host the duration after they applied the tree -
and at once, wherever nothing moved. An answer about a move since overtaken
ends nothing. A renderer that never answers is waited for a quarter of a
second past the duration. Seen on an iOS simulator, an Android emulator and
in Chrome: an 800 ms `AnimatedContainer` ended at 842, 837 and 803 ms. This
is the event an explicit animation design would start from.

### Sizes move

`AnimatedSize` showed its child's new size at once, and an
`AnimatedCrossFade` jumped to the new child's size when the fade ended. A box
with `animateSize` now moves from the size it was to the size its child came
to over its `animateMs` - the renderer does the moving, since only it knows
how big the child came out - and both widgets are drawn with one. The child
is laid out once, at its new size, and clipped while the box passes over it:
text does not wrap again at every width on the way. In a cross-fade the child
going is laid over the top, as wide as the stack, so the space follows the
child coming. Android moves the box in its measure, iOS holds the old size
and lets it go inside an animation, the browser animates between the two
sizes it measures before and after a patch, and the Flutter host uses its
own `AnimatedSize`. Seen on an iOS simulator, an Android emulator and in
Chrome. A child that changes size between renders - a picture arriving - is
not moved to, and `AnimatedSize.onEnd` is not called.

### `PageView` slides, and follows the finger

A `PageView` changed page at once, whether swiped or told to by
`animateToPage`. The page now slides: `animateToPage`, `nextPage` and
`previousPage` over the duration and curve asked for, completing when the
page is there; a swipe from wherever the finger let go, over what is left of
the way. Under the finger, the page and the one beside it move with it, and
let go short of the next, they go back. At either end the page gives a
little and no more. `jumpToPage` is still at once. Seen on an iOS simulator,
an Android emulator and in Chrome. As with a `Dismissible`, each movement of
the finger is a build, so on a long screen the page is a little behind it.

### Two fingers zoom an `InteractiveViewer`

No renderer reported a pinch, so an `InteractiveViewer` could only be zoomed
by its controller. A box with `panScale` now hears a second finger: while two
are down, its pan updates carry `scale` - the spread over what it was - with
the point between them. `GestureDetector` has `onScaleStart`, `onScaleUpdate`
and `onScaleEnd` on it, and the viewer scales about the point between the
fingers, held between `minScale` and `maxScale`. Pinched in Chrome and in the
Flutter host's tests. **Not tried on a phone:** neither the simulator nor the
emulator can be given two fingers from here, so on iOS and Android it rests
on the code. `Matrix4.getMaxScaleOnAxis()` is there, to read the zoom back.

### Rows part while one is moved

A `ReorderableListView` showed nothing of where a row would land. While a
row is over another, a gap as tall as the row opens on the side it will go,
and closes when it moves on - built in the widget layer from what the rows
measure. With it, a `DragTarget`'s builder is handed what is being dragged
over it (`candidateData`), as in Flutter, where it was handed `[null]`; to
know, every `Draggable` now says when it is picked up and let go. Seen on an
Android emulator and in Chrome; on iOS a row cannot be held and dragged from
here.

### What a canvas left out

- `dart:ui`'s own gradients: `Gradient.linear`, `Gradient.radial` and
  `Gradient.sweep`, so a painter that wrote `ui.Gradient.linear(...)` migrates
  by dropping the `ui.`.
- Tile modes other than clamp - `repeated`, `mirror` and `decal` - for a
  linear, radial or sweep gradient on a canvas, sent as the copies of it that
  cover the canvas.
- Blur styles other than normal: `solid`, `outer` and `inner`. A stroke is
  blurred `normal` or `solid`; asked for either of the others, `normal`.
- `Path.fillType = PathFillType.evenOdd`, for a fill and for a clip.
- A blur over a gradient on iOS, which was drawn sharp.

Seen on an iOS simulator, an Android emulator and in Chrome; even-odd also by
pixel in Chrome and the Flutter host. Blend modes on a paint and `saveLayer`
are still not carried.

### An image's tint blends as asked

`Image.colorBlendMode` is carried (`blend`), every mode of Flutter's, which
`BlendMode` now lists in full. Seen on an iOS simulator, an Android emulator
and in Chrome. On the web the picture's transparent parts stay clear whatever
the mode, where Flutter fills them for some (multiply, screen and the like).

### Smaller things

- A floating snackbar over a nested scaffold's bottom bar knows how tall the
  bar is: it is measured, where it was taken to be 80 or 56.
- What stands in for an image - an `errorBuilder`'s widget - fills the
  image's box on Android and the web as it did on iOS, with an icon or a
  spinner in the middle of it.

### Found by looking

- On the web a canvas with a stated size, given more room than that - a
  scaffold's body gives its one child all of it - had its picture stretched
  to fit. It keeps the size it was painted at.
- On the web a `PageView` in a `SizedBox` that only says how tall was as
  narrow as its page's content, and so was a `ListView` under an `Expanded`
  in a column that centres - on iOS too. Both are as wide as the column, as in
  Flutter.
- On Android a drag over a row that was itself a `Draggable` someone listened
  to was never heard by the `DragTarget` round it: the platform tells only
  the innermost view listening.
- A `SliverAppBar`'s title sat at the left read from the right too; it is at
  the start of the line.
- In the Flutter host an image's stand-in was as big as its content rather
  than the image's box.

Also seen for the first time, and working: a named page's state kept on an
iOS simulator, a `Hero` flying right to left on one, a pinned `SliverAppBar`
on an iOS simulator, an Android emulator and in Chrome, and an image's wait
and failure in the Flutter host on a simulator.

### A `Hero` flies

A `Hero` was its child and nothing else. Now, when a page is pushed or popped
and both pages have a hero with the same tag, the arriving page's hero flies
from where the old one stood to its own place - a picture of it, stretched
from the one size to the other over the length of the page transition - and
neither of the two is seen meanwhile. On all four renderers; seen on an iOS
simulator, an Android emulator, in Chrome and in the Flutter host. It is a box
with a `hero` prop, and the flight is the renderer's: always the arriving
hero, along a straight line. `createRectTween`, `flightShuttleBuilder` and
`placeholderBuilder` are accepted and not called.

### An image's wait and its failure are seen (breaking)

An image with a `loadingBuilder`, an `errorBuilder` or a `frameBuilder` is now
told by the renderer how its load ended (`eventId` on the `Image` node:
`{state: 'loaded'}` or `{state: 'failed'}`), and the builders follow it as
they do in Flutter:

- `loadingBuilder` is called with an `ImageChunkEvent` while a remote image
  is on its way, and what it returns - a spinner - is drawn in the image's
  place until the picture arrives; then it is called with null. The event
  never says how far: the bytes are counted by the renderer and not reported.
  Its third parameter is `ImageChunkEvent?`, which was `Object?`.
- `errorBuilder` is called when the load has failed, and not before. It used
  to be called up front and its widget shown while loading as well, so a
  screen of pictures flashed its error widgets first; that is what changes
  for existing code.
- `frameBuilder` is called with no frame and then with frame 0, so a fade-in
  written the usual way fades in.

Seen on an iOS simulator, an Android emulator and in Chrome with a slow
server and a missing picture; the Flutter host by its tests. While loading,
the `child` a `loadingBuilder` is handed is an empty box - the image has to
be in the tree to be fetched - so its widget stands in the image's place, not
around it.

### A named route keeps the page beneath it (breaking)

`MaterialApp(routes:)` showed one named page at a time: pushing `/detail`
took the list page away, and going back built it again from nothing - scroll
position, a typed field, a counter, all gone. The pages on the way to the
one on screen are now kept, as pushed pages are, and come back as they were
left. With it:

- **`pushNamed` completes when the page is popped**, with what it was popped
  with, as in Flutter - it used to complete at once with null, so code after
  `await Navigator.pushNamed(...)` ran while the page was still open. The
  same for `pushReplacementNamed` and `pushNamedAndRemoveUntil`. The
  platform's back gesture and the browser's button answer null.
- **A named page has its `arguments` in its first build.** They arrived after
  it, so `ModalRoute.of(context)!.settings.arguments` read null the first
  time.
- The same route twice on the way is two pages, each with its own state.

### Hardware keys on iOS, and once each on Android

The iOS renderer never sent `dnn:key`: a `KeyboardListener` heard nothing
there. It does now - the container takes the keys when no field has them -
and Android, which reported every key twice (the engine sends round again a
key the Flutter view did not want), reports it once. Pressed on a simulator
and an emulator.

### An old picture is better than none

Android and iOS keep remote images on disk for as long as the server's cache
headers allow, and showed nothing for one that had outlived them when the
server could not be reached. They now show the copy they have. Checked on
both with a server that was stopped between two launches of the app.

### A pinned bar stays

A `SliverAppBar(pinned: true)` scrolled away with everything else. First
among the slivers of a `CustomScrollView`, its toolbar and `bottom` are now
held above the scroll view, and what is left of a tall bar - the
`flexibleSpace`, less a toolbar's height - scrolls away beneath them. A
`SliverPersistentHeader(pinned: true)` is held the same way when it is first,
or follows only other pinned ones. Built in the widget layer, so the same on
every renderer; nothing collapses, a title does not move up into the toolbar,
and a header pinned further down the list still scrolls away.

### Smaller things

- A floating snackbar stays above the bottom bar of a scaffold nested in
  another's body, as it already did above its floating button. The bar's
  height is not measured: a `NavigationBar` is as tall as it says or 80, and
  anything else is taken to be 56.
- `ScrollController.animateTo` travels in a windowed list on iOS, which
  jumped. Seen on a simulator.

### Found by looking

Looking at the last round's work on screens turned these up:

- A named route pushed again after going back faded in, where it should
  slide: the move was told from how long the way was, and that push leaves
  it as long as it was.
- In the Flutter host a pushed page arrived over black, where the leaving
  page thinned out with nothing behind it.
- On Android a child with a stated size - an image - lost it inside an
  `AnimatedOpacity`, and took no room until its picture arrived.

Also seen for the first time, and working: right-to-left page transitions on
iOS and in Chrome, a `GoRouter` transition on both devices, the date and time
pickers, `FocusNode.requestFocus()`, a `FlutterSlot` inside a scroller, and
the Flutter host's sweep gradient, blur, clip, tint, floating snackbar and
travelling scroll.

### Pages arrive and leave

- **A page transition.** A renderer moves from the old page to the new
  one: the old page, kept as a picture, fades away; a pushed page slides in
  from the end of the screen and a popped one slides off towards it. For
  pages pushed on a `Navigator` and for named routes, on all four
  renderers. A page was simply replaced before.
- It is the renderer's transition and the only one:
  `PageRouteBuilder.transitionsBuilder` is still never called. Its
  `transitionDuration` and `reverseTransitionDuration` are how long the
  move takes, and zero is a page that is simply there.
- Protocol: `RootProps.pageTransition`, `{'kind': 'push' | 'pop' | 'fade',
  'ms': 300}`, on the first tree that shows the new page
  (`UIBuilder.withPageTransition`). A renderer that ignores it shows the
  page at once.

- The in-repo `GoRouter`'s pages transition too. Any `RouterConfig` can
  say so for its own: `announcePageTransition(context, 'push')` from the
  build that first shows the new page.
- A transition said on a tree that was batched away before it was drawn is
  still shown, in the browser and the Flutter host.

### Padding and alignment move

- `AnimatedPadding`, `AnimatedAlign` and an `AnimatedContainer`'s padding,
  margin and alignment travel over their duration. They already did on iOS
  and, for the insets, in the browser; they now do on Android, in the
  Flutter host and, for an alignment, in the browser.

### Scroll notifications

- `Notification`, `NotificationListener`, `ScrollNotification` and its
  start, update and end, with `ScrollMetrics`. A scroller tells the
  listeners above it as often as it reports its offset - at rest and about
  every 100 ms on the way - and the end is a quarter of a second without a
  report. `Notification.dispatch(context)` sends one of an app's own.

### More of a canvas

- `Canvas.clipPath` clips, on all four renderers (a `clipPath` command). It
  was accepted and did nothing.
- `Path.addRRect` is the rounded rectangle, each corner its own radius, and
  `Path.arcToPoint` (and `relativeArcToPoint`) the arc. They were the plain
  rectangle and a straight line.

- A `SweepGradient` on a canvas, and `MaskFilter.blur` on a paint, on all
  four renderers (a paint's `gradient` of type `sweep`, and its `blur`).
  iOS draws a blur over a gradient sharp.

### `animateTo` travels

- `ScrollController.animateTo` scrolls there smoothly - the renderer's own
  scroll, at the platform's pace - and its future takes the duration asked
  for. It used to jump. A windowed list on iOS still does.

### A box around an `Align` is as wide as it is offered

- A `Container` with no width of its own around an `Align` (or an
  `AnimatedAlign`) fills the width it is given, as Flutter's does. In the
  browser it hugged the child, so the alignment had no room to show.

### A tinted image

- `Image.color` draws the picture as its own shape in that colour, on all
  four renderers (`UIBuilder.image(color:)`). Flutter's default blend,
  `srcIn`, is the one carried.

### `AnimatedSwitcher` and `AnimatedCrossFade` fade

- The old child stays under the new one, deaf to touches, and fades out as
  the new one fades in; it used to be swapped at once. A child is new when
  its type or key changes, as in Flutter. The fade is the only transition -
  a `transitionBuilder` is handed a finished animation - and a cross-fade
  does not animate its size.
- **State under a keyed widget travels with the key.** A widget with a
  `Key` kept its own `State` when it moved on its page, but the widgets it
  built were still found by where they were drawn, and started again. They
  are counted from the key now, which is what `KeyedSubtree` always said.

### `Stepper` and `DataTable`

- `Stepper`, `Step`, `StepState`, `StepperType` and `ControlsDetails`:
  vertical or horizontal, with `onStepTapped`, `onStepContinue`,
  `onStepCancel`, `controlsBuilder` and `stepIconBuilder`.
- `DataTable`, `DataColumn`, `DataRow` and `DataCell`: sorting headings
  with their arrow, numeric columns, selectable rows with a select-all
  box, tappable cells, `placeholder` and `showEditIcon`.
- Both were missing, so an app with either did not compile. They are
  built in the widget layer from what was already there, so every
  renderer draws them and the protocol is as it was.
- **A `DataTable` is as wide as what it is in.** Flutter makes each column
  as wide as its widest cell; here the columns shared the width equally -
  since 2026-10-17 by how wide their cells are. `columnSpacing` is 24 where
  it is not said, and a cell too narrow for its text wraps it.

### A canvas paints gradients

- `paint.shader = LinearGradient(...).createShader(rect)`, and a
  `RadialGradient`'s, are drawn - filled or stroked. A paint's shader was
  ignored, so the shape was drawn in the paint's plain colour.
- The protocol: a canvas paint may carry `gradient` - `{type: 'linear',
  from, to, colors, stops?}` or `{type: 'radial', center, radius, colors,
  stops?}`, in the canvas's own coordinates. All four renderers.
- **On iOS a page whose body does not scroll and has a size of its own
  keeps its app bar the right height.** The spare height went to the bar,
  which came out half a screen tall over a canvas of a stated size.

### `PageView`

- `PageView`, `PageView.builder` and `PageController` (`jumpToPage`,
  `animateToPage`, `nextPage`, `previousPage`, `page`, `hasClients`), with
  `onPageChanged`, either `scrollDirection`, `reverse` and
  `NeverScrollableScrollPhysics`. They were missing, so an app with a
  carousel did not compile.
- A swipe moves to the page beside the one showing when the finger lifts,
  on the same pan along one axis a `TabBarView` uses. The page does not
  follow the finger, `animateToPage` arrives at once and `viewportFraction`
  is not carried. With `children` each page keeps its `State`; with the
  builder only the page showing is built.

### A drag says when it begins and ends

- `Draggable.onDragStarted`, `onDragEnd` and `onDraggableCanceled` are
  called, and `childWhenDragging` is drawn where the piece was while it is
  in the air. Only a drop a target accepted was heard before, so a board
  could not mark the piece being moved or put back one let go over nothing.
  The velocity and offset those callbacks are given are zero.
- The protocol: `dragEventId` on a box with `dragData`, sending `_start`
  when it is picked up and `_end` when it is let go - after any drop it
  made. `UIBuilder.box` takes `onDrag`. All four renderers.
- Dragged on an Android emulator and in Chrome. Not by hand on iOS.

### A windowed list says where it is

- A `ScrollController` on a `ListView` with `itemExtent` follows the
  reader: `offset`, `position` and listeners, when the list comes to rest
  and at most every 100 ms on the way. It heard the app's own moves only.
- A windowed list comes back where it was when its tab or page returns.
  On the web it started again from the top.
- The protocol: `scrollEventId` on a `LazyList`, reporting `{offset,
  maxExtent, viewport}` as on a `Scroll`. `UIBuilder.lazyList` takes
  `onScroll`. All four renderers.

### A `Dismissible` slides away

- **The row follows the finger and is gone**, as in Flutter, with the
  app's own `background` behind it. It used to reveal a platform swipe
  action - a button in the background's colour and words - and did nothing
  for a vertical direction. `confirmDismiss`, `dismissThresholds`,
  `movementDuration` and all six directions are honoured. An app that
  relied on the revealed button gets the swipe instead;
  `UIBuilder.swipeActions` is still the node for actions behind a row.
- Built in the widget layer, so on every renderer at once. Each movement
  of the finger is a build; the gap a dismissed row leaves does not close
  until the app removes it.
- **A pan reports how far the finger moved on the screen** on iOS and
  Android. It was measured inside the box, so a box that followed the
  finger was told the finger had hardly moved - the web and the Flutter
  host always measured on the screen.
- **On iOS a scroller waits for a pan along one axis**, where the two
  raced and the scroller around a row took a sideways swipe.
- **A short list is not stretched to fill the screen on iOS.** A scroller
  was tied to its content's length by a constraint, which on a page taller
  than the list was met by stretching a row - a `ListTile` several times
  its height. The scroller is naturally as long as its content now, which
  asks nothing of the content.
- Swiped on an iOS simulator, an Android emulator and in Chrome with touch.

### A `TabBarView` is swiped

- A swipe across a `TabBarView`'s page moves to the tab beside it. The
  strip was the only way. The page changes when the finger lifts - it does
  not follow the finger - and `NeverScrollableScrollPhysics` turns the
  swipe off, as in Flutter.
- The protocol: `panAxis` ('horizontal' or 'vertical') on a box with a pan.
  A movement that sets off the other way is not the box's, so a list inside
  a swiped page still scrolls. All four renderers.
- A `GestureDetector` with only `onHorizontalDrag*`, or only
  `onVerticalDrag*`, is such a pan: it no longer takes a scroll the other
  way from the scroller it is in.
- **Text is written from the top of its box on iOS.** A label given more
  height than its lines need centred them, where Flutter and the other
  three renderers start at the top; a page that was one line of text had it
  halfway down the screen.
- Swiped on an iOS simulator, an Android emulator and in Chrome with touch.

### Buttons as Flutter draws them

- **`ElevatedButton` under Material 3 is the surface, raised, with the
  primary for its label.** It was a filled primary button, which is
  Flutter's `FilledButton`. This changes how every `ElevatedButton` in a
  Material 3 app looks; one that wants the fill is a `FilledButton`, or
  states `backgroundColor`. Under `useMaterial3: false` it is the filled
  button it was. The protocol: a new button variant, `elevated`, drawn by
  all four renderers.
- **A disabled button looks disabled on Android**: what it is drawn on at
  12%, its label at 38%. It kept the working button's colours.
- **`useMaterial3: false` reaches Android.** `AppTheme.material3` (from
  `ThemeData.toAppTheme()`) makes its buttons and cards 4dp, its floating
  button round and its bottom navigation pill-less. Only Android reads it.
- Seen on an Android emulator under both Materials, on an iOS simulator and
  in Chrome under both style kits.

### A run of text can be tapped

- `TextSpan(recognizer: TapGestureRecognizer()..onTap = ...)`: a link inside
  a paragraph. `TextSpan` had no `recognizer`, so an app with one did not
  compile. `TapGestureRecognizer` comes with the widgets.
- The protocol: a run in a `Text` node's `spans` may carry an `eventId`,
  which a tap on that run sends.
- All four renderers. On the web the run is a link - reached with Tab,
  chosen with Enter, announced as one. A touch on the words around a link is
  not the text's, and reaches whatever the text is written in.
- Seen on an iOS simulator, an Android emulator and in Chrome. Only a tap is
  heard, and on iOS a selectable text's links are not tappable.

### A windowed list can be padded and pulled

- `ListView.builder(itemExtent:, padding:)` puts its padding inside the
  scroller, so the rows scroll under the edges and the room below the last
  row is reached by scrolling to it. It was a `Padding` node around the
  list, which held the edges in.
- A `RefreshIndicator` over a windowed list gives it pull-to-refresh. It was
  "its child and no more", on the lists most likely to want it.
- The protocol: `padding`, `refreshEventId` and `refreshing` on a `LazyList`
  node, as on a `Scroll`, all optional. `UIBuilder.lazyList` takes
  `padding`, `onRefresh` and `refreshing`. The rows a renderer reports as
  visible are counted from the first row, below the padding.
- All four renderers. Seen on an iOS simulator, an Android emulator and in
  Chrome with touch.

### A rail draws what is put above and below it

- `NavigationRail(leading:, trailing:, extended:)` are drawn. They were
  accepted and left out, so a rail was its destinations and nothing else.
- The protocol: a `BottomNavigation` node with `rail` takes `extended`, and
  `hasLeading` / `hasTrailing` for its children - the leading, when there is
  one, and then the trailing. `UIBuilder.bottomNavigation` takes the three.
- All four renderers. Seen on an iOS simulator, an Android emulator and in
  Chrome under both style kits. An extended rail does not animate open and
  is 256 wide; on Android it is drawn here, since Material's rail has no
  such form in the version this builds against.
- **A rail in a row is drawn on iOS.** It had no height of its own and a row
  gave it none, so it was a blank strip the width of a rail. It is as tall as
  its row now, as Flutter's is.

### A text field takes the look it is given

- `TextField.style` (the colour, size and weight of what is typed) and
  `InputDecoration`'s `filled` and `fillColor`, `border` - none, an
  underline or a box, with the side's colour and width and the box's radius
  - and `contentPadding` are drawn. They were accepted and sent nowhere, so
  every field was its platform's default box. `TextFormField` the same.
- The protocol: `textColor`, `fontSize`, `fontWeight`, `fillColor`,
  `border`, `borderColor`, `borderWidth`, `borderRadius` and
  `contentPadding` on a `TextField` node, all optional. A field that states
  none of them is the renderer's, as before.
- All four renderers. Seen on an iOS simulator, an Android emulator and in
  Chrome under both style kits. The borders for a field's other states are
  the renderer's own, and on Android a field with a floating label is
  Material's filled box, which keeps its own line.
- **A text field in a column that aligns to one side is as wide as the
  column on Android**, as it is in Flutter and already was on iOS and the
  web. It was as wide as its hint.

### A control takes the colour it is given

- `Checkbox(activeColor:, checkColor:)`, `Radio(activeColor:)`,
  `Switch(activeColor:, activeTrackColor:, activeThumbColor:,
  inactiveTrackColor:, inactiveThumbColor:)`, `Slider(activeColor:,
  inactiveColor:, thumbColor:)` and `FloatingActionButton(backgroundColor:,
  foregroundColor:)` are drawn in those colours. The widgets accepted them
  and sent none, so every control was the theme's primary and an app could
  not have one green switch.
- The protocol: `activeColor`, `checkColor`, `thumbColor`, `inactiveColor`,
  `inactiveTrackColor` and `inactiveThumbColor` on the four controls, and
  `foregroundColor` beside the `backgroundColor` a floating button already
  had. All optional; a control that states none is the renderer's to
  colour, as before, and one that stops stating them goes back.
- All four renderers, on the build and on a patch. Seen on an iOS simulator,
  an Android emulator and in Chrome under both style kits. On the web a
  browser's own checkbox and range input take one accent colour, so the
  tick, the thumb and the unfilled track are theirs outside the Materialize
  kit, which draws those parts itself.

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
- **None of the three migrated production apps has run on iOS.** They were
  walked screen by screen on an Android emulator, which found and fixed some
  thirty bugs; on iOS the examples and the controls gallery have been driven
  on a simulator (`tool/device_check.sh ios`, with the gallery's three Maestro
  flows since 2026-10-18) and three examples on an iPad, and that is all.
  Most iOS screens have not been looked at on a phone. The device flows cannot
  close that gap - Maestro cannot build its driver for a physical iOS device
  (see `maestro/native/README.md`), so it stays a by-hand job.
- The last device runs on real hardware were on 2026-09-24; everything since
  has run on an iOS simulator and an Android emulator.
- A list of rows of no stated height is windowed with guessed heights for the
  rows not yet seen: a jump to a far offset lands by the guesses, and the
  scroll bar's length settles as rows are measured.
- What a build makes from a scroll offset follows it each frame for a box's
  opacity, size, movement, turn and colour; words and a tree that changes
  shape with the offset follow the reports, at most every 100 ms.
- Text is measured with Roboto's widths and kerning (or an app font's, once
  registered); ligatures and Arabic's joined forms are not counted, and
  scripts without a table are estimated.
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
