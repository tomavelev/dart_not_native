/// Form Validators
///
/// Reusable validation rules for form fields.

library;

/// Validation result
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  ValidationResult({required this.isValid, this.errorMessage});

  factory ValidationResult.valid() => ValidationResult(isValid: true);

  factory ValidationResult.invalid(String message) =>
      ValidationResult(isValid: false, errorMessage: message);
}

/// Base validator interface
abstract class Validator {
  String get name;
  Future<ValidationResult> validate(String value);
}

/// Required field validator
class RequiredValidator implements Validator {
  final String errorMessage;

  @override
  String get name => 'required';

  RequiredValidator([this.errorMessage = 'This field is required']);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.trim().isEmpty) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Email validator
class EmailValidator implements Validator {
  final String errorMessage;
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  @override
  String get name => 'email';

  EmailValidator([this.errorMessage = 'Invalid email address'])
    : assert(errorMessage.isNotEmpty);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    if (!_emailRegex.hasMatch(value)) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Minimum length validator
class MinLengthValidator implements Validator {
  final int minLength;
  final String errorMessage;

  @override
  String get name => 'minLength';

  MinLengthValidator(this.minLength, [String? errorMessage])
    : errorMessage = errorMessage ?? 'Must be at least $minLength characters';

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.length < minLength) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Maximum length validator
class MaxLengthValidator implements Validator {
  final int maxLength;
  final String errorMessage;

  @override
  String get name => 'maxLength';

  MaxLengthValidator(this.maxLength, [String? errorMessage])
    : errorMessage =
          errorMessage ?? 'Must be no more than $maxLength characters';

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.length > maxLength) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Password strength validator
class PasswordValidator implements Validator {
  final int minLength;
  final bool requireUppercase;
  final bool requireNumbers;
  final bool requireSpecialChars;
  final String errorMessage;

  @override
  String get name => 'password';

  PasswordValidator({
    this.minLength = 8,
    this.requireUppercase = true,
    this.requireNumbers = true,
    this.requireSpecialChars = false,
    String? errorMessage,
  }) : errorMessage =
           errorMessage ??
           _defaultMessage(
             minLength,
             requireUppercase,
             requireNumbers,
             requireSpecialChars,
           );

  static String _defaultMessage(
    int minLength,
    bool upper,
    bool numbers,
    bool special,
  ) {
    final requirements = <String>[];
    requirements.add('at least $minLength characters');
    if (upper) requirements.add('an uppercase letter');
    if (numbers) requirements.add('a number');
    if (special) requirements.add('a special character');
    return 'Password must contain ${requirements.join(", ")}';
  }

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.length < minLength) {
      return ValidationResult.invalid(errorMessage);
    }

    if (requireUppercase && !value.contains(RegExp(r'[A-Z]'))) {
      return ValidationResult.invalid(errorMessage);
    }

    if (requireNumbers && !value.contains(RegExp(r'[0-9]'))) {
      return ValidationResult.invalid(errorMessage);
    }

    if (requireSpecialChars &&
        !value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return ValidationResult.invalid(errorMessage);
    }

    return ValidationResult.valid();
  }
}

/// Phone number validator
class PhoneValidator implements Validator {
  final String errorMessage;
  static final RegExp _phoneRegex = RegExp(r'^\+?1?\d{9,15}$');

  @override
  String get name => 'phone';

  PhoneValidator([this.errorMessage = 'Invalid phone number']);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    final cleaned = value.replaceAll(RegExp(r'[^\d+]'), '');
    if (!_phoneRegex.hasMatch(cleaned)) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// URL validator
class UrlValidator implements Validator {
  final String errorMessage;
  static final RegExp _urlRegex = RegExp(
    r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&/=]*)$',
  );

  @override
  String get name => 'url';

  UrlValidator([this.errorMessage = 'Invalid URL']);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    if (!_urlRegex.hasMatch(value)) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Pattern (regex) validator
class PatternValidator implements Validator {
  final RegExp pattern;
  final String errorMessage;

  @override
  String get name => 'pattern';

  PatternValidator(this.pattern, [this.errorMessage = 'Invalid format']);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    if (!pattern.hasMatch(value)) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Match validator (field equality)
class MatchValidator implements Validator {
  final String Function() getOtherValue;
  final String errorMessage;

  @override
  String get name => 'match';

  MatchValidator(
    this.getOtherValue, [
    this.errorMessage = 'Values do not match',
  ]);

  @override
  Future<ValidationResult> validate(String value) async {
    final other = getOtherValue();
    if (value != other) {
      return ValidationResult.invalid(errorMessage);
    }
    return ValidationResult.valid();
  }
}

/// Custom validator (function-based)
class CustomValidator implements Validator {
  final Future<ValidationResult> Function(String) validationFn;
  final String validatorName;

  @override
  String get name => validatorName;

  CustomValidator(this.validationFn, {this.validatorName = 'custom'});

  @override
  Future<ValidationResult> validate(String value) => validationFn(value);
}

/// Range validator (numeric)
class RangeValidator implements Validator {
  final num min;
  final num max;
  final String errorMessage;

  @override
  String get name => 'range';

  RangeValidator(this.min, this.max, [String? errorMessage])
    : errorMessage = errorMessage ?? 'Must be between $min and $max';

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    try {
      final num = double.parse(value);
      if (num < min || num > max) {
        return ValidationResult.invalid(errorMessage);
      }
    } catch (e) {
      return ValidationResult.invalid('Must be a valid number');
    }

    return ValidationResult.valid();
  }
}

/// Unique validator (checks if value is unique via callback)
class UniqueValidator implements Validator {
  final Future<bool> Function(String) checkUniqueFn;
  final String errorMessage;

  @override
  String get name => 'unique';

  UniqueValidator(
    this.checkUniqueFn, [
    this.errorMessage = 'This value is already taken',
  ]);

  @override
  Future<ValidationResult> validate(String value) async {
    if (value.isEmpty) return ValidationResult.valid();

    try {
      final isUnique = await checkUniqueFn(value);
      if (!isUnique) {
        return ValidationResult.invalid(errorMessage);
      }
    } catch (e) {
      return ValidationResult.invalid('Validation error: $e');
    }

    return ValidationResult.valid();
  }
}
