/// Mounts a widget on an in-memory renderer and drives it as a real one
/// would, so these tests exercise the widget layer rather than a stand-in.
library;

import 'package:dart_not_native/core.dart';
import 'package:bloc/bloc.dart';
import 'package:dart_not_native/widgets.dart';

Iterable<WidgetNode> _walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _walk(child);
  }
}

class Harness {
  Harness(Widget widget) : app = hostApp(widget) {
    app.onChanged = () => renders++;
    app.mount(renderer);
  }

  final NativeUIApp app;
  final InMemoryRenderer renderer = InMemoryRenderer();

  /// How many times the tree has been drawn.
  int renders = 0;

  Iterable<WidgetNode> get nodes => _walk(renderer.tree!);

  WidgetNode? find(String id) =>
      nodes.where((n) => n.props['id'] == id).firstOrNull;

  /// The text of the node with [id], or null when it is not in the tree.
  String? text(String id) => find(id)?.props['content'] as String?;

  Future<void> tap(String id) async {
    final node = find(id) ?? (throw StateError('No node "$id"'));
    await renderer.handleEvent(node.props['eventId'] as String, {});
    await pump();
  }

  /// Lets streams deliver and the rebuilds they ask for run.
  Future<void> pump() => Future<void>.delayed(Duration.zero);
}

class CounterCubit extends Cubit0 {
  CounterCubit([super.initial]);
}

/// A cubit that counts, and records being closed.
class Cubit0 extends Cubit<int> {
  Cubit0([super.initial = 0]);

  void increment() => emit(state + 1);
  void set(int value) => emit(value);

  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}
