# Maestro web tests for the examples

End-to-end flows for every runnable example in `lib/examples`, running in
headless Chrome against the **DOM build** of each example. The pages are real
HTML styled by a Material CSS framework, with no Flutter canvas. Every flow runs
once per **style kit** (Material Design Lite and Materialize CSS), and each
kit has its own screenshot baselines.

## Quick start

```bash
maestro/web/run.sh generate            # build, run all flows on mdl + materialize, record baselines
maestro/web/run.sh verify              # build, run all flows, compare with baselines
maestro/web/run.sh check               # behaviour only (no screenshots), fastest
```

Common options:

```bash
maestro/web/run.sh verify --kit materialize todo_example calculator_example
maestro/web/run.sh verify --no-build        # reuse build/web_examples
maestro/web/run.sh generate --kit mdl --port 9000
```

`run.sh` exits non-zero if any flow or screenshot comparison fails.

Requirements: Flutter SDK (`dart`), Maestro CLI (≥ 2.x, web support),
Google Chrome, `python3` (static server) and `curl`.

## Layout

```
maestro/web/
├── build_examples.sh          # dart2js build of lib/examples/web/*.dart → build/web_examples/<name>/
├── run.sh                     # generate | verify | check
├── flows/
│   ├── <example>.yaml         # one flow per example
│   ├── subflows/snap.yaml     # screenshot checkpoint (take or compare, by MODE)
│   └── screenshots/<kit>/<example>/NN_name.png   # baselines (commit these)
└── output/                    # reports, debug artifacts, diffs (git-ignored)
    └── <mode>/<kit>/{report.xml,debug/,diffs/}
```

## How it works

- **Web builds.** Each example has a pure-Dart app in `lib/examples/apps/`
  (written against `package:dart_not_native/widgets.dart`, with no Flutter
  import) and a web entry in `lib/examples/web/` that calls
  `runWebApp(hostApp(...))`. `build_examples.sh` compiles the entries with
  plain `dart compile js` (about 360-380 KB of JavaScript each, measured
  2026-10-03 at `-O2`) and copies `packages/native_bridge/web_shell/` next to
  them.
- **Style kits.** `WebUIRenderer` owns the DOM and events. A `WebStyleKit`
  builds the Material components. The page picks its kit from the URL
  (`?kit=mdl|materialize|plain`), so one build serves all kits. The flows open
  `${BASE_URL}/<example>/?kit=${KIT}&animations=off`.
- **Two variations, one set of flows.** Flows call `subflows/snap.yaml` at
  each checkpoint. `run.sh` sets `MODE`:
  - `generate`: `takeScreenshot` writes `flows/screenshots/<kit>/<example>/<name>.png`.
  - `verify`: `assertScreenshot` compares with that file at 99.95% similarity.
    A one-digit change on a 1280×800 page scores about 99.87%, so it fails.
  - `check`: no screenshots.
- **Determinism.** The viewport is fixed at 1280×800. CSS frameworks and fonts
  are vendored (no CDN). Fonts and stylesheets load before the first render,
  and animations are off. Baselines are still only comparable on the machine
  (OS, Chrome version, font rendering) that generated them, so regenerate them
  when that changes.

## Writing a flow

```yaml
url: ${BASE_URL}/my_example/?kit=${KIT}&animations=off
tags: [web]
---
- launchApp
- extendedWaitUntil:
    visible: "My title"
    timeout: 20000
- tapOn:
    id: save_button          # ElevatedButton(key: ValueKey('save_button'), ...)
- runFlow:
    file: subflows/snap.yaml
    env:
      NAME: my_example/01_saved
```

Selectors: Maestro reads an element's text from its own text nodes, and its
`id` from the DOM `id`, `aria-label`, `name` or `title` attribute. Give a
widget a `ValueKey` - it becomes the node's `id`, and so the element's -
whenever the visible text alone is ambiguous (`UIBuilder.text(..., id:)` and
`UIBuilder.button(..., id:)` at the protocol level). Icon buttons and FABs can be selected by
their tooltip (`id: "Increment"`).

After changing an example's UI on purpose, run `generate` for it and review
the new PNGs before committing them.
