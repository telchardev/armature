import 'package:meta/meta.dart';

import '../container/container.dart' show AppContainer;
import '../errors.dart'
    show FeatureResolutionError, FeatureResolutionReason, StoreLookupError;
import '../store/store.dart' show Store;
import './feature.dart' show AnyFeature, Feature;
import './feature_status.dart' show FeatureStatus;

/// Synchronous factory that builds this feature's stores record. Runs
/// once during `AppContainer.start`'s construct phase with the feature's
/// [FeatureParentApi], so it can reach already-built parent stores.
typedef StoresFactory<TStores> = TStores Function(FeatureParentApi parentApi);

/// Synchronous factory that builds this feature's public exports record.
///
/// Receives a [FeatureScopeApi] pointing at this feature's already-built
/// stores; returns whatever record / object the feature wants to expose
/// to child features via `api.of(thisFeature)`. Run once (memoized) on
/// first external access.
///
/// Use `(api) => api.own` for a passthrough view that mirrors stores;
/// narrow the record to hide implementation details.
typedef ExportsFactory<TStores, TExports> =
    TExports Function(FeatureScopeApi<TStores> api);

/// Provides typed access to parent feature stores for a specific
/// [AppContainer].
///
/// Each container gets its own [FeatureParentApi] per feature (allocated
/// by that container's [FeatureRuntime]) — so `parentApi.of(x)` resolves
/// through the same container's runtime for `x`, never leaking into
/// another container's state.
class FeatureParentApi {
  final AppContainer _container;
  final Set<AnyFeature> _requiredParents;
  final Set<AnyFeature> _optionalParents;

  FeatureParentApi._({
    required AppContainer container,
    required Set<AnyFeature> requiredParents,
    required Set<AnyFeature> optionalParents,
  }) : _container = container,
       _requiredParents = requiredParents,
       _optionalParents = optionalParents;

  /// Returns typed exports of a declared parent [feature] — either
  /// required (`dependsOn`) or optional (`optionalDependsOn`).
  ///
  /// Throws [FeatureResolutionError] with reason
  /// [FeatureResolutionReason.notDeclaredParent] if [feature] is not in
  /// the caller's `dependsOn` or `optionalDependsOn` list.
  TExports of<TExports>(Feature<dynamic, TExports, dynamic> feature) {
    _ensureDeclaredParent(feature);
    return _container.runtimeOf(feature).exports as TExports;
  }

  /// Returns a reactive [Store] mirroring the declared parent
  /// [feature]'s current [FeatureStatus] **for this container**.
  ///
  /// Reads inside a reaction-tracked scope subscribe the enclosing
  /// reaction — transitions fire automatic re-evaluation.
  Store<FeatureStatus> statusOf(AnyFeature feature) {
    _ensureDeclaredParent(feature);
    return _container.runtimeOf(feature).statusStore;
  }

  /// Shared guard for [of] / [statusOf]. Throws
  /// [FeatureResolutionError] with [FeatureResolutionReason.notDeclaredParent]
  /// when [feature] is absent from both parent sets.
  void _ensureDeclaredParent(AnyFeature feature) {
    if (_requiredParents.contains(feature) ||
        _optionalParents.contains(feature)) {
      return;
    }
    throw FeatureResolutionError(
      feature.name,
      'Feature "${feature.name}" is not a declared parent.',
      reason: FeatureResolutionReason.notDeclaredParent,
    );
  }
}

/// Framework-only factory for a container-scoped [FeatureParentApi].
/// Used by [FeatureRuntime]; not for application code.
@internal
FeatureParentApi featureParentApiForContainer({
  required AppContainer container,
  required Set<AnyFeature> requiredParents,
  required Set<AnyFeature> optionalParents,
}) => FeatureParentApi._(
  container: container,
  requiredParents: requiredParents,
  optionalParents: optionalParents,
);

/// Context passed to port handlers (`usePipe` / `useBehavior` /
/// slot handlers). Exposes the feature's own stores plus a
/// [parent] accessor for declared parent stores and a [container]
/// reference for framework-internal plumbing.
///
/// The typed subclass [FeatureScopeApi] is what `onStart` and
/// activation `setup` receive — prefer its `.own` accessor for typed
/// access to this feature's stores.
class FeatureHandlerContext {
  /// The container that owns this context. Framework-internal: used by
  /// custom [Port] implementations that need to look up feature
  /// runtimes. User code should not read this.
  @internal
  final AppContainer container;

  /// Typed accessor for any declared parent feature's stores via
  /// `parent.of(parentFeature)`. See [FeatureParentApi].
  final FeatureParentApi parent;

  /// Raw (untyped) own-stores record. Marked `@internal` — framework
  /// code (notably [FeatureScopeApi.own]) projects it into a typed
  /// view; user code outside `armature` should reach for `.own` instead
  /// of this `dynamic` field.
  @internal
  final dynamic stores;

  /// Map of [Store] instances constructed inside the feature's
  /// `stores` factory, keyed by runtime type. Populated via
  /// zone-tracking in [Store.track]; powers [store]-by-type lookups
  /// and debug tooling.
  final Map<Type, Store> storeMap;

  @internal
  FeatureHandlerContext({
    required this.container,
    required this.parent,
    this.stores,
    this.storeMap = const {},
  });

  /// Returns typed exports of a parent [feature]. See
  /// [FeatureParentApi.of].
  TExports of<TExports>(Feature<dynamic, TExports, dynamic> feature) {
    return parent.of(feature);
  }

  /// Returns a reactive `Store<FeatureStatus>` for a declared parent
  /// [feature]. Equivalent to [FeatureParentApi.statusOf] delegating to
  /// [parent].
  Store<FeatureStatus> statusOf(AnyFeature feature) {
    return parent.statusOf(feature);
  }

  /// Look up a [Store] by its runtime type.
  ///
  /// Throws [StoreLookupError] if the store is not in the feature's
  /// tracked map. Stores are tracked when they are constructed **inside**
  /// the `stores: (parent) => ...` factory of a feature — any instance
  /// created outside that factory (e.g. a top-level `final`, a lambda
  /// inside `activation`, or a test fixture) is not visible to this
  /// lookup.
  T store<T extends Store>() {
    final s = storeMap[T];
    if (s == null) {
      final available = storeMap.keys.join(', ');
      final availableText = available.isEmpty ? '<none>' : available;
      throw StoreLookupError(
        T,
        'Store of type $T not found. Available: $availableText. '
        'Tip: stores are tracked only when constructed inside the '
        '`stores: (parent) => ...` factory. If you built the store '
        'outside the factory, inject it via the factory instead.',
      );
    }
    return s as T;
  }
}

/// Typed scope passed into a feature's own callbacks — activation
/// `setup`, `onStart`, and port handlers registered via `usePipe` /
/// `useBehavior`.
///
/// Extends [FeatureHandlerContext] with the strongly-typed [own]
/// accessor; [parent] / `.of()` / `.store<T>()` are inherited.
class FeatureScopeApi<TStores> extends FeatureHandlerContext {
  /// This feature's own typed stores record.
  TStores get own => stores as TStores;

  @internal
  FeatureScopeApi({
    required super.container,
    required TStores super.stores,
    required super.parent,
    super.storeMap,
  });
}
