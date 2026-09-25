import 'package:dart_not_native/material.dart';

import 'apps/todo_example_app.dart' show TodoItem, TodoLogic;

/// Simple Todo app - pure Flutter, no native code needed.
/// This demonstrates that the framework works for regular apps too.
///
/// Run with: flutter run
/// No NativeBridge initialization needed for pure Dart apps.

void main() {
  // No NativeBridge.initialize() needed for pure Dart apps!
  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Todo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const TodoPage(title: 'My Todos'),
    );
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final TodoLogic _logic = TodoLogic();
  final TextEditingController _controller = TextEditingController();

  List<TodoItem> get _todos => _logic.todos;

  void _addTodo() {
    setState(() {
      if (_logic.add(_controller.text)) _controller.clear();
    });
  }

  void _toggleTodo(int id) {
    setState(() => _logic.toggle(id));
  }

  void _deleteTodo(int id) {
    setState(() => _logic.delete(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Add a new todo...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _addTodo,
                  tooltip: 'Add Todo',
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Expanded(
            child: _todos.isEmpty
                ? const Center(
                    child: Text(
                      'No todos yet. Add one above!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (context, index) {
                      final todo = _todos[index];
                      return ListTile(
                        leading: Checkbox(
                          value: todo.completed,
                          onChanged: (_) => _toggleTodo(todo.id),
                        ),
                        title: Text(
                          todo.title,
                          style: TextStyle(
                            decoration: todo.completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteTodo(todo.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
