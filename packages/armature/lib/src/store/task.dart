import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart' show internal;

import '../errors.dart' show TaskError;
import './state.dart' show State, StateChangeListener, StateListenerDisposer;

/// Async function executed by a [Task].
typedef TaskFn<TParams, TResult, TError> =
    Future<TResult> Function(TParams params);

/// Execution strategy for a [Task].
///
/// Five variants, each with distinct semantics:
///
/// * [TaskStrategy.once] — runs once; subsequent calls return the cached
///   result (or share the in-flight future).
/// * [TaskStrategy.queue] — serialises calls; each awaits the previous.
/// * [TaskStrategy.latest] — supersedes the previous in-flight run. All
///   pending callers share the **latest** run's outcome (success or
///   [TError]); superseded runs' own results are discarded. Only the
///   latest run updates [Task.state]. Pending callers reject with
///   [TaskError] only if the task is disposed mid-flight.
/// * [TaskStrategy.debounce] — coalesces bursts. Each call restarts a
///   [Duration] timer; when the timer finally elapses without a new call,
///   the function runs with the last-seen parameters. All coalesced
///   callers share one result.
/// * [TaskStrategy.throttle] — two edges:
///   - [ThrottleEdge.leading]: first call runs immediately; calls during
///     the cooldown window return the in-flight or most recently settled
///     future.
///   - [ThrottleEdge.trailing]: fn runs once at the end of each
///     [duration] window with the most recent parameters. Calls within
///     the window coalesce into the scheduled run.
sealed class TaskStrategy {
  const TaskStrategy();

  /// Runs once, subsequent calls return cached result.
  static const TaskStrategy once = TaskStrategyOnce();

  /// Queues calls and executes them sequentially.
  static const TaskStrategy queue = TaskStrategyQueue();

  /// New call supersedes the in-flight one.
  static const TaskStrategy latest = TaskStrategyLatest();

  /// Coalesces rapid calls: the last parameters win after [duration]
  /// passes with no further calls.
  const factory TaskStrategy.debounce(Duration duration) = TaskStrategyDebounce;

  /// Leading-edge throttle: one run per [duration] window.
  const factory TaskStrategy.throttle(Duration duration, {ThrottleEdge edge}) =
      TaskStrategyThrottle;
}

/// See [TaskStrategy.once].
final class TaskStrategyOnce extends TaskStrategy {
  const TaskStrategyOnce();
}

/// See [TaskStrategy.queue].
final class TaskStrategyQueue extends TaskStrategy {
  const TaskStrategyQueue();
}

/// See [TaskStrategy.latest].
final class TaskStrategyLatest extends TaskStrategy {
  const TaskStrategyLatest();
}

/// See [TaskStrategy.debounce].
final class TaskStrategyDebounce extends TaskStrategy {
  final Duration duration;

  const TaskStrategyDebounce(this.duration);
}

/// See [TaskStrategy.throttle].
final class TaskStrategyThrottle extends TaskStrategy {
  final Duration duration;
  final ThrottleEdge edge;

  const TaskStrategyThrottle(this.duration, {this.edge = ThrottleEdge.leading});
}

/// Edge semantics for [TaskStrategy.throttle].
enum ThrottleEdge { leading, trailing }

