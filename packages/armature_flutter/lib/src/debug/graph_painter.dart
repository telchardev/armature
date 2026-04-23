import 'dart:ui';

import 'package:armature/armature.dart' show FeatureStatus;
import 'package:flutter/widgets.dart'
    show
        CustomPainter,
        TextDirection,
        TextPainter,
        TextSpan,
        TextStyle,
        FontWeight;
import 'package:meta/meta.dart' show internal;

import './debug_theme.dart';
import './graph_data.dart';
import './graph_layout.dart' show nodeHeight;

/// Paints the feature-dependency DAG shown in the debug overlay.
/// Framework-internal.
@internal
class GraphPainter extends CustomPainter {
  final Map<String, DebugFeatureNode> nodes;
  final String? selectedNodeName;

  /// Name of the node currently being long-press-dragged. Rendered
  /// with an outer-glow highlight so the interaction is visually
  /// obvious — without it, a drag looks like spontaneous motion.
  final String? draggingNodeName;

  GraphPainter(this.nodes, {this.selectedNodeName, this.draggingNodeName});

  /// Hit test: returns feature name if offset hits a node.
  String? hitTestNode(Offset position) {
    for (var node in nodes.values) {
      final h = nodeHeight(node);
      final rect = Rect.fromLTWH(
        node.position.dx,
        node.position.dy,
        kNodeWidth,
        h,
      );
      if (rect.contains(position)) return node.name;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Dot grid — covers entire canvas
    final dotPaint = Paint()..color = const Color(0x18FFFFFF);
    const spacing = 20.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
      }
    }

    // Edges first (behind nodes)
    for (var node in nodes.values) {
      for (var childName in node.childNames) {
        final child = nodes[childName];
        if (child != null) {
          final dep = child.dependencies.where(
            (d) => d.featureName == node.name,
          );
          final isRequired = dep.isNotEmpty && dep.first.isRequired;

          // Highlight: connected to selected → bright, others → dim
          final isHighlighted =
              selectedNodeName == null ||
              node.name == selectedNodeName ||
              child.name == selectedNodeName;

          _drawEdge(
            canvas,
            node,
            child,
            isRequired: isRequired,
            highlighted: isHighlighted,
          );
        }
      }
    }

