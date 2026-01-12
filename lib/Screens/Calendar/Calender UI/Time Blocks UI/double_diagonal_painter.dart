import 'dart:math' as math;
import 'package:flutter/material.dart';

class DoubleDiagonalPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;
  final double lineGap;

  DoubleDiagonalPainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 2.5,
    this.spacing =
    28.0, // Increased default spacing between sets of double lines
    this.lineGap = 5.0, // Gap between the two lines within each pair
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Guard against invalid sizes
    if (size.width <= 0 ||
        size.height <= 0 ||
        size.width.isNaN ||
        size.height.isNaN ||
        size.width.isInfinite ||
        size.height.isInfinite) {
      return;
    }

    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;

    // Draw two sets of parallel diagonal lines with gap between them
    final lineSpacing = spacing + stripeWidth;
    if (lineSpacing <= 0 || lineSpacing.isNaN) return;

    final perpendicularSpacing = lineSpacing / math.sqrt(2);
    if (perpendicularSpacing <= 0 || perpendicularSpacing.isNaN) return;

    final minOffset = -size.width;
    final maxOffset = size.height;
    final numLines =
        ((maxOffset - minOffset) / perpendicularSpacing).ceil() + 2;

    for (int i = -1; i < numLines; i++) {
      final baseOffset = minOffset + (i * perpendicularSpacing);

      // Draw two parallel lines with visible gap between them
      for (int lineIndex = 0; lineIndex < 2; lineIndex++) {
        // Offset the second line to create a visible gap
        // For 45-degree diagonal, offset along the diagonal direction
        final offset = baseOffset + (lineIndex * lineGap * math.sqrt(2));

        final intersections = <Offset>[];
        final topX = -offset;
        if (topX >= 0 &&
            topX <= size.width &&
            !topX.isNaN &&
            !topX.isInfinite) {
          intersections.add(Offset(topX, 0));
        }
        final bottomX = size.height - offset;
        if (bottomX >= 0 &&
            bottomX <= size.width &&
            !bottomX.isNaN &&
            !bottomX.isInfinite) {
          intersections.add(Offset(bottomX, size.height));
        }
        final leftY = offset;
        if (leftY >= 0 &&
            leftY <= size.height &&
            !leftY.isNaN &&
            !leftY.isInfinite) {
          intersections.add(Offset(0, leftY));
        }
        final rightY = size.width + offset;
        if (rightY >= 0 &&
            rightY <= size.height &&
            !rightY.isNaN &&
            !rightY.isInfinite) {
          intersections.add(Offset(size.width, rightY));
        }

        if (intersections.length >= 2) {
          intersections.sort((a, b) => a.dx.compareTo(b.dx));
          final start = intersections.first;
          final end = intersections.last;
          // Validate offsets before drawing
          if (!start.dx.isNaN &&
              !start.dy.isNaN &&
              !end.dx.isNaN &&
              !end.dy.isNaN &&
              !start.dx.isInfinite &&
              !start.dy.isInfinite &&
              !end.dx.isInfinite &&
              !end.dy.isInfinite) {
            canvas.drawLine(start, end, paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(DoubleDiagonalPainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}