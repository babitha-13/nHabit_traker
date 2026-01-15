import 'dart:math' as math;
import 'package:flutter/material.dart';

class DiagonalStripePainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;

  DiagonalStripePainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 3.5,
    this.spacing = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;

    final lineSpacing = spacing + stripeWidth;
    final perpendicularSpacing = lineSpacing / math.sqrt(2);

    final minOffset = -size.width;
    final maxOffset = size.height;
    final numLines = ((maxOffset - minOffset) / perpendicularSpacing).ceil() + 2;

    for (int i = -1; i < numLines; i++) {
      final offset = minOffset + (i * perpendicularSpacing);

      final intersections = <Offset>[];

      final topX = -offset;
      if (topX >= 0 && topX <= size.width) intersections.add(Offset(topX, 0));

      final bottomX = size.height - offset;
      if (bottomX >= 0 && bottomX <= size.width) {
        intersections.add(Offset(bottomX, size.height));
      }

      final leftY = offset;
      if (leftY >= 0 && leftY <= size.height) intersections.add(Offset(0, leftY));

      final rightY = size.width + offset;
      if (rightY >= 0 && rightY <= size.height) {
        intersections.add(Offset(size.width, rightY));
      }

      if (intersections.length >= 2) {
        intersections.sort((a, b) => a.dx.compareTo(b.dx));
        final start = intersections.first;
        final end = intersections.last;
        canvas.drawLine(start, end, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DiagonalStripePainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}
