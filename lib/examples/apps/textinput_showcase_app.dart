/// TextInput Showcase - written as a plain Flutter app.
///
/// Demonstrates TextField variations and events: floating labels, hint text,
/// error states, disabled fields, focus/blur/submit events, password and
/// multi-line input. Only the import (`widgets.dart`) renders it through the
/// platform's own views instead of the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

/// TextInput Logic - handles validation and state
class TextInputLogic {
  String name = '';
  String email = '';
  String password = '';
  String message = '';

  String? nameError;
  String? emailError;
  String? passwordError;

  bool nameFocused = false;
  bool emailFocused = false;
  bool nameSubmitted = false;

  List<String> logs = [];

  void validateName() {
    if (name.isEmpty) {
      nameError = 'Name is required';
    } else if (name.length < 2) {
      nameError = 'Name must be at least 2 characters';
    } else {
      nameError = null;
    }
  }

  void validateEmail() {
    if (email.isEmpty) {
      emailError = 'Email is required';
    } else if (!_isValidEmail(email)) {
      emailError = 'Please enter a valid email';
    } else {
      emailError = null;
    }
  }

  void validatePassword() {
    if (password.isEmpty) {
      passwordError = 'Password is required';
    } else if (password.length < 8) {
      passwordError = 'Password must be at least 8 characters';
    } else {
      passwordError = null;
    }
  }

  void validateAll() {
    validateName();
    validateEmail();
    validatePassword();
  }

  String getPasswordStrength() {
    if (password.isEmpty) return 'Empty';
    if (password.length < 8) return 'Weak';
    if (password.length < 12) return 'Medium';
    if (_hasSpecialChars(password)) return 'Strong';
    return 'Good';
  }

  void addLog(String message) {
    logs.insert(0, message);
    if (logs.length > 20) {
      logs.removeLast();
    }
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return regex.hasMatch(email);
  }

  bool _hasSpecialChars(String str) {
    final regex = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
    return regex.hasMatch(str);
  }
}

class TextInputShowcaseApp extends StatefulWidget {
  const TextInputShowcaseApp({super.key});

  @override
  State<TextInputShowcaseApp> createState() => _TextInputShowcaseAppState();
}

class _TextInputShowcaseAppState extends State<TextInputShowcaseApp> {
  final logic = TextInputLogic();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _message = TextEditingController();
  final _disabled = TextEditingController(text: 'Disabled value');

  /// The name field's handle: the app asks for the keyboard through it, rather
  /// than waiting for someone to tap the field.
  final _nameFocus = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBar(title: Text('TextInput Showcase')),
      body: Column(
        children: [
          _section('🏷️ Floating Label Input', [
            TextField(
              key: const ValueKey('name_field'),
              controller: _name,
              focusNode: _nameFocus,
              // The return key moves to the email field rather than closing
              // the keyboard - the point of the whole showcase being a form.
              textInputAction: TextInputAction.next,
              onChanged: (v) => setState(() {
                logic.name = v;
                logic.validateName();
              }),
              onFocus: () => setState(() => logic.nameFocused = true),
              onBlur: () => setState(() => logic.nameFocused = false),
              onSubmitted: (v) => setState(() {
                logic.nameSubmitted = true;
                logic.addLog('Name submitted: $v');
              }),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                labelText: 'Full Name',
                errorText: logic.nameError,
              ),
            ),
            Text(
              logic.nameFocused ? 'Status: Focused' : 'Status: Not focused',
              key: const ValueKey('name_status'),
            ),
          ]),
          _section('⌨️ Focus From The App', [
            const Text(
              'The app can put the caret in a field, or take the keyboard '
              'away, without the user touching either.',
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const ValueKey('focus_name'),
              onPressed: () => setState(() {
                _nameFocus.requestFocus();
                logic.addLog('Asked for the name field');
              }),
              child: const Text('Focus the name field'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              key: const ValueKey('dismiss_keyboard'),
              onPressed: () => setState(() {
                _nameFocus.unfocus();
                logic.addLog('Gave the keyboard back');
              }),
              child: const Text('Dismiss the keyboard'),
            ),
          ]),
          _section('📧 Email Input with Validation', [
            TextField(
              key: const ValueKey('email_field'),
              controller: _email,
              textInputAction: TextInputAction.next,
              onChanged: (v) => setState(() {
                logic.email = v;
                logic.validateEmail();
              }),
              onFocus: () => setState(() => logic.emailFocused = true),
              onBlur: () => setState(() => logic.emailFocused = false),
              decoration: InputDecoration(
                hintText: 'user@example.com',
                labelText: 'Email Address',
                errorText: logic.emailError,
              ),
            ),
            Text(_emailStatus(), key: const ValueKey('email_status')),
          ]),
          _section('🔒 Password Input', [
            TextField(
              key: const ValueKey('password_field'),
              controller: _password,
              obscureText: true,
              onChanged: (v) => setState(() {
                logic.password = v;
                logic.validatePassword();
              }),
              decoration: InputDecoration(
                hintText: 'Enter password',
                labelText: 'Password',
                errorText: logic.passwordError,
              ),
            ),
            Text(
              logic.password.isNotEmpty
                  ? 'Strength: ${logic.getPasswordStrength()}'
                  : 'Enter at least 8 characters',
              key: const ValueKey('password_status'),
            ),
          ]),
          _section('📝 Multi-line Input', [
            TextField(
              key: const ValueKey('message_field'),
              controller: _message,
              maxLines: 3,
              onChanged: (v) => setState(() => logic.message = v),
              decoration: const InputDecoration(
                hintText: 'Enter your message...',
                labelText: 'Message',
              ),
            ),
            Text(
              'Characters: ${logic.message.length}',
              key: const ValueKey('message_count'),
            ),
          ]),
          _section('🚫 Disabled Input', [
            TextField(
              key: const ValueKey('disabled_field'),
              controller: _disabled,
              enabled: false,
              decoration: const InputDecoration(
                hintText: 'Cannot edit this field',
                labelText: 'Read-only',
              ),
            ),
          ]),
          _section('📋 Event Log', [
            ElevatedButton(
              key: const ValueKey('validate_all'),
              onPressed: () => setState(() {
                logic.validateAll();
                logic.addLog('Validated all fields');
              }),
              child: const Text('Validate All'),
            ),
            const SizedBox(height: 8),
            const Text('Last 5 events:'),
            for (final (i, log) in logic.logs.take(5).indexed)
              Text('• $log', key: ValueKey('log_$i')),
          ]),
          _section('✅ TextInput Features:', const [
            Text('• Floating labels'),
            Text('• Hint text'),
            Text('• Error state with message'),
            Text('• Disabled state'),
            Text('• Focus/Blur events'),
            Text('• Change events'),
            Text('• Submit/Next events'),
            Text('• Password obscuring'),
            Text('• Multi-line support'),
            Text('• Initial values'),
            Text('• Character counting'),
            Text('• Validation feedback'),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _emailStatus() {
    if (logic.emailFocused) return '✏️ Editing email';
    if (logic.email.isNotEmpty && logic.emailError == null) {
      return '✅ Email valid';
    }
    if (logic.email.isNotEmpty) return '❌ Invalid email';
    return '📝 Enter email';
  }

  static Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}
