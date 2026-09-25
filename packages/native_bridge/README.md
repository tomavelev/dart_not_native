# dart_not_native

A reusable Dart/Flutter framework for calling native code via method dispatch. **Same client code runs on Android, iOS, and Web.**

Build Flutter UIs that bind directly to native methods without boilerplate.

## Features

- **Cross-platform** - Single client code, platform-specific backends (FFI for mobile, in-memory for web)
- **Generic method dispatch** - Call native methods by name, no FFI bindings per method
- **Reusable widgets** - `NativeStatefulWidget` wraps any native method into a Flutter widget
- **Browser memory** - Web state lives in browser memory; future plugins can add persistence
- **Zero initialization on web** - `NativeBridge.initialize()` is a no-op for web
- **Hot reload friendly** - Dart code hot reloads; native code requires hot restart
- **Extensible** - Add new native methods without touching bridge code

## Cross-Platform Support

**Same Dart UI code** runs identically on all platforms:

| Platform | Backend | Initialization | State Storage |
|----------|---------|-----------------|---------------|
| **Android** | Native C (FFI) | `NativeBridge.initialize('libbridge.so')` loads native library | C globals (device memory) |
| **iOS** | Native Swift/ObjC (FFI) | `NativeBridge.initialize('libbridge.so')` loads native library | C globals (device memory) |
| **Web** | Dart methods (in-memory) | `NativeBridge.initialize()` is a no-op | Dart globals (browser memory) |

**Your client code never changes:**

```dart
void main() {
  NativeBridge.initialize('libbridge.so');
  runApp(const MyApp()); // Identical code on all platforms
}
```

Platform detection is automatic via conditional imports. State lives in browser memory on web; future plugins can add localStorage/backend persistence.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  dart_not_native:
    path: ../packages/native_bridge
```

Or from git, now that the repository is hosted:

```yaml
dependencies:
  dart_not_native:
    git:
      url: https://github.com/tomavelev/dart_not_native.git
      path: packages/native_bridge
```

`dart_not_native: ^0.1.0` is not on pub.dev yet, so a path or git dependency
are the two that work.

## Usage

### 1. Initialize the Bridge

In `main.dart`:

```dart
import 'package:dart_not_native/native_bridge_flutter.dart';

void main() {
  NativeBridge.initialize('libbridge.so'); // or your library name
  runApp(const MyApp());
}
```

### 2. Create Native Widgets

Use `NativeStatefulWidget` to bind UI to native methods:

```dart
import 'package:dart_not_native/native_bridge_flutter.dart';

class MyCounter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NativeStatefulWidget(
      nativeMethodName: 'increment_counter',
      label: 'Counter',
      initialMethodName: 'get_counter',
      resetMethodName: 'reset_counter',
    );
  }
}
```

### 3. Implement Native Methods (C)

In your native C code:

```c
static int counter = 0;

int32_t get_counter() {
  return counter;
}

int32_t increment_counter() {
  counter++;
  return counter;
}

void reset_counter() {
  counter = 0;
}

// Generic dispatcher called by the bridge
int32_t call_native(const char* method_name, const char* args) {
  if (strcmp(method_name, "increment_counter") == 0) {
    return increment_counter();
  } else if (strcmp(method_name, "get_counter") == 0) {
    return get_counter();
  } else if (strcmp(method_name, "reset_counter") == 0) {
    reset_counter();
    return 0;
  }
  return -1; // Unknown method
}
```

### 4. Low-Level Method Calls

For custom logic, call methods directly:

```dart
import 'package:dart_not_native/native_bridge_flutter.dart';

// Call a native method and get result
int result = NativeBridge.callMethod('increment_counter');

// Call with arguments (if your C code parses them)
int result = NativeBridge.callMethod('set_value', '42');
```

## Widget Parameters

`NativeStatefulWidget` supports:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `nativeMethodName` | String | required | Method to call on action |
| `label` | String | required | Display label |
| `initialMethodName` | String | `'get_value'` | Method to load initial value |
| `resetMethodName` | String | `'reset_value'` | Method to call on reset |
| `onValueChanged` | `ValueChanged<int>?` | null | Callback on value change |
| `actionButtonLabel` | String | `'Invoke'` | Action button text |
| `resetButtonLabel` | String | `'Reset'` | Reset button text |
| `showResetButton` | bool | true | Show/hide reset button |

## Architecture

**Conditional imports** (automatic platform detection):

```
native_bridge.dart
  ↓
[kIsWeb check]
  ├─ true → import 'platforms/web_bridge.dart'
  └─ false → import 'platforms/mobile_bridge.dart'
```

**Cross-platform flow:**

```
Dart UI Code (identical on all platforms)
  ↓
NativeStatefulWidget.build() (same code everywhere)
  ↓
NativeBridge.callMethod('method_name')
  ↓
┌─────────────────────────────────────────────────┐
│ Platform-specific dispatch                       │
├─────────────────────────────────────────────────┤
│ Mobile (Android/iOS)                            │ Web (Browser)
│ ─────────────────────────                       │ ────────────
│ platform/mobile_bridge.dart                     │ platform/web_bridge.dart
│   ↓                                             │   ↓
│ FFI: DynamicLibrary.open('libbridge.so')        │ Dart global functions
│   ↓                                             │   ↓
│ Native C: call_native(methodName, args)         │ switch(methodName)
│   ↓                                             │   ↓
│ Dispatcher → specific C function                │ Dart method (_incrementCounter, etc.)
│   ↓                                             │   ↓
│ C Implementation                                │ In-memory Dart state
└─────────────────────────────────────────────────┘
  ↓
Result: int32 (identical across platforms)
```

## Building Native Code

Use CMake to compile C code into `libbridge.so`:

**CMakeLists.txt**:
```cmake
cmake_minimum_required(VERSION 3.10)
project(my_app)

add_library(bridge SHARED src/main/cpp/bridge.c)
```

**build.gradle.kts**:
```kotlin
android {
  externalNativeBuild {
    cmake {
      path = file("CMakeLists.txt")
    }
  }
}
```

## Web State Persistence

By default, web state lives in browser memory and is lost on refresh. Future plugins can add:

- **localStorage plugin** - Persist simple key-value state
- **IndexedDB plugin** - Persist complex object state
- **Backend sync plugin** - Sync state to a server

Plugins would hook into `initializeWeb()` in `platforms/web_bridge.dart` without changing your client code.

## Limitations

- Return type is fixed to `int32` (can be extended for other types)
- Method names limited to C identifiers
- No built-in argument parsing (parse in C if needed)
- Hot reload requires native library to be reloaded (not automatic)
- Web state is not persisted by default (future plugin)

## Not yet: offline-first sync

`lib/plugins/backend_sync_plugin.dart` declares the pieces an offline-first
sync needs - a queue of pending operations, a retry policy, a sync status, a
conflict outcome - and performs no sync. There is no `BackendSync` API to call.

An app that has to work offline today keeps its own state with
`StorageService` (or `SecureStorageService`) and talks to its own backend; the
plugin system is how a sync would be dropped in later without the app changing.

## Example Project

See `dart_not_native` example app in the repository for a complete implementation.

## License

Copyright 2026 Toma Velev.

Licensed under the [Apache License, Version 2.0](LICENSE). Commercial and
closed-source use is allowed; redistribution carries the [NOTICE](NOTICE)
file, which also lists the vendored fonts and CSS frameworks in `web_shell/`
and their own licences.
