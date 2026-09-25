/// The catalogue of example apps, shared by the smoke tests and the goldens.
///
/// Every example is constructed the way its platform entry point does, with
/// side effects (storage, i18n) supplied from the test doubles so the trees
/// are deterministic.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:dart_not_native_example/examples/apps/calculator_app.dart';
import 'package:dart_not_native_example/examples/apps/components_showcase_app.dart';
import 'package:dart_not_native_example/examples/apps/counter_app.dart';
import 'package:dart_not_native_example/examples/apps/design_system_showcase_app.dart';
import 'package:dart_not_native_example/examples/apps/i18n_example_app.dart';
import 'package:dart_not_native_example/examples/apps/inbox_example_app.dart';
import 'package:dart_not_native_example/examples/apps/routing_example_app.dart';
import 'package:dart_not_native_example/examples/apps/signup_form_app.dart';
import 'package:dart_not_native_example/examples/apps/storage_example_app.dart';
import 'package:dart_not_native_example/examples/apps/textinput_showcase_app.dart';
import 'package:dart_not_native_example/examples/apps/todo_example_app.dart';

import 'fake_storage.dart';

/// Example name -> a freshly built app.
final Map<String, NativeUIApp Function()> exampleApps = {
  'calculator': () => hostApp(const CalculatorApp()),
  'components_showcase': () => hostApp(const ComponentsShowcaseApp()),
  'counter': () => hostApp(const CounterApp()),
  'design_system_showcase': () => hostApp(const DesignSystemShowcaseApp()),
  'i18n': () => hostApp(I18nExampleApp(setUpDemoI18n())),
  'inbox': () => hostApp(const InboxApp()),
  'routing': () => hostApp(const RoutingExampleApp()),
  'signup_form': () => hostApp(const SignupFormApp()),
  'storage': () => hostApp(
    StorageExampleApp(
      storage: FakeStorage(),
      secureStorage: FakeSecureStorage(),
    ),
  ),
  'textinput_showcase': () => hostApp(const TextInputShowcaseApp()),
  'todo': () => hostApp(const TodoApp()),
};
