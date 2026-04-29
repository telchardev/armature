import 'dart:async';

import 'package:meta/meta.dart' show internal;

import '../container/container.dart' show AppContainer;
import '../errors.dart'
    show
        FeatureConfigurationError,
        FeatureResolutionError,
        FeatureResolutionReason,
        HandlerError;
import '../store/store.dart' show Store;
import '../user_callback_zone.dart' show runAsUserCallback;
import './cleanup.dart' show CleanupBag;
import './feature.dart' show AnyFeature;
import './feature_api.dart'
    show FeatureParentApi, FeatureScopeApi, featureParentApiForContainer;
import './feature_status.dart' show FeatureStatus, FeatureToggle;

/// Private [Store] subclass whose state mirrors the container's
/// per-feature [FeatureStatus]. Exposes a file-local [setStatus] mutator
/// so the framework can write transitions; user code receives a plain
/// `Store<FeatureStatus>` reference.
class _FeatureStatusStore extends Store<FeatureStatus> {
  _FeatureStatusStore() : super(state: FeatureStatus.disabled);

  void setStatus(FeatureStatus next) {
    state = next;
  }
}

/// Per-container runtime state for a [Feature].
///
/// Holds every piece of state that's mutated during container start /
/// activate / deactivate / teardown — scope API, exports cache, status
/// store, cleanup bags, own-active flag, toggle callable. Two
/// [AppContainer] instances backed by the same top-level `final`
/// [Feature] hold independent runtimes, so async dispose of one can't
/// corrupt the other.
///
/// Users never reach for this directly; it's allocated by the container
/// at construction and orchestrated by [FeatureOrchestrator].
@internal
final class FeatureRuntime<TStores extends Object?, TExports extends Object?> {
  /// The top-level feature this runtime is bound to.
  final AnyFeature feature;

  /// The container that owns this runtime. Passed to
  /// [FeatureParentApi] / [FeatureScopeApi] so descendant
  /// `parent.of(...)` / `parent.statusOf(...)` resolves through the
  /// same container.
  final AppContainer container;

  /// Parent API bound to [container] — what `activation` setups and
  /// store factories receive. Separate instance per runtime so two
  /// containers' parent APIs never share state.
  final FeatureParentApi parent;

  FeatureScopeApi<TStores>? _scopeApi;
  TExports? _exportsCached;
  bool _exportsComputed = false;

  /// Reactive status store. Recreated in [teardown] so the next start
  /// cycle on the same container gets a fresh, undisposed instance.
  /// External holders of a previous-cycle reference must re-fetch via
  /// [statusStore] after the next [AppContainer.start].
  _FeatureStatusStore _statusStore = _FeatureStatusStore();

  /// Container-lifetime cleanup bag passed to [activationSetup]. Wired
  /// by the orchestrator layer in `_buildGraph` with an `onError`
  /// handler; sealed on [teardown].
  late CleanupBag lifetimeCleanup;

  /// Cleanup bag for the currently-active session. Pre-sealed between
  /// activations so any late `add` runs the disposer immediately.
  CleanupBag currentCleanup = CleanupBag.sealed();

  /// Error sink carried through activations so sealed bags replacing
  /// [currentCleanup] during `deactivate` / [teardown] keep routing
  /// late-`add` disposer failures to the container's `errorHandler`.
  void Function(Object, StackTrace)? _cleanupOnError;

  /// Own-level activation flag. Default `true`; set to `false` when an
  /// activation setup is configured (flipped back when the setup's
  /// toggle fires `ToggleState.active`).
  bool ownActive;

  /// Toggle handle exposed to [activationSetup]. Populated by the
  /// orchestrator in `_buildGraph`.
  late FeatureToggle toggle;

  FeatureRuntime({required this.feature, required this.container})
    : parent = featureParentApiForContainer(
        container: container,
        requiredParents: feature.parents.toSet().cast<AnyFeature>(),
        optionalParents: feature.optionalParents.toSet().cast<AnyFeature>(),
      ),
      ownActive = feature.config.activationSetup == null;

  // === Accessors (replace FeatureInternal getters) ===

  /// Returns the scope API. Throws until [construct] has run.
  FeatureScopeApi<TStores> get scopeApi =>
      _scopeApi ??
      (throw FeatureConfigurationError(
        'Scope API of "${feature.name}" accessed before construction.',
        featureName: feature.name,
      ));

  /// Whether [construct] has run successfully on this runtime.
  bool get isResolved => _scopeApi != null;