/// Atomic snapshot of a [Task]'s lifecycle. Replaces the previous trio
/// of independent `pending` / `done` / `fail` states — observers now
/// see a single value that transitions through the cases below.
///
/// **Transition rules:**
///   * Initial value is [TaskIdle].
///   * Each `call(params)` transitions to [TaskPending(params)] for the
///     duration of the async work (with one exception: see debounce/throttle).
///   * On success → [TaskDone(result)] (sticky until the next `call`
///     or `reset`).
///   * On error that matches `TError` → [TaskFailed(error)] (sticky).
///   * On error that does **not** match `TError` (unexpected runtime
///     failure) → reverts to [TaskIdle]; the original exception rethrows
///     from `call()` so the caller can handle it.
///   * `Task.reset()` (manual or via `autoReset: duration`) → returns
///     the state to [TaskIdle] from any sticky state and supersedes any
///     in-flight run (its outcome no longer reaches [state]).
///
/// Strategy-specific notes:
///
///   * [TaskStrategy.debounce] — state transitions to
///     [TaskPending(latestParams)] on every call while the quiet timer
///     is waiting, so observers see a "coming soon" signal with the
///     up-to-date params. The actual run transitions through the same
///     [TaskPending] then [TaskDone]/[TaskFailed] as any other strategy.
///   * [TaskStrategy.throttle] ([ThrottleEdge.leading]) — calls during
///     the cooldown window do not change state; only the first call of
///     each window drives transitions.
///   * [TaskStrategy.throttle] ([ThrottleEdge.trailing]) — calls within
///     a window transition state to [TaskPending(latestParams)] until
///     the window expires and the run actually fires.
///   * [TaskStrategy.latest] — only the most recent `call`'s completion
///     writes to state. Superseded runs finish quietly in the background,
///     and all pending callers share the latest run's outcome.
///
/// Because each new `call` restarts the transition, only the **current**
/// run is reflected in the state. If you need "the last successful
/// result even while a new call is in flight", cache it in the owning
/// store yourself.
sealed class TaskState<TParams, TResult, TError> {
  const TaskState();
}

/// The task has not started yet, or the previous non-matching throw
/// reverted it.
final class TaskIdle<TParams, TResult, TError>
    extends TaskState<TParams, TResult, TError> {
  const TaskIdle();

  @override
  String toString() => 'TaskIdle';

  @override
  bool operator ==(Object other) => other is TaskIdle<TParams, TResult, TError>;

  @override
  int get hashCode => 0;
}

/// The task is currently executing with [params].
final class TaskPending<TParams, TResult, TError>
    extends TaskState<TParams, TResult, TError> {
  final TParams params;

  const TaskPending(this.params);

  @override
  String toString() => 'TaskPending($params)';

  @override
  bool operator ==(Object other) =>
      other is TaskPending<TParams, TResult, TError> && other.params == params;

  @override
  int get hashCode => Object.hash(TaskPending, params);
}

/// The most recent [Task.call] completed successfully with [result].
final class TaskDone<TParams, TResult, TError>
    extends TaskState<TParams, TResult, TError> {
  final TResult result;

  const TaskDone(this.result);

  @override
  String toString() => 'TaskDone($result)';

  @override
  bool operator ==(Object other) =>
      other is TaskDone<TParams, TResult, TError> && other.result == result;

  @override
  int get hashCode => Object.hash(TaskDone, result);
}

/// The most recent [Task.call] threw an error of type `TError`.
final class TaskFailed<TParams, TResult, TError>
    extends TaskState<TParams, TResult, TError> {
  final TError error;

  const TaskFailed(this.error);

  @override
  String toString() => 'TaskFailed($error)';

  @override
  bool operator ==(Object other) =>
      other is TaskFailed<TParams, TResult, TError> && other.error == error;

  @override
  int get hashCode => Object.hash(TaskFailed, error);
}

/// Async operation with an observable [state] machine ([TaskState]).
///
/// Create tasks via [Store.createTask] / [Store.createVoidTask]; they
/// belong to the owning store and are disposed together with it.
/// Call a task as a function: `task(params)` returns a `Future<TResult>`.
///
/// Behaviour across concurrent calls depends on the [TaskStrategy]
/// picked at construction — see [TaskStrategy] for the menu:
/// `.once` (cache + share), `.queue` (FIFO serialise), `.latest`
/// (supersede + share latest), `.debounce(d)` (coalesce burst),
/// `.throttle(d)` (rate-limit, leading or trailing edge).
///
/// The observable [state] transitions through [TaskState] variants so
/// UI can render loaders, errors, and results without ad-hoc boolean
/// flags. Reading [state] inside a reactive scope auto-subscribes the
/// enclosing reaction; use [subscribe] for imperative listeners.
class Task<TParams, TResult, TError> {
  final State<TaskState<TParams, TResult, TError>> _state = State(
    state: TaskIdle<TParams, TResult, TError>(),
  );

  /// Current snapshot of the task's lifecycle state.
  ///
  /// Reading inside a reaction-tracked scope (a `StateObserver` body,
  /// a `Reaction.track` block) auto-subscribes the enclosing reaction
  /// so any transition triggers a re-run. Reads outside a tracked scope
  /// are plain snapshots.
  TaskState<TParams, TResult, TError> get state => _state.state;

