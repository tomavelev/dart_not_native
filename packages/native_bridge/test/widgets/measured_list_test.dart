/// A long `ListView.builder` whose rows say no height of their own is built
/// a window at a time all the same: the renderer measures the rows it holds
/// (`measureEventId`), and the rows not measured yet are as tall as the
/// ones that have been, on average.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppTester list({int count = 1000, bool separated = false}) {
    Widget row(BuildContext _, int i) => ListTile(title: Text('Row $i'));
    return AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: separated
              ? ListView.separated(
                  itemCount: count,
                  itemBuilder: row,
                  separatorBuilder: (_, _) => const Divider(),
                )
              : ListView.builder(itemCount: count, itemBuilder: row),
        ),
      ),
    );
  }

  test('only the rows near the screen are built, and are measured', () async {
    final app = list();
    final node = app.ofType('LazyList').single;
    expect(node.props['itemCount'], 1000);
    expect(node.props['measureEventId'], isA<String>());
    expect(app.hasText('Row 0'), isTrue);
    expect(app.hasText('Row 500'), isFalse);
    final window = (node.props['extents'] as List).length;
    expect(window, lessThan(100));

    // The renderer says the rows it holds are 72 tall: so is every other.
    await app.emit(node.props['measureEventId'] as String, {
      'start': 0,
      'heights': [for (var i = 0; i < window; i++) 72.0],
    });
    final after = app.ofType('LazyList').single;
    expect((after.props['extents'] as List).first, 72);
    expect(after.props['totalExtent'], closeTo(72 * 1000, 1e-6));
  });

  test('a separated list is rows and separators in turn', () {
    final app = list(separated: true);
    final node = app.ofType('LazyList').single;
    expect(node.props['itemCount'], 1999);
    expect(app.hasText('Row 0'), isTrue);
    expect(app.nodes.any((n) => n.type == 'Divider'), isTrue);
  });

  test('a short list is built whole, as before', () {
    final app = list(count: 20);
    expect(app.ofType('LazyList'), isEmpty);
    expect(app.hasText('Row 19'), isTrue);
  });

  test('a sliver list a builder makes, among others, is windowed too', () {
    final app = AppTester.widget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: Text('Header')),
              SliverList.builder(
                itemCount: 1000,
                itemBuilder: (_, i) => ListTile(title: Text('Row $i')),
              ),
              const SliverToBoxAdapter(child: Text('Footer')),
            ],
          ),
        ),
      ),
    );
    final node = app.ofType('LazyList').single;
    expect(node.props['itemCount'], 1002);
    expect(app.hasText('Header'), isTrue);
    expect(app.hasText('Row 0'), isTrue);
    expect(app.hasText('Row 999'), isFalse);
    expect(app.hasText('Footer'), isFalse);
  });
}
