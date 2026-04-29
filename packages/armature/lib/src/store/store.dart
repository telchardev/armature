import 'dart:async' show runZoned, Zone;

import 'package:meta/meta.dart' show internal, mustCallSuper, protected;

import '../errors.dart' show FeatureConfigurationError;
import './state.dart'
    show State, StateUpdateCallback, StateChangeListener, StateListenerDisposer;
import './task.dart'
    show Task, TaskStrategy, TaskFn, VoidTask, create, createVoid;

/// Framework-internal aggregate thrown by [Store.dispose] when
/// **multiple** owned [Task]s threw during teardown. A single task
/// dispose error is rethrown as-is with its original stack trace;
/// this aggregate only appears for two or more captured errors.
@internal
class TaskDisposeErrors implements Exception {
  /// Captured throws, in dispose order. Each entry pairs the thrown
  /// object with its stack trace.
  final List<({Object error, StackTrace stackTrace})> errors;

  TaskDisposeErrors(List<({Object error, StackTrace stackTrace})> errors)
    : errors = List.unmodifiable(errors);

  @override
  String toString() {
    final buf = StringBuffer(
      'TaskDisposeErrors: ${errors.length} task disposal errors during '
      'Store.dispose():\n',
    );
    for (var i = 0; i < errors.length; i++) {
      buf.writeln('  [$i] ${errors[i].error}');
    }
    return buf.toString();
  }
}

/// Base class for feature stores with reactive state.
///
/// Subclass to hold the state of a feature slice plus the [Task]s that
/// mutate it. Stores participate in two orthogonal mechanisms:
///
/// * **Reactive reads** — reading [state] inside a reaction-tracked
///   scope (a `StateObserver` body, a port handler) auto-subscribes
///   the enclosing reaction, so writes automatically invalidate it.
/// * **Imperative subscribers** — [subscribe] registers a classic
///   `void Function(prev, next)` listener for side-effect style
///   integration.
///
/// ```dart
/// class UserStore extends Store<UserState> {
///   UserStore() : super(state: const UserState());
///
///   late final loadProfile = createTask(
///     fn: (String userId) async => /* ... */,
///     strategy: .once,
///   );
///
///   void logout() => update((s) => s.copyWith(user: null));
/// }
/// ```
///
/// **Lifecycle** — a store constructed inside a feature's `stores`
/// factory is auto-registered with that feature via zone tracking and
/// disposed when the container tears the feature down. Stores
/// constructed outside a `stores` factory (e.g. in tests, or standalone
/// Dart utilities) are not registered; the owner is responsible for
/// calling [dispose].
abstract class Store<TState extends Object?> {
  static final _zoneKey = Object();

  /// Runs [fn] and collects every [Store] instance constructed during
  /// it, keyed by `runtimeType`. Used by the container to populate the
  /// per-feature store map from a user-supplied `stores` factory
  /// without an explicit `register()` API.
  ///
  /// **Caller contract:** [fn] must be synchronous. Any microtask
  /// scheduled inside [fn] that outlives its own frame will leak into
  /// the current feature's store map — because the zone marker stays
  /// active for the whole async continuation. Feature `stores`
  /// factories respect this by construction (they are sync).
  @internal
  static (T result, Map<Type, Store> stores) track<T>(T Function() fn) {
    final map = <Type, Store>{};
    final result = runZoned(fn, zoneValues: {_zoneKey: map});
    return (result, map);
  }

  final State<TState> _internalState;

  final List<Task<dynamic, dynamic, dynamic>> _tasks = [];

  /// Creates a store initialised with [state]. If this constructor runs
  /// inside a [Store.track] scope (i.e. inside a feature's `stores`
  /// factory) the instance is automatically collected into the active
  /// store map. Duplicate registrations — two Stores of the same
  /// runtime type in one feature — throw [FeatureConfigurationError]
  /// before construction completes.
  Store({required TState state}) : _internalState = State(state: state) {
    final map = Zone.current[_zoneKey] as Map<Type, Store>?;
    if (map == null) {
      return;
    }
    if (map.containsKey(runtimeType)) {
      throw FeatureConfigurationError(
        'Duplicate Store of type $runtimeType in the same feature. '
        'Each feature may hold only one store per runtime type; '
        'use distinct subclasses if you need multiple.',
      );
    }
    map[runtimeType] = this;
  }

