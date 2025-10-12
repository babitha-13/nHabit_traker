import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:intl/intl.dart';

class TaskPage extends StatefulWidget {
  final String? categoryName;
  final bool showCompleted;

  const TaskPage({super.key, this.categoryName, required this.showCompleted});

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _quickAddController = TextEditingController();
  final TextEditingController _quickTargetNumberController =
      TextEditingController();
  final TextEditingController _quickHoursController = TextEditingController();
  final TextEditingController _quickMinutesController = TextEditingController();
  List<ActivityInstanceRecord> _taskInstances = [];
  List<CategoryRecord> _categories = [];
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  String sortMode = 'default';
  String? _selectedQuickCategoryId;
  String? _selectedQuickTrackingType = 'binary';
  DateTime? _selectedQuickDueDate;
  int _quickTargetNumber = 1;
  Duration _quickTargetDuration = const Duration(hours: 1);
  final TextEditingController _quickUnitController = TextEditingController();
  late bool _showCompleted;
  bool quickIsRecurring = false;
  FrequencyConfig? _quickFrequencyConfig;
  final Map<String, bool> _sectionExpanded = {
    'Overdue': true,
    'Today': true,
    'Tomorrow': true,
    'This Week': true,
    'Later': true,
    'No due date': true,
  };

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _quickTargetNumberController.text = _quickTargetNumber.toString();
    _quickHoursController.text = _quickTargetDuration.inHours.toString();
    _quickMinutesController.text =
        (_quickTargetDuration.inMinutes % 60).toString();
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
    _quickTargetNumberController.dispose();
    _quickHoursController.dispose();
    _quickMinutesController.dispose();
    _quickUnitController.dispose();
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
    final returnedWidget = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildQuickAdd()),
                    ..._buildSections(),
                  ],
                ),
              ),
              FloatingTimer(
                activeInstances: _activeFloatingInstances,
                onRefresh: _loadData,
                onInstanceUpdated: _updateInstanceInLocalState,
              ),
            ],
          );
    return returnedWidget;
  }

  List<ActivityInstanceRecord> get _activeFloatingInstances {
    return _taskInstances.where((inst) {
      return inst.templateShowInFloatingTimer == true &&
          inst.templateTrackingType == 'time' &&
          inst.isTimerActive &&
          inst.status != 'completed';
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final instances = await queryTaskInstances(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);

      // DEBUG: Print instance details
      print('TaskPage: Received ${instances.length} instances');
      for (final inst in instances) {
        print('  Instance: ${inst.templateName}');
        print('    - ID: ${inst.reference.id}');
        print('    - Category ID: ${inst.templateCategoryId}');
        print('    - Category Name: ${inst.templateCategoryName}');
        print('    - Category Type: ${inst.templateCategoryType}');
        print('    - Due Date: ${inst.dueDate}');
        print('    - Status: ${inst.status}');
        print('    - isActive: ${inst.isActive}');
      }
      print('TaskPage: This page categoryName filter: ${widget.categoryName}');
      print('TaskPage: Available categories:');
      for (final cat in categories) {
        print('  - ${cat.name} (${cat.reference.id})');
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _taskInstances = instances.where((inst) {
            final matches = (widget.categoryName == null ||
                inst.templateCategoryName == widget.categoryName);
            print(
                'Instance ${inst.templateName} matches filter: $matches (categoryName: ${inst.templateCategoryName} vs ${widget.categoryName})');
            return matches;
          }).toList();

          print(
              'TaskPage: After filtering: ${_taskInstances.length} instances');

          if (_selectedQuickCategoryId == null && categories.isNotEmpty) {
            // Set the quick-add category to the current tab's category
            final currentCategory = categories.firstWhere(
              (c) => c.name == widget.categoryName,
              orElse: () => categories.first,
            );
            _selectedQuickCategoryId = currentCategory.reference.id;
            print(
                'TaskPage: Set quick-add category to: ${currentCategory.name} (${currentCategory.reference.id})');
          }
          _isLoading = false;
        });
      }
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
    final quickAddWidget = Container(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey(_quickAddController.hashCode),
                    controller: _quickAddController,
                    decoration: const InputDecoration(
                      hintText: 'Quick add task…',
                      border: InputBorder.none,
                      isDense: true,
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
          ...[
            Divider(
              height: 1,
              thickness: 1,
              color: FlutterFlowTheme.of(context).alternate,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                children: [
                  Row(
                    children: [
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
                      // Show due date button only when no date is selected
                      if (_selectedQuickDueDate == null)
                        IconButton(
                          icon: Icon(
                            Icons.calendar_today_outlined,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                          onPressed: _selectQuickDueDate,
                          tooltip: 'Set due date',
                          padding: const EdgeInsets.all(4),
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      // Show due date description when date is selected
                      if (_selectedQuickDueDate != null)
                        InkWell(
                          onTap: _selectQuickDueDate,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  quickIsRecurring
                                      ? 'From ${DateFormat('MMM dd').format(_selectedQuickDueDate!)}'
                                      : DateFormat('MMM dd')
                                          .format(_selectedQuickDueDate!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    // Clear due date without opening picker
                                    setState(() {
                                      _selectedQuickDueDate = null;
                                    });
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Show recurring button only when no frequency is configured
                      if (!quickIsRecurring || _quickFrequencyConfig == null)
                        IconButton(
                          icon: Icon(
                            Icons.repeat_outlined,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                          onPressed: () async {
                            // Opening recurring - show frequency config
                            final config = await showFrequencyConfigDialog(
                              context: context,
                              initialConfig: _quickFrequencyConfig ??
                                  FrequencyConfig(
                                    type: FrequencyType.everyXPeriod,
                                    startDate:
                                        _selectedQuickDueDate ?? DateTime.now(),
                                  ),
                            );
                            if (config != null) {
                              setState(() {
                                _quickFrequencyConfig = config;
                                quickIsRecurring = true;
                                // Sync start date to due date
                                _selectedQuickDueDate = config.startDate;
                              });
                            }
                          },
                          tooltip: 'Make recurring',
                          padding: const EdgeInsets.all(4),
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      // Show frequency description when configured
                      if (quickIsRecurring && _quickFrequencyConfig != null)
                        InkWell(
                          onTap: () async {
                            // Reopen frequency config dialog to edit
                            final config = await showFrequencyConfigDialog(
                              context: context,
                              initialConfig: _quickFrequencyConfig,
                            );
                            if (config != null) {
                              setState(() {
                                _quickFrequencyConfig = config;
                                // Sync start date to due date
                                _selectedQuickDueDate = config.startDate;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.repeat,
                                    size: 14, color: Colors.blue.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  _getQuickFrequencyDescription(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    // Clear recurrence without opening dialog
                                    setState(() {
                                      quickIsRecurring = false;
                                      _quickFrequencyConfig = null;
                                    });
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_selectedQuickTrackingType == 'quantitative') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.track_changes,
                              size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Target:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickTargetNumberController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.orange.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.orange.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: Colors.orange.shade500, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                _quickTargetNumber = int.tryParse(value) ?? 1;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Unit:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickUnitController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.orange.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.orange.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: Colors.orange.shade500, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                hintText: 'e.g., pages, reps',
                                isDense: true,
                              ),
                              onChanged: (value) {},
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_selectedQuickTrackingType == 'time') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer,
                              size: 16, color: Colors.purple.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Target Duration:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.purple.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _quickHoursController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.purple.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.purple.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: Colors.purple.shade500, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                labelText: 'Hours',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final hours = int.tryParse(value) ?? 1;
                                _quickTargetDuration = Duration(
                                  hours: hours,
                                  minutes: _quickTargetDuration.inMinutes % 60,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextFormField(
                              controller: _quickMinutesController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.purple.shade300),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide:
                                      BorderSide(color: Colors.purple.shade300),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: Colors.purple.shade500, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                labelText: 'Minutes',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final minutes = int.tryParse(value) ?? 0;
                                _quickTargetDuration = Duration(
                                  hours: _quickTargetDuration.inHours,
                                  minutes: minutes,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    return quickAddWidget;
  }

  bool _isTaskCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed';
  }

  String _getQuickFrequencyDescription() {
    if (_quickFrequencyConfig == null) return '';

    switch (_quickFrequencyConfig!.type) {
      case FrequencyType.specificDays:
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final selectedDayNames = _quickFrequencyConfig!.selectedDays
            .map((day) => days[day - 1])
            .join(', ');
        return 'Recurring on $selectedDayNames';
      case FrequencyType.timesPerPeriod:
        final String period;
        switch (_quickFrequencyConfig!.periodType) {
          case PeriodType.weeks:
            period = 'week';
            break;
          case PeriodType.months:
            period = 'month';
            break;
          case PeriodType.year:
            period = 'year';
            break;
          case PeriodType.days:
            period = 'days';
            break;
        }
        return 'Recurring ${_quickFrequencyConfig!.timesPerPeriod} times per $period';
      case FrequencyType.everyXPeriod:
        // Special case: every 1 day is the same as every day
        if (_quickFrequencyConfig!.everyXValue == 1 &&
            _quickFrequencyConfig!.everyXPeriodType == PeriodType.days) {
          return 'Recurring every day';
        }
        final String period;
        switch (_quickFrequencyConfig!.everyXPeriodType) {
          case PeriodType.days:
            period = 'days';
            break;
          case PeriodType.weeks:
            period = 'weeks';
            break;
          case PeriodType.months:
            period = 'months';
            break;
          case PeriodType.year:
            period = 'years';
            break;
        }
        return 'Recurring every ${_quickFrequencyConfig!.everyXValue} $period';
      default:
        return 'Recurring';
    }
  }

  List<Widget> _buildSections() {
    final theme = FlutterFlowTheme.of(context);
    final buckets = _bucketedItems;
    final order = [
      'Overdue',
      'Today',
      'Tomorrow',
      'This Week',
      'Later',
      'No due date'
    ];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is ActivityInstanceRecord) {
          return _showCompleted || !_isTaskCompleted(item);
        }
        return true;
      }).toList();
      if (visibleItems.isEmpty) continue;
      _applySort(visibleItems);
      final isExpanded = _sectionExpanded[key] ?? true;
      widgets.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(key, visibleItems.length, isExpanded),
        ),
      );
      if (isExpanded) {
        widgets.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = visibleItems[index];
                return _buildItemTile(item, key);
              },
              childCount: visibleItems.length,
            ),
          ),
        );
        widgets.add(
          const SliverToBoxAdapter(
            child: SizedBox(height: 8),
          ),
        );
      }
    }
    if (widgets.isEmpty) {
      widgets.add(SliverFillRemaining(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(
            child: Text(
              'No tasks yet',
              style: theme.bodyLarge,
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildSectionHeader(String title, int count, bool isExpanded) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: EdgeInsets.fromLTRB(16, 8, 16, isExpanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, isExpanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isExpanded ? Radius.zero : const Radius.circular(16),
          bottomRight: isExpanded ? Radius.zero : const Radius.circular(16),
        ),
        boxShadow: isExpanded ? [] : theme.neumorphicShadowsRaised,
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _sectionExpanded[title] = !isExpanded;
          });
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$title ($count)',
              style: theme.titleMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  String _getSubtitle(ActivityInstanceRecord instance, String bucketKey) {
    // For Today and Tomorrow, dates are obvious, so don't show anything
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      return '';
    }

    // For Overdue, This Week, and Later, show only the date (no category since we're in a category tab)
    final dueDate = instance.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      return formattedDate;
    }

    // Fallback to empty string if no due date
    return '';
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

    final categoryId = _selectedQuickCategoryId;
    if (categoryId == null) {
      if (!mounted) return;
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
          targetValue = null;
          break;
        case 'quantitative':
          targetValue = _quickTargetNumber;
          break;
        case 'time':
          targetValue = _quickTargetDuration.inMinutes;
          break;
        default:
          targetValue = null;
      }

      final docRef = await createActivity(
        name: title,
        categoryName:
            _categories.firstWhere((c) => c.reference.id == categoryId).name,
        trackingType: _selectedQuickTrackingType!,
        target: targetValue,
        isRecurring: quickIsRecurring,
        userId: currentUserUid,
        dueDate: _selectedQuickDueDate,
        priority: 1,
        unit: _quickUnitController.text,
        specificDays: _quickFrequencyConfig != null &&
                _quickFrequencyConfig!.type == FrequencyType.specificDays
            ? _quickFrequencyConfig!.selectedDays
            : null,
        categoryType: 'task',
        frequencyType: quickIsRecurring
            ? _quickFrequencyConfig!.type.toString().split('.').last
            : null,
        everyXValue: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? _quickFrequencyConfig!.everyXValue
            : null,
        everyXPeriodType: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? _quickFrequencyConfig!.everyXPeriodType.toString().split('.').last
            : null,
        timesPerPeriod: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? _quickFrequencyConfig!.timesPerPeriod
            : null,
        periodType: quickIsRecurring &&
                _quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? _quickFrequencyConfig!.periodType.toString().split('.').last
            : null,
        startDate: quickIsRecurring ? _quickFrequencyConfig!.startDate : null,
        endDate: quickIsRecurring ? _quickFrequencyConfig!.endDate : null,
      );

      // Reset the form immediately after creating the task
      _resetQuickAdd();

      // We created a template, now find the first instance created for it.
      try {
        final instances = await ActivityInstanceService.getInstancesForTemplate(
            templateId: docRef.id);
        if (instances.isNotEmpty) {
          final newInstance = instances.first;
          setState(() {
            _taskInstances.add(newInstance);
          });
        } else {
          // If no instances found, try a silent refresh without loading indicator
          _loadDataSilently();
        }
      } catch (e) {
        print('Error getting instances for template, doing silent refresh: $e');
        // Even if there's an error getting instances, do a silent refresh
        _loadDataSilently();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding task: $e')),
      );
    }
  }

  void _resetQuickAdd() {
    print('DEBUG: _resetQuickAdd called');
    print('DEBUG: Controller text before clear: "${_quickAddController.text}"');
    setState(() {
      _quickAddController.clear();
      _selectedQuickTrackingType = 'binary';
      _quickTargetNumber = 1;
      _quickTargetDuration = const Duration(hours: 1);
      _selectedQuickDueDate = null;
      _quickFrequencyConfig = null;
      quickIsRecurring = false;
      _quickUnitController.clear();
      _quickTargetNumberController.text = '1';
      _quickHoursController.text = '1';
      _quickMinutesController.text = '0';
    });
    print('DEBUG: Controller text after clear: "${_quickAddController.text}"');
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
        if (quickIsRecurring && _quickFrequencyConfig != null) {
          _quickFrequencyConfig =
              _quickFrequencyConfig!.copyWith(startDate: picked);
        }
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
      'No due date': [],
    };

    print('_bucketedItems: Processing ${_taskInstances.length} task instances');
    final today = _todayDate();
    final tomorrow = _tomorrowDate();
    // "This Week" covers the next 5 days after tomorrow
    final thisWeekEnd = tomorrow.add(const Duration(days: 5));

    for (final instance in _taskInstances) {
      print('  Bucketing instance: ${instance.templateName}');
      print('    - isActive: ${instance.isActive}');
      if (!instance.isActive) {
        print('    - SKIPPED: not active');
        continue;
      }
      if (widget.categoryName != null &&
          instance.templateCategoryName != widget.categoryName) {
        print('    - SKIPPED: category mismatch');
        continue;
      }

      final dueDate = instance.dueDate;
      if (dueDate == null) {
        print('    - ADDED TO: No due date');
        buckets['No due date']!.add(instance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      print('    - Due date: $instanceDueDate, Today: $today');

      if (instanceDueDate.isBefore(today)) {
        print('    - ADDED TO: Overdue');
        buckets['Overdue']!.add(instance);
      } else if (_isSameDay(instanceDueDate, today)) {
        print('    - ADDED TO: Today');
        buckets['Today']!.add(instance);
      } else if (_isSameDay(instanceDueDate, tomorrow)) {
        print('    - ADDED TO: Tomorrow');
        buckets['Tomorrow']!.add(instance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        print('    - ADDED TO: This Week');
        buckets['This Week']!.add(instance);
      } else {
        print('    - ADDED TO: Later');
        buckets['Later']!.add(instance);
      }
    }

    print('_bucketedItems: Final bucket counts:');
    buckets.forEach((key, value) {
      print('  $key: ${value.length} items');
    });

    return buckets;
  }

  Widget _buildItemTile(dynamic item, String bucketKey) {
    if (item is ActivityInstanceRecord) {
      return _buildTaskTile(item, bucketKey);
    }
    return const SizedBox.shrink();
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));

  Widget _buildTaskTile(ActivityInstanceRecord instance, String bucketKey) {
    return ItemComponent(
      page: "task",
      subtitle: _getSubtitle(instance, bucketKey),
      showCalendar: true,
      showTaskEdit: true,
      key: Key(instance.reference.id),
      instance: instance,
      showCompleted: _showCompleted,
      categories: _categories,
      onRefresh: _loadData,
      onInstanceUpdated: _updateInstanceInLocalState,
      onInstanceDeleted: _removeInstanceFromLocalState,
      showTypeIcon: false,
      showRecurringIcon: true,
    );
  }

  void _updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    setState(() {
      final index = _taskInstances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _taskInstances[index] = updatedInstance;
      }
      // Remove from list if completed and not showing completed
      if (!_showCompleted && updatedInstance.status == 'completed') {
        _taskInstances.removeWhere(
            (inst) => inst.reference.id == updatedInstance.reference.id);
      }
    });
    // Background refresh to sync with server
    _loadDataSilently();
  }

  void _removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    setState(() {
      _taskInstances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
    });
    // Background refresh to sync with server
    _loadDataSilently();
  }

  Future<void> _loadDataSilently() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;
      final instances = await queryTaskInstances(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);

      if (mounted) {
        setState(() {
          _categories = categories;
          _taskInstances = instances.where((inst) {
            final matches = (widget.categoryName == null ||
                inst.templateCategoryName == widget.categoryName);
            return matches;
          }).toList();
        });
      }
    } catch (e) {
      // Silent error handling - don't disrupt UI
      print('Silent refresh error: $e');
    }
  }

  void _applySort(List<dynamic> items) {
    if (sortMode != 'importance') return;
    int cmpTask(ActivityInstanceRecord a, ActivityInstanceRecord b) {
      final ap = a.templatePriority;
      final bp = b.templatePriority;
      if (bp != ap) return bp.compareTo(ap);
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.templateName
          .toLowerCase()
          .compareTo(b.templateName.toLowerCase());
    }

    items.sort((x, y) {
      final xt = x is ActivityInstanceRecord;
      final yt = y is ActivityInstanceRecord;
      if (xt && yt) return cmpTask(x, y);
      if (xt && !yt) return -1;
      if (!xt && yt) return 1;
      return 0;
    });
  }
}
