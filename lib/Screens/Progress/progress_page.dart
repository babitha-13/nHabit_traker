import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Progress/weekly_category_group.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _loadHabits();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && _shouldReloadOnReturn) {
        _shouldReloadOnReturn = false;
        _loadHabits();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildProgressContent(),
                FloatingTimer(
                  activeHabits: _habits,
                  onRefresh: _loadHabits,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHabits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final habits = await queryHabitsRecordOnce(userId: userId);
        final categories = await queryCategoriesRecordOnce(userId: userId);

        setState(() {
          _habits = habits;
          _categories = categories;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading habits: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildProgressContent() {
    return _groupedHabitsWeekly.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.view_week,
                  size: 64,
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
                const SizedBox(height: 16),
                Text(
                  'No habits found',
                  style: FlutterFlowTheme.of(context).titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create your first habit to get started!',
                  style: FlutterFlowTheme.of(context).bodyMedium,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _shouldReloadOnReturn = true;
                  },
                  child: const Text('Add Habit'),
                ),
              ],
            ),
          )
        : ListView.builder(
            controller: _scrollController,
            itemCount: _groupedHabitsWeekly.keys.length,
            itemBuilder: (context, index) {
              final categoryName = _groupedHabitsWeekly.keys.elementAt(index);
              final habits = _groupedHabitsWeekly[categoryName]!;

              // Find the category record or create a fallback
              CategoryRecord? category;
              try {
                category = _categories.firstWhere(
                  (cat) => cat.name == categoryName,
                );
              } catch (e) {
                // Create a fallback category for display
                final categoryData = createCategoryRecordData(
                  name: categoryName,
                  color: '#2196F3',
                  userId: currentUserUid,
                  isActive: true,
                  weight: 1.0,
                  createdTime: DateTime.now(),
                  lastUpdated: DateTime.now(),
                  categoryType: 'habit', // Progress page shows habits
                );
                category = CategoryRecord.getDocumentFromData(
                  categoryData,
                  FirebaseFirestore.instance.collection('categories').doc(),
                );
              }

              return WeeklyCategoryGroup(
                key: Key('weekly_${category.reference.id}'),
                category: category,
                habits: habits,
                onRefresh: _loadHabits,
              );
            },
          );
  }

  Map<String, List<HabitRecord>> get _groupedHabitsWeekly {
    final grouped = <String, List<HabitRecord>>{};

    for (final habit in _habits) {
      final categoryName =
          habit.categoryName.isNotEmpty ? habit.categoryName : 'Uncategorized';
      if (!grouped.containsKey(categoryName)) {
        grouped[categoryName] = [];
      }
      grouped[categoryName]!.add(habit);
    }

    return grouped;
  }
}
