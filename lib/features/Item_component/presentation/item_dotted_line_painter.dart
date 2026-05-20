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
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(cx, startY),
        Offset(cx, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(DottedLinePainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashHeight != dashHeight ||
      old.dashSpace != dashSpace;
}
