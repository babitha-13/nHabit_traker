import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class HabitsPage extends StatefulWidget {
  final bool showCompleted;
  const HabitsPage({super.key, required this.showCompleted});

  @override
  _HabitsPageState createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  final Map<String, bool> _categoryExpanded = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  late bool _showCompleted;

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadHabits();
    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });
    NotificationCenter.addObserver(this, 'loadHabits', (param) {
      if (mounted) {
        setState(() {
          _loadHabits();
        });
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
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

  String _getDueDateSubtitle(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (habit.dueDate == null) {
      return 'No due date';
    }

    final dueDate =
        DateTime(habit.dueDate!.year, habit.dueDate!.month, habit.dueDate!.day);

    if (dueDate.isAtSameMomentAs(today)) {
      return 'Today';
    } else if (dueDate.isAtSameMomentAs(tomorrow)) {
      return 'Tomorrow';
    } else {
      return DateFormat.yMMMd().format(habit.dueDate!);
    }
  }

  Future<void> _loadHabits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final habits = await queryHabitsRecordOnce(userId: userId);
        final categories = await queryHabitCategoriesOnce(userId: userId);

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

  Map<String, List<HabitRecord>> get _groupedHabits {
    final grouped = <String, List<HabitRecord>>{};

    for (final habit in _habits) {
      if (!habit.isRecurring) continue;

      final isCompleted = HabitTrackingUtil.isCompletedToday(habit);
      if (!_showCompleted && isCompleted) continue;

      final categoryName =
          habit.categoryName.isNotEmpty ? habit.categoryName : 'Uncategorized';
      (grouped[categoryName] ??= []).add(habit);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildAllHabitsView(),
          FloatingTimer(
            activeHabits: _activeFloatingHabits,
            onRefresh: _loadHabits,
            onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
          ),
        ],
      ),
    );
  }

  List<HabitRecord> get _activeFloatingHabits {
    return _habits.where((h) => h.showInFloatingTimer == true).toList();
  }

  Widget _buildAllHabitsView() {
    final groupedHabits = _groupedHabits;

    if (groupedHabits.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.list_alt,
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
      );
    }

    final slivers = <Widget>[];

    for (final categoryName in groupedHabits.keys) {
      final habits = groupedHabits[categoryName]!;
      CategoryRecord? category;
      try {
        category = _categories.firstWhere((c) => c.name == categoryName);
      } catch (e) {
        final categoryData = createCategoryRecordData(
          name: categoryName,
          color: '#2196F3',
          userId: currentUserUid,
          isActive: true,
          weight: 1.0,
          createdTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          categoryType: 'habit',
        );
        category = CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }

      final expanded = _categoryExpanded[categoryName] ?? true;

      slivers.add(
        SliverToBoxAdapter(
          child: _buildCategoryHeader(
              category, expanded, categoryName, habits.length),
        ),
      );

      if (expanded) {
        final sortedHabits = List<HabitRecord>.from(habits);
        sortedHabits.sort((a, b) {
          final ao = a.hasManualOrder() ? a.manualOrder : habits.indexOf(a);
          final bo = b.hasManualOrder() ? b.manualOrder : habits.indexOf(b);
          return ao.compareTo(bo);
        });

        slivers.add(
          SliverReorderableList(
            itemCount: sortedHabits.length,
            itemBuilder: (context, index) {
              final habit = sortedHabits[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey('habit_${habit.reference.id}'),
                index: index,
                child: ItemComponent(
                  subtitle: _getDueDateSubtitle(habit),
                  showCompleted: _showCompleted,
                  key: Key(habit.reference.id),
                  habit: habit,
                  categoryColorHex: category!.color,
                  onRefresh: _loadHabits,
                  onHabitUpdated: (updated) =>
                      _updateHabitInLocalState(updated),
                  onHabitDeleted: (deleted) async => _loadHabits(),
                  isHabit: true,
                  showTypeIcon: false,
                  showRecurringIcon: false,
                ),
              );
            },
            proxyDecorator: (child, index, animation) {
              final size = MediaQuery.of(context).size;
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  return Material(
                    elevation: 6,
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width,
                        maxHeight: 140,
                      ),
                      child: child,
                    ),
                  );
                },
              );
            },
            onReorder: (oldIndex, newIndex) async {
              if (newIndex > sortedHabits.length) {
                newIndex = sortedHabits.length;
              }
              if (newIndex > oldIndex) newIndex -= 1;
              final item = sortedHabits.removeAt(oldIndex);
              sortedHabits.insert(newIndex, item);
              for (int i = 0; i < sortedHabits.length; i++) {
                final h = sortedHabits[i];
                try {
                  await updateHabit(habitRef: h.reference, manualOrder: i);
                } catch (_) {}
              }
              await _loadHabits();
            },
          ),
        );
      }
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: 140),
        ),
      ],
    );
  }

  Widget _buildCategoryHeader(CategoryRecord category, bool expanded,
      String categoryName, int itemCount) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 8, 16, expanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, expanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: FlutterFlowTheme.of(context).neumorphicGradient,
        border: Border.all(
          color: FlutterFlowTheme.of(context).surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: expanded ? Radius.zero : const Radius.circular(16),
          bottomRight: expanded ? Radius.zero : const Radius.circular(16),
        ),
        boxShadow: expanded
            ? []
            : FlutterFlowTheme.of(context).neumorphicShadowsRaised,
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.name,
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(
                      int.parse(category.color.replaceFirst('#', '0xFF'))),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FlutterFlowTheme.of(context).primary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildCategoryWeightStars(category),
          SizedBox(
            height: 20,
            width: 20,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              menuPadding: EdgeInsets.zero,
              tooltip: 'Category options',
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
              onSelected: (value) => _handleCategoryMenuAction(value, category),
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 5),
                      Text('Edit category'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red),
                      SizedBox(width: 5),
                      Text('Delete category',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              if (mounted) {
                setState(() {
                  _categoryExpanded[categoryName] = !expanded;
                });
              }
            },
            child: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryWeightStars(CategoryRecord category) {
    final current = category.weight.round().clamp(1, 3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            try {
              final next = current % 3 + 1;
              await updateCategory(
                categoryId: category.reference.id,
                weight: next.toDouble(),
              );
              await _loadHabits();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating category weight: $e')),
              );
            }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 24,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  void _updateHabitInLocalState(HabitRecord updated) {
    setState(() {
      final habitIndex =
          _habits.indexWhere((h) => h.reference.id == updated.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updated;
      }
    });
    _loadHabits();
  }

  void _handleCategoryMenuAction(String action, CategoryRecord category) {
    switch (action) {
      case 'edit':
        _showEditCategoryDialog(category);
        break;
      case 'delete':
        _showDeleteCategoryConfirmation(category);
        break;
    }
  }

  void _showEditCategoryDialog(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => CreateCategory(category: category),
    );
  }

  void _showDeleteCategoryConfirmation(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await deleteCategory(category.reference.id,
                    userId: currentUserUid);
                await _loadHabits();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${category.name}" deleted successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                print('Error deleting category: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting category: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
