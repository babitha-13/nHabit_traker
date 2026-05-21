import 'package:flutter/material.dart';

/// Custom painter for creating a dotted vertical line
/// Used to visually distinguish essential items in routines and item components
class DottedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashHeight;
  final double dashSpace;

  const DottedLinePainter({
    required this.color,
    this.strokeWidth = 4.0,
    this.dashHeight = 3.5,
    this.dashSpace = 5.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final period = dashHeight + dashSpace;

    // How many dots fit? Each dot occupies dashHeight; each gap occupies
    // dashSpace. The last dot needs no trailing gap.
    final nDots = ((size.height + dashSpace) / period).floor();
    if (nDots <= 0) return;

    // Visual span: from the top of the first dot to the bottom of the last dot.
    final patternSpan = nDots * period - dashSpace;

    // Centre the pattern within the available height.
    final startY = (size.height - patternSpan) / 2;

    for (int i = 0; i < nDots; i++) {
      final y = startY + i * period;
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, y + dashHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DottedLinePainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashHeight != dashHeight ||
      old.dashSpace != dashSpace;
}
