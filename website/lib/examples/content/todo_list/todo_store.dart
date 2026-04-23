import 'package:armature/armature.dart';

typedef Todo = ({String id, String text, bool done});

typedef TodoState = ({List<Todo> items});

/// A small reactive store for a todo list example.
///
/// State is a record with one field — an immutable list of todos.
/// Actions are plain methods; each one writes a **new** list so the
/// equality filter sees a change and observers re-render.
class TodoStore extends Store<TodoState> {
  TodoStore() : super(state: (items: <Todo>[]));

  /// Appends a new todo. Blank input is ignored silently.
  void add(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final todo = (
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: trimmed,
      done: false,
    );
    state = (items: [...state.items, todo]);
  }

  /// Flips the done flag for the todo with [id].
  void toggle(String id) {
    state = (
      items: [
        for (final t in state.items)
          if (t.id == id) (id: t.id, text: t.text, done: !t.done) else t,
      ],
    );
  }

  /// Removes the todo with [id].
  void remove(String id) {
    state = (items: state.items.where((t) => t.id != id).toList());
  }

  /// Drops every completed todo.
  void clearDone() {
    state = (items: state.items.where((t) => !t.done).toList());
  }
}
