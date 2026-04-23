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
