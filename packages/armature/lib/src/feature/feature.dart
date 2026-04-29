import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import 'package:armature_graph/armature_graph.dart' show GraphNodeValue;
import 'package:meta/meta.dart' as meta show internal;

import '../container/container.dart' show AppContainer;
import '../errors.dart'
    show
        FeatureConfigurationError,
        FeatureResolutionError,
        FeatureResolutionReason,
        PortError;
import '../logger/logger.dart' show LoggerDebugInfo;
import '../port/behavior.dart'
    show Behavior, BehaviorDescriptor, BehaviorHandler;
import '../port/pipe.dart' show Pipe, PipeHandler;
import '../port/port.dart' show AnyPort;
import '../store/store.dart' show Store;
import './cleanup.dart' show Cleanup;
import './feature_api.dart'
    show
        ExportsFactory,
        FeatureHandlerContext,
        FeatureParentApi,
        FeatureScopeApi,
        StoresFactory;
import './feature_status.dart' show FeatureToggle;

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
/// The bag is sealed on `AppContainer.stop` and all disposers run in LIFO
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

/// Framework-internal record of a single `(port, handler)` binding a
/// feature installed via `usePipe` / `useBehavior` / slot extensions.
///
/// Stored per-feature so each new `AppContainer.start()` installs the
/// handlers into its own per-container handler map (on [AppContainer]),
/// without touching a shared map on the port.
@meta.internal
class PortBinding {
  final AnyPort port;
  final Function handler;

  const PortBinding(this.port, this.handler);
}

/// Immutable configuration for a [Feature]. All fields on this class
/// are either set once at construction or mutated exclusively during
/// the top-level cascade that builds the feature (via
/// `..activation(...)`, `..onStart(...)`, `..usePipe(...)`, `..useBehavior(...)`
/// and the slot extensions from `armature_flutter`). Once the cascade
/// completes, `FeatureConfig` stays read-only for the rest of the
/// process lifetime.
///
/// Per-container mutable state (scope API, status store, cleanup bags,
/// etc.) lives on `FeatureRuntime` — not here.
@meta.internal
final class FeatureConfig<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
> {
  final String name;
  final List<AnyFeature> _dependsOn;
  final List<AnyFeature> _optionalDependsOn;

  final Set<AnyPort> ports = {};
  final List<PortBinding> portBindings = [];

  List<AnyPort>? _portsSnapshot;

  /// Stable unmodifiable view of [ports]. Cached on first read; safe
  /// because [ports] is frozen after the feature's construction
  /// cascade. Used by hot iteration paths (e.g. status-change fanout).
  List<AnyPort> get portsSnapshot =>
      _portsSnapshot ??= List<AnyPort>.unmodifiable(ports);

  StoresFactory<TStores>? storesFactory;
  final ExportsFactory<TStores, TExports>? exportsFactory;

  /// User's imperative activation setup, if any.
  ActivationSetup? activationSetup;

  /// User's onStart callback invoked on every inactive→active transition.
  ///
  /// Stored as a type-erased adapter so AppContainer can invoke it without
  /// knowing [TStores]. [Feature.onStart] installs an adapter that
  /// down-casts the scope API to the feature's concrete type.
  FutureOr<void> Function(FeatureScopeApi<Object?>, Cleanup)? startCallback;

  /// Whether this feature has been constructed by at least one
  /// [AppContainer] since the process started. Set by [FeatureRuntime]
  /// at the end of `buildScopeApi`; checked by [Feature.useStores] to
  /// prevent late factory overrides from silently taking effect only
  /// in subsequent container lifecycles (which usually indicates a
  /// bug).
  bool hasBeenConstructed = false;

  FeatureConfig({
    required this.name,
    List<AnyFeature> dependsOn = const [],
    List<AnyFeature> optionalDependsOn = const [],
    StoresFactory<TStores>? stores,
    ExportsFactory<TStores, TExports>? exports,
  }) : _dependsOn = dependsOn,
       _optionalDependsOn = optionalDependsOn,
       storesFactory = stores,
       exportsFactory = exports;

  /// Required parent features (`dependsOn`). Returned as an
  /// unmodifiable view so callers can't mutate the underlying list.
  late final List<AnyFeature> dependsOn = UnmodifiableListView(_dependsOn);

  /// Optional parent features (`optionalDependsOn`). Returned as an
  /// unmodifiable view.
  late final List<AnyFeature> optionalDependsOn = UnmodifiableListView(
    _optionalDependsOn,
  );
}

