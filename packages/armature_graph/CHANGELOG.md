## 1.0.0

> First stable release. Public API is unchanged since 0.1.0 — the bump
> reflects the package being battle-tested through several `armature`
> release cycles and is now committed to semver.

### Documentation

- `Graph.topologicalOrder()` doc-comment now explains the typical
  consumer ("walk the graph respecting dependency order — debug
  snapshots, dumps, custom parent-first visitors") and notes that the
  result is cheap to call repeatedly because it's cached per [Graph].
- `Graph.descendantsInTopologicalOrder(root)` doc-comment now points to
  its primary internal use (driving `recompute`'s per-root cascade) and
  the secondary external use ("everyone affected when this node toggles").
- README minor edits.

## 0.1.0

- Initial release — DAG primitives for `armature`:
  - `Graph<T>` — a directed-acyclic graph of typed nodes.
  - `GraphVisitor<T>` — user-supplied lifecycle hooks (`shouldBeActive`,
    `onActivate`, `onDeactivate`, `onStatusChanged`, `onError`).
  - Topological resolution with a fixed-point cascade — nodes settle in
    `.active` / `.pending` / `.disabled` over a single `resolve()` call.
  - Activation throttle (`activationConcurrency`) via an internal
    semaphore.
  - Sealed `GraphError` hierarchy — cycles, missing nodes, fixed-point
    failures.
