import 'package:armature/armature.dart' show FeatureStatus;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import './debug_theme.dart';
import './graph_data.dart';
import './graph_layout.dart';

/// Small overview of the graph with a viewport indicator.
/// Framework-internal.
@internal
class Minimap extends StatefulWidget {
  final Map<String, DebugFeatureNode> nodes;
  final Size canvasSize;
  final TransformationController controller;
  final Size screenSize;

  const Minimap({
    super.key,
    required this.nodes,
    required this.canvasSize,
    required this.controller,
    required this.screenSize,
  });

  @override
  State<Minimap> createState() => _MinimapState();
}

class _MinimapState extends State<Minimap> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(Minimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      // Swap listener from old controller to new one.
      oldWidget.controller.removeListener(_onTransformChanged);
      widget.controller.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTransformChanged);
    super.dispose();
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  Rect _getViewportRect(Size minimapSize) {
    final matrix = widget.controller.value;
    final scale = matrix.storage[0];
    final tx = matrix.storage[12];
    final ty = matrix.storage[13];

    final screenSize = widget.screenSize;
    if (scale <= 0 || widget.canvasSize.width == 0 || screenSize == Size.zero) {
      return Rect.zero;
    }

    final mx = minimapSize.width / widget.canvasSize.width;
    final my = minimapSize.height / widget.canvasSize.height;

    final canvasX = -tx / scale;
    final canvasY = -ty / scale;
    final canvasW = screenSize.width / scale;
    final canvasH = screenSize.height / scale;

    return Rect.fromLTWH(
      canvasX * mx,
      canvasY * my,
      canvasW * mx,
      canvasH * my,
    );
  }

  @override
  Widget build(BuildContext context) {
    const minimapSize = Size(140, 90);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMinimapBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kMinimapBorder),
      ),
      child: SizedBox(
        width: minimapSize.width,
        height: minimapSize.height,
        child: CustomPaint(
          painter: _MinimapPainter(
            widget.nodes,
            widget.canvasSize,
            _getViewportRect(minimapSize),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final Map<String, DebugFeatureNode> nodes;
  final Size canvasSize;
  final Rect viewportRect;

  _MinimapPainter(this.nodes, this.canvasSize, this.viewportRect);

  @override
  void paint(Canvas canvas, Size size) {
    if (canvasSize.width == 0 || canvasSize.height == 0) return;

    final sx = size.width / canvasSize.width;
    final sy = size.height / canvasSize.height;

    final edgePaint = Paint()
      ..color = kMinimapEdge
      ..strokeWidth = 0.5;

    for (final node in nodes.values) {
      for (final childName in node.childNames) {
        final child = nodes[childName];
        if (child != null) {
          canvas.drawLine(
            Offset(
              (node.position.dx + kNodeWidth / 2) * sx,
              (node.position.dy + 10) * sy,
            ),
            Offset(
              (child.position.dx + kNodeWidth / 2) * sx,
              child.position.dy * sy,
            ),
            edgePaint,
          );
        }
      }
    }

    for (final node in nodes.values) {
      final color = switch (node.status) {
        FeatureStatus.active => kEnabledColor,
        FeatureStatus.disabled => kDisabledColor,
        FeatureStatus.pending => kPendingColor,
      };
      canvas.drawRect(
        Rect.fromLTWH(
          node.position.dx * sx,
          node.position.dy * sy,
          kNodeWidth * sx,
          nodeHeight(node) * sy,
        ),
        Paint()..color = color.withAlpha(150),
      );
    }

    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = kMinimapViewport
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) {
    // Node fields mutate in place; always repaint (debug overlay).
    return true;
  }
}
