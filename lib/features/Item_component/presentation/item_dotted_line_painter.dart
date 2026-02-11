import 'package:flutter/material.dart';

/// Custom painter for creating a dotted vertical line
/// Used to visually distinguish essential items in routines and item components
class DottedLinePainter extends CustomPainter {
  final Color color;

  DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const double dashHeight = 3.5; // Slightly shorter dashes
    const double dashSpace = 5.5; // Increased spacing for more visible gaps
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(1.5, startY),
        Offset(1.5, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
