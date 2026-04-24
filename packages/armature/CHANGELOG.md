## 0.3.0

> Note: This release has breaking internal changes. User-facing API is
> unchanged; internal (`@internal`) paths have moved.

### Fixed

- **Per-container feature runtime** — top-level `final feature = createFeature(...)`
  instances no longer carry mutable runtime state. Scope API, status
  store, cleanup bags, `ownActive`, toggle callable, and the bound
  `FeatureParentApi` now live in a new `FeatureRuntime` owned by each
  [AppContainer]. Two concurrent or sequentially-remounted containers
  backed by the same feature list hold independent runtime state —
  fixes a race where async dispose of one container corrupted another's
  stores, port handlers, and status subscriptions.

### BREAKING (internal)

- `Feature.internal` getter replaced by `Feature.config` — exposes
  `FeatureConfig` (immutable after cascade): name, deps, factories,
  activation setup, onStart callback, port bindings. Runtime state is
  reached via `container.runtimeOf(feature)`.
- `Port._handlers` removed — port handler registration lives on the
  container as `container.handlersOf<THandler>(port)` /
  `container.addPortHandler(...)` / `container.removePortHandler(...)`.
  Ports themselves become stateless across containers (only `_owner`
  remains, set-once and stable).
- `Port.addHandler` / `removeHandler` / `hasHandlerFor` / `handlerCount` /
  `handlerFeatureNames` / `handlers` getter deleted.
- `Port.check` signature now takes `container: AppContainer` alongside
  `applyingFeature:` — the lookup of pre-registered handlers reads from
  the container's per-container map.
- `FeatureParentApi` is instantiated per-container via the new internal
  `featureParentApiForContainer(...)` helper; `.of` / `.statusOf`
  resolve through `container.runtimeOf(feature)`.
- `FeatureHandlerContext` / `FeatureScopeApi` gain an `@internal
  container` field (set by the container during scope construction).
- `feature.storeOf<T>()` in `test_utils.dart` now takes an explicit
  `AppContainer` argument: `feature.storeOf<T>(container)`.

### Behavioural changes

- `useStores` throws `FeatureResolutionError` after any container has
  constructed the feature (previously: after `_scopeApi` was set on a
  single shared slot). Semantics are the same for the single-container
  case; multi-container now also guards.
- `container.dispose()` clears the per-container port handler map — no
  cross-container deregistration needed. Handlers are reinstalled on
  the next `container.start()` from each feature's recorded
  `portBindings`.

## 0.2.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**(website): add interactive docs and examples site. ([f30d28c1](https://github.com/telchardev/armature/commit/f30d28c1f5d0259b6b8af4b387c01b24564b90e1))

## 0.1.0

- Initial release — the core `armature` framework:
  - `Feature` — a modular unit with typed stores, exports, activation,
    and ports. Built via `createFeature(...)` with a records-based
    `stores:` / `exports:` / `ports:` surface.
  - `AppContainer` — orchestrates feature lifecycle, dependency-graph
    resolution, and port application. Single error sink via
    `ContainerErrorHandler({source, error, meta})`.
  - `Store<T>` / `State<T>` — reactive state primitives built on
    `armature_reactive`, with subscribe / fireImmediately / update
    semantics.
  - `Task` — strategy-backed async action runner
    (`.once`, `.queue`, `.latest`, `.debounce`, `.throttle`).
  - Ports: `Pipe`, `Behavior` — owner/handler contract with eager or
    lazy owner binding; slot ports live in `armature_flutter`.
  - Activation helpers: `manualActivation`, `whenStoreState`,
    `whenActive`, `whenInactive`, `whenAllActive`.
  - Reactive feature-status observation via
    `parentApi.statusOf(feature)` returning a `Store<FeatureStatus>`.
  - `CleanupBag` with LIFO disposal, late-add semantics, and async
    error routing.
  - Sealed `ArmatureError` hierarchy (`ContainerError`,
    `FeatureResolutionError`, `HandlerError`, `ListenerError`,
    `PortError`, `RenderError`, `StoreLookupError`, `TaskError`, …).
