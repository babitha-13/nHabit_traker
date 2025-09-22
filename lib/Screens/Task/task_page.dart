import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Dashboard/compact_habit_item.dart' show CompactHabitItem;

class TaskPage extends StatefulWidget {
  final String? categoryId;

  const TaskPage({super.key, this.categoryId});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _quickAddController = TextEditingController();
  List<HabitRecord> _tasks = [];
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
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
    final all = [..._tasks, ..._habits];
    return all.where((h) => h.showInFloatingTimer == true).toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      final categories = await queryCategoriesRecordOnce(userId: uid);
      setState(() {
        _tasks = allHabits
            .where((h) => !h.isRecurring &&
            (widget.categoryId == null || h.categoryId == widget.categoryId))
            .toList();
        _habits = allHabits
            .where((h) => h.isRecurring &&
            (widget.categoryId == null || h.categoryId == widget.categoryId))
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
                    // Category dropdown
                    Expanded(
                      flex: 2,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: FlutterFlowTheme.of(context).alternate,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: DropdownButtonFormField<String>(
                                value: _selectedQuickCategoryId,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                  labelStyle: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  isDense: true,
                                ),
                                items: _categories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category.reference.id,
                                    child: Text(
                                      category.name,
                                      style: const TextStyle(fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedQuickCategoryId = value;
                                  });
                                },
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: FlutterFlowTheme.of(context).alternate,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _selectedQuickTrackingType ?? 'binary',
                          decoration: const InputDecoration(
                            labelText: 'Type',
                            labelStyle: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'binary',
                                child: Text('To-do',
                                    style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(
                                value: 'quantitative',
                                child: Text('Qty',
                                    style: TextStyle(fontSize: 11))),
                            DropdownMenuItem(
                                value: 'time',
                                child: Text('Time',
                                    style: TextStyle(fontSize: 11))),
                          ],
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
                        ),
                      ),
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

  List<Widget> _buildSections() {
    final theme = FlutterFlowTheme.of(context);
    final buckets = _bucketedItems;
    final order = ['Overdue', 'Task', 'Tomorrow', 'This Week', 'Later'];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is HabitRecord) {
          return !HabitTrackingUtil.isCompletedToday(item);
        }
        return true;
      }).toList();
      if (visibleItems.isEmpty) continue;
      _applySort(items);
      // if (items.isEmpty) continue;
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
      widgets.addAll(items.map(_buildItemTile));
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
    if (_selectedQuickCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
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
      final taskData = createHabitRecordData(
        showInFloatingTimer: true,
        name: title,
        categoryId: _selectedQuickCategoryId!,
        categoryName: _categories.firstWhere((c) => c.reference.id == _selectedQuickCategoryId).name,
        trackingType: _selectedQuickTrackingType!,
        target: targetValue,
        taskStatus: 'todo',
        isRecurring: false,
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: currentUserUid,
        dueDate: _selectedQuickDueDate,
        priority: 1,
        unit: _quickUnit,
      );
      final docRef = await HabitRecord.collectionForUser(currentUserUid).add(taskData);
      final newTask = HabitRecord.getDocumentFromData(taskData, docRef);
      setState(() {
        _tasks.add(newTask);
        _quickAddController.clear();
        _selectedQuickDueDate = null;
        _quickTargetNumber = 1;
        _quickTargetDuration = const Duration(hours: 1);
        _quickUnit = '';
        _quickUnitController.clear();
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
      'Task': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
    };
    final today = _todayDate();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    for (final t in _tasks) {
      if (!t.isActive || t.taskStatus == 'done') continue;
      final due = t.dueDate;
      if (due == null) {
        buckets['Later']!.add(t);
        continue;
      }
      if (due.isBefore(today)) {
        buckets['Overdue']!.add(t);
      } else if (_isSameDay(due, today)) {
        buckets['Task']!.add(t);
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
        buckets['Task']!.add(h);
        continue;
      }
      final next = _nextDueDateForHabit(h, today);
      if (next == null) {
        buckets['Later']!.add(h);
      } else if (_isSameDay(next, today)) {
        buckets['Task']!.add(h);
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
    if (item is HabitRecord) {
      if (!item.isRecurring) {
        return _buildTaskTile(item);
      }
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
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
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

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

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

  Widget _buildTaskTile(HabitRecord task) {
    return CompactHabitItem(
      key: Key(task.reference.id),
      habit: task,
      onRefresh: _loadData,
      onHabitUpdated: (updated) =>
          _updateHabitInLocalState(updated),
      onHabitDeleted: (deleted) async => _loadData(),
    );
  }

  void _updateHabitInLocalState(HabitRecord updatedHabit) {
    setState(() {
      final habitIndex = _habits.indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updatedHabit;
      }
      final taskIndex = _tasks.indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (taskIndex != -1) {
        _tasks[taskIndex] = updatedHabit;
      }
      _loadDataSilently();
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
        _tasks = allHabits.where((h) => !h.isRecurring).toList();
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