// What the widget layer tells a renderer about a node beyond how it looks: who
// it is (a Key becomes the id a device test finds it by), what it is called,
// what it is, and whether it is on. A renderer can only put in the
// accessibility tree what the tree it is given says.
import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<WidgetNode> _walk(WidgetNode node) sync* {
  yield node;
  for (final child in node.children ?? const <WidgetNode>[]) {
    yield* _walk(child);
  }
}

List<WidgetNode> _nodes(Widget widget) {
  final renderer = InMemoryRenderer();
  final app = hostApp(widget)..mount(renderer);
  addTearDown(app.unmount);
  return _walk(renderer.tree!).toList();
}

WidgetNode _byId(Widget widget, String id) =>
    _nodes(widget).firstWhere((n) => n.props['id'] == id);

void main() {
  group('Semantics', () {
    test('a header is said of the text itself, not a box around it', () {
      final nodes = _nodes(
        const Semantics(header: true, child: Text('Guests')),
      );
      final text = nodes.firstWhere((n) => n.type == 'Text');
      expect(text.props['semanticRole'], 'heading');
      expect(nodes.where((n) => n.type == 'Box'), isEmpty);
    });

    test(
      'a label around something tappable names the thing that is tapped',
      () {
        final box = _byId(
          Semantics(
            label: 'Tube 1',
            child: GestureDetector(
              key: const ValueKey('tube'),
              onTap: () {},
              child: const SizedBox(width: 10, height: 10),
            ),
          ),
          'tube',
        );
        expect(box.props['tapEventId'], isNotNull);
        expect(box.props['semanticLabel'], 'Tube 1');
      },
    );

    test('a label around something else is a box that carries it', () {
      final box = _byId(
        const Semantics(
          key: ValueKey('weather'),
          label: 'Sunny',
          value: '24 degrees',
          image: true,
          child: Icon(Icons.wb_sunny),
        ),
        'weather',
      );
      expect(box.type, 'Box');
      expect(box.props['semanticLabel'], 'Sunny, 24 degrees');
      expect(box.props['semanticRole'], 'image');
    });

    test('liveRegion and excludeSemantics travel', () {
      final box = _byId(
        const Semantics(
          key: ValueKey('status'),
          label: 'Saved',
          liveRegion: true,
          excludeSemantics: true,
          child: Text('ok'),
        ),
        'status',
      );
      expect(box.props['liveRegion'], isTrue);
      expect(box.props['excludeSemantics'], isTrue);
    });

    test('ExcludeSemantics hides its child', () {
      final nodes = _nodes(const ExcludeSemantics(child: Text('decoration')));
      expect(
        nodes.where((n) => n.props['excludeSemantics'] == true),
        hasLength(1),
      );
    });
  });

  test('a Tooltip around something tappable is that thing\'s own', () {
    final box = _byId(
      Tooltip(
        message: 'Undo',
        child: InkWell(
          key: const ValueKey('undo'),
          onTap: () {},
          child: const Icon(Icons.undo),
        ),
      ),
      'undo',
    );
    expect(box.props['tapEventId'], isNotNull);
    expect(box.props['tooltip'], 'Undo');
  });

  group('a control in a list tile is named by the tile', () {
    test('checkbox', () {
      final box = _byId(
        CheckboxListTile(
          key: const ValueKey('terms'),
          title: const Text('Accept the terms'),
          value: false,
          onChanged: (_) {},
        ),
        'terms',
      );
      expect(box.type, 'Checkbox');
      expect(box.props['semanticLabel'], 'Accept the terms');
    });

    test('switch', () {
      final toggle = _byId(
        SwitchListTile(
          key: const ValueKey('alerts'),
          title: const Text('Send me alerts'),
          value: true,
          onChanged: (_) {},
        ),
        'alerts',
      );
      expect(toggle.type, 'Toggle');
      expect(toggle.props['semanticLabel'], 'Send me alerts');
    });

    test('radio', () {
      final radio = _byId(
        RadioListTile<String>(
          key: const ValueKey('pro'),
          title: const Text('Pro plan'),
          value: 'pro',
          groupValue: 'free',
          onChanged: (_) {},
        ),
        'pro',
      );
      expect(radio.type, 'Radio');
      expect(radio.props['semanticLabel'], 'Pro plan');
    });

    test('a control with a label of its own needs no other name', () {
      final box = _nodes(
        Checkbox(
          value: false,
          onChanged: (_) {},
          label: 'Subscribe',
          semanticLabel: 'ignored',
        ),
      ).firstWhere((n) => n.type == 'Checkbox');
      expect(box.props.containsKey('semanticLabel'), isFalse);
    });
  });

  group('a button drawn from a box', () {
    test('says it is a button and that it is off when it has no handler', () {
      final box = _byId(
        const FilledButton(
          key: ValueKey('letter'),
          onPressed: null,
          style: ButtonStyle(shape: WidgetStatePropertyAll(CircleBorder())),
          child: Text('E'),
        ),
        'letter',
      );
      expect(box.type, 'Box');
      expect(box.props.containsKey('tapEventId'), isFalse);
      expect(box.props['semanticRole'], 'button');
      expect(box.props['disabled'], isTrue);
    });

    test('says neither when it can be pressed', () {
      final box = _byId(
        FilledButton(
          key: const ValueKey('letter'),
          onPressed: () {},
          style: const ButtonStyle(
            shape: WidgetStatePropertyAll(CircleBorder()),
          ),
          child: const Text('E'),
        ),
        'letter',
      );
      expect(box.props['tapEventId'], isNotNull);
      expect(box.props.containsKey('disabled'), isFalse);
      expect(box.props.containsKey('semanticRole'), isFalse);
    });
  });

  group('selection', () {
    test('a filter chip says whether it is on', () {
      WidgetNode chip(bool selected) => _byId(
        FilterChip(
          key: const ValueKey('mon'),
          label: const Text('Mon'),
          selected: selected,
          onSelected: (_) {},
        ),
        'mon',
      );
      expect(chip(true).props['selected'], isTrue);
      expect(chip(false).props['selected'], isFalse);
    });

    test('a plain chip is not something that is on or off', () {
      final chip = _byId(
        const Chip(key: ValueKey('tag'), label: Text('Tag')),
        'tag',
      );
      expect(chip.props.containsKey('selected'), isFalse);
    });

    test('a chip\'s delete button has a name', () {
      final delete = _byId(
        Chip(
          key: const ValueKey('tag'),
          label: const Text('Tag'),
          onDeleted: () {},
        ),
        'tag.delete',
      );
      expect(delete.props['tooltip'], 'Delete');
    });

    test('the selected list tile says so, and only that one', () {
      WidgetNode tile(bool selected) => _byId(
        ListTile(
          key: const ValueKey('row'),
          title: const Text('Table 1'),
          selected: selected,
          onTap: () {},
        ),
        'row',
      );
      expect(tile(true).props['selected'], isTrue);
      expect(tile(false).props.containsKey('selected'), isFalse);
    });
  });

  group('progress', () {
    test('a keyed, named spinner carries both', () {
      final ring = _byId(
        const CircularProgressIndicator(
          key: ValueKey('loading'),
          semanticsLabel: 'Loading guests',
        ),
        'loading',
      );
      expect(ring.type, 'Loading');
      expect(ring.props['semanticLabel'], 'Loading guests');
    });

    test('a bar drawn from boxes says what it is and how far along', () {
      final bar = _byId(
        const LinearProgressIndicator(
          key: ValueKey('upload'),
          value: 0.4,
          minHeight: 8,
          semanticsLabel: 'Upload',
        ),
        'upload',
      );
      expect(bar.type, 'Box');
      expect(bar.props['semanticRole'], 'progress');
      expect(bar.props['semanticValue'], '40%');
      expect(bar.props['semanticLabel'], 'Upload');
    });
  });

  test('semanticRoles names every role the widget layer writes', () {
    expect(
      semanticRoles,
      containsAll(['heading', 'button', 'image', 'progress']),
    );
  });

  test('a canvas node can be named', () {
    final node = UIBuilder.canvas(commands: const [], semanticLabel: 'Chart');
    expect(node.props['semanticLabel'], 'Chart');
  });
}
