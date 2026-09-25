/// TextFormField wires a FormField to a text field: value in, error out.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

// The app's form, captured so the test can read the field it drives.
Form? capturedForm;

class _FormApp extends StatefulWidget {
  const _FormApp();

  @override
  State<_FormApp> createState() => _FormAppState();
}

class _FormAppState extends State<_FormApp> {
  late final Form form = (FormBuilder()..addEmailField(name: 'email')).build();

  @override
  void initState() {
    capturedForm = form;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [TextFormField(field: form.getField('email')!)],
        ),
      );
}

/// Lets an async validate() and its rebuild settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('TextFormField', () {
    setUp(() => capturedForm = null);

    test('renders the field label and hint from the FormField', () {
      final tester = AppTester.mount(hostApp(const _FormApp()));
      final field = tester.get('field_email');
      expect(field.type, 'TextField');
      expect(field.props['label'], 'Email');
    });

    test('reports typing back to the form', () async {
      final tester = AppTester.mount(hostApp(const _FormApp()));
      await tester.typeInto('field_email', 'a@b.co');
      expect(capturedForm!.getField('email')!.value, 'a@b.co');
    });

    test('validates on submit: shows the error, then clears it', () async {
      final tester = AppTester.mount(hostApp(const _FormApp()));

      await tester.typeInto('field_email', 'not-an-email');
      await tester.submitInto('field_email', 'not-an-email');
      await flush();
      expect(tester.get('field_email').props['error'], isNotNull);

      await tester.typeInto('field_email', 'ada@example.com');
      await tester.submitInto('field_email', 'ada@example.com');
      await flush();
      expect(tester.get('field_email').props.containsKey('error'), isFalse);
    });
  });
}
