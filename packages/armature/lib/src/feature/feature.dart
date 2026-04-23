import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import 'package:armature_graph/armature_graph.dart' show GraphNodeValue;
import 'package:meta/meta.dart' as meta show internal;

import '../errors.dart'
    show
        FeatureConfigurationError,
        FeatureResolutionError,
        FeatureResolutionReason,
        HandlerError;
import '../logger/logger.dart' show LoggerDebugInfo;
import '../port/behavior.dart'
    show Behavior, BehaviorDescriptor, BehaviorHandler;
import '../port/pipe.dart' show Pipe, PipeHandler;
import '../port/port.dart' show AnyPort;
import '../store/store.dart' show Store;
import '../user_callback_zone.dart' show runAsUserCallback;
import './cleanup.dart' show Cleanup, CleanupBag;
import './feature_api.dart'
    show
        ExportsFactory,
        FeatureHandlerContext,
        FeatureParentApi,
        FeatureScopeApi,
        StoresFactory;
import './feature_status.dart' show FeatureStatus, FeatureToggle;

/// Type alias for a [Feature] with all type parameters erased.
typedef AnyFeature = Feature<dynamic, dynamic, dynamic>;

/// Imperative setup for reactive feature activation.
///
/// Runs once during `AppContainer.start` after auto-active parent features
/// have been activated (so their stores are available via
/// [FeatureParentApi.of]). The user wires whatever triggers their
/// feature's activation state (state subscription, stream, timer) and
/// calls `toggle(state: ...)` with the desired [ToggleState].
///
/// Register teardown for any subscriptions via `cleanup.add(disposer)`.
/// The bag is sealed on `AppContainer.dispose` and all disposers run in LIFO
/// order.
typedef ActivationSetup =
    FutureOr<void> Function(
      FeatureParentApi parentApi,
      FeatureToggle toggle,
      Cleanup cleanup,
    );

/// Per-activation callback run by AppContainer on `inactive→active`
/// transitions. The user registers teardown via `cleanup.add(disposer)` —
/// all registered disposers run in LIFO order on deactivation.
typedef StartCallback<TStores> =
    FutureOr<void> Function(FeatureScopeApi<TStores> api, Cleanup cleanup);

/// Private [Store] subclass whose state mirrors the container's
/// per-feature [FeatureStatus]. Exposes a file-local [set] setter so
/// the framework can write transitions; user code receives a plain
/// `Store<FeatureStatus>` reference.
class _FeatureStatusStore extends Store<FeatureStatus> {
  _FeatureStatusStore() : super(state: FeatureStatus.disabled);

  // ignore: use_setters_to_change_properties — framework-only mutator.
  void set(FeatureStatus next) {
    state = next;
  }
}

/// Framework-internal state bag attached to every [Feature]. Never
/// referenced by application code — reach it only through the `@internal`
/// [Feature.internal] accessor.
@meta.internal
class FeatureInternal<TStores extends Object?, TExports extends Object?> {
  final String _featureName;

  final List<AnyFeature> _dependsOn;

  final List<AnyFeature> _optionalDependsOn;

  final Set<AnyPort> _ports = {};

  StoresFactory<TStores>? _storesFactory;

  final ExportsFactory<TStores, TExports>? _exportsFactory;

  final FeatureParentApi _parent;

  FeatureScopeApi<TStores>? _scopeApi;

  TExports? _exportsCached;
  bool _exportsComputed = false;

  final _FeatureStatusStore _statusStore = _FeatureStatusStore();

  // --- Reactive lifecycle state (driven by AppContainer) ---

  /// User's imperative activation setup, if any.
  @meta.internal
  ActivationSetup? activationSetup;

  /// User's onStart callback invoked on every inactive→active transition.
  ///
  /// Stored as a type-erased adapter so AppContainer can invoke it without
  /// knowing [TStores]. [Feature.onStart] installs an adapter that
  /// down-casts the scope API to the feature's concrete type.
  @meta.internal
  FutureOr<void> Function(FeatureScopeApi<Object?>, Cleanup)? startCallback;