  /// Registers [listener] for imperative observation of state
  /// transitions. Returns a disposer that detaches the listener.
  ///
  /// Semantics mirror [State.subscribe]: synchronous dispatch on every
  /// transition where the new value differs from the previous one;
  /// silent no-op after [dispose]. Pass `fireImmediately: true` to seed
  /// the listener with the current value on subscribe.
  StateListenerDisposer subscribe(
    StateChangeListener<TaskState<TParams, TResult, TError>> listener, {
    bool fireImmediately = false,
  }) => _state.subscribe(listener, fireImmediately: fireImmediately);

  final Queue<Future<TResult>> _callQueue = Queue();

  bool _called = false;

  bool _disposed = false;

  Future<void>? _queueTail;

  /// Monotonic supersession token. Bumped by `.latest`'s `_callLatest`
  /// (so superseded runs drop their writes) and by [_supersedeInFlight]
  /// (so `dispose` / `reset` invalidate every in-flight run regardless
  /// of strategy). Each `_executeFn` / `_runLatest` / `_fireDebounced`
  /// / `_fireThrottleTrailing` captures the current value at entry
  /// and skips state writes / completer settles when the captured
  /// value no longer matches.
  int _generation = 0;
  final List<Completer<TResult>> _latestPending = [];

  Timer? _debounceTimer;
  Completer<TResult>? _debounceCompleter;
  TParams? _debouncePendingParams;
  bool _debouncePendingHasParams = false;

  Future<TResult>? _throttleLastFuture;
  Timer? _throttleCooldown;

  Timer? _throttleTrailingWindow;
  Completer<TResult>? _throttleTrailingCompleter;
  TParams? _throttleTrailingParams;
  bool _throttleTrailingHasParams = false;

  final TaskFn<TParams, TResult, TError> _fn;

  final TaskStrategy _strategy;

  final Duration? _autoReset;
  Timer? _autoResetTimer;
  StateListenerDisposer? _autoResetDisposer;

  Task._(
    TaskFn<TParams, TResult, TError> fn,
    TaskStrategy strategy, {
    Duration? autoReset,
  }) : _fn = fn,
       _strategy = strategy,
       _autoReset = autoReset {
    if (_autoReset != null) {
      _autoResetDisposer = _state.subscribe((_, next) {
        _autoResetTimer?.cancel();
        _autoResetTimer = null;
        if (next is TaskDone<TParams, TResult, TError> ||
            next is TaskFailed<TParams, TResult, TError>) {
          _autoResetTimer = Timer(_autoReset, reset);
        }
      }, fireImmediately: false);
    }
  }

  /// Disposes the task's state listeners. In-flight calls still resolve
  /// normally (or reject with [TaskError] for coalesced/debounced work),
  /// but further calls throw [TaskError].
  ///
  /// Do not call directly — use [Store.dispose], which cascades
  /// to every task created via [Store.createTask].
  @internal
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _autoResetDisposer?.call();
    _autoResetDisposer = null;
    _autoResetTimer?.cancel();
    _autoResetTimer = null;

    _supersedeInFlight(TaskError('Task is disposed.'));

