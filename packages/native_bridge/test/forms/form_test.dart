/// Unit tests for form fields, form state and the fluent builder.
library;

import 'package:dart_not_native/forms/form.dart';
import 'package:dart_not_native/forms/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormField state', () {
    test('starts pristine at its initial value', () {
      final field = FormField(name: 'email', initialValue: 'a@b.co');

      expect(field.value, 'a@b.co');
      expect(field.state, FieldState.pristine);
      expect(field.errorMessage, isNull);
    });

    test('defaults to an empty value', () {
      expect(FormField(name: 'x').value, '');
    });

    test('touch, focus and blur move through the state machine', () {
      final field = FormField(name: 'x');

      field.markTouched();
      expect(field.state, FieldState.touched);

      field.markFocused();
      expect(field.state, FieldState.focused);

      field.markBlurred();
      expect(field.state, FieldState.touched);
    });

    test('a touched field becomes dirty when edited', () {
      final field = FormField(name: 'x')..markTouched();

      field.setValue('hello');

      expect(field.value, 'hello');
      expect(field.isDirty, isTrue);
    });

    test('setValue refuses more than maxLength characters', () {
      final field = FormField(name: 'x', maxLength: 3);

      expect(() => field.setValue('abcd'), throwsArgumentError);
      expect(field.value, '');
    });

    test(
      'edits on a touched field are published on the change stream',
      () async {
        final field = FormField(name: 'x')..markTouched();
        final changes = field.onChange.take(1).toList();

        field.setValue('new');

        final change = (await changes).single;
        expect(change.fieldName, 'x');
        expect(change.oldValue, '');
        expect(change.newValue, 'new');
        field.dispose();
      },
    );

    test('reset restores the initial value and clears the error', () async {
      final field = FormField(name: 'x', initialValue: 'start', required: true)
        ..markTouched();
      field.setValue('');
      await field.validate();
      expect(field.errorMessage, isNotNull);

      field.reset();

      expect(field.value, 'start');
      expect(field.state, FieldState.pristine);
      expect(field.errorMessage, isNull);
    });
  });

  group('FormField.validate', () {
    test('a field with no rules is always valid', () async {
      final field = FormField(name: 'x');

      expect(await field.validate(), isTrue);
      expect(field.state, FieldState.valid);
    });

    test('required rejects a blank value with a standard message', () async {
      final field = FormField(name: 'x', required: true);

      expect(await field.validate(), isFalse);
      expect(field.state, FieldState.invalid);
      expect(field.errorMessage, 'This field is required');
    });

    test('validators run in order and the first failure wins', () async {
      final field = FormField(
        name: 'x',
        validators: [MinLengthValidator(5, 'too short'), EmailValidator()],
      )..setValue('a@b');

      expect(await field.validate(), isFalse);
      expect(field.errorMessage, 'too short');
    });

    test('a passing field clears a previous error', () async {
      final field = FormField(name: 'email', validators: [EmailValidator()])
        ..setValue('nope');
      await field.validate();
      expect(field.isValid, isFalse);

      field.setValue('user@example.com');

      expect(await field.validate(), isTrue);
      expect(field.errorMessage, isNull);
      expect(field.isValid, isTrue);
    });

    test('errors are published on the error stream', () async {
      final field = FormField(name: 'x', required: true);
      final errors = field.onError.take(1).toList();

      await field.validate();

      expect((await errors).single, 'This field is required');
      field.dispose();
    });

    test('async validators are awaited', () async {
      final field = FormField(
        name: 'username',
        validators: [
          UniqueValidator((value) async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            return value != 'taken';
          }),
        ],
      )..setValue('taken');

      expect(await field.validate(), isFalse);
      expect(field.errorMessage, 'This value is already taken');
    });
  });

  group('FormField auto-save', () {
    test('fires once the debounce window elapses', () async {
      final field = FormField(
        name: 'x',
        autoSaveDuration: const Duration(milliseconds: 10),
      );
      final saved = <String>[];
      field.setAutoSave(saved.add);

      field.setValue('a');
      field.setValue('ab');
      expect(saved, isEmpty, reason: 'still within the debounce window');

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(saved, ['ab']);
      field.dispose();
    });

    test('reset cancels a pending save', () async {
      final field = FormField(
        name: 'x',
        autoSaveDuration: const Duration(milliseconds: 10),
      );
      final saved = <String>[];
      field.setAutoSave(saved.add);

      field.setValue('a');
      field.reset();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(saved, isEmpty);
      field.dispose();
    });
  });

  group('Form', () {
    Form loginForm() =>
        (FormBuilder()
              ..addEmailField(name: 'email')
              ..addPasswordField(name: 'password'))
            .build();

    test('collects values and errors by field name', () async {
      final form = loginForm();
      form.getField('email')!.setValue('user@example.com');
      form.getField('password')!.setValue('SecurePass123');

      expect(await form.validate(), isTrue);
      expect(form.values, {
        'email': 'user@example.com',
        'password': 'SecurePass123',
      });
      expect(form.getErrors(), {'email': null, 'password': null});
      expect(form.isValid, isTrue);
      form.dispose();
    });

    test('is invalid when any field fails, and names the offender', () async {
      final form = loginForm();
      form.getField('email')!.setValue('not-an-email');
      form.getField('password')!.setValue('SecurePass123');

      expect(await form.validate(), isFalse);
      expect(form.isValid, isFalse);
      expect(form.getErrors()['email'], 'Invalid email address');
      expect(form.getErrors()['password'], isNull);
      form.dispose();
    });

    test(
      'validate runs every field, not just up to the first failure',
      () async {
        final form = loginForm();

        await form.validate();

        expect(form.getErrors()['email'], 'This field is required');
        expect(form.getErrors()['password'], 'This field is required');
        form.dispose();
      },
    );

    test('getField returns null for an unknown name', () {
      expect(loginForm().getField('nope'), isNull);
    });

    test('is dirty once a touched field changes', () async {
      final form = loginForm();
      expect(form.isDirty, isFalse);

      form.getField('email')!
        ..markTouched()
        ..setValue('a@b.co');

      expect(form.isDirty, isTrue);
      // Let the field's change event reach the form before it closes.
      await Future<void>.delayed(Duration.zero);
      form.dispose();
    });

    test('reset restores every field', () async {
      final form = loginForm();
      form.getField('email')!.setValue('user@example.com');
      await form.validate();

      form.reset();

      expect(form.values, {'email': '', 'password': ''});
      expect(form.getField('email')!.state, FieldState.pristine);
      form.dispose();
    });

    test('changes are published as a snapshot of all values', () async {
      final form = loginForm();
      final email = form.getField('email')!..markTouched();
      final snapshots = form.onChange.take(1).toList();

      email.setValue('a@b.co');

      expect((await snapshots).single, {'email': 'a@b.co', 'password': ''});
      form.dispose();
    });
  });

  group('Form undo/redo', () {
    test(
      'undo steps back to the previous value',
      () async {
        final form = (FormBuilder()..addTextField(name: 'note')).build();
        final note = form.getField('note')!..markTouched();
        note.setValue('a');
        await Future<void>.delayed(Duration.zero);
        note.setValue('ab');
        await Future<void>.delayed(Duration.zero);

        expect(form.canUndo, isTrue);
        expect(form.undo(), isTrue);

        expect(note.value, 'a');
        await Future<void>.delayed(Duration.zero);
        expect(form.redo(), isTrue);
        expect(note.value, 'ab');
        form.dispose();
      },
    );
  });

  group('FormBuilder', () {
    test('builds fields with the right validators and labels', () {
      final form =
          (FormBuilder()
                ..addTextField(
                  name: 'nickname',
                  label: 'Nickname',
                  hint: 'Optional',
                  initialValue: 'anon',
                )
                ..addEmailField(name: 'email')
                ..addPasswordField(name: 'password')
                ..addPhoneField(name: 'phone'))
              .build();

      expect(form.values.keys, ['nickname', 'email', 'password', 'phone']);
      expect(form.getField('nickname')!.value, 'anon');
      expect(form.getField('email')!.label, 'Email');
      expect(form.getField('email')!.required, isTrue);
      expect(form.getField('password')!.obscured, isTrue);
      expect(form.getField('phone')!.required, isFalse);
      expect(form.getField('phone')!.validators.map((v) => v.name), ['phone']);
      form.dispose();
    });
  });

  group('submitting', () {
    Form signupForm() => (FormBuilder()
          ..addTextField(name: 'name', label: 'Full name', required: true)
          ..addEmailField(name: 'email'))
        .build();

    test('a form with something wrong does not run the work', () async {
      final form = signupForm();
      form.getField('email')!.setValue('not-an-email');
      var ran = false;

      final sent = await form.submit((_) => ran = true);

      expect(sent, isFalse);
      expect(ran, isFalse);
      // The messages stay up, which is what the screen is showing.
      expect(form.getErrors()['email'], isNotNull);
      form.dispose();
    });

    test('a form that passes hands over every value', () async {
      final form = signupForm();
      form.getField('name')!.setValue('Ada');
      form.getField('email')!.setValue('ada@example.com');
      Map<String, String>? received;

      final sent = await form.submit((values) => received = values);

      expect(sent, isTrue);
      expect(received, {'name': 'Ada', 'email': 'ada@example.com'});
      form.dispose();
    });

    test('it waits for work that takes a moment', () async {
      final form = signupForm();
      form.getField('name')!.setValue('Ada');
      form.getField('email')!.setValue('ada@example.com');
      var finished = false;

      await form.submit((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        finished = true;
      });

      expect(finished, isTrue);
      form.dispose();
    });

    test('the first invalid field is the first one on screen', () async {
      final form = signupForm();
      form.getField('email')!.setValue('nope');

      await form.validate();

      expect(form.firstInvalid?.name, 'name');
      expect(form.firstInvalid?.label, 'Full name');
      form.dispose();
    });

    test('nothing is invalid until something has been validated', () {
      final form = signupForm();

      expect(form.firstInvalid, isNull);
      form.dispose();
    });
  });
}
