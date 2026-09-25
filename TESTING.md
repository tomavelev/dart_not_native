# Testing

The framework renders **native UI** - Android Views, iOS UIViews, real DOM -
not a Flutter canvas. That shapes what each test layer can look at:

| Layer | What it checks | Where | How to run |
|---|---|---|---|
| Unit | Pure Dart: protocol, router, forms, i18n, storage, plugins, design system | `packages/native_bridge/test/` | `cd packages/native_bridge && flutter test` |
| Widget (native UI) | An app mounted on a renderer: events in, tree out | `test/apps/` | `flutter test` |
| Widget (DOM) | Real elements, classes, attributes and browser events | `packages/native_bridge/test/web_ui/` | `cd packages/native_bridge && flutter test --platform chrome` |
| Widget (Flutter) | The Flutter renderer painting the tree, the Flutter-hosted screens, `NativeStatefulWidget` | `packages/native_bridge/test/platforms/flutter_renderer_test.dart`, `test/flutter/` | `flutter test` |
| Golden (tree) | The widget tree each example builds, as JSON | `test/goldens/` | `flutter test` |
| Golden (DOM) | The markup each style kit produces | `packages/native_bridge/test/web_ui/dom_golden_test.dart` | `flutter test --platform chrome` |
| Device (native) | A tap and a keystroke through the real views - on a physical Android, or an iOS simulator (Maestro cannot build its driver for an iOS device) | `maestro/native/flows/` | `maestro/native/run.sh android` / `… ios` |
| Integration | The whole app on a device or desktop host | `integration_test/` | `flutter test integration_test -d linux` |
| E2E | A real browser, real CSS, screenshots | `maestro/web/` | `maestro/web/run.sh` |

## Everything at once

```bash
flutter test                                              # examples + goldens + Flutter widgets
flutter test integration_test -d linux                    # or -d <device>
cd packages/native_bridge && flutter test                 # framework unit tests
cd packages/native_bridge && flutter test --platform chrome test/web_ui   # DOM + DOM goldens
```

Every example app is rendered three ways by the suite: as a tree
(`test/apps/`), as DOM in Chrome, and as Flutter widgets
(`test/flutter/example_apps_flutter_render_test.dart`, which also checks each
screen fits a phone and uses no node type the renderer cannot paint).

The Kotlin and Swift renderers need a device, an emulator or a simulator, and
an Xcode for the iOS half - none of which a plain `flutter test` has. So
`renderer_coverage_test.dart` reads the dispatch out of all four renderer
sources and checks each against the protocol's node vocabulary, and pins a few
behaviours the same way (the focus ask on both build and patch paths, the app
bar's insets). A renderer that stops handling a type fails that test on any
machine, instead of showing a placeholder on a device nobody is holding.

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
no `skip:` in it (as the section below says), and there is exactly one pixel
golden (as the section above says).

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

There is exactly one pixel golden - `test/gallery/counter_gallery_golden_test.dart`,
the counter as the Flutter renderer paints it. It is compared with a tolerance
(`test/support/tolerant_golden_comparator.dart`) because a picture is the one
thing here that does not survive a change of engine: an upgrade moved two
pixels of an icon's edge and failed a test nothing had broken. Note what it
cannot see - the suite draws with the test font, whose every glyph is the same
box, so it pins where things are and how big, never which glyph.

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
