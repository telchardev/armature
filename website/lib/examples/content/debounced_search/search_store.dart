import 'package:armature/armature.dart';

/// Minimal store with a single debounced task.
///
/// The debounce strategy coalesces rapid calls into one run at the end
/// of the quiet window. Ideal for search-as-you-type: every keystroke
/// invokes the task, but the underlying work only fires once the user
/// pauses typing.
class SearchStore extends Store<({String lastQuery})> {
  SearchStore() : super(state: (lastQuery: ''));

  late final search = createTask<String, List<String>, Never>(
    fn: (query) async {
      state = (lastQuery: query);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (query.trim().isEmpty) {
        return const [];
      }
      final needle = query.toLowerCase();
      return _catalogue
          .where((item) => item.toLowerCase().contains(needle))
          .toList();
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );
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
