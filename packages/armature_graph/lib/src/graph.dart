import 'dart:collection' show Queue, UnmodifiableListView, UnmodifiableSetView;

import './node.dart' show GraphNode, GraphNodeValue;
import './semaphore.dart' show Semaphore;
import './status.dart' show GraphNodeStatus, GraphVisitor;

/// Base class for every structural / cascade failure the [Graph] surfaces.
///
/// Sealed so callers can catch the whole family with a single `on
/// GraphError` clause and exhaustively switch on the subtype — the three
/// concrete variants are [GraphCycleError], [GraphNodeNotFoundError],
/// and [GraphFixedPointError].
sealed class GraphError extends Error {
  /// Human-readable description of the failure.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown at graph construction when the parent/child edges form a cycle.
final class GraphCycleError extends GraphError {
  @override
  final String message;

  GraphCycleError(this.message);
}

/// Thrown at graph construction when a node's declared parent (required or
/// optional) is not present in the `nodeValues` list passed to [Graph].
final class GraphNodeNotFoundError extends GraphError {
  final String missing;
  final String referencedBy;

  GraphNodeNotFoundError({required this.missing, required this.referencedBy});

  @override
  String get message =>
      '"$missing" is referenced as a parent of "$referencedBy" but is '
      'not listed in nodeValues.';
}

/// Thrown by [Graph.resolve] when the cascade chain keeps regenerating
/// new cascades past the configured `drainIterationLimit`. Indicates
/// that a visitor callback is toggling targets in a cycle that never
/// stabilises.
final class GraphFixedPointError extends GraphError {
  @override
  final String message;

  GraphFixedPointError(this.message);
}

/// DAG of [GraphNodeValue]s with a three-state cascade state machine.
///
/// Graph owns:
///   * Structure (parent/child edges, cycle detection at construction).
///   * Per-node status ([GraphNodeStatus]).
///   * Cascade ordering: parallel sibling activation with parent-before-
///     child ordering; reverse-topological deactivation.
///   * Serialization: [resolve] and [recompute] chain through a single
///     in-flight cascade future so rapid calls are observed in order.
///   * Centralized error reporting: all visitor exceptions are caught
///     and routed through [GraphVisitor.onError].
///
/// The visitor (see [GraphVisitor]) supplies the policy (target state)
/// and side effects (on-activate / on-deactivate).
class Graph<TNodeValue extends GraphNodeValue> {
  final List<TNodeValue> _nodeValues;

  final Map<TNodeValue, GraphNode<TNodeValue>> _nodes = {};

  final Set<GraphNode<TNodeValue>> _rootNodes = {};

  final Map<TNodeValue, GraphNodeStatus> _statuses = {};

  final GraphVisitor<TNodeValue> _visitor;

  /// Optional concurrency cap on parallel `onActivate` invocations.
  /// Declared once at construction; `null` means unbounded.
  final Semaphore? _activationLimit;

  /// Upper bound on the drain loop in [resolve]. Configured once at
  /// construction; if the cascade chain keeps regenerating past this
  /// many iterations, [resolve] throws [GraphFixedPointError].
  final int _drainIterationLimit;

  Future<void>? _activeCascade;

  List<TNodeValue>? _topoCache;

  /// Memoizes [descendantsInTopologicalOrder] per root. The graph's
  /// structure is immutable after construction (only [_statuses]
  /// changes), so each subtree walk is a one-shot BFS + topo-filter and
  /// the result is safe to keep forever.
  final Map<TNodeValue, List<TNodeValue>> _descendantsCache = {};

  bool _shutdown = false;

  /// Whether [shutdown] has been invoked. Subsequent [resolve] / [recompute]
  /// calls throw `StateError`.
  bool get isShutdown => _shutdown;

  Set<GraphNode<TNodeValue>> get rootNodes => UnmodifiableSetView(_rootNodes);

  /// Constructs a graph over [nodeValues] with [visitor] for cascade
  /// policy/side-effects.
  ///
  /// * [activationConcurrency] — optional cap on parallel
  ///   [GraphVisitor.onActivate] invocations. `null` (default) is
  ///   unbounded.
  /// * [drainIterationLimit] — maximum number of cascade rounds
  ///   [resolve] will run before throwing [GraphFixedPointError].
  ///   64 is a generous default; raise it for graphs with deeply
  ///   chained reactive toggles, lower it to fail faster in tests.
  Graph({
    required List<TNodeValue> nodeValues,
    required GraphVisitor<TNodeValue> visitor,
    int? activationConcurrency,
    int drainIterationLimit = 64,
  }) : _nodeValues = nodeValues,
       _visitor = visitor,
       _activationLimit = activationConcurrency != null
           ? Semaphore(activationConcurrency)
           : null,
       _drainIterationLimit = drainIterationLimit {
    if (activationConcurrency != null && activationConcurrency <= 0) {
      throw ArgumentError.value(
        activationConcurrency,
        'activationConcurrency',
        'must be > 0 or null (unbounded)',
      );
    }
    if (drainIterationLimit <= 0) {
      throw ArgumentError.value(
        drainIterationLimit,
        'drainIterationLimit',
        'must be > 0',
      );
    }
    final declared = _nodeValues.toSet();
    for (final value in _nodeValues) {
      _createNode(value, declared, []);
      _statuses[value] = GraphNodeStatus.disabled;
    }
  }

