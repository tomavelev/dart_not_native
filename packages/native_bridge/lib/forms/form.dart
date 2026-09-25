/// Form Management System
///
/// Form fields, state management, validation, and binding.

library;

import 'dart:async';
import 'validators.dart';

/// Form field state
enum FieldState {
  pristine, // Untouched
  touched, // User has interacted
  dirty, // Value has changed
  focused, // Currently focused
  validating, // Validation in progress
  valid, // Validation passed
  invalid, // Validation failed
}

/// Form field change event
class FieldChange {
  final String fieldName;
  final String oldValue;
  final String newValue;
  final DateTime timestamp;

  FieldChange({
    required this.fieldName,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
  });
}

/// Form field definition and state
class FormField {
  final String name;
  final String? label;
  final String? hint;
  final List<Validator> validators;
  final bool required;
  final bool obscured;
  final int maxLength;
  final String? initialValue;
  final Duration autoSaveDuration;

  late String _value;
  late FieldState _state;
  late String? _errorMessage;
  late StreamController<FieldChange> _changeController;
  late StreamController<String> _errorController;
  Timer? _autoSaveTimer;
  Function(String)? _onAutoSave;

  FormField({
    required this.name,
    this.label,
    this.hint,
    this.validators = const [],
    this.required = false,
    this.obscured = false,
    this.maxLength = 255,
    this.initialValue,
    this.autoSaveDuration = const Duration(milliseconds: 500),
  }) {
    _value = initialValue ?? '';
    _state = FieldState.pristine;
    _errorMessage = null;
    _changeController = StreamController<FieldChange>.broadcast();
    _errorController = StreamController<String>.broadcast();
    _autoSaveTimer = null;
  }

  // Getters
  String get value => _value;
  FieldState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isValid => _state == FieldState.valid;
  bool get isDirty => _state == FieldState.dirty;
  bool get isTouched => _state == FieldState.touched;
  bool get isValidating => _state == FieldState.validating;

  Stream<FieldChange> get onChange => _changeController.stream;
  Stream<String> get onError => _errorController.stream;

  /// Set field value (doesn't trigger validation)
  void setValue(String newValue) {
    if (newValue.length > maxLength) {
      throw ArgumentError('Value exceeds max length of $maxLength');
    }

    final oldValue = _value;
    _value = newValue;

    if (_state != FieldState.pristine) {
      _state = FieldState.dirty;
      _changeController.add(
        FieldChange(
          fieldName: name,
          oldValue: oldValue,
          newValue: newValue,
          timestamp: DateTime.now(),
        ),
      );
    }

    // Schedule auto-save
    _autoSaveTimer?.cancel();
    if (_onAutoSave != null) {
      _autoSaveTimer = Timer(autoSaveDuration, () {
        _onAutoSave!(_value);
      });
    }
  }

  /// Mark field as touched
  void markTouched() {
    if (_state == FieldState.pristine) {
      _state = FieldState.touched;
    }
  }

  /// Mark field as focused
  void markFocused() {
    _state = FieldState.focused;
  }

  /// Mark field as blurred
  void markBlurred() {
    if (_state == FieldState.focused) {
      _state = FieldState.touched;
    }
  }

  /// Validate field
  Future<bool> validate() async {
    if (validators.isEmpty && !required) {
      _state = FieldState.valid;
      _errorMessage = null;
      return true;
    }

    _state = FieldState.validating;

    // Check required first
    if (required && _value.trim().isEmpty) {
      _state = FieldState.invalid;
      _errorMessage = 'This field is required';
      _errorController.add(_errorMessage!);
      return false;
    }

    // Run all validators
    for (final validator in validators) {
      final result = await validator.validate(_value);
      if (!result.isValid) {
        _state = FieldState.invalid;
        _errorMessage = result.errorMessage;
        _errorController.add(_errorMessage!);
        return false;
      }
    }

    _state = FieldState.valid;
    _errorMessage = null;
    return true;
  }

  /// Set auto-save callback
  void setAutoSave(Function(String) callback) {
    _onAutoSave = callback;
  }

  /// Reset field to initial value
  void reset() {
    _value = initialValue ?? '';
    _state = FieldState.pristine;
    _errorMessage = null;
    _autoSaveTimer?.cancel();
  }

  /// Dispose field resources
  void dispose() {
    _autoSaveTimer?.cancel();
    _changeController.close();
    _errorController.close();
  }
}

/// Form state and management
class Form {
  final Map<String, FormField> _fields = {};
  final List<FieldChange> _history = [];
  int _historyIndex = -1;

  /// True while [_applyHistoryState] is replaying a change, so the field's
  /// resulting onChange is not recorded as a fresh edit.
  bool _replaying = false;
  late StreamController<Map<String, String>> _changesController;

  Form() {
    _changesController = StreamController<Map<String, String>>.broadcast();
  }

