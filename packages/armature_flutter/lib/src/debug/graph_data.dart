import 'dart:ui' show Offset;

import 'package:armature/advanced.dart'
    show ContainerDebugExt, FeatureDebugInfo, FeatureDependency, PortDebugInfo;
import 'package:armature/armature.dart' show AppContainer, FeatureStatus, Store;
import 'package:meta/meta.dart' show internal;

/// Debug node for the overlay layout. Wraps [FeatureDebugInfo] with
/// layout-mutable fields ([position] / [level]) that
/// [layoutNodes] writes to. Framework-internal.
@internal
class DebugFeatureNode {
  final String name;
  final FeatureStatus status;
  final String? storesType;
  final dynamic storesRecord;
  final List<Store> storeEntries;
  final List<PortDebugInfo> ports;
  final List<String> childNames;
  final List<FeatureDependency> dependencies;
  final Duration? resolveTime;

  Offset position = Offset.zero;
  int level = 0;

  DebugFeatureNode({
    required this.name,
    required this.status,
    required this.storesType,
    required this.storesRecord,
    required this.storeEntries,
    required this.ports,
    required this.childNames,
    required this.dependencies,
    this.resolveTime,
  });

  factory DebugFeatureNode.fromDebugInfo(FeatureDebugInfo info) {
    return DebugFeatureNode(
      name: info.name,
      status: info.status,
      storesType: info.storesRecord?.runtimeType.toString(),
      storesRecord: info.storesRecord,
      storeEntries: info.stores,
      ports: info.ports,
      childNames: info.childNames,
      dependencies: info.dependencies,
      resolveTime: info.resolveTime,
    );
  }
}

/// Builds a name-indexed map of debug nodes for the overlay.
/// Framework-internal.
@internal
Map<String, DebugFeatureNode> extractGraphData(AppContainer container) {
  final nodes = <String, DebugFeatureNode>{};
  for (final info in container.debug.features) {
    nodes[info.name] = DebugFeatureNode.fromDebugInfo(info);
  }
  return nodes;
}
