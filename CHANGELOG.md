# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2026-04-25

### Changes

---

Packages with breaking changes:

 - [`armature` - `v0.3.0`](#armature---v030)
 - [`armature_flutter` - `v0.3.0`](#armature_flutter---v030)

Packages with other changes:

 - There are no other changes in this release.

---

#### `armature` - `v0.3.0`

 - **FIX**: per-container feature runtime — top-level `createFeature(...)` instances no longer carry mutable runtime state. Scope API, status store, cleanup bags, `ownActive`, toggle, and bound `FeatureParentApi` now live in a per-`AppContainer` `FeatureRuntime`. Two concurrent or sequentially-remounted containers backed by the same feature list hold independent runtime state.
 - **BREAKING** (internal): `Feature.internal` getter replaced by `Feature.config` (immutable post-cascade); runtime state reached via `container.runtimeOf(feature)`. Port handler maps moved off `Port` onto `AppContainer.handlersOf` / `addPortHandler` / `removePortHandler`; `Port.addHandler` / `removeHandler` / `hasHandlerFor` / `handlerCount` / `handlerFeatureNames` / `handlers` deleted. `Port.check` now takes `container:`. `FeatureParentApi` is per-container; `FeatureHandlerContext` / `FeatureScopeApi` gained an `@internal container` field. `feature.storeOf<T>()` now requires an `AppContainer` argument: `feature.storeOf<T>(container)`.

#### `armature_flutter` - `v0.3.0`

 - **FIX**: per-container renderer — the pre-0.3.0 `rendererContext` global singleton has been replaced by a per-`AppContainer` renderer slot, accessed via the new `ContainerRenderer` extension (`container.renderer`). Sibling `ArmatureApp`s and rapid mount / unmount cycles each carry their own renderer.
 - **BREAKING** (internal): `rendererContext` global removed. `ArmatureApp.initState` and `bootstrap()` call `container.setRenderer(...)`; slot widgets read via `container.renderer`. `initTestRenderer` now takes an `AppContainer`: `initTestRenderer(container)`. `pumpFeature` lazily installs a `FlutterRenderer` if none is set, so most widget tests no longer need to call `initTestRenderer` directly. `useSingleSlot` / `useMultiSlot` extensions record port bindings into the feature's config (no longer call `port.addHandler` directly); user-facing API unchanged.

## 2026-04-24

### Changes

---

Packages with breaking changes:

 - [`armature` - `v0.2.0`](#armature---v020)
 - [`armature_flutter` - `v0.2.0`](#armature_flutter---v020)

Packages with other changes:

 - There are no other changes in this release.

---

#### `armature` - `v0.2.0`

 - **BREAKING** **FEAT**(website): add interactive docs and examples site. ([f30d28c1](https://github.com/telchardev/armature/commit/f30d28c1f5d0259b6b8af4b387c01b24564b90e1))

#### `armature_flutter` - `v0.2.0`

 - **BREAKING** **FEAT**(website): add interactive docs and examples site. ([f30d28c1](https://github.com/telchardev/armature/commit/f30d28c1f5d0259b6b8af4b387c01b24564b90e1))

