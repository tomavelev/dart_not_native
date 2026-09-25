# Examples Directory

A guide to every example application in the dart_not_native framework.

## The one idea behind every example

Each example is written as an ordinary Flutter app — `StatelessWidget` /
`StatefulWidget`, `setState`, `Scaffold`, `Column`, `TextField`, and so on.
The **only** thing that separates it from a real Flutter app is the import:

```dart
import 'package:dart_not_native/widgets.dart';   // renders through native views
// instead of
import 'package:flutter/material.dart';           // renders through the Flutter engine
```

The same widget tree is then painted through **Android Views**, **UIKit**, the
**DOM**, or the **Flutter engine**, depending on the entry point you launch.
There are no longer separate "Android", "iOS", and "web" copies of an example —
one codebase runs everywhere, and the platform is chosen at launch, not in the
source.

## The examples

| Example | App widget | Demonstrates |
| --- | --- | --- |
| **Counter** | `apps/counter_app.dart` | The smallest possible app: `setState` on a native renderer. |
| **Calculator** | `apps/calculator_app.dart` | Arithmetic + a flex/`Wrap` keypad grid. |
| **Todo** | `apps/todo_example_app.dart` | A list plus a `TextField` that adds and clears items. |
| **Inbox** | `apps/inbox_example_app.dart` | 10k-row `ListView.builder`, bottom sheet, confirm dialog, undo snackbar. |
| **Component Showcase** | `apps/components_showcase_app.dart` | A three-page tour of the core widgets. |
| **TextInput Showcase** | `apps/textinput_showcase_app.dart` | `TextField` variations, validation and focus/submit events. |
| **Design System Showcase** | `apps/design_system_showcase_app.dart` | Five pages of design-system tokens and components. |
| **Routing** | `apps/routing_example_app.dart` | `MaterialApp` named routes, route params, a back/forward history. |
| **i18n** | `apps/i18n_example_app.dart` | Locale switching through the framework's `I18n`. |
| **Storage** | `apps/storage_example_app.dart` | An injected storage back end (prefs/secure on mobile, localStorage on web). |

There is also a `native_ui_example.dart` concept demo that shows the raw
architecture (app logic in Dart, rendering delegated to the platform) without
the Flutter-shaped facade.

## How an example is wired

Every example is three thin layers:

```
lib/examples/apps/<name>_app.dart   ← the app itself (imports widgets.dart), platform-neutral
lib/examples/<name>.dart            ← mobile entry:  runApp(...)       → native views on the device
lib/examples/web/<name>.dart        ← web entry:     runWebApp(...)    → DOM (built by the maestro script)
```

Plus dev entry points at the repo root for running a specific example natively:

```
lib/main_native_<name>.dart         ← flutter run -t <this> -d <device>
```

The `main_native_*` entries carry **no** platform suffix — you choose the target
device with `-d`. The counter is the exception for historical reasons: it runs
from `lib/main_native_android.dart` and `lib/main_native_ios.dart`.

The catalogue in `test/support/example_apps.dart` constructs each app exactly the
way its entry point does, and both the smoke tests and the tree goldens iterate
over it — so every example is exercised by CI.

## Running the examples

**Natively (Android Views / UIKit) on a connected device or simulator:**

```bash
flutter run -t lib/examples/todo_example.dart          -d <device>
flutter run -t lib/main_native_components_showcase.dart -d <device>   # dev entry
flutter run -t lib/main_native_android.dart             -d <android>  # the counter
flutter run -t lib/main_native_ios.dart                 -d <ios>      # the counter
```

**On the web (DOM + CSS):** the web entries under `lib/examples/web/` are compiled
by `maestro/web/build_examples.sh`, which auto-discovers every file in that folder.
The Maestro flows in `maestro/web/flows/` then drive and snapshot them.

## File layout

```
lib/
├── main.dart                         Flutter-engine counter (the reference point)
├── main_native_android.dart          counter → Android Views
├── main_native_ios.dart              counter → UIKit
├── main_native_calculator.dart       \
├── main_native_components_showcase.dart│ dev entries: run one example natively
├── main_native_inbox.dart            │
├── main_native_textinput.dart        │
├── main_native_todo.dart             /
└── examples/
    ├── apps/                         the platform-neutral apps (import widgets.dart)
    │   ├── calculator_app.dart
    │   ├── components_showcase_app.dart
    │   ├── counter_app.dart
    │   ├── design_system_showcase_app.dart
    │   ├── i18n_example_app.dart
    │   ├── inbox_example_app.dart
    │   ├── routing_example_app.dart
    │   ├── storage_example_app.dart
    │   ├── textinput_showcase_app.dart
    │   └── todo_example_app.dart
    ├── <name>.dart                   mobile entries (runApp)
    ├── native_ui_example.dart        architecture concept demo
    └── web/<name>.dart               web entries (runWebApp)
```

## Choosing an example

- **Start here:** `counter_app.dart` — one screen, one `setState`.
- **See the widgets:** the **Component Showcase** and **Design System Showcase**.
- **Real interactions:** the **Inbox** (long list + overlays) and **Todo**.
- **Text entry:** the **TextInput Showcase**.
- **App structure:** the **Routing** example (named routes + history).
- **Platform services:** the **Storage** and **i18n** examples (injected back ends).
- **The architecture itself:** `native_ui_example.dart`.
