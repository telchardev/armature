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
          _Caption('The store'),
          CodeBlock(code: _storeSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('Observing the list'),
          CodeBlock(code: _observeSource, language: 'dart'),
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

const _storeSource = '''typedef Todo = ({String id, String text, bool done});
typedef TodoState = ({List<Todo> items});

class TodoStore extends Store<TodoState> {
  TodoStore() : super(state: (items: <Todo>[]));

  void add(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    state = (items: [
      ...state.items,
      (id: uniqueId(), text: trimmed, done: false),
    ]);
  }

  void toggle(String id) {
    state = (items: [
      for (final t in state.items)
        if (t.id == id) (id: t.id, text: t.text, done: !t.done) else t,
    ]);
  }

  void remove(String id) {
    state = (items: state.items.where((t) => t.id != id).toList());
  }

  void clearDone() {
    state = (items: state.items.where((t) => !t.done).toList());
  }
}''';

const _observeSource = '''StateObserver(
  builder: (_) {
    final items = store.state.items;
    if (items.isEmpty) return const Text('Nothing yet.');
    return Column(
      children: [
        for (final todo in items)
          CheckboxListTile(
            value: todo.done,
            onChanged: (_) => store.toggle(todo.id),
            title: Text(todo.text),
          ),
      ],
    );
  },
)''';
