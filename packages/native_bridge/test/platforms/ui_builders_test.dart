/// Unit tests for the platform-flavoured builders.
///
/// Android and iOS builders emit platform-idiomatic node types, but every
/// renderer - including the web DOM one - has to understand them, so these
/// tests pin the node types and prop names that make up that contract.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tree.dart';

void main() {
  group('AndroidUIBuilder', () {
    test('scaffold matches the neutral one', () {
      final node = AndroidUIBuilder.scaffold(
        appBar: AndroidUIBuilder.appBar(title: 'Demo'),
        body: UIBuilder.text('body'),
      );

      expect(node.type, 'Scaffold');
      expect(node.children!.map((c) => c.type), ['AppBar', 'Text']);
    });

    test('app bar can be tinted', () {
      expect(AndroidUIBuilder.appBar(title: 'Demo').props, {'title': 'Demo'});
      expect(
        AndroidUIBuilder.appBar(title: 'Demo', backgroundColor: '#000').props,
        {'title': 'Demo', 'backgroundColor': '#000'},
      );
    });

    test('material button is a Button flavour the renderers accept', () {
      final node = AndroidUIBuilder.materialButton(
        label: 'Tap',
        eventId: 'tap',
        color: '#1976d2',
      );

      expect(node.type, 'MaterialButton');
      expect(node.props, {
        'label': 'Tap',
        'eventId': 'tap',
        'color': '#1976d2',
      });
    });

    test('list view holds list items with optional subtitles', () {
      final node = AndroidUIBuilder.listView(
        children: [
          AndroidUIBuilder.listItem(text: 'One'),
          AndroidUIBuilder.listItem(text: 'Two', subtitle: 'second'),
        ],
      );

      expect(node.type, 'ListView');
      expect(node.children!.map((c) => c.props['text']), ['One', 'Two']);
      expect(node.children!.first.props.containsKey('subtitle'), isFalse);
      expect(node.children!.last.props['subtitle'], 'second');
    });

    test('text field uses the hint prop', () {
      final node = AndroidUIBuilder.textField(
        hint: 'Name',
        eventId: 'name',
        maxLines: 3,
      );

      expect(node.type, 'TextField');
      expect(node.props['hint'], 'Name');
      expect(node.props['maxLines'], 3);
      expect(node.props['enabled'], isTrue);
    });
  });

  group('iOSUIBuilder', () {
    test('navigation stack wraps its content', () {
      final node = iOSUIBuilder.navigationStack(
        content: iOSUIBuilder.vStack(children: [UIBuilder.text('hi')]),
      );

      expect(node.type, 'NavigationStack');
      expect(node.children!.single.type, 'VStack');
    });

    test('navigation bar defaults to the inline title', () {
      expect(iOSUIBuilder.navigationBar(title: 'Demo').props, {
        'title': 'Demo',
        'inline': true,
      });
      expect(
        iOSUIBuilder
            .navigationBar(title: 'Demo', inline: false)
            .props['inline'],
        isFalse,
      );
    });

    test('stacks carry alignment and spacing', () {
      final vStack = iOSUIBuilder.vStack(
        children: [UIBuilder.text('a')],
        alignment: 'center',
        spacing: 12,
      );
      expect(vStack.props, {'alignment': 'center', 'spacing': 12.0});

      final hStack = iOSUIBuilder.hStack(children: []);
      expect(hStack.props, {'alignment': 'center', 'spacing': 0.0});
    });

    test('list rows mirror the Android list items', () {
      final node = iOSUIBuilder.list(
        children: [iOSUIBuilder.listRow(text: 'One', subtitle: 'first')],
      );

      expect(node.type, 'List');
      expect(node.children!.single.type, 'ListRow');
      expect(node.children!.single.props, {'text': 'One', 'subtitle': 'first'});
    });

    test('spacer carries a minimum length', () {
      expect(iOSUIBuilder.spacer().props, {'minLength': 0.0});
      expect(iOSUIBuilder.spacer(minLength: 20).props, {'minLength': 20.0});
    });

    test('text field uses the placeholder prop', () {
      final node = iOSUIBuilder.textField(
        placeholder: 'Name',
        eventId: 'name',
        obscureText: true,
      );

      expect(node.type, 'TextField');
      expect(node.props['placeholder'], 'Name');
      expect(node.props['obscureText'], isTrue);
      expect(
        node.props.containsKey('maxLines'),
        isFalse,
        reason: 'iOS text fields are single line unless the host says so',
      );
    });
  });

  group('cross-platform trees', () {
    test('an Android and an iOS screen share the neutral node vocabulary', () {
      final android = AndroidUIBuilder.scaffold(
        appBar: AndroidUIBuilder.appBar(title: 'Counter'),
        body: UIBuilder.center(child: UIBuilder.text('0', id: 'value')),
      );
      final ios = iOSUIBuilder.navigationStack(
        content: iOSUIBuilder.vStack(
          children: [
            iOSUIBuilder.navigationBar(title: 'Counter'),
            UIBuilder.text('0', id: 'value'),
          ],
        ),
      );

      for (final tree in [android, ios]) {
        expect(nodeById(tree, 'value')!.props['content'], '0');
        expect(findNode(tree, (n) => n.props['title'] == 'Counter'), isNotNull);
      }
    });
  });
}
