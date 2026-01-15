import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:intl/intl.dart';

/// Custom painter for dotted diagonal lines (used for Habits)
class _DottedDiagonalPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;
  final double dotLength;
  final double dotGap;

  _DottedDiagonalPainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 3.0,
    this.spacing = 12.0,
    this.dotLength = 4.0,
    this.dotGap = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
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

    final lineSpacing = spacing + stripeWidth;
    if (lineSpacing <= 0 || lineSpacing.isNaN) return;

    final perpendicularSpacing = lineSpacing / math.sqrt(2);
    if (perpendicularSpacing <= 0 || perpendicularSpacing.isNaN) return;

    final minOffset = -size.width;
    final maxOffset = size.height;
    final numLines =
        ((maxOffset - minOffset) / perpendicularSpacing).ceil() + 2;

    for (int i = -1; i < numLines; i++) {
      final offset = minOffset + (i * perpendicularSpacing);

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
        intersections.sort((a, b) => a.dx.compareTo(b.dx));
        final start = intersections.first;
        final end = intersections.last;

        if (start.dx.isNaN ||
            start.dy.isNaN ||
            end.dx.isNaN ||
            end.dy.isNaN ||
            start.dx.isInfinite ||
            start.dy.isInfinite ||
            end.dx.isInfinite ||
            end.dy.isInfinite) {
          continue;
        }

        final lineLength = (end - start).distance;
        if (lineLength <= 0 || lineLength.isNaN || lineLength.isInfinite) {
          continue;
        }

        final segmentLength = dotLength + dotGap;
        if (segmentLength <= 0 || segmentLength.isNaN) {
          continue;
        }

        final numSegments = (lineLength / segmentLength).floor();

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
  bool shouldRepaint(_DottedDiagonalPainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}

/// Custom painter for double diagonal lines (used for Essentials)
class _DoubleDiagonalPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;
  final double lineGap;

  _DoubleDiagonalPainter({
    this.stripeColor = const Color(0xFFBDBDBD),
    this.stripeWidth = 2.5,
    this.spacing = 28.0,
    this.lineGap = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
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

      for (int lineIndex = 0; lineIndex < 2; lineIndex++) {
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
  bool shouldRepaint(_DoubleDiagonalPainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.stripeWidth != stripeWidth ||
        oldDelegate.spacing != spacing;
  }
}

/// Data class for pie chart segments
class PieChartSegment {
  final String label;
  final double value; // Duration in minutes
  final Color color;
  final String category; // 'habit', 'task', 'essential', 'unlogged'

  PieChartSegment({
    required this.label,
    required this.value,
    required this.color,
    required this.category,
  });
}

/// Data model for time breakdown with totals and category-level segments
class TimeBreakdownData {
  final double habitMinutes;
  final double taskMinutes;
  final double essentialMinutes;
  final List<PieChartSegment> segments;
  final Map<String, List<PieChartSegment>>
      subcategories; // key: 'habit', 'task', 'essential'

  TimeBreakdownData({
    required this.habitMinutes,
    required this.taskMinutes,
    required this.essentialMinutes,
    required this.segments,
    Map<String, List<PieChartSegment>>? subcategories,
  }) : subcategories = subcategories ?? {};

  double get totalLoggedMinutes =>
      habitMinutes + taskMinutes + essentialMinutes;

  /// Get top-level segments only (Tasks, Habits, Essentials, Unlogged)
  List<PieChartSegment> get topLevelSegments {
    final topLevel = <PieChartSegment>[];

    if (taskMinutes > 0) {
      topLevel.add(PieChartSegment(
        label: 'Tasks',
        value: taskMinutes,
        color: const Color(0xFF1A1A1A),
        category: 'task',
      ));
    }

    if (habitMinutes > 0) {
      topLevel.add(PieChartSegment(
        label: 'Habits',
        value: habitMinutes,
        color: const Color(0xFFC57B57), // Copper color
        category: 'habit',
      ));
    }

    if (essentialMinutes > 0) {
      topLevel.add(PieChartSegment(
        label: 'Essentials',
        value: essentialMinutes,
        color: Colors.grey,
        category: 'essential',
      ));
    }

    final totalLogged = totalLoggedMinutes;
    final unloggedMinutes = (24 * 60) - totalLogged;
    if (unloggedMinutes > 0) {
      topLevel.add(PieChartSegment(
        label: 'Unlogged',
        value: unloggedMinutes,
        color: Colors.grey.shade300,
        category: 'unlogged',
      ));
    }

    return topLevel;
  }
}

/// Custom painter for pie chart
class PieChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double strokeWidth;

  PieChartPainter({
    required this.segments,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width < size.height ? size.width : size.height) / 2 - strokeWidth;

    // Calculate total value
    final total =
        segments.fold<double>(0, (sum, segment) => sum + segment.value);
    if (total == 0) return;

    // Draw segments
    double startAngle = -math.pi / 2; // Start from top

    for (final segment in segments) {
      if (segment.value <= 0) continue;

      final sweepAngle = (segment.value / total) * 2 * math.pi;

      // Create path for this segment to clip pattern
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + radius * math.cos(startAngle),
          center.dy + radius * math.sin(startAngle),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
        )
        ..lineTo(center.dx, center.dy)
        ..close();

      // Draw base arc with color
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);

      // Apply pattern overlay based on category
      if (segment.category == 'habit') {
        // Habits: Dotted diagonal pattern
        canvas.save();
        canvas.clipPath(path);
        final patternPainter = _DottedDiagonalPainter(
          stripeColor: segment.color.withOpacity(0.6),
          stripeWidth: 3.0,
          spacing: 12.0,
          dotLength: 4.0,
          dotGap: 4.0,
        );
        patternPainter.paint(canvas, size);
        canvas.restore();
      } else if (segment.category == 'essential') {
        // Essentials: Double diagonal pattern
        canvas.save();
        canvas.clipPath(path);
        final patternPainter = _DoubleDiagonalPainter(
          stripeColor: segment.color.withOpacity(0.2),
          stripeWidth: 2.5,
          spacing: 28.0,
          lineGap: 5.0,
        );
        patternPainter.paint(canvas, size);
        canvas.restore();
      }
      // Tasks and Unlogged: No pattern (plain solid color)

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! PieChartPainter) return true;
    if (oldDelegate.segments.length != segments.length) return true;
    for (int i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i].value != segments[i].value ||
          oldDelegate.segments[i].color != segments[i].color ||
          oldDelegate.segments[i].category != segments[i].category) {
        return true;
      }
    }
    return false;
  }
}

