part of './core.dart';

/// Framework-internal bag of per-context mutable state. Never referenced
/// outside the package — the reactive core isolates batch counters,
/// pending reactions, and the currently tracked reaction here so a
/// [Context] instance can be swapped or reset without reshaping its
/// public surface.
class _ContextState {
  int batch = 0;

  Set<Reaction> pendingReactions = {};

  /// Ping-pong buffer paired with [pendingReactions] in [Context.endBatch].
  /// Held here (rather than re-allocated each drain) so a batch with no
  /// chained reactions allocates nothing beyond the initial two sets.
  Set<Reaction> pendingBuffer = {};

  Reaction? trackingReaction;

  /// Set while an outer [Context.endBatch] is mid-drain. Blocks nested
  /// drains triggered by a reaction's own `reportChanged` — otherwise
  /// a cyclic reactive graph recurses through `reportChanged → startBatch
  /// → endBatch → drain` instead of bouncing pending-reactions through
  /// the ping-pong buffer, and the per-invocation `maxIterations` guard
  /// never sees the cycle.
  bool draining = false;
}

/// Runtime configuration for a reactive [Context].
///
/// Primarily exposes [maxIterations] — the convergence budget applied
/// to each batch drain. Use [ReactiveConfig.defaults] for the standard
/// 100-iteration limit, or construct a custom instance for tests and
/// specialised workloads.
class ReactiveConfig {
  /// Default configuration, shared by [globalContext]. 100 iterations
  /// is generous for legitimate cascades (deep reactive graphs rarely
  /// go past single digits) while short enough to fail fast on cycles.
  static final ReactiveConfig defaults = ReactiveConfig(maxIterations: 100);

  /// Maximum number of drain iterations [Context.endBatch] performs
  /// before giving up and throwing [ReactiveCycleError]. Each iteration
  /// fires all currently-pending reactions; if any of those schedule
  /// new pending reactions, another iteration runs. Non-converging
  /// configurations (A invalidates B invalidates A) are bounded here.
  final int maxIterations;

  /// Creates a configuration with an explicit iteration limit. Prefer
  /// [ReactiveConfig.defaults] unless you have a measured reason to
  /// diverge.
  ReactiveConfig({required this.maxIterations});
}

/// Root of the reactive graph — owns batching, the tracking stack, and
/// the pending-reaction queue drained on [endBatch].
///
/// Most apps use the package-wide [globalContext]; construct a custom
/// [Context] only to isolate reactive state (e.g. parallel test
/// environments or multi-tenant scenarios where batches must not mix).
class Context {
  final ReactiveConfig _config;

  final _ContextState _state = _ContextState();

  /// Creates a standalone context with the supplied [config]. Atoms and
  /// reactions bound to this context don't interact with state in any
  /// other context.
  Context({required ReactiveConfig config}) : _config = config;

  /// Clears batch counter, pending reactions, and currently tracked
  /// reaction. Intended for test isolation when [globalContext] is shared
  /// across test cases — call this in `tearDown` to drop residual state
  /// from the previous test.
  ///
  /// Does not disconnect [Atom] observers; that is handled by
  /// [Reaction.clear].
  void reset() {
    _state.batch = 0;
    _state.pendingReactions = {};
    _state.pendingBuffer = {};
    _state.trackingReaction = null;
    _state.draining = false;
  }

  /// Increments the batch counter. Mutations made between
  /// [startBatch] and the matching [endBatch] are coalesced — pending
  /// reactions only drain when the counter returns to zero. Calls
  /// nest safely; only the outermost [endBatch] drains.
  void startBatch() {
    _state.batch++;
  }

