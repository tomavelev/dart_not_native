/// Counter - written as a plain Flutter app.
///
/// The only thing that separates this from `lib/main.dart` is the import: swap
/// `package:dart_not_native/material.dart` (Flutter's engine) for
/// `package:dart_not_native/widgets.dart` and the same widgets render through
/// the platform's own views on Android and iOS, and the DOM on web - one file,
/// no per-platform variants.
library;

import 'package:dart_not_native/widgets.dart';

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  void _increment() => setState(() => _count++);
  void _decrement() => setState(() => _count = _count > 0 ? _count - 1 : 0);
  void _reset() => setState(() => _count = 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBar(title: Text('Counter App')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_count',
              key: const ValueKey('count'),
              style: const TextStyle(fontSize: 34),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                ElevatedButton(
                  key: const ValueKey('decrement'),
                  onPressed: _decrement,
                  child: const Text('Decrement'),
                ),
                ElevatedButton(
                  key: const ValueKey('reset'),
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _increment,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
