import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/loaded_code_block.dart';
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
        child: _TodoDemoEmbed(),
      ),
    );
  }
}

class _TodoDemoEmbed extends StatelessWidget {
  const _TodoDemoEmbed();

  @override
  Widget build(BuildContext context) {
    return ArmatureApp(features: [todoFeature], child: todoRoot(data: null));
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
          LoadedCodeBlock(
            path: 'lib/examples/content/todo_list/todo_store.dart',
          ),
          SizedBox(height: 20),
          _Caption('todo_widget.dart'),
          LoadedCodeBlock(
            path: 'lib/examples/content/todo_list/todo_widget.dart',
          ),
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
