/// Padding that is not the same on every edge.
///
/// `EdgeInsets.symmetric` and `.only` used to collapse to their largest edge -
/// `symmetric(horizontal: 16)` padded the top and bottom by 16 as well, which
/// is not what the app asked for and not what Flutter does. No example used
/// them, which is why it went unnoticed.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _Screen extends StatelessWidget {
  const _Screen(this.padding);

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: padding,
          child: const Text('x', key: ValueKey('body')),
        ),
      );
}

WidgetNode paddingNode(EdgeInsets insets) =>
    AppTester.mount(hostApp(_Screen(insets))).ofType('Padding').single;

void main() {
  test('all four edges the same travel as one number', () {
    expect(paddingNode(const EdgeInsets.all(16)).props, {'padding': 16.0});
  });

  test('symmetric pads the two axes it names, and no others', () {
    expect(
      paddingNode(const EdgeInsets.symmetric(horizontal: 16)).props,
      {
        'paddingLeft': 16.0,
        'paddingTop': 0.0,
        'paddingRight': 16.0,
        'paddingBottom': 0.0,
      },
    );
  });

  test('only pads the edges it names', () {
    expect(
      paddingNode(const EdgeInsets.only(top: 24, left: 8)).props,
      {
        'paddingLeft': 8.0,
        'paddingTop': 24.0,
        'paddingRight': 0.0,
        'paddingBottom': 0.0,
      },
    );
  });

  test('fromLTRB reads in that order', () {
    expect(
      paddingNode(const EdgeInsets.fromLTRB(1, 2, 3, 4)).props,
      {
        'paddingLeft': 1.0,
        'paddingTop': 2.0,
        'paddingRight': 3.0,
        'paddingBottom': 4.0,
      },
    );
  });
}
