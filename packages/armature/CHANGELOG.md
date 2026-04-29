## 1.0.0

> First stable release. Public API surface in `package:armature/armature.dart`
> is committed: every symbol exported from that barrel follows semver from
> here on. Code written against `0.4.0` continues to compile — `1.0.0` is
> additive on top of it.

### Added — DX

- **`StoreListener` / `TaskBuilder`** (Flutter side) — new widgets in
  `armature_flutter` that pair with this release. See that package's
  changelog for details.
- **`TaskStateExtensions`** on `TaskState<TParams, TResult, TError>`:
  - `.when({idle, pending, done, failed})` — exhaustive pattern match.
  - `.maybeWhen({...}, orElse:)` — partial match with fallback.
  - `.isIdle` / `.isPending` / `.isDone` / `.isFailed` — branch booleans.
  - `.paramsOrNull` / `.resultOrNull` / `.errorOrNull` — branch payload
    getters.
- **Task awaiters** — `Task.firstWhere(predicate)`, `Task.awaitDone()`,
  `Task.awaitFailed()`, `Task.awaitSettled()`. Useful in tests and
  orchestration scripts that need to gate on a transition without
  spinning up a reaction.
- **`Store.subscribeSelect(selector, listener, {fireImmediately, equals})`**
  — equality-filtered projection with optional custom equality (e.g.
  `listEquals` for collection-typed selectors). Replaces the
  `StoreSubscribeExtensions` proposal — lives directly on `Store<T>`.
- **`package:armature/framework.dart`** — new barrel for sibling-package
  plumbing. Exposes `Port`, `AnyPort`, `PortType`, `PortSubscription`
  for `armature_flutter` and custom `Renderer` implementations.
  **Application code should not import it** — the typed APIs in
  `armature.dart` cover every end-user scenario.

### Fixed

- **Listener errors in `State`** are now isolated. Each listener call is
  wrapped in `try/catch`; a single captured error rethrows with its
  original stack trace, multiple errors surface through the new internal
  `StateListenerErrors` aggregate. A throwing listener no longer aborts
  its siblings or the surrounding `state =` setter.
- **`Store.dispose()` isolates each `task.dispose()` call** so a
  misbehaving task can't prevent siblings from being torn down. Same
  single/aggregate semantics via internal `TaskDisposeErrors`.
- **`FeatureOrchestrator._onToggle` switched to a batched FIFO queue**
  with microtask-deferred drain. Eliminates re-entrant cascade chains
  from inside lifecycle callbacks — resolves the deadlock under
  `maxResolveConcurrency: 1` and the fixed-point livelock when a
  reactive subscription toggles during an active cascade. The
  `armature_graph` package was not touched.
- **`FeatureRuntime.teardown` clears `_cleanupOnError`** so prior-cycle
  closures don't pin the container's error handler / logger references
  across `start` / `stop` cycles.
- **`PrintLogger.log` wraps `JsonEncoder.convert` in try/catch** with a
  `toString()` fallback so a non-encodable `debugInfo` map can no
  longer crash the framework.

### Performance

- **State `_notifyListeners` fast path** — single-listener writes skip
  the try/catch + error list allocation entirely; the listener throws
  propagate naturally.
- **Atom `_propagateChanged` fast path** — single-observer atoms skip
  iterator allocation on every `reportChanged()`.
- **`Reaction._clearAtoms` reuses the atom set** in place of allocating
  a fresh empty set on every clear; early-return when the set is
  already empty.
- **`Task._flushLatestPending` single-completer fast path** — the
  common `.latest` case (one pending caller) skips the defensive
  `List.from()` snapshot.

### Internal

- `PortType` / `AnyPort` / `Port` / `PortSubscription` moved out of
  `package:armature/advanced.dart` into `package:armature/framework.dart`.
  `advanced.dart` now holds only application-facing escape-hatch types
  (handler typedefs, individual `TaskStrategy*` constructors,
  debug-overlay mirrors).

## 0.4.0

> Breaking release: container lifecycle reshaped around `stop()`.
> `dispose()` is gone — see Migration below.

### Removed

- **`AppContainer.dispose()`** and **`ContainerStatus.disposed`** — the
  container is no longer a one-shot disposable.
- **`AppContainer.onDispose(...)`** and the internal `_disposeCallbacks`
  plumbing — per-container resources should now live inside a feature's
  `setup` + cleanup bag, where they're recreated each cycle.