  /// AppContainer-lifetime cleanup bag passed to [activationSetup]. Wired by
  /// the orchestrator layer with an `onError` handler before `start()` runs;
  /// sealed on `AppContainer.dispose`. For features without an activation
  /// setup the bag stays empty and `runAll` is a no-op.
  @meta.internal
  late CleanupBag lifetimeCleanup;

  /// Toggle handle exposed to [activationSetup]. Populated by the
  /// orchestrator layer for every feature during resolution — calling it on
  /// a feature without an activation setup just toggles `ownActive` (the
  /// user has no way to reach the toggle for such features).
  @meta.internal
  late FeatureToggle toggle;

  /// Cleanup bag for the currently-active session. Between activations
  /// it's a pre-sealed empty bag so any late `add` runs the disposer
  /// immediately. Replaced with a fresh open bag inside `_activate`.
  @meta.internal
  CleanupBag currentCleanup = CleanupBag.sealed();

  /// Error sink carried through activations so sealed bags replacing
  /// [currentCleanup] during `deactivate` / `resetForRestart` keep
  /// routing late-`add` disposer failures to the container's
  /// `errorHandler` (rather than silently swallowing them).
  void Function(Object error, StackTrace stack)? _cleanupOnError;

  /// Own-level activation flag. Default `true`; set to `false` when
  /// [activationSetup] is provided until the toggle fires `ToggleState.active`.
  ///
  /// Effective state (own-active AND required parents active) is tracked
  /// by [Graph] via `GraphNodeStatus`, not here.
  @meta.internal
  bool ownActive = true;

  FeatureInternal({
    required AnyFeature feature,
    List<AnyFeature> dependsOn = const [],
    List<AnyFeature> optionalDependsOn = const [],
    StoresFactory<TStores>? stores,
    ExportsFactory<TStores, TExports>? exports,
  }) : _featureName = feature.name,
       _dependsOn = dependsOn,
       _optionalDependsOn = optionalDependsOn,
       _storesFactory = stores,
       _exportsFactory = exports,
       _parent = FeatureParentApi(
         requiredParents: dependsOn.toSet(),
         optionalParents: optionalDependsOn.toSet(),
       );

  Set<AnyPort> get ports => _ports;

  /// True iff this feature's stores were successfully constructed
  /// during the container's construct phase. With eager construction +
  /// fail-fast, this is `true` for every feature after a successful
  /// `AppContainer.start()`, and `false` before `start()` or after a
  /// rolled-back start.
  bool get isResolved => _scopeApi != null;

  /// Parent API for this feature — exposes `.of(parentFeature)` for
  /// typed access to any declared `dependsOn` / `optionalDependsOn`
  /// feature's stores.
  FeatureParentApi get parent => _parent;

  /// Handler/onStart context for this feature. Throws
  /// [FeatureConfigurationError] if accessed before the container's
  /// construct phase has run or after a rolled-back start. After a
  /// successful `AppContainer.start()`, this is always non-null for
  /// every feature — failure to construct any feature aborts `start()`
  /// fail-fast.
  FeatureScopeApi<TStores> get scopeApi =>
      _scopeApi ??
      (throw FeatureConfigurationError(
        'Scope API of "$_featureName" accessed before construction.',
        featureName: _featureName,
      ));

  /// Reactive store mirroring this feature's current [FeatureStatus].
  /// Updated by the container/orchestrator on every lifecycle
  /// transition; user-facing reads (via [FeatureParentApi.statusOf])
  /// return the same instance, which observes `Store<FeatureStatus>`
  /// semantics (reactive inside port reactions, `.subscribe` for
  /// imperative listeners).
  Store<FeatureStatus> get statusStore => _statusStore;

  /// Framework mutator for [statusStore]. Called by the orchestrator
  /// after every committed graph transition; emits atom-level change
  /// notifications so reactive handlers re-evaluate.
  @meta.internal
  void updateStatusStore(FeatureStatus next) {
    _statusStore.set(next);
  }

  /// Public exports record for this feature — what
  /// [FeatureParentApi.of] returns to descendants. Computed lazily on
  /// first external access via the `exports:` factory passed at
  /// [createFeature]; memoised for the feature's lifetime.
  ///
  /// For stateless features (no `stores`, no `exports`) returns `null`
  /// typed as [TExports] (which itself resolves to `Object?`/`Null`
  /// by inference — no consumer has a meaningful type to call on it).
  TExports get exports {
    if (!_exportsComputed) {
      final factory = _exportsFactory;
      if (factory != null) {
        _exportsCached = factory(scopeApi);
      } else {
        // No exports factory — must be a stateless feature
        // (createFeature rejects stores-without-exports up front).
        _exportsCached = null as TExports;
      }
      _exportsComputed = true;
    }
    return _exportsCached as TExports;
  }

