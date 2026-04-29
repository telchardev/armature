## 1.0.0

> First stable release. Tracks `armature` 1.0.0; existing widgets and
> providers from 0.4.0 are unchanged. New widgets (`StoreListener`,
> `TaskBuilder`) are additive.

### Added

- **`StoreListener<S>`** — side-effect host for a `Store<S>` that fires
  the listener on transitions without rebuilding `child`. The state
  generic infers from the `store: Store<S>` argument; an optional
  `listenWhen: (prev, next) => ...` predicate filters which transitions
  trigger the callback. Use for navigation, snackbars, analytics —
  anywhere `StoreBuilder` would over-rebuild.

  ```dart
  StoreListener(
    store: context.store<AuthStore>(),
    listenWhen: (p, n) => !p.isLoggedIn && n.isLoggedIn,
    listener: (ctx, _) => Navigator.of(ctx).pushReplacementNamed('/home'),
    child: const LoginForm(),
  )
  ```

- **`TaskBuilder`** — reactive four-way switch on `Task.state`. All
  three generics (`TParams`, `TResult`, `TError`) infer from the `task`
  argument; the four branch builders (`idle`, `pending`, `done`,
  `failed`) are required so the compiler enforces exhaustive coverage.

  ```dart
  TaskBuilder(
    task: store.fetchUser, // Task<int, User, ApiException>
    idle:    (_)         => const _Placeholder(),
    pending: (_, userId) => const CircularProgressIndicator.adaptive(),
    done:    (_, user)   => UserCard(user),
    failed:  (_, e)      => ErrorBanner(message: e.message),
  )
  ```

### Performance

- **`MultiPortBuilder` build hoists** — the per-build `tracked` Set,
  `_reconcile` `stale` List, and error-reporter closure are now
  allocated once in `initState` and reused, instead of being recreated
  on every reactive rebuild.
- **`MultiSlot.apply` empty-handlers / empty-entries fast paths** —
  return `initialValue` directly when the port has no registered
  handlers, or when no active feature contributes a descriptor for the
  current `data` payload, instead of allocating an empty `entries`
  list and copying `initialValue` into a new `List<Widget>`.

### Internal

- Switched from `package:armature/advanced.dart` to
  `package:armature/framework.dart` for `Port` / `PortType`. The
  `framework.dart` barrel is the new home for sibling-package
  plumbing types.

### Depends on

- `armature: ^1.0.0` (was `^0.4.0`).

## 0.4.0

> Tracks the `armature` 0.4.0 container lifecycle rename. No new
> Flutter-side surface — but consumers that called `dispose()` on a
> container directly must migrate.

### Changed

- `ArmatureApp` now calls `container.stop()` instead of
  `container.dispose()` when the widget is disposed. With the new
  restart-friendly cycle, the container can be `start()`-ed again from
  user code if the same `ArmatureApp` is remounted.
- `container_dispose_test.dart` removed; the equivalent restart-cycle
  coverage now lives in `armature`'s `container_test.dart`.

### Migration

- Any user code that called `container.dispose()` directly (for example,
  when bootstrapping a container outside `ArmatureApp`) must switch to
  `container.stop()`. See the `armature` 0.4.0 changelog for the full
  rationale.

### Documentation

- `SlotDescriptor`, `SlotLoaderBuilder`, and `Renderer.renderLoader`
  doc-comments now reference `FeatureStatus.pending` /
  `FeatureStatus.active` / `ContainerStatus.starting` explicitly instead
  of the `.pending` / `.active` shorthand.
- Provider and renderer files (`single_slot_provider.dart`,
  `multi_slot_provider.dart`, `flutter_renderer.dart`) cleaned up the
  same way.
- README aligned with the current API surface.

### Depends on

- `armature: ^0.4.0` — see that package's CHANGELOG for the lifecycle
  rename details.
- `armature_reactive: ^1.0.0` (was `^0.1.0`) — first stable release;
  public API unchanged.

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
