part of './core.dart';

/// Reactive signal primitive — a value-less node that tracks which
/// [Reaction]s depend on it and notifies them on change.
///
/// Atoms are the low-level building block of the reactive graph;
/// higher-level abstractions (`State<T>`, `Store`) embed one to turn
/// plain reads/writes into tracked observations. Pair an atom with
/// your own storage field and call [reportObserved] on read,
/// [reportChanged] on write.
class Atom {
  final Context _context;

  final Set<Reaction> _observers = {};

  bool _disposed = false;

  /// Creates an atom bound to [context] — defaults to [globalContext]
  /// for single-context apps. Use a custom context to isolate
  /// reactive state (e.g. parallel test environments).
  Atom({Context? context}) : _context = context ?? globalContext;

  /// Detaches this atom from every observing [Reaction] and drops the
  /// observer set. Subsequent [reportChanged] / [reportObserved] calls
  /// are no-ops; safe to call multiple times.
  ///
  /// Does not emit a final change notification — this is a teardown,
  /// not a flush. Observers never see a disposal event.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Iterate `_observers` directly — the loop body only mutates each
    // reaction's `_atoms` set, never `_observers`, so Dart's
    // concurrent-modification check stays green without a defensive copy.
    for (final reaction in _observers) {
      reaction._atoms.remove(this);
    }
    _observers.clear();
  }

  /// Signals that the value backing this atom has changed. Schedules
  /// every observing reaction for invalidation on the next batch
  /// drain. No-op if the atom is disposed or has no observers —
  /// the second case short-circuits the batch machinery entirely so
  /// uncontended writes stay cheap.
  void reportChanged() {
    if (_disposed) return;
    if (_observers.isEmpty) return;
    _context
      ..startBatch()
      .._propagateChanged(this)
      ..endBatch();
  }

  /// Signals that the value backing this atom was read while a
  /// [Reaction] was tracking. When called outside a tracking scope
  /// (no ambient reaction), this is a no-op. No-op when disposed.
  void reportObserved() {
    if (_disposed) return;
    _context._reportObserved(this);
  }

  void _addObserver(Reaction reaction) {
    _observers.add(reaction);
  }

  void _removeObserver(Reaction reaction) {
    _observers.remove(reaction);
  }
}