  /// Current state snapshot.
  ///
  /// Reading inside a reaction-tracked scope (a `StateObserver` body,
  /// a port handler, a `Reaction.track` block) auto-subscribes the
  /// enclosing reaction so that the reaction re-runs when subsequent
  /// writes flip the value. Reading outside a tracked scope is a plain
  /// read — no subscription is registered.
  TState get state {
    return _internalState.state;
  }

  /// Writes a new state value. `@protected` — only the store's own
  /// methods (or subclass methods) may mutate; external callers must
  /// go through the store's public action methods.
  ///
  /// Equality-filtered: when `state == current` the write is a no-op
  /// (no listener dispatch, no reaction invalidation). After [dispose]
  /// writes are silently ignored — the store settles at its final
  /// snapshot.
  @protected
  set state(TState state) {
    _internalState.state = state;
  }

  /// Creates a parameterised async [Task] with an observable state
  /// machine (`TaskIdle → TaskPending → TaskDone|TaskFailed`).
  ///
  /// [strategy] defaults to [TaskStrategy.queue] — FIFO serialisation,
  /// the most common call pattern. Override for other semantics:
  /// `.once` for deduplicated one-shot requests, `.latest` for
  /// supersede-in-flight, `.debounce(d)` for coalescing rapid calls,
  /// `.throttle(d)` for rate-limited fire.
  ///
  /// Pass [autoReset] to schedule an automatic transition back to
  /// [TaskIdle] after the given duration has elapsed in [TaskDone] or
  /// [TaskFailed]. The timer cancels and re-arms on every state
  /// transition, so a fresh `call()` while the timer is waiting starts
  /// a new lifecycle without flickering through [TaskIdle].
  ///
  /// **Picking `TError`** — the third generic gates which thrown values
  /// land in [TaskFailed] (sticky, observable in UI) vs propagate from
  /// `await task(...)` and revert state to [TaskIdle]. Common choices:
  ///
  /// * `Exception` — default for API / IO. Domain failures stick;
  ///   `Error` subclasses (programming bugs) propagate.
  /// * a domain class — only that family sticks; UI pattern-matches
  ///   on specific cases.
  /// * `Never` — nothing sticks; any throw escalates. Use when the
  ///   fn isn't expected to fail in normal flow.
  /// * `Object` — everything sticks. Last resort.
  ///
  /// The task is owned by this store — [dispose] cascades to it,
  /// rejecting any in-flight calls with [TaskError].
  @protected
  Task<TParams, TResult, TError> createTask<
    TParams extends Object?,
    TResult extends Object?,
    TError extends Object?
  >({
    required TaskFn<TParams, TResult, TError> fn,
    TaskStrategy strategy = TaskStrategy.queue,
    Duration? autoReset,
  }) {
    final task = create<TParams, TResult, TError>(
      fn: fn,
      strategy: strategy,
      autoReset: autoReset,
    );
    _tasks.add(task);
    return task;
  }

  /// Creates a no-parameter [VoidTask]. Callers invoke it with `task()`
  /// — no `null` argument required — and compile-time safety is
  /// preserved for parameterised tasks created via [createTask].
  ///
  /// [strategy] defaults to [TaskStrategy.queue]; accepts the same
  /// variants as [createTask]. Pass [autoReset] to schedule an
  /// automatic transition back to [TaskIdle] after the given duration
  /// in [TaskDone] / [TaskFailed]. [dispose] cascades to this task too.
  @protected
  VoidTask<TResult, TError>
  createVoidTask<TResult extends Object?, TError extends Object?>({
    required Future<TResult> Function() fn,
    TaskStrategy strategy = TaskStrategy.queue,
    Duration? autoReset,
  }) {
    final task = createVoid<TResult, TError>(
      fn: fn,
      strategy: strategy,
      autoReset: autoReset,
    );
    _tasks.add(task);
    return task;
  }

