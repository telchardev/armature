import 'package:armature/armature.dart';
import 'package:armature_flutter/armature_flutter.dart';
import 'package:flutter/material.dart';

import 'search_store.dart';

class SearchDemoWidget extends StatefulWidget {
  const SearchDemoWidget({super.key});

  @override
  State<SearchDemoWidget> createState() => _SearchDemoWidgetState();
}

class _SearchDemoWidgetState extends State<SearchDemoWidget> {
  late final SearchStore _store;
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _store = SearchStore();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _store.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onChanged: (value) => _store.search(value),
            decoration: const InputDecoration(
              hintText: 'Type to search (try "flu")',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: StateObserver(builder: (_) => _results(theme)),
          ),
        ],
      ),
    );
  }

  Widget _results(ThemeData theme) {
    final taskState = _store.search.state;
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
