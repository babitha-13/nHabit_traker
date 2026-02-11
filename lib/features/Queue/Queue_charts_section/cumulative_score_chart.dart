import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Queue/Queue_charts_section/cumulative_score_line_painter.dart';
import 'package:intl/intl.dart';

class CumulativeScoreGraph extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Color color;
  final bool isLoading;

  const CumulativeScoreGraph({
    super.key,
    required this.history,
    required this.color,
    this.isLoading = false,
  });

  @override
  State<CumulativeScoreGraph> createState() => _CumulativeScoreGraphState();
}

class _CumulativeScoreGraphState extends State<CumulativeScoreGraph> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _jumpToLatestPoint();
  }

  @override
  void didUpdateWidget(covariant CumulativeScoreGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if history length changed - scroll to latest point
    if (widget.history.length != oldWidget.history.length) {
      _jumpToLatestPoint();
    }
    // Note: We don't need setState here - the widget already rebuilds with new data
    // The custom painter's shouldRepaint method will efficiently handle repainting
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToLatestPoint() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    // Show loading indicator while data is loading
    if (widget.isLoading) {
      return Container(
        decoration: BoxDecoration(
          color: theme.alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
            ),
          ),
        ),
      );
    }

    // Show "No data" only if not loading and history is empty
    if (widget.history.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: theme.alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No data',
            style: theme.bodySmall.override(
              fontFamily: 'Readex Pro',
              color: theme.secondaryText,
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildScrollableGraph(context, constraints),
    );
  }

  Widget _buildScrollableGraph(
      BuildContext context, BoxConstraints constraints) {
    final theme = FlutterFlowTheme.of(context);
    final scores = widget.history.map((d) => d['score'] as double).toList();
    final minScore = scores.reduce(math.min);
    final maxScore = scores.reduce(math.max);
    final adjustedMax = maxScore == minScore ? minScore + 10.0 : maxScore;
    final adjustedRange = adjustedMax - minScore;
    final scaleLabels = _buildScaleLabels(minScore, adjustedRange);
    const visibleDays = 7.0;
    final dayWidth = constraints.maxWidth / visibleDays;
    // Ensure width is enough for 7 data points even if history has fewer
    final totalWidth = dayWidth * math.max(widget.history.length, visibleDays);
    const verticalPadding = 8.0; // top + bottom padding
    const labelAreaHeight = 18.0;
    final graphHeight = math.max(
        constraints.maxHeight - labelAreaHeight - verticalPadding, 30.0);

    return Container(
      decoration: BoxDecoration(
        color: theme.alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildYAxis(theme, scaleLabels),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: graphHeight,
                      child: _buildOptimizedChart(
                        minScore: minScore,
                        maxScore: adjustedMax,
                        scoreRange: adjustedRange,
                        graphHeight: graphHeight,
                      ),
                    ),
                    SizedBox(
                      height: 18,
                      child:
                          _buildDateLabels(theme, totalWidth, widget.history),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYAxis(FlutterFlowTheme theme, List<double> labels) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: labels.reversed
          .map(
            (value) => Text(
              value.toStringAsFixed(0),
              style: theme.bodySmall.override(
                fontFamily: 'Readex Pro',
                fontSize: 9,
                color: theme.secondaryText,
              ),
            ),
          )
          .toList(),
    );
  }

  List<double> _buildScaleLabels(double minScore, double range) {
    const count = 4;
    return List.generate(
      count,
      (index) => minScore + (range * index / math.max(count - 1, 1)),
    );
  }

  Widget _buildDateLabels(FlutterFlowTheme theme, double width,
      List<Map<String, dynamic>> history) {
    final labels = _generateDateLabels(history);
    return Stack(
      children: labels.map((label) {
        final divisor = history.length > 1 ? history.length - 1 : 1;
        final xPosition = (label.index / divisor) * width;
        const labelWidth = 36.0;
        final desiredLeft = xPosition - labelWidth / 2;
        final clampedLeft = desiredLeft.clamp(0.0, width - labelWidth);
        return Positioned(
          left: clampedLeft,
          child: Text(
            DateFormat('MM/dd').format(label.date),
            style: theme.bodySmall.override(
              fontFamily: 'Readex Pro',
              fontSize: 8,
              color: theme.secondaryText,
            ),
          ),
        );
      }).toList(),
    );
  }

  List<_DateLabel> _generateDateLabels(List<Map<String, dynamic>> history) {
    if (history.isEmpty) return [];
    // Only show today's label (last point)
    final lastIndex = history.length - 1;
    return [_DateLabel(lastIndex, history[lastIndex]['date'] as DateTime)];
  }

  /// Build optimized chart with split painters for better performance
  /// Historical data (static) and current day (dynamic) are painted separately
  Widget _buildOptimizedChart({
    required double minScore,
    required double maxScore,
    required double scoreRange,
    required double graphHeight,
  }) {
    if (widget.history.isEmpty) {
      return const SizedBox.shrink();
    }

    // Split data: historical (all but last) and current day (last)
    final historicalData = widget.history.length > 1
        ? widget.history.sublist(0, widget.history.length - 1)
        : <Map<String, dynamic>>[];
    final currentDayData = widget.history.last;
    final previousDayData = widget.history.length > 1
        ? widget.history[widget.history.length - 2]
        : null;

    return Stack(
      children: [
        // Historical data painter (static - rarely repaints)
        // Wrap in RepaintBoundary for extra isolation
        if (historicalData.isNotEmpty)
          RepaintBoundary(
            child: CustomPaint(
              size: Size(double.infinity, graphHeight),
              painter: CumulativeScoreHistoricalPainter(
                historicalData: historicalData,
                minScore: minScore,
                maxScore: maxScore,
                scoreRange: scoreRange,
                color: widget.color,
                totalDataPoints: widget.history.length,
              ),
            ),
          ),
        // Current day painter (dynamic - repaints frequently)
        // Only this repaints when score updates, not the entire chart
        CustomPaint(
          key: ValueKey(
            'current_${currentDayData['score'] as double}',
          ),
          size: Size(double.infinity, graphHeight),
          painter: CumulativeScoreCurrentDayPainter(
            previousDayData: previousDayData,
            currentDayData: currentDayData,
            minScore: minScore,
            maxScore: maxScore,
            scoreRange: scoreRange,
            color: widget.color,
            totalDataPoints: widget.history.length,
          ),
        ),
      ],
    );
  }
}

class _DateLabel {
  final int index;
  final DateTime date;
  const _DateLabel(this.index, this.date);
}