  /// Current status of [node] in the cascade state machine. Returns
  /// [GraphNodeStatus.disabled] for unknown values.
  GraphNodeStatus statusOf(TNodeValue node) {
    return _statuses[node] ?? GraphNodeStatus.disabled;
  }

  /// Upper bound on the drain loop applied by [resolve] — captured
  /// from the `drainIterationLimit` constructor parameter.
  int get drainIterationLimit => _drainIterationLimit;

  /// Runs the initial cascade — computes a target for every node in
  /// topological order and transitions each one to it.
  ///
  /// Idempotent: nodes already at their target are skipped. Safe to
  /// call multiple times.
  ///
  /// If visitor callbacks (`onActivate`, etc.) trigger further [recompute]
  /// calls while the first cascade is in-flight, those chained
  /// cascades are drained before [resolve] returns. This guarantees
  /// callers that `await resolve()` sees the graph at a stable
  /// fixed point, not mid-cascade.
  ///
  /// Throws [StateError] if [shutdown] has already been invoked.
  /// Throws [GraphFixedPointError] if chained cascades keep
  /// regenerating past [drainIterationLimit].
  Future<void> resolve() async {
    _throwIfShutdown();
    var prev = _chainCascade(() => _applyCascade(topologicalOrder()));
    try {
      await prev;
    } on Object {
      // Already reported via onError.
    }
    // Drain any cascades queued during the previous await. Loop until
    // `_activeCascade` stops changing — i.e. no nested cascade was
    // produced while we were waiting.
    for (var i = 0; i < _drainIterationLimit; i++) {
      final tail = _activeCascade;
      if (tail == null || identical(tail, prev)) {
        // Clear the reference so subsequent operations (notably
        // `shutdown`) don't re-await a completed future whose zone
        // may have torn down by then (e.g. Flutter's fake-async test
        // zone after the test body returns).
        _activeCascade = null;
        return;
      }
      prev = tail;
      try {
        await prev;
      } on Object {
        // Already reported via onError.
      }
    }
    throw GraphFixedPointError(
      'Graph did not stabilise after $_drainIterationLimit cascades. '
      'Likely a toggle cycle in visitor callbacks.',
    );
  }

  /// Recomputes the target state for [node] and its transitive
  /// descendants. Call this when external state affecting the node's
  /// target changes (e.g. `ownActive` toggled via a feature toggle).
  ///
  /// Throws [StateError] if [shutdown] has already been invoked.
  Future<void> recompute(TNodeValue node) {
    _throwIfShutdown();
    return _chainCascade(
      () => _applyCascade(descendantsInTopologicalOrder(node)),
    );
  }

  /// Transitions every currently-active node to `disabled` in reverse
  /// topological order, awaiting the visitor's `onDeactivate` for each.
  ///
  /// Awaits the in-flight cascade (if any) first to avoid racing with
  /// `resolve` / `recompute`. Idempotent — calling [shutdown] twice is a
  /// no-op on the second call.
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    // Wake any threads queued on the activation limit so their pending
    // `await` returns instead of hanging forever.
    _activationLimit?.drain();
    final prev = _activeCascade;
    if (prev != null) {
      try {
        await prev;
      } on Object {
        // Already reported via onError by the cascade machinery.
      }
    }
    for (final v in topologicalOrder().reversed) {
      if (_statuses[v] == GraphNodeStatus.active) {
        try {
          await _visitor.onDeactivate(v);
        } on Object catch (e, st) {
          _safeOnError(v, e, st);
        }
        _statuses[v] = GraphNodeStatus.disabled;
        _safeOnStatusChanged(v, GraphNodeStatus.disabled);
      }
    }

    // Drop structural caches — shutdown is a one-way door; no further
    // `resolve`/`recompute` can run, so holding the entries keeps memory
    // pinned for no purpose. Topological and descendants caches are
    // bounded by node count, but releasing them early helps when the
    // caller stores the graph in a long-lived container.
    _topoCache = null;
    _descendantsCache.clear();
  }

  void _throwIfShutdown() {
    if (_shutdown) {
      throw StateError('Graph has been shut down; no further cascades.');
    }
  }

