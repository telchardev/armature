## 0.1.0

- Initial release — Flutter integration for `armature`:
  - `ArmatureApp` — top-level widget that bootstraps the container and
    installs providers. `bootstrap(...)` remains as the manual
    alternative for custom lifecycles.
  - `FeatureRoot` / `createFeatureRoot` — mounts a feature as a
    top-level root widget via its descriptor (`widget:` + optional
    `loader:`).
  - Slot widgets: `SingleSlot`, `MultiSlot`, `SingleSwitchSlot`,
    `MultiSwitchSlot`. Registration via the typed
    `feature.useSingleSlot(...)` / `useMultiSlot(...)` extensions —
    handlers return `Widget?` and the framework wraps them into
    descriptors.
  - Port providers: `PipeProvider`, `BehaviorProvider`,
    `SingleSlotProvider`, `MultiSlotProvider`, `MultiPortBuilder` /
    `PortReader` for multi-port reactive reads.
  - Store widgets:
    - `context.store<T>()` — one-shot imperative store lookup.
    - `StoreBuilder<T>` — reactive DI + rebuild on any tracked state
      change.
    - `StoreSelector<V>` — equality-based rebuild on derived values,
      for multi-store projections and fine-grained optimisation.
    - `StateObserver` — raw reactive wrapper for custom builders.
  - Renderer: pluggable `Renderer` interface with `FlutterRenderer`
    as the default; `FlutterRendererOptions.errorBuilder` /
    `loaderBuilder` for customising slot error / loading states.
  - Debug overlay: `FeatureGraphOverlay` — interactive feature-graph
    canvas with pan / zoom / drag, node detail panel, live store
    inspector, minimap, refresh button, gesture hint.
  - Test utilities (`package:armature_flutter/test_utils.dart`):
    `initTestRenderer`, `wrapForTesting`, `pumpFeature`.
