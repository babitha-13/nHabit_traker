import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

class ProgressBreakdownDialog extends StatelessWidget {
  final DateTime date;
  final double totalEarned;
  final double totalTarget;
  final double percentage;
  final List<Map<String, dynamic>> habitBreakdown;
  final List<Map<String, dynamic>> taskBreakdown;
  const ProgressBreakdownDialog({
    Key? key,
    required this.date,
    required this.totalEarned,
    required this.totalTarget,
    required this.percentage,
    required this.habitBreakdown,
    required this.taskBreakdown,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final sortedHabits = List<Map<String, dynamic>>.from(habitBreakdown)
      ..sort(
          (a, b) => (b['earned'] as double).compareTo(a['earned'] as double));
    final sortedTasks = List<Map<String, dynamic>>.from(taskBreakdown)
      ..sort(
          (a, b) => (b['earned'] as double).compareTo(a['earned'] as double));

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Progress Breakdown',
                          style: FlutterFlowTheme.of(context)
                              .headlineSmall
                              .override(
                                fontFamily: 'Readex Pro',
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.day}/${date.month}/${date.year}',
                          style:
                              FlutterFlowTheme.of(context).bodyMedium.override(
                                    fontFamily: 'Readex Pro',
                                    color: Colors.white70,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryCard(
                    context,
                    'Earned',
                    totalEarned.toStringAsFixed(1),
                    FlutterFlowTheme.of(context).primary,
                  ),
                  _buildSummaryCard(
                    context,
                    'Target',
                    totalTarget.toStringAsFixed(1),
                    FlutterFlowTheme.of(context).secondaryText,
                  ),
                  _buildSummaryCard(
                    context,
                    'Progress',
                    '${percentage.toStringAsFixed(1)}%',
                    _getProgressColor(context, percentage),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tasks Section
                    if (sortedTasks.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Tasks', sortedTasks.length),
                      const SizedBox(height: 8),
                      ...sortedTasks
                          .map((task) => _buildItemCard(context, task)),
                      const SizedBox(height: 16),
                    ],
                    // Habits Section
                    if (sortedHabits.isNotEmpty) ...[
                      _buildSectionHeader(
                          context, 'Habits', sortedHabits.length),
                      const SizedBox(height: 8),
                      ...sortedHabits
                          .map((habit) => _buildItemCard(context, habit)),
                    ],
                    // Empty state
                    if (habitBreakdown.isEmpty && taskBreakdown.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.assignment_outlined,
                                size: 48,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No activities for this day',
                                style: FlutterFlowTheme.of(context)
                                    .bodyLarge
                                    .override(
                                      fontFamily: 'Readex Pro',
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
      BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: FlutterFlowTheme.of(context).headlineSmall.override(
                fontFamily: 'Readex Pro',
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: FlutterFlowTheme.of(context).titleMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(BuildContext context, Map<String, dynamic> item) {
    final name = item['name'] as String;
    final status = item['status'] as String;
    final earned = item['earned'] as double;
    final target = item['target'] as double;
    final progress = item['progress'] as double;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Status
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              _buildStatusChip(context, status),
            ],
          ),
          const SizedBox(height: 8),
          // Progress Bar
          if (target > 0) ...[
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: FlutterFlowTheme.of(context).alternate,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(context, progress * 100),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Points
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Points: ${earned.toStringAsFixed(1)} / ${target.toStringAsFixed(1)}',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
              if (target > 0)
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: FlutterFlowTheme.of(context).bodySmall.override(
                        fontFamily: 'Readex Pro',
                        color: _getProgressColor(context, progress * 100),
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, String status) {
    Color color;
    String label;
    switch (status) {
      case 'completed':
        color = Colors.green;
        label = 'Completed';
        break;
      case 'skipped':
        color = Colors.orange;
        label = 'Skipped';
        break;
      case 'pending':
        color = Colors.blue;
        label = 'Pending';
        break;
      default:
        color = FlutterFlowTheme.of(context).secondaryText;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: FlutterFlowTheme.of(context).bodySmall.override(
              fontFamily: 'Readex Pro',
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Color _getProgressColor(BuildContext context, double percentage) {
    if (percentage >= 100) return Colors.green;
    if (percentage >= 75) return Colors.blue;
    if (percentage >= 50) return Colors.orange;
    return Colors.red;
  }
}