/// Widget to display time breakdown pie chart
class TimeBreakdownPieChart extends StatelessWidget {
  final List<PieChartSegment> segments;
  final double size;

  const TimeBreakdownPieChart({
    super.key,
    required this.segments,
    this.size = 250.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (segments.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: theme.alternate.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              'No data',
              style: theme.bodyMedium.copyWith(
                color: theme.secondaryText,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: PieChartPainter(segments: segments),
      ),
    );
  }
}

/// Widget to display pie chart with legend
class TimeBreakdownChartWidget extends StatefulWidget {
  final TimeBreakdownData breakdownData;
  final DateTime selectedDate;

  const TimeBreakdownChartWidget({
    super.key,
    required this.breakdownData,
    required this.selectedDate,
  });

  @override
  State<TimeBreakdownChartWidget> createState() =>
      _TimeBreakdownChartWidgetState();
}

class _TimeBreakdownChartWidgetState extends State<TimeBreakdownChartWidget> {
  String?
      selectedCategory; // null = top level, 'habit'/'task'/'essential' = subcategory view

  void _handleSegmentTap(Offset tapPosition, Size chartSize) {
    final center = Offset(chartSize.width / 2, chartSize.height / 2);
    final radius = (chartSize.width < chartSize.height
            ? chartSize.width
            : chartSize.height) /
        2;

    // Calculate distance from center
    final distance = (tapPosition - center).distance;
    if (distance > radius) {
      // Tapped outside chart - do nothing
      return;
    }

    // If tapped in center area and in subcategory view, go back
    if (distance < radius * 0.3 && selectedCategory != null) {
      setState(() {
        selectedCategory = null;
      });
      return;
    }

    // Get current segments (top level or subcategory)
    final currentSegments = selectedCategory == null
        ? widget.breakdownData.topLevelSegments
        : widget.breakdownData.subcategories[selectedCategory] ?? [];

    if (currentSegments.isEmpty) return;

    // Calculate angle from center to tap point
    final dx = tapPosition.dx - center.dx;
    final dy = tapPosition.dy - center.dy;
    var angle = math.atan2(dy, dx);
    // Normalize to 0-2π range, starting from top (-π/2)
    angle = angle + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    // Calculate total value
    final total =
        currentSegments.fold<double>(0, (sum, segment) => sum + segment.value);
    if (total == 0) return;

    // Find which segment was tapped
    double currentAngle = 0.0;
    for (final segment in currentSegments) {
      if (segment.value <= 0) continue;

      final sweepAngle = (segment.value / total) * 2 * math.pi;

      // Check if angle falls within this segment
      // Handle wrap-around case (angle near 2π)
      bool isInSegment = false;
      if (currentAngle + sweepAngle <= 2 * math.pi) {
        isInSegment =
            angle >= currentAngle && angle < currentAngle + sweepAngle;
      } else {
        // Segment wraps around
        isInSegment = angle >= currentAngle ||
            angle < (currentAngle + sweepAngle - 2 * math.pi);
      }

      if (isInSegment) {
        // Tapped this segment
        if (selectedCategory == null) {
          // Top level - drill down if subcategories exist
          final subcategories =
              widget.breakdownData.subcategories[segment.category];
          if (subcategories != null && subcategories.isNotEmpty) {
            setState(() {
              selectedCategory = segment.category;
            });
          }
        } else {
          // Already in subcategory view - tapping any segment goes back
          setState(() {
            selectedCategory = null;
          });
        }
        return;
      }

      currentAngle += sweepAngle;
    }
  }