    _state.dispose();
  }

  /// Returns the task to [TaskIdle], cancelling pending coalesced
  /// callers and dropping state writes from any in-flight run. The
  /// underlying fn keeps running to completion — Dart has no
  /// cancellation primitive — but its outcome no longer reaches
  /// [state] and no longer settles callers that subscribed before
  /// the reset.
  ///
  /// Pending callers from `.latest`, `.debounce`, and
  /// `.throttle(trailing)` reject with [TaskError]. The `.once` cache
  /// is cleared so the next call re-executes the fn. Strategy-internal
  /// timers (debounce quiet timer, throttle cooldown / window) are
  /// cancelled; the `.queue` chain is broken so subsequent calls start
  /// a fresh sequence.
  ///
  /// Silent no-op after [dispose] and from [TaskIdle] (where the state
  /// transition is suppressed by equality, so subscribers don't fire).
  void reset() {
    if (_disposed) return;

    _autoResetTimer?.cancel();
    _autoResetTimer = null;

    _supersedeInFlight(TaskError('Task was reset.'));

    _state.state = TaskIdle<TParams, TResult, TError>();
  }

  /// Bumps `_generation` (so any in-flight runs drop their state writes
  /// when they resume), cancels every strategy-internal timer, rejects
  /// every pending coalesced caller with [error], and clears the
  /// strategy-state buffers (`_callQueue`, `_queueTail`, `_called`,
  /// debounce / throttle params).
  ///
  /// Shared between [dispose] and [reset]; the callers handle the bits
  /// that differ — `_state.dispose()` vs writing [TaskIdle], and the
  /// `autoReset` listener detach (only on `dispose`).
  void _supersedeInFlight(TaskError error) {
    ++_generation;

    _debounceTimer?.cancel();
    _debounceTimer = null;
    _throttleCooldown?.cancel();
    _throttleCooldown = null;
    _throttleTrailingWindow?.cancel();
    _throttleTrailingWindow = null;

    _settleIncompleteError(_debounceCompleter, error);
    _debounceCompleter = null;
    _settleIncompleteError(_throttleTrailingCompleter, error);
    _throttleTrailingCompleter = null;
    for (final c in _latestPending) {
      _settleIncompleteError(c, error);
    }
    _latestPending.clear();

    _debouncePendingParams = null;
    _debouncePendingHasParams = false;
    _throttleTrailingParams = null;
    _throttleTrailingHasParams = false;
    _throttleLastFuture = null;
    _callQueue.clear();
    _queueTail = null;
    _called = false;
  }

  /// Invokes the task's underlying async function with [params],
  /// returning the eventual [TResult]. Behaviour under concurrent
  /// calls depends on the [TaskStrategy] (see class-level docs).
  ///
  /// Throws [TaskError] synchronously when called after [dispose].
  /// Throws a caller-supplied error of type `TError` through the
  /// returned future when the underlying function fails; non-`TError`
  /// throws propagate as-is (and revert `state` to [TaskIdle] so
  /// observers don't see a stale [TaskPending]).
  Future<TResult> call(TParams params) async {
    if (_disposed) {
      throw TaskError('Task is disposed.');
    }
    switch (_strategy) {
      case TaskStrategyOnce():
        return _callOnce(params);
      case TaskStrategyQueue():
        return _callQueueStrategy(params);
      case TaskStrategyLatest():
        return _callLatest(params);
      case TaskStrategyDebounce(:final duration):
        return _callDebounce(params, duration);
      case TaskStrategyThrottle(:final duration, :final edge):
        return _callThrottle(params, duration, edge);
    }
  }

  Future<TResult> _callOnce(TParams params) {
    if (_called && _state.state is TaskDone<TParams, TResult, TError>) {
      return Future.value(
        (_state.state as TaskDone<TParams, TResult, TError>).result,
      );
    }
    if (_callQueue.isNotEmpty) {
      return _callQueue.first;
    }
    return _executeFn(params);
  }

  Future<TResult> _callQueueStrategy(TParams params) async {
    final prev = _queueTail;
    final myCompletion = Completer<void>();
    _queueTail = myCompletion.future;
    try {
      if (prev != null) {
        try {
          await prev;
        } on Object {
          // Each queued call is independent; swallow prior caller's error.
        }
      }
      return await _executeFn(params);
    } finally {
      myCompletion.complete();
      if (identical(_queueTail, myCompletion.future)) {
        _queueTail = null;
      }
    }
  }

  Future<TResult> _callLatest(TParams params) {
    final myRun = ++_generation;
    final completer = Completer<TResult>();
    _latestPending.add(completer);
    unawaited(_runLatest(params, myRun));
    return completer.future;
  }

  /// Runs the `.latest`-strategy fn in a fire-and-forget future.
  /// Observes a [runId]-tagged supersession: only the run whose id
  /// still matches [_generation] on return is allowed to publish
  /// its outcome (both to [state] and to every pending caller).
  /// Superseded runs return silently — their result/error is dropped
  /// so the caller waits for the latest run instead.
  Future<void> _runLatest(TParams params, int runId) async {
    if (runId == _generation) {
      _state.state = TaskPending<TParams, TResult, TError>(params);
    }

    final fnFuture = Future<TResult>.sync(() => _fn(params));

    try {
      final result = await fnFuture;
      if (runId != _generation) return;
      _state.state = TaskDone<TParams, TResult, TError>(result);
      _flushLatestPending(result: result);
    } on Object catch (error, stackTrace) {
      if (runId != _generation) return;
      if (error is TError) {
        _state.state = TaskFailed<TParams, TResult, TError>(error as TError);
      } else if (_state.state is TaskPending<TParams, TResult, TError>) {
        _state.state = TaskIdle<TParams, TResult, TError>();
      }
      _flushLatestPending(error: error, stackTrace: stackTrace);
    }
  }

  void _flushLatestPending({
    Object? result,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final pending = List<Completer<TResult>>.from(_latestPending);
    _latestPending.clear();
    for (final c in pending) {
      if (c.isCompleted) continue;
      if (error != null) {
        c.completeError(error, stackTrace);
      } else {
        c.complete(result as TResult);
      }
    }
  }

  Future<TResult> _callDebounce(TParams params, Duration duration) {
    _debouncePendingParams = params;
    _debouncePendingHasParams = true;
    _debounceCompleter ??= Completer<TResult>();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(duration, _fireDebounced);
    _state.state = TaskPending<TParams, TResult, TError>(params);
    return _debounceCompleter!.future;
  }

  /// Debounce-timer callback. Runs the fn exactly once with the
  /// most-recent parameters seen during the quiet window and resolves
  /// every coalesced caller with the same outcome. Early-returns after
  /// [dispose] — the completer/param fields are cleared there so we
  /// won't accidentally resurrect stale state.
  Future<void> _fireDebounced() async {
    final completer = _debounceCompleter;
    if (completer == null || !_debouncePendingHasParams) return;

    final myGen = _generation;
    final params = _debouncePendingParams as TParams;
    _debounceTimer = null;
    _debounceCompleter = null;
    _debouncePendingParams = null;
    _debouncePendingHasParams = false;

    try {
      final result = await _executeFn(params);
      if (myGen != _generation) {
        _settleIncompleteError(completer, TaskError('Task was reset.'));
        return;
      }
      _settleIncompleteValue(completer, result);
    } on Object catch (error, stackTrace) {
      if (myGen != _generation) {
        _settleIncompleteError(completer, TaskError('Task was reset.'));
        return;
      }
      _settleIncompleteError(completer, error, stackTrace);
    }
  }

  Future<TResult> _callThrottle(
    TParams params,
    Duration duration,
    ThrottleEdge edge,
  ) {
    switch (edge) {
      case ThrottleEdge.leading:
        return _callThrottleLeading(params, duration);
      case ThrottleEdge.trailing:
        return _callThrottleTrailing(params, duration);
    }
  }

  Future<TResult> _callThrottleLeading(TParams params, Duration duration) {
    final existing = _throttleLastFuture;
    if (existing != null) {
      return existing;
    }

    final fut = _executeFn(params);
    _throttleLastFuture = fut;

    fut.then<void>((_) {}, onError: (Object _, StackTrace _) {}).whenComplete(
      () {
        if (_disposed) return;
        _throttleCooldown = Timer(duration, () {
          _throttleCooldown = null;
          _throttleLastFuture = null;
        });
      },
    );

    return fut;
  }

  Future<TResult> _callThrottleTrailing(TParams params, Duration duration) {
    _throttleTrailingParams = params;
    _throttleTrailingHasParams = true;
    _throttleTrailingCompleter ??= Completer<TResult>();
    _throttleTrailingWindow ??= Timer(duration, _fireThrottleTrailing);
    _state.state = TaskPending<TParams, TResult, TError>(params);
    return _throttleTrailingCompleter!.future;
  }

  /// Trailing-throttle timer callback. Fires at window end with the
  /// most-recent params and resolves every coalesced caller from this
  /// window with a single outcome. Safe after [dispose] — same
  /// completer/params-cleared guard as [_fireDebounced].
  Future<void> _fireThrottleTrailing() async {
    final completer = _throttleTrailingCompleter;
    if (completer == null || !_throttleTrailingHasParams) {
      _throttleTrailingWindow = null;
      return;
    }
    final myGen = _generation;
    final params = _throttleTrailingParams as TParams;
    _throttleTrailingWindow = null;
    _throttleTrailingCompleter = null;
    _throttleTrailingParams = null;
    _throttleTrailingHasParams = false;

    try {
      final result = await _executeFn(params);
      if (myGen != _generation) {
        _settleIncompleteError(completer, TaskError('Task was reset.'));
        return;
      }
      _settleIncompleteValue(completer, result);
    } on Object catch (error, stackTrace) {
      if (myGen != _generation) {
        _settleIncompleteError(completer, TaskError('Task was reset.'));
        return;
      }
      _settleIncompleteError(completer, error, stackTrace);
    }
  }

  Future<TResult> _executeFn(TParams params) async {
    // Capture the generation at entry so concurrent [reset] (which
    // bumps `_generation`) supersedes this run's state writes — the
    // fn keeps running and the caller still gets its result, but
    // `state` no longer reflects an outcome the user explicitly
    // discarded.
    final myGen = _generation;

    // `Future.sync` captures synchronous throws from a non-async [_fn],
    // turning them into a rejected future so the try/finally below
    // still settles state and `_callQueue`.
    final fnFuture = Future<TResult>.sync(() => _fn(params));

    try {
      if (myGen == _generation) {
        _state.state = TaskPending<TParams, TResult, TError>(params);
      }
      _callQueue.add(fnFuture);

      final result = await fnFuture;

      if (myGen == _generation) {
        _state.state = TaskDone<TParams, TResult, TError>(result);
        _called = true;
      }
      return result;
    } on Object catch (error) {
      if (error is TError && myGen == _generation) {
        // The `is TError` check guarantees the cast; the compiler
        // cannot promote through a generic type parameter, hence the
        // explicit `as`.
        _state.state = TaskFailed<TParams, TResult, TError>(error as TError);
      }
      rethrow;
    } finally {
      _callQueue.remove(fnFuture);

      // If neither TaskDone nor TaskFailed landed (non-TError throw),
      // revert to TaskIdle so observers don't see a stale TaskPending.
      // Gen guard prevents reverting state that a post-reset run is
      // legitimately driving.
      if (myGen == _generation &&
          _callQueue.isEmpty &&
          _state.state is TaskPending<TParams, TResult, TError>) {
        _state.state = TaskIdle<TParams, TResult, TError>();
      }
    }
  }

  void _settleIncompleteValue(Completer<TResult> c, TResult value) {
    if (!c.isCompleted) c.complete(value);
  }

  void _settleIncompleteError(
    Completer<TResult>? c,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (c == null || c.isCompleted) return;
    c.completeError(error, stackTrace);
  }
}

