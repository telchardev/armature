import 'package:armature/armature.dart';

typedef HistoryState = ({List<int> values});

extension HistoryStateCopyWith on HistoryState {
  HistoryState copyWith({List<int>? values}) => (values: values ?? this.values);
}

class HistoryStore extends Store<HistoryState> {
  static const int maxEntries = 20;

  HistoryStore() : super(state: (values: const <int>[]));

  void push(int value) {
    update(
      (s) => s.copyWith(
        values: [value, ...s.values].take(maxEntries).toList(growable: false),
      ),
    );
  }

  void clear() {
    update((s) => s.copyWith(values: const <int>[]));
  }
}
