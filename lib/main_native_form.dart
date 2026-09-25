/// The sign-up form, drawn with the platform's own views.
///
///   flutter run -t lib/main_native_form.dart -d `<device>`
library;

import 'package:dart_not_native/run_app.dart';
import 'package:dart_not_native/widgets.dart';

import 'examples/apps/signup_form_app.dart';

Future<void> main() => runNativeApp(
      hostApp(const SignupFormApp()),
      nativeViews: true,
      title: 'Sign up',
    );
