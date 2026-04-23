import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import './debug_theme.dart';

/// Color / edge / icon legend strip shown in the debug overlay.
/// Framework-internal — consumed only by `FeatureGraphOverlay` and
/// siblings.
@internal
class GraphLegend extends StatelessWidget {
  const GraphLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: const [
          _LegendItem(color: kEnabledColor, label: 'Enabled'),
          _LegendItem(color: kDisabledColor, label: 'Disabled'),
          _LegendItem(color: kPendingColor, label: 'Pending'),
          _LegendLine(dashed: false, label: 'Required dep'),
          _LegendLine(dashed: true, label: 'Optional dep'),
          _LegendIcon(icon: '📦', label: 'Stores'),
          _LegendIcon(icon: '🔌', label: 'Port'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 8, height: 8),
        ),
        const SizedBox(width: 4),
        Text(label, style: kLegendTextStyle),
      ],
    );
  }
}

class _LegendLine extends StatelessWidget {
  final bool dashed;
  final String label;

  const _LegendLine({required this.dashed, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 2,
          child: CustomPaint(painter: _LinePainter(dashed: dashed)),
        ),
        const SizedBox(width: 4),
        Text(label, style: kLegendTextStyle),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final bool dashed;

  _LinePainter({required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kTextGrey
      ..strokeWidth = 1.5;

    if (dashed) {
      for (var x = 0.0; x < size.width; x += 5) {
        canvas.drawLine(Offset(x, 1), Offset(x + 3, 1), paint);
      }
    } else {
      canvas.drawLine(Offset(0, 1), Offset(size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendIcon extends StatelessWidget {
  final String icon;
  final String label;

  const _LegendIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          icon,
          style: const TextStyle(fontSize: 10, decoration: TextDecoration.none),
        ),
        const SizedBox(width: 2),
        Text(label, style: kLegendTextStyle),
      ],
    );
  }
}
