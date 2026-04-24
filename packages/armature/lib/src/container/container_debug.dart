import 'package:armature_graph/armature_graph.dart' show GraphNode;

import '../errors.dart' show ContainerUsageError;
import '../feature/feature.dart' show AnyFeature;
import '../feature/feature_status.dart' show FeatureStatus;
import '../port/port_type.dart' show PortType;
import '../store/store.dart' show Store;
import './container.dart' show AppContainer, ContainerStatus;

/// Structured, read-only snapshot of an [AppContainer] for debug tooling.
///
/// Returned by [AppContainer.debug]. Decouples debug/inspection
/// consumers (such as the `armature_flutter` graph overlay) from the
/// container's framework-internal fields — they read a plain data
/// snapshot instead of reaching into runtime state, ports, or the
/// orchestrator directly.
class ContainerDebug {
  /// Features in topological order — parents before children.
  final List<FeatureDebugInfo> features;

  ContainerDebug({required this.features});
}

/// Debug info for a single feature.
class FeatureDebugInfo {
  final String name;
  final FeatureStatus status;
  final List<PortDebugInfo> ports;
  final List<FeatureDependency> dependencies;
  final List<Store> stores;

  /// Raw stores record returned by the feature's `stores` factory.
  /// `null` if the feature has no factory or has not been activated yet.
  final Object? storesRecord;

  /// Names of features that depend on this one (direct children).
  final List<String> childNames;

  /// Time taken by the feature's most recent activation, or `null` if it
  /// never activated.
  final Duration? resolveTime;

  FeatureDebugInfo({
    required this.name,
    required this.status,
    required this.ports,
    required this.dependencies,
    required this.childNames,
    required this.stores,
    required this.storesRecord,
    required this.resolveTime,
  });
}

/// Debug info for a single port registered by a feature.
class PortDebugInfo {
  final String name;
  final PortType type;
  final int handlerCount;
  final List<String> handlerFeatureNames;

  PortDebugInfo({
    required this.name,
    required this.type,
    required this.handlerCount,
    required this.handlerFeatureNames,
  });
}

/// A parent-of link from one feature to another with required/optional
/// distinction.
class FeatureDependency {
  final String featureName;
  final bool isRequired;

  FeatureDependency({required this.featureName, required this.isRequired});
}

/// Builds a fresh [ContainerDebug] snapshot. Re-invoke to refresh — nothing
/// is cached; each call walks the live graph.
///
/// Throws [ContainerUsageError] if the container is disposed (the graph
/// is still referenced after teardown but the snapshot would describe a
/// torn-down state), or if the graph has not yet been built — i.e.
/// before the first successful `start()` or after a rolled-back start.
extension ContainerDebugExt on AppContainer {
  ContainerDebug get debug {
    if (status == ContainerStatus.disposed) {
      throw ContainerUsageError(
        'AppContainer.debug is unavailable after dispose().',
      );
    }
    final g = graph;
    final nodeByValue = <AnyFeature, GraphNode<AnyFeature>>{};
    for (final root in g.rootNodes) {
      _collectNodes(root, nodeByValue);
    }

    final features = <FeatureDebugInfo>[];
    for (final value in g.topologicalOrder()) {
      final node = nodeByValue[value];
      if (node == null) continue;
      features.add(_buildFeatureDebugInfo(value, node));
    }
    return ContainerDebug(features: features);
  }

  FeatureDebugInfo _buildFeatureDebugInfo(
    AnyFeature feature,
    GraphNode<AnyFeature> node,
  ) {
    final dependencies = [
      for (final parent in node.parents)
        FeatureDependency(
          featureName: parent.value.name,
          isRequired: node.isRequired(parent),
        ),
    ];

    final ports = [
      for (final p in feature.config.ports)
        PortDebugInfo(
          name: p.name,
          type: p.type,
          handlerCount: handlersOf(p).length,
          handlerFeatureNames: [for (final f in handlersOf(p).keys) f.name],
        ),
    ];

    final runtime = runtimeOf(feature);
    final scopeApi = runtime.isResolved ? runtime.scopeApi : null;

    return FeatureDebugInfo(
      name: feature.name,
      status: statusOf(feature),
      ports: ports,
      dependencies: dependencies,
      childNames: [for (final c in node.children) c.value.name],
      stores: scopeApi?.storeMap.values.toList(growable: false) ?? const [],
      storesRecord: scopeApi?.stores,
      resolveTime: resolveTimes[feature.name],
    );
  }
}

void _collectNodes(
  GraphNode<AnyFeature> node,
  Map<AnyFeature, GraphNode<AnyFeature>> into,
) {
  if (into.containsKey(node.value)) return;
  into[node.value] = node;
  for (final child in node.children) {
    _collectNodes(child, into);
  }
}
