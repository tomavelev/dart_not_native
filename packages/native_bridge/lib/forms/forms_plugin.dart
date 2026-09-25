/// Forms Plugin
///
/// Complete form validation, binding, and state management.

library;

import 'package:dart_not_native/plugins/plugin.dart';
import 'validators.dart';
import 'form.dart';

export 'validators.dart';
export 'form.dart';

/// Forms plugin providing validation and form management
class FormsPlugin extends BasePlugin {
  @override
  String get name => 'forms';

  @override
  String get version => '1.0.0';

  @override
  String get description =>
      'Complete form validation, binding, and state management system';

  @override
  List<String> get providedServices => ['forms'];

  @override
  Future<void> onInitialize(PluginContext context) async {
    try {
      // Register form factory
      context.registerService<FormFactory>('forms', FormFactory());

      print('✓ FormsPlugin initialized');
      print('  • Field validators: 12 built-in');
      print('  • Form state management: Ready');
      print('  • Auto-save: Enabled');
      print('  • Undo/Redo: Ready');
    } catch (e) {
      print('✗ FormsPlugin initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> onDispose() async {
    print('✓ FormsPlugin disposed');
  }
}

/// Form factory for creating forms
class FormFactory {
  /// Create a new form
  Form createForm() => Form();

  /// Create form builder
  FormBuilder createBuilder() => FormBuilder();

  /// Create individual field
  FormField createField({
    required String name,
    String? label,
    String? hint,
    List<Validator> validators = const [],
    bool required = false,
    String? initialValue,
  }) {
    return FormField(
      name: name,
      label: label,
      hint: hint,
      validators: validators,
      required: required,
      initialValue: initialValue,
    );
  }
}

/// Pre-built form templates
class FormTemplates {
  /// Create login form
  static Form createLoginForm() {
    return FormBuilder()
        .addEmailField(name: 'email')
        .addPasswordField(name: 'password')
        .build();
  }

  /// Create signup form
  static Form createSignupForm() {
    final form = FormBuilder()
        .addTextField(
          name: 'firstName',
          label: 'First Name',
          required: true,
          validators: [RequiredValidator()],
        )
        .addTextField(
          name: 'lastName',
          label: 'Last Name',
          required: true,
          validators: [RequiredValidator()],
        )
        .addEmailField(name: 'email', required: true)
        .addPasswordField(name: 'password', required: true)
        .build();

    // The confirmation is checked against the password field, which only
    // exists once the form is built - so the validator is attached here.
    form.addField(
      FormField(
        name: 'confirmPassword',
        label: 'Confirm Password',
        obscured: true,
        required: true,
        validators: [
          RequiredValidator(),
          MatchValidator(
            () => form.getField('password')?.value ?? '',
            'Passwords do not match',
          ),
        ],
      ),
    );
    return form;
  }

  /// Create contact form
  static Form createContactForm() {
    return FormBuilder()
        .addTextField(
          name: 'name',
          label: 'Your Name',
          required: true,
          validators: [RequiredValidator(), MinLengthValidator(2)],
        )
        .addEmailField(name: 'email', required: true)
        .addPhoneField(name: 'phone')
        .addField(
          FormField(
            name: 'message',
            label: 'Message',
            required: true,
            maxLength: 1000,
            validators: [
              RequiredValidator(),
              MinLengthValidator(10),
              MaxLengthValidator(1000),
            ],
          ),
        )
        .build();
  }

  /// Create profile form
  static Form createProfileForm() {
    return FormBuilder()
        .addTextField(
          name: 'username',
          label: 'Username',
          required: true,
          validators: [
            RequiredValidator(),
            MinLengthValidator(3),
            MaxLengthValidator(20),
            PatternValidator(
              RegExp(r'^[a-zA-Z0-9_-]+$'),
              'Username can only contain letters, numbers, dash and underscore',
            ),
          ],
        )
        .addTextField(
          name: 'bio',
          label: 'Bio',
          validators: [MaxLengthValidator(500)],
        )
        .addPhoneField(name: 'phone')
        .addTextField(
          name: 'website',
          label: 'Website',
          validators: [UrlValidator()],
        )
        .build();
  }
}

/// Extension for easier field access
extension FormAccess on Form {
  /// Get field or throw
  FormField field(String name) {
    final f = getField(name);
    if (f == null) throw ArgumentError('Field not found: $name');
    return f;
  }

  /// Set value easily
  void setValue(String fieldName, String value) {
    getField(fieldName)?.setValue(value);
  }

  /// Get value easily
  String? getValue(String fieldName) {
    return getField(fieldName)?.value;
  }

  /// Get error easily
  String? getError(String fieldName) {
    return getField(fieldName)?.errorMessage;
  }

  /// Mark field as touched
  void touchField(String fieldName) {
    getField(fieldName)?.markTouched();
  }

  /// Mark field as focused
  void focusField(String fieldName) {
    getField(fieldName)?.markFocused();
  }

  /// Mark field as blurred
  void blurField(String fieldName) {
    getField(fieldName)?.markBlurred();
  }

  /// Validate specific field
  Future<bool> validateField(String fieldName) async {
    return await getField(fieldName)?.validate() ?? false;
  }
}
