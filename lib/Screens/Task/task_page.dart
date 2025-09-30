import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:habit_tracker/Screens/Dashboard/compact_habit_item.dart'
    show CompactHabitItem;

class TaskPage extends StatefulWidget {
  final String? categoryId;
  final bool showCompleted;

  const TaskPage({super.key, this.categoryId, required this.showCompleted});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _quickAddController = TextEditingController();
  List<TaskRecord> _tasks = [];
  List<HabitRecord> _habits = [];
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  String sortMode = 'default';
  String? _selectedQuickCategoryId;
  String? _selectedQuickTrackingType = 'binary';
  DateTime? _selectedQuickDueDate;
  int _quickTargetNumber = 1;
  Duration _quickTargetDuration = const Duration(hours: 1);
  String _quickUnit = '';
  final TextEditingController _quickUnitController = TextEditingController();
  late bool _showCompleted;
  bool quickIsRecurring = false;

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadData();
    NotificationCenter.addObserver(this, 'showTaskCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _quickAddController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        _loadData();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  children: [
                    _buildQuickAdd(),
                    ..._buildSections(),
                  ],
                ),
              ),
              FloatingTimer(
                activeHabits: _activeFloatingHabits,
                onRefresh: _loadData,
                onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
              ),
            ],
          );
  }

  List<HabitRecord> get _activeFloatingHabits {
    // Include both habits and tasks that have floating timer enabled
    final floatingHabits =
        _habits.where((h) => h.showInFloatingTimer == true).toList();
    // TODO: Add tasks to floating timer when FloatingTimer supports TaskRecord
    // For now, only return habits
    return floatingHabits;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final allTasks = await queryTasksRecordOnce(userId: uid);
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      // Ensure inbox category exists
      await getOrCreateInboxCategory(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);

      // Debug prints
      print('DEBUG: Loaded ${allTasks.length} tasks');
      print('DEBUG: Loaded ${allHabits.length} habits');
      print('DEBUG: Loaded ${categories.length} categories');
      if (allTasks.isNotEmpty) {
        print(
            'DEBUG: First task: ${allTasks.first.name}, status: ${allTasks.first.status}, isActive: ${allTasks.first.isActive}');
      }

      setState(() {
        _tasks = allTasks
            .where((t) =>
                widget.categoryId == null || t.categoryId == widget.categoryId)
            .toList();

        print(
            'DEBUG: Filtered to ${_tasks.length} tasks for categoryId: ${widget.categoryId}');
        _habits = allHabits
            .where((h) =>
                h.isRecurring &&
                (widget.categoryId == null ||
                    h.categoryId == widget.categoryId))
            .toList();
        _categories = categories;
        if (_selectedQuickCategoryId == null && categories.isNotEmpty) {
          _selectedQuickCategoryId = categories.first.reference.id;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tasks: $e')),
        );
      }
    }
  }

  Widget _buildQuickAdd() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: FlutterFlowTheme.of(context).secondaryBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: FlutterFlowTheme.of(context).alternate,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quickAddController,
                        decoration: const InputDecoration(
                          hintText: 'Quick add task…',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _submitQuickAdd(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _submitQuickAdd,
                    ),
                  ],
                ),
                // Divider between task input and options
                Divider(
                  height: 16,
                  thickness: 1,
                  color: FlutterFlowTheme.of(context).alternate,
                ),
                // Options section
                Row(
                  children: [
                    const SizedBox.shrink(),
                    IconTaskTypeDropdown(
                      selectedValue: _selectedQuickTrackingType ?? 'binary',
                      onChanged: (value) {
                        setState(() {
                          _selectedQuickTrackingType = value;
                          if (value == 'binary') {
                            _quickTargetNumber = 1;
                            _quickTargetDuration = const Duration(hours: 1);
                            _quickUnit = '';
                          }
                        });
                      },
                      tooltip: 'Select task type',
                    ),
                    const SizedBox(width: 5),
                    IconButton(
                      icon: Icon(
                        _selectedQuickDueDate != null
                            ? Icons.calendar_today
                            : Icons.calendar_today_outlined,
                        color: _selectedQuickDueDate != null
                            ? FlutterFlowTheme.of(context).primary
                            : FlutterFlowTheme.of(context).secondaryText,
                      ),
                      onPressed: _selectQuickDueDate,
                      tooltip: 'Set due date',
                    ),
                    Transform.scale(
                      scale: 0.7, // make the switch smaller
                      child: Switch(
                        value: quickIsRecurring,
                        onChanged: (val) {
                          setState(() {
                            quickIsRecurring = val;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (_selectedQuickTrackingType != null &&
                    _selectedQuickTrackingType != 'binary') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_selectedQuickTrackingType == 'quantitative') ...[
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: _quickTargetNumber.toString(),
                            decoration: const InputDecoration(
                              labelText: 'Target',
                              labelStyle: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              isDense: false,
                            ),
                            style: const TextStyle(fontSize: 11),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {
                                _quickTargetNumber = int.tryParse(value) ?? 1;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _quickUnitController,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              labelStyle: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                              hintText: 'e.g., pages',
                              hintStyle: TextStyle(fontSize: 10),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              isDense: false,
                            ),
                            style: const TextStyle(fontSize: 11),
                            onChanged: (value) {
                              setState(() {
                                _quickUnit = value;
                              });
                            },
                          ),
                        ),
                      ] else if (_selectedQuickTrackingType == 'time') ...[
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue:
                                (_quickTargetDuration.inHours).toString(),
                            decoration: const InputDecoration(
                              labelText: 'Hours',
                              labelStyle: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              isDense: false,
                            ),
                            style: const TextStyle(fontSize: 11),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final hours = int.tryParse(value) ?? 1;
                              setState(() {
                                _quickTargetDuration = Duration(hours: hours);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: (_quickTargetDuration.inMinutes % 60)
                                .toString(),
                            decoration: const InputDecoration(
                              labelText: 'Minutes',
                              labelStyle: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              isDense: false,
                            ),
                            style: const TextStyle(fontSize: 11),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final minutes = int.tryParse(value) ?? 0;
                              setState(() {
                                _quickTargetDuration = Duration(
                                  hours: _quickTargetDuration.inHours,
                                  minutes: minutes,
                                );
                              });
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isTaskCompleted(dynamic task) {
    if (task is TaskRecord) {
      return task.status == 'complete' || task.status == 'done';
    } else if (task is HabitRecord) {
      if (!task.isActive) return false;
      switch (task.trackingType) {
        case 'binary':
          return task.status == 'complete';
        case 'quantitative':
          final currentValue = task.currentValue ?? 0;
          final target = task.target ?? 0;
          return target > 0 && currentValue >= target;
        case 'time':
          final currentMinutes = (task.accumulatedTime) ~/ 60000;
          final targetMinutes = task.target ?? 0;
          return targetMinutes > 0 && currentMinutes >= targetMinutes;
        default:
          return task.status == 'complete';
      }
    }
    return false;
  }

  List<Widget> _buildSections() {
    final theme = FlutterFlowTheme.of(context);
    final buckets = _bucketedItems;
    final order = ['Overdue', 'Today', 'Tomorrow', 'This Week', 'Later'];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        final isCompleted = _isTaskCompleted(item);
        return _showCompleted || !isCompleted;
      }).toList();
      if (visibleItems.isEmpty) continue;
      _applySort(visibleItems);
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            key,
            style: theme.titleMedium.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      widgets.addAll(visibleItems.map(_buildItemTile));
      widgets.add(const SizedBox(height: 8));
    }
    if (widgets.isEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Text(
            'No tasks yet',
            style: theme.bodyLarge,
          ),
        ),
      ));
    }
    return widgets;
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickAddController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }
    final categoryId = widget.categoryId;
    if (categoryId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category not found for this tab')),
      );
      return;
    }
    if (_selectedQuickTrackingType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tracking type')),
      );
      return;
    }
    try {
      dynamic targetValue;
      switch (_selectedQuickTrackingType) {
        case 'binary':
          targetValue = true;
          break;
        case 'quantitative':
          targetValue = _quickTargetNumber;
          break;
        case 'time':
          targetValue = _quickTargetDuration.inMinutes;
          break;
        default:
          targetValue = true;
      }

      final taskData = createTaskRecordData(
        title: title,
        description: '',
        status: 'incomplete',
        dueDate: _selectedQuickDueDate,
        priority: 1,
        trackingType: _selectedQuickTrackingType ?? 'binary',
        target: targetValue,
        schedule: 'daily', // Default schedule
        unit: _quickUnit,
        showInFloatingTimer: false, // Default to false
        accumulatedTime: 0,
        isActive: true,
        createdTime: DateTime.now(),
        categoryId: categoryId,
        categoryName:
            _categories.firstWhere((c) => c.reference.id == categoryId).name,
      );
      await TaskRecord.collectionForUser(currentUserUid).add(taskData);
      setState(() {
        // Note: _tasks is still List<HabitRecord> for now, we'll fix this in step 2
        // For now, we'll reload data to get the new task
        _loadData();
        _quickAddController.clear();
        _quickTargetNumber = 1;
        _quickTargetDuration = const Duration(hours: 1);
        _quickUnit = '';
        _quickUnitController.clear();
        _selectedQuickDueDate = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding task: $e')),
      );
    }
  }

  Future<void> _selectQuickDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedQuickDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedQuickDueDate) {
      setState(() {
        _selectedQuickDueDate = picked;
      });
    }
  }

  Map<String, List<dynamic>> get _bucketedItems {
    final Map<String, List<dynamic>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
    };
    final today = _todayDate();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    for (final t in _tasks) {
      print(
          'DEBUG: Processing task: ${t.name}, isActive: ${t.isActive}, status: ${t.status}');
      if (!t.isActive) {
        print('DEBUG: Skipping task ${t.name} - not active');
        continue;
      }
      // Note: Completed task filtering will be handled in _buildSections() to respect the toggle
      final due = t.dueDate;
      if (due == null) {
        buckets['Later']!.add(t);
        continue;
      }
      if (due.isBefore(today)) {
        buckets['Overdue']!.add(t);
      } else if (_isSameDay(due, today)) {
        buckets['Today']!.add(t);
      } else if (_isSameDay(due, _tomorrowDate())) {
        buckets['Tomorrow']!.add(t);
      } else if (!due.isAfter(endOfWeek)) {
        buckets['This Week']!.add(t);
      } else {
        buckets['Later']!.add(t);
      }
    }
    for (final h in _habits) {
      if (!h.isActive) continue;
      if (HabitTrackingUtil.shouldTrackToday(h)) {
        buckets['Today']!.add(h);
        continue;
      }
      final next = _nextDueDateForHabit(h, today);
      if (next == null) {
        buckets['Later']!.add(h);
      } else if (_isSameDay(next, today)) {
        buckets['Today']!.add(h);
      } else if (_isSameDay(next, _tomorrowDate())) {
        buckets['Tomorrow']!.add(h);
      } else if (!next.isAfter(endOfWeek)) {
        buckets['This Week']!.add(h);
      } else {
        buckets['Later']!.add(h);
      }
    }
    return buckets;
  }

  Widget _buildItemTile(dynamic item) {
    if (item is TaskRecord) {
      return _buildTaskTile(item);
    }
    if (item is HabitRecord) {
      return _buildTaskTile(item);
    }
    return const SizedBox.shrink();
  }

  void _applySort(List<dynamic> items) {
    if (sortMode != 'importance') return;
    int cmpTask(TaskRecord a, TaskRecord b) {
      final ap = a.priority;
      final bp = b.priority;
      if (bp != ap) return bp.compareTo(ap);
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    items.sort((x, y) {
      final xt = x is TaskRecord;
      final yt = y is TaskRecord;
      if (xt && yt) return cmpTask(x, y);
      if (xt && !yt) return -1; // tasks first in importance mode
      if (!xt && yt) return 1;
      return 0;
    });
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
        return today;
      case 'weekly':
        if (h.specificDays.isNotEmpty) {
          for (int i = 0; i < 7; i++) {
            final candidate = today.add(Duration(days: i));
            if (h.specificDays.contains(candidate.weekday)) return candidate;
          }
          return today.add(const Duration(days: 7));
        }
        return today;
      case 'monthly':
        return today.add(const Duration(days: 3));
      default:
        return today.add(const Duration(days: 1));
    }
  }

  Widget _buildTaskTile(dynamic task) {
    if (task is TaskRecord) {
      // Convert TaskRecord to HabitRecord-like structure for CompactHabitItem
      // Since both now have the same fields, we can create a unified display
      return _buildUnifiedTaskTile(task);
    } else if (task is HabitRecord) {
      return CompactHabitItem(
        showCalendar: true,
        showTaskEdit: true,
        key: Key(task.reference.id),
        habit: task,
        showCompleted: _showCompleted,
        categories: _categories,
        tasks: [], // Empty for now since _tasks is now TaskRecord
        onRefresh: _loadData,
        onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
        onHabitDeleted: (deleted) async => _loadData(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildUnifiedTaskTile(TaskRecord task) {
    final theme = FlutterFlowTheme.of(context);
    final isCompleted = _isTaskCompleted(task);

    // Find category color
    CategoryRecord? category;
    try {
      category = _categories.firstWhere(
        (c) => c.reference.id == task.categoryId,
      );
    } catch (e) {
      category = _categories.isNotEmpty ? _categories.first : null;
    }
    final categoryColor = category != null
        ? Color(int.parse(category.color.replaceFirst('#', '0xFF')))
        : theme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: categoryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editTask(task),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status indicator (similar to habit completion)
                GestureDetector(
                  onTap: () => _toggleTaskStatus(task),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted ? categoryColor : Colors.transparent,
                      border: Border.all(
                        color: categoryColor,
                        width: 2,
                      ),
                    ),
                    child: isCompleted
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),

                // Task content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: theme.bodyLarge.copyWith(
                          decoration:
                              isCompleted ? TextDecoration.lineThrough : null,
                          color: isCompleted
                              ? theme.secondaryText
                              : theme.primaryText,
                        ),
                      ),
                      if (task.dueDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Due: ${DateFormat('MMM d').format(task.dueDate!)}',
                          style: theme.bodySmall.copyWith(
                            color: _isOverdue(task.dueDate!)
                                ? Colors.red
                                : theme.secondaryText,
                          ),
                        ),
                      ],
                      if (category != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          category.name,
                          style: theme.bodySmall.copyWith(
                            color: categoryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      // Show tracking type and target info
                      if (task.trackingType != 'binary') ...[
                        const SizedBox(height: 4),
                        Text(
                          _getTrackingInfo(task),
                          style: theme.bodySmall.copyWith(
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Priority stars
                if (task.priority > 0) ...[
                  const SizedBox(width: 8),
                  Row(
                    children: List.generate(
                      task.priority.clamp(1, 3),
                      (index) => Icon(
                        Icons.star,
                        size: 16,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTrackingInfo(TaskRecord task) {
    switch (task.trackingType) {
      case 'quantitative':
        final target = task.target ?? 0;
        final unit = task.unit.isNotEmpty ? ' ${task.unit}' : '';
        return 'Target: $target$unit';
      case 'time':
        final targetMinutes = task.target ?? 0;
        final hours = targetMinutes ~/ 60;
        final minutes = targetMinutes % 60;
        if (hours > 0) {
          return 'Target: ${hours}h ${minutes}m';
        } else {
          return 'Target: ${minutes}m';
        }
      default:
        return '';
    }
  }

  bool _isOverdue(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return due.isBefore(today);
  }

  void _editTask(TaskRecord task) {
    // TODO: Implement task editing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task editing coming soon!')),
    );
  }

  void _toggleTaskStatus(TaskRecord task) async {
    try {
      final newStatus = task.status == 'complete' ? 'incomplete' : 'complete';
      await updateTask(
        taskRef: task.reference,
        status: newStatus,
      );
      _loadData(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  void _updateHabitInLocalState(HabitRecord updatedHabit) {
    setState(() {
      final habitIndex = _habits
          .indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updatedHabit;
      }
      // For now, just reload data since tasks are now TaskRecord type
      // TODO: Update this when CompactHabitItem supports TaskRecord
      _loadDataSilently();
    });
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final allTasks = await queryTasksRecordOnce(userId: uid);
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      // Ensure inbox category exists
      await getOrCreateInboxCategory(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);
      if (!mounted) return;
      setState(() {
        _tasks = allTasks;
        _habits = allHabits.where((h) => h.isRecurring).toList();
        _categories = categories;
        if (_selectedQuickCategoryId == null && categories.isNotEmpty) {
          _selectedQuickCategoryId = categories.first.reference.id;
        }
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
