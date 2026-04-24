import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
import 'todo_widget.dart';

class TodoExamplePage extends StatelessWidget {
  const TodoExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Todo list'),
          const DocParagraph(
            'One store, one list, four actions. The UI observes the '
            'items via StateObserver; every write produces a new list, '
            'so the equality filter sees a change and the subscribed '
            'widgets rebuild.',
          ),
          const SizedBox(height: 8),
          const _Tabs(),
          const SizedBox(height: 24),
          const SizedBox(
            height: 560,
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_PreviewTab(), _CodeTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Preview'),
          Tab(text: 'Code'),
        ],
      ),
    );
  }
}

class _PreviewTab extends StatefulWidget {
  const _PreviewTab();

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: TodoDemoWidget(),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _Caption('todo_store.dart'),
          CodeBlock(code: _todoStoreSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('todo_widget.dart'),
          CodeBlock(code: _todoWidgetSource, language: 'dart'),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _todoStoreSource = r'''import 'package:armature/armature.dart';

typedef Todo = ({String id, String text, bool done});

typedef TodoState = ({List<Todo> items});

/// A small reactive store for a todo list example.
///
/// State is a record with one field — an immutable list of todos.
/// Actions are plain methods; each one writes a **new** list so the
/// equality filter sees a change and observers re-render.
class TodoStore extends Store<TodoState> {
  TodoStore() : super(state: (items: <Todo>[]));

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

  void toggle(String id) {
    state = (
      items: [
        for (final t in state.items)
          if (t.id == id) (id: t.id, text: t.text, done: !t.done) else t,
      ],
    );
  }

  void remove(String id) {
    state = (items: state.items.where((t) => t.id != id).toList());
  }

  void clearDone() {
    state = (items: state.items.where((t) => !t.done).toList());
  }
}
''';

const _todoWidgetSource = r'''import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'todo_store.dart';

/// Feature owning the [TodoStore] — container disposes it automatically.
final todoFeature = createFeature(
  name: 'Todo',
  stores: (_) => (todos: TodoStore()),
  exports: (api) => api.own,
);

final _todoRoot = createFeatureRoot(
  feature: todoFeature,
  widget: const _TodoView(),
);

class TodoDemoWidget extends StatelessWidget {
  const TodoDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArmatureApp(
      features: [todoFeature],
      child: _todoRoot(data: null),
    );
  }
}

class _TodoView extends StatefulWidget {
  const _TodoView();

  @override
  State<_TodoView> createState() => _TodoViewState();
}

class _TodoViewState extends State<_TodoView> {
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
    final store = StoreContext.of<TodoStore>(context);

    void submit() {
      store.add(_input.text);
      _input.clear();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(hintText: 'Add a todo…'),
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
              return const Text('Nothing yet — add your first todo above.');
            }
            return Column(
              children: [
                for (final todo in items)
                  _TodoTile(
                    todo: todo,
                    onToggle: () => store.toggle(todo.id),
                    onRemove: () => store.remove(todo.id),
                  ),
              ],
            );
          },
        ),
        StateObserver(
          builder: (_) {
            final items = store.state.items;
            final remaining = items.where((t) => !t.done).length;
            final hasDone = items.any((t) => t.done);
            return Row(
              children: [
                Text('$remaining remaining'),
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
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onRemove,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: todo.done, onChanged: (_) => onToggle()),
        Expanded(
          child: Text(
            todo.text,
            style: TextStyle(
              decoration: todo.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }
}
''';