    // Nodes
    for (var node in nodes.values) {
      _drawNode(
        canvas,
        node,
        isSelected: node.name == selectedNodeName,
        isDragging: node.name == draggingNodeName,
      );
    }
  }

  void _drawEdge(
    Canvas canvas,
    DebugFeatureNode from,
    DebugFeatureNode to, {
    required bool isRequired,
    bool highlighted = true,
  }) {
    final fromH = nodeHeight(from);
    final startX = from.position.dx + kNodeWidth / 2;
    final startY = from.position.dy + fromH + 4;
    final endX = to.position.dx + kNodeWidth / 2;
    final endY = to.position.dy - kArrowSize * 2 - 2;

    final gap = (endY - startY).abs();
    final curveStrength = (gap * 0.45).clamp(40.0, 120.0);

    final baseColor = isRequired ? kRequiredEdgeColor : kOptionalEdgeColor;
    final color = highlighted ? baseColor : baseColor.withAlpha(20);
    final strokeWidth = highlighted ? kEdgeStrokeWidth : 0.8;

    if (isRequired) {
      // Solid curved line
      final paint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(startX, startY)
        ..cubicTo(
          startX,
          startY + curveStrength,
          endX,
          endY - curveStrength,
          endX,
          endY,
        );
      canvas.drawPath(path, paint);
    } else {
      // Dashed curved line
      _drawDashedCurve(
        canvas,
        startX,
        startY,
        endX,
        endY,
        color,
        curveStrength,
      );
    }

    // Arrow head — pointing at node top
    final arrowTipY = to.position.dy - 2;
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(endX, arrowTipY)
      ..lineTo(endX - kArrowSize, arrowTipY - kArrowSize * 1.8)
      ..lineTo(endX + kArrowSize, arrowTipY - kArrowSize * 1.8)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
  }

  void _drawDashedCurve(
    Canvas canvas,
    double x1,
    double y1,
    double x2,
    double y2,
    Color color,
    double curveStrength,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = kEdgeStrokeWidth
      ..style = PaintingStyle.stroke;

    // Approximate curve with line segments, draw dashed
    const segments = 30;
    var dashOn = true;
    var segmentsInDash = 0;
    final dashSegments = (kDashLength / ((y2 - y1) / segments)).ceil().clamp(
      1,
      5,
    );
    final gapSegments = (kDashGap / ((y2 - y1) / segments)).ceil().clamp(1, 3);

    for (var i = 0; i < segments; i++) {
      final t0 = i / segments;
      final t1 = (i + 1) / segments;

      if (dashOn) {
        final p0 = _cubicPoint(
          x1,
          y1,
          x1,
          y1 + curveStrength,
          x2,
          y2 - curveStrength,
          x2,
          y2,
          t0,
        );
        final p1 = _cubicPoint(
          x1,
          y1,
          x1,
          y1 + curveStrength,
          x2,
          y2 - curveStrength,
          x2,
          y2,
          t1,
        );
        canvas.drawLine(p0, p1, paint);
      }

      segmentsInDash++;
      if (dashOn && segmentsInDash >= dashSegments) {
        dashOn = false;
        segmentsInDash = 0;
      } else if (!dashOn && segmentsInDash >= gapSegments) {
        dashOn = true;
        segmentsInDash = 0;
      }
    }
  }

  Offset _cubicPoint(
    double x1,
    double y1,
    double cx1,
    double cy1,
    double cx2,
    double cy2,
    double x2,
    double y2,
    double t,
  ) {
    final mt = 1 - t;
    final mt2 = mt * mt;
    final mt3 = mt2 * mt;
    final t2 = t * t;
    final t3 = t2 * t;

    return Offset(
      mt3 * x1 + 3 * mt2 * t * cx1 + 3 * mt * t2 * cx2 + t3 * x2,
      mt3 * y1 + 3 * mt2 * t * cy1 + 3 * mt * t2 * cy2 + t3 * y2,
    );
  }

  void _drawNode(
    Canvas canvas,
    DebugFeatureNode node, {
    bool isSelected = false,
    bool isDragging = false,
  }) {
    final w = kNodeWidth;
    final h = nodeHeight(node);
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(node.position.dx, node.position.dy, w, h),
      const Radius.circular(kNodeRadius),
    );

    // Drag glow — drawn BEFORE the node fill so the node itself sits
    // on top. A single outer rounded-stroke with two widths (wider +
    // fainter, narrower + brighter) fakes a soft glow without a
    // shadow filter.
    if (isDragging) {
      final glowRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          node.position.dx - 6,
          node.position.dy - 6,
          w + 12,
          h + 12,
        ),
        const Radius.circular(kNodeRadius + 6),
      );
      canvas.drawRRect(
        glowRect,
        Paint()
          ..color = kDragGlowOuter
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      canvas.drawRRect(
        glowRect,
        Paint()
          ..color = kDragGlowInner
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Background
    final bgColor = switch (node.status) {
      FeatureStatus.active => kNodeBgEnabled,
      FeatureStatus.disabled => kNodeBgDisabled,
      FeatureStatus.pending => kNodeBgPending,
    };
    canvas.drawRRect(rect, Paint()..color = bgColor);

    // Border
    final borderColor = switch (node.status) {
      FeatureStatus.active => kEnabledColor,
      FeatureStatus.disabled => kDisabledColor,
      FeatureStatus.pending => kPendingColor,
    };
    canvas.drawRRect(
      rect,
      Paint()
        ..color = isSelected ? const Color(0xFFFFFFFF) : borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : kEdgeStrokeWidth,
    );

    // Status dot
    canvas.drawCircle(
      Offset(node.position.dx + 14, node.position.dy + 18),
      kStatusDotRadius,
      Paint()..color = borderColor,
    );

    var y = node.position.dy + 10;

    // Feature name + resolve time on same line
    final timeStr = node.resolveTime != null
        ? '  ${node.resolveTime!.inMilliseconds}ms'
        : '';
    _drawText(
      canvas,
      node.name,
      Offset(node.position.dx + 24, y),
      w - 28 - (timeStr.isNotEmpty ? 40 : 0),
      kTextWhite,
      bold: true,
      fontSize: 12,
    );
    if (timeStr.isNotEmpty) {
      _drawText(
        canvas,
        timeStr,
        Offset(node.position.dx + w - 44, y + 2),
        40,
        kTextAmber,
        fontSize: 9,
      );
    }
    y += kLineHeight + 4;

    // Stores
    if (node.storesType != null) {
      _drawText(
        canvas,
        '📦 ${node.storesType}',
        Offset(node.position.dx + 12, y),
        w - 16,
        kTextBlue,
        fontSize: 9,
      );
      y += kLineHeight;
    }

    // Ports
    for (var id in node.ports) {
      _drawText(
        canvas,
        '🔌 ${id.name} (${id.type})',
        Offset(node.position.dx + 12, y),
        w - 40,
        kTextPurple,
        fontSize: 9,
      );
      // Handler count in green
      if (id.handlerCount > 0) {
        _drawText(
          canvas,
          '×${id.handlerCount}',
          Offset(node.position.dx + w - 28, y),
          24,
          kEnabledColor,
          bold: true,
          fontSize: 9,
        );
      }
      y += kLineHeight;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    Color color, {
    bool bold = false,
    double fontSize = 11,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    // `DebugFeatureNode` fields (`status`, `position`, `ports`,
    // `handlerCount`, `resolveTime`) mutate in place — node drag and
    // status flips keep the same `nodes` map reference. A content-
    // based compare would have to walk every node on every build, so
    // for the debug overlay we just always repaint: it's cheap
    // relative to the rest of the overlay and avoids silent staleness.
    return true;
  }
}
