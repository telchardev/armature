import 'package:armature/armature.dart';

typedef CounterState = ({int value});

class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));

  late final increment = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      update((s) => (value: s.value + 1));
    },
  );

  late final decrementTo = createTask(
    fn: (int target) async {
      while (state.value > target) {
        state = (value: state.value - 1);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    },
  );

  late final reset = createVoidTask(
    fn: () async {
      update((s) => (value: 0));
    },
  );

  late final debouncedBump = createVoidTask(
    fn: () async {
      update((s) => (value: s.value + 1));
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 300)),
  );
}
