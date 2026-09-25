# Components Reference

The widgets available from `package:dart_not_native/widgets.dart`. Each one is a
Flutter-shaped class that emits a platform-neutral node tree; the renderer for
your target (Android Views, UIKit, DOM, or the Flutter engine) paints it with
the platform's own controls. The code you write is identical everywhere — only
the import differs from a real Flutter app.

To see them all running, launch the **Component Showcase**
(`lib/examples/components_showcase.dart`) or the **Design System Showcase**
(`lib/examples/design_system_showcase.dart`).

## App structure

| Widget | Purpose |
| --- | --- |
| `MaterialApp` | Root of a routed app: `home`, or `initialRoute` + `routes`. |
| `Scaffold` | Screen scaffold with `appBar`, `body`, and `floatingActionButton`. |
| `AppBar` | Top bar with a `title`. |
| `Navigator` | `pushNamed`, `pop`, plus `currentPath` / `history` / `canGoBack`. |

```dart
Scaffold(
  appBar: AppBar(title: const Text('Home')),
  body: Center(child: Text('Hello')),
  floatingActionButton: FloatingActionButton(
    onPressed: _add, child: const Icon(Icons.add)),
);
```

## Layout

| Widget | Purpose |
| --- | --- |
| `Column` / `Row` | Vertical / horizontal stacks (with `spacing`). |
| `Wrap` | Flowing layout that wraps to the next line (`spacing`, `runSpacing`). |
| `Center` | Centre a child on both axes. |
| `Padding` | Inset a child by `EdgeInsets`. |
| `Expanded` | Fill remaining space along the main axis (by `flex`). |
| `SizedBox` / `Spacer` | Fixed gaps / flexible gaps. |
| `ListView` / `ListView.builder` | Scrollable lists; `.builder` is lazy for long lists. |
| `ListTile` | A row with `title` / `subtitle`. |
| `Card` | Elevated, outlined, or filled container. |
| `Divider` | A horizontal rule. |

## Display

| Widget | Purpose |
| --- | --- |
| `Text` | Text with a `TextStyle` (color, size, `FontWeight`, decoration). |
| `Icon` | An icon from `Icons`. |
| `Badge` | A small count/dot badge. |
| `Alert` | An inline informational banner. |

## Input

| Widget | Purpose |
| --- | --- |
| `TextField` | Text entry with `InputDecoration`, `obscureText`, focus/submit events. |
| `TextEditingController` | Read and set field text (see `TEXTINPUT_GUIDE.md`). |
| `Checkbox` | Boolean toggle, optionally with a label. |
| `Radio<T>` | Single choice from a group. |
| `Switch` | On/off toggle. |

## Buttons

| Widget | Purpose |
| --- | --- |
| `ElevatedButton` | Primary button; `ElevatedButton.styleFrom(backgroundColor: ...)`. |
| `TextButton` | Low-emphasis button. |
| `IconButton` | An icon that acts as a button. |
| `FloatingActionButton` | The circular action button in a `Scaffold`. |

## Feedback & overlays

| Widget / API | Purpose |
| --- | --- |
| `LinearProgressIndicator` / `CircularProgressIndicator` | Progress. |
| `Skeleton` | Loading placeholder. |
| `showDialog` / `AlertDialog` | Modal dialog. |
| `showModalBottomSheet` | Modal bottom sheet. |
| `ScaffoldMessenger.of(context).showSnackBar` | `SnackBar` + `SnackBarAction`. |

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('Message deleted'),
    action: SnackBarAction(label: 'Undo', onPressed: _undo),
  ),
);
```

## Value types

`Color` (+ `Color.fromHex`) and `Colors`, `TextStyle`, `FontWeight`,
`TextDecoration`, `EdgeInsets`, `MainAxisAlignment`, `CrossAxisAlignment`,
`IconData` and `Icons`, `ButtonStyle`, `InputDecoration`, and `Key` / `ValueKey`
(a `ValueKey` becomes the node id used by tests and the renderers).

## How it renders

A widget's `build` returns other widgets; the framework flattens the tree into
`WidgetNode`s and hands them to the active renderer. The renderers map each node
type to a native control — e.g. `Column` → a vertical `UIStackView` /
`LinearLayout` / flex `div`, `TextField` → `UITextField` / `EditText` / `<input>`.
Because the node tree is identical across platforms, the same example produces a
native-looking result on each one without any per-platform code.
