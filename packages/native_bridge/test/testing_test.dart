/// The harness an app's own tests are written against.
///
/// It is public (`package:dart_not_native/testing.dart`), so what it finds,
/// what it sends and how it fails are things other people's suites lean on.
library;

import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Screen extends StatefulWidget {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  int _count = 0;
  bool _agreed = false;
  String _name = '';
  String _sent = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text('$_count', key: const ValueKey('count')),
        ElevatedButton(
          key: const ValueKey('add'),
          onPressed: () => setState(() => _count++),
          child: const Text('Add'),
        ),
        Checkbox(
          key: const ValueKey('agree'),
          value: _agreed,
          onChanged: (value) => setState(() => _agreed = value ?? false),
        ),
        Text(_agreed ? 'agreed' : 'not agreed', key: const ValueKey('state')),
        TextField(
          key: const ValueKey('name'),
          onChanged: (value) => setState(() => _name = value),
          onSubmitted: (value) => setState(() => _sent = value),
        ),
        Text('name: $_name', key: const ValueKey('typed')),
        Text('sent: $_sent', key: const ValueKey('submitted')),
      ],
    ),
  );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.widget(const _Screen()));

  test('widget() mounts what mount(hostApp()) does', () {
    final other = AppTester.mount(hostApp(const _Screen()));

    expect(other.texts, tester.texts);
    expect(tester.tree.type, 'Scaffold');
  });

  test('a key is the id a node is found by', () {
    expect(tester.text('count'), '0');
    expect(tester.get('add').type, 'Button');
    expect(tester.find('nothing'), isNull);
    expect(tester.hasText('not agreed'), isTrue);
    expect(tester.ofType('TextField'), hasLength(1));
  });

  test('a tap reaches the callback, and the tree is current after it',
      () async {
    await tester.tap('add');
    await tester.tap('add');

    expect(tester.text('count'), '2');
  });

  test('toggle sends the opposite of what the box shows', () async {
    await tester.toggle('agree');
    expect(tester.text('state'), 'agreed');

    await tester.toggle('agree');
    expect(tester.text('state'), 'not agreed');
  });

  test('typing and submitting go to the field named by its key', () async {
    await tester.typeInto('name', 'Ada');
    expect(tester.text('typed'), 'name: Ada');

    await tester.submitInto('name', 'Ada');
    expect(tester.text('submitted'), 'sent: Ada');
  });

  test('every event a node carries is listed', () {
    expect(tester.eventIds, contains(tester.eventIdOf('add')));
  });

  test('a node that is not there is an error that names it', () {
    expect(
      () => tester.get('missing'),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('missing')),
      ),
    );
    expect(() => tester.tap('missing'), throwsStateError);
  });

  test('tapping a node with nothing to fire is an error, not a no-op', () {
    expect(() => tester.tap('count'), throwsStateError);
  });

  test('walk visits a node and everything under it', () {
    final types = walk(tester.tree).map((node) => node.type).toSet();

    expect(types, containsAll(['Scaffold', 'Text', 'Button', 'TextField']));
  });
}
