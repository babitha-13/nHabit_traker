import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart'; // Keep for fetching template on edit
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/features/Timer/Helpers/timer_logic_helper.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Item_component/helper/item_context_menu_actions.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_menu_actions.dart';
import 'package:habit_tracker/features/Item_component/helper/item_binary_controls_helper.dart';
import 'package:habit_tracker/features/Item_component/helper/item_quantitative_controls_helper.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_subtitle.dart';
import 'package:habit_tracker/features/Item_component/helper/item_time_controls_helper.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_ui.dart';
import 'package:habit_tracker/features/activity%20editor/presentation/activity_editor_dialog.dart';
import 'package:habit_tracker/features/Timer/timer_page.dart';
import 'package:habit_tracker/features/Progress/Pages/habit_detail_statistics_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_expanded.dart';

class ItemComponent extends StatefulWidget {
  final ActivityInstanceRecord instance;
  final Future<void> Function()? onRefresh;
  final void Function(ActivityRecord updatedHabit)? onHabitUpdated;
  final void Function(ActivityRecord deletedHabit)? onHabitDeleted;
  final void Function(ActivityInstanceRecord updatedInstance)?
      onInstanceUpdated;
  final void Function(ActivityInstanceRecord deletedInstance)?
      onInstanceDeleted;
  final String? categoryColorHex, page;
  final bool? showCompleted;
  final bool showCalendar;
  final bool showTaskEdit;
  final List<CategoryRecord>? categories;
  final List<ActivityRecord>? tasks;
  final bool isHabit;
  final bool showTypeIcon;
  final bool showRecurringIcon;
  final String? subtitle;
  final bool showExpandedCategoryName;
  final DateTime? progressReferenceTime;
  final bool showQuickLogOnLeft; // NEW: Flag to show + on left
  final VoidCallback? onQuickLog; // NEW: Callback for + on left
  final bool showManagementActions;
  final bool enableExpandedEdit;
  final bool showSwipeTimerAction;
  final bool
      treatAsBinary; // NEW: Forces checklist behavior regardless of tracking type
  const ItemComponent(
      {super.key,
      required this.instance,
      this.onRefresh,
      this.onHabitUpdated,
      this.onHabitDeleted,
      this.onInstanceUpdated,
      this.onInstanceDeleted,
      this.categoryColorHex,
      this.showCompleted,
      this.showCalendar = false,
      this.categories,
      this.tasks,
      this.showTaskEdit = false,
      this.isHabit = false,
      this.showTypeIcon = true,
      this.showRecurringIcon = false,
      this.subtitle,
      this.page,
      this.showExpandedCategoryName = false,
      this.progressReferenceTime,
      this.showQuickLogOnLeft = false,
      this.onQuickLog,
      this.showManagementActions = true,
      this.enableExpandedEdit = true,
      this.showSwipeTimerAction = true,
      this.treatAsBinary = false});
  @override
  State<ItemComponent> createState() => _ItemComponentState();
}

