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
