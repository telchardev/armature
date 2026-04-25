import 'dart:math' show Random;

import 'package:armature/armature.dart';

typedef CounterState = ({int value});

/// Sample domain error for [CounterStore.flakyFetch] — sticks to
/// TaskFailed because it's the task's TError.
class FetchError implements Exception {
  final String message;
  FetchError(this.message);

  @override
  String toString() => message;
}

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

  /// Demo task: 50% chance of throwing [FetchError]. Pairs with
  /// `autoReset: 3s` so observers see Done/Failed for ~3 seconds, then
  /// state transitions back to TaskIdle and the button re-enables.
  late final flakyFetch = createVoidTask<String, FetchError>(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (Random().nextDouble() < 0.5) {
        throw FetchError('Network unreachable');
      }
      return 'Greeting #${state.value}';
    },
    autoReset: const Duration(seconds: 3),
  );
}
