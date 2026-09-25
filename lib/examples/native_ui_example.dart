/// Native UI Example
///
/// This example demonstrates the new architecture where:
/// - App logic stays in Dart (client)
/// - UI is rendered by native widgets (Android Views, iOS UIViews, HTML/CSS)
/// - Communication via widget tree protocol

import 'package:flutter/material.dart';
import 'package:dart_not_native/material.dart';

/// Application state and logic (pure Dart)
class TodoAppLogic {
  int _counter = 0;
  final List<String> _todos = [];

  int get counter => _counter;
  List<String> get todos => _todos;

  void incrementCounter() {
    _counter++;
  }

  void addTodo(String title) {
    _todos.add(title);
  }

  void removeTodo(int index) {
    if (index >= 0 && index < _todos.length) {
      _todos.removeAt(index);
    }
  }
}

/// UI Definition (widget tree)
/// This builds the same widget tree regardless of platform
/// The native renderer handles translating it to native UI
class NativeUIApp extends StatefulWidget {
  final NativeUIRenderer renderer;
  final TodoAppLogic logic;

  const NativeUIApp({Key? key, required this.renderer, required this.logic})
    : super(key: key);

  @override
  State<NativeUIApp> createState() => _NativeUIAppState();
}

class _NativeUIAppState extends State<NativeUIApp> {
  late NativeUIRenderer renderer;
  late TodoAppLogic logic;

  @override
  void initState() {
    super.initState();
    renderer = widget.renderer;
    logic = widget.logic;

    // Register event handlers
    renderer.onEvent('increment', (_) {
      setState(() {
        logic.incrementCounter();
        _renderUI();
      });
    });

    // Initial render
    _renderUI();
  }

  void _renderUI() {
    // Build widget tree using the UIBuilder
    final tree = UIBuilder.scaffold(
      appBar: UIBuilder.appBar(title: 'Counter App'),
      body: UIBuilder.center(
        child: UIBuilder.column(
          children: [
            UIBuilder.text('You have pushed the button this many times:'),
            UIBuilder.text('${logic.counter}'),
          ],
        ),
      ),
      floatingActionButton: UIBuilder.floatingActionButton(
        tooltip: 'Increment',
        eventId: 'increment',
      ),
    );

    // Render to native UI
    renderer.render(tree);
  }

  @override
  Widget build(BuildContext context) {
    // In this architecture, Flutter is only used for:
    // 1. App logic (state, event handling)
    // 2. Building widget trees
    // 3. The renderer is responsible for UI

    // This method just manages the state lifecycle
    // The actual rendering is done by the native renderer
    return SizedBox.expand(
      child: Container(
        color: Colors.transparent,
        child: const Center(child: Text('Rendering via native UI...')),
      ),
    );
  }
}

/// Example: How to use this in a real app
void exampleUsage() {
  // 1. Create app logic (pure Dart)
  // final logic = TodoAppLogic();

  // 2. Get the native renderer for this platform
  // On web: WebUIRenderer
  // On Android: AndroidNativeRenderer
  // On iOS: iOSNativeRenderer
  // final renderer = getNativeRenderer(); // Platform-specific

  // 3. Build widget tree and render
  // final tree = UIBuilder.scaffold(...);
  // await renderer.render(tree);

  // 4. Handle events from native side
  // renderer.onEvent('increment', (_) {
  //   logic.incrementCounter();
  //   renderer.render(updatedTree);
  // });
}

/// Benefits of this architecture:
///
/// ✅ Logic Layer (Pure Dart):
///    - No platform-specific code
///    - Easy to test
///    - Single source of truth
///
/// ✅ UI Layer (Native Rendering):
///    - Android: Native Views / Jetpack Compose
///    - iOS: SwiftUI / UIKit
///    - Web: HTML/CSS with Material Design Lite
///
/// ✅ Communication (Widget Tree Protocol):
///    - JSON-serializable widget descriptions
///    - Platform-agnostic
///    - Event callbacks for interactivity
///
/// This is true "write once, run anywhere" - same logic,
/// native rendering on each platform.
