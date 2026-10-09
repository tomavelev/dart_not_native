# Testing

The framework renders **native UI** - Android Views, iOS UIViews, real DOM -
not a Flutter canvas. That shapes what each test layer can look at:

| Layer | What it checks | Where | How to run |
|---|---|---|---|
| Unit | Pure Dart: protocol, router, forms, i18n, storage, plugins, design system | `packages/native_bridge/test/` | `cd packages/native_bridge && flutter test` |
| Widget (native UI) | An app mounted on a renderer: events in, tree out | `test/apps/` | `flutter test` |
| Widget layer | The Flutter-shaped facade itself: state identity, navigation, forms, painting, direction | `test/apps/flutter_facade_test.dart`, `packages/native_bridge/test/widgets/`, `packages/native_bridge/test/router/` | `flutter test` in each |
| Companion | `dart_not_native_bloc`'s providers and bloc widgets | `packages/dart_not_native_bloc/test/` | `cd packages/dart_not_native_bloc && flutter test` |
| Widget (DOM) | Real elements, classes, attributes and browser events | `packages/native_bridge/test/web_ui/` | `cd packages/native_bridge && flutter test --platform chrome` |
| Widget (Flutter) | The Flutter renderer painting the tree, the Flutter-hosted screens, `NativeStatefulWidget` | `packages/native_bridge/test/platforms/flutter_renderer_test.dart`, `test/flutter/` | `flutter test` |
| Golden (tree) | The widget tree each example builds, as JSON | `test/goldens/` | `flutter test` |
| Golden (DOM) | The markup each style kit produces | `packages/native_bridge/test/web_ui/dom_golden_test.dart` | `flutter test --platform chrome` |
| Device (native) | A tap and a keystroke through the real views - on a physical Android, or an iOS simulator (Maestro cannot build its driver for an iOS device) | `maestro/native/flows/` | `maestro/native/run.sh android` / `… ios` |
| Device (agent-device) | The same real views, found by id: tappable boxes, layers, a dropdown, tabs, a bottom bar, a dialog, a snackbar - on an Android device or emulator | `e2e/agent-device/flows/` | `e2e/agent-device/run.sh` |
| Integration | The whole app on a device or desktop host | `integration_test/` | `flutter test integration_test -d linux` |
| E2E | A real browser, real CSS, screenshots | `maestro/web/` | `maestro/web/run.sh` |

## Everything at once

```bash
flutter test                                              # examples + goldens + Flutter widgets
flutter test integration_test -d linux                    # or -d <device>
cd packages/native_bridge && flutter test                 # framework unit tests
cd packages/native_bridge && flutter test --platform chrome test/web_ui   # DOM + DOM goldens
cd packages/dart_not_native_bloc && flutter test          # the bloc companion (not in CI, not counted)
```

Every example app is rendered three ways by the suite: as a tree
(`test/apps/`), as DOM in Chrome, and as Flutter widgets
(`test/flutter/example_apps_flutter_render_test.dart`, which also checks each
screen fits a phone and uses no node type the renderer cannot paint).

## Testing a screen written against `widgets.dart`

`flutter_test`'s `WidgetTester` pumps Flutter widgets, and a screen written
against `package:dart_not_native/widgets.dart` is not made of those. The
equivalent is `hostApp` - which wraps a widget as the `NativeUIApp` the
framework mounts - on an `InMemoryRenderer`, which keeps the tree and
dispatches events. `test/support/app_tester.dart` is the harness over the two:

```dart
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

void main() {
  test('tapping Add counts', () async {
    final tester = AppTester.mount(hostApp(const Counter()));
    expect(tester.text('count'), '0');   // the Text with ValueKey('count')
    await tester.tap('add');             // the button with ValueKey('add')
    expect(tester.text('count'), '1');
  });
}
```

A `ValueKey` becomes the node's `id`, which is how a test finds a node. There
is no `pump`: await the event and the tree is current. `tester.emit` sends a
raw event - `RendererEvents.viewport` with a `width` and `height` is how a
test gives `MediaQuery` and `LayoutBuilder` a window.

This asserts the *tree* - that a node says the right thing - not the picture.
Whether a renderer draws it correctly is that renderer's own suite, and
whether a layout overflows is only seen on the Flutter renderer
(`test/flutter/example_apps_flutter_render_test.dart`) or a device.

