import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'todo_store.dart';

/// Feature owning the [TodoStore]. The container disposes the store
/// when the ArmatureApp unmounts — no widget-level dispose needed.
final todoFeature = createFeature(
  name: 'Todo',
  stores: (_) => (todos: TodoStore()),
  exports: (api) => api.own,
);

final todoRoot = createFeatureRoot(
  feature: todoFeature,
  widget: const TodoView(),
);

class TodoView extends StatefulWidget {
  const TodoView({super.key});

  @override
  State<TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<TodoView> {
  // TextEditingController is UI-only — not a Store — so the widget
  // owns it and disposes it. Framework only manages Stores.
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreContext.of<TodoStore>(context);

    void submit() {
      store.add(_input.text);
      _input.clear();
    }

    return Container(
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 480),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    hintText: 'Add a todo…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: submit, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 16),
          StateObserver(
            builder: (_) {
              final items = store.state.items;
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing yet — add your first todo above.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final todo in items)
                    TodoTile(
                      todo: todo,
                      onToggle: () => store.toggle(todo.id),
                      onRemove: () => store.remove(todo.id),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          StateObserver(
            builder: (_) {
              final items = store.state.items;
              final remaining = items.where((t) => !t.done).length;
              final hasDone = items.any((t) => t.done);
              return Row(
                children: [
                  Text(
                    '$remaining remaining',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: hasDone ? store.clearDone : null,
                    child: const Text('Clear done'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onRemove,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(value: todo.done, onChanged: (_) => onToggle()),
          Expanded(
            child: Text(
              todo.text,
              style: theme.textTheme.bodyLarge?.copyWith(
                decoration: todo.done ? TextDecoration.lineThrough : null,
                color: todo.done
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(
    ArmatureApp(
      features: [todoFeature],
      child: MaterialApp(home: todoRoot(data: null)),
    ),
  );
}
