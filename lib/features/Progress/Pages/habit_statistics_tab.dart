import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Progress/backend/habit_statistics_data_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Progress/Pages/habit_detail_statistics_page.dart';

class HabitStatisticsTab extends StatefulWidget {
  const HabitStatisticsTab({Key? key}) : super(key: key);

  @override
  State<HabitStatisticsTab> createState() => _HabitStatisticsTabState();
}

class _HabitStatisticsTabState extends State<HabitStatisticsTab> {
  List<HabitStatistics> _habitsStats = [];
  bool _isLoading = true;
  String _selectedPeriod = '30';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHabitsStatistics();
  }

  Future<void> _loadHabitsStatistics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      DateTime? startDate;
      final endDate = DateService.currentDate;

      switch (_selectedPeriod) {
        case '7':
          startDate = endDate.subtract(const Duration(days: 7));
          break;
        case '30':
          startDate = endDate.subtract(const Duration(days: 30));
          break;
        case '90':
          startDate = endDate.subtract(const Duration(days: 90));
          break;
        case 'all':
          startDate = null;
          break;
      }

      final stats = await HabitStatisticsService.getAllHabitsStatistics(
        userId,
        startDate: startDate,
        endDate: endDate,
      );

      if (mounted) {
        setState(() {
          _habitsStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading habit statistics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<HabitStatistics> get _filteredHabits {
    if (_searchQuery.isEmpty) {
      return _habitsStats;
    }
    return _habitsStats.where((habit) {
      return habit.habitName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  double get _overallCompletionRate {
    if (_habitsStats.isEmpty) return 0.0;
    final total = _habitsStats.fold(
      0.0,
      (sum, habit) => sum + habit.completionRate,
    );
    return total / _habitsStats.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls
        Container(
          padding: const EdgeInsets.all(16),
          color: FlutterFlowTheme.of(context).secondaryBackground,
          child: Column(
            children: [
              // Time period selector
              Row(
                children: [
                  Text(
                    'Time Period:',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _selectedPeriod,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: '7', child: Text('7 Days')),
                        DropdownMenuItem(value: '30', child: Text('30 Days')),
                        DropdownMenuItem(value: '90', child: Text('90 Days')),
                        DropdownMenuItem(value: 'all', child: Text('All Time')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedPeriod = value;
                          });
                          _loadHabitsStatistics();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Search
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search habits...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ],
          ),
        ),
        // Summary cards
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  context,
                  'Total Habits',
                  '${_habitsStats.length}',
                  Icons.list_alt,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  context,
                  'Avg Completion',
                  '${_overallCompletionRate.toStringAsFixed(0)}%',
                  Icons.trending_up,
                ),
              ),
            ],
          ),
        ),
        // Habits list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredHabits.isEmpty
                  ? Center(
                      child: Text(
                        'No habits found',
                        style: FlutterFlowTheme.of(context).bodyLarge.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredHabits.length,
                      itemBuilder: (context, index) {
                        final habit = _filteredHabits[index];
                        return _buildHabitCard(context, habit);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: FlutterFlowTheme.of(context).primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: FlutterFlowTheme.of(context).titleLarge.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitCard(BuildContext context, HabitStatistics habit) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HabitDetailStatisticsPage(
                habitName: habit.habitName,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Circular progress indicator
              SizedBox(
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: habit.completionRate / 100,
                      strokeWidth: 6,
                      backgroundColor: FlutterFlowTheme.of(context).alternate,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getCompletionColor(habit.completionRate),
                      ),
                    ),
                    Text(
                      '${habit.completionRate.toStringAsFixed(0)}%',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Habit info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.habitName,
                      style: FlutterFlowTheme.of(context).titleMedium.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${habit.totalCompletions} / ${habit.totalDaysTracked} days',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            fontFamily: 'Readex Pro',
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Icon(
                Icons.chevron_right,
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCompletionColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 50) return Colors.orange;
    return Colors.red;
  }
}