- The internal `forRestart` flag on `_teardownFeatures` — there is now a
  single teardown path.

### Added

- **`AppContainer.stop()`** — returns the container to `.idle` with the
  same coalesce / re-entrance guards `dispose()` had. After `stop()`,
  `start()` can be called again to spin up a fresh cycle: new stores,
  fresh status stores, re-armed lifetime cleanup, re-registered port
  handlers.
- **`Events.clearListeners()`** — invoked from every `stop` and from
  rollback paths so event subscribers don't leak across cycles.
- Restart-cycle correctness tests in `container_test.dart` and a
  same-container restart RSS leak benchmark in `leak_benchmark_test.dart`.

### Migration

- Replace `container.dispose()` with `container.stop()`.
- Move any `onDispose(...)` work into a feature's cleanup bag
  (`cleanup.add(...)`) so it runs per cycle rather than once at the end
  of the container's life.

### Documentation

- Expanded doc-comments on enum members of `ContainerStatus`, `LogLevel`,
  and `ThrottleEdge`.
- Per-strategy doc-comments on `TaskStrategyOnce` / `TaskStrategyQueue` /
  `TaskStrategyLatest` / `TaskStrategyDebounce` / `TaskStrategyThrottle`
  describing the behaviour each one selects.
- Field-level doc-comments on `PortDebugInfo` and `FeatureDependency`.
- README aligned with the current API surface (keyed slots, `.queue` /
  `asc` defaults, `package:armature/advanced.dart` barrel, explicit
  `FeatureStatus` / `ToggleState`).

### Depends on

- `armature_graph: ^1.0.0` (was `^0.1.0`) — first stable release.
- `armature_reactive: ^1.0.0` (was `^0.1.0`) — first stable release.

Public API of both transitive packages is unchanged, so this is a
constraint-only bump for `armature` consumers.

## 0.3.1

> Additive release: new public APIs on `Task` and `Cleanup`. No breaking
> changes — `^0.3.0` consumers can adopt without code modifications.

### Added

- **`Task.reset()`** — public method that returns a task to `TaskIdle`
  from any sticky state (`TaskDone` / `TaskFailed`). Supersedes any
  in-flight run via a generation token (state writes from older runs
  drop), cancels strategy-internal timers (debounce quiet timer,
  throttle cooldown / window), rejects coalesced callers from
  `.latest` / `.debounce` / `.throttle(trailing)` with `TaskError`,
  and clears the `.once` cache so the next call re-executes the fn.
  Silent no-op after `dispose` and from `TaskIdle`.
- **`autoReset: Duration?`** parameter on `Store.createTask` /
  `Store.createVoidTask` — schedules an automatic transition back to
  `TaskIdle` after the given duration in `TaskDone` / `TaskFailed`.
  The internal timer cancels and re-arms on every state transition,
  so a fresh `call()` while the timer is waiting starts a new
  lifecycle without flickering through `TaskIdle`. Cancelled in
  `dispose()` and on manual `reset()`.
- **`Cleanup.subscribe(store, listener, {fireImmediately})`** — sugar
  for `cleanup.add(store.subscribe(listener, ...))`.
- **`Cleanup.periodic(duration, callback)`** — wraps `Timer.periodic`
  and auto-cancels the timer on deactivation.
- **`Cleanup.listen(stream, onData, {onError, onDone, cancelOnError})`**
  — wraps `Stream.listen(...)` and auto-cancels the subscription on
  deactivation.

### Changed

- `CleanupBag` now `extends Cleanup` (was `implements Cleanup`) so the
  new sugar helpers are inherited. Late-add semantics on the sealed
  bag are preserved — sugar methods route through `add()`.
- `TaskError` doc clarifies that the same error is also surfaced
  through pending futures when `Task.reset()` cancels coalesced
  callers (previously documented only for `dispose`).
- README and `Store.createTask` docstring gain a "Picking TError"
  guide (`Exception` / domain class / `Never` / `Object`) explaining
  which thrown values land in `TaskFailed` vs propagate.

### Internal

- `_latestRunId` generalised into a cross-strategy `_generation`
  supersession token. Every async path (`_executeFn` / `_runLatest`
  / `_fireDebounced` / `_fireThrottleTrailing`) captures the token
  at entry and skips state writes / completer settles when the
  captured value no longer matches.
- Extracted `_supersedeInFlight` helper shared between `dispose` and
  `reset` for strategy-state teardown (timer cancel, completer
  rejection, queue / debounce / throttle buffer clear).

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
