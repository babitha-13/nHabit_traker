import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/date_filter_dropdown.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class QueuePage extends StatefulWidget {
  final bool showCompleted;
  const QueuePage({super.key, required this.showCompleted});

  @override
  _QueuePageState createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  List<HabitRecord> _tasks = [];
  List<HabitRecord> _tasksTodayOrder = [];
  final Map<String, bool> _timeSectionExpanded = {
    'Overdue': true,
    'Today': true
  };
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  late bool _showCompleted;
  DateFilterType _selectedDateFilter = DateFilterType.today;

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

  Future<void> _loadHabits() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final allHabits = await queryHabitsRecordOnce(userId: userId);
        final categories = await queryHabitCategoriesOnce(userId: userId);
        final taskCategories = await queryTaskCategoriesOnce(userId: userId);
        final allCategories = [...categories, ...taskCategories];
        setState(() {
          _habits = allHabits;
          _categories = allCategories;
          _tasks = allHabits.where((h) {
            if (h.categoryType != 'task') return false;
            if (_isTaskCompleted(h) && !_showCompleted) return false;
            return DateFilterHelper.isItemInFilter(h, _selectedDateFilter);
          }).toList();
          _isLoading = false;
        });
        if (_tasks.isNotEmpty) {
          for (final task in _tasks) {
            print('  - ${task.name}: ${task.trackingType}, target: ${task.target}');
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isTaskCompleted(HabitRecord task) {
    return task.status == 'complete';
  }

  bool _isFlexibleWeekly(HabitRecord habit) {
    return habit.schedule == 'weekly' && habit.specificDays.isEmpty;
  }

  int _completedCountThisWeek(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return habit.completedDates.where((date) {
      final d = DateTime(date.year, date.month, date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEnd);
    }).length;
  }

  int _daysRemainingThisWeekInclusiveToday() {
    final now = DateTime.now();
    return DateTime.sunday - now.weekday + 1;
  }

  int _remainingCompletionsThisWeek(HabitRecord habit) {
    final done = _completedCountThisWeek(habit);
    final remaining = habit.weeklyTarget - done;
    return remaining > 0 ? remaining : 0;
  }

  bool _shouldShowInTodayMain(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (habit.skippedDates.any((d) =>
    d.year == today.year && d.month == today.month && d.day == today.day)) {
      return false;
    }
    if (habit.hasSnoozedUntil()) {
      final until = habit.snoozedUntil!;
      final untilDate = DateTime(until.year, until.month, until.day);
      if (!today.isAfter(untilDate)) {
        return false;
      }
    }
    if (habit.schedule == 'daily') return true;
    if (habit.schedule == 'weekly' && habit.specificDays.isNotEmpty) {
      return habit.specificDays.contains(now.weekday);
    }
    if (_isFlexibleWeekly(habit)) {
      final remaining = _remainingCompletionsThisWeek(habit);
      if (remaining <= 0) return false;
      final daysRemaining = _daysRemainingThisWeekInclusiveToday();
      return remaining >= daysRemaining;
    }
    return false;
  }

  bool _shouldShowInDateFilter(HabitRecord habit) {
    switch (_selectedDateFilter) {
      case DateFilterType.today:
        return _shouldShowInTodayMain(habit);
      case DateFilterType.tomorrow:
        return _shouldShowInTomorrowMain(habit);
      case DateFilterType.week:
        return _shouldShowInThisWeekMain(habit);
      case DateFilterType.later:
        return _shouldShowInLaterMain(habit);
    }
  }

  bool _shouldShowInTomorrowMain(HabitRecord habit) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (habit.skippedDates.any((d) =>
    d.year == tomorrow.year &&
        d.month == tomorrow.month &&
        d.day == tomorrow.day)) {
      return false;
    }
    if (habit.hasSnoozedUntil()) {
      final until = habit.snoozedUntil!;
      final untilDate = DateTime(until.year, until.month, until.day);
      if (!tomorrow.isAfter(untilDate)) {
        return false;
      }
    }
    if (habit.schedule == 'daily') return true;
    if (habit.schedule == 'weekly' && habit.specificDays.isNotEmpty) {
      return habit.specificDays.contains(tomorrow.weekday);
    }
    if (_isFlexibleWeekly(habit)) {
      final remaining = _remainingCompletionsThisWeek(habit);
      if (remaining <= 0) return false;
      return remaining > 0;
    }
    return false;
  }

  bool _shouldShowInThisWeekMain(HabitRecord habit) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    for (int i = 0; i < 7; i++) {
      final checkDate = startOfWeek.add(Duration(days: i));
      if (habit.skippedDates.any((d) =>
      d.year == checkDate.year &&
          d.month == checkDate.month &&
          d.day == checkDate.day)) {
        continue;
      }
      if (habit.hasSnoozedUntil()) {
        final until = habit.snoozedUntil!;
        final untilDate = DateTime(until.year, until.month, until.day);
        if (!checkDate.isAfter(untilDate)) {
          continue;
        }
      }
      if (habit.schedule == 'daily') return true;
      if (habit.schedule == 'weekly' && habit.specificDays.isNotEmpty) {
        if (habit.specificDays.contains(checkDate.weekday)) return true;
      }
      if (_isFlexibleWeekly(habit)) {
        final remaining = _remainingCompletionsThisWeek(habit);
        if (remaining > 0) return true;
      }
    }
    return false;
  }

  bool _shouldShowInLaterMain(HabitRecord habit) {
    return !_shouldShowInTodayMain(habit) &&
        !_shouldShowInTomorrowMain(habit) &&
        !_shouldShowInThisWeekMain(habit);
  }

  Map<String, List<HabitRecord>> get _bucketedItems {
    final Map<String, List<HabitRecord>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
    };

    final today = _todayDate();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    void addToBucket(HabitRecord h, DateTime? dueDate) {
      if (!_showCompleted && _isTaskCompleted(h)) return;

      if (dueDate == null) {
        buckets['Later']!.add(h);
        return;
      }

      final dateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      if (dateOnly.isBefore(today)) {
        buckets['Overdue']!.add(h);
      } else if (_isSameDay(dateOnly, today)) {
        buckets['Today']!.add(h);
      } else if (_isSameDay(dateOnly, _tomorrowDate())) {
        buckets['Tomorrow']!.add(h);
      } else if (!dateOnly.isAfter(endOfWeek)) {
        buckets['This Week']!.add(h);
      } else {
        buckets['Later']!.add(h);
      }
    }

    for (final item in _habits) {
      if (!item.isActive) continue;
      final isRecurring = (item.hasIsHabitRecurring() || item.hasIsTaskRecurring())
          ? (item.isHabitRecurring || item.isTaskRecurring)
          : item.isRecurring;

      if (isRecurring) {
        if (_shouldShowInDateFilter(item)) {
          addToBucket(item, today);
        } else {
          final next = _nextDueDateForHabit(item, today);
          addToBucket(item, next);
        }
      } else {
        addToBucket(item, item.dueDate);
      }
    }

    return buckets;
  }

  String _getSubtitle(HabitRecord item, String bucketKey) {
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      return item.categoryName;
    }

    final dueDate = item.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      return '$formattedDate • ${item.categoryName}';
    }

    return item.categoryName;
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));

  DateTime? _nextDueDateForHabit(HabitRecord h, DateTime today) {
    switch (h.schedule) {
      case 'daily':
        return today.add(const Duration(days: 1));
      case 'weekly':
        if (h.specificDays.isNotEmpty) {
          for (int i = 1; i <= 7; i++) {
            final candidate = today.add(Duration(days: i));
            if (h.specificDays.contains(candidate.weekday)) return candidate;
          }
          return today.add(const Duration(days: 7));
        }
        return today.add(const Duration(days: 1));
      case 'monthly':
        return today.add(const Duration(days: 3));
      default:
        return today.add(const Duration(days: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
            children: [
              Expanded(
                child: _buildDailyView(),
              ),
            ],
          ),
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
    final all = [
      ..._tasksTodayOrder,
      ..._bucketedItems.values.expand((list) => list)
    ];
    return all.where((h) => h.showInFloatingTimer == true).toList();
  }

  Widget _buildDailyView() {
    final buckets = _bucketedItems;
    final order = ['Overdue', 'Today', 'Tomorrow', 'This Week', 'Later'];
    final theme = FlutterFlowTheme.of(context);

    final visibleSections =
    order.where((key) => buckets[key]!.isNotEmpty).toList();

    if (visibleSections.isEmpty) {
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
              'No items in the queue for the selected filter',
              style: FlutterFlowTheme.of(context).titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final slivers = <Widget>[];

    for (final key in visibleSections) {
      final items = buckets[key]!;
      final expanded = _timeSectionExpanded[key] ?? false;

      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.fromLTRB(16, 8, 16, expanded ? 0 : 6),
            padding: EdgeInsets.fromLTRB(12, 8, 12, expanded ? 2 : 6),
            decoration: BoxDecoration(
              gradient: theme.neumorphicGradient,
              border: Border.all(
                color: theme.surfaceBorderColor,
                width: 1,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: expanded ? Radius.zero : const Radius.circular(16),
                bottomRight: expanded ? Radius.zero : const Radius.circular(16),
              ),
              boxShadow: expanded ? [] : theme.neumorphicShadowsRaised,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$key (${items.length})',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    if (mounted) {
                      setState(() {
                        _timeSectionExpanded[key] = !expanded;
                      });
                    }
                  },
                  child: Icon(
                    size: 28,
                    expanded ? Icons.expand_less : Icons.expand_more,
                  ),
                )
              ],
            ),
          ),
        ),
      );

      if (expanded) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final item = items[index];
                final category = _categories.firstWhere(
                      (c) => c.name == item.categoryName,
                  orElse: () {
                    try {
                      return _categories
                          .firstWhere((c) => c.categoryType == 'task');
                    } catch (e) {
                      return CategoryRecord.getDocumentFromData(
                          {},
                          FirebaseFirestore.instance
                              .collection('categories')
                              .doc());
                    }
                  },
                );
                final isHabit = item.categoryType == 'habit';
                return ItemComponent(
                  subtitle: _getSubtitle(item, key),
                  key: Key(item.reference.id),
                  habit: item,
                  showCompleted: _showCompleted,
                  categoryColorHex: _getTaskCategoryColor(item),
                  onRefresh: _loadHabits,
                  onHabitUpdated: (updated) =>
                      _updateHabitInLocalState(updated),
                  onHabitDeleted: (deleted) async => _loadHabits(),
                  isHabit: isHabit,
                  showTypeIcon: true,
                  showRecurringIcon: true,
                );
              },
              childCount: items.length,
            ),
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

  String _getTaskCategoryColor(HabitRecord task) {
    CategoryRecord? matchedCategory;
    try {
      if (task.categoryId.isNotEmpty) {
        matchedCategory =
            _categories.firstWhere((c) => c.reference.id == task.categoryId);
      } else if (task.categoryName.isNotEmpty) {
        final taskName = task.categoryName.trim().toLowerCase();
        matchedCategory = _categories.firstWhere(
              (c) => c.name.trim().toLowerCase() == taskName,
        );
      }
    } catch (_) {}
    if (matchedCategory != null && matchedCategory.color.isNotEmpty) {
      return matchedCategory.color;
    }
    final name = task.categoryName.trim().toLowerCase();
    if (name == 'tasks' || name == 'task') {
      return '#2196F3';
    }
    return '#2196F3';
  }


  void _updateHabitInLocalState(HabitRecord updated) {
    setState(() {
      final habitIndex =
      _habits.indexWhere((h) => h.reference.id == updated.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updated;
      }

      final taskIndex =
      _tasks.indexWhere((t) => t.reference.id == updated.reference.id);
      if (taskIndex != -1) {
        _tasks[taskIndex] = updated;
      }
    });
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      final categories = await queryCategoriesRecordOnce(userId: uid);
      if (!mounted) return;
      setState(() {
        _tasks = allHabits.where((h) {
          if (h.categoryType != 'task') return false;
          return DateFilterHelper.isItemInFilter(h, _selectedDateFilter);
        }).toList();
        _habits = allHabits.where((h) {
          return h.categoryType == 'habit';
        }).toList();
        _categories = categories;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }

}