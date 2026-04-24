import 'package:armature_reactive/armature_reactive.dart' show Atom;
import 'package:meta/meta.dart' show internal;

/// Invoked by [State.subscribe] on every state transition.
///
/// Receives the value before the write and the value after — useful
/// for diffing (e.g. "only fire when the `user` field changed").
/// Listeners run synchronously from [State.state]'s setter.
typedef StateChangeListener<TState> =
    void Function(TState prevState, TState state);

/// Produces the next state from the current state. Passed to
/// [State.update] (and re-exported via [Store.update]) for functional
/// updates that don't need a temp variable.
typedef StateUpdateCallback<TState> = TState Function(TState state);

/// Disposer returned by [State.subscribe]. Call to remove the listener;
/// idempotent — repeated calls are safe no-ops.
typedef StateListenerDisposer = void Function();

/// Framework-internal observable value holder backing every [Store].
///
/// Wraps a mutable `_state` field plus an [Atom] for reactive tracking
/// and a set of imperative [StateChangeListener]s. Reads route through
/// the atom (so reaction scopes auto-subscribe); writes fire listeners
/// and invalidate the atom only when the new value differs from the
/// current one (by `==`).
///
/// Not exported from `armature.dart` — user code interacts through
/// `Store<TState>.state` / `Store<TState>.subscribe` instead.
@internal
class State<TState> {
  final Atom _atom = Atom();

  final Set<StateChangeListener<TState>> _changeStateListeners = {};

  TState _state;

  bool _disposed = false;

  /// Creates a holder with the given initial [state].
  State({required TState state}) : _state = state;

  /// Current state. Reading inside a reaction-tracked scope
  /// (e.g. a port handler body) registers the enclosing reaction as
  /// an observer — subsequent writes will invalidate it.
  TState get state {
    _atom.reportObserved();
    return _state;
  }

  /// Writes a new state. No-op when the value is `==` to the current
  /// state, or when this instance has been disposed — in both cases
  /// listeners and atom observers stay untouched. Otherwise fires
  /// every [StateChangeListener] in insertion order and marks the
  /// atom as changed.
  set state(TState state) {
    if (_disposed) {
      return;
    }
    if (state != _state) {
      final prevState = _state;
      _state = state;
      _notifyListeners(prevState, state);
      _atom.reportChanged();
    }
  }

  /// Subscribes [listener] for future state transitions. When
  /// [fireImmediately] is `true` the listener also fires once
  /// synchronously with `(current, current)` so the caller can
  /// seed its own side effects with the present value.
  ///
  /// Returns a disposer that detaches the listener. **Silent no-op
  /// after [dispose]** — the returned disposer closes over nothing
  /// and the listener never fires, including the `fireImmediately`
  /// pass. Treat this as a defensive no-op for late subscribers on
  /// a torn-down state, not a supported pattern.
  StateListenerDisposer subscribe(
    StateChangeListener<TState> listener, {
    required bool fireImmediately,
  }) {
    if (_disposed) {
      return () {};
    }

    _changeStateListeners.add(listener);

    if (fireImmediately) {
      listener(_state, _state);
    }

    return () {
      _changeStateListeners.remove(listener);
    };
  }

  /// Drops every registered listener, tears down the reactive atom,
  /// and rejects subsequent writes. Idempotent — double-dispose is
  /// safe. The underlying `_state` value is preserved so late
  /// readers still see the final snapshot.
  void dispose() {
    _disposed = true;
    _changeStateListeners.clear();
    _atom.dispose();
  }

  /// Functional update — computes the next state from the current
  /// one via [callback] and assigns.
  ///
  /// Reads `_state` directly (not via the `state` getter) so the
  /// update call itself doesn't register the caller as a reactive
  /// observer — an `update` is a write, not an observation. Delegates
  /// to the `state` setter for the actual write so equality filtering,
  /// listener dispatch, and atom invalidation stay consistent with
  /// direct `state = value` writes.
  void update(StateUpdateCallback<TState> callback) {
    state = callback(_state);
  }

  /// Fires change listeners in registration order.
  ///
  /// Allocation policy: for the single-listener case (the overwhelmingly
  /// common shape in practice — one `StateObserver`, one subscriber)
  /// we skip the defensive snapshot and call the listener directly.
  /// Multi-listener states iterate a snapshot so listeners are free
  /// to subscribe / unsubscribe during their own invocation (classic
  /// one-shot listener pattern).
  void _notifyListeners(TState prevState, TState state) {
    final count = _changeStateListeners.length;
    if (count == 0) return;
    if (count == 1) {
      _changeStateListeners.first(prevState, state);
      return;
    }
    for (final listener in _changeStateListeners.toList(growable: false)) {
      listener(prevState, state);
    }
  }
}
