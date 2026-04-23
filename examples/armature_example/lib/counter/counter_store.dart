import 'package:armature/armature.dart';

typedef CounterState = ({int value});

extension CounterStateCopyWith on CounterState {
  CounterState copyWith({int? value}) => (value: value ?? this.value);
}

class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));

  late final increment = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      update((s) => s.copyWith(value: s.value + 1));
    },
    strategy: TaskStrategy.queue,
  );

  late final decrementTo = createTask(
    fn: (int target) async {
      while (state.value > target) {
        state = state.copyWith(value: state.value - 1);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    },
    strategy: TaskStrategy.queue,
  );

  late final reset = createVoidTask(
    fn: () async {
      update((s) => s.copyWith(value: 0));
    },
    strategy: TaskStrategy.queue,
  );

  late final debouncedBump = createVoidTask(
    fn: () async {
      update((s) => s.copyWith(value: s.value + 1));
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 300)),
  );
}