  /// Decrements the batch counter. When it returns to zero, drains the
  /// pending-reaction queue with a ping-pong buffer: each iteration
  /// fires every currently-pending reaction; reactions scheduled by
  /// those fires land in the next iteration's queue. Stops and throws
  /// [ReactiveCycleError] after [ReactiveConfig.maxIterations] iterations
  /// without convergence.
  void endBatch() {
    if (--_state.batch != 0) return;

    // Reaction fires can call `reportChanged` on other atoms, which
    // brings batch back to 0 and would recursively re-enter this drain.
    // That recursion bypasses the per-invocation `maxIterations` guard,
    // so cyclic graphs blow the stack instead of raising
    // [ReactiveCycleError]. Defer any re-entered drain: the outer loop
    // already owns the ping-pong buffers and will pick up the newly
    // added reactions in its next iteration (counted against
    // maxIterations).
    if (_state.draining) return;
    _state.draining = true;

    // Ping-pong drain: `current` holds the reactions we're firing right
    // now; `next` receives any new reactions scheduled by a callback
    // (via `_addPendingReaction`). After each iteration we swap them,
    // reusing both sets so a stable drain allocates zero. `finally`
    // restores `_state.pendingBuffer` on the throw path too.
    var current = _state.pendingReactions;
    var next = _state.pendingBuffer;
    _state.pendingReactions = next;

    var iterations = 0;
    try {
      while (current.isNotEmpty) {
        if (++iterations == _config.maxIterations) {
          final failingReaction = current.first;
          current.clear();
          next.clear();
          throw ReactiveCycleError(
            reactionName: failingReaction.name,
            maxIterations: _config.maxIterations,
          );
        }

        for (final reaction in current) {
          // Swallow handled inside `_fireInvalidate` via the reaction's
          // optional onError hook; keep an outer catch as defense-in-depth
          // so sibling reactions still run if the hook itself throws.
          try {
            reaction._fireInvalidate();
          } on Object {
            // Already reported via Reaction.onError if configured.
          }
        }
        current.clear();

        final tmp = current;
        current = next;
        next = tmp;
        _state.pendingReactions = next;
      }
    } finally {
      _state.pendingBuffer = current;
      _state.draining = false;
    }
  }

  void _addPendingReaction(Reaction reaction) {
    _state.pendingReactions.add(reaction);
  }

  void _propagateChanged(Atom atom) {
    final observers = atom._observers;
    if (observers.length == 1) {
      observers.first._onBecomeStale();
      return;
    }
    for (final observer in observers) {
      observer._onBecomeStale();
    }
  }

  T _trackReaction<T>(Reaction reaction, T Function() fn) {
    final prevReaction = _startTracking(reaction);
    try {
      return fn();
    } finally {
      _endTracking(reaction, prevReaction);
    }
  }

  void _clearAtoms(Reaction reaction) {
    final observables = reaction._atoms;
    if (observables.isEmpty) return;
    for (final x in observables) {
      x._removeObserver(reaction);
    }
    observables.clear();
  }

  void _endTracking(Reaction currentReaction, Reaction? prevReaction) {
    _state.trackingReaction = prevReaction;
    _updateUsedAtoms(currentReaction);
  }

  void _reportObserved(Atom atom) {
    final reaction = _state.trackingReaction;

    if (reaction != null) {
      reaction._newAtoms.add(atom);
    }
  }

  Reaction? _startTracking(Reaction reaction) {
    final prevReaction = _state.trackingReaction;
    _state.trackingReaction = reaction;

    reaction._newAtoms.clear();

    return prevReaction;
  }

  void _updateUsedAtoms(Reaction reaction) {
    // Single-pass diff + set swap: reuse the old `_atoms` set as the next
    // `_newAtoms` buffer so a stable reaction allocates nothing here. Two
    // Set.difference calls + an empty-set literal allocated three sets per
    // track() otherwise — this runs on every port apply.
    final oldAtoms = reaction._atoms;
    final newAtoms = reaction._newAtoms;

    for (final atom in oldAtoms) {
      if (!newAtoms.contains(atom)) atom._removeObserver(reaction);
    }
    for (final atom in newAtoms) {
      if (!oldAtoms.contains(atom)) atom._addObserver(reaction);
    }

    oldAtoms.clear();
    reaction._atoms = newAtoms;
    reaction._newAtoms = oldAtoms;
  }
}
