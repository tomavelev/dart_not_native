/// Smoke tests every example app shares.
///
/// These guard the invariants a renderer depends on: the app mounts, the tree
/// it builds is well formed, every node the user can act on is wired to a
/// handler, and nothing renders a node type no renderer knows.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';
import '../support/example_apps.dart';

/// The events a node must have a handler for.
///
/// A text field's value arrives as `<eventId>_change`; focus, blur and submit
/// are optional. A field the app does not control (no `initialValue`, so it
/// only shows what the user typed) needs no handler at all - the showcases
/// use those, and disabled fields, to demonstrate appearance.
Set<String> _requiredEvents(WidgetNode node, String eventId) {
  if (node.type != 'TextField') return {eventId};
  if (node.props['enabled'] == false) return const {};
  if (node.props['initialValue'] == null) return const {};
  return {'${eventId}_change'};
}

void main() {
  exampleApps.forEach((name, build) {
    group(name, () {
      late AppTester tester;

      setUp(() => tester = AppTester.mount(build()));

      test('mounts and renders a tree', () {
        expect(tester.tree, isNotNull);
        expect(tester.nodes, isNotEmpty);
      });

      test('renders only node types the renderers implement', () {
        final unknown = tester.nodes
            .map((n) => n.type)
            .where((type) => !nodeTypes.contains(type))
            .toSet();

        expect(unknown, isEmpty);
      });

      test('survives the wire format', () {
        final round = WidgetNode.fromJson(tester.tree.toJson());

        expect(round.toJsonString(), tester.tree.toJsonString());
      });

      test('every interactive node is wired to a handler', () async {
        for (final node in tester.nodes) {
          final eventId = node.props['eventId'];
          if (eventId is! String) continue;

          for (final event in _requiredEvents(node, eventId)) {
            final result = await tester.emit(event, {
              'value': '',
              'checked': false,
              if (node.props['data'] is Map)
                ...Map<String, dynamic>.from(node.props['data'] as Map),
            });
            expect(
              result['success'],
              isTrue,
              reason: '$name: "$event" (${node.type}) has no handler',
            );
          }
        }
      });

      test('ids are unique so e2e flows can select them', () {
        final ids = tester.nodes
            .map((n) => n.props['id'])
            .whereType<String>()
            .toList();
        final duplicates = ids.toSet().where(
          (id) => ids.where((other) => other == id).length > 1,
        );

        expect(duplicates, isEmpty);
      });

      test('no text node renders a null or an unresolved placeholder', () {
        for (final text in tester.texts) {
          expect(text, isNot(contains('null')), reason: name);
          expect(text, isNot(contains('Instance of')), reason: name);
        }
      });

      test('re-rendering is stable when nothing changed', () async {
        // Some examples load asynchronously; compare settled trees.
        await Future<void>.delayed(Duration.zero);
        final first = tester.tree.toJsonString();

        tester.app.render();

        expect(tester.tree.toJsonString(), first);
      });
    });
  });

  test('the catalogue covers every example app', () {
    expect(exampleApps, hasLength(12));
  });
}
