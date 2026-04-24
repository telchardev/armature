import 'package:armature/armature.dart';

typedef HistoryState = ({List<int> values});

class HistoryStore extends Store<HistoryState> {
  static const int maxEntries = 20;

  HistoryStore() : super(state: (values: const <int>[]));

  void push(int value) {
    update(
      (s) => (
        values: [value, ...s.values].take(maxEntries).toList(growable: false),
      ),
    );
  }

  void clear() {
    update((s) => (values: const <int>[]));
  }
}
