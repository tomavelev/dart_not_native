/// Runs the todo example - a plain Flutter `StatefulWidget` - through the
/// platform's own views, so the Material Icons glyphs (add_task, delete) are
/// drawn natively. Only the import sets it apart from a Flutter app.
///
///   flutter run -t lib/main_native_todo.dart -d `<device>`
library;

import 'package:dart_not_native/widgets.dart';

import 'examples/apps/todo_example_app.dart';

void main() {
  runApp(const TodoApp(), title: 'Native Todo');
}
