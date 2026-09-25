/// The sign-up screen: four fields that depend on each other, one submit.
///
/// What this pins down is the behaviour a form has to get right - an error
/// that appears when the button is pressed, goes when the value is fixed
/// *while typing*, and a submit that only runs once nothing is left to show.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:dart_not_native_example/examples/apps/signup_form_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

/// Lets an async validate() and the rebuild it causes settle.
Future<void> flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const SignupFormApp())));

  WidgetNode field(String name) => tester.get('field_$name');
  Object? errorOf(String name) => field(name).props['error'];

  Future<void> fillValid() async {
    await tester.typeInto('field_name', 'Ada Lovelace');
    await tester.typeInto('field_email', 'ada@example.com');
    await tester.typeInto('field_password', 'Passw0rdy');
    await tester.typeInto('field_confirm', 'Passw0rdy');
  }

  test('shows the fields the form declares, in order', () {
    expect(field('name').props['label'], 'Full name');
    expect(field('email').props['label'], 'Email');
    expect(field('password').props['obscureText'], isTrue);
    expect(field('confirm').props['label'], 'Confirm password');
  });

  test('a submit with nothing filled in shows every error at once', () async {
    await tester.tap('submit');
    await flush();

    expect(errorOf('name'), isNotNull);
    expect(errorOf('email'), isNotNull);
    expect(errorOf('password'), isNotNull);
    // And it says where to start, rather than only that something is wrong.
    expect(tester.get('form_message').props['content'], contains('Full name'));
  });

  test('a failed submit puts the caret in the field that needs it', () async {
    await tester.tap('submit');
    await flush();

    expect(field('name').props['focusVersion'], isNotNull);
    // Only that one - the others are wrong too, but the caret goes to the
    // first thing to fix.
    expect(field('email').props.containsKey('focusVersion'), isFalse);
  });

  test('a second failed submit is a second ask, not the same one', () async {
    await tester.tap('submit');
    await flush();
    final first = field('name').props['focusVersion'];

    await tester.tap('submit');
    await flush();

    expect(field('name').props['focusVersion'], greaterThan(first! as int));
  });

  test('a form that submits leaves the caret alone', () async {
    await fillValid();
    await tester.tap('submit');
    await flush();

    expect(
      tester.nodes.any((n) => n.props.containsKey('focusVersion')),
      isFalse,
    );
  });

  test('an error goes as the value is fixed, not at the next submit', () async {
    await tester.tap('submit');
    await flush();
    expect(errorOf('email'), isNotNull);

    // No submit, no blur - just typing.
    await tester.typeInto('field_email', 'ada@example.com');
    await flush();

    expect(field('email').props.containsKey('error'), isFalse);
    // The fields that are still empty keep theirs.
    expect(errorOf('name'), isNotNull);
  });

  test(
    'a field that has never failed is not validated as it is typed',
    () async {
      // Half an email is not an error until something asks.
      await tester.typeInto('field_email', 'ada@');
      await flush();

      expect(field('email').props.containsKey('error'), isFalse);
    },
  );

  test('the confirmation is checked against the password beside it', () async {
    await fillValid();
    await tester.typeInto('field_confirm', 'something else');
    await tester.tap('submit');
    await flush();

    expect(errorOf('confirm'), 'Passwords do not match');

    await tester.typeInto('field_confirm', 'Passw0rdy');
    await flush();

    expect(field('confirm').props.containsKey('error'), isFalse);
  });

  test('a valid submit runs the work and shows what it did', () async {
    await fillValid();
    await tester.tap('submit');
    await flush();

    expect(tester.get('signed_up').props['content'], 'Welcome aboard');
    expect(
      tester.nodes.any(
        (n) =>
            n.props['content'] == 'We sent a confirmation to ada@example.com.',
      ),
      isTrue,
    );
  });

  test('starting over brings the empty form back', () async {
    await fillValid();
    await tester.tap('submit');
    await flush();

    await tester.tap('start_over');
    await flush();

    expect(field('name').props['value'], anyOf(isNull, ''));
    expect(
      tester.nodes.any((n) => n.props['content'] == 'Welcome aboard'),
      isFalse,
    );
  });
}