  /// Returns node values in topological order — parents before children.
  /// The returned view is unmodifiable and cached across calls.
  List<TNodeValue> topologicalOrder() {
    return _topoCache ??= UnmodifiableListView(_computeTopologicalOrder());
  }

  /// Returns [root] plus all transitively dependent nodes (children,
  /// grandchildren, …), in topological order. Unmodifiable view.
  ///
  /// Memoized in [_descendantsCache]: graph topology is immutable after
  /// construction, so the BFS + topo-filter for each root runs at most
  /// once, which matters for frequent [recompute] callers.
  List<TNodeValue> descendantsInTopologicalOrder(TNodeValue root) {
    final cached = _descendantsCache[root];
    if (cached != null) return cached;

    final node = _nodes[root];
    if (node == null) return const [];

    final affected = <TNodeValue>{};
    final queue = Queue<GraphNode<TNodeValue>>()..add(node);
    while (queue.isNotEmpty) {
      final n = queue.removeFirst();
      if (affected.add(n.value)) {
        for (final child in n.children) {
          queue.add(child);
        }
      }
    }
    final result = UnmodifiableListView([
      for (final v in topologicalOrder())
        if (affected.contains(v)) v,
    ]);
    _descendantsCache[root] = result;
    return result;
  }

  /// Serializes cascades through a single in-flight future so concurrent
  /// [resolve] / [recompute] calls are observed in invocation order.
  Future<void> _chainCascade(Future<void> Function() build) {
    final prev = _activeCascade;
    final future = () async {
      if (prev != null) {
        try {
          await prev;
        } on Object {
          // Already reported via onError by the previous cascade.
        }
      }
      await build();
    }();
    _activeCascade = future;
    return future;
  }

  /// Core cascade algorithm. Computes targets parent-first, deactivates
  /// reverse-topologically (sequential), activates forward-topologically
  /// in parallel with parent-await ordering (async).
  ///
  /// The target for each node is `active` iff the visitor's
  /// [GraphVisitor.shouldBeActive] returns true AND every required
  /// parent's target is `active`. Activation is fail-closed: if a
  /// required parent fails to activate, the child settles in `disabled`
  /// without [GraphVisitor.onActivate] being called.
  Future<void> _applyCascade(List<TNodeValue> affected) async {
    if (affected.isEmpty) return;

    final targets = <TNodeValue, GraphNodeStatus>{};
    for (final v in affected) {
      targets[v] = _computeTarget(v, targets);
    }

    for (final v in affected.reversed) {
      final current = _statuses[v] ?? GraphNodeStatus.disabled;
      if (current == GraphNodeStatus.active &&
          targets[v] != GraphNodeStatus.active) {
        try {
          await _visitor.onDeactivate(v);
        } on Object catch (e, st) {
          _safeOnError(v, e, st);
        }
        _statuses[v] = GraphNodeStatus.disabled;
        _safeOnStatusChanged(v, GraphNodeStatus.disabled);
      }
    }

    final futures = <TNodeValue, Future<void>>{};
    for (final v in affected) {
      final current = _statuses[v] ?? GraphNodeStatus.disabled;
      if (targets[v] == GraphNodeStatus.active &&
          current != GraphNodeStatus.active) {
        final node = _nodes[v]!;
        final parentFutures = <Future<void>>[];
        for (final parent in node.requiredParents) {
          final pf = futures[parent.value];
          if (pf != null) parentFutures.add(pf);
        }
        futures[v] = _activateAfter(v, parentFutures);
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures.values, eagerError: false);
    }
  }

  /// Combines visitor's node-local preference with the required-parent
  /// cascade rule. Reads parents' in-flight targets from [pendingTargets]
  /// (for ancestors already processed in the current cascade), falling
  /// back to current graph status.
  GraphNodeStatus _computeTarget(
    TNodeValue v,
    Map<TNodeValue, GraphNodeStatus> pendingTargets,
  ) {
    final bool active;
    try {
      active = _visitor.shouldBeActive(v);
    } on Object catch (e, st) {
      _safeOnError(v, e, st);
      return GraphNodeStatus.disabled;
    }
    if (!active) return GraphNodeStatus.disabled;
    final node = _nodes[v]!;
    for (final parent in node.requiredParents) {
      final parentValue = parent.value;
      final parentStatus = pendingTargets[parentValue] ?? statusOf(parentValue);
      if (parentStatus != GraphNodeStatus.active) {
        return GraphNodeStatus.disabled;
      }
    }
    return GraphNodeStatus.active;
  }