  /// Reactive store mirroring this feature's current [FeatureStatus]
  /// for this container.
  Store<FeatureStatus> get statusStore => _statusStore;

  /// Public exports record returned to descendants by
  /// [FeatureParentApi.of]. Computed lazily once per cycle through
  /// the feature's typed `applyExportsFactory` (which preserves the
  /// concrete `TStores` / `TExports` generics), memoised for the
  /// lifetime of this runtime.
  TExports get exports {
    if (_exportsComputed) return _exportsCached as TExports;
    final applied = feature.applyExportsFactory(scopeApi);
    _exportsCached = applied as TExports?;
    _exportsComputed = true;
    return _exportsCached as TExports;
  }

  // === Mutators (replace FeatureInternal methods) ===

  /// Framework mutator for [statusStore]. Called by the orchestrator
  /// after every committed graph transition.
  void updateStatusStore(FeatureStatus next) {
    _statusStore.setStatus(next);
  }

  /// Eager construct phase: delegates to [Feature.buildScopeApi],
  /// which knows the feature's concrete generics. On factory throw,
  /// rethrows as a [FeatureResolutionError] tagged with
  /// [FeatureResolutionReason.storesFactoryFailed].
  void construct() {
    if (_scopeApi != null) return;
    try {
      _scopeApi =
          feature.buildScopeApi(container: container, parent: parent)
              as FeatureScopeApi<TStores>;
    } on Object catch (e, st) {
      if (e is FeatureResolutionError) rethrow;
      Error.throwWithStackTrace(
        FeatureResolutionError(
          feature.name,
          'Stores factory for "${feature.name}" threw: $e',
          reason: FeatureResolutionReason.storesFactoryFailed,
        ),
        st,
      );
    }
  }

  /// Per-activation transition. Stores are already constructed here;
  /// we only set up the per-activation [CleanupBag] and await the
  /// user's `onStart` callback if any.
  Future<void> activate({
    required void Function(Object, StackTrace) onError,
  }) async {
    _cleanupOnError = onError;
    currentCleanup = CleanupBag(onError: onError);

    final cb = feature.config.startCallback;
    if (cb == null) return;

    try {
      await runAsUserCallback(() => cb(scopeApi, currentCleanup));
    } on Object catch (e, st) {
      Error.throwWithStackTrace(
        HandlerError.wrap(feature.name, e, source: 'onStart', stackTrace: st),
        st,
      );
    }
  }

  /// Per-activation teardown. Awaits the current cleanup bag and
  /// replaces it with a sealed empty bag — late `cleanup.add(...)`
  /// calls (from a racing async `onStart`) then run the disposer
  /// immediately.
  Future<void> deactivate() async {
    await currentCleanup.runAll();
    currentCleanup = CleanupBag.sealed(onError: _cleanupOnError);
  }

  /// Per-cycle teardown. Runs [lifetimeCleanup], disposes every
  /// tracked user [Store] and the current status store, then resets
  /// every per-cycle field back to its construction default so the
  /// next [AppContainer.start] on the same container can rebuild
  /// fresh state on top.
  ///
  /// References to previous-cycle stores (via `use(...).stores` or
  /// the prior `statusStore`) are stale once this returns — re-fetch
  /// after the next start. Long-lived per-container resources belong
  /// inside a feature's `setup` / `onStart` and its `cleanup` bag, so
  /// they're recreated each cycle automatically.
  Future<void> teardown({
    required void Function(Object, StackTrace) onError,
  }) async {
    await lifetimeCleanup.runAll();

    final scoped = _scopeApi;
    if (scoped != null) {
      for (final store in scoped.storeMap.values) {
        try {
          store.dispose();
        } on Object catch (e, st) {
          onError(e, st);
        }
      }
    }

    try {
      _statusStore.dispose();
    } on Object catch (e, st) {
      onError(e, st);
    }

    _scopeApi = null;
    _exportsCached = null;
    _exportsComputed = false;
    // Restore the construction default so a retry on the same
    // container doesn't pick up a half-toggled flag from the previous
    // cycle. The orchestrator's setup phase will re-run on the next
    // start and may flip this back via toggle().
    ownActive = feature.config.activationSetup == null;
    // Fresh status store so the next cycle's status updates land on
    // an undisposed instance. External holders of a previous-cycle
    // reference get a stale (disposed) store — they must re-fetch
    // via [statusStore].
    _statusStore = _FeatureStatusStore();
    lifetimeCleanup = CleanupBag.sealed();
    currentCleanup = CleanupBag.sealed();
    _cleanupOnError = null;
  }
}
