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
  List<ActivityInstanceRecord> _activeTaskInstances = [];
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
  bool quickIsRecurring = false;
  FrequencyConfig? _quickFrequencyConfig;
  String? _expandedSection;
  final Map<String, GlobalKey> _sectionKeys = {};

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
          // Filter by category and separate active from all instances
          final categoryFiltered = instances.where((inst) {
            final matches = (widget.categoryName == null ||
                inst.templateCategoryName == widget.categoryName);
            print(
                'Instance ${inst.templateName} matches filter: $matches (categoryName: ${inst.templateCategoryName} vs ${widget.categoryName})');
            return matches;
          }).toList();

          // Store all instances (for Recent Completions)
          _taskInstances = categoryFiltered;

          // Filter active instances for main sections
          _activeTaskInstances = categoryFiltered
              .where((inst) => inst.status == 'pending')
              .toList();

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
                      const SizedBox(width: 12),
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
                      const SizedBox(width: 12),
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
      'No due date',
      'Recent Completions',
    ];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(buckets[key]!);
      final visibleItems = items.where((item) {
        if (item is ActivityInstanceRecord) {
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
    if (bucketKey == 'Recent Completions') {
      final completedAt = instance.completedAt!;
      final completedStr =
          _isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = instance.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      return 'Completed $completedStr • Due: $dueStr';
    }

    // For Today and Tomorrow, dates are obvious, so don't show anything
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      return '';
    }

    // For Overdue, This Week, Later, show only the date
    final dueDate = instance.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      return formattedDate;
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
      'Recent Completions': [],
    };

    // Filter instances by search query if active
    final activeInstancesToProcess = _activeTaskInstances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();

    print(
        '_bucketedItems: Processing ${activeInstancesToProcess.length} active task instances (search: "$_searchQuery")');
    final today = DateService.todayShiftedStart;
    final tomorrow = DateService.tomorrowShiftedStart;
    // "This Week" covers the next 5 days after tomorrow
    final thisWeekEnd = tomorrow.add(const Duration(days: 5));

    for (final instance in activeInstancesToProcess) {
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

    // Populate Recent Completions (completed today or yesterday)
    final yesterdayStart = DateService.yesterdayShiftedStart;
    final allInstancesToProcess = _taskInstances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();

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
      final isRecent = completedDateOnly.isAfter(yesterdayStart) ||
          completedDateOnly.isAtSameMomentAs(yesterdayStart);
      if (isRecent) {
        buckets['Recent Completions']!.add(instance);
      }
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

    print('_bucketedItems: Final bucket counts:');
    buckets.forEach((key, value) {
      print('  $key: ${value.length} items');
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
          // Also add to active list if pending
          if (instance.status == 'pending') {
            _activeTaskInstances.add(instance);
          }
        });
        print('TaskPage: Added new task instance ${instance.templateName}');
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

            // Also update _activeTaskInstances
            final activeIndex = _activeTaskInstances.indexWhere(
                (inst) => inst.reference.id == instance.reference.id);
            if (activeIndex != -1) {
              _activeTaskInstances[activeIndex] = instance;
            } else if (instance.status == 'pending') {
              // If instance is now pending and not in active list, add it
              _activeTaskInstances.add(instance);
            }

            // Remove from active list if no longer pending
            if (instance.status != 'pending') {
              _activeTaskInstances.removeWhere(
                  (inst) => inst.reference.id == instance.reference.id);
            }

            print('TaskPage: Updated task instance ${instance.templateName}');
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
          _activeTaskInstances.removeWhere(
              (inst) => inst.reference.id == instance.reference.id);
          print('TaskPage: Removed task instance ${instance.templateName}');
        });
      }
    }
  }

  /// Silent refresh instances without loading indicator
  Future<void> _silentRefreshInstances() async {
    try {
      final uid = currentUserUid;
      if (uid.isEmpty) return;

      final instances = await queryAllTaskInstances(userId: uid);
      final categories = await queryTaskCategoriesOnce(userId: uid);

      if (mounted) {
        setState(() {
          _categories = categories;
          final categoryFiltered = instances.where((inst) {
            return widget.categoryName == null ||
                inst.templateCategoryName == widget.categoryName;
          }).toList();

          _taskInstances = categoryFiltered;
          _activeTaskInstances = categoryFiltered
              .where((inst) => inst.status == 'pending')
              .toList();
          // Don't touch _isLoading
        });
      }
    } catch (e) {
      print('Error silently refreshing instances: $e');
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

      // Don't call setState before database update
      // Let ReorderableList handle the drag animation
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'tasks',
        oldIndex,
        newIndex,
      );

      // Silent refresh - no loading indicator
      await _silentRefreshInstances();

      print('TaskPage: Reordered items in section $sectionKey');
    } catch (e) {
      print('TaskPage: Error reordering items: $e');
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