  /// Add field to form
  void addField(FormField field) {
    _fields[field.name] = field;
    field.onChange.listen((change) {
      // undo/redo replays a change through setValue, which fires onChange
      // again; recording that would append a new entry and reset the cursor to
      // the end, so undo/redo would work only once. The replay's own event
      // clears the flag (onChange is delivered on a later microtask).
      if (_replaying) {
        _replaying = false;
      } else {
        _history.add(change);
        _historyIndex = _history.length - 1;
      }
      _notifyChanges();
    });
  }

  /// Get field by name
  FormField? getField(String name) => _fields[name];

  /// Get all field values
  Map<String, String> get values {
    return _fields.map((name, field) => MapEntry(name, field.value));
  }

  /// Get all field errors
  Map<String, String?> getErrors() {
    return _fields.map((name, field) => MapEntry(name, field.errorMessage));
  }

  /// Check if form is valid
  bool get isValid => _fields.values.every((f) => f.isValid);

  /// Check if form is dirty
  bool get isDirty => _fields.values.any((f) => f.isDirty);

  /// Check if form is validating
  bool get isValidating => _fields.values.any((f) => f.isValidating);

  /// Validate entire form
  Future<bool> validate() async {
    final results = await Future.wait(
      _fields.values.map((field) => field.validate()),
    );
    return results.every((r) => r);
  }

  /// The first field that is currently reporting an error, in the order the
  /// fields were added - which is the order they are on screen, and so the one
  /// an app would point someone at.
  FormField? get firstInvalid {
    for (final field in _fields.values) {
      if (field.errorMessage != null) return field;
    }
    return null;
  }

  /// Validates every field and, when they all pass, hands [onValid] the
  /// values; answers whether it got that far.
  ///
  /// This is the shape a submit button wants: one call that checks the whole
  /// form, shows every error at once rather than the first, and does the work
  /// only if there is nothing to show. A false answer leaves the messages in
  /// place - [firstInvalid] says where to look.
  ///
  /// ```dart
  /// onPressed: () async {
  ///   if (await form.submit((values) => api.signUp(values))) {
  ///     // sent
  ///   }
  /// }
  /// ```
  Future<bool> submit(
    FutureOr<void> Function(Map<String, String> values) onValid,
  ) async {
    if (!await validate()) return false;
    await onValid(values);
    return true;
  }

  /// Reset form to initial values
  void reset() {
    for (final field in _fields.values) {
      field.reset();
    }
    _history.clear();
    _historyIndex = -1;
  }

  /// Set auto-save for field
  void setAutoSave(String fieldName, Function(String) callback) {
    _fields[fieldName]?.setAutoSave(callback);
  }

  /// Undo last change
  bool undo() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _applyHistoryState();
      return true;
    }
    return false;
  }

  /// Redo last undo
  bool redo() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _applyHistoryState();
      return true;
    }
    return false;
  }

  /// Check if can undo
  bool get canUndo => _historyIndex > 0;

  /// Check if can redo
  bool get canRedo => _historyIndex < _history.length - 1;

  /// Apply history state
  void _applyHistoryState() {
    if (_historyIndex < 0 || _historyIndex >= _history.length) return;

    final change = _history[_historyIndex];
    _replaying = true;
    _fields[change.fieldName]?.setValue(change.newValue);
  }

  /// Notify listeners of changes
  void _notifyChanges() {
    // A field's onChange is delivered on a later microtask, so one can still
    // arrive after the form is disposed (e.g. an undo/redo replay); don't push
    // into a closed controller.
    if (_changesController.isClosed) return;
    _changesController.add(values);
  }

  /// Listen to form changes
  Stream<Map<String, String>> get onChange => _changesController.stream;

  /// Dispose form
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _changesController.close();
  }
}

/// Form builder for fluent API
class FormBuilder {
  final Form _form = Form();
  final List<FormField> _fields = [];

  /// Add field
  FormBuilder addField(FormField field) {
    _fields.add(field);
    _form.addField(field);
    return this;
  }

  /// Add text field
  FormBuilder addTextField({
    required String name,
    String? label,
    String? hint,
    List<Validator> validators = const [],
    bool required = false,
    String? initialValue,
  }) {
    final field = FormField(
      name: name,
      label: label,
      hint: hint,
      validators: validators,
      required: required,
      initialValue: initialValue,
    );
    return addField(field);
  }

  /// Add email field
  FormBuilder addEmailField({
    required String name,
    String? label,
    bool required = true,
  }) {
    final field = FormField(
      name: name,
      label: label ?? 'Email',
      validators: [EmailValidator()],
      required: required,
    );
    return addField(field);
  }

  /// Add password field
  FormBuilder addPasswordField({
    required String name,
    String? label,
    bool required = true,
  }) {
    final field = FormField(
      name: name,
      label: label ?? 'Password',
      obscured: true,
      validators: [PasswordValidator()],
      required: required,
    );
    return addField(field);
  }

  /// Add phone field
  FormBuilder addPhoneField({
    required String name,
    String? label,
    bool required = false,
  }) {
    final field = FormField(
      name: name,
      label: label ?? 'Phone',
      validators: [PhoneValidator()],
      required: required,
    );
    return addField(field);
  }

  /// Build form
  Form build() => _form;
}
