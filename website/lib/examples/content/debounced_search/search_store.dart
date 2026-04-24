import 'package:armature/armature.dart';

/// Store with a single debounced search task and a live list of
/// recent *successful* queries.
///
/// The debounce strategy coalesces rapid calls into one run at the end
/// of the quiet window — ideal for search-as-you-type. Every successful
/// (non-empty result) search appends its query to [recent] in MRU
/// order, capped at [_recentLimit].
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
        // and cap the list. `state.recent` here is the LATEST value
        // because the task just awaited — safe to read.
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

  /// Drop a single query from the MRU list (used by the chip's
  /// delete affordance). Preserves [lastQuery].
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