  /// Waits for [parents], re-verifies each required parent actually
  /// settled at `.active` (fail-closed), then runs `onActivate`.
  Future<void> _activateAfter(TNodeValue v, List<Future<void>> parents) async {
    for (final pf in parents) {
      try {
        await pf;
      } on Object {
        // Parent's failure is already reported via onError; we check
        // status below.
      }
    }
    final node = _nodes[v]!;
    for (final parent in node.requiredParents) {
      if (statusOf(parent.value) != GraphNodeStatus.active) {
        // Required parent did not settle `.active` — we bail before
        // `onActivate` runs. `_applyCascade`'s precondition guarantees
        // we entered with `current != .active`, and `.pending` only
        // exists INSIDE this method (the `_statuses[v] = .pending`
        // below), so on this path `_statuses[v]` was already
        // `.disabled`. The write is an idempotent guard — no
        // observable transition, so no `_safeOnStatusChanged` fire.
        _statuses[v] = GraphNodeStatus.disabled;
        return;
      }
    }
    _statuses[v] = GraphNodeStatus.pending;
    _safeOnStatusChanged(v, GraphNodeStatus.pending);
    try {
      final limit = _activationLimit;
      if (limit != null) {
        await limit.run(() => _visitor.onActivate(v));
      } else {
        await _visitor.onActivate(v);
      }
      _statuses[v] = GraphNodeStatus.active;
      _safeOnStatusChanged(v, GraphNodeStatus.active);
    } on Object catch (e, st) {
      // Failed activation: we briefly showed `.pending` to any
      // observer, now settle back to `.disabled`. The post-commit
      // notification keeps reactive consumers (e.g. Feature status
      // stores) consistent — without it they'd stay stuck on the
      // transient `.pending`.
      _statuses[v] = GraphNodeStatus.disabled;
      _safeOnStatusChanged(v, GraphNodeStatus.disabled);
      _safeOnError(v, e, st);
    }
  }

  void _safeOnError(TNodeValue node, Object error, StackTrace stackTrace) {
    try {
      _visitor.onError(node, error, stackTrace);
    } on Object {
      // If onError itself throws there's nowhere to report — swallow so
      // siblings still process.
    }
  }

  /// Post-commit notification dispatcher. Called after every
  /// `_statuses[node]` write that represents an actual transition.
  /// Visitor throws route through [_safeOnError] so sibling nodes in
  /// the same cascade keep making progress.
  void _safeOnStatusChanged(TNodeValue node, GraphNodeStatus newStatus) {
    try {
      _visitor.onStatusChanged(node, newStatus);
    } on Object catch (e, st) {
      _safeOnError(node, e, st);
    }
  }

  List<TNodeValue> _computeTopologicalOrder() {
    final result = <TNodeValue>[];
    final visited = <GraphNode<TNodeValue>>{};

    void visit(GraphNode<TNodeValue> node) {
      if (!visited.add(node)) return;
      for (final parent in node.parents) {
        visit(parent);
      }
      result.add(node.value);
    }

    for (final value in _nodeValues) {
      final node = _nodes[value];
      if (node != null) visit(node);
    }
    return result;
  }

  GraphNode<TNodeValue> _createNode(
    TNodeValue value,
    Set<TNodeValue> declared,
    List<TNodeValue> creatingPath,
  ) {
    final existing = _nodes[value];
    if (existing != null) return existing;

    final onPathIdx = creatingPath.indexOf(value);
    if (onPathIdx != -1) {
      final cycle = [
        ...creatingPath.sublist(onPathIdx),
        value,
      ].map((v) => v.name).join(' → ');
      throw GraphCycleError('Cycle detected: $cycle');
    }
    creatingPath.add(value);
    try {
      final requiredParentNodes = <GraphNode<TNodeValue>>{};
      for (final pv in value.parents) {
        requiredParentNodes.add(
          _createParent(pv as TNodeValue, value, declared, creatingPath),
        );
      }
      final optionalParentNodes = <GraphNode<TNodeValue>>{};
      for (final pv in value.optionalParents) {
        optionalParentNodes.add(
          _createParent(pv as TNodeValue, value, declared, creatingPath),
        );
      }

      final node = GraphNode<TNodeValue>(
        value: value,
        parents: {...requiredParentNodes, ...optionalParentNodes},
        requiredParents: requiredParentNodes,
      );

      for (final parentNode in node.parents) {
        parentNode.addChild(node);
      }

      _nodes[value] = node;
      if (node.parents.isEmpty) _rootNodes.add(node);
      return node;
    } finally {
      creatingPath.removeLast();
    }
  }

  GraphNode<TNodeValue> _createParent(
    TNodeValue parent,
    TNodeValue child,
    Set<TNodeValue> declared,
    List<TNodeValue> creatingPath,
  ) {
    if (!declared.contains(parent)) {
      throw GraphNodeNotFoundError(
        missing: parent.name,
        referencedBy: child.name,
      );
    }
    return _createNode(parent, declared, creatingPath);
  }
}
