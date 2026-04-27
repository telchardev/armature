import 'dart:async' show unawaited;

import '../store/store.dart' show Store;
import './feature.dart' show ActivationSetup, AnyFeature, Feature;
import './feature_status.dart' show FeatureStatus, ToggleState;

/// Activation setup that installs **no triggers** — the feature stays
/// [FeatureStatus.disabled] until driven externally via
/// `AppContainer.toggleFeature(feature, ToggleState.active)`.
///
/// Sugar for `..activation((_, _, _) {})`, documented as a first-class
/// pattern.
///
/// ```dart
/// final externallyDrivenFeature = createFeature(name: 'ExternallyDriven')
///   ..activation(manualActivation());
/// ```
ActivationSetup manualActivation() {
  return (parentApi, toggle, cleanup) {};
}

/// Activation setup that gates the feature on a [Store] reached through
/// a declared parent feature's exports.
///
/// Subscribes to [store] with `fireImmediately: true`, then calls
/// `toggle(.active)` whenever [predicate] evaluates to `true` for the
/// store's current state, `.inactive` otherwise. The subscription
/// disposer is registered on the activation's `cleanup` bag — it
/// unsubscribes automatically on container stop.
///
/// ```dart
/// inspectorFeature
///   ..activation(whenStoreState(
///     feature: featureTogglesFeature,
///     store: (exports) => exports.featureToggles,
///     predicate: (state) => state.inspector,
///   ));
/// ```
///
/// The [feature] must appear in the owning feature's `dependsOn` or
/// `optionalDependsOn` list — `api.of(feature)` will throw
/// `FeatureResolutionError` otherwise (standard parent-API contract).
ActivationSetup whenStoreState<TExports, TState>({
  required Feature<dynamic, TExports, dynamic> feature,
  required Store<TState> Function(TExports exports) store,
  required bool Function(TState state) predicate,
}) {
  return (parentApi, toggle, cleanup) {
    final target = store(parentApi.of(feature));
    cleanup.subscribe(target, (_, state) {
      unawaited(
        toggle(predicate(state) ? ToggleState.active : ToggleState.inactive),
      );
    }, fireImmediately: true);
  };
}

/// Activation setup that mirrors a declared parent [feature]'s lifecycle —
/// the owning feature toggles `.active` whenever [feature] is
/// [FeatureStatus.active], `.inactive` otherwise.
///
/// Subscribes to the parent's status store via
/// `parentApi.statusOf(feature)`. The per-container status store lives
/// on the feature's runtime, so every container that uses this helper
/// gets its own independent subscription wired up at activation time.
///
/// ```dart
/// final decoratorFeature = createFeature(
///   name: 'Decorator',
///   optionalDependsOn: [inspectorFeature],
/// )..activation(whenActive(inspectorFeature));
/// ```
///
/// The [feature] must appear in the caller's `dependsOn` or
/// `optionalDependsOn` list.
ActivationSetup whenActive(AnyFeature feature) {
  return (parentApi, toggle, cleanup) {
    final statusStore = parentApi.statusOf(feature);
    cleanup.subscribe(statusStore, (_, status) {
      unawaited(
        toggle(
          status == FeatureStatus.active
              ? ToggleState.active
              : ToggleState.inactive,
        ),
      );
    }, fireImmediately: true);
  };
}

/// Inverse of [whenActive] — the owning feature is active while
/// [feature] is **not** `FeatureStatus.active` (i.e. `.disabled` or
/// `.pending`). Useful for fallback / "offline" UI features that live
/// only while their main counterpart is off.
///
/// ```dart
/// final loginPromptFeature = createFeature(
///   name: 'LoginPrompt',
///   optionalDependsOn: [sessionFeature],
/// )..activation(whenInactive(sessionFeature));
/// ```
ActivationSetup whenInactive(AnyFeature feature) {
  return (parentApi, toggle, cleanup) {
    final statusStore = parentApi.statusOf(feature);
    cleanup.subscribe(statusStore, (_, status) {
      unawaited(
        toggle(
          status != FeatureStatus.active
              ? ToggleState.active
              : ToggleState.inactive,
        ),
      );
    }, fireImmediately: true);
  };
}

/// Activation setup that stays `.active` only while **every** parent in
/// [features] is [FeatureStatus.active]. Any parent flipping away from
/// `.active` deactivates the owning feature; a return to "all active"
/// re-activates it.
///
/// Every entry must be in the caller's `dependsOn` / `optionalDependsOn`
/// list. An empty [features] list makes the feature permanently active.
///
/// ```dart
/// final fullyOnlineFeature = createFeature(
///   name: 'FullyOnline',
///   dependsOn: [networkFeature, sessionFeature],
/// )..activation(whenAllActive([networkFeature, sessionFeature]));
/// ```
ActivationSetup whenAllActive(List<AnyFeature> features) {
  return (parentApi, toggle, cleanup) {
    if (features.isEmpty) {
      unawaited(toggle(ToggleState.active));
      return;
    }
    final stores = [for (final f in features) parentApi.statusOf(f)];
    void reevaluate() {
      final allActive = stores.every((s) => s.state == FeatureStatus.active);
      unawaited(toggle(allActive ? ToggleState.active : ToggleState.inactive));
    }

    for (final store in stores) {
      cleanup.subscribe(store, (_, _) => reevaluate());
    }
    reevaluate();
  };
}
