/// Todo list - written as a plain Flutter app.
///
/// [TodoLogic] is the pure list logic; [TodoApp] is an ordinary Flutter
/// `StatefulWidget`. Swapping the import for `package:dart_not_native/widgets.dart`
/// is all that renders it through the platform's own views (the web DOM on web)
/// rather than the Flutter engine.
library;

import 'package:dart_not_native/widgets.dart';

class TodoItem {
  final int id;
  final String title;
  bool completed;

  TodoItem({required this.id, required this.title, required this.completed});
}

class TodoLogic {
  final List<TodoItem> todos = [];
  int _nextId = 1;

  int get completedCount => todos.where((t) => t.completed).length;

  /// Adds a todo; blank titles are ignored. Returns whether one was added.
  bool add(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    todos.add(TodoItem(id: _nextId++, title: trimmed, completed: false));
    return true;
  }

  void toggle(int id) {
    final todo = todos.firstWhere((t) => t.id == id);
    todo.completed = !todo.completed;
  }

  void delete(int id) {
    todos.removeWhere((t) => t.id == id);
  }
}

class TodoApp extends StatefulWidget {
  const TodoApp({super.key});

  @override
  State<TodoApp> createState() => _TodoAppState();
}

class _TodoAppState extends State<TodoApp> {
  final logic = TodoLogic();
  final _field = TextEditingController();

  void _add(String title) {
    setState(() {
      if (logic.add(title)) _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBar(title: Text('My Todos')),
      body: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('new_todo'),
                    controller: _field,
                    onSubmitted: _add,
                    decoration:
                        const InputDecoration(hintText: 'Add a new todo...'),
                  ),
                ),
                IconButton(
                  key: const ValueKey('add'),
                  icon: const Icon(Icons.add_task),
                  tooltip: 'Add Todo',
                  onPressed: () => _add(_field.text),
                ),
              ],
            ),
          ),
          if (logic.todos.isEmpty)
            const Center(
              child: Text(
                'No todos yet. Add one above!',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final todo in logic.todos) _todoRow(todo),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${logic.completedCount} of ${logic.todos.length} completed',
                    key: const ValueKey('todo_summary'),
                    style: const TextStyle(color: Color(0xFF757575)),
                  ),
                ),
              ],
            ),
        ],
      )),
    );
  }

  /// The row carries the todo's id (via its key) so renderers can tell one row
  /// from another: adding or removing a todo then moves the rows that remain
  /// instead of rebuilding every row below the change.
  Widget _todoRow(TodoItem todo) => Padding(
        key: ValueKey('todo_row_${todo.id}'),
        padding: const EdgeInsets.all(8),
        child: Row(
          spacing: 8,
          children: [
            Checkbox(
              key: ValueKey('todo_${todo.id}_done'),
              value: todo.completed,
              onChanged: (_) => setState(() => logic.toggle(todo.id)),
            ),
            Expanded(
              child: Text(
                todo.title,
                key: ValueKey('todo_${todo.id}_title'),
                style: TextStyle(
                  fontSize: 16,
                  color: todo.completed ? Colors.grey : null,
                  decoration:
                      todo.completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('todo_${todo.id}_delete'),
              icon: const Icon(Icons.delete),
              tooltip: 'Delete ${todo.title}',
              onPressed: () => setState(() => logic.delete(todo.id)),
            ),
          ],
        ),
      );
}