`AppTester` is not exported by the package. An app that depends on the
framework copies the file into its own `test/support/`, which is what the
three migrated apps do (`TODO.md` §6.5 has shipping it as an open item).

## The native renderers

The Kotlin and Swift renderers need a device, an emulator or a simulator, and
an Xcode for the iOS half - none of which a plain `flutter test` has. So
`renderer_coverage_test.dart` reads the dispatch out of all four renderer
sources and checks each against the protocol's node vocabulary, and pins a few
behaviours the same way (the focus ask on both build and patch paths, the app
bar's insets). A renderer that stops handling a type fails that test on any
machine, instead of showing a placeholder on a device nobody is holding.

Reading source is not compiling it, and compiling it is not running it. The
`native.yml` lane compiles both natives when a path that can break them
changes, and it built everything the iOS renderer gained on 2026-10-03.
`tool/device_check.sh ios` then ran it on a simulator on 2026-10-09 and came
back green - which says the examples draw, not that anyone has looked at them
(`TODO.md` §6.1).

## What runs in CI, and when

Two workflows, split by how long they take:

| Workflow | Lanes | When |
|---|---|---|
| `ci.yml` | analyze, the three suites, Linux integration, web examples, benchmarks | every push and PR - about three minutes |
| `native.yml` | Android and iOS compiles | when a path that can break them changes |
| `quality.yml` | secret scan, no signing identifiers, publishable | every push and PR - seconds |

**Nothing in CI boots a device.** No simulator, no emulator, not even nightly.
(The agent-device lane is written to be run by one when that changes: it
would need an Android emulator with hardware acceleration, Node 22 with
`npm i -g agent-device`, Flutter, and then `e2e/agent-device/run.sh`, keeping
`e2e/agent-device/artifacts/` as the job's artefact.)
Those lanes took tens of minutes against about three for everything else, and
they were the only ones that ever hung - sixteen minutes with no output on a
simulator that finishes in under two on a laptop. They ran where the device
was slowest to get and least reliable.

## The device checks, on your machine

`tool/device_check.sh` is what those lanes did, run where the device already
is:

```bash
tool/device_check.sh android          # a phone over USB, or a running emulator
tool/device_check.sh ios              # a booted simulator
tool/device_check.sh ios --device <udid>
tool/device_check.sh android --flows-only
tool/device_check.sh ios --tests-only
```

It runs the Maestro flows first, then the integration tests one file at a
time, and finds the device itself. On Android it also sets `svc power stayon
true`, because a phone that sleeps mid-run produces black screenshots and dead
first taps that look exactly like render bugs.

What it covers has fallen behind what the renderers draw. The integration
lane's "one of every node type" tree and the Maestro flows were written for
the vocabulary as of 2026-09-24; the twelve node types added since are in
neither, except where an example app reaches one through the widget layer
(`TODO.md` §6.3). And `device_check.sh ios` needs the Swift to compile first.

**Run it after a change to the Kotlin or Swift renderers, and before a
release.** That is not a suggestion to be polite about: the flows are the only
thing that starts the app, and a compile cannot see an app that builds and
then refuses to launch. The iOS 26 UIScene failure was exactly that - `Runner`
quit before any Dart ran, and every compile lane was green.

## The agent-device lane

[agent-device](https://github.com/callstack/agent-device) drives an app the
way the Maestro flows do - through the platform's accessibility tree - from a
command line an AI agent can also hold. Its flows are `.ad` scripts: one
command a line, replayed by `agent-device test`.

```bash
npm i -g agent-device                    # 0.21.20 is what these were written against
e2e/agent-device/run.sh                  # every flow, on the only device attached
e2e/agent-device/run.sh gallery_touch    # one flow
e2e/agent-device/run.sh --no-build       # reuse what is installed
tool/device_check.sh android             # Maestro, then these, then the integration tests
```

Each flow names the entry point it needs in an `# entry:` comment, as the
Maestro flows do, and the runner builds each one once. It exits non-zero if a
flow fails, and leaves agent-device's logs, a JUnit file per flow and a
screenshot of the screen a failing flow stopped on under
`e2e/agent-device/artifacts/`, which git ignores. Android only for now: the
flows were written there, and the iOS half of what they rely on has drawn
the examples on a simulator and nothing more.

Six flows, across four entry points: the component showcase, the design
system, the text input showcase, and the controls gallery
(`lib/main_native_gallery.dart`) three times - touch, choosing, feedback. The
gallery exists for this lane: the older examples have no tappable box, no
layers, no dropdown, tabs or bottom bar for a flow to press.

To give an agent the same device, register the tool's MCP server:

```bash
claude mcp add agent-device -- agent-device mcp
```

### How a widget becomes something a flow can find

| In the widget | In the tree a flow reads | In a flow |
|---|---|---|
| `key: ValueKey('save')` on any widget | the node's `id`: Android `resource-id`, iOS `accessibilityIdentifier`, the DOM `id` | `press "id=\"save\""` - Maestro: `tapOn: {id: save}` |
| the text of a `Text` or a button | the element's text | `wait text "Saved"`, `press "label=\"Save\""` |
| `InkWell`, `GestureDetector(onTap:)`, `ListTile(onTap:)`, a chip | a button, named by the text inside it | `press "label=\"Tic Tac Toe\""` |
| `tooltip:` on an `IconButton`, `Icon(semanticLabel:)`, `Image(semanticLabel:)` | the element's description | `press "label=\"Undo\""` |
| `Semantics(label:)` | the description of the box around the child - or of the child itself, when the child takes a tap | `wait "label=\"Sunny, 24 degrees\""` |
| `onPressed: null`, a child of `IgnorePointer` | not enabled | `wait "id=\"save\" enabled=false"` |
| `FilterChip(selected:)`, `ListTile(selected:)`, the current tab or destination | selected | `wait "label=\"Guests\" selected=true"` |

The id is the key's value as written - `save`, not
`com.example:id/save`. That is what React Native does with a `testID` and
Compose with `testTagsAsResourceId`, and agent-device compares an `id`
selector with the whole string, so a prefixed id could only be matched by
spelling the package out. A text field's id is on the field itself, so `fill`
types into it and `is text` reads it back; a row a `Dismissible` swipes aside
gives its actions `<row id>.action-0`, `.action-1`.

What that means when writing a screen:

- **Key what a flow will press or read**, with a name that reads well in the
  flow. Prefer the text on screen where there is one; a key is for what has no
  text (a board cell, an icon button with no tooltip), what is ambiguous (the
  Delete in every row) and what changes with the language.
- **Name what has no text.** A box with a tap and nothing in it but an icon is
  announced as "button" and no more. Give the `IconButton` a `tooltip`, the
  `Icon` a `semanticLabel`, or wrap it in `Semantics(label:)`.
- **Assert what the screen says**, with `wait "<selector>" <ms>` on the
  condition rather than a pause. `wait "id=\"moves\" label=\"Moves: 1\""` is
  both the wait and the assertion.

### What agent-device cannot do here

Found on this stack, with 0.21.20:

- **A dropdown's menu is out of reach of a script.** It is a window of its
  own; the tree a selector is matched against leaves it out. By hand,
  `press 'label="Cherry"' --raw` reaches it; a `.ad` script has no `--raw`.
- **No `checked`.** A checkbox's state is in the snapshot but is not a
  selector key or an `is` predicate, so a flow asserts the text that follows
  from it ("Newsletter: on"). `selected` and `enabled` are keys.
- **`scroll up` and `scroll top` swipe the whole screen**, from a fifth of the
  way down it. Where something else is there - a card, a row of chips - the
  list never moves. `scroll down` starts low enough to land in the list.
- **A script has no `--until` and no `--settle`**, so "scroll until visible"
  is a fixed number of `scroll down` lines and a `wait`.
- **A press is a tap where the element is.** A swipe row's Delete is in the
  tree, and a screen reader can activate it, but the row covers it; a flow
  swipes first (`gesture drag` from one element in the row to another).

## Quality lanes

`quality.yml` runs on everything and takes seconds:

- **Secret scan** - gitleaks over the full history, which is the point: a
  secret that was committed and later deleted is the one worth finding.
  GitHub's own secret scanning and push protection are enabled on the
  repository and are the better defence, because they block a secret before it
  lands; this is the second pair of eyes, and it is stricter - it objected to
  demo values GitHub's scanner passed.
  `.gitleaks.toml` carries the exceptions, and each says why. They are all
  strings that exist only in commits *before* the example that wrote them was
  fixed; the working tree has none of them. If a new one appears, change the
  code rather than the config - a sample that ships a credential-shaped string
  teaches the shape and trips every scanner its readers run.
- **No signing identifiers committed** - an Apple team id is ten uppercase
  alphanumerics, and it belongs in the git-ignored
  `ios/Flutter/Signing.xcconfig`. The committed `.example` says YOUR_TEAM_ID,
  which the check deliberately allows.
- **Package still publishable** - `dart pub publish --dry-run`, which catches
  a missing repository URL, a changelog that has not heard of the version in
  the pubspec, or a file that should not ship. All easier to fix now than on
  release day.

`dependabot.yml` keeps the pinned actions current by opening pull requests,
which the other lanes then judge. It deliberately leaves Dart dependencies
alone: the lanes pin a Flutter version on purpose and a bot bumping packages
underneath that would fight it.

## Counting the tests

TODO.md's "What is already solid" quotes how many tests there are.
`tool/count_tests.sh` measures that rather than trusting anyone to remember:

```bash
tool/count_tests.sh            # print the three numbers
tool/count_tests.sh --write    # and put them into TODO.md
```

It runs all three suites, so it takes a minute, and it refuses to write if one
of them is red. Run it when you have added or removed tests - the number went
stale twice in one day while it was typed by hand.

The docs test below deliberately does not check these numbers: it would have
to run the suites from inside a suite. This is the seam where the
documentation still depends on someone doing something, and it is the only one
left.

## Docs against the code

`test/docs/docs_match_the_code_test.dart` checks the part of the
documentation a machine can check: every repository path a doc names exists,
every `package:dart_not_native/...` import a doc shows resolves, the suite has
no `skip:` in it (as the section below says), and there are no pixel goldens
(as the Goldens section says).

It exists because these files drift. Twelve claims were corrected on
2026-09-24 - a changelog describing CI lanes that had never run, this file
saying there were no pixel goldens, its "Skipped tests" section listing four
that had all been fixed, and paths pointing at files that had moved. Two of
those had been written earlier the same day.

Most of a doc is prose and stays a reader's job; this only pins what can be
pinned. If a claim it makes stops being true, change the code or change the
doc - and if a doc deliberately names something that does not exist yet, add
it to `plannedImports` with the reason.

## Benchmarks

Not tests, and not run by `flutter test` - they report numbers rather than
assert on them, since the numbers depend on the machine. Run them before and
after a change and compare:

```bash
cd packages/native_bridge
flutter test test/benchmark/tree_build_benchmark.dart              # tree, serialisation, Flutter renderer
flutter test --platform chrome test/benchmark/web_render_benchmark.dart
```

The web benchmark reports twice: once through the batched renderer with every
render awaited, and once through an unbatched one measured synchronously, so
the reconciliation algorithm can be compared across builds without the
batching changing what the timer sees.

## Goldens

Tree and markup goldens are the useful ones: the framework's output is a
widget tree that a native renderer turns into platform views, so those are
what a golden can meaningfully pin. Screenshots are covered by the Maestro
flows.

There are no pixel goldens, and that is a decision rather than an omission.
There was one - the counter as the Flutter renderer paints it - compared with
a tolerance, because a picture does not survive a change of engine. The
tolerance was set from a drift of two pixels between two versions of the same
engine on one machine. Then CI ran it on Linux and it drifted by **2810
pixels, 1.04% of the frame**, because FreeType and CoreText do not draw the
same glyph edges. No tolerance spans that honestly: 1% of a frame is enough to
hide a widget that moved, so a golden that permits it asserts nothing while
looking like it asserts something.

It was also blind to more than it appeared: the suite draws with the test
font, whose every glyph is the same box, so the picture pinned where things
were and how big, never which glyph. Swapping one icon for another left it
byte for byte identical.

The tree and markup goldens do the work instead. They compare structure, which
is what this framework actually produces, and they mean the same thing on
every machine.

Regenerate the tree goldens after an intended change:

```bash
UPDATE_GOLDENS=1 flutter test test/goldens/tree_golden_test.dart
```

The DOM goldens live in `packages/native_bridge/test/web_ui/goldens/dom.dart`;
browser tests cannot write files, so a drifted golden prints its fresh markup -
review it and paste it into that file.

## Skipped tests

None. This section used to list four tests skipped with a `BUG:` reason -
`Route.extractParams` leaking into `defaultParams`, `Locale.fromString`
reading the wrong script subtag, `Form.undo`/`redo` moving the cursor to the
end, and `DSText.h1`..`caption` ignoring the typography tokens. All four are
fixed and their skips are gone; the suite has no `skip:` left in it.

If a skip is added again, give it a `BUG:` reason saying what the code should
do, and list it here.
