import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import './debug_theme.dart';

/// Frosted-glass debug overlay toggle. Framework-internal — consumed
/// only by `FeatureGraphOverlay`.
@internal
class DebugFab extends StatelessWidget {
  final bool isClose;

  const DebugFab({super.key, this.isClose = false});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: ColoredBox(
          color: isClose ? kFabBgClose : kFabBgOpen,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: isClose
                  ? const Text(
                      '✕',
                      style: TextStyle(
                        color: kTextWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    )
                  : const CustomPaint(
                      size: Size(20, 20),
                      painter: _GraphIconPainter(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded refresh-action FAB shown next to the close button when the
/// debug overlay is open. Framework-internal.
@internal
class RefreshFab extends StatelessWidget {
  const RefreshFab({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: ColoredBox(
          color: kFabBgClose,
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Text(
                '⟳',
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphIconPainter extends CustomPainter {
  const _GraphIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Calibrated at 24; scales proportionally when [size] differs.
    final s = size.width / 24;

    final top = Offset(cx, cy - 8 * s);
    final left = Offset(cx - 9 * s, cy + 8 * s);
    final right = Offset(cx + 9 * s, cy + 8 * s);

    final edgePaint = Paint()
      ..color = const Color(0xBBFFFFFF)
      ..strokeWidth = 1.8 * s
      ..style = PaintingStyle.stroke;

    canvas.drawLine(top, left, edgePaint);
    canvas.drawLine(top, right, edgePaint);

    final nodePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(top, 4 * s, nodePaint);
    canvas.drawCircle(left, 3.2 * s, nodePaint);
    canvas.drawCircle(right, 3.2 * s, nodePaint);

    canvas.drawCircle(top, 2.2 * s, Paint()..color = kEnabledColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