  /// Required parent features (`dependsOn`) — narrowed from
  /// [GraphNodeValue] to [AnyFeature] for internal cascade use.
  /// Returned as an unmodifiable view so callers can't mutate the
  /// underlying list and corrupt graph invariants.
  late final List<AnyFeature> parents = UnmodifiableListView(_dependsOn);

  /// Optional parent features (`optionalDependsOn`) — narrowed from
  /// [GraphNodeValue] to [AnyFeature] for internal cascade use.
  /// Returned as an unmodifiable view; mutation attempts throw
  /// [UnsupportedError].
  late final List<AnyFeature> optionalParents = UnmodifiableListView(
    _optionalDependsOn,
  );

  /// Framework-internal — records [port] in this feature's
  /// registered-ports set. Called by [Feature.usePipe] / [Feature.useBehavior]
  /// (and the Flutter slot extensions) right after handler registration,
  /// so the container can enumerate a feature's ports for
  /// `onPortChanged` fan-out on activate/deactivate.
  @meta.internal
  void usePort({required AnyPort port}) {
    _ports.add(port);
  }

  /// Per-activation transition. Stores are already constructed by the
  /// container (eager construct phase); here we only set up the fresh
  /// per-activation [CleanupBag] and await the user's `onStart`
  /// callback if any.
  ///
  /// A failing `onStart` is always **rethrown** as a
  /// [HandlerError] tagged with `source: 'onStart'`. The graph catches
  /// it and settles the feature `.disabled`, then the orchestrator
  /// forwards it to the user's `errorHandler` via
  /// [GraphVisitor.onError]. The supplied [onError] is reserved for
  /// the per-activation cleanup bag; it is invoked whenever a disposer
  /// registered via the `onStart` cleanup bag throws at deactivation
  /// time.
  ///
  /// Status-store / event emission for the `.pending` view is handled
  /// by the container via [GraphVisitor.onStatusChanged] — the graph
  /// fires `.pending` before calling this method, so consumers see the
  /// loader state even for `onStart`s that resolve synchronously.
  @meta.internal
  Future<void> activate({
    required void Function(Object error, StackTrace stack) onError,
  }) async {
    _cleanupOnError = onError;
    currentCleanup = CleanupBag(onError: onError);

    final cb = startCallback;
    if (cb == null) return;

    try {
      // Wrapped in [runAsUserCallback] so dispose() called from inside
      // onStart can be detected and rejected (self-deadlock guard).
      await runAsUserCallback(() => cb(scopeApi, currentCleanup));
    } on Object catch (e, st) {
      // Tag the failure with `source: 'onStart'` and rethrow. Policy
      // (disable vs activate) is an orchestrator concern; this method
      // stays policy-agnostic.
      Error.throwWithStackTrace(
        HandlerError.wrap(_featureName, e, source: 'onStart', stackTrace: st),
        st,
      );
    }
  }

  /// Eager construct phase: runs the stores factory exactly once
  /// during `AppContainer.start()` in topological order. On success,
  /// populates [scopeApi]. On factory throw, rethrows as a
  /// [FeatureResolutionError] tagged with
  /// [FeatureResolutionReason.storesFactoryFailed] — the caller
  /// ([FeatureOrchestrator._runConstructPhase]) lets it propagate to
  /// abort `start()` fail-fast; the polished rollback then disposes
  /// any stores already built by earlier iterations.
  @meta.internal
  void construct() {
    if (_scopeApi != null) return;
    try {
      TStores? stores;
      var storeMap = const <Type, Store>{};

      if (_storesFactory case var factory?) {
        final (result, tracked) = Store.track(() => factory(_parent));
        stores = result;
        storeMap = tracked;
      }

      _scopeApi = FeatureScopeApi(
        stores: stores as TStores,
        parent: _parent,
        storeMap: storeMap,
      );
    } on Object catch (e, st) {
      // Graph/orchestrator expects framework-typed errors, so wrap
      // arbitrary user throws in a FeatureResolutionError. Preserve
      // the original stack trace so the aborted start() points at the
      // actual factory line.
      if (e is FeatureResolutionError) rethrow;
      Error.throwWithStackTrace(
        FeatureResolutionError(
          _featureName,
          'Stores factory for "$_featureName" threw: $e',
          reason: FeatureResolutionReason.storesFactoryFailed,
        ),
        st,
      );
    }
  }

