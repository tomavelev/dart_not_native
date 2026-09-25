# Benchmark baseline

One run, so a later one has something to be compared against. These are
*records*, not thresholds: the numbers belong to the machine as much as to the
code, and a CI runner will produce different ones. What is asserted on every
commit lives elsewhere - see the bottom of this file.

Measured 2026-09-19 · an Apple Silicon Mac, macOS 26 · Flutter 3.47.2 (Dart VM for the
tree benchmarks, Chrome + dartdevc for the web ones) · medians over the
iteration counts each file sets.

Scene: the todo screen with 50 rows = **309 nodes**; the components screen =
**105 nodes**.

## Building and serialising a tree (`tree_build_benchmark.dart`, VM)

| Case | Median |
|---|---|
| build tree, todo 50 | 0.028 ms |
| build tree, components | 0.016 ms |
| toJson, todo 50 | 0.024 ms |
| toJsonString, todo 50 | 0.204 ms |
| props.toString() over the tree | 0.132 ms |
| mount + render through NativeUIApp | 0.089 ms |
| render + pump through the Flutter renderer, todo 50 | 0.078 ms |

Building a 309-node tree costs about as much as serialising it, and both are a
fraction of a frame. `toJsonString` is an order of magnitude dearer than
`toJson`, which is why the channel is handed the map.

## The web renderer (`web_render_benchmark.dart`, Chrome)

Awaited, so the timing covers the DOM work rather than the call that queues it.

| Case | Median |
|---|---|
| first paint, todo 50 | 0.699 ms |
| re-render, nothing changed | 0.100 ms |
| re-render, one text changed | 0.301 ms |
| re-render, list grows and shrinks | 0.301 ms |
| re-render, components | 0.099 ms |
| burst: 5 renders in one tick | 0.400 ms |

Unbatched, measured synchronously, with the keyed-row cases:

| Case | Median |
|---|---|
| re-render, nothing changed | 0.100 ms |
| re-render, one text changed | 0.300 ms |
| re-render, list grows and shrinks | 0.300 ms |
| front insert, rows unkeyed | 0.500 ms |
| front insert, rows keyed by id | 0.399 ms |
| build the tree only | ~0.000 ms |

Two things worth reading off this table, because both are easy to assume wrong:

- **Patching is cheaper than painting, but not by an order of magnitude** -
  0.30 ms against 0.70 ms. Most of a re-render is walking and comparing the
  tree, not touching the DOM. The saving grows with how little changed
  (nothing changed: 0.10 ms) rather than with the size of the screen.
- **Keys pay for themselves on a front insert** - 0.40 ms against 0.50 ms -
  because the rows are moved instead of rewritten, and that is before counting
  what a rewritten row costs the user (focus, scroll position, selection).

## Frame times on a device

Recorded separately, in TODO.md §1.4: the Android phone scrolls the 10k-row inbox at
0.7-0.8% janky frames with a 19.7 ms worst frame, in a release build.

## What is asserted rather than recorded

A number cannot gate a build across machines; a ratio can.

- `scaling_test.dart` - four times the rows costs about four times as much, not
  sixteen. Catches an accidental O(n²) on any machine.
- `../web_ui/render_cost_test.dart` - re-rendering an unchanged tree costs a
  fraction of drawing one (~7x here), the elements survive a re-render, and
  five renders in one tick cost about one. The *changed-row* ratio above is
  recorded rather than asserted: at ~1.8x it is too narrow to tell a
  regression from a busy machine, and a first attempt at gating on it failed
  in the full browser suite while passing on its own.

## Rerunning

```sh
cd packages/native_bridge
flutter test test/benchmark/tree_build_benchmark.dart
flutter test --platform chrome test/benchmark/web_render_benchmark.dart
```

Every report also prints a `BENCH_JSON {...}` line, which is what CI keeps as
an artifact.
