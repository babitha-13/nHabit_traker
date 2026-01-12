import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/cumulative_score_line_painter.dart';
import 'package:intl/intl.dart';

class CumulativeScoreGraph extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Color color;

  const CumulativeScoreGraph({
    super.key,
    required this.history,
    required this.color,
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
    // Check if history length changed
    if (widget.history.length != oldWidget.history.length) {
      _jumpToLatestPoint();
    } else if (widget.history.isNotEmpty && oldWidget.history.isNotEmpty) {
      // Check if the last item's score changed (for live updates)
      final lastScore = widget.history.last['score'] as double;
      final oldLastScore = oldWidget.history.last['score'] as double;
      if (lastScore != oldLastScore) {
        // Data changed, trigger repaint by calling setState
        setState(() {});
      }
    }
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
    if (widget.history.isEmpty) {
      final theme = FlutterFlowTheme.of(context);
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
    final totalWidth =
        math.max(dayWidth * widget.history.length, constraints.maxWidth);
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
                      child: CustomPaint(
                        key: ValueKey(
                          widget.history.isNotEmpty
                              ? widget.history.last['score'] as double
                              : 0.0,
                        ),
                        painter: CumulativeScoreLinePainter(
                          data: widget.history,
                          minScore: minScore,
                          maxScore: adjustedMax,
                          scoreRange: adjustedRange,
                          color: widget.color,
                        ),
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
    final indices = <int>{};
    const step = 3;
    final lastIndex = history.length - 1;
    for (int i = 0; i <= lastIndex; i++) {
      if (i % step == 0) {
        indices.add(i);
      }
    }
    indices.add(lastIndex);
    final labels = indices.toList()..sort();
    return labels
        .map((index) => _DateLabel(index, history[index]['date'] as DateTime))
        .toList();
  }
}

class _DateLabel {
  final int index;
  final DateTime date;
  const _DateLabel(this.index, this.date);
}
