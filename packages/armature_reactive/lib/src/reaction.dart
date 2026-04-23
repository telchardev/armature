part of './core.dart';

/// Fired when a tracked atom changes — the reactive graph's "re-run me"
/// signal. Handlers are responsible for recomputing derived state,
/// re-applying ports, or whatever downstream work the reaction owns.
typedef OnInvalidateCallback = void Function();

/// Error reporter for exceptions thrown inside [OnInvalidateCallback].
/// When unset, exceptions are swallowed so sibling reactions keep
/// firing; with it, the callback receives the error plus its stack
/// trace for centralised logging.
typedef OnReactionErrorCallback = void Function(Object error, StackTrace st);

/// Unit of reactive computation — tracks a set of [Atom]s and runs
/// [OnInvalidateCallback] whenever any of them changes.
///
/// A reaction acquires its dependency set by wrapping the observing
/// computation in [track]. Subsequent atom mutations enqueue the
/// reaction on its [Context]; the context drains the queue on
/// [Context.endBatch], firing [OnInvalidateCallback] once per pending
/// reaction (with cycle protection).
///
/// Call [clear] when the reaction should stop observing — it detaches
/// from every tracked atom and leaves the instance usable for a fresh
/// [track] cycle.
class Reaction {
  static int _counter = 0;

  Set<Atom> _atoms = {};

  final Context _context;

  final String _name;

  Set<Atom> _newAtoms = {};

  final OnInvalidateCallback _onInvalidate;

  final OnReactionErrorCallback? _onError;

  /// Creates a reaction bound to [context] (defaults to
  /// [globalContext]). [onInvalidate] fires whenever a tracked atom
  /// changes; [onError] receives exceptions thrown from [onInvalidate]
  /// (otherwise they're swallowed so sibling reactions still run).
  /// [name] is used in diagnostic output (e.g. [ReactiveCycleError]);
  /// an auto-generated one is assigned if omitted.
  Reaction({
    String? name,
    Context? context,
    required OnInvalidateCallback onInvalidate,
    OnReactionErrorCallback? onError,
  }) : _name = name != null
           ? "@armature_reaction_$name"
           : "@armature_reaction_${++_counter}",
       _context = context ?? globalContext,
       _onInvalidate = onInvalidate,
       _onError = onError;

  /// Detaches this reaction from every atom it was observing and drops
  /// its tracking sets. Safe to call multiple times; the reaction
  /// remains usable — the next [track] call re-establishes a fresh
  /// dependency set.
  void clear() {
    _context
      ..startBatch()
      .._clearAtoms(this)
      ..endBatch();
  }

  /// Display name — either the one passed to the constructor (prefixed
  /// for clarity) or an auto-generated sequential tag.
  String get name => _name;

  /// Runs [fn] with this reaction as the ambient tracking scope.
  ///
  /// Any [Atom.reportObserved] calls that fire during [fn] record a
  /// dependency; on completion, the reaction's observed set is
  /// diff'ed against the previous run (new atoms subscribed, dropped
  /// atoms unsubscribed) in a single pass.
  ///
  /// Exceptions propagate out of [track]; the tracking stack is
  /// always restored even on throw, so subsequent reactions in the
  /// same frame see a clean ambient.
  T track<T>(T Function() fn) {
    return _context._trackReaction<T>(this, fn);
  }

  void _onBecomeStale() {
    _context._addPendingReaction(this);
  }

  /// Invoked by the context when this reaction's dependencies change.
  /// Swallows listener exceptions so they don't break sibling reactions
  /// scheduled in the same batch; reports them through [OnReactionErrorCallback]
  /// if provided.
  void _fireInvalidate() {
    try {
      _onInvalidate();
    } on Object catch (e, st) {
      _onError?.call(e, st);
    }
  }
}
