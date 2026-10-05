# Components Reference

The widgets most screens use, from `package:dart_not_native/widgets.dart`.
Each one has Flutter's name and signature and emits a platform-neutral node
tree; the renderer for your target (Android Views, UIKit, DOM, or the Flutter
engine) paints it with the platform's own controls. The code you write is
identical everywhere — only the import differs from a real Flutter app.

This is the short list. The layer holds most of what a Material app uses;
`packages/native_bridge/API_REFERENCE.md` has every family with its source
file, and each widget's doc comment says what it carries and what it accepts
and leaves alone. `INTEGRATION.md` §8.9 lists what looks or behaves
differently from Flutter.

To see the core widgets running, launch the **Component Showcase**
(`lib/examples/components_showcase.dart`) or the **Design System Showcase**
(`lib/examples/design_system_showcase.dart`).

## App structure

| Widget | Purpose |
| --- | --- |
| `MaterialApp` | Root of an app: `home`, or `initialRoute` + `routes`, or `MaterialApp.router`. Takes `theme`, `darkTheme`, `themeMode`, `locale`, `supportedLocales`, `builder`. |
| `Scaffold` | The frame of a screen: `appBar`, `body`, `floatingActionButton`, `bottomNavigationBar`, `drawer`. **The body does not scroll.** |
| `AppBar` | Top bar: `title`, `leading`, `actions`, `bottom` (a `TabBar`). Gains a back button on a page that can be popped. |
| `NavigationBar` / `BottomNavigationBar` | The platform's bottom navigation. `NavigationRail` for a wide window. |
| `TabBar` / `TabBarView` / `DefaultTabController` | Tabs. No swipe between pages. |
| `Navigator` | `push`, `pop`, `pushReplacement`, `popUntil`, `pushNamed`. See `ROUTING_GUIDE.md`. |

```dart
Scaffold(
  appBar: AppBar(title: const Text('Home')),
  body: ListView(children: const [ListTile(title: Text('Hello'))]),
  floatingActionButton: FloatingActionButton(
    onPressed: _add, child: const Icon(Icons.add)),
  bottomNavigationBar: NavigationBar(
    selectedIndex: _tab,
    onDestinationSelected: (i) => setState(() => _tab = i),
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
    ],
  ),
);
```

## Layout

| Widget | Purpose |
| --- | --- |
| `Column` / `Row` | Vertical / horizontal stacks (with `spacing`). `Flex` for either. |
| `Wrap` | Flowing layout that wraps to the next line (`spacing`, `runSpacing`). |
| `Stack` / `Positioned` | Children over one another; a child pinned to edges. `IndexedStack`. |
| `Container` | Size, padding, margin, `BoxDecoration` (colour, gradient, border, radius, shadow), alignment, transform - one `Box` node. |
| `Center` / `Align` / `Padding` | Place and inset a child. |
| `Expanded` / `Flexible` / `Spacer` | Share the main axis. |
| `SizedBox` / `ConstrainedBox` / `AspectRatio` | Fix or bound a size. |
| `SafeArea` | Keep clear of the system insets. |
| `ClipRRect` / `ClipOval` / `Opacity` / `Transform` | Clip, fade, move. |
| `Card` | A raised surface: a margin of 4 and no padding of its own, as in Flutter. |
| `Divider` / `VerticalDivider` | A rule. |
| `LayoutBuilder` / `MediaQuery` | Build from the room on offer or the window's size. |

## Scrolling and lists

| Widget | Purpose |
| --- | --- |
| `SingleChildScrollView` | Scroll one child, on either axis. |
| `ListView` / `ListView.builder` / `.separated` | A scrolling list. `.builder` is **windowed when given `itemExtent`** (or `itemExtentBuilder`); without one every row is built. |
| `GridView.count` / `.builder` / `.extent` | Equal cells in rows. |
| `RefreshIndicator` | Pull to refresh, on a scroller that is not windowed. |
| `ListTile` | Leading, title, subtitle, trailing, `onTap`. `CheckboxListTile`, `SwitchListTile`, `RadioListTile`, `ExpansionTile`. |
| `Dismissible` / `SwipeActions` | Swipe a row to reveal an action. |

```dart
ListView.builder(
  itemCount: messages.length,
  itemExtent: 72,   // a stated height is what makes ten thousand rows cheap
  itemBuilder: (context, index) => ListTile(
    key: ValueKey(messages[index].id),
    title: Text(messages[index].subject),
  ),
)
```

## Display

