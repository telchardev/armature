import 'package:flutter/material.dart';

import '../../../docs/doc_typography.dart';
import '../../../widgets/code_block.dart';
import 'search_widget.dart';

class SearchExamplePage extends StatelessWidget {
  const SearchExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DocTitle('Debounced search'),
          const DocParagraph(
            'Search-as-you-type with a single task on a debounce '
            'strategy. Every keystroke invokes the task, but the '
            'underlying work only fires once the user pauses for 400 ms. '
            'The UI renders directly off the task state — pattern '
            'matching on TaskIdle / TaskPending / TaskDone drives the '
            'display.',
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
          const SizedBox(height: 24),
          const DocParagraph(
            'Try typing fast — the "Searching" indicator shows up '
            'immediately because the task state transitions to '
            'TaskPending, but the actual fetch only runs after the '
            'quiet window elapses.',
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
        child: SearchDemoWidget(),
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
          _Caption('Observing task state'),
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

const _storeSource = '''class SearchStore extends Store<({String lastQuery})> {
  SearchStore() : super(state: (lastQuery: ''));

  late final search = createTask<String, List<String>, Never>(
    fn: (query) async {
      state = (lastQuery: query);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (query.trim().isEmpty) return const [];
      return catalogue
          .where((item) => item.toLowerCase().contains(query.toLowerCase()))
          .toList();
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );
}''';

const _observeSource = '''TextField(
  onChanged: (value) => store.search(value),
),
StateObserver(
  builder: (_) {
    final taskState = store.search.state;
    return switch (taskState) {
      TaskIdle() => const Text('Type to search.'),
      TaskPending(:final params) => Text('Searching "\$params"…'),
      TaskDone(:final result) when result.isEmpty =>
        const Text('No matches.'),
      TaskDone(:final result) => Column(
          children: [for (final r in result) ListTile(title: Text(r))],
        ),
      TaskFailed() => const Text('Search failed.'),
    };
  },
)''';
