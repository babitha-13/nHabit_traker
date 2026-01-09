import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/goal_record.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/main.dart';
import 'package:intl/intl.dart';

/// Goal history page showing all goals (active and completed)
class GoalHistoryPage extends StatefulWidget {
  const GoalHistoryPage({super.key});

  @override
  State<GoalHistoryPage> createState() => _GoalHistoryPageState();
}

class _GoalHistoryPageState extends State<GoalHistoryPage> {
  bool _isLoading = true;
  List<GoalRecord> _goals = [];

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final goals = await GoalService.getAllGoals(users.uid ?? '');
      setState(() {
        _goals = goals;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat('MMM dd, yyyy').format(date);
  }

  Widget _buildGoalCard(GoalRecord goal) {
    final theme = FlutterFlowTheme.of(context);
    final isCompleted = goal.completedAt != null;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and dates row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCompleted ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isCompleted ? 'Completed' : 'Active',
                    style: TextStyle(
                      color: isCompleted ? Colors.green.shade700 : Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Set: ${_formatDate(goal.createdAt)}',
                      style: theme.bodySmall.override(
                        fontFamily: 'Readex Pro',
                        color: theme.secondaryText,
                      ),
                    ),
                    if (isCompleted)
                      Text(
                        'Completed: ${_formatDate(goal.completedAt)}',
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'In Progress',
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: theme.secondaryText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Goal answers
            if (goal.whatToAchieve.isNotEmpty) ...[
              _buildAnswerSection('What', goal.whatToAchieve, theme),
            ],
            if (goal.byWhen.isNotEmpty) ...[
              _buildAnswerSection('By When', goal.byWhen, theme),
            ],
            if (goal.why.isNotEmpty) ...[
              _buildAnswerSection('Why', goal.why, theme),
            ],
            if (goal.how.isNotEmpty) ...[
              _buildAnswerSection('How', goal.how, theme),
            ],
            if (goal.thingsToAvoid.isNotEmpty) ...[
              _buildAnswerSection('Things to Avoid', goal.thingsToAvoid, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerSection(String label, String answer, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.titleSmall.override(
              fontFamily: 'Outfit',
              fontWeight: FontWeight.w600,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: theme.bodyMedium.override(
              fontFamily: 'Readex Pro',
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal History'),
        backgroundColor: theme.primaryBackground,
        foregroundColor: theme.primaryText,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 64,
                        color: theme.secondaryText,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No goals yet',
                        style: theme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first goal to get started!',
                        style: theme.bodyMedium.override(
                          color: theme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadGoals,
                  child: ListView.builder(
                    itemCount: _goals.length,
                    itemBuilder: (context, index) {
                      return _buildGoalCard(_goals[index]);
                    },
                  ),
                ),
    );
  }
}

