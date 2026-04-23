import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:meta/meta.dart' show internal;

import './debug_theme.dart';
import './graph_data.dart';

/// Calculate height of a node based on its content. Framework-internal.
@internal
double nodeHeight(DebugFeatureNode node) {
  var lines = 1; // name line (includes resolve time)
  if (node.storesType != null) lines++;
  lines += node.ports.length;
  return kNodeBaseHeight + lines * kLineHeight;
}

/// Position all nodes in a layered graph layout.
/// Returns the total canvas size needed. Framework-internal.
@internal
Size layoutNodes(Map<String, DebugFeatureNode> nodes) {
  if (nodes.isEmpty) return Size.zero;

  // Find root nodes (no feature depends on them as a parent)
  final allChildNames = nodes.values.expand((n) => n.childNames).toSet();
  final roots = nodes.values
      .where((n) => !allChildNames.contains(n.name))
      .toList();

  // If no roots found (circular?), use first node
  if (roots.isEmpty && nodes.isNotEmpty) {
    roots.add(nodes.values.first);
  }

  // Assign levels via BFS
  for (var root in roots) {
    _assignLevel(root, 0, nodes);
  }

  // Group by level
  final levels = <int, List<DebugFeatureNode>>{};
  for (var node in nodes.values) {
    levels.putIfAbsent(node.level, () => []).add(node);
  }

  // Calculate positions
  final maxNodesInLevel = levels.values.fold(
    0,
    (int max, list) => math.max(max, list.length),
  );
  final totalWidth = maxNodesInLevel * (kNodeWidth + kSiblingGap);

  var maxX = 0.0;
  var maxY = 0.0;

  for (var entry in levels.entries) {
    final level = entry.key;
    final levelNodes = entry.value;
    final levelWidth =
        levelNodes.length * (kNodeWidth + kSiblingGap) - kSiblingGap;
    final startX = (totalWidth - levelWidth) / 2;

    for (var i = 0; i < levelNodes.length; i++) {
      final x = startX + i * (kNodeWidth + kSiblingGap);
      final y = level * kLevelGap;
      levelNodes[i].position = Offset(x, y);

      final h = nodeHeight(levelNodes[i]);
      maxX = math.max(maxX, x + kNodeWidth);
      maxY = math.max(maxY, y + h);
    }
  }

  return Size(maxX + 40, maxY + 40);
}

void _assignLevel(
  DebugFeatureNode node,
  int level,
  Map<String, DebugFeatureNode> nodes, [
  Set<DebugFeatureNode>? stack,
]) {
  // Cycle guard: track nodes on the current DFS path. A cycle in
  // `childNames` (e.g. A → B → A) would otherwise recurse indefinitely
  // with ever-growing `level`. `AppContainer` rejects cycles at
  // `start()`, but this debug layout may run on partial / synthetic
  // snapshots too. Using a per-walk stack rather than a visited set so
  // diamond shapes (same node reached via two distinct root paths)
  // still raise the level correctly.
  final path = stack ?? <DebugFeatureNode>{};
  if (!path.add(node)) return;
  try {
    if (node.level < level) node.level = level;
    for (var childName in node.childNames) {
      final child = nodes[childName];
      if (child != null) {
        _assignLevel(child, level + 1, nodes, path);
      }
    }
  } finally {
    path.remove(node);
  }
}
