# Text Input & Forms Guide

Text entry in dart_not_native is a plain-Flutter `TextField`, and validated forms
are a `FormBuilder` + `TextFormField`, all from
`package:dart_not_native/widgets.dart`. This guide covers both.

The field itself is the platform's own editor - `UITextField` on iOS, `EditText`
on Android, `<input>`/`<textarea>` on the web, a Flutter `TextField` under the
Flutter engine - while the code stays a plain Flutter `TextField`.

## A single text field

```dart
final _name = TextEditingController();

TextField(
  controller: _name,
  decoration: const InputDecoration(
    labelText: 'Name',
    hintText: 'Ada Lovelace',
  ),
  onChanged: (value) => setState(() => _greeting = 'Hi, $value'),
  onSubmitted: (value) => _save(value),
)
```

`TextField` takes `controller`, `decoration` (`labelText` / `hintText` /
`errorText`), `obscureText` for passwords, `enabled`, `maxLines`, and the events
`onChanged` / `onSubmitted` / `onFocus` / `onBlur`.

### Reading and setting the value

A `TextEditingController` is the value:

```dart
final text = _name.text;   // read
_name.text = 'Ada';        // set programmatically
_name.clear();             // clear
```

Setting `text` (or `clear()`) updates the native field even while it holds focus
— the todo example clears the box the moment you add an item — while the user's
own typing never triggers a re-render.

That is a version counter: the controller bumps it when the *app* changes the
text, never when the *user* types, and every rendered node carries it. A
renderer re-applies the value only when the version moved, which is why typing
quickly is never truncated by a re-render and an app-side `clear()` still
reaches a focused field.

### The keyboard's return key, and where the label sits

```dart
TextField(
  controller: _email,
  textInputAction: TextInputAction.next,   // advances to the next field
  decoration: const InputDecoration(
    labelText: 'Email',
    // The label floats into the field's outline by default, as in Flutter.
    // FloatingLabelBehavior.never draws it above the field instead - which is
    // what the native iOS renderer does either way, since UIKit has no
    // floating label.
    floatingLabelBehavior: FloatingLabelBehavior.auto,
  ),
)
```

`TextInputAction.next` moves to the next field in the tree's reading order; the
last field has nowhere to go and closes the keyboard instead, and a multi-line
field keeps its newline key whatever this says.

### Asking for the keyboard from the app

A screen whose whole point is one field takes the keyboard as it opens:

```dart
TextField(autofocus: true, decoration: const InputDecoration(hintText: 'Search'))
```

Anything later goes through a `FocusNode`, which the app holds and the field
carries:

```dart
final email = FocusNode();

TextField(focusNode: email, decoration: const InputDecoration(labelText: 'Email'))

// Somewhere in a handler, inside setState:
email.requestFocus();   // put the caret here and open the keyboard
email.unfocus();        // give the keyboard back
```

Unlike Flutter's `FocusNode`, this one is not a live object the renderer talks
to: the tree is all that crosses, so each call bumps a version the field
carries, and a renderer acts on a version it has not seen. That is deliberate -
"focused" as a *state* would take the caret back every time the app re-rendered
for an unrelated reason. A node nobody has called yet asks for nothing.

## Validated forms

For anything with validation, build a `Form` and bind each field to a
`TextFormField`. Three steps.

### 1. Build the form

`FormBuilder` has typed helpers plus a general `addTextField`:

```dart
final form = (FormBuilder()
      ..addTextField(
        name: 'name',
        label: 'Name',
        required: true,
        validators: [MinLengthValidator(2)],
      )
      ..addEmailField(name: 'email')
      ..addPasswordField(name: 'password'))
    .build();
```

| Builder | Field it adds |
| --- | --- |
| `addTextField(name:, label:, hint:, required:, initialValue:, validators:)` | a general field |
| `addEmailField(name:, label:, required:)` | email + `EmailValidator`, required |
| `addPasswordField(name:, ...)` | obscured + `PasswordValidator` |
| `addPhoneField(name:, ...)` | a phone field with `PhoneValidator` |

### 2. Bind the fields

`TextFormField(field:)` renders the field's value, label, hint and validation
error, reports edits back, and validates on submit (and on blur by default). It
rebuilds itself when a validator reports an error, so you do not have to.

```dart
Column(children: [
  TextFormField(field: form.getField('name')!),
  TextFormField(field: form.getField('email')!),
  TextFormField(field: form.getField('password')!),
  ElevatedButton(onPressed: _submit, child: const Text('Sign up')),
]);
```

### 3. Validate and read

```dart
Future<void> _submit() async {
  if (await form.validate()) {
    final data = form.values;          // { 'name': 'Ada', 'email': ... }
    await api.signUp(data);
  }
  // On failure each field already shows its error - TextFormField saw it.
}
```

Other `Form` members: `getField(name)`, `values`, `isValid`, `validate()`,
`reset()`, and `onChange` (a stream of the whole value map). After `reset()`,
rebuild so the bound fields pick the cleared values back up.

## Validators

Compose them in a field's `validators:` list; `required:` is checked first.

| Validator | Checks |
| --- | --- |
| `RequiredValidator()` | non-empty (or use `required: true`) |
| `EmailValidator()` | a valid email address |
| `MinLengthValidator(n)` / `MaxLengthValidator(n)` | length bounds |
| `PasswordValidator()` | password strength rules |
| `PhoneValidator()` | a phone number |
| `UrlValidator()` | a URL |
| `PatternValidator(regExp)` | a custom regular expression |
| `MatchValidator(() => other.value)` | equals another field (confirm password) |

## A complete sign-up form

```dart
import 'package:dart_not_native/widgets.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});
  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  late final Form form = (FormBuilder()
        ..addTextField(name: 'name', label: 'Name', required: true)
        ..addEmailField(name: 'email')
        ..addPasswordField(name: 'password'))
      .build();

  String status = '';

  Future<void> _submit() async {
    if (await form.validate()) {
      setState(() => status = 'Welcome, ${form.values['name']}!');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const AppBar(title: Text('Sign up')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextFormField(field: form.getField('name')!),
            TextFormField(field: form.getField('email')!),
            TextFormField(field: form.getField('password')!),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _submit, child: const Text('Sign up')),
            Text(status),
          ]),
        ),
      );
}
```

The text-input showcase (`lib/examples/apps/textinput_showcase_app.dart`) shows
the raw `TextField` variations; the pattern above shows the same fields wired
through a form.
