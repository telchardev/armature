import 'dart:async' show runZoned, Zone;

import 'package:meta/meta.dart' show internal, mustCallSuper, protected;

import '../errors.dart' show FeatureConfigurationError;
import './state.dart'
    show State, StateUpdateCallback, StateChangeListener, StateListenerDisposer;
import './task.dart'
    show Task, TaskStrategy, TaskFn, VoidTask, create, createVoid;

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
  }) {
    final task = create<TParams, TResult, TError>(fn: fn, strategy: strategy);
    _tasks.add(task);
    return task;
  }

  /// Creates a no-parameter [VoidTask]. Callers invoke it with `task()`
  /// — no `null` argument required — and compile-time safety is
  /// preserved for parameterised tasks created via [createTask].
  ///
  /// [strategy] defaults to [TaskStrategy.queue]; accepts the same
  /// variants as [createTask]. [dispose] cascades to this task too.
  @protected
  VoidTask<TResult, TError>
  createVoidTask<TResult extends Object?, TError extends Object?>({
    required Future<TResult> Function() fn,
    TaskStrategy strategy = TaskStrategy.queue,
  }) {
    final task = createVoid<TResult, TError>(fn: fn, strategy: strategy);
    _tasks.add(task);
    return task;
  }

  /// Tears down the store: disposes its [State] (detaches every
  /// subscriber and the reactive atom), disposes every owned [Task]
  /// (rejecting in-flight calls with [TaskError]), and clears the
  /// internal task list.
  ///
  /// Idempotent — calling [dispose] twice is safe (underlying
  /// components re-enter their own `_disposed` short-circuits).
  /// Subclasses that need custom teardown should override this
  /// method and invoke `super.dispose()` (`@mustCallSuper`).
  @mustCallSuper
  void dispose() {
    _internalState.dispose();
    for (final task in _tasks) {
      task.dispose();
    }
    _tasks.clear();
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
}
