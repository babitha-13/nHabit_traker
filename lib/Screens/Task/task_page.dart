import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/floating_timer.dart';
import 'package:habit_tracker/Helper/utils/task_type_dropdown_helper.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:intl/intl.dart';
class TaskPage extends StatefulWidget {
  final String? categoryName;
  const TaskPage({super.key, this.categoryName});
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
  TimeOfDay? _selectedQuickDueTime;
  int _quickTargetNumber = 1;
  Duration _quickTargetDuration = const Duration(hours: 1);
  final TextEditingController _quickUnitController = TextEditingController();
  bool quickIsRecurring = false;
  FrequencyConfig? _quickFrequencyConfig;
  String? _expandedSection;
  final Map<String, GlobalKey> _sectionKeys = {};
  int _completionTimeFrame = 2; // 2 = 2 days, 7 = 7 days, 30 = 30 days
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  @override
  void initState() {
    super.initState();
    _quickTargetNumberController.text = _quickTargetNumber.toString();
    _quickHoursController.text = _quickTargetDuration.inHours.toString();
    _quickMinutesController.text =
        (_quickTargetDuration.inMinutes % 60).toString();
    _loadExpansionState();
    _loadData();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    // Listen for instance events
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord && mounted) {
        _handleInstanceDeleted(param);
      }
    });
  }
  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
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
  Future<void> _loadExpansionState() async {
    final expandedSection =
        await ExpansionStateManager().getTaskExpandedSection();
    if (mounted) {
      setState(() {
        _expandedSection = expandedSection;
      });
    }
  }
  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
      });
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildQuickAdd(),
                      ),
                    ),
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
      final instances = await queryAllTaskInstances(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);
      // DEBUG: Print instance details
      for (final inst in instances) {
      }
      for (final cat in categories) {
        print('  - ${cat.name} (${cat.reference.id})');
      }
      if (mounted) {
        setState(() {
          _categories = categories;
          // Filter by category and separate active from all instances
          final categoryFiltered = instances.where((inst) {
            final matches = (widget.categoryName == null ||
                inst.templateCategoryName == widget.categoryName);
            print(
                'Instance ${inst.templateName} matches filter: $matches (categoryName: ${inst.templateCategoryName} vs ${widget.categoryName})');
            return matches;
          }).toList();
          // Store all instances
          _taskInstances = categoryFiltered;
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                      // Date icon or chip
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
                        )
                      else
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
                      // Time icon or chip
                      if (_selectedQuickDueTime == null)
                        IconButton(
                          icon: Icon(
                            Icons.access_time,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                          onPressed: _selectQuickDueTime,
                          tooltip: 'Set due time',
                          padding: const EdgeInsets.all(4),
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        )
                      else
                        InkWell(
                          onTap: _selectQuickDueTime,
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
                                Icon(Icons.access_time,
                                    size: 14, color: Colors.blue.shade700),
                                const SizedBox(width: 6),
                                Text(
                                  TimeUtils.formatTimeOfDayForDisplay(
                                      _selectedQuickDueTime!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    // Clear due time without opening picker
                                    setState(() {
                                      _selectedQuickDueTime = null;
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
                      // Recurring icon or chip
                      if (!quickIsRecurring || _quickFrequencyConfig == null)
                        SizedBox(
                          width: 32,
                          child: IconButton(
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
                                      startDate: _selectedQuickDueDate ??
                                          DateTime.now(),
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
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        )
                      else
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
      'No due date',
      'Recent Completions',
    ];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is ActivityInstanceRecord) {
          // Allow completed tasks in Recent Completions section
          if (key == 'Recent Completions') {
            return true;
          }
          return !_isTaskCompleted(item);
        }
        return true;
      }).toList();
      if (visibleItems.isEmpty) continue;
      _applySort(visibleItems);
      final isExpanded = _expandedSection == key;
      // Get or create GlobalKey for this section
      if (!_sectionKeys.containsKey(key)) {
        _sectionKeys[key] = GlobalKey();
      }
      widgets.add(
        SliverToBoxAdapter(
          child: _buildSectionHeader(
              key, visibleItems.length, isExpanded, _sectionKeys[key]!),
        ),
      );
      if (isExpanded) {
        widgets.add(
          SliverReorderableList(
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${item.reference.id}_drag'),
                child: _buildItemTile(item, key),
              );
            },
            itemCount: visibleItems.length,
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(oldIndex, newIndex, key),
          ),
        );
        // Add "Show older" buttons for Recent Completions section
        if (key == 'Recent Completions') {
          widgets.add(
            SliverToBoxAdapter(
              child: _buildShowOlderButtons(theme),
            ),
          );
        }
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
    // Recent Completions will be handled via buckets like other sections
    return widgets;
  }
  Widget _buildSectionHeader(
      String title, int count, bool isExpanded, GlobalKey headerKey) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      key: headerKey,
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
            if (isExpanded) {
              // If trying to collapse "Today", keep it expanded
              if (title == 'Today') {
                return;
              }
              // Collapse current section
              _expandedSection = null;
            } else {
              // Expand this section (accordion behavior)
              _expandedSection = title;
            }
          });
          // Save state persistently
          ExpansionStateManager().setTaskExpandedSection(_expandedSection);
          // Scroll to make the newly expanded section visible
          if (_expandedSection == title) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (headerKey.currentContext != null) {
                Scrollable.ensureVisible(
                  headerKey.currentContext!,
                  duration: Duration.zero,
                  alignment: 0.0,
                  alignmentPolicy:
                      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                );
              }
            });
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title == 'Recent Completions'
                      ? 'Recent Completions (${_completionTimeFrame == 2 ? '2 days' : _completionTimeFrame == 7 ? '7 days' : '30 days'}) ($count)'
                      : '$title ($count)',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
    if (bucketKey == 'Recent Completions') {
      final completedAt = instance.completedAt!;
      final completedStr =
          _isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = instance.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return 'Completed $completedStr • Due: $dueStr$timeStr';
    }
    // For Today and Tomorrow, dates are obvious, show only time if available
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      if (instance.hasDueTime()) {
        return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
      }
      return '';
    }
    // For Overdue, This Week, Later, show date + time
    final dueDate = instance.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return '$formattedDate$timeStr';
    }
    // For No due date section, show just time if available
    if (instance.hasDueTime()) {
      return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
    }
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
      await createActivity(
        name: title,
        categoryName:
            _categories.firstWhere((c) => c.reference.id == categoryId).name,
        trackingType: _selectedQuickTrackingType!,
        target: targetValue,
        isRecurring: quickIsRecurring,
        userId: currentUserUid,
        dueDate: _selectedQuickDueDate,
        dueTime: _selectedQuickDueTime != null
            ? TimeUtils.timeOfDayToString(_selectedQuickDueTime!)
            : null,
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
      // The createActivity function already broadcasts the instance creation event
      // No need to manually broadcast or refresh - the event handler will handle it
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding task: $e')),
      );
    }
  }
  void _resetQuickAdd() {
    setState(() {
      _quickAddController.clear();
      _selectedQuickTrackingType = 'binary';
      _quickTargetNumber = 1;
      _quickTargetDuration = const Duration(hours: 1);
      _selectedQuickDueDate = null;
      _selectedQuickDueTime = null;
      _quickFrequencyConfig = null;
      quickIsRecurring = false;
      _quickUnitController.clear();
      _quickTargetNumberController.text = '1';
      _quickHoursController.text = '1';
      _quickMinutesController.text = '0';
    });
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
  Future<void> _selectQuickDueTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedQuickDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != _selectedQuickDueTime) {
      setState(() {
        _selectedQuickDueTime = picked;
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
      'Recent Completions': [],
    };
    // Filter instances by search query if active
    final activeInstancesToProcess = _taskInstances
        .where((inst) => inst.status == 'pending') // Filter for pending tasks
        .where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();
    print(
        '_bucketedItems: Processing ${activeInstancesToProcess.length} active task instances (search: "$_searchQuery")');
    final today = DateService.todayStart;
    final tomorrow = DateService.tomorrowStart;
    // "This Week" covers the next 5 days after tomorrow
    final thisWeekEnd = tomorrow.add(const Duration(days: 5));
    // Group recurring tasks by templateId to show only earliest pending instance
    final Map<String, List<ActivityInstanceRecord>> recurringTasksByTemplate =
        {};
    final List<ActivityInstanceRecord> oneOffTasks = [];
    for (final instance in activeInstancesToProcess) {
      if (!instance.isActive) {
        continue;
      }
      if (widget.categoryName != null &&
          instance.templateCategoryName != widget.categoryName) {
        continue;
      }
      if (instance.templateIsRecurring) {
        // Group recurring tasks by template
        final templateId = instance.templateId;
        (recurringTasksByTemplate[templateId] ??= []).add(instance);
      } else {
        // One-off tasks go directly to processing
        oneOffTasks.add(instance);
      }
    }
    // Process one-off tasks normally
    for (final instance in oneOffTasks) {
      final dueDate = instance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(instance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(instance);
      } else if (_isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(instance);
      } else if (_isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(instance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(instance);
      } else {
        buckets['Later']!.add(instance);
      }
    }
    // Process recurring tasks - show only earliest pending instance per template
    for (final templateId in recurringTasksByTemplate.keys) {
      final instances = recurringTasksByTemplate[templateId]!;
      // Sort by due date (earliest first)
      instances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      // Take the earliest pending instance
      final earliestInstance = instances.first;
      print(
          '  Processing recurring task: ${earliestInstance.templateName} (earliest of ${instances.length} instances)');
      final dueDate = earliestInstance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(earliestInstance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(earliestInstance);
      } else if (_isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(earliestInstance);
      } else if (_isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(earliestInstance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(earliestInstance);
      } else {
        buckets['Later']!.add(earliestInstance);
      }
    }
    // Populate Recent Completions with unified time window logic
    final completionCutoff =
        DateService.todayStart.subtract(Duration(days: _completionTimeFrame));
    final allInstancesToProcess = _taskInstances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();
    // Group completed instances by template for recurring tasks
    final Map<String, List<ActivityInstanceRecord>>
        completedRecurringByTemplate = {};
    final List<ActivityInstanceRecord> completedOneOffTasks = [];
    for (final instance in allInstancesToProcess) {
      if (instance.status != 'completed') continue;
      if (instance.completedAt == null) continue;
      if (widget.categoryName != null &&
          instance.templateCategoryName != widget.categoryName) {
        continue;
      }
      final completedDate = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedDate.year, completedDate.month, completedDate.day);
      // Unified time window for both recurring and one-off tasks
      if (completedDateOnly.isAfter(completionCutoff) ||
          completedDateOnly.isAtSameMomentAs(completionCutoff)) {
        if (instance.templateIsRecurring) {
          // Group recurring tasks by template
          final templateId = instance.templateId;
          (completedRecurringByTemplate[templateId] ??= []).add(instance);
        } else {
          // Add one-off tasks directly
          completedOneOffTasks.add(instance);
        }
      }
    }
    // Add all completed instances of recurring tasks within time window
    for (final templateId in completedRecurringByTemplate.keys) {
      final instances = completedRecurringByTemplate[templateId]!;
      // Sort by completion date (latest first)
      instances.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
      // Add ALL instances within the time window
      for (final instance in instances) {
        buckets['Recent Completions']!.add(instance);
        print(
            '  Added completed recurring task: ${instance.templateName} (completed: ${instance.completedAt})');
      }
    }
    // Add all completed one-off tasks within time window
    for (final instance in completedOneOffTasks) {
      buckets['Recent Completions']!.add(instance);
    }
    // Sort items within each bucket by tasks order
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        // Cast to ActivityInstanceRecord list
        final typedItems = items.cast<ActivityInstanceRecord>();
        // Initialize order values for items that don't have them
        InstanceOrderService.initializeOrderValues(typedItems, 'tasks');
        // Sort by tasks order
        buckets[key] =
            InstanceOrderService.sortInstancesByOrder(typedItems, 'tasks');
      }
    }
    // Auto-expand sections with search results
    if (_searchQuery.isNotEmpty) {
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          _expandedSection = key;
          break; // Expand the first section with results
        }
      }
    }
    buckets.forEach((key, value) {
    });
    return buckets;
  }
  // Recent Completions UI is now handled via standard sections and ItemComponent
  // Removed legacy actions for custom Recent Completions UI
  Widget _buildItemTile(dynamic item, String bucketKey) {
    if (item is ActivityInstanceRecord) {
      return _buildTaskTile(item, bucketKey);
    }
    return const SizedBox.shrink();
  }
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  Widget _buildTaskTile(ActivityInstanceRecord instance, String bucketKey) {
    return ItemComponent(
      page: "task",
      subtitle: _getSubtitle(instance, bucketKey),
      showCalendar: true,
      showTaskEdit: true,
      key: Key(instance.reference.id),
      instance: instance,
      categories: _categories,
      onRefresh: _loadData,
      onInstanceUpdated: _updateInstanceInLocalState,
      onInstanceDeleted: _removeInstanceFromLocalState,
      showTypeIcon: false,
      showRecurringIcon: instance.status != 'completed',
      showCompleted: bucketKey == 'Recent Completions' ? true : null,
    );
  }
  Widget _buildShowOlderButtons(FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Show fewer button (when not at minimum)
          if (_completionTimeFrame > 2) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _completionTimeFrame = _completionTimeFrame == 30 ? 7 : 2;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.alternate,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 16,
                      color: theme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show fewer (${_completionTimeFrame == 30 ? '7 days' : '2 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Show older button (when not at maximum)
          if (_completionTimeFrame < 30) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _completionTimeFrame = _completionTimeFrame == 2 ? 7 : 30;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 16,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show older (${_completionTimeFrame == 2 ? '7 days' : '30 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  void _updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    setState(() {
      final index = _taskInstances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _taskInstances[index] = updatedInstance;
      }
      // Remove from list if completed (completed items now show in Recent Completions)
      if (updatedInstance.status == 'completed') {
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
  // Event handlers for live updates
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    // Only add task instances to this page
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          _taskInstances.add(instance);
        });
      }
    }
  }
  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    // Only handle task instances
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          final index = _taskInstances
              .indexWhere((inst) => inst.reference.id == instance.reference.id);
          if (index != -1) {
            _taskInstances[index] = instance;
          }
        });
      }
    }
  }
  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    // Only handle task instances
    if (instance.templateCategoryType == 'task') {
      // Check if instance matches this page's category filter
      final matchesCategory = widget.categoryName == null ||
          instance.templateCategoryName == widget.categoryName;
      if (matchesCategory) {
        setState(() {
          _taskInstances.removeWhere(
              (inst) => inst.reference.id == instance.reference.id);
        });
      }
    }
  }
  /// Handle reordering of items within a section
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String sectionKey) async {
    try {
      final buckets = _bucketedItems;
      final items = buckets[sectionKey]!;
      if (oldIndex >= items.length || newIndex >= items.length) return;
      // Create a copy of the items list for reordering
      final reorderedItems = List<ActivityInstanceRecord>.from(items);
      // Adjust newIndex for the case where we're moving down
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }
      // Get the item being moved
      final movedItem = reorderedItems.removeAt(oldIndex);
      reorderedItems.insert(adjustedNewIndex, movedItem);
      // OPTIMISTIC UI UPDATE: Update local state immediately
      // Update order values in _taskInstances
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];
        // Create updated instance with new tasks order
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['tasksOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );
        // Update in _taskInstances
        final taskIndex = _taskInstances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);
        if (taskIndex != -1) {
          _taskInstances[taskIndex] = updatedInstance;
        }
      }
      // Trigger setState to update UI immediately (eliminates twitch)
      if (mounted) {
        setState(() {
          // State is already updated above
        });
      }
      // Perform database update in background
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'tasks',
        oldIndex,
        newIndex,
      );
    } catch (e) {
      // Revert to correct state by refreshing data
      await _loadData();
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
