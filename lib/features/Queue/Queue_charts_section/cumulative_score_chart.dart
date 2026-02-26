import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
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
  static const int _minimumChartPoints = 7;

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
    final chartHistory = _buildChartHistory(widget.history);

    // Show loading only when no history is available yet.
    // During background refresh keep rendering the existing chart.
    if (widget.isLoading && chartHistory.isEmpty) {
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
    if (chartHistory.isEmpty) {
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
          _buildScrollableGraph(context, constraints, chartHistory),
    );
  }

  Widget _buildScrollableGraph(
    BuildContext context,
    BoxConstraints constraints,
    List<Map<String, dynamic>> chartHistory,
  ) {
    final theme = FlutterFlowTheme.of(context);
    final scores = chartHistory
        .map((d) => (d['score'] as num?)?.toDouble() ?? 0.0)
        .toList();
    final minScore = scores.reduce(math.min);
    final maxScore = scores.reduce(math.max);
    final adjustedMax = maxScore == minScore ? minScore + 10.0 : maxScore;
    final adjustedRange = adjustedMax - minScore;
    final scaleLabels = _buildScaleLabels(minScore, adjustedRange);
    const yAxisWidth = 24.0;
    const axisGap = 6.0;
    const containerHorizontalPadding = 8.0; // 4 left + 4 right
    const visibleDays = 7.0;
    final chartViewportWidth = math.max(
      constraints.maxWidth - containerHorizontalPadding - yAxisWidth - axisGap,
      1.0,
    );
    final dayWidth = chartViewportWidth / visibleDays;
    // Ensure width is enough for 7 data points even if history has fewer
    final totalWidth = dayWidth * math.max(chartHistory.length, visibleDays);
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
          _buildYAxis(theme, scaleLabels, yAxisWidth),
          const SizedBox(width: axisGap),
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
                        history: chartHistory,
                        minScore: minScore,
                        maxScore: adjustedMax,
                        scoreRange: adjustedRange,
                        graphHeight: graphHeight,
                      ),
                    ),
                    SizedBox(
                      height: 18,
                      child: _buildDateLabels(theme, totalWidth, chartHistory),
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

  Widget _buildYAxis(
      FlutterFlowTheme theme, List<double> labels, double width) {
    return SizedBox(
      width: width,
      child: Column(
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
      ),
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
    final labels = <_DateLabel>[];
    final lastIndex = history.length - 1;

    final firstDate = safeDateTime(history.first['date']);
    if (firstDate != null) {
      labels.add(_DateLabel(0, firstDate));
    }

    if (history.length > 2) {
      final middleIndex = history.length ~/ 2;
      final middleDate = safeDateTime(history[middleIndex]['date']);
      if (middleDate != null &&
          labels.every((label) => label.index != middleIndex)) {
        labels.add(_DateLabel(middleIndex, middleDate));
      }
    }

    final lastDate = safeDateTime(history[lastIndex]['date']);
    if (lastDate != null && labels.every((label) => label.index != lastIndex)) {
      labels.add(_DateLabel(lastIndex, lastDate));
    }

    return labels;
  }

  /// Build optimized chart with split painters for better performance
  /// Historical data (static) and current day (dynamic) are painted separately
  Widget _buildOptimizedChart({
    required List<Map<String, dynamic>> history,
    required double minScore,
    required double maxScore,
    required double scoreRange,
    required double graphHeight,
  }) {
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }

    // Split data: historical (all but last) and current day (last)
    final historicalData = history.length > 1
        ? history.sublist(0, history.length - 1)
        : <Map<String, dynamic>>[];
    final currentDayData = history.last;
    final previousDayData =
        history.length > 1 ? history[history.length - 2] : null;

    return Stack(
      children: [
        // Historical data painter (static - rarely repaints)
        // Wrap in RepaintBoundary for extra isolation
        if (historicalData.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CumulativeScoreHistoricalPainter(
                  historicalData: historicalData,
                  minScore: minScore,
                  maxScore: maxScore,
                  scoreRange: scoreRange,
                  color: widget.color,
                  totalDataPoints: history.length,
                ),
              ),
            ),
          ),
        // Current day painter (dynamic - repaints frequently)
        // Only this repaints when score updates, not the entire chart
        Positioned.fill(
          child: CustomPaint(
            key: ValueKey(
              'current_${currentDayData['score'] as double}',
            ),
            painter: CumulativeScoreCurrentDayPainter(
              previousDayData: previousDayData,
              currentDayData: currentDayData,
              minScore: minScore,
              maxScore: maxScore,
              scoreRange: scoreRange,
              color: widget.color,
              totalDataPoints: history.length,
            ),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _buildChartHistory(
      List<Map<String, dynamic>> source) {
    final parsed = source
        .map((entry) {
          final date = safeDateTime(entry['date']);
          if (date == null) return null;
          return <String, dynamic>{
            'date': DateTime(date.year, date.month, date.day),
            'score': (entry['score'] as num?)?.toDouble() ?? 0.0,
            'gain': (entry['gain'] as num?)?.toDouble() ?? 0.0,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
      );

    if (parsed.isEmpty || parsed.length >= _minimumChartPoints) {
      return parsed;
    }

    final first = parsed.first;
    final firstDate = first['date'] as DateTime;
    final firstScore = first['score'] as double;
    final missing = _minimumChartPoints - parsed.length;

    final padded = <Map<String, dynamic>>[];
    for (int i = missing; i >= 1; i--) {
      padded.add({
        'date': firstDate.subtract(Duration(days: i)),
        'score': firstScore,
        'gain': 0.0,
      });
    }
    padded.addAll(parsed);
    return padded;
  }
}

class _DateLabel {
  final int index;
  final DateTime date;
  const _DateLabel(this.index, this.date);
}