  /// Tears down the store: disposes its [State], disposes every owned
  /// [Task] (rejecting in-flight calls with [TaskError]), and clears
  /// the internal task list. Idempotent. Subclasses that override
  /// must invoke `super.dispose()` (`@mustCallSuper`).
  ///
  /// Each owned task's `dispose()` is wrapped in try/catch so one
  /// misbehaving task never prevents siblings from being torn down.
  /// After the pass: 0 errors → return; 1 → rethrow with the
  /// original stack trace; ≥ 2 → throw [TaskDisposeErrors].
  @mustCallSuper
  void dispose() {
    _internalState.dispose();
    final errors = <({Object error, StackTrace stackTrace})>[];
    for (final task in _tasks) {
      try {
        task.dispose();
      } on Object catch (e, st) {
        errors.add((error: e, stackTrace: st));
      }
    }
    _tasks.clear();
    if (errors.isEmpty) return;
    if (errors.length == 1) {
      Error.throwWithStackTrace(errors.first.error, errors.first.stackTrace);
    }
    throw TaskDisposeErrors(errors);
  }

  /// Subscribes [listener] to state transitions. [listener] fires
  /// synchronously on every write where `newState != currentState`;
  /// equality-suppressed writes don't emit.
  ///
  /// When [fireImmediately] is `true` (default `false`) the listener
  /// also fires once during `subscribe` with `(current, current)`, so
  /// the caller can seed its side effect with the present value.
  ///
  /// Returns a disposer that detaches the listener. **Silent no-op
  /// after [dispose]** — late subscriptions return a no-op disposer
  /// without firing, matching [State.subscribe]'s defensive contract.
  StateListenerDisposer subscribe(
    StateChangeListener<TState> listener, {
    bool fireImmediately = false,
  }) {
    return _internalState.subscribe(listener, fireImmediately: fireImmediately);
  }

  /// Functional state update — applies [callback] to the current
  /// value and writes the result.
  ///
  /// Equivalent to `state = callback(state)` but reads the underlying
  /// field directly (bypassing [state]'s reactive `reportObserved`):
  /// an `update` is a write, not an observation, so the caller must
  /// not be registered as a reactive dependent. Listener dispatch +
  /// equality filtering run the same way as direct `state = ...`
  /// writes.
  @protected
  void update(StateUpdateCallback<TState> callback) {
    _internalState.update(callback);
  }

  /// Subscribes [listener] to a derived projection of [state]; fires
  /// only when the selected value changes by `==` (or by [equals] if
  /// supplied). Use [subscribe] for the raw whole-state signal; use
  /// this when you want a field, record, or view-model.
  ///
  /// ```dart
  /// final unsubscribe = userStore.subscribeSelect(
  ///   (state) => state.user?.id,
  ///   (prev, next) => analytics.identify(next),
  /// );
  /// ```
  ///
  /// Pass [equals] for content-based equality on collections (`List`,
  /// `Map`, `Set`) — e.g. `listEquals` from `flutter/foundation`:
  ///
  /// ```dart
  /// store.subscribeSelect(
  ///   (s) => s.items,
  ///   (_, next) => onItemsChanged(next),
  ///   equals: listEquals,
  /// );
  /// ```
  ///
  /// When [fireImmediately] is `true` the listener fires once with
  /// `(currentSelection, currentSelection)`. Returns a disposer;
  /// silent no-op after [dispose].
  StateListenerDisposer subscribeSelect<R>(
    R Function(TState state) selector,
    void Function(R prev, R next) listener, {
    bool Function(R a, R b)? equals,
    bool fireImmediately = false,
  }) {
    final eq = equals ?? _defaultEquals<R>;
    var lastSelection = selector(state);
    if (fireImmediately) {
      listener(lastSelection, lastSelection);
    }
    return subscribe((_, next) {
      final nextSelection = selector(next);
      if (eq(lastSelection, nextSelection)) return;
      final prevSelection = lastSelection;
      lastSelection = nextSelection;
      listener(prevSelection, nextSelection);
    });
  }
}

/// Default equality used by [Store.subscribeSelect] when the caller
/// doesn't pass a custom comparator. Hoisted to a top-level function
/// so we don't allocate a fresh closure per call.
bool _defaultEquals<R>(R a, R b) => a == b;