  void _goBack() {
    if (selectedCategory != null) {
      setState(() {
        selectedCategory = null;
      });
    }
  }

  String _formatDuration(double minutes) {
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).round();
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String _formatPercentage(double value, double total) {
    if (total == 0) return '0%';
    return '${((value / total) * 100).toStringAsFixed(1)}%';
  }

  List<PieChartSegment> get _currentSegments {
    if (selectedCategory == null) {
      return widget.breakdownData.topLevelSegments;
    } else {
      return widget.breakdownData.subcategories[selectedCategory] ?? [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final totalHours = 24.0 * 60.0; // 24 hours in minutes
    final totalLoggedMinutes = widget.breakdownData.totalLoggedMinutes;
    final currentSegments = _currentSegments;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            if (selectedCategory != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
                tooltip: 'Back',
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date subtitle
                  Text(
                    DateFormat('MMM d, y').format(widget.selectedDate),
                    style: theme.titleMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total Logged: ${_formatDuration(totalLoggedMinutes)} / 24h',
                    style: theme.bodyMedium.copyWith(
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Chart and Legend
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pie Chart - increased size with tap detection
            GestureDetector(
              onTapDown: (details) {
                final chartSize = Size(240.0, 240.0);
                _handleSegmentTap(details.localPosition, chartSize);
              },
              child: TimeBreakdownPieChart(
                segments: currentSegments,
                size: 240.0,
              ),
            ),
            const SizedBox(width: 24),

            // Legend
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: currentSegments.map((segment) {
                  return GestureDetector(
                    onTap: () {
                      // Tapping legend item has same effect as tapping chart segment
                      if (selectedCategory == null) {
                        final subcategories = widget
                            .breakdownData.subcategories[segment.category];
                        if (subcategories != null && subcategories.isNotEmpty) {
                          setState(() {
                            selectedCategory = segment.category;
                          });
                        }
                      } else {
                        setState(() {
                          selectedCategory = null;
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          // Color/pattern indicator
                          _buildLegendIndicator(segment, theme),
                          const SizedBox(width: 12),
                          // Label and value
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  segment.label,
                                  style: theme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_formatDuration(segment.value)} • ${_formatPercentage(segment.value, totalHours)}',
                                  style: theme.bodySmall.copyWith(
                                    color: theme.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendIndicator(
      PieChartSegment segment, FlutterFlowTheme theme) {
    if (selectedCategory == null) {
      // Top level - show pattern indicator
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: segment.color,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: Colors.white,
            width: 2,
          ),
        ),
        child: segment.category == 'habit'
            ? ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: CustomPaint(
                  painter: _DottedDiagonalPainter(
                    stripeColor: segment.color.withOpacity(0.6),
                    stripeWidth: 2.0,
                    spacing: 8.0,
                    dotLength: 2.0,
                    dotGap: 2.0,
                  ),
                ),
              )
            : segment.category == 'essential'
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: CustomPaint(
                      painter: _DoubleDiagonalPainter(
                        stripeColor: segment.color.withOpacity(0.2),
                        stripeWidth: 1.5,
                        spacing: 16.0,
                        lineGap: 3.0,
                      ),
                    ),
                  )
                : null,
      );
    } else {
      // Subcategory level - show color circle
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: segment.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: 2,
          ),
        ),
      );
    }
  }
}
