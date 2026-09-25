/// Unit tests for the form validators.
library;

import 'package:dart_not_native/forms/validators.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches a validator result that passed.
final Matcher isValid = isA<ValidationResult>()
    .having((r) => r.isValid, 'isValid', isTrue)
    .having((r) => r.errorMessage, 'errorMessage', isNull);

/// Matches a failed result whose message contains [message].
Matcher isInvalid([String? message]) => isA<ValidationResult>()
    .having((r) => r.isValid, 'isValid', isFalse)
    .having(
      (r) => r.errorMessage,
      'errorMessage',
      message == null ? isNotNull : contains(message),
    );

void main() {
  group('RequiredValidator', () {
    final validator = RequiredValidator();

    test('accepts any non-blank value', () async {
      expect(await validator.validate('a'), isValid);
    });

    test('rejects empty and whitespace-only values', () async {
      expect(await validator.validate(''), isInvalid('required'));
      expect(await validator.validate('   '), isInvalid('required'));
    });

    test('uses a custom message', () async {
      final result = await RequiredValidator('Name needed').validate('');
      expect(result.errorMessage, 'Name needed');
    });
  });

  group('EmailValidator', () {
    final validator = EmailValidator();

    test('accepts ordinary addresses', () async {
      for (final email in [
        'user@example.com',
        'first.last+tag@sub.domain.co.uk',
        'a_b-c%d@example.org',
      ]) {
        expect(await validator.validate(email), isValid, reason: email);
      }
    });

    test('rejects malformed addresses', () async {
      for (final email in [
        'invalid-email',
        'no-at.example.com',
        'user@',
        'user@example',
        'user@example.c',
        'user name@example.com',
      ]) {
        expect(await validator.validate(email), isInvalid(), reason: email);
      }
    });

    test('leaves emptiness to RequiredValidator', () async {
      expect(await validator.validate(''), isValid);
    });
  });

  group('MinLengthValidator / MaxLengthValidator', () {
    test('bounds are inclusive', () async {
      expect(await MinLengthValidator(3).validate('abc'), isValid);
      expect(await MinLengthValidator(3).validate('ab'), isInvalid('3'));

      expect(await MaxLengthValidator(3).validate('abc'), isValid);
      expect(await MaxLengthValidator(3).validate('abcd'), isInvalid('3'));
    });

    test('the default message names the bound', () async {
      final result = await MinLengthValidator(8).validate('x');
      expect(result.errorMessage, 'Must be at least 8 characters');
    });
  });

  group('PasswordValidator', () {
    test(
      'default policy wants length, an uppercase letter and a digit',
      () async {
        final validator = PasswordValidator();

        expect(await validator.validate('SecurePass123'), isValid);
        expect(await validator.validate('Short1'), isInvalid());
        expect(await validator.validate('nouppercase123'), isInvalid());
        expect(await validator.validate('NoDigitsHere'), isInvalid());
      },
    );

    test('special characters are opt-in', () async {
      final lax = PasswordValidator();
      final strict = PasswordValidator(requireSpecialChars: true);

      expect(await lax.validate('SecurePass123'), isValid);
      expect(await strict.validate('SecurePass123'), isInvalid());
      expect(await strict.validate('SecurePass123!'), isValid);
    });

    test('a relaxed policy accepts a simple password', () async {
      final validator = PasswordValidator(
        minLength: 4,
        requireUppercase: false,
        requireNumbers: false,
      );

      expect(await validator.validate('plain'), isValid);
    });

    test('the default message lists the active requirements', () async {
      final result = await PasswordValidator(
        minLength: 10,
        requireSpecialChars: true,
      ).validate('x');

      expect(
        result.errorMessage,
        'Password must contain at least 10 characters, an uppercase letter, '
        'a number, a special character',
      );
    });
  });

  group('PhoneValidator', () {
    final validator = PhoneValidator();

    test('accepts numbers with common separators', () async {
      for (final phone in ['+1234567890', '123456789', '(555) 123-4567']) {
        expect(await validator.validate(phone), isValid, reason: phone);
      }
    });

    test('rejects too short and too long numbers', () async {
      expect(await validator.validate('123'), isInvalid('phone'));
      // The pattern allows an optional leading country 1 plus up to 15 digits.
      expect(await validator.validate('12345678901234567'), isInvalid('phone'));
    });

    test('leaves emptiness to RequiredValidator', () async {
      expect(await validator.validate(''), isValid);
    });
  });

  group('UrlValidator', () {
    final validator = UrlValidator();

    test('accepts http(s) urls with paths and queries', () async {
      for (final url in [
        'https://example.com',
        'http://www.example.com/path?q=1',
        'https://example.co.uk/a/b#frag',
      ]) {
        expect(await validator.validate(url), isValid, reason: url);
      }
    });

    test('rejects urls without a scheme or host', () async {
      for (final url in ['example.com', 'ftp://example.com', 'https://']) {
        expect(await validator.validate(url), isInvalid('URL'), reason: url);
      }
    });
  });

  group('PatternValidator', () {
    final validator = PatternValidator(RegExp(r'^[A-Z]{3}$'), 'Three capitals');

    test('accepts matching values and rejects the rest', () async {
      expect(await validator.validate('ABC'), isValid);
      expect(await validator.validate('abc'), isInvalid('Three capitals'));
    });
  });

  group('MatchValidator', () {
    test('compares against the current value of another field', () async {
      var other = 'secret';
      final validator = MatchValidator(() => other);

      expect(await validator.validate('secret'), isValid);
      expect(await validator.validate('typo'), isInvalid('do not match'));

      other = 'typo';
      expect(await validator.validate('typo'), isValid);
    });
  });

  group('RangeValidator', () {
    final validator = RangeValidator(1, 10);

    test('bounds are inclusive', () async {
      expect(await validator.validate('1'), isValid);
      expect(await validator.validate('10'), isValid);
      expect(await validator.validate('5.5'), isValid);
    });

    test('rejects values outside the range', () async {
      expect(await validator.validate('0'), isInvalid('between 1 and 10'));
      expect(await validator.validate('11'), isInvalid('between 1 and 10'));
    });

    test('rejects non-numbers with a dedicated message', () async {
      expect(await validator.validate('abc'), isInvalid('valid number'));
    });
  });

  group('UniqueValidator', () {
    test('asks the callback and reports a taken value', () async {
      final taken = {'admin'};
      final validator = UniqueValidator(
        (value) async => !taken.contains(value),
      );

      expect(await validator.validate('newuser'), isValid);
      expect(await validator.validate('admin'), isInvalid('already taken'));
    });

    test('a failing lookup becomes a validation error, not a crash', () async {
      final validator = UniqueValidator(
        (_) async => throw StateError('backend down'),
      );

      expect(await validator.validate('x'), isInvalid('Validation error'));
    });
  });

  group('CustomValidator', () {
    test('delegates to the supplied function and keeps its name', () async {
      final validator = CustomValidator(
        (value) async => value == 'ok'
            ? ValidationResult.valid()
            : ValidationResult.invalid('nope'),
        validatorName: 'only_ok',
      );

      expect(validator.name, 'only_ok');
      expect(await validator.validate('ok'), isValid);
      expect(await validator.validate('other'), isInvalid('nope'));
    });
  });

  test('every validator reports a stable name', () {
    final names = <Validator>[
      RequiredValidator(),
      EmailValidator(),
      MinLengthValidator(1),
      MaxLengthValidator(1),
      PasswordValidator(),
      PhoneValidator(),
      UrlValidator(),
      PatternValidator(RegExp('.')),
      MatchValidator(() => ''),
      RangeValidator(0, 1),
      UniqueValidator((_) async => true),
    ].map((v) => v.name).toList();

    expect(names, [
      'required',
      'email',
      'minLength',
      'maxLength',
      'password',
      'phone',
      'url',
      'pattern',
      'match',
      'range',
      'unique',
    ]);
  });
}
