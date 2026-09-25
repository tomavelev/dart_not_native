# Component Showcase — Guide

A walkthrough of the **Component Showcase**
(`lib/examples/apps/components_showcase_app.dart`), the three-page tour of the
core widgets. It is a plain Flutter `StatefulWidget`; only the
`package:dart_not_native/widgets.dart` import makes it render through the
platform's own views instead of the Flutter engine.

## Running it

| Target | Command |
| --- | --- |
| Native (dev entry) | `flutter run -t lib/main_native_components_showcase.dart -d <device>` |
| Native (mobile entry) | `flutter run -t lib/examples/components_showcase.dart -d <device>` |
| Web | Built by `maestro/web/build_examples.sh`; driven by `maestro/web/flows/components_showcase.yaml`. |

The same source drives all of them — Android Views, UIKit, the DOM, and the
Flutter engine each paint the identical widget tree with native controls.

## Page 1 — Layout

Introduces the layout widgets: `Column` stacks children vertically, `Center`
centres a child, `Padding` insets it, `SizedBox` adds fixed gaps, and `Scaffold`
provides the `AppBar` + `FloatingActionButton` structure. The title reads
`Component Showcase (Page 1/3)` and a `page_indicator` shows `Page 1 of 3`.

## Page 2 — Basic components

Shows `AppBar`, `Text`, and interactive state:

- The `FloatingActionButton` (tooltip **Increment**) raises **Counter Value** and
  **Tap Count**.
- A **Decrement** `ElevatedButton` lowers the counter (floored at zero).
- The counter value **persists across page changes** — page away and back and it
  is still there, demonstrating that `State` outlives rebuilds on the native host.

## Page 3 — Rich components

Describes the richer widgets — buttons, `TextField`, and a `ListView` — and lists
what the framework does under the hood in a set of `ListTile`s:

- Native platform components (UIKit · Android Views · DOM)
- Efficient stack layout
- Centered content
- One widget tree, every platform
- Native performance

This page is taller than the viewport, so on the web the Maestro flow scrolls to
reach the navigation buttons.

## Navigation

`Previous` / `Next` page with wrap-around (Next on page 3 returns to page 1). The
`page_indicator` and the app-bar title both track the current page.

## Where to go next

- `COMPONENTS_SHOWCASE.md` — the complete widget catalogue.
- `EXAMPLES_DIRECTORY.md` — every example and how it is wired.
- The **Design System Showcase** — tokens plus `Card`, `Badge`, `Alert`,
  `Divider`, and the loading indicators.