/// A modular unit of functionality with typed stores and dependencies.
///
/// Created via [createFeature]. Register handlers with [usePipe],
/// [useBehavior], and slot extensions from `armature_flutter`.
///
/// All per-container runtime state (scope API, status store, cleanup
/// bags, exports cache) lives on `FeatureRuntime` allocated per
/// [AppContainer], *not* on this object. That lets the same `Feature`
/// instance be safely used across multiple concurrent or sequential
/// containers without their state corrupting each other.
final class Feature<
  TStores extends Object?,
  TExports extends Object?,
  TPorts extends Object?
>
    implements GraphNodeValue, LoggerDebugInfo {
  late final FeatureConfig<TStores, TExports, TPorts> _config;

  final TPorts? _portsRecord;

  final String _name;

  /// Typed record of ports **owned** by this feature — the record
  /// passed as `ports:` to [createFeature]. Descendant features reach
  /// for these ports through `thisFeature.ports.myPort` when they
  /// register handlers via `useSingleSlot` / `useMultiSlot` /
  /// `usePipe` / `useBehavior`.
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
    _config = FeatureConfig<TStores, TExports, TPorts>(
      name: name,
      dependsOn: dependsOn,
      optionalDependsOn: optionalDependsOn,
      stores: stores,
      exports: exports,
    );
  }

  /// Registers imperative activation setup — the user wires activation
  /// triggers and uses the provided [FeatureToggle] to set the feature
  /// to `.active` / `.inactive`. Runs once per container lifecycle,
  /// not once total — each [AppContainer] calls the setup against its
  /// own [FeatureRuntime] bindings.
  ///
  /// If omitted, the feature auto-activates at `AppContainer.start`.
  void activation(ActivationSetup setup) {
    if (_config.activationSetup != null) {
      throw FeatureConfigurationError(
        'activation() already called on "$_name" feature.',
        featureName: _name,
      );
    }
    _config.activationSetup = setup;
  }

  @override
  Map<String, String> get debugInfo => {"name": _name};

  /// Framework-internal accessor used by `armature_flutter`, orchestrator
  /// and debug tooling. Application code should not reach into this
  /// object.
  @meta.internal
  FeatureConfig<TStores, TExports, TPorts> get config => _config;

  @override
  String get name => _name;

  @override
  List<GraphNodeValue> get optionalParents => _config.optionalDependsOn;

  @override
  List<GraphNodeValue> get parents => _config.dependsOn;

  @override
  String toString() => 'Feature($_name)';

  /// Registers a callback that runs on each `inactive→active` transition.
  /// Stores are already constructed by the time `onStart` fires (the
  /// container eagerly builds every feature's scope API at `start()`).
  void onStart(StartCallback<TStores> callback) {
    if (_config.startCallback != null) {
      throw FeatureConfigurationError(
        'onStart() already called on "$_name" feature.',
        featureName: _name,
      );
    }
    // Adapter erases TStores in the storage slot while the cast preserves
    // type safety at invocation (scopeApi always matches the feature's
    // concrete TStores at runtime).
    _config.startCallback = (api, cleanup) =>
        callback(api as FeatureScopeApi<TStores>, cleanup);
  }

  /// Registers this feature's [handler] for a parent's [Behavior]
  /// port. Each behavior collects contributions from all features
  /// that registered a handler; the active contribution is picked by
  /// **priority** — highest wins; ties favour the most recently
  /// registered handler.
  void useBehavior<TBranch extends Enum, TPayload>(
    Behavior<TBranch, TPayload, BehaviorHandler<TBranch, TPayload>> port,
    ({TBranch branch, TPayload payload})? Function(FeatureScopeApi<TStores> api)
    handler, {
    int priority = 1,
  }) {
    BehaviorDescriptor<TBranch, TPayload>? wrappedHandler(
      FeatureHandlerContext ctx,
    ) {
      final result = handler(ctx as FeatureScopeApi<TStores>);
      if (result == null) return null;
      return BehaviorDescriptor(
        branch: result.branch,
        payload: result.payload,
        priority: priority,
      );
    }

    recordPortBinding(port, wrappedHandler);
  }

  /// Registers this feature's [handler] as a transformation step in a
  /// parent's [Pipe].
  void usePipe<TValue extends Object>(
    Pipe<TValue, PipeHandler<TValue>> port,
    TValue Function(TValue value, FeatureScopeApi<TStores> api) handler,
  ) {
    TValue wrappedHandler(TValue value, FeatureHandlerContext ctx) =>
        handler(value, ctx as FeatureScopeApi<TStores>);

    recordPortBinding(port, wrappedHandler);
  }

  /// Replaces the stores factory for this feature. Primary use case is
  /// test setup: swap real stores for fakes before a container is
  /// started.
  ///
  /// Must be called **before** any [AppContainer] that uses this
  /// feature reaches its construct phase. Once any container has
  /// constructed this feature (even one that has since been
  /// stopped), further [useStores] calls throw
  /// [FeatureResolutionError] — a late override would silently apply
  /// only to future containers, which is almost always a bug.
  void useStores(StoresFactory<TStores> factory) {
    if (_config.hasBeenConstructed) {
      throw FeatureResolutionError(
        _name,
        'useStores() called after "$_name" already attempted '
        'initialisation; override factories before Container.start().',
        reason: FeatureResolutionReason.storesAlreadyInitialised,
      );
    }
    _config.storesFactory = factory;
  }

  /// Framework-internal helper used by [usePipe], [useBehavior], and
  /// `armature_flutter`'s slot extensions to record a port / handler
  /// pair into this feature's config. Each container installs these
  /// bindings into its own per-container handler map at start.
  ///
  /// Performs eager ownership validation: for a port with a known
  /// owner (set via the `feature:` constructor argument), attempting
  /// to register a handler from the owner itself or from a feature
  /// that doesn't depend on the owner throws [PortError] immediately.
  /// Ports with lazy-bound owners defer that check to container start
  /// time.
  ///
  /// Duplicate registration (same port used twice from the same
  /// feature) also throws here.
  @meta.internal
  void recordPortBinding(AnyPort port, Function handler) {
    final ownershipError = port.validateOwnership(applyingFeature: this);
    if (ownershipError != null) throw ownershipError;
    for (final binding in _config.portBindings) {
      if (identical(binding.port, port)) {
        throw PortError(
          port.name,
          'Port "${port.name}" already used in "$_name" feature',
        );
      }
    }
    _config.ports.add(port);
    _config.portBindings.add(PortBinding(port, handler));
  }

  /// Framework-internal: invokes the exports factory stored on this
  /// feature with a scope api. Callers from outside the feature
  /// (notably [FeatureRuntime.exports]) must go through this method
  /// — reading `_config.exportsFactory` directly from an `AnyFeature`
  /// reference fails at runtime because the generic erasure turns
  /// `ExportsFactory<TStores, TExports>` into a function whose
  /// argument type (`FeatureScopeApi<TStores>`) ends up as
  /// `FeatureScopeApi<Object?>`, which is not in the expected
  /// contravariance relation with the stored typed function.
  ///
  /// Inside this method, `TStores` / `TExports` are the instance's
  /// concrete type parameters, so the cast is safe.
  @meta.internal
  TExports? applyExportsFactory(FeatureScopeApi<TStores> scopeApi) {
    final factory = _config.exportsFactory;
    if (factory == null) return null;
    return factory(scopeApi);
  }

  /// Framework-internal: builds this feature's [FeatureScopeApi] with
  /// the concrete `TStores` type alive. Runs the stores factory inside
  /// [Store.track] so every store constructed during it is auto-
  /// collected into `storeMap`. Called by [FeatureRuntime.construct].
  ///
  /// The scope api is created under this feature's instance-level
  /// generics — not the runtime's erased `Object?` — which keeps the
  /// `ExportsFactory` / typed handler casts safe downstream.
  @meta.internal
  FeatureScopeApi<TStores> buildScopeApi({
    required AppContainer container,
    required FeatureParentApi parent,
  }) {
    TStores? stores;
    var storeMap = const <Type, Store>{};
    final factory = _config.storesFactory;
    if (factory != null) {
      final (result, tracked) = Store.track(() => factory(parent));
      stores = result;
      storeMap = tracked;
    }
    final scope = FeatureScopeApi<TStores>(
      container: container,
      stores: stores as TStores,
      parent: parent,
      storeMap: storeMap,
    );
    _config.hasBeenConstructed = true;
    return scope;
  }
}

/// Creates a [Feature] with typed dependencies, stores, and exports.
///
/// **Contract.** A feature that declares `stores:` must also declare
/// `exports:` — the record returned to descendants via
/// `api.of(thisFeature)`. Use `exports: (api) => api.own` for a
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