| Widget | Purpose |
| --- | --- |
| `Text` | Text with a `TextStyle`, `maxLines`, `overflow`, `textAlign`. `Text.rich` / `RichText` for styled runs. |
| `Icon` | An icon from `Icons` - every Material icon, including `_outlined`, `_rounded` and `_sharp`. |
| `Image.network` / `.asset` / `.memory` | An image. Remote ones are cached; `errorBuilder` gives the fallback. |
| `CircleAvatar` | A round picture or initials. |
| `Chip` and its kin | A compact label; `FilterChip`, `ChoiceChip`, `ActionChip`, `InputChip`. |
| `Badge` / `Alert` | A count or dot; an inline banner. Framework-specific. |
| `CustomPaint` | Draw with Flutter's `Canvas`, `Paint` and `Path`. |

## Input

| Widget | Purpose |
| --- | --- |
| `TextField` | Text entry with `InputDecoration`, `obscureText`, focus/submit events. |
| `TextEditingController` / `FocusNode` | Read and set field text; ask for the keyboard (see `TEXTINPUT_GUIDE.md`). |
| `Form` / `TextFormField` | Flutter's validated form. `ModelTextFormField` binds the framework's own `FormModel`. |
| `Checkbox` | Boolean toggle; `onChanged` is `ValueChanged<bool?>`. |
| `Radio<T>` | Single choice from a group. |
| `Switch` | On/off toggle. |
| `Slider` | A value in a range; `divisions`, `onChangeEnd`. |
| `DropdownButton<T>` | One of a list, from the platform's own menu. |
| `showDatePicker` / `showTimePicker` | The platform's own pickers. |

## Buttons and touch

| Widget | Purpose |
| --- | --- |
| `ElevatedButton` / `FilledButton` / `OutlinedButton` / `TextButton` | The four families; each has `styleFrom(...)` and an `.icon` form. |
| `IconButton` | An icon that acts as a button. |
| `FloatingActionButton` | The action button in a `Scaffold`; `.extended` adds a label. |
| `InkWell` / `GestureDetector` | Taps, double taps, long presses, drags on any child. |
| `Draggable` / `DragTarget` | Drag and drop. |

## Feedback, overlays and motion

| Widget / API | Purpose |
| --- | --- |
| `LinearProgressIndicator` / `CircularProgressIndicator` | Progress. |
| `Skeleton` | Loading placeholder. Framework-specific. |
| `showDialog` / `AlertDialog` / `SimpleDialog` | Modal dialog. |
| `showModalBottomSheet` | Modal bottom sheet. |
| `ScaffoldMessenger.of(context).showSnackBar` | `SnackBar` + `SnackBarAction`. One at a time - a new one replaces the old. |
| `AnimatedContainer` / `AnimatedOpacity` / `AnimatedScale` / `AnimatedRotation` / `AnimatedSlide` | Implicit animation, done by the renderer. |
| `FutureBuilder` / `StreamBuilder` / `ValueListenableBuilder` | Build from something that arrives or changes. |

```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('Message deleted'),
    action: SnackBarAction(label: 'Undo', onPressed: _undo),
  ),
);
```

## Theme and value types

`ThemeData` (with `ColorScheme.fromSeed` and `TextTheme`), read with
`Theme.of(context)` exactly as in Flutter:

```dart
Text(
  'Total',
  style: Theme.of(context).textTheme.titleMedium?.copyWith(
    color: Theme.of(context).colorScheme.primary,
  ),
)
```

`Color` (+ `Color.fromHex`) and `Colors`, `TextStyle`, `FontWeight`,
`TextDecoration`, `EdgeInsets` and `EdgeInsetsDirectional`, `Alignment`,
`BorderRadius`, `BoxDecoration`, `LinearGradient`, `BoxShadow`,
`MainAxisAlignment`, `CrossAxisAlignment`, `IconData` and `Icons`,
`ButtonStyle`, `InputDecoration`, `Offset`/`Size`/`Rect`, and `Key` /
`ValueKey` (a `ValueKey` becomes the node id used by tests and the renderers).

## How it renders

A widget's `build` returns other widgets; the framework flattens the tree into
`WidgetNode`s and hands them to the active renderer. The renderers map each node
type to a native control — e.g. `Column` → a vertical `UIStackView` /
`LinearLayout` / flex `div`, `TextField` → `UITextField` / `EditText` / `<input>`.
Because the node tree is identical across platforms, the same example produces a
native-looking result on each one without any per-platform code.

Where no platform has the control - a chip, a list tile, a card with a colour -
the widget is composed from boxes in Material's metrics instead, and looks the
same everywhere.
