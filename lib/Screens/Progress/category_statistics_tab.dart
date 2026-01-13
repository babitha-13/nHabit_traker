import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Progress/category_statistics_data_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

class CategoryStatisticsTab extends StatefulWidget {
  const CategoryStatisticsTab({Key? key}) : super(key: key);

  @override
  State<CategoryStatisticsTab> createState() => _CategoryStatisticsTabState();
}

class _CategoryStatisticsTabState extends State<CategoryStatisticsTab> {
  List<CategoryStatistics> _categoriesStats = [];
  bool _isLoading = true;
  String _selectedPeriod = '30';

  @override
  void initState() {
    super.initState();
    _loadCategoriesStatistics();
  }

  Future<void> _loadCategoriesStatistics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
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

      final stats = await CategoryStatisticsService.getAllCategoriesStatistics(
        userId,
        startDate: startDate,
        endDate: endDate,
      );

      if (mounted) {
        setState(() {
          _categoriesStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading category statistics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double get _overallCompletionRate {
    if (_categoriesStats.isEmpty) return 0.0;
    final total = _categoriesStats.fold(
      0.0,
      (sum, category) => sum + category.completionRate,
    );
    return total / _categoriesStats.length;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls
        Container(
          padding: const EdgeInsets.all(16),
          color: FlutterFlowTheme.of(context).secondaryBackground,
          child: Row(
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
                      _loadCategoriesStatistics();
                    }
                  },
                ),
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
                  'Total Categories',
                  '${_categoriesStats.length}',
                  Icons.category,
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
        // Categories list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _categoriesStats.isEmpty
                  ? Center(
                      child: Text(
                        'No categories found',
                        style: FlutterFlowTheme.of(context).bodyLarge.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _categoriesStats.length,
                      itemBuilder: (context, index) {
                        final category = _categoriesStats[index];
                        return _buildCategoryCard(context, category);
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

  Widget _buildCategoryCard(
    BuildContext context,
    CategoryStatistics category,
  ) {
    // Parse color from hex string
    Color categoryColor;
    try {
      categoryColor =
          Color(int.parse(category.categoryColor.replaceFirst('#', '0xFF')));
    } catch (e) {
      categoryColor = FlutterFlowTheme.of(context).primary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: categoryColor.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category name and color
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    category.categoryName,
                    style: FlutterFlowTheme.of(context).titleMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Completion rate with progress bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Completion Rate',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: category.completionRate / 100,
                        backgroundColor: FlutterFlowTheme.of(context).alternate,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(categoryColor),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${category.completionRate.toStringAsFixed(1)}%',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Habits',
                    '${category.totalHabits}',
                    Icons.list_alt,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Completions',
                    '${category.totalCompletions}',
                    Icons.check_circle,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Avg Points',
                    category.averagePointsEarned.toStringAsFixed(1),
                    Icons.star,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          size: 20,
          color: FlutterFlowTheme.of(context).secondaryText,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
        ),
        Text(
          label,
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
                fontSize: 10,
              ),
        ),
      ],
    );
  }
}
