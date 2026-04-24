import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'search_store.dart';

/// Feature owning the [SearchStore] — the framework disposes it when
/// the container tears down, which includes the pending debounce
/// timer and task state.
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
  // Plain TextEditingController — UI state, widget-owned.
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
    final theme = Theme.of(context);
    final store = StoreContext.of<SearchStore>(context);
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
          TextField(
            controller: _input,
            onChanged: (value) => store.search(value),
            decoration: const InputDecoration(
              hintText: 'Type to search (try "flu")',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          StateObserver(builder: (_) => _recentChips(theme, store)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: StateObserver(builder: (_) => _results(theme, store)),
          ),
        ],
      ),
    );
  }

  Widget _recentChips(ThemeData theme, SearchStore store) {
    final recent = store.state.recent;
    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Recent:',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final query in recent)
          InputChip(
            visualDensity: VisualDensity.compact,
            label: Text(query),
            onPressed: () => _rerun(store, query),
            onDeleted: () => store.removeRecent(query),
            deleteIconBoxConstraints: const BoxConstraints(
              minWidth: 18,
              minHeight: 18,
            ),
          ),
      ],
    );
  }

  Widget _results(ThemeData theme, SearchStore store) {
    final taskState = store.search.state;
    return switch (taskState) {
      TaskIdle() => _empty(
        theme,
        'Ready — type a query to search the catalogue.',
      ),
      TaskPending(:final params) => _pending(theme, params),
      TaskDone(:final result) when result.isEmpty => _empty(
        theme,
        'No matches.',
      ),
      TaskDone(:final result) => _list(theme, result),
      TaskFailed() => _empty(theme, 'Search failed.'),
    };
  }

  Widget _empty(ThemeData theme, String message) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _pending(ThemeData theme, String query) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 12),
        Text(
          query.trim().isEmpty ? 'Waiting for input…' : 'Searching "$query"…',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _list(ThemeData theme, List<String> results) {
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (_, index) => ListTile(
        dense: true,
        title: Text(results[index]),
        leading: Icon(
          Icons.circle_outlined,
          size: 12,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
