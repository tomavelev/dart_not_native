/// A whole screen made of a form: sign-up, validated and submitted.
///
/// The other examples show fields one at a time; this one is what an app
/// actually has - four fields that depend on each other, errors that appear
/// when someone leaves a field or presses the button, and a submit that only
/// runs when everything passes.
///
/// The form itself is `dart_not_native`'s `Form`/`FormField`: the widgets bind
/// to it with [TextFormField], and the button hands the whole thing to
/// `form.submit`, which validates every field and calls back only if they all
/// pass.
library;

import 'package:dart_not_native/widgets.dart';

/// The fields, in the order they are on screen.
///
/// Built once per app so the validators can close over each other - the
/// confirmation matches whatever the password field holds *now*.
class SignupFormFields {
  SignupFormFields() {
    password = FormField(
      name: 'password',
      label: 'Password',
      hint: 'At least 8 characters, one capital and one number',
      required: true,
      obscured: true,
      validators: [PasswordValidator(minLength: 8)],
    );
    confirm = FormField(
      name: 'confirm',
      label: 'Confirm password',
      hint: 'Type it again',
      required: true,
      obscured: true,
      validators: [
        MatchValidator(() => password.value, 'Passwords do not match'),
      ],
    );
    form
      ..addField(name)
      ..addField(email)
      ..addField(password)
      ..addField(confirm);
  }

  final Form form = Form();

  final FormField name = FormField(
    name: 'name',
    label: 'Full name',
    hint: 'Ada Lovelace',
    required: true,
    validators: [MinLengthValidator(2)],
  );

  final FormField email = FormField(
    name: 'email',
    label: 'Email',
    hint: 'you@example.com',
    required: true,
    validators: [EmailValidator()],
  );

  late final FormField password;
  late final FormField confirm;

  /// A focus handle per field, so a failed submit can send the user straight
  /// to the one that needs attention.
  final Map<String, FocusNode> _focus = {};

  FocusNode focusOf(FormField field) =>
      _focus.putIfAbsent(field.name, FocusNode.new);
}

class SignupFormApp extends StatefulWidget {
  const SignupFormApp({super.key});

  @override
  State<SignupFormApp> createState() => _SignupFormAppState();
}

class _SignupFormAppState extends State<SignupFormApp> {
  final fields = SignupFormFields();

  /// What the last submit did: nothing yet, the message a failed one leaves,
  /// or the account it would have created.
  String? message;
  String? signedUpAs;
  bool submitting = false;

  Future<void> _submit() async {
    setState(() => submitting = true);
    final sent = await fields.form.submit((values) async {
      // Where an app would call its API. The values are the whole form.
      signedUpAs = values['email'];
    });
    if (!mounted) return;
    final invalid = fields.form.firstInvalid;
    setState(() {
      submitting = false;
      message = sent
          ? null
          : 'Check the fields above - '
                '${invalid?.label ?? 'one'} needs attention.';
      // Saying which field is wrong is half of it; the other half is putting
      // the caret there, so the fix is a keystroke away rather than a tap.
      if (!sent && invalid != null) fields.focusOf(invalid).requestFocus();
    });
  }

  void _reset() => setState(() {
    fields.form.reset();
    message = null;
    signedUpAs = null;
  });

  @override
  Widget build(BuildContext context) {
    if (signedUpAs != null) {
      return Scaffold(
        appBar: const AppBar(title: Text('Sign up')),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome aboard',
                      key: ValueKey('signed_up'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('We sent a confirmation to $signedUpAs.'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                key: const ValueKey('start_over'),
                onPressed: _reset,
                child: const Text('Start over'),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: const AppBar(title: Text('Sign up')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  field: fields.name,
                  focusNode: fields.focusOf(fields.name),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  field: fields.email,
                  focusNode: fields.focusOf(fields.email),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  field: fields.password,
                  focusNode: fields.focusOf(fields.password),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  field: fields.confirm,
                  focusNode: fields.focusOf(fields.confirm),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  key: const ValueKey('submit'),
                  onPressed: submitting ? null : _submit,
                  child: Text(submitting ? 'Creating…' : 'Create account'),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    key: const ValueKey('form_message'),
                    style: TextStyle(color: Color.fromHex('#d32f2f')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