/// A [Task] that takes no parameter. Call it with `task()` — no `null`
/// required. Created via [createVoid] or [Store.createVoidTask].
///
/// Internally a thin subclass over `Task<void, TResult, TError>` that turns
/// the required positional parameter into an optional one.
class VoidTask<TResult, TError> extends Task<void, TResult, TError> {
  VoidTask._(
    Future<TResult> Function() fn,
    TaskStrategy strategy, {
    Duration? autoReset,
  }) : super._((_) => fn(), strategy, autoReset: autoReset);

  @override
  Future<TResult> call([void params]) => super.call(null);
}

/// Framework factory invoked by [Store.createTask]. Not intended for
/// direct use — user code constructs tasks through the Store surface so
/// that lifecycle ownership + dispose cascade stay consistent.
@internal
Task<TParams, TResult, TError> create<
  TParams extends Object?,
  TResult extends Object?,
  TError extends Object?
>({
  required TaskFn<TParams, TResult, TError> fn,
  required TaskStrategy strategy,
  Duration? autoReset,
}) {
  return Task._(fn, strategy, autoReset: autoReset);
}

/// Framework factory invoked by [Store.createVoidTask]. Not intended
/// for direct use — see [create] for the rationale.
@internal
VoidTask<TResult, TError>
createVoid<TResult extends Object?, TError extends Object?>({
  required Future<TResult> Function() fn,
  required TaskStrategy strategy,
  Duration? autoReset,
}) {
  return VoidTask._(fn, strategy, autoReset: autoReset);
}
