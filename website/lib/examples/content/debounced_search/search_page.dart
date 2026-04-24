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
          const DocParagraph(
            'The store also keeps a live list of recent successful '
            'queries — whenever the task completes with a non-empty '
            'result, the query is promoted to the front of an MRU list '
            'and written back into the store state. The chips below the '
            'input read that list reactively.',
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
          _Caption('search_store.dart'),
          CodeBlock(code: _searchStoreSource, language: 'dart'),
          SizedBox(height: 20),
          _Caption('search_widget.dart'),
          CodeBlock(code: _searchWidgetSource, language: 'dart'),
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

const _searchStoreSource = r'''import 'package:armature/armature.dart';

/// Store with a single debounced search task and a live list of
/// recent *successful* queries.
class SearchStore extends Store<({String lastQuery, List<String> recent})> {
  SearchStore() : super(state: (lastQuery: '', recent: const []));

  static const _recentLimit = 5;

  late final search = createTask<String, List<String>, Never>(
    fn: (query) async {
      final trimmed = query.trim();
      // Reflect the in-flight query immediately so the UI can show it.
      state = (lastQuery: query, recent: state.recent);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (trimmed.isEmpty) {
        return const [];
      }
      final needle = trimmed.toLowerCase();
      final results = _catalogue
          .where((item) => item.toLowerCase().contains(needle))
          .toList();
      if (results.isNotEmpty) {
        // Move this query to the front, drop any prior duplicate,
        // and cap the list.
        final updated = <String>[
          trimmed,
          ...state.recent.where((q) => q.toLowerCase() != needle),
        ].take(_recentLimit).toList();
        state = (lastQuery: query, recent: updated);
      }
      return results;
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );

  /// Drop a single query from the MRU list.
  void removeRecent(String query) {
    state = (
      lastQuery: state.lastQuery,
      recent: state.recent.where((q) => q != query).toList(growable: false),
    );
  }
}

const _catalogue = [
  'Armature',
  'Armature Flutter',
  'Armature Graph',
  'Armature Reactive',
  'Bloc',
  'ChangeNotifier',
  'Dart',
  'Equatable',
  'Flutter',
  'Flutter Hooks',
  'freezed',
  'GetX',
  'go_router',
  'Hive',
  'MobX',
  'Provider',
  'Riverpod',
  'Signals',
  'Shared Preferences',
  'sqflite',
  'StateNotifier',
];
''';

const _searchWidgetSource = r'''import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'search_store.dart';

/// Feature owning the [SearchStore] — the framework disposes it when
/// the container tears down.
final searchFeature = createFeature(
  name: 'Search',
  stores: (_) => (search: SearchStore()),
  exports: (api) => api.own,
);

final _searchRoot = createFeatureRoot(
  feature: searchFeature,
  widget: const _SearchView(),
);

class SearchDemoWidget extends StatelessWidget {
  const SearchDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArmatureApp(
      features: [searchFeature],
      child: _searchRoot(data: null),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  // TextEditingController is UI-only, widget-owned.
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

  void _rerun(SearchStore store, String query) {
    _input.text = query;
    _input.selection = TextSelection.collapsed(offset: query.length);
    store.search(query);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreContext.of<SearchStore>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _input,
          onChanged: (value) => store.search(value),
          decoration: const InputDecoration(
            hintText: 'Type to search (try "flu")',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        StateObserver(
          builder: (_) {
            final recent = store.state.recent;
            if (recent.isEmpty) return const SizedBox.shrink();
            return Wrap(
              spacing: 8,
              children: [
                const Text('Recent:'),
                for (final q in recent)
                  InputChip(
                    label: Text(q),
                    onPressed: () => _rerun(store, q),
                    onDeleted: () => store.removeRecent(q),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: StateObserver(
            builder: (_) {
              final taskState = store.search.state;
              return switch (taskState) {
                TaskIdle() => const Text('Type to search.'),
                TaskPending(:final params) => Text('Searching "$params"…'),
                TaskDone(:final result) when result.isEmpty =>
                  const Text('No matches.'),
                TaskDone(:final result) => ListView(
                  children: [for (final r in result) ListTile(title: Text(r))],
                ),
                TaskFailed() => const Text('Search failed.'),
              };
            },
          ),
        ),
      ],
    );
  }
}
''';
