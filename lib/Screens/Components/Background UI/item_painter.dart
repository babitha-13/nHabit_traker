
import 'package:flutter/material.dart';

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

class DoubleLinePainter extends CustomPainter {
  final Color color;

  DoubleLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const double lineSpacing = 1.5;
    const double leftLineX = 0.5;
    const double rightLineX =
        leftLineX + lineSpacing + 2.0; // Right line position

    canvas.drawLine(
      const Offset(leftLineX, 0),
      Offset(leftLineX, size.height),
      paint,
    );
    canvas.drawLine(
      const Offset(rightLineX, 0),
      Offset(rightLineX, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}