class _ItemComponentState extends State<ItemComponent>
    with TickerProviderStateMixin {
  bool _isUpdating = false;
  Timer? _timer;
  Timer? _quantUpdateTimer; // Timer for batching quantitative updates
  int _pendingQuantIncrement = 0; // Accumulated pending increments
  num? _quantProgressOverride;
  bool? _timerStateOverride;
  bool? _binaryCompletionOverride;
  bool _isExpanded = false;
  bool? _hasReminders; // Cache for reminder check
  String? _reminderDisplayText; // Cache for reminder display text
  int? _resolvedTimeEstimateMinutes;
  bool _isFetchingTimeEstimate = false;
  @override
  void initState() {
    super.initState();
    _resolvedTimeEstimateMinutes =
        _normalizeTimeEstimate(widget.instance.templateTimeEstimateMinutes);
    if (_shouldFetchTemplateEstimate()) {
      _fetchTemplateTimeEstimate();
    }
    if (widget.instance.templateTrackingType == 'time' &&
        widget.instance.isTimerActive) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant ItemComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.instance.templateTrackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      final backendValue = widget.instance.currentValue;
      if (backendValue == _quantProgressOverride) {
        setState(() => _quantProgressOverride = null);
      }
    }
    if (widget.instance.templateTrackingType == 'time' &&
        _timerStateOverride != null) {
      if (widget.instance.isTimerActive == _timerStateOverride) {
        setState(() => _timerStateOverride = null);
      } else if (widget.instance.isTimerActive != _timerStateOverride &&
          widget.instance.isTimerActive != oldWidget.instance.isTimerActive) {
        setState(() => _timerStateOverride = null);
      }
    }
    if (_binaryCompletionOverride != null) {
      final backendCompleted = _isBackendCompleted;
      final instanceChanged =
          widget.instance.reference.id != oldWidget.instance.reference.id;
      final statusChanged = widget.instance.status != oldWidget.instance.status;
      if (backendCompleted == _binaryCompletionOverride ||
          instanceChanged ||
          statusChanged) {
        setState(() => _binaryCompletionOverride = null);
      }
    }
    if (widget.instance.templateTrackingType == 'time') {
      if (widget.instance.isTimerActive && !oldWidget.instance.isTimerActive) {
        _startTimer();
      } else if (!widget.instance.isTimerActive &&
          oldWidget.instance.isTimerActive) {
        _stopTimer();
      }
    }
    final estimateChanged = widget.instance.templateTimeEstimateMinutes !=
        oldWidget.instance.templateTimeEstimateMinutes;
    final instanceChanged =
        widget.instance.reference.id != oldWidget.instance.reference.id;
    if (estimateChanged || instanceChanged) {
      final newValue =
          _normalizeTimeEstimate(widget.instance.templateTimeEstimateMinutes);
      if (_resolvedTimeEstimateMinutes != newValue) {
        setState(() {
          _resolvedTimeEstimateMinutes = newValue;
        });
      }
      if (_shouldFetchTemplateEstimate()) {
        _fetchTemplateTimeEstimate();
      }
    }
  }

  bool _isRecurringItem() {
    return ItemUIBuildingHelper.isRecurringItem(widget.instance);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  int? _normalizeTimeEstimate(int? minutes) {
    if (minutes == null) return null;
    if (minutes <= 0) return null;
    return minutes.clamp(1, 600);
  }

  bool _shouldFetchTemplateEstimate() {
    if (_resolvedTimeEstimateMinutes != null) return false;
    if (_isFetchingTimeEstimate) return false;
    if (widget.instance.templateTrackingType == 'time') return false;
    return widget.instance.templateId.isNotEmpty;
  }

  Future<void> _fetchTemplateTimeEstimate() async {
    if (_isFetchingTimeEstimate) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _isFetchingTimeEstimate = true;
    try {
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(widget.instance.templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      if (!mounted) return;
      final sanitized = _normalizeTimeEstimate(template.timeEstimateMinutes);
      if (sanitized != null &&
          sanitized != _resolvedTimeEstimateMinutes &&
          mounted) {
        setState(() {
          _resolvedTimeEstimateMinutes = sanitized;
        });
      }
    } catch (_) {
    } finally {
      _isFetchingTimeEstimate = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _quantUpdateTimer?.cancel();
    super.dispose();
  }

  bool get _isBackendCompleted {
    return widget.instance.status == 'completed' ||
        widget.instance.status == 'skipped';
  }

  bool get _isCompleted {
    return _binaryCompletionOverride ?? _isBackendCompleted;
  }

  Color get _impactLevelColor {
    return ItemUIBuildingHelper.getImpactLevelColor(
      theme: FlutterFlowTheme.of(context),
      priority: widget.instance.templatePriority,
    );
  }

  String _getTimerDisplayWithSeconds() {
    return TimerLogicHelper.formatTimeDisplay(widget.instance);
  }

  bool get _isTimerActiveLocal {
    if (widget.instance.templateTrackingType == 'time' &&
        _timerStateOverride != null) {
      return _timerStateOverride!;
    }
    if (widget.instance.templateTrackingType == 'time') {
      return widget.instance.isTimerActive || widget.instance.isTimeLogging;
    }
    return widget.instance.isTimerActive;
  }

  num _currentProgressLocal() {
    if (widget.instance.templateTrackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      return _quantProgressOverride!;
    }
    if (widget.instance.templateTrackingType == 'time') {
      return TimerLogicHelper.getRealTimeAccumulated(widget.instance);
    }
    final val = widget.instance.currentValue;
    if (val is num) return val;
    if (val is String) return num.tryParse(val) ?? 0;
    return 0;
  }

  double get _progressPercentClamped {
    try {
      if (widget.instance.templateTrackingType == 'quantitative') {
        final num progress = _currentProgressLocal();
        final num target = (widget.instance.templateTarget is num)
            ? widget.instance.templateTarget
            : 0;
        if (target == 0) return 0.0;
        final pct = (progress.toDouble() / target.toDouble());
        if (pct.isNaN) return 0.0;
        return pct.clamp(0.0, 1.0);
      } else if (widget.instance.templateTrackingType == 'time') {
        final realTimeAccumulated =
            TimerLogicHelper.getRealTimeAccumulated(widget.instance);
        final target = widget.instance.templateTarget ?? 0;
        if (target == 0) return 0.0;
        final targetMs = target * 60000;
        final pct = (realTimeAccumulated / targetMs);
        if (pct.isNaN) return 0.0;
        return pct.clamp(0.0, 1.0);
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  bool get _shouldShowProgress {
    if (_isExpanded) return true;
    if (widget.instance.templateTrackingType == 'time' && _isTimerActiveLocal) {
      return true;
    }
    return false;
  }

  bool get _isFullyCompleted {
    return _isCompleted;
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullyCompleted && (widget.showCompleted != true)) {
      return const SizedBox.shrink();
    }
    final content = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).cardBorderColor,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: _buildLeftStripe(),
          ),
          const SizedBox(width: 5),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: SizedBox(
                width: 48,
                child: Center(child: _buildLeftControlsCompact()),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                      if (_isExpanded && _hasReminders == null) {
                        _checkForReminders();
                      }
                    });
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.instance.templateName,
                          maxLines: _isExpanded ? null : 1,
                          overflow: _isExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: FlutterFlowTheme.of(context)
                              .bodyMedium
                              .override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                                decoration: _isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                color: _isCompleted
                                    ? FlutterFlowTheme.of(context).secondaryText
                                    : FlutterFlowTheme.of(context).primaryText,
                              ),
                        ),
                        if (_getEnhancedSubtitle(
                                    includeProgress: _shouldShowProgress)
                                .isNotEmpty &&
                            !_isessential) ...[
                          const SizedBox(height: 2),
                          Text(
                            _getEnhancedSubtitle(
                                includeProgress: _shouldShowProgress),
                            maxLines: _isExpanded ? null : 1,
                            overflow: _isExpanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      fontFamily: 'Readex Pro',
                                      color: FlutterFlowTheme.of(context)
                                          .primaryText
                                          .withOpacity(0.7),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                        if (_isExpanded && !_isessential) ...[
                          const SizedBox(height: 4),
                          ItemExpandedDetails(
                            instance: widget.instance,
                            page: widget.page,
                            subtitle: widget.subtitle,
                            isHabit: widget.isHabit,
                            isRecurring: _isRecurringItem(),
                            frequencyDisplay: _getFrequencyDisplay(),
                            hasReminders: _hasReminders,
                            reminderDisplayText: _reminderDisplayText,
                            showCategoryOnExpansion:
                                widget.showExpandedCategoryName,
                            timeEstimateMinutes: _resolvedTimeEstimateMinutes,
                            onEdit: widget.enableExpandedEdit
                                ? _editActivity
                                : null,
                          ),
                        ],
                        if (widget.instance.templateTrackingType != 'binary' &&
                            !widget.treatAsBinary) ...[
                          const SizedBox(height: 4),
                          Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: _leftStripeColor,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _progressPercentClamped,
                                  child: Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: _leftStripeColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: _isExpanded && !_isessential ? 6.0 : 0.0,
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 5),
                        if (_isExpanded && widget.isHabit) ...[
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      HabitDetailStatisticsPage(
                                    habitName: widget.instance.templateName,
                                  ),
                                ),
                              );
                            },
                            child: Icon(
                              Icons.bar_chart,
                              size: 20,
                              color: FlutterFlowTheme.of(context).primary,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        if (widget.showManagementActions && !_isessential) ...[
                          Builder(
                            builder: (btnCtx) => GestureDetector(
                              onTap: () {
                                ItemMenuLogicHelper.showScheduleMenu(
                                  context: context,
                                  anchorContext: btnCtx,
                                  instance: widget.instance,
                                  isRecurringItem: _isRecurringItem(),
                                  currentProgressLocal: _currentProgressLocal(),
                                  onInstanceUpdated: (updated) =>
                                      widget.onInstanceUpdated?.call(updated),
                                  onRefresh: widget.onRefresh,
                                  showUncompleteDialog: _showUncompleteDialog,
                                );
                              },
                              child: const Icon(Icons.calendar_month, size: 20),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        if (widget.showManagementActions && !_isessential) ...[
                          Builder(
                            builder: (btnCtx) => GestureDetector(
                              onTap: () {
                                ItemManagementHelper.showHabitOverflowMenu(
                                  context: context,
                                  anchorContext: btnCtx,
                                  instance: widget.instance,
                                  categories: widget.categories ?? [],
                                  onInstanceDeleted: (deleted) =>
                                      widget.onInstanceDeleted?.call(deleted),
                                  onInstanceUpdated: (updated) =>
                                      widget.onInstanceUpdated?.call(updated),
                                  setUpdating: (val) =>
                                      setState(() => _isUpdating = val),
                                  onRefresh: widget.onRefresh,
                                  onEstimateUpdate: (newEst) => setState(() =>
                                      _resolvedTimeEstimateMinutes = newEst),
                                  editActivity: _editActivity, // ADD THIS
                                  normalizeTimeEstimate:
                                      _normalizeTimeEstimate, // ADD THIS
                                  isMounted: () => mounted, // ADD THIS
                                );
                              },
                              child: const Icon(Icons.more_vert, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_isExpanded &&
                  !_isessential &&
                  widget.showManagementActions) ...[
                Center(
                  child: _buildHabitPriorityStars(),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (!widget.showSwipeTimerAction) {
      return content;
    }

    return Slidable(
      key: ValueKey(widget.instance.reference.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        dismissible: DismissiblePane(
          onDismissed: () {},
          confirmDismiss: () async {
            return false;
          },
        ),
        children: [
          SlidableAction(
            onPressed: (context) => _startTimerFromSwipe(context),
            backgroundColor: FlutterFlowTheme.of(context).primary,
            foregroundColor: Colors.white,
            icon: Icons.timer,
            label: 'Start Timer',
          ),
        ],
      ),
      child: content,
    );
  }

  Widget _buildHabitPriorityStars() {
    return ItemUIBuildingHelper.buildHabitPriorityStars(
      instance: widget.instance,
      context: context,
      updateTemplatePriority: _updateTemplatePriority,
    );
  }

  Future<void> _updateTemplatePriority(int newPriority) async {
    final previousInstance = widget.instance;
    final optimisticInstance =
        InstanceEvents.createOptimisticPropertyUpdateInstance(
      previousInstance,
      {'templatePriority': newPriority},
    );
    widget.onInstanceUpdated?.call(optimisticInstance);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(widget.instance.templateId);
      await templateRef.update({
        'priority': newPriority,
        'lastUpdated': DateTime.now(),
      });
      final instanceRef = ActivityInstanceRecord.collectionForUser(uid)
          .doc(widget.instance.reference.id);
      await instanceRef.update({
        'templatePriority': newPriority,
        'lastUpdated': DateTime.now(),
      });
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      widget.onInstanceUpdated?.call(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      widget.onInstanceUpdated?.call(previousInstance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating priority: $e')),
        );
      }
    }
  }

  Future<void> _editActivity() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final templateRef =
        ActivityRecord.collectionForUser(uid).doc(widget.instance.templateId);
    ActivityRecord template;
    try {
      template = await ActivityRecord.getDocumentOnce(templateRef);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading activity: ${e.toString()}')),
        );
      }
      return;
    }
    if (widget.instance.templateCategoryType == 'task' ||
        widget.instance.templateCategoryType == 'habit') {
      showDialog(
        context: context,
        builder: (_) => ActivityEditorDialog(
          activity: template,
          instance: widget.instance,
          isHabit: widget.instance.templateCategoryType == 'habit',
          categories: widget.categories ?? [],
          onSave: (updatedHabit) async {
            final newEstimate = updatedHabit != null
                ? _normalizeTimeEstimate(updatedHabit.timeEstimateMinutes)
                : null;
            if (mounted) {
              setState(() {
                _resolvedTimeEstimateMinutes = newEstimate;
              });
            } else {
              _resolvedTimeEstimateMinutes = newEstimate;
            }
            if (widget.onRefresh != null) {
              await widget.onRefresh!();
            }
          },
        ),
      );
    }
  }

  Color get _leftStripeColor {
    return ItemUIBuildingHelper.getLeftStripeColor(
      categoryColorHex: widget.categoryColorHex,
      categoryType: widget.instance.templateCategoryType,
    );
  }

  bool get _isessential {
    return widget.instance.templateCategoryType == 'essential';
  }

  Widget _buildLeftStripe() {
    return ItemUIBuildingHelper.buildLeftStripe(
      instance: widget.instance,
      context: context,
      leftStripeColor: _leftStripeColor,
    );
  }

  String _getEnhancedSubtitle({bool includeProgress = true}) {
    return ItemSubtitleReminderHelper.getEnhancedSubtitle(
      baseSubtitle: widget.subtitle,
      page: widget.page,
      instance: widget.instance,
      currentProgressLocal: _currentProgressLocal,
      getTimerDisplayWithSeconds: _getTimerDisplayWithSeconds,
      includeProgress: includeProgress,
    );
  }

  Future<void> _checkForReminders() async {
    await ItemSubtitleReminderHelper.checkForReminders(
      instance: widget.instance,
      isMounted: () => mounted,
      setState: (callback) => setState(callback),
      setHasReminders: (val) => _hasReminders = val,
      setReminderDisplayText: (val) => _reminderDisplayText = val,
    );
  }

  String _getFrequencyDisplay() {
    return ItemUIBuildingHelper.getFrequencyDisplay(widget.instance);
  }

  Widget _buildLeftControlsCompact() {
    return ItemUIBuildingHelper.buildLeftControlsCompact(
      context: context,
      instance: widget.instance,
      showQuickLogOnLeft: widget.showQuickLogOnLeft,
      onQuickLog: widget.onQuickLog,
      treatAsBinary: widget.treatAsBinary,
      isUpdating: _isUpdating,
      isCompleted: _isCompleted,
      impactLevelColor: _impactLevelColor,
      leftStripeColor: _leftStripeColor,
      currentProgressLocal: _currentProgressLocal,
      isTimerActiveLocal: _isTimerActiveLocal,
      pendingQuantIncrement: _pendingQuantIncrement,
      handleBinaryCompletion: _handleBinaryCompletion,
      updateProgress: _updateProgress,
      showQuantControlsMenu: _showQuantControlsMenu,
      toggleTimer: _toggleTimer,
      showTimeControlsMenu: _showTimeControlsMenu,
    );
  }

  Future<void> _updateProgress(int delta) async {
    await ItemQuantitativeControlsHelper.updateProgress(
      delta: delta,
      instance: widget.instance,
      isUpdating: _isUpdating,
      progressReferenceTime: widget.progressReferenceTime,
      setUpdating: (val) => setState(() => _isUpdating = val),
      currentProgressLocal: _currentProgressLocal,
      getTargetValue: _getTargetValue,
      setQuantProgressOverride: (val) =>
          setState(() => _quantProgressOverride = val),
      setBinaryCompletionOverride: (val) =>
          setState(() => _binaryCompletionOverride = val),
      onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
      onRefresh: widget.onRefresh,
      context: context,
      isMounted: () => mounted,
      setState: (callback) => setState(callback),
      getPendingQuantIncrement: () => _pendingQuantIncrement,
      setPendingQuantIncrement: (val) =>
          setState(() => _pendingQuantIncrement = val),
      getQuantUpdateTimer: () => _quantUpdateTimer,
      setQuantUpdateTimer: (val) => setState(() => _quantUpdateTimer = val),
      processPendingQuantUpdate: () => _processPendingQuantUpdate(),
    );
  }

  Future<void> _processPendingQuantUpdate() async {
    await ItemQuantitativeControlsHelper.processPendingQuantUpdate(
      instance: widget.instance,
      progressReferenceTime: widget.progressReferenceTime,
      isUpdating: _isUpdating,
      setUpdating: (val) => setState(() => _isUpdating = val),
      currentProgressLocal: _currentProgressLocal,
      onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
      onRefresh: widget.onRefresh,
      context: context,
      isMounted: () => mounted,
      setState: (callback) => setState(callback),
      getPendingQuantIncrement: () => _pendingQuantIncrement,
      setPendingQuantIncrement: (val) =>
          setState(() => _pendingQuantIncrement = val),
      setQuantProgressOverride: (val) =>
          setState(() => _quantProgressOverride = val),
      getQuantUpdateTimer: () => _quantUpdateTimer,
      setQuantUpdateTimer: (val) => setState(() => _quantUpdateTimer = val),
      processPendingQuantUpdateCallback: () => _processPendingQuantUpdate(),
    );
  }

  Future<String?> _showUncompleteDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uncomplete Task/Habit'),
        content: const Text(
            'This task/habit has calendar logs. What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Keep Logs'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete Logs'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBinaryCompletion(bool completed) async {
    await ItemBinaryControlsHelper.handleBinaryCompletion(
      completed: completed,
      instance: widget.instance,
      isUpdating: _isUpdating,
      treatAsBinary: widget.treatAsBinary,
      progressReferenceTime: widget.progressReferenceTime,
      setUpdating: (val) => _isUpdating = val,
      setBinaryOverride: (val) => _binaryCompletionOverride = val,
      onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
      onRefresh: widget.onRefresh,
      context: context,
      showUncompleteDialog: _showUncompleteDialog,
      currentProgressLocal: _currentProgressLocal(),
      isMounted: () => mounted,
      setState: (callback) => setState(callback),
    );
  }

  Future<void> _toggleTimer() async {
    await ItemTimeControlsHelper.toggleTimer(
      instance: widget.instance,
      isUpdating: _isUpdating,
      setUpdating: (val) => setState(() => _isUpdating = val),
      setTimerOverride: (val) => setState(() => _timerStateOverride = val),
      onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
      context: context,
      checkTimerCompletion: (updated) =>
          ItemTimeControlsHelper.checkTimerCompletion(
        context,
        updated,
        (finalUpdate) => widget.onInstanceUpdated?.call(finalUpdate),
      ),
      isTimerActiveLocal: _isTimerActiveLocal,
    );
  }

  num _getTargetValue() {
    return widget.instance.templateTarget ?? 0;
  }

  Future<void> _showQuantControlsMenu(
      BuildContext anchorContext, bool canDecrement) async {
    await ItemQuantitativeControlsHelper.showQuantControlsMenu(
      context: context,
      anchorContext: anchorContext,
      instance: widget.instance,
      canDecrement: canDecrement,
      currentProgressLocal: _currentProgressLocal,
      getTargetValue: _getTargetValue,
      resetQuantity: () => ItemQuantitativeControlsHelper.resetQuantity(
        instance: widget.instance,
        isUpdating: _isUpdating,
        progressReferenceTime: widget.progressReferenceTime,
        setUpdating: (val) => setState(() => _isUpdating = val),
        setQuantProgressOverride: (val) =>
            setState(() => _quantProgressOverride = val),
        onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
        onRefresh: widget.onRefresh,
        context: context,
        isMounted: () => mounted,
        setState: (callback) => setState(callback),
        showUncompleteDialog: _showUncompleteDialog,
      ),
      updateProgress: (delta) => ItemQuantitativeControlsHelper.updateProgress(
        delta: delta,
        instance: widget.instance,
        isUpdating: _isUpdating,
        progressReferenceTime: widget.progressReferenceTime,
        setUpdating: (val) => setState(() => _isUpdating = val),
        currentProgressLocal: _currentProgressLocal,
        getTargetValue: _getTargetValue,
        setQuantProgressOverride: (val) =>
            setState(() => _quantProgressOverride = val),
        setBinaryCompletionOverride: (val) =>
            setState(() => _binaryCompletionOverride = val),
        onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
        onRefresh: widget.onRefresh,
        context: context,
        isMounted: () => mounted,
        setState: (callback) => setState(callback),
        getPendingQuantIncrement: () => _pendingQuantIncrement,
        setPendingQuantIncrement: (val) =>
            setState(() => _pendingQuantIncrement = val),
        getQuantUpdateTimer: () => _quantUpdateTimer,
        setQuantUpdateTimer: (val) => setState(() => _quantUpdateTimer = val),
        processPendingQuantUpdate: () => _processPendingQuantUpdate(),
      ),
    );
  }

  Future<void> _showTimeControlsMenu(BuildContext anchorContext) async {
    await ItemTimeControlsHelper.showTimeControlsMenu(
      context: context,
      anchorContext: anchorContext,
      instance: widget.instance,
      isUpdating: _isUpdating,
      setUpdating: (val) => setState(() => _isUpdating = val),
      onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
      resetTimer: () => ItemTimeControlsHelper.resetTimer(
        instance: widget.instance,
        isUpdating: _isUpdating,
        setUpdating: (val) => setState(() => _isUpdating = val),
        onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
        context: context,
        isMounted: () => mounted,
        setState: (callback) => setState(callback),
      ),
      showCustomTimeDialog: () => ItemTimeControlsHelper.showCustomTimeDialog(
        instance: widget.instance,
        context: context,
        setCustomTime: (hours, minutes) => ItemTimeControlsHelper.setCustomTime(
          hours: hours,
          minutes: minutes,
          instance: widget.instance,
          isUpdating: _isUpdating,
          setUpdating: (val) => setState(() => _isUpdating = val),
          onInstanceUpdated: (updated) =>
              widget.onInstanceUpdated?.call(updated),
          context: context,
          isMounted: () => mounted,
          setState: (callback) => setState(callback),
          showUncompleteDialog: _showUncompleteDialog,
        ),
        formatTimeFromMs: ItemTimeControlsHelper.formatTimeFromMs,
      ),
      markTimerComplete: () => ItemTimeControlsHelper.markTimerComplete(
        instance: widget.instance,
        isUpdating: _isUpdating,
        setUpdating: (val) => setState(() => _isUpdating = val),
        onInstanceUpdated: (updated) => widget.onInstanceUpdated?.call(updated),
        context: context,
        isMounted: () => mounted,
        setState: (callback) => setState(callback),
      ),
    );
  }

  Future<void> _startTimerFromSwipe(BuildContext context) async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TimerPage(
            initialTimerLogRef: widget.instance.reference,
            taskTitle: widget.instance.templateName,
            fromSwipe: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting timer: $e')),
        );
      }
    }
  }
}
