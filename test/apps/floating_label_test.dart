/// Where a field's label sits, as the Flutter-shaped facade says it.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Fields extends StatelessWidget {
  const _Fields();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            const TextField(
              key: ValueKey('auto'),
              decoration: InputDecoration(labelText: 'Full Name'),
            ),
            const TextField(
              key: ValueKey('never'),
              decoration: InputDecoration(
                labelText: 'Full Name',
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
            ),
            const TextField(
              key: ValueKey('unlabelled'),
              decoration: InputDecoration(hintText: 'Add a todo'),
            ),
          ],
        ),
      );
}

void main() {
  test('a labelled field floats by default, as Flutter does', () {
    final tester = AppTester.mount(hostApp(const _Fields()));

    // Absent means floating: only the opt-out travels in the tree.
    expect(tester.get('auto').props.containsKey('floatingLabel'), isFalse);
    expect(tester.get('auto').props['label'], 'Full Name');
  });

  test('FloatingLabelBehavior.never pins the label above the field', () {
    final tester = AppTester.mount(hostApp(const _Fields()));

    expect(tester.get('never').props['floatingLabel'], isFalse);
  });

  test('a field with only a hint says nothing about floating', () {
    final tester = AppTester.mount(hostApp(const _Fields()));

    expect(
      tester.get('unlabelled').props.containsKey('floatingLabel'),
      isFalse,
    );
  });
}
