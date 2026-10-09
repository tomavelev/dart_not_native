// A FlutterSlot on a page that is under another one is built only to keep
// its State; it must not keep re-registering a slot nothing draws.
import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Object _builder = (Object context) => Object();

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        key: const ValueKey('open'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const Text('second page')),
        ),
        child: const Text('open'),
      ),
      FlutterSlot(slotId: 'banner', height: 50, builder: _builder),
    ],
  );
}

Iterable<WidgetNode> _walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _walk(child);
  }
}

void main() {
  setUp(FlutterSlots.instance.clear);
  tearDown(FlutterSlots.instance.clear);

  test('a slot under a pushed page is not registered again', () async {
    final renderer = InMemoryRenderer();
    final app = hostApp(const MaterialApp(home: _Home()))..mount(renderer);
    addTearDown(app.unmount);
    expect(FlutterSlots.instance.isRegistered('banner'), isTrue);

    final open = _walk(renderer.tree!)
        .firstWhere((n) => n.props['id'] == 'open');
    await renderer.handleEvent(open.props['eventId'] as String, {});
    expect(_walk(renderer.tree!).any((n) => n.type == 'FlutterSlot'), isFalse);

    // What a native renderer does with the tree it was just handed.
    FlutterSlots.instance.sync(renderer, renderer.tree!);
    FlutterSlots.instance.unregister('banner');
    var changes = 0;
    FlutterSlots.instance.addListener(() => changes++);

    // The page on top rebuilds - a game ticking, say.
    app.render();
    app.render();
    expect(FlutterSlots.instance.isRegistered('banner'), isFalse);
    expect(changes, 0);

    // Back on the first page the slot is wanted again.
    SystemBack.dispatch();
    expect(_walk(renderer.tree!).any((n) => n.type == 'FlutterSlot'), isTrue);
    expect(FlutterSlots.instance.isRegistered('banner'), isTrue);
  });
}
