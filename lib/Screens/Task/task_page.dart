import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/task_frequency_helper.dart';
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
  late bool _showCompleted;
  bool quickIsRecurring = false;
  bool _quickIsRecurring = false;
  String _quickSchedule = 'daily';
  int _quickFrequency = 1;
  List<int> _quickSelectedDays = [];

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
            key: ValueKey('task_list_${_tasks.length}_${_habits.length}'),
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
      final categories = await queryTaskCategoriesOnce(userId: uid);
      setState(() {
        _tasks = allHabits
            .where((h) =>h.isRecurring||
            !h.isRecurring &&
                (widget.categoryId == null ||
                    h.categoryId == widget.categoryId))
            .toList();
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
          // Main input row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAddController,
                    decoration: const InputDecoration(
                      hintText: 'Quick add task…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _submitQuickAdd(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _submitQuickAdd,
                  padding: const EdgeInsets.all(4),
                  constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // Always show options
          ...[
            Divider(
              height: 1,
              thickness: 1,
              color: FlutterFlowTheme.of(context).alternate,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  // Compact single row with icons only
                  Row(
                    children: [
                      // Task type dropdown (icon only)
                      IconTaskTypeDropdown(
                        selectedValue: _selectedQuickTrackingType ?? 'binary',
                        onChanged: (value) {
                          setState(() {
                            _selectedQuickTrackingType = value;
                            if (value == 'binary') {
                              _quickTargetNumber = 1;
                              _quickTargetDuration = const Duration(hours: 1);
                              _quickUnitController.clear();
                            }
                          });
                        },
                        tooltip: 'Select task type',
                      ),
                      const SizedBox(width: 4),
                      // Due date picker (icon only)
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
                        tooltip: _selectedQuickDueDate != null
                            ? 'Due: ${DateFormat('MMM dd').format(_selectedQuickDueDate!)}'
                            : 'Set due date',
                        padding: const EdgeInsets.all(4),
                        constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      // Recurring task toggle (icon only)
                      IconButton(
                        icon: Icon(
                          _quickIsRecurring
                              ? Icons.repeat
                              : Icons.repeat_outlined,
                          color: _quickIsRecurring
                              ? FlutterFlowTheme.of(context).primary
                              : FlutterFlowTheme.of(context).secondaryText,
                        ),
                        onPressed: () {
                          setState(() {
                            _quickIsRecurring = !_quickIsRecurring;
                            if (!_quickIsRecurring) {
                              // Reset recurring options when disabled
                              _quickSchedule = 'daily';
                              _quickFrequency = 1;
                              _quickSelectedDays = [];
                            } else {
                              // Set default frequency when enabling
                              _quickFrequency =
                                  TaskFrequencyHelper.getDefaultFrequency(
                                      _quickSchedule);
                            }
                          });
                        },
                        tooltip: _quickIsRecurring
                            ? 'Recurring task'
                            : 'Make recurring',
                        padding: const EdgeInsets.all(4),
                        constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Target value row (conditional)
                  if (_selectedQuickTrackingType == 'quantitative') ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Target',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                initialValue: _quickTargetNumber.toString(),
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  _quickTargetNumber = int.tryParse(value) ?? 1;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              TextFormField(
                                controller: _quickUnitController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  hintText: 'e.g., pages, reps',
                                ),
                                onChanged: (value) {
                                  // Unit value stored in controller
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedQuickTrackingType == 'time') ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Target Duration',
                                style: FlutterFlowTheme.of(context).bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: _quickTargetDuration.inHours
                                          .toString(),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        labelText: 'Hours',
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final hours = int.tryParse(value) ?? 1;
                                        _quickTargetDuration = Duration(
                                          hours: hours,
                                          minutes:
                                          _quickTargetDuration.inMinutes %
                                              60,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue:
                                      (_quickTargetDuration.inMinutes % 60)
                                          .toString(),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        labelText: 'Minutes',
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) {
                                        final minutes =
                                            int.tryParse(value) ?? 0;
                                        _quickTargetDuration = Duration(
                                          hours: _quickTargetDuration.inHours,
                                          minutes: minutes,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Recurring options (only show when recurring is enabled)
                  if (_quickIsRecurring) ...[
                    // Schedule dropdown
                    Row(
                      children: [
                        Expanded(
                          child: ScheduleDropdown(
                            selectedSchedule: _quickSchedule,
                            onChanged: (value) {
                              setState(() {
                                _quickSchedule = value ?? 'daily';
                                // Reset frequency and days when schedule changes
                                _quickFrequency =
                                    TaskFrequencyHelper.getDefaultFrequency(
                                        _quickSchedule);
                                _quickSelectedDays = [];
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    // Frequency input for weekly/monthly
                    if (TaskFrequencyHelper.shouldShowFrequencyInput(
                        _quickSchedule)) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: FrequencyInput(
                              schedule: _quickSchedule,
                              frequency: _quickFrequency,
                              onChanged: (value) {
                                setState(() {
                                  _quickFrequency = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Day selection for weekly
                    if (TaskFrequencyHelper.shouldShowDaySelection(
                        _quickSchedule)) ...[
                      const SizedBox(height: 6),
                      DaySelectionChips(
                        selectedDays: _quickSelectedDays,
                        onChanged: (days) {
                          setState(() {
                            _quickSelectedDays = days;
                          });
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  bool _isTaskCompleted(HabitRecord task) {
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

  List<Widget> _buildSections() {
    final theme = FlutterFlowTheme.of(context);
    final buckets = _bucketedItems;
    final order = ['Overdue', 'Task', 'Tomorrow', 'This Week', 'Later'];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is HabitRecord) {
          final isCompleted = _isTaskCompleted(item);
          return _showCompleted || !isCompleted;
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
      widgets.addAll(visibleItems.map((item) => _buildItemTile(item)));
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
        schedule: _quickIsRecurring ? _quickSchedule : 'daily',
        unit: _quickUnit,
        showInFloatingTimer: false, // Default to false
        accumulatedTime: 0,
        isActive: true,
        createdTime: DateTime.now(),
        categoryId: categoryId,
        // 🔧 FIXED: Added safe category name lookup with fallbacks
        categoryName: _categories.isNotEmpty
            ? _categories.firstWhere((c) => c.reference.id == categoryId, orElse: () => _categories.first).name
            : 'Inbox',
        isRecurring: _quickIsRecurring,
        frequency: _quickIsRecurring ? _quickFrequency : 1,
        specificDays: _quickIsRecurring ? _quickSelectedDays : null,
        lastUpdated: DateTime.now(),
      );
      await TaskRecord.collectionForUser(currentUserUid).add(taskData);

      // Clear form fields first
      setState(() {
        _quickAddController.clear();
        _quickTargetNumber = 1;
        _quickTargetDuration = const Duration(hours: 1);
        _quickUnit = '';
        _quickUnitController.clear();
        _selectedQuickDueDate = null;
        quickIsRecurring = false;
        _quickSchedule = 'daily';
        _quickFrequency = 1;
        _quickSelectedDays = [];
        _quickIsRecurring = false;
      });

      // Reload data after setState to avoid nested state updates
      await _loadData();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task "$title" added successfully')),
        );
      }
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
      if (!t.isActive || t.status == 'complete') continue;
      if (!_showCompleted && _isTaskCompleted(t)) continue;
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
      // if (!item.isRecurring) {
      return _buildTaskTile(item);
      // }
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

  Widget _buildTaskTile(HabitRecord task) {
    return CompactHabitItem(
      showCalendar: true,
      showTaskEdit: true,
      key: ValueKey('${task.reference.id}_${task.status}_$_showCompleted'),
      habit: task,
      showCompleted: _showCompleted,
      categories: _categories,
      tasks: _tasks,
      onRefresh: _loadData,
      onHabitUpdated: (updated) => _updateHabitInLocalState(updated),
      onHabitDeleted: (deleted) async => _loadData(),
    );
  }

  void _updateHabitInLocalState(HabitRecord updatedHabit) {
    setState(() {
      final habitIndex = _habits
          .indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (habitIndex != -1) {
        _habits[habitIndex] = updatedHabit;
      }
      final taskIndex =
      _tasks.indexWhere((h) => h.reference.id == updatedHabit.reference.id);
      if (taskIndex != -1) {
        _tasks[taskIndex] = updatedHabit;
      }
      if (!_showCompleted && _isTaskCompleted(updatedHabit)) {
        _tasks.removeWhere((h) => h.reference.id == updatedHabit.reference.id);
      }
    });
    _loadDataSilently();
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final allHabits = await queryHabitsRecordOnce(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);
      if (!mounted) return;
      setState(() {
        _tasks = allHabits.where((h) => h.isRecurring||!h.isRecurring).toList();
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

