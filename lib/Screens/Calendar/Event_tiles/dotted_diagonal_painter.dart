import 'dart:math' as math;

import 'package:flutter/material.dart';

class DottedDiagonalPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;
  final double dotLength;
  final double dotGap;

  DottedDiagonalPainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 3.0,
    this.spacing = 12.0,
    this.dotLength = 4.0,
    this.dotGap = 4.0,
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
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Calculate perpendicular spacing for even stripe distribution
    final lineSpacing = spacing + stripeWidth;
    if (lineSpacing <= 0 || lineSpacing.isNaN) return;

    final perpendicularSpacing = lineSpacing / math.sqrt(2);
    if (perpendicularSpacing <= 0 || perpendicularSpacing.isNaN) return;

    final minOffset = -size.width;
    final maxOffset = size.height;
    final numLines =
        ((maxOffset - minOffset) / perpendicularSpacing).ceil() + 2;

    // Draw dotted diagonal lines at 45 degrees
    for (int i = -1; i < numLines; i++) {
      final offset = minOffset + (i * perpendicularSpacing);

      // Find intersection points with canvas boundaries (same logic as solid lines)
      final intersections = <Offset>[];
      final topX = -offset;
      if (topX >= 0 && topX <= size.width && !topX.isNaN && !topX.isInfinite) {
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
        // Sort by x coordinate to get start and end points
        intersections.sort((a, b) => a.dx.compareTo(b.dx));
        final start = intersections.first;
        final end = intersections.last;

        // Validate offsets before using
        if (start.dx.isNaN ||
            start.dy.isNaN ||
            end.dx.isNaN ||
            end.dy.isNaN ||
            start.dx.isInfinite ||
            start.dy.isInfinite ||
            end.dx.isInfinite ||
            end.dy.isInfinite) {
          continue; // Skip this line if invalid
        }

        // Calculate line length
        final lineLength = (end - start).distance;
        if (lineLength <= 0 || lineLength.isNaN || lineLength.isInfinite) {
          continue; // Skip this line if invalid
        }

        final segmentLength = dotLength + dotGap;
        if (segmentLength <= 0 || segmentLength.isNaN) {
          continue; // Skip if invalid segment length
        }

        final numSegments = (lineLength / segmentLength).floor();

        // Draw dashed segments along the line
        for (int j = 0; j <= numSegments; j++) {
          final t = (j * segmentLength) / lineLength;
          final tEnd =
          ((j * segmentLength + dotLength) / lineLength).clamp(0.0, 1.0);

          final segmentStart = Offset(
            start.dx + (end.dx - start.dx) * t,
            start.dy + (end.dy - start.dy) * t,
          );
          final segmentEnd = Offset(
            start.dx + (end.dx - start.dx) * tEnd,
            start.dy + (end.dy - start.dy) * tEnd,
          );

          // Validate offsets before drawing
          if (!segmentStart.dx.isNaN &&
              !segmentStart.dy.isNaN &&
              !segmentEnd.dx.isNaN &&
              !segmentEnd.dy.isNaN &&
              !segmentStart.dx.isInfinite &&
              !segmentStart.dy.isInfinite &&
              !segmentEnd.dx.isInfinite &&
              !segmentEnd.dy.isInfinite) {
            canvas.drawLine(segmentStart, segmentEnd, paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(DottedDiagonalPainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}