## 1.0.0

> First stable release. Public API is unchanged since 0.1.0 — `Atom`,
> `Reaction`, `Context`, batching, and the `ReactiveError` hierarchy
> have shipped through several `armature` release cycles without
> change, and the package is now committed to semver.

## 0.1.0

- Initial release — reactive primitives for `armature`:
  - `Atom<T>` — observable cell with identity-based change detection.
  - `Reaction` — dependency-tracking invalidator with batched notification.
  - `Context` — zone-scoped tracking glue that wires reads from inside
    a `track()` block to the enclosing reaction.
  - Batching with fixed-point convergence and configurable iteration cap.
  - Sealed `ReactiveError` hierarchy for all framework-raised errors.
