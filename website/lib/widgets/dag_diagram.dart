import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One node in a [DagDiagram].
///
/// The [id] is used for edge resolution; [label] is rendered on the card.
/// [parentIds] list the nodes this one depends on — edges are drawn from
/// each parent (top) down to this node (bottom). Optional [accent] tints
/// the node's border.
class DagNode {
  const DagNode({
    required this.id,
    required this.label,
    this.parentIds = const [],
    this.accent,
  });

  final String id;
  final String label;
  final List<String> parentIds;
  final Color? accent;
}

/// Auto-laid-out DAG illustration.
///
/// Nodes are placed on horizontal rows by topological level (max parent
/// level + 1). Each row is centered within the canvas; edges are drawn
/// as straight lines with arrowheads terminating at each child.
class DagDiagram extends StatelessWidget {
  const DagDiagram({
    super.key,
    required this.nodes,
    this.nodeWidth = 160,
    this.nodeHeight = 56,
    this.colGap = 24,
    this.rowGap = 56,
  });

  final List<DagNode> nodes;
  final double nodeWidth;
  final double nodeHeight;
  final double colGap;
  final double rowGap;

  @override
  Widget build(BuildContext context) {
    final levels = _computeLevels();
    final maxPerLevel = levels
        .map((l) => l.length)
        .reduce((a, b) => math.max(a, b));
    final canvasWidth = maxPerLevel * nodeWidth + (maxPerLevel - 1) * colGap;
    final canvasHeight =
        levels.length * nodeHeight + (levels.length - 1) * rowGap;

    // Compute top-left positions for every node.
    final positions = <String, Offset>{};
    for (int li = 0; li < levels.length; li++) {
      final level = levels[li];
      final rowWidth = level.length * nodeWidth + (level.length - 1) * colGap;
      final startX = (canvasWidth - rowWidth) / 2;
      for (int ni = 0; ni < level.length; ni++) {
        final x = startX + ni * (nodeWidth + colGap);
        final y = li * (nodeHeight + rowGap);
        positions[level[ni].id] = Offset(x, y);
      }
    }

    final edges = <(String from, String to)>[];
    for (final n in nodes) {
      for (final p in n.parentIds) {
        edges.add((p, n.id));
      }
    }

    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(canvasWidth, canvasHeight),
                painter: _EdgesPainter(
                  edges: edges,
                  positions: positions,
                  nodeWidth: nodeWidth,
                  nodeHeight: nodeHeight,
                  color: scheme.outline,
                ),
              ),
              for (final node in nodes)
                Positioned(
                  left: positions[node.id]!.dx,
                  top: positions[node.id]!.dy,
                  width: nodeWidth,
                  height: nodeHeight,
                  child: _NodeCard(node: node),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Groups nodes into rows by topological level (root = 0).
  List<List<DagNode>> _computeLevels() {
    final byId = {for (final n in nodes) n.id: n};
    final levels = <String, int>{};

    int levelOf(String id) {
      final cached = levels[id];
      if (cached != null) {
        return cached;
      }
      final node = byId[id]!;
      if (node.parentIds.isEmpty) {
        return levels[id] = 0;
      }
      final maxParent = node.parentIds
          .map(levelOf)
          .reduce((a, b) => math.max(a, b));
      return levels[id] = maxParent + 1;
    }

    for (final n in nodes) {
      levelOf(n.id);
    }

    final result = <List<DagNode>>[];
    for (final n in nodes) {
      final level = levels[n.id]!;
      while (result.length <= level) {
        result.add([]);
      }
      result[level].add(n);
    }
    return result;
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});

  final DagNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = node.accent ?? scheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 1.5),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        node.label,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.edges,
    required this.positions,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.color,
  });

  final List<(String from, String to)> edges;
  final Map<String, Offset> positions;
  final double nodeWidth;
  final double nodeHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const arrowSize = 5.0;

    for (final (from, to) in edges) {
      final fromPos = positions[from]!;
      final toPos = positions[to]!;
      final start = Offset(fromPos.dx + nodeWidth / 2, fromPos.dy + nodeHeight);
      // Stop the line 1px above the node so the arrow touches it cleanly.
      final end = Offset(toPos.dx + nodeWidth / 2, toPos.dy - 1);
      canvas.drawLine(start, end, linePaint);

      final arrowPath = Path()
        ..moveTo(end.dx, end.dy + 1)
        ..lineTo(end.dx - arrowSize, end.dy - arrowSize * 1.4)
        ..lineTo(end.dx + arrowSize, end.dy - arrowSize * 1.4)
        ..close();
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.edges != edges ||
      oldDelegate.positions != positions;
}
