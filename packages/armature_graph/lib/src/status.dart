/// The three-state machine each [GraphNode] is tracked in.
///
/// * [disabled] — not active. Default; also the settling state after a
///   failed activation or a deactivation.
/// * [pending] — transitioning from `disabled` to `active`. Set by the
///   graph while the visitor's `onActivate` is awaiting async work.
///   Briefly observable; becomes `active` when `onActivate` resolves.
/// * [active] — fully online.
enum GraphNodeStatus { disabled, pending, active }

/// Policy + side-effect interface for a [Graph] cascade.
///
/// The graph owns topology, state tracking, ordering, parallel-with-
/// ordering activation, and **required-parent cascade** (a node can only
/// be `active` if all its required parents are `active`). The visitor
/// supplies only node-local policy + side effects:
///
///   * [shouldBeActive] — should this node be active? Graph combines this
///     with required-parent cascade to compute the final target.
///   * [onActivate] — async work when a node transitions toward `active`.
///     Awaited so children see a fully-online parent.
///   * [onDeactivate] — async work when a node transitions away from
///     `active`. Awaited so a child's cleanup completes before its
///     parent's resources are torn down.
///   * [onStatusChanged] — single post-commit notification hook fired
///     whenever the graph commits a new [GraphNodeStatus] for a node
///     (`.pending`, `.active`, or `.disabled`). Replaces the older
///     split of `onActivated` / `onDeactivated` — having one hook for
///     every transition removes the bug class "I forgot to fire the
///     post-commit callback for state X".
///   * [onError] — centralized error reporting for any exception thrown
///     by [shouldBeActive], [onActivate], [onDeactivate], or
///     [onStatusChanged]. The graph catches these so one failure doesn't
///     break siblings, then calls [onError] so the visitor can log/report
///     without its own try/catch.
abstract class GraphVisitor<T> {
  /// Whether [node]'s own preference is to be active. Graph downgrades
  /// the final target to `disabled` if any required parent isn't active.
  ///
  /// A throw is treated as `false` (the node stays/goes `disabled`) and
  /// routed through [onError]. Implementations should be pure and
  /// deterministic — the graph may call [shouldBeActive] multiple times
  /// per cascade iteration while computing targets.
  bool shouldBeActive(T node);

  /// Async work when [node] transitions toward `active`. The future
  /// must complete before children start their own transitions (the
  /// graph awaits it). Throwing settles the node in `disabled` and its
  /// required descendants stay `disabled` too — the graph then calls
  /// [onError] and proceeds with siblings.
  ///
  /// **Status invariant.** While [onActivate] is awaiting, the graph's
  /// internal status for [node] is [GraphNodeStatus.pending] — the
  /// transition to [GraphNodeStatus.active] happens only after
  /// [onActivate] returns successfully. [onStatusChanged] fires post-
  /// commit for every state ([pending], [active], [disabled]), so use
  /// that hook when you need to observe settled status.
  Future<void> onActivate(T node);

  /// Async work when [node] transitions away from `active`. Awaited
  /// sequentially in reverse topological order (children before
  /// parents) so a child's cleanup completes before its parent's
  /// resources are torn down. Throwing is reported via [onError] and
  /// does not abort the remaining deactivations.
  ///
  /// **Status invariant.** While [onDeactivate] is awaiting, the
  /// graph's internal status for [node] is still
  /// [GraphNodeStatus.active]. The flip to [GraphNodeStatus.disabled]
  /// happens only after [onDeactivate] returns; the post-commit
  /// notification surfaces through [onStatusChanged].
  Future<void> onDeactivate(T node);

  /// Invoked synchronously right after the graph commits [node] to
  /// [newStatus]. Fires for every transition: `.pending` (before the
  /// [onActivate] await), `.active` (after a successful [onActivate]),
  /// and `.disabled` (after an [onDeactivate], a failed activation, or
  /// a [shutdown]).
  ///
  /// Unlike [onActivate] / [onDeactivate] (the async work hooks), this
  /// runs **after** the status flip — any `statusOf(node)` read during
  /// the call reflects the committed state. Used by consumers that
  /// mirror graph status into their own reactive state (e.g. feature
  /// status stores, debug overlays, UI spinners).
  ///
  /// Not called for idempotent writes — if `_statuses[v]` was already
  /// [newStatus] the graph short-circuits and never fires the hook.
  ///
  /// Default implementation is a no-op so minimal visitors stay
  /// source-compatible. Throws route through [onError].
  void onStatusChanged(T node, GraphNodeStatus newStatus) {}

  /// Invoked whenever the graph catches an exception from one of the
  /// other visitor methods for [node]. Implementations should log or
  /// report; they do NOT need to rethrow — the graph has already
  /// recorded the node's final status by the time this runs.
  ///
  /// May be invoked multiple times for the same node when a compound
  /// transition trips several hooks (e.g. an [onActivate] throw followed
  /// by an [onDeactivate] throw during the rollback that settles the
  /// node in `disabled`). Each invocation describes one distinct
  /// failure; keep implementations idempotent.
  void onError(T node, Object error, StackTrace stackTrace);
}
