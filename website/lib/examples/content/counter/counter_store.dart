import 'package:armature/armature.dart';

/// State record — a single integer value.
typedef CounterState = ({int value});

/// Reactive store for the counter example.
///
/// Demonstrates two task strategies: `queue` for serialised asynchronous
/// increments, and `debounce` for rate-limited bumps that collapse rapid
/// calls into a single write.
class CounterStore extends Store<CounterState> {
  CounterStore() : super(state: (value: 0));

  /// Increments after a short delay. With `queue`, two rapid taps run
  /// back-to-back — you see the value climb smoothly.
  late final increment = createVoidTask(
    fn: () async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = (value: state.value + 1);
    },
    strategy: TaskStrategy.queue,
  );

  /// Fires at most once per 400 ms, no matter how fast you tap.
  late final debouncedBump = createVoidTask(
    fn: () async {
      state = (value: state.value + 1);
    },
    strategy: TaskStrategy.debounce(Duration(milliseconds: 400)),
  );

  /// Resets the counter to zero immediately.
  late final reset = createVoidTask(
    fn: () async {
      state = (value: 0);
    },
    strategy: TaskStrategy.queue,
  );
}