  /// Per-activation teardown. Awaits the current cleanup bag (LIFO,
  /// async disposers awaited; errors routed through the bag's handler)
  /// and replaces it with a sealed empty bag — late `cleanup.add(...)`
  /// calls (from a racing async `onStart`) then run the disposer
  /// immediately, with failures routed through the same `errorHandler`
  /// sink the live bag used.
  @meta.internal
  Future<void> deactivate() async {
    await currentCleanup.runAll();
    currentCleanup = CleanupBag.sealed(onError: _cleanupOnError);
  }

  /// AppContainer-dispose teardown. Awaits the lifetime [lifetimeCleanup]
  /// bag (disposer errors are routed through the bag's own `onError`,
  /// bound when the orchestrator layer created it) and disposes every
  /// tracked [Store]. Store-dispose errors are routed through [onError].
  @meta.internal
  Future<void> teardown({
    required void Function(Object error, StackTrace stack) onError,
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

    // Final dispose: restore `ownActive` to the same default
    // [resetForRestart] uses, so the feature's inspection-visible
    // state is consistent whether the container tore down normally
    // or rolled back. Feature shouldn't be reused after teardown, but
    // debug tooling can still read the field cleanly.
    ownActive = activationSetup == null;
  }

  /// Restores feature-internal state to the freshly-constructed baseline
  /// so a subsequent `AppContainer.start()` call can rebuild everything
  /// from scratch. Invoked only by the polished-rollback path after
  /// [teardown].
  ///
  /// Specifically: drops the cached scope API + stores, replaces
  /// per-activation and lifetime cleanup bags with fresh sealed ones,
  /// and resets `ownActive` to the same default the [FeatureInternal]
  /// constructor / [Feature.activation] established — `false` when an
  /// activation setup is installed (waits for `toggle(.active)`),
  /// `true` otherwise (auto-active).
  @meta.internal
  void resetForRestart() {
    _scopeApi = null;
    _exportsCached = null;
    _exportsComputed = false;
    // Lifetime bag was run by [teardown]; seal it so any stray late
    // `add` runs the disposer immediately. The orchestrator layer installs
    // a fresh open bag when it rebuilds the graph.
    lifetimeCleanup = CleanupBag.sealed();
    currentCleanup = CleanupBag.sealed();
    ownActive = activationSetup == null;
  }

  /// Replaces the stores factory before the feature has been
  /// constructed. Intended for test overrides (e.g. swap in a fake
  /// stores tree). Throws if the scope API has already been built.
  void useStores(StoresFactory<TStores> factory) {
    if (_scopeApi != null) {
      throw FeatureResolutionError(
        _featureName,
        'useStores() called after "$_featureName" already attempted '
        'initialisation; override factories before Container.start().',
        reason: FeatureResolutionReason.storesAlreadyInitialised,
      );
    }
    _storesFactory = factory;
  }
}

/// A modular unit of functionality with typed stores and dependencies.
///
/// Created via [createFeature]. Register handlers with [usePipe],
/// [useBehavior], and slot extensions from `armature_flutter`.
final class Feature<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
>
    implements GraphNodeValue, LoggerDebugInfo {
  late FeatureInternal<TStores, TExports> _internal;

  final TPorts? _portsRecord;

  final String _name;

  /// Typed record of ports **owned** by this feature — the record
  /// passed as `ports:` to [createFeature]. Descendant features reach
  /// for these ports through `thisFeature.ports.myPort` when they
  /// register handlers via `useSingleSlot` / `useMultiSlot` /
  /// `usePipe` / `useBehavior`.
  ///
  /// Throws an assertion in debug builds when the feature was
  /// constructed without a `ports:` record. Use cautiously from
  /// features whose ports record is statically known; stateless
  /// features without ports don't expose this getter in practice.
  TPorts get ports {
    assert(_portsRecord != null, 'No ports declared on "$_name" feature');
    return _portsRecord!;
  }

  Feature({
    required String name,
    List<AnyFeature> dependsOn = const [],
    List<AnyFeature> optionalDependsOn = const [],
    TPorts? ports,
    StoresFactory<TStores>? stores,
    ExportsFactory<TStores, TExports>? exports,
  }) : _name = name,
       _portsRecord = ports {
    _internal = FeatureInternal<TStores, TExports>(
      feature: this,
      dependsOn: dependsOn,
      optionalDependsOn: optionalDependsOn,
      stores: stores,
      exports: exports,
    );
  }

  /// Registers imperative activation setup — the user wires activation
  /// triggers and uses the provided [FeatureToggle] to set the feature
  /// to `.active` / `.inactive`.
  ///
  /// If omitted, the feature auto-activates at `AppContainer.start`.
  ///
  /// The setup callback runs once during `AppContainer.start` after all
  /// auto-active features have been activated (so their stores are
  /// available via [FeatureParentApi.of]). Register teardown for any
  /// subscriptions via `cleanup.add(disposer)` — the bag is sealed on
  /// `AppContainer.dispose`.
  void activation(ActivationSetup setup) {
    if (_internal.activationSetup != null) {
      throw FeatureConfigurationError(
        'activation() already called on "$_name" feature.',
        featureName: _name,
      );
    }
    _internal.activationSetup = setup;
    _internal.ownActive = false; // stays disabled until toggle fires .active
  }

  @override
  Map<String, String> get debugInfo => {"name": _name};

  /// Framework-internal accessor used by `armature_flutter` and debug
  /// tooling. Application code should not reach into this object.
  ///
  /// The return type preserves the feature's type parameters so that
  /// generic fields (like `startCallback`) keep their concrete type
  /// arguments at runtime. Callers that hold an `AnyFeature` see the
  /// `dynamic`-typed view, which opts out of runtime variance checks.
  @meta.internal
  FeatureInternal<TStores, TExports> get internal => _internal;

  @override
  String get name => _name;

  @override
  List<GraphNodeValue> get optionalParents => _internal.optionalParents;

  @override
  List<GraphNodeValue> get parents => _internal.parents;

  @override
  String toString() => 'Feature($_name)';

  /// Registers a callback that runs on each `inactive→active` transition.
  /// Stores are already constructed by the time `onStart` fires (the
  /// container eagerly builds every feature's scope API at `start()`).
  ///
  /// User registers teardown via `cleanup.add(disposer)` — the bag runs
  /// in LIFO order on the next deactivation (or on
  /// `AppContainer.dispose`).
  ///
  /// **Error behaviour.** If the callback throws, the feature settles
  /// in `FeatureStatus.disabled` and its required descendants cascade
  /// closed (fail-closed). The error reaches the container's
  /// `errorHandler` as a [HandlerError] tagged with `source: 'onStart'`.
  /// For best-effort work whose failure should not disable the feature,
  /// wrap the call in a local `try`/`catch` inside the callback body.
  void onStart(StartCallback<TStores> callback) {
    if (_internal.startCallback != null) {
      throw FeatureConfigurationError(
        'onStart() already called on "$_name" feature.',
        featureName: _name,
      );
    }
    // Adapter erases TStores in the storage slot while the cast preserves
    // type safety at invocation (scopeApi always matches the feature's
    // concrete TStores at runtime).
    _internal.startCallback = (api, cleanup) =>
        callback(api as FeatureScopeApi<TStores>, cleanup);
  }

  /// Registers this feature's [handler] for a parent's [Behavior]
  /// port. Each behavior collects contributions from all features
  /// that registered a handler; the active contribution is picked by
  /// **priority** — highest wins; ties favour the most recently
  /// registered handler.
  ///
  /// The handler runs inside a reactive scope on every `port.apply()`:
  /// reads of `api.own.x.state` auto-subscribe the enclosing reaction
  /// so updates re-invalidate the port. Return `(branch, payload)` to
  /// participate, `null` to abstain for this particular evaluation.
  ///
  /// [priority] defaults to `1`. Raise it to deliberately override
  /// lower-priority handlers (e.g. a dark-mode feature that takes
  /// precedence over the default light theme).
  ///
  /// Call this once per port; re-registration throws the same way as
  /// [onStart] / [activation] repeat calls.
  void useBehavior<TBranch extends Enum, TPayload>(
    Behavior<TBranch, TPayload, BehaviorHandler<TBranch, TPayload>> port,
    ({TBranch branch, TPayload payload})? Function(FeatureScopeApi<TStores> api)
    handler, {
    int priority = 1,
  }) {
    BehaviorDescriptor<TBranch, TPayload>? wrappedHandler(
      FeatureHandlerContext _,
    ) {
      final result = handler(_internal.scopeApi);
      if (result == null) return null;
      return BehaviorDescriptor(
        branch: result.branch,
        payload: result.payload,
        priority: priority,
      );
    }

    port.addHandler(handler: wrappedHandler, feature: this);
    _internal.usePort(port: port);
  }

  /// Registers this feature's [handler] as a transformation step in a
  /// parent's [Pipe]. Pipes collect contributions from all features
  /// that registered a handler and compose them **left-to-right** in
  /// insertion order — each handler receives the previous step's
  /// output (or the provider's `initialValue` for the first) and
  /// returns the next value.
  ///
  /// Runs inside a reactive scope: reads of `api.own.x.state` inside
  /// the handler auto-subscribe the enclosing reaction so pipe
  /// re-applies when observed state flips.
  ///
  /// Handlers whose owning feature is not `.active` are skipped — so
  /// deactivating a feature removes its pipe step transparently,
  /// without the provider having to re-wire anything.
  void usePipe<TValue extends Object>(
    Pipe<TValue, PipeHandler<TValue>> port,
    TValue Function(TValue value, FeatureScopeApi<TStores> api) handler,
  ) {
    TValue wrappedHandler(TValue value, FeatureHandlerContext _) =>
        handler(value, _internal.scopeApi);

    port.addHandler(handler: wrappedHandler, feature: this);
    _internal.usePort(port: port);
  }

  /// Replaces the stores factory for this feature. Primary use case
  /// is test setup: swap real stores for fakes without reconstructing
  /// the feature.
  ///
  /// Must be called **before** `AppContainer.start()`. Calling after
  /// the container's construct phase has built this feature's scope
  /// API throws [FeatureResolutionError] with reason
  /// [FeatureResolutionReason.storesAlreadyInitialised] — re-starting
  /// the container via polished rollback re-opens the window for
  /// further overrides.
  ///
  /// The replacement factory must have the same `TStores` type as the
  /// original; the `exports:` factory attached at [createFeature] is
  /// re-run against the new stores on the next `api.from(thisFeature)`
  /// access.
  void useStores(StoresFactory<TStores> factory) {
    _internal.useStores(factory);
  }
}

/// Creates a [Feature] with typed dependencies, stores, and exports.
///
/// **Contract.** A feature that declares `stores:` must also declare
/// `exports:` — the record returned to descendants via
/// `api.from(thisFeature)`. Use `exports: (api) => api.own` for a
/// passthrough (stores visible as-is); narrow the record to hide
/// implementation details.
///
/// Stateless features (no `stores:`, typically pure port extensions)
/// may omit both.
///
/// Throws [FeatureConfigurationError] when `stores` is provided without
/// `exports`.
Feature<TStores, TExports, TPorts> createFeature<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
>({
  required String name,
  List<AnyFeature> dependsOn = const [],
  List<AnyFeature> optionalDependsOn = const [],
  TPorts? ports,
  StoresFactory<TStores>? stores,
  ExportsFactory<TStores, TExports>? exports,
}) {
  if (stores != null && exports == null) {
    throw FeatureConfigurationError(
      '"$name": feature with `stores:` must also declare `exports:`. '
      'Use `exports: (api) => api.own` for a passthrough view, '
      'or narrow the exposed surface explicitly.',
      featureName: name,
    );
  }
  return Feature(
    name: name,
    dependsOn: dependsOn,
    optionalDependsOn: optionalDependsOn,
    ports: ports,
    stores: stores,
    exports: exports,
  );
}
