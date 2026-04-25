## 0.3.1

> Docs and example refresh. No library code changes.

### Changed

- README updated to align terminology with the current API surface
  (keyed slots, `.queue` / `asc` defaults, `package:armature/advanced.dart`
  barrel, explicit `FeatureStatus` / `ToggleState`).
- `example/example.dart` switches to the new `cleanup.subscribe(...)`
  sugar from `armature` 0.3.1.

## 0.3.0

### Fixed

- **Per-container renderer** — the pre-0.3.0 `rendererContext` global
  singleton has been replaced by a per-`AppContainer` renderer slot,
  accessed via the new `ContainerRenderer` extension
  (`container.renderer`). Two `ArmatureApp`s living sibling-by-sibling
  or mounting / unmounting in rapid succession each carry their own
  renderer — the previous race where an outgoing widget's async
  dispose nulled out the incoming widget's renderer is gone.

### BREAKING (internal)

- `rendererContext` global removed. `ArmatureApp.initState` and
  `bootstrap()` now call `container.setRenderer(...)` instead of
  assigning the global. Custom renderers and slot implementations read
  via `container.renderer`.
- `initTestRenderer` in `test_utils.dart` now takes an `AppContainer`:
  `initTestRenderer(container)`. `pumpFeature` installs a
  `FlutterRenderer` lazily on each container, so most widget tests
  don't need to call `initTestRenderer` directly anymore.
- `useSingleSlot` / `useMultiSlot` extensions record the binding into
  the feature's config (via the new internal `Feature.recordPortBinding`
  helper) instead of calling `port.addHandler`. User-facing API is
  unchanged.
- Slot widget builders use `container.renderer.renderSlot(...)` instead
  of `rendererContext.renderer.renderSlot(...)`. The `container` is
  available at every existing call site — no extra plumbing needed.

### Depends on

- `armature: ^0.3.0` — see that package's CHANGELOG for the full
  config/runtime split.

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**(website): add interactive docs and examples site. ([f30d28c1](https://github.com/telchardev/armature/commit/f30d28c1f5d0259b6b8af4b387c01b24564b90e1))

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
