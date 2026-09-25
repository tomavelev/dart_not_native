/// Unit tests for the widget-tree protocol: the contract between Dart apps
/// and every native renderer (Android views, iOS views, web DOM).
library;

import 'dart:convert';

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tree.dart';

void main() {
  group('WidgetNode', () {
    test('toJson keeps type, props and nested children', () {
      final node = UIBuilder.column(
        children: [UIBuilder.text('hello'), UIBuilder.sizedBox(height: 8)],
      );

      expect(node.toJson(), {
        'type': 'Column',
        'props': <String, dynamic>{},
        'children': [
          {
            'type': 'Text',
            'props': {'content': 'hello'},
            'children': null,
          },
          {
            'type': 'SizedBox',
            'props': {'height': 8.0},
            'children': null,
          },
        ],
      });
    });

    test('survives a round trip through the wire format', () {
      final tree = UIBuilder.scaffold(
        appBar: UIBuilder.appBar(title: 'Demo'),
        body: UIBuilder.center(child: UIBuilder.text('body', fontSize: 20)),
        floatingActionButton: UIBuilder.floatingActionButton(
          tooltip: 'Add',
          eventId: 'add',
        ),
      );

      final decoded = WidgetNode.fromJson(
        jsonDecode(tree.toJsonString()) as Map<String, dynamic>,
      );

      expect(decoded.toJsonString(), tree.toJsonString());
      expect(decoded.children, hasLength(3));
      expect(nodeById(decoded, 'nope'), isNull);
      expect(texts(decoded), ['body']);
    });

    test('fromJson tolerates missing props and children', () {
      final node = WidgetNode.fromJson({'type': 'Spacer'});

      expect(node.type, 'Spacer');
      expect(node.props, isEmpty);
      expect(node.children, isNull);
    });
  });

  group('UIBuilder', () {
    test(
      'scaffold orders children app bar, body, fab and drops the absent',
      () {
        final full = UIBuilder.scaffold(
          appBar: UIBuilder.appBar(title: 'T'),
          body: UIBuilder.text('B'),
          floatingActionButton: UIBuilder.floatingActionButton(
            tooltip: 'F',
            eventId: 'f',
          ),
        );
        expect(full.children!.map((c) => c.type), [
          'AppBar',
          'Text',
          'FloatingActionButton',
        ]);

        final bare = UIBuilder.scaffold(body: UIBuilder.text('B'));
        expect(bare.children!.map((c) => c.type), ['Text']);
      },
    );

    test('optional style props are omitted rather than sent as null', () {
      final plain = UIBuilder.text('plain');
      expect(plain.props.keys, ['content']);

      final styled = UIBuilder.text(
        'styled',
        fontSize: 18,
        fontWeight: 700,
        color: '#ff0000',
        decoration: 'lineThrough',
        id: 'title',
      );
      expect(styled.props, {
        'content': 'styled',
        'fontSize': 18.0,
        'fontWeight': 700,
        'color': '#ff0000',
        'decoration': 'lineThrough',
        'id': 'title',
      });
    });

    test('button carries the event id, variant and handler payload', () {
      final node = UIBuilder.button(
        label: 'Delete',
        eventId: 'delete',
        variant: 'error',
        data: {'id': 7},
        disabled: true,
        id: 'delete_7',
      );

      expect(node.type, 'Button');
      expect(node.props['eventId'], 'delete');
      expect(node.props['variant'], 'error');
      expect(node.props['data'], {'id': 7});
      expect(node.props['disabled'], isTrue);
      expect(node.props['id'], 'delete_7');
    });

    test('button defaults to an enabled primary with no payload', () {
      final node = UIBuilder.button(label: 'OK', eventId: 'ok');

      expect(node.props['variant'], 'primary');
      expect(node.props['disabled'], isFalse);
      expect(node.props.containsKey('data'), isFalse);
      expect(node.props.containsKey('id'), isFalse);
    });

    test('a disabled button needs no handler and carries no event id', () {
      final node = UIBuilder.button(label: 'Disabled', disabled: true);

      expect(node.props['disabled'], isTrue);
      expect(node.props.containsKey('eventId'), isFalse);
    });

    test('an enabled button with no handler is a mistake, not a blank screen', () {
      expect(() => UIBuilder.button(label: 'Oops'), throwsArgumentError);
    });

    test('layout primitives keep alignment and spacing hints', () {
      final column = UIBuilder.column(
        crossAxisAlignment: 'stretch',
        children: [],
      );
      expect(column.props['crossAxisAlignment'], 'stretch');

      final row = UIBuilder.row(
        mainAxisAlignment: 'spaceBetween',
        spacing: 8,
        children: [],
      );
      expect(row.props['mainAxisAlignment'], 'spaceBetween');
      expect(row.props['spacing'], 8.0);

      // Spacing always ships so renderers need no default of their own.
      expect(UIBuilder.row(children: []).props['spacing'], 0.0);
    });

    test('expanded wraps a single child with a flex factor', () {
      final node = UIBuilder.expanded(child: UIBuilder.text('x'), flex: 3);

      expect(node.props['flex'], 3);
      expect(node.children, hasLength(1));
      expect(node.children!.single.type, 'Text');
    });

    test('text field ships hint, value and validation state', () {
      final node = UIBuilder.textField(
        hint: 'Email',
        eventId: 'email',
        label: 'Email address',
        error: 'Invalid email',
        obscureText: true,
        enabled: false,
        initialValue: 'a@b.co',
        maxLines: 3,
      );

      expect(node.type, 'TextField');
      expect(node.props, {
        'hint': 'Email',
        'eventId': 'email',
        'label': 'Email address',
        'error': 'Invalid email',
        'obscureText': true,
        'enabled': false,
        'initialValue': 'a@b.co',
        'maxLines': 3,
        // The return key closes the keyboard unless a field asks to advance.
        'textInputAction': 'done',
      });
    });

    test('a column says how it distributes its children, when it does', () {
      final centred = UIBuilder.column(
        mainAxisAlignment: 'center',
        children: [UIBuilder.text('x')],
      );
      expect(centred.props['mainAxisAlignment'], 'center');

      // 'start' is the absence of distributing, so it is left out and every
      // tree that never asked for any stays exactly as it was.
      final plain = UIBuilder.column(
        mainAxisAlignment: 'start',
        children: [UIBuilder.text('x')],
      );
      expect(plain.props.containsKey('mainAxisAlignment'), isFalse);
    });

    test('padding travels as one number, or as four', () {
      final uniform = UIBuilder.padding(all: 16, child: UIBuilder.text('x'));
      expect(uniform.props, {'padding': 16.0});

      // An override makes it non-uniform, and then every edge is stated: a
      // renderer that got one number could only guess which edges it meant.
      final mixed = UIBuilder.padding(
        all: 8,
        top: 24,
        child: UIBuilder.text('x'),
      );
      expect(mixed.props, {
        'paddingLeft': 8.0,
        'paddingTop': 24.0,
        'paddingRight': 8.0,
        'paddingBottom': 8.0,
      });

      // Edges given separately, with no `all` behind them, default to nothing.
      final sides = UIBuilder.padding(
        left: 12,
        right: 12,
        child: UIBuilder.text('x'),
      );
      expect(sides.props, {
        'paddingLeft': 12.0,
        'paddingTop': 0.0,
        'paddingRight': 12.0,
        'paddingBottom': 0.0,
      });
    });

    test('a label floats unless the field says otherwise', () {
      // The default is absent from the tree: a renderer floats a label it is
      // not told anything about, so only the opt-out has to travel.
      final floating = UIBuilder.textField(
        hint: 'Email',
        eventId: 'email',
        label: 'Email address',
      );
      expect(floating.props.containsKey('floatingLabel'), isFalse);

      final plain = UIBuilder.textField(
        hint: 'Email',
        eventId: 'email',
        label: 'Email address',
        floatingLabel: false,
      );
      expect(plain.props['floatingLabel'], isFalse);

      // Nothing to float without a label, so nothing is said about it.
      final unlabelled = UIBuilder.textField(
        hint: 'Email',
        eventId: 'email',
        floatingLabel: false,
      );
      expect(unlabelled.props.containsKey('floatingLabel'), isFalse);
    });

    test('checkbox and icon button carry their payload', () {
      final checkbox = UIBuilder.checkbox(
        eventId: 'toggle',
        checked: true,
        label: 'Done',
        data: {'id': 1},
      );
      expect(checkbox.props['checked'], isTrue);
      expect(checkbox.props['data'], {'id': 1});

      final icon = UIBuilder.iconButton(
        icon: 'delete',
        eventId: 'delete',
        tooltip: 'Delete item',
        data: {'id': 1},
      );
      expect(icon.props['icon'], 'delete');
      expect(icon.props['tooltip'], 'Delete item');
      expect(icon.props['data'], {'id': 1});
    });
  });
}
