import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Widget to display habit completion distribution by day of week or hour
class HabitDistributionChartWidget extends StatelessWidget {
  final Map<int, int> data; // Day of week (1-7) or hour (0-23)
  final bool isDayOfWeek; // true for day of week, false for hour
  final double height;
  
  const HabitDistributionChartWidget({
    Key? key,
    required this.data,
    this.isDayOfWeek = true,
    this.height = 200,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }
    
    final maxValue = data.values.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b);
    
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDayOfWeek ? 'Completions by Day of Week' : 'Completions by Hour',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildBars(context, maxValue),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _buildLabels(context),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _buildBars(BuildContext context, int maxValue) {
    final bars = <Widget>[];
    final range = isDayOfWeek ? 7 : 24;
    final start = isDayOfWeek ? 1 : 0;
    
    for (int i = start; i < start + range; i++) {
      final value = data[i] ?? 0;
      final heightRatio = maxValue > 0 ? (value / maxValue) : 0.0;
      
      bars.add(
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: heightRatio * (height - 100), // Reserve space for labels
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).primary.withOpacity(0.7),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                  child: value > 0
                      ? Center(
                          child: Text(
                            value.toString(),
                            style: FlutterFlowTheme.of(context)
                                .bodySmall
                                .override(
                                  fontFamily: 'Readex Pro',
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return bars;
  }
  
  List<Widget> _buildLabels(BuildContext context) {
    final labels = <Widget>[];
    final range = isDayOfWeek ? 7 : 24;
    final start = isDayOfWeek ? 1 : 0;
    
    for (int i = start; i < start + range; i++) {
      String label;
      if (isDayOfWeek) {
        const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        label = dayLabels[i - 1];
      } else {
        label = '${i % 12 == 0 ? 12 : i % 12}${i < 12 ? 'a' : 'p'}';
      }
      
      labels.add(
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  fontSize: 9,
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }
    
    return labels;
  }
}

