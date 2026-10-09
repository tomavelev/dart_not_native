/// Component Showcase - written as a plain Flutter app.
///
/// Three pages of components. Only the import (`widgets.dart`) renders the same
/// widget tree through Android Views, UIKit, or the DOM instead of the Flutter
/// engine — the code below is identical on every platform.
library;

import 'package:dart_not_native/widgets.dart';

/// Shared showcase logic
class ShowcaseLogic {
  int counter = 0;
  int tapCount = 0;

  void incrementCounter() {
    counter++;
    tapCount++;
  }

  void decrementCounter() {
    if (counter > 0) counter--;
  }

  void reset() {
    counter = 0;
    tapCount = 0;
  }
}

class ComponentsShowcaseApp extends StatefulWidget {
  const ComponentsShowcaseApp({super.key});

  static const pageCount = 3;

  @override
  State<ComponentsShowcaseApp> createState() => _ComponentsShowcaseAppState();
}

class _ComponentsShowcaseAppState extends State<ComponentsShowcaseApp> {
  final logic = ShowcaseLogic();
  int currentPage = 0;

  void _nextPage() => setState(
      () => currentPage = (currentPage + 1) % ComponentsShowcaseApp.pageCount);
  void _prevPage() => setState(() => currentPage =
      (currentPage - 1 + ComponentsShowcaseApp.pageCount) %
          ComponentsShowcaseApp.pageCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Component Showcase (Page ${currentPage + 1}/${ComponentsShowcaseApp.pageCount})',
        ),
      ),
      body: SingleChildScrollView(child: _pageContent()),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Increment',
        onPressed: () => setState(logic.incrementCounter),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _pageContent() {
    switch (currentPage) {
      case 0:
        return _layoutPage();
      case 1:
        return _componentsPage();
      case 2:
        return _richPage();
      default:
        return const Center(child: Text('Unknown page'));
    }
  }

  Widget _layoutPage() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('📐 Layout Components',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('✓ Column'),
                Text('Arranges children vertically. Used for stacking widgets.'),
                SizedBox(height: 16),
                Text('✓ Center'),
                Text('Centers its child both horizontally and vertically.'),
                SizedBox(height: 16),
                Text('✓ Padding'),
                Text('Adds space around a widget using the padding property.'),
                SizedBox(height: 16),
                Text('✓ SizedBox'),
                Text('Creates a box with fixed height for spacing.'),
                SizedBox(height: 16),
                Text('✓ Scaffold'),
                Text('App structure with an AppBar and a FAB.'),
              ],
            ),
          ),
          _navigationButtons(),
        ],
      );

  Widget _componentsPage() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('🎨 Basic Components',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('✓ AppBar'),
                const Text('Header with a title, drawn as the platform toolbar.'),
                const SizedBox(height: 16),
                const Text('✓ Text'),
                const Text('Displays text content.'),
                const SizedBox(height: 16),
                Text('Counter Value: ${logic.counter}',
                    key: const ValueKey('counter_value')),
                const SizedBox(height: 16),
                Text('Tap Count: ${logic.tapCount}',
                    key: const ValueKey('tap_count')),
                const SizedBox(height: 8),
                ElevatedButton(
                  key: const ValueKey('decrement'),
                  onPressed: () => setState(logic.decrementCounter),
                  child: const Text('Decrement'),
                ),
                const SizedBox(height: 16),
                const Text('✓ FloatingActionButton'),
                const Text('Circular button (position: bottom-right).'),
              ],
            ),
          ),
          _navigationButtons(),
        ],
      );

  Widget _richPage() => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('🎯 Rich Components',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('✓ Buttons'),
                Text('Elevated and text buttons with tap handlers.'),
                SizedBox(height: 16),
                Text('✓ TextField'),
                Text('Text input field backed by the native editor.'),
                SizedBox(height: 16),
                Text('✓ ListView'),
                Text('Scrollable list of items.'),
                SizedBox(height: 16),
                Text('Rendered natively on each platform:'),
                ListView(
                  children: [
                    ListTile(
                      title: Text('Native platform components'),
                      subtitle: Text('UIKit · Android Views · DOM'),
                    ),
                    ListTile(title: Text('Efficient stack layout')),
                    ListTile(title: Text('Centered content')),
                    ListTile(title: Text('One widget tree, every platform')),
                    ListTile(title: Text('Native performance')),
                  ],
                ),
              ],
            ),
          ),
          _navigationButtons(),
        ],
      );

  Widget _navigationButtons() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Page ${currentPage + 1} of ${ComponentsShowcaseApp.pageCount}',
                key: const ValueKey('page_indicator')),
            const SizedBox(height: 16),
            Row(
              spacing: 8,
              children: [
                ElevatedButton(
                  key: const ValueKey('prev_page'),
                  onPressed: _prevPage,
                  child: const Text('← Previous'),
                ),
                ElevatedButton(
                  key: const ValueKey('next_page'),
                  onPressed: _nextPage,
                  child: const Text('Next →'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Tap + to increment the counter'),
          ],
        ),
      );
}
