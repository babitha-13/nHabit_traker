import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart'; // Keep for fetching template on edit
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Helper/utils/timer_logic_helper.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/activity_editor_dialog.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';
import 'package:habit_tracker/Screens/Progress/habit_detail_statistics_page.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Helper/utils/sound_helper.dart';
import 'package:habit_tracker/Screens/Components/item_expanded_details.dart';

class ItemComponent extends StatefulWidget {
  final ActivityInstanceRecord instance;
  final Future<void> Function()? onRefresh;
  final void Function(ActivityRecord updatedHabit)?
      onHabitUpdated; // TODO: Refactor to instance
  final void Function(ActivityRecord deletedHabit)?
      onHabitDeleted; // TODO: Refactor to instance
  final void Function(ActivityInstanceRecord updatedInstance)?
      onInstanceUpdated;
  final void Function(ActivityInstanceRecord deletedInstance)?
      onInstanceDeleted;
  final String? categoryColorHex, page;
  final bool? showCompleted;
  final bool showCalendar;
  final bool showTaskEdit;
  final List<CategoryRecord>? categories;
  final List<ActivityRecord>? tasks; // TODO: Refactor to instance
  final bool isHabit;
  final bool showTypeIcon;
  final bool showRecurringIcon;
  final String? subtitle;
  final bool showExpandedCategoryName;
  final DateTime? progressReferenceTime;
  final bool showQuickLogOnLeft; // NEW: Flag to show + on left
  final VoidCallback? onQuickLog; // NEW: Callback for + on left
  final bool
      treatAsBinary; // NEW: Forces checklist behavior regardless of tracking type
  const ItemComponent(
      {Key? key,
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
      this.treatAsBinary = false})
      : super(key: key);
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
    // Reset quantitative progress override when backend catches up
    if (widget.instance.templateTrackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      final backendValue = widget.instance.currentValue;
      if (backendValue == _quantProgressOverride) {
        setState(() => _quantProgressOverride = null);
      }
    }
    // Reset timer state override when backend catches up or when external change detected
    if (widget.instance.templateTrackingType == 'time' &&
        _timerStateOverride != null) {
      if (widget.instance.isTimerActive == _timerStateOverride) {
        setState(() => _timerStateOverride = null);
      } else if (widget.instance.isTimerActive != _timerStateOverride &&
          widget.instance.isTimerActive != oldWidget.instance.isTimerActive) {
        // External change detected - clear override to sync with actual state
        setState(() => _timerStateOverride = null);
      }
    }
    // Reset binary completion override when backend catches up or instance changes
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
    // Handle timer state changes (existing logic)
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
    // Check if the template is recurring
    // For habits: always recurring
    // For tasks: check if it's a recurring task
    if (widget.instance.templateCategoryType == 'habit') {
      return true; // Habits are always recurring
    } else {
      // For tasks, we need to determine if the template is recurring
      // Since we don't have the isRecurring field cached in the instance,
      // we'll use a heuristic: check if it has frequency configuration
      // A task is recurring if it has any frequency configuration
      return widget.instance.templateCategoryType == 'task' &&
          (widget.instance.templateEveryXPeriodType.isNotEmpty ||
              widget.instance.templatePeriodType.isNotEmpty);
    }
  }

  Future<void> _copyHabit() async {
    try {
      setState(() => _isUpdating = true);
      // Get the template from the instance
      final templateRef = ActivityRecord.collectionForUser(currentUserUid)
          .doc(widget.instance.templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      // Create a new template with "Copy of" prefix
      final newTemplateName = 'Copy of ${template.name}';
      // Create the new activity template
      final newTemplateRef = await createActivity(
        name: newTemplateName,
        categoryId: template.categoryId,
        categoryName: template.categoryName,
        trackingType: template.trackingType,
        target: template.target,
        description: template.description,
        categoryType: template.categoryType,
        priority: template.priority,
        unit: template.unit,
        isRecurring: template.isRecurring,
        frequencyType: template.frequencyType,
        specificDays: template.specificDays,
        startDate: template.startDate,
        dueDate: template.dueDate,
      );
      // Get the new template to create an instance
      final newTemplate = await ActivityRecord.getDocumentOnce(newTemplateRef);
      // Create a new instance for the duplicated template
      await ActivityInstanceService.createActivityInstance(
        templateId: newTemplateRef.id,
        template: newTemplate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Task "${newTemplateName}" created successfully')),
        );
        // Refresh the page to show the new task
        if (widget.onRefresh != null) {
          await widget.onRefresh!();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
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
      // Ignore fetch errors for this non-critical UI enhancement
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
    // In weekly view, items are shown as quantities (not binary completions),
    // so we don't treat them as "completed" for display purposes
    if (widget.page == 'weekly') {
      return false;
    }
    return _binaryCompletionOverride ?? _isBackendCompleted;
  }

  Color get _impactLevelColor {
    final theme = FlutterFlowTheme.of(context);
    switch (widget.instance.templatePriority) {
      case 1:
        return theme.accent3;
      case 2:
        return theme.secondary;
      case 3:
        return theme.primary;
      default:
        return theme.secondary;
    }
  }

  String _getTimerDisplayWithSeconds() {
    return TimerLogicHelper.formatTimeDisplay(widget.instance);
  }

  bool get _isTimerActiveLocal {
    if (widget.instance.templateTrackingType == 'time' &&
        _timerStateOverride != null) {
      return _timerStateOverride!;
    }
    // For session-based tasks, check both isTimerActive and isTimeLogging
    if (widget.instance.templateTrackingType == 'time') {
      return widget.instance.isTimerActive || widget.instance.isTimeLogging;
    }
    return widget.instance.isTimerActive;
  }

  num _currentProgressLocal() {
    // Use optimistic override if present
    if (widget.instance.templateTrackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      return _quantProgressOverride!;
    }
    // For time-based tasks, use real-time accumulated time
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
        // Use real-time accumulated time including currently running elapsed
        final realTimeAccumulated =
            TimerLogicHelper.getRealTimeAccumulated(widget.instance);
        final target = widget.instance.templateTarget ?? 0;
        if (target == 0) return 0.0;
        // Convert target from minutes to milliseconds for comparison
        final targetMs = target * 60000;
        final pct = (realTimeAccumulated / targetMs);
        if (pct.isNaN) return 0.0;
        // Allow > 1.0 to show overtime, but clamp for display
        return pct.clamp(0.0, 1.0);
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Determine if progress should be shown in subtitle
  /// For timer tasks: show when expanded OR when timer is running
  /// For other tasks: show only when expanded
  bool get _shouldShowProgress {
    if (_isExpanded) return true;
    // For timer tasks, also show when timer is running (even in compact form)
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
    return Slidable(
      key: ValueKey(widget.instance.reference.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        dismissible: DismissiblePane(
          onDismissed: () {},
          confirmDismiss: () async {
            // TODO: Phase 3 - Timer logic
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
      child: Container(
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
            // Left stripe - match content height
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: _buildLeftStripe(),
            ),
            const SizedBox(width: 5),
            // Left controls - centered vertically
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
                        // Check for reminders when expanding
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
                                      ? FlutterFlowTheme.of(context)
                                          .secondaryText
                                      : FlutterFlowTheme.of(context)
                                          .primaryText,
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
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
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
                              onEdit: _editActivity,
                            ),
                          ],
                          // Progress bar inside the text container for proper vertical centering
                          if (widget.instance.templateTrackingType !=
                                  'binary' &&
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
            // Right controls - centered vertically, match content height
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icons container - match content height (50) for alignment, but use padding to reduce visual space
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
                          if (!_isessential) ...[
                            Builder(
                              builder: (btnCtx) => GestureDetector(
                                onTap: () {
                                  _showScheduleMenu(btnCtx);
                                },
                                child:
                                    const Icon(Icons.calendar_month, size: 20),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (!_isessential) ...[
                            Builder(
                              builder: (btnCtx) => GestureDetector(
                                onTap: () {
                                  _showHabitOverflowMenu(btnCtx);
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
                // Priority stars - centered horizontally relative to icons above
                if (_isExpanded && !_isessential) ...[
                  Center(
                    child: _buildHabitPriorityStars(),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitPriorityStars() {
    final current = widget.instance.templatePriority;
    final nextPriority = current >= 3 ? 1 : current + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async => _updateTemplatePriority(nextPriority),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 16,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
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
      // Get the template document
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(widget.instance.templateId);
      // Update the template's priority
      await templateRef.update({
        'priority': newPriority,
        'lastUpdated': DateTime.now(),
      });
      // Also update the instance's cached priority for immediate UI update
      final instanceRef = ActivityInstanceRecord.collectionForUser(uid)
          .doc(widget.instance.reference.id);
      await instanceRef.update({
        'templatePriority': newPriority,
        'lastUpdated': DateTime.now(),
      });
      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);
      // Broadcast the instance update event
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
    } else {
      // Fallback or error if unknown type
    }
  }

  Future<void> _showHabitOverflowMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: const [
        PopupMenuItem<String>(
            value: 'edit',
            height: 32,
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'copy',
            height: 32,
            child: Text('Duplicate', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    // To edit/delete, we need the original template document.
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final templateRef =
        ActivityRecord.collectionForUser(uid).doc(widget.instance.templateId);
    if (selected == 'edit') {
      await _editActivity();
    } else if (selected == 'copy') {
      await _copyHabit();
    } else if (selected == 'delete') {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Activity'),
          content: Text(
              'Delete "${widget.instance.templateName}"? This will delete the activity and all its history. This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: FlutterFlowTheme.of(context).error,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (shouldDelete == true) {
        final deletedInstance = widget.instance;
        // Optimistically remove the instance from the UI
        widget.onInstanceDeleted?.call(deletedInstance);
        InstanceEvents.broadcastInstanceDeleted(deletedInstance);
        try {
          // Soft delete the template
          await deleteHabit(templateRef);
          // Hard delete all instances for the template
          await ActivityInstanceService.deleteInstancesForTemplate(
              templateId: widget.instance.templateId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Activity deleted')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting activity: $e')),
            );
          }
          if (widget.onRefresh != null) {
            await widget.onRefresh!();
          }
        }
      }
    }
  }

  // TODO: Phase 4 - Reschedule/Skip logic
  Future<void> _showScheduleMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final isHabit = widget.instance.templateCategoryType == 'habit';
    final isRecurringTask =
        widget.instance.templateCategoryType == 'task' && _isRecurringItem();
    final isSnoozed = widget.instance.snoozedUntil != null &&
        DateTime.now().isBefore(widget.instance.snoozedUntil!);
    final menuItems = <PopupMenuEntry<String>>[];
    if (isHabit) {
      // Habit-specific menu
      final isSkipped = widget.instance.status == 'skipped';
      if (isSkipped) {
        // Show unskip option for skipped habits
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12)),
          ),
        );
      } else if (isSnoozed) {
        // Show bring back option for snoozed habits
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'bring_back',
            height: 32,
            child: Text('Bring back', style: TextStyle(fontSize: 12)),
          ),
        );
      } else {
        // Check if habit has partial progress
        final currentValue = _currentProgressLocal();
        final hasProgress = currentValue > 0;
        if (hasProgress) {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'skip_rest',
              height: 32,
              child: Text('Skip the rest', style: TextStyle(fontSize: 12)),
            ),
          );
        } else {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'skip',
              height: 32,
              child: Text('Skip', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        // Check if today is the last day of the window
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final isLastDay = widget.instance.windowEndDate != null &&
            DateTime(
                    widget.instance.windowEndDate!.year,
                    widget.instance.windowEndDate!.month,
                    widget.instance.windowEndDate!.day)
                .isAtSameMomentAs(today);
        // Add "Snooze for Today" option (only if not last day)
        if (!isLastDay) {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'snooze_today',
              height: 32,
              child: Text('Snooze for today', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        // Add snooze option
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'snooze',
            height: 32,
            child: Text('Snooze until...', style: TextStyle(fontSize: 12)),
          ),
        );
      }
    } else if (isRecurringTask) {
      // Recurring task menu
      final isSkipped = widget.instance.status == 'skipped';
      if (isSkipped) {
        // Show unskip option for skipped tasks
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12)),
          ),
        );
      } else if (isSnoozed) {
        // Show bring back option for snoozed tasks
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'bring_back',
            height: 32,
            child: Text('Bring back', style: TextStyle(fontSize: 12)),
          ),
        );
      } else {
        // Calculate if "Skip all past occurrences" should be shown
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final missingInstancesCount =
            ActivityInstanceService.calculateMissingInstancesFromInstance(
          instance: widget.instance,
          today: today,
        );
        // Standard recurring task options
        final recurringTaskOptions = <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'skip',
            height: 32,
            child: Text('Skip this occurrence', style: TextStyle(fontSize: 12)),
          ),
        ];
        // Only show "Skip all past occurrences" if there are 2+ missing instances
        if (missingInstancesCount >= 2) {
          recurringTaskOptions.add(
            const PopupMenuItem<String>(
              value: 'skip_until_today',
              height: 32,
              child: Text('Skip all past occurrences',
                  style: TextStyle(fontSize: 12)),
            ),
          );
        }
        recurringTaskOptions.addAll([
          const PopupMenuItem<String>(
            value: 'skip_until',
            height: 32,
            child: Text('Skip until...', style: TextStyle(fontSize: 12)),
          ),
          const PopupMenuDivider(height: 6),
          const PopupMenuItem<String>(
            value: 'snooze',
            height: 32,
            child: Text('Snooze until...', style: TextStyle(fontSize: 12)),
          ),
        ]);
        menuItems.addAll(recurringTaskOptions);
      }
    } else {
      // One-time tasks menu - show contextual options
      final isSkipped = widget.instance.status == 'skipped';
      if (isSkipped) {
        // Show unskip option for skipped one-time tasks
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12)),
          ),
        );
      } else {
        final currentDueDate = widget.instance.dueDate;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final isDueToday =
            currentDueDate != null && _isSameDay(currentDueDate, today);
        final isDueTomorrow =
            currentDueDate != null && _isSameDay(currentDueDate, tomorrow);
        // Only show "Schedule for today" if not already due today
        if (!isDueToday) {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'today',
              height: 32,
              child: Text('Schedule for today', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        // Only show "Schedule for tomorrow" if not already due tomorrow
        if (!isDueTomorrow) {
          menuItems.add(
            const PopupMenuItem<String>(
              value: 'tomorrow',
              height: 32,
              child:
                  Text('Schedule for tomorrow', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        // Always show "Pick due date"
        menuItems.add(
          const PopupMenuItem<String>(
            value: 'pick_date',
            height: 32,
            child: Text('Pick due date...', style: TextStyle(fontSize: 12)),
          ),
        );
        // Only show "Clear due date" if task has a due date
        if (currentDueDate != null) {
          menuItems.addAll([
            const PopupMenuDivider(height: 6),
            const PopupMenuItem<String>(
              value: 'clear_due_date',
              height: 32,
              child: Text('Clear due date', style: TextStyle(fontSize: 12)),
            ),
          ]);
        }
      }
    }
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: menuItems,
    );
    if (selected == null) return;
    await _handleScheduleAction(selected);
  }

  Future<void> _handleScheduleAction(String action) async {
    final previousInstance = widget.instance;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      switch (action) {
        case 'unskip':
          _applyOptimisticUnskip();
          await _handleUnskip();
          break;
        case 'skip':
          _applyOptimisticSkip();
          await ActivityInstanceService.skipInstance(
            instanceId: widget.instance.reference.id,
          );
          final message = widget.instance.templateCategoryType == 'habit'
              ? 'Habit skipped'
              : 'Occurrence skipped';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          break;
        case 'skip_until_today':
          _applyOptimisticSkip();
          await ActivityInstanceService.skipInstancesUntil(
            templateId: widget.instance.templateId,
            untilDate: today,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Skipped all past occurrences')),
          );
          break;
        case 'skip_until':
          final picked = await showDatePicker(
            context: context,
            initialDate: tomorrow,
            firstDate: today,
            lastDate: today.add(const Duration(days: 365 * 5)),
          );
          if (picked != null) {
            _applyOptimisticSkip();
            await ActivityInstanceService.skipInstancesUntil(
              templateId: widget.instance.templateId,
              untilDate: picked,
            );
            final label = DateFormat('EEE, MMM d').format(picked);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Skipped until $label')),
            );
          }
          break;
        case 'today':
          _applyOptimisticReschedule(
            today,
            newDueTime: widget.instance.dueTime,
          );
          await ActivityInstanceService.rescheduleInstance(
            instanceId: widget.instance.reference.id,
            newDueDate: today,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled for today')),
          );
          break;
        case 'tomorrow':
          _applyOptimisticReschedule(
            tomorrow,
            newDueTime: widget.instance.dueTime,
          );
          await ActivityInstanceService.rescheduleInstance(
            instanceId: widget.instance.reference.id,
            newDueDate: tomorrow,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled for tomorrow')),
          );
          break;
        case 'pick_date':
          final picked = await showDatePicker(
            context: context,
            initialDate: widget.instance.dueDate ?? tomorrow,
            firstDate: today,
            lastDate: today.add(const Duration(days: 365 * 5)),
          );
          if (picked != null) {
            _applyOptimisticReschedule(
              picked,
              newDueTime: widget.instance.dueTime,
            );
            await ActivityInstanceService.rescheduleInstance(
              instanceId: widget.instance.reference.id,
              newDueDate: picked,
            );
            final label = DateFormat('EEE, MMM d').format(picked);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scheduled for $label')),
            );
          }
          break;
        case 'clear_due_date':
          _applyOptimisticClearDueDate();
          await ActivityInstanceService.removeDueDateFromInstance(
            instanceId: widget.instance.reference.id,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Due date cleared')),
          );
          break;
        case 'skip_rest':
          _applyOptimisticSkip();
          await _handleHabitSkipRest();
          break;
        case 'snooze_today':
          await _handleSnoozeForToday();
          break;
        case 'snooze':
          await _handleSnooze();
          break;
        case 'bring_back':
          await _handleBringBack();
          break;
      }
      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      widget.onInstanceUpdated?.call(previousInstance);
      if (widget.onRefresh != null) {
        await widget.onRefresh!();
      }
    }
  }

  void _applyOptimisticInstance(ActivityInstanceRecord optimisticInstance) {
    widget.onInstanceUpdated?.call(optimisticInstance);
  }

  void _applyOptimisticSkip() {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticSkippedInstance(widget.instance),
    );
  }

  void _applyOptimisticUnskip() {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticUncompletedInstance(widget.instance),
    );
  }

  void _applyOptimisticReschedule(DateTime newDueDate, {String? newDueTime}) {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticRescheduledInstance(
        widget.instance,
        newDueDate: newDueDate,
        newDueTime: newDueTime,
      ),
    );
  }

  void _applyOptimisticClearDueDate() {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticPropertyUpdateInstance(
        widget.instance,
        {'dueDate': null, 'dueTime': null},
      ),
    );
  }

  void _applyOptimisticSnooze(DateTime until) {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticSnoozedInstance(
        widget.instance,
        snoozedUntil: until,
      ),
    );
  }

  void _applyOptimisticUnsnooze() {
    _applyOptimisticInstance(
      InstanceEvents.createOptimisticUnsnoozedInstance(widget.instance),
    );
  }

  Future<void> _handleUnskip() async {
    try {
      // Check if instance has calendar logs before uncompleting
      bool deleteLogs = false;
      if (widget.instance.timeLogSessions.isNotEmpty) {
        final userChoice = await _showUncompleteDialog();
        if (userChoice == null || userChoice == 'cancel') {
          // User cancelled, abort unskip
          return;
        }
        deleteLogs = userChoice == 'delete';
      }

      await ActivityInstanceService.uncompleteInstance(
        instanceId: widget.instance.reference.id,
        deleteLogs: deleteLogs,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Item unskipped and returned to pending')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unskipping: $e')),
        );
      }
    }
  }

  Color get _leftStripeColor {
    // Use category color for all types (Tasks, Habits, Essentials)
    final hex = widget.categoryColorHex;
    if (hex != null && hex.isNotEmpty) {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        // Silently ignore color parsing errors - fallback to default color
      }
    }
    // Fallback to default colors if category color not provided
    if (widget.instance.templateCategoryType == 'essential') {
      return const Color(0xFF9E9E9E); // Medium grey fallback
    }
    if (widget.instance.templateCategoryType == 'task') {
      return const Color(0xFF2F4F4F); // Dark Slate Gray fallback
    }
    return Colors.black; // Default fallback for habits
  }

  bool get _isessential {
    return widget.instance.templateCategoryType == 'essential';
  }

  Widget _buildLeftStripe() {
    final categoryType = widget.instance.templateCategoryType;

    // ConstrainedBox wrapper provides height constraints
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : constraints.minHeight;

        if (categoryType == 'essential') {
          // Double line for Essentials
          return SizedBox(
            width: 5, // Slightly wider to accommodate double lines
            height: height,
            child: CustomPaint(
              size: Size(5, height),
              painter: _DoubleLinePainter(color: _leftStripeColor),
            ),
          );
        } else if (categoryType == 'habit') {
          // Dotted line for Habits
          return SizedBox(
            width: 3,
            height: height,
            child: CustomPaint(
              size: Size(3, height),
              painter: _DottedLinePainter(color: _leftStripeColor),
            ),
          );
        } else {
          // Solid line for Tasks (default) - expands to fill ConstrainedBox height
          return Container(
            width: 4,
            decoration: BoxDecoration(
              color: _leftStripeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }
      },
    );
  }

  String _getProgressDisplayText() {
    switch (widget.instance.templateTrackingType) {
      case 'binary':
        return '';
      case 'quantitative':
        final progress = _currentProgressLocal();
        final target = widget.instance.templateTarget;
        return '$progress/$target ${widget.instance.templateUnit}';
      case 'time':
        final target = _getTemplateTargetMinutes();
        final currentTime = _getTimerDisplayWithSeconds();
        // For completed tasks, show max(actual, target) / target
        if (widget.instance.status == 'completed') {
          final targetFormatted = TimerLogicHelper.formatTargetTime(target);
          // Use max of actual time or target time for the left side
          final actualTimeMs =
              TimerLogicHelper.getRealTimeAccumulated(widget.instance);
          final targetTimeMs = target * 60000;
          final maxTimeMs =
              actualTimeMs > targetTimeMs ? actualTimeMs : targetTimeMs;
          final maxTimeFormatted = _formatTimeFromMs(maxTimeMs);
          return '$maxTimeFormatted / $targetFormatted';
        }
        // For incomplete tasks, show current time / - (undefined target)
        if (target == 0) {
          return '$currentTime / -';
        }
        // For tasks with defined target, show normal format
        final targetFormatted = TimerLogicHelper.formatTargetTime(target);
        return '$currentTime / $targetFormatted';
      default:
        return '';
    }
  }

  int _getTemplateTargetMinutes() {
    final targetValue = widget.instance.templateTarget;
    if (targetValue == null) return 0;
    if (targetValue is num) return targetValue.toInt();
    if (targetValue is String) {
      return int.tryParse(targetValue) ?? 0;
    }
    return 0;
  }

  String _getEnhancedSubtitle({bool includeProgress = true}) {
    final baseSubtitle = widget.subtitle ?? '';
    final progressText = _getProgressDisplayText();

    // For queue page, always remove category name from subtitle (it's shown next to icon in expanded view)
    String processedSubtitle = baseSubtitle;
    if (widget.page == 'queue' || _isQueuePageSubtitle(baseSubtitle)) {
      processedSubtitle = _removeCategoryNameFromSubtitle(baseSubtitle);
    }

    // Add due time to subtitle if date exists but time doesn't
    processedSubtitle = _addDueTimeToSubtitle(processedSubtitle);

    if (processedSubtitle.isEmpty && progressText.isEmpty) {
      return '';
    }

    if (processedSubtitle.isEmpty) {
      return includeProgress ? progressText : '';
    }

    if (progressText.isEmpty) {
      return processedSubtitle;
    }

    // Due date first, then progress stats (only if includeProgress is true)
    if (includeProgress) {
      return '$processedSubtitle • $progressText';
    } else {
      return processedSubtitle;
    }
  }

  String _addDueTimeToSubtitle(String subtitle) {
    // Check if subtitle already contains a time (indicated by @ symbol)
    if (subtitle.contains('@')) {
      return subtitle; // Already has time, don't add
    }

    // Get due time from instance (check both dueTime and templateDueTime)
    String? dueTimeStr;
    if (widget.instance.hasDueTime()) {
      dueTimeStr = TimeUtils.formatTimeForDisplay(widget.instance.dueTime);
    } else if (widget.instance.hasTemplateDueTime()) {
      dueTimeStr =
          TimeUtils.formatTimeForDisplay(widget.instance.templateDueTime);
    }

    final bool hasDueTime = dueTimeStr != null && dueTimeStr.isNotEmpty;
    final timeSuffix = hasDueTime ? ' @ $dueTimeStr' : '';

    // If instance has dueDate, we should add time even if date pattern isn't detected
    // This handles cases where subtitle format might be different
    if (widget.instance.dueDate == null || _isessential) {
      return subtitle; // No due date, can't add time
    }

    // Check if subtitle contains a date pattern (common date formats)
    // Patterns: "Dec 10", "Dec 10, 2024", "Today", "Tomorrow", "MMM d" format, etc.
    final datePatterns = [
      RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\b',
          caseSensitive: false), // Matches "Dec 10" or "Dec 10, 2024"
      RegExp(r'\bToday\b', caseSensitive: false),
      RegExp(r'\bTomorrow\b', caseSensitive: false),
      RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'), // MM/DD/YYYY or DD-MM-YYYY
    ];

    bool hasDate = false;
    for (final pattern in datePatterns) {
      if (pattern.hasMatch(subtitle)) {
        hasDate = true;
        break;
      }
    }

    // Also check if instance has dueDate (more reliable check)
    if (!hasDate && widget.instance.dueDate != null) {
      // Format the due date to match common subtitle formats
      final dueDate = widget.instance.dueDate!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      // Check both MMMd and yMMMd formats (habits use yMMMd)
      String dateStrMMMd;
      String dateStrYMMMd;
      if (dueDateOnly.isAtSameMomentAs(today)) {
        dateStrMMMd = 'Today';
        dateStrYMMMd = 'Today';
      } else if (dueDateOnly.isAtSameMomentAs(tomorrow)) {
        dateStrMMMd = 'Tomorrow';
        dateStrYMMMd = 'Tomorrow';
      } else {
        dateStrMMMd = DateFormat.MMMd().format(dueDate); // "Dec 10"
        dateStrYMMMd = DateFormat.yMMMd().format(dueDate); // "Dec 10, 2024"
      }

      // Check if subtitle starts with or contains either date format
      if (subtitle.contains(dateStrMMMd) ||
          subtitle.startsWith(dateStrMMMd) ||
          subtitle.contains(dateStrYMMMd) ||
          subtitle.startsWith(dateStrYMMMd)) {
        hasDate = true;
      }
    }

    if (hasDate) {
      if (!hasDueTime) {
        return subtitle; // Already shows date but no time to append
      }
      // Append time to the date part
      // Find where the date ends (before any bullet points or other text)
      final dateEndIndex = subtitle.indexOf(' •');
      if (dateEndIndex > 0) {
        // Insert time before the bullet
        return '${subtitle.substring(0, dateEndIndex)}$timeSuffix${subtitle.substring(dateEndIndex)}';
      } else {
        // Append time at the end of the date
        return '$subtitle$timeSuffix';
      }
    }

    // If we have dueDate but didn't detect date pattern, we need to add date + time
    // This handles cases where subtitle doesn't contain a date (e.g., "food • Every day")
    if (widget.instance.dueDate != null && !hasDate) {
      // Format the due date
      final dueDate = widget.instance.dueDate!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);

      String dateStr;
      if (dueDateOnly.isAtSameMomentAs(today)) {
        dateStr = 'Today';
      } else if (dueDateOnly.isAtSameMomentAs(tomorrow)) {
        dateStr = 'Tomorrow';
      } else {
        // Use MMMd format for consistency (shorter, cleaner)
        dateStr = DateFormat.MMMd().format(dueDate); // "Dec 10"
      }

      final dateWithOptionalTime = '$dateStr$timeSuffix';
      if (subtitle.isEmpty) {
        return dateWithOptionalTime;
      } else {
        // Add date + time at the beginning, followed by existing subtitle
        return '$dateWithOptionalTime • $subtitle';
      }
    }

    return subtitle;
  }

  bool _isQueuePageSubtitle(String subtitle) {
    // Check if subtitle contains category name pattern (common in queue page)
    final categoryName = widget.instance.templateCategoryName;
    if (categoryName.isEmpty) return false;
    // Queue page subtitles often have category name with bullet separators or at start/end
    return subtitle.contains(' • $categoryName') ||
        subtitle.contains('$categoryName •') ||
        subtitle.startsWith('$categoryName ') ||
        subtitle == categoryName;
  }

  String _removeCategoryNameFromSubtitle(String subtitle) {
    final categoryName = widget.instance.templateCategoryName;
    if (categoryName.isEmpty) return subtitle;

    // Handle different subtitle formats from queue page
    // Format 1: "categoryName" or "categoryName @ time"
    if (subtitle.startsWith('$categoryName ')) {
      final remaining = subtitle.substring(categoryName.length).trim();
      // If it starts with "@", keep it, otherwise it might be just category name
      if (remaining.startsWith('@')) {
        return remaining;
      }
      return remaining.isEmpty ? '' : remaining;
    }
    if (subtitle == categoryName) {
      return '';
    }

    // Format 2: "statusText • categoryName • Due: date @ time"
    if (subtitle.contains(' • $categoryName • ')) {
      return subtitle.replaceAll(' • $categoryName • ', ' • ');
    }
    if (subtitle.contains(' • $categoryName')) {
      return subtitle.replaceAll(' • $categoryName', '');
    }

    // Format 3: "date @ time • categoryName"
    if (subtitle.endsWith(' • $categoryName')) {
      return subtitle
          .substring(0, subtitle.length - categoryName.length - 3)
          .trim();
    }

    return subtitle;
  }

  /// Check if the template has reminders configured
  Future<void> _checkForReminders() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        if (mounted) {
          setState(() => _hasReminders = false);
        }
        return;
      }

      final templateRef = ActivityRecord.collectionForUser(userId)
          .doc(widget.instance.templateId);
      final templateDoc = await templateRef.get();

      if (!templateDoc.exists) {
        if (mounted) {
          setState(() => _hasReminders = false);
        }
        return;
      }

      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Check if instance has due time (for relative reminders)
      final hasDueTime =
          widget.instance.hasDueTime() || widget.instance.hasTemplateDueTime();

      // Check if template has reminders
      bool hasReminders = false;
      String? reminderDisplayText;
      if (template.hasReminders()) {
        final reminders = ReminderConfigList.fromMapList(template.reminders);
        // Check if any reminder is enabled
        hasReminders = reminders.any((reminder) => reminder.enabled);
        // Build display text for reminders
        if (hasReminders) {
          final List<String> reminderTexts = [];

          // Add fixed time reminders
          final fixedTimeReminders = reminders
              .where((r) => r.enabled && r.fixedTimeMinutes != null)
              .toList();
          if (fixedTimeReminders.isNotEmpty) {
            final times = fixedTimeReminders
                .map((r) => TimeUtils.formatTimeOfDayForDisplay(r.time))
                .toList();
            reminderTexts.addAll(times);
          }

          // Add relative reminders (offset-based) if due time exists
          if (hasDueTime) {
            final relativeReminders = reminders
                .where((r) =>
                    r.enabled &&
                    r.fixedTimeMinutes == null) // Only offset-based reminders
                .toList();
            if (relativeReminders.isNotEmpty) {
              final descriptions =
                  relativeReminders.map((r) => r.getDescription()).toList();
              reminderTexts.addAll(descriptions);
            }
          }

          if (reminderTexts.isNotEmpty) {
            reminderDisplayText = reminderTexts.join(', ');
          }
        }
      }

      if (mounted) {
        setState(() {
          _hasReminders = hasReminders;
          _reminderDisplayText = reminderDisplayText;
        });
      }
    } catch (e) {
      // On error, assume no reminders
      if (mounted) {
        setState(() => _hasReminders = false);
      }
    }
  }

  String _getFrequencyDisplay() {
    final instance = widget.instance;

    // Only show frequency for recurring items
    if (!_isRecurringItem()) return '';

    // Check for "every X period" pattern
    if (instance.templateEveryXValue > 0 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      final value = instance.templateEveryXValue;
      final period = instance.templateEveryXPeriodType;

      if (value == 1) {
        switch (period) {
          case 'days':
            return 'Every day';
          case 'weeks':
            return 'Every week';
          case 'months':
            return 'Every month';
          default:
            return 'Every $value ${period}';
        }
      } else {
        final periodName = period == 'days'
            ? 'days'
            : period == 'weeks'
                ? 'weeks'
                : 'months';
        return 'Every $value $periodName';
      }
    }

    // Check for "times per period" pattern
    if (instance.templateTimesPerPeriod > 0 &&
        instance.templatePeriodType.isNotEmpty) {
      final times = instance.templateTimesPerPeriod;
      final period = instance.templatePeriodType;

      final periodName = period == 'weeks'
          ? (times == 1 ? 'week' : 'weeks')
          : (times == 1 ? 'month' : 'months');

      return '$times time${times == 1 ? '' : 's'} per $periodName';
    }

    // Default fallback
    return '';
  }

  Widget _buildLeftControlsCompact() {
    if (widget.showQuickLogOnLeft) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onQuickLog,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Icon(
              Icons.add_circle_outline,
              size: 24,
              color: FlutterFlowTheme.of(context).primary,
            ),
          ),
        ),
      );
    }
    // If treatAsBinary is enabled, use binary controls regardless of actual tracking type
    final effectiveTrackingType =
        widget.treatAsBinary ? 'binary' : widget.instance.templateTrackingType;

    switch (effectiveTrackingType) {
      case 'binary':
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _isUpdating
                ? null
                : () async {
                    await _handleBinaryCompletion(!_isCompleted);
                  },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _isCompleted ? _impactLevelColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: _isCompleted
                      ? null
                      : Border.all(
                          color: _leftStripeColor,
                          width: 2,
                        ),
                ),
                child: _isCompleted
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        );
      case 'quantitative':
        final current = _currentProgressLocal();
        final canDecrement = current > 0;
        return Builder(
          builder: (btnCtx) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _updateProgress(1),
              onLongPress: () => _showQuantControlsMenu(btnCtx, canDecrement),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _leftStripeColor,
                      width: 2,
                    ),
                  ),
                  child: Opacity(
                    opacity:
                        (_isUpdating || _pendingQuantIncrement > 0) ? 0.6 : 1.0,
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: _leftStripeColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = _isTimerActiveLocal;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _isUpdating ? null : () => _toggleTimer(),
            onLongPress:
                _isUpdating ? null : () => _showTimeControlsMenu(context),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isActive
                      ? FlutterFlowTheme.of(context).error
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: isActive
                      ? null
                      : Border.all(
                          color: _leftStripeColor,
                          width: 2,
                        ),
                ),
                child: Icon(
                  isActive ? Icons.stop : Icons.play_arrow,
                  size: 18,
                  color: isActive ? Colors.white : _leftStripeColor,
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _updateProgress(int delta) async {
    // For binary habits, use immediate update (no batching needed)
    if (widget.instance.templateTrackingType == 'binary' &&
        widget.instance.templateCategoryType == 'habit') {
      if (_isUpdating) return;
      setState(() {
        _isUpdating = true;
      });
      try {
        final currentValue = _currentProgressLocal();
        final target = _getTargetValue();
        final newValue = (currentValue + delta).clamp(0, double.infinity);
        // Cap at 10x target to prevent accidental pocket taps
        final maxCompletions = (target * 10).toInt();
        if (newValue > maxCompletions) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Maximum completions reached (${maxCompletions}x)')),
            );
          }
          setState(() => _isUpdating = false);
          return;
        }
        // Set optimistic state immediately for local UI
        setState(() => _quantProgressOverride = newValue.toInt());

        // Service method will broadcast optimistically
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: widget.instance.reference.id,
          currentValue: newValue,
          referenceTime: widget.progressReferenceTime,
        );
      } catch (e) {
        // Revert optimistic state on error
        setState(() => _quantProgressOverride = null);
        widget.onInstanceUpdated?.call(widget.instance);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating progress: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isUpdating = false;
          });
        }
      }
      return;
    }

    // For quantitative activities: batch processing with immediate UI update
    // Accumulate the increment
    _pendingQuantIncrement += delta;

    // Update UI optimistically immediately
    final currentValue = _currentProgressLocal();
    final newOptimisticValue =
        (currentValue + _pendingQuantIncrement).clamp(0, double.infinity);

    final targetValue = _getTargetValue();
    setState(() {
      _quantProgressOverride = newOptimisticValue.toInt();
      // Optimistically update completion status based on target
      if (targetValue > 0) {
        if (newOptimisticValue >= targetValue) {
          _binaryCompletionOverride = true;
        } else {
          // If value falls below target, clear completion override optimistically
          // This ensures immediate UI update when decreasing quantity
          _binaryCompletionOverride = false;
        }
      }
    });

    // Play step counter sound for quantitative updates
    SoundHelper().playStepCounterSound();

    // Check if target is reached and play completion sound
    if (targetValue > 0 && newOptimisticValue >= targetValue) {
      SoundHelper().playCompletionSound();
    }

    // Cancel existing timer if any
    _quantUpdateTimer?.cancel();

    // Schedule batched backend update after a short delay (300ms)
    // This allows rapid clicks to accumulate before sending to backend
    _quantUpdateTimer = Timer(const Duration(milliseconds: 300), () {
      _processPendingQuantUpdate();
    });
  }

  Future<void> _processPendingQuantUpdate() async {
    if (_pendingQuantIncrement == 0) return;
    if (_isUpdating) {
      // If already updating, reschedule to process after current update completes
      _quantUpdateTimer = Timer(const Duration(milliseconds: 300), () {
        _processPendingQuantUpdate();
      });
      return;
    }

    final incrementToProcess = _pendingQuantIncrement;
    // Get the value to send BEFORE resetting pending
    // _quantProgressOverride already includes all pending increments
    final currentValue = _currentProgressLocal();
    _pendingQuantIncrement = 0; // Reset before processing

    setState(() {
      _isUpdating = true;
    });

    try {
      // Service method will broadcast optimistically
      await ActivityInstanceService.updateInstanceProgress(
        instanceId: widget.instance.reference.id,
        currentValue: currentValue,
        referenceTime: widget.progressReferenceTime,
      );
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      widget.onInstanceUpdated?.call(updatedInstance);
      await _handleQuantCompletion(updatedInstance);
      await _handleQuantUncompletion(updatedInstance);
      // Reconciliation happens automatically via service method broadcasts
      // The override will be cleared when backend value matches
    } catch (e) {
      // Revert optimistic state on error - subtract what we tried to process
      setState(() {
        _quantProgressOverride = (currentValue - incrementToProcess)
            .clamp(0, double.infinity)
            .toInt();
      });
      // Re-add to pending since it failed
      _pendingQuantIncrement += incrementToProcess;
      widget.onInstanceUpdated?.call(widget.instance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }

      // Process any new pending increments that accumulated during the update
      if (_pendingQuantIncrement != 0) {
        _quantUpdateTimer = Timer(const Duration(milliseconds: 300), () {
          _processPendingQuantUpdate();
        });
      }
    }
  }

  bool _shouldAutoCompleteQuant(ActivityInstanceRecord instance) {
    final target = _valueToNum(instance.templateTarget);
    if (target <= 0) return false;
    if (instance.status == 'completed' || instance.status == 'skipped')
      return false;
    final current = _valueToNum(instance.currentValue);
    return current >= target;
  }

  num _valueToNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  bool _shouldAutoUncompleteQuant(ActivityInstanceRecord instance) {
    final target = _valueToNum(instance.templateTarget);
    if (target <= 0) return false;
    if (instance.status != 'completed' && instance.status != 'skipped')
      return false;
    final current = _valueToNum(instance.currentValue);
    return current < target;
  }

  Future<void> _handleQuantCompletion(
      ActivityInstanceRecord updatedInstance) async {
    if (!_shouldAutoCompleteQuant(updatedInstance)) return;
    try {
      await ActivityInstanceService.completeInstance(
        instanceId: widget.instance.reference.id,
        finalValue: updatedInstance.currentValue,
      );
      final completedInstance =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      widget.onInstanceUpdated?.call(completedInstance);
      if (widget.instance.templateCategoryType == 'habit') {
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing task: $e')),
        );
      }
    }
  }

  Future<void> _handleQuantUncompletion(
      ActivityInstanceRecord updatedInstance) async {
    if (!_shouldAutoUncompleteQuant(updatedInstance)) return;
    try {
      await ActivityInstanceService.uncompleteInstance(
        instanceId: widget.instance.reference.id,
      );
      final uncompletedInstance =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      widget.onInstanceUpdated?.call(uncompletedInstance);
      if (widget.instance.templateCategoryType == 'habit') {
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uncompleting task: $e')),
        );
      }
    }
  }

  /// Show dialog asking user what to do with calendar logs when uncompleting
  /// Returns 'keep', 'delete', or 'cancel'
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
    if (_isUpdating) return;
    bool deleteLogs = false;
    if (!completed && widget.instance.timeLogSessions.isNotEmpty) {
      final userChoice = await _showUncompleteDialog();
      if (userChoice == null || userChoice == 'cancel') {
        return;
      }
      deleteLogs = userChoice == 'delete';
    }
    if (mounted) {
      setState(() {
        _isUpdating = true;
        _binaryCompletionOverride = completed;
      });
    }

    try {
      if (completed) {
        // Play completion sound
        SoundHelper().playCompletionSound();

        // If treating as binary, set currentValue/accumulatedTime
        dynamic targetValue = 1;
        int? targetAccumulatedTime;
        if (widget.instance.templateTrackingType == 'quantitative') {
          if (widget.treatAsBinary) {
            // NEW: A tick in the routine is equivalent to a single increment
            final current = _currentProgressLocal();
            targetValue = current + 1;
          } else {
            // Full target for other views
            targetValue = widget.instance.templateTarget ?? 1;
          }
        } else if (widget.instance.templateTrackingType == 'time') {
          // target is in minutes, accumulatedTime is in milliseconds
          final targetMinutes = widget.instance.templateTarget ?? 1;
          targetAccumulatedTime = (targetMinutes * 60000).toInt();
          targetValue = targetAccumulatedTime;
        }

        // Service methods will broadcast optimistically
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: widget.instance.reference.id,
          currentValue: targetValue,
          referenceTime: widget.progressReferenceTime,
        );
        await ActivityInstanceService.completeInstance(
          instanceId: widget.instance.reference.id,
          finalAccumulatedTime: targetAccumulatedTime,
        );
      } else {
        // Play completion sound for uncompletion too
        SoundHelper().playCompletionSound();

        // If treating as binary and qty, decrement by 1 to undo the routine step
        dynamic undoValue = 0;
        if (widget.treatAsBinary &&
            widget.instance.templateTrackingType == 'quantitative') {
          final current = _currentProgressLocal();
          undoValue = (current - 1).clamp(0, double.infinity);
        }

        // Service methods will broadcast optimistically
        await ActivityInstanceService.updateInstanceProgress(
          instanceId: widget.instance.reference.id,
          currentValue: undoValue,
          referenceTime: widget.progressReferenceTime,
        );
        await ActivityInstanceService.uncompleteInstance(
          instanceId: widget.instance.reference.id,
          deleteLogs: deleteLogs,
        );
      }
      // Reconciliation happens automatically via service method broadcasts
      // For habits, trigger a full refresh to fetch the newly generated instance
      if (widget.instance.templateCategoryType == 'habit' && completed) {
        widget.onRefresh?.call();
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      widget.onInstanceUpdated?.call(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      // Revert optimistic state on error
      widget.onInstanceUpdated?.call(widget.instance);
      if (mounted) {
        setState(() {
          _binaryCompletionOverride = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating completion: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _toggleTimer() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
    });
    try {
      final wasActive = _isTimerActiveLocal;
      final newTimerState = !wasActive;
      // Set optimistic state immediately for local UI
      setState(() => _timerStateOverride = newTimerState);

      // Service method will broadcast optimistically
      await ActivityInstanceService.toggleInstanceTimer(
        instanceId: widget.instance.reference.id,
      );

      // Get the updated instance data for TimerManager integration
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      // Integrate with TimerManager for floating timer
      if (!wasActive) {
        // Timer was started - play sound and add to TimerManager
        SoundHelper().playPlayButtonSound();
        TimerManager().startInstance(updatedInstance);
      } else {
        // Timer was stopped - play sound and remove from TimerManager
        SoundHelper().playStopButtonSound();
        TimerManager().stopInstance(updatedInstance);
        // Only check completion if target is set and met
        if (TimerLogicHelper.hasMetTarget(updatedInstance)) {
          await _checkTimerCompletion(updatedInstance);
        }
      }
      // Reconciliation happens automatically via service method broadcasts
    } catch (e) {
      // Revert optimistic state on error
      setState(() => _timerStateOverride = null);
      widget.onInstanceUpdated?.call(widget.instance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling timer: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _checkTimerCompletion(ActivityInstanceRecord instance) async {
    if (instance.templateTrackingType != 'time') return;
    final target = instance.templateTarget ?? 0;
    if (target == 0) return; // No target set
    // Use the instance's accumulatedTime (already updated by stop)
    final accumulated = instance.accumulatedTime;
    // Convert target to int for comparison (target is in minutes, accumulated is in milliseconds)
    final targetMs = (target * 60000).toInt();
    // Only complete if target is met or exceeded
    if (accumulated >= targetMs) {
      try {
        await ActivityInstanceService.completeInstance(
          instanceId: instance.reference.id,
          finalAccumulatedTime: accumulated,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task completed! Target reached.')),
          );
        }
        // Get updated instance and call callback for immediate UI update
        final completedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id,
        );
        widget.onInstanceUpdated?.call(completedInstance);
      } catch (e) {
        // Log error but don't fail - instance update callback is non-critical
        print('Error updating instance in item component: $e');
      }
    }
  }

  num _getTargetValue() {
    return widget.instance.templateTarget ?? 0;
  }

  Future<void> _showQuantControlsMenu(
      BuildContext anchorContext, bool canDecrement) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    // Calculate remaining quantity needed to complete
    final current = _currentProgressLocal();
    final target = _getTargetValue();
    final remaining = target - current;
    final canMarkComplete = remaining > 0;
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reset',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('Reset to Zero')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
          value: 'inc',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Increase by 1')
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dec',
          enabled: canDecrement,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.remove, size: 18),
              SizedBox(width: 8),
              Text('Decrease by 1')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'complete',
          enabled: canMarkComplete,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18),
              const SizedBox(width: 8),
              Text('Mark as Complete${canMarkComplete ? ' (+$remaining)' : ''}')
            ],
          ),
        ),
      ],
    );
    if (selected == null) return;
    if (selected == 'reset') {
      await _resetQuantity();
    } else if (selected == 'inc') {
      await _updateProgress(1);
    } else if (selected == 'dec' && canDecrement) {
      await _updateProgress(-1);
    } else if (selected == 'complete' && canMarkComplete) {
      await _updateProgress(remaining.toInt());
    }
  }

  Future<void> _showTimeControlsMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    // Calculate remaining time needed to complete
    final realTimeAccumulated =
        TimerLogicHelper.getRealTimeAccumulated(widget.instance);
    final target = widget.instance.templateTarget ?? 0;
    final targetMs = target * 60000; // Convert minutes to milliseconds
    final remainingMs = targetMs - realTimeAccumulated;
    // Enable mark complete if: (target > 0 AND remaining > 0) OR (target == 0 AND accumulated > 0)
    final canMarkComplete = (target > 0 && remainingMs > 0) ||
        (target == 0 && realTimeAccumulated > 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'reset',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('Reset Timer')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
          value: 'custom',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('Set Custom Time')
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'complete',
          enabled: canMarkComplete,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18),
              const SizedBox(width: 8),
              Text(
                  'Mark as Complete${canMarkComplete ? (target > 0 ? ' (+${_formatRemainingTime(remainingMs)})' : ' (${_formatTimeFromMs(realTimeAccumulated)})') : ''}')
            ],
          ),
        ),
      ],
    );
    if (selected == null) return;
    if (selected == 'reset') {
      await _resetTimer();
    } else if (selected == 'custom') {
      await _showCustomTimeDialog();
    } else if (selected == 'complete' && canMarkComplete) {
      await _markTimerComplete();
    }
  }

  String _formatRemainingTime(int remainingMs) {
    final totalSeconds = remainingMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatTimeFromMs(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  Future<void> _resetTimer() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
    });
    try {
      // Get current instance to check status
      final instance = widget.instance;

      // Reset timer - use direct update for now since updateInstanceProgress
      // doesn't handle timer-specific fields. The uncompleteInstance call below
      // will handle optimistic broadcast if needed.
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(currentUserUid)
              .doc(widget.instance.reference.id);
      await instanceRef.update({
        'accumulatedTime': 0,
        'totalTimeLogged': 0,
        'timeLogSessions': [],
        'currentSessionStartTime': null,
        'isTimerActive': false,
        'timerStartTime': null,
        'lastUpdated': DateTime.now(),
      });

      // If the item was completed or skipped based on timer, uncomplete it
      if (instance.status == 'completed' || instance.status == 'skipped') {
        // Check if timer was the only progress (for time-based tracking)
        if (instance.templateTrackingType == 'time') {
          // Auto-delete logs when resetting timer (silent deletion, no dialog)
          // uncompleteInstance will broadcast optimistically
          await ActivityInstanceService.uncompleteInstance(
            instanceId: widget.instance.reference.id,
            deleteLogs: true, // Automatically delete logs when timer is reset
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer reset to 0')),
        );
      }
    } catch (e) {
      // Revert optimistic state on error
      widget.onInstanceUpdated?.call(widget.instance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting timer: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _resetQuantity() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
      // Clear optimistic state override
      _quantProgressOverride = null;
    });
    try {
      // Get current instance to check status
      final instance = widget.instance;

      // Reset quantity using service method (will broadcast optimistically)
      await ActivityInstanceService.updateInstanceProgress(
        instanceId: widget.instance.reference.id,
        currentValue: 0,
        referenceTime: widget.progressReferenceTime,
      );

      // If the item was completed or skipped based on quantity, uncomplete it
      if (instance.status == 'completed' || instance.status == 'skipped') {
        // Check if quantity was the only progress (for quantitative tracking)
        if (instance.templateTrackingType == 'quantitative') {
          // Check if instance has calendar logs before uncompleting
          bool deleteLogs = false;
          if (instance.timeLogSessions.isNotEmpty) {
            final userChoice = await _showUncompleteDialog();
            if (userChoice == null || userChoice == 'cancel') {
              // User cancelled, abort uncomplete
              if (mounted) {
                setState(() {
                  _isUpdating = false;
                });
              }
              return;
            }
            deleteLogs = userChoice == 'delete';
          }

          // uncompleteInstance will broadcast optimistically
          await ActivityInstanceService.uncompleteInstance(
            instanceId: widget.instance.reference.id,
            deleteLogs: deleteLogs,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantity reset to 0')),
        );
      }
    } catch (e) {
      // Revert optimistic state on error
      widget.onInstanceUpdated?.call(widget.instance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting quantity: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _markTimerComplete() async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
    });
    try {
      // Step 1: Stop any active timer session first
      if (widget.instance.isTimeLogging &&
          widget.instance.currentSessionStartTime != null) {
        await TaskInstanceService.stopTimeLogging(
          activityInstanceRef: widget.instance.reference,
          markComplete: false, // Don't mark complete yet, just stop the session
        );
      }

      // Step 2: Get fresh instance data after stopping timer
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Step 3: Get target amount for completion
      final target = updatedInstance.templateTarget ?? 0;
      int newAccumulatedTime;

      // Step 4: Handle completion based on whether target exists
      if (target == 0) {
        // No target set: use accumulated time as target
        final realTimeAccumulated =
            TimerLogicHelper.getRealTimeAccumulated(updatedInstance);
        if (realTimeAccumulated <= 0) {
          throw Exception('No time recorded to complete task');
        }
        newAccumulatedTime = realTimeAccumulated;

        // Convert accumulated time to minutes for target
        final targetInMinutes = realTimeAccumulated ~/ 60000;

        // Update instance's templateTarget
        final instanceRef =
            ActivityInstanceRecord.collectionForUser(currentUserUid)
                .doc(updatedInstance.reference.id);
        await instanceRef.update({
          'templateTarget': targetInMinutes,
          'lastUpdated': DateTime.now(),
        });

        // Update template's target
        final templateRef = ActivityRecord.collectionForUser(currentUserUid)
            .doc(updatedInstance.templateId);
        await templateRef.update({
          'target': targetInMinutes,
          'lastUpdated': DateTime.now(),
        });
      } else {
        // Target exists: use target amount (ensures 100% progress)
        final targetMs = target * 60000; // Convert minutes to milliseconds
        newAccumulatedTime = targetMs.toInt();
      }

      // Step 5: Create a time log session with the full target duration
      // This ensures the calendar shows the complete 3 hours, not just the timer duration
      final completionTime = DateTime.now();
      final stackedTimes =
          await ActivityInstanceService.calculateStackedStartTime(
        userId: currentUserUid,
        completionTime: completionTime,
        durationMs: newAccumulatedTime,
        instanceId: updatedInstance.reference.id,
      );

      // Get fresh instance to check existing sessions
      final instanceBeforeSession =
          await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Create new session with full target duration
      final newSession = {
        'startTime': stackedTimes.startTime,
        'endTime': stackedTimes.endTime,
        'durationMilliseconds': newAccumulatedTime,
      };

      // Add to existing sessions (or replace if we want to use only the completion session)
      final existingSessions = List<Map<String, dynamic>>.from(
          instanceBeforeSession.timeLogSessions);

      // For timer tasks marked as complete, we want to show the full target duration
      // So we'll add a new session with the full duration
      // This ensures the calendar displays the complete time, not just partial timer sessions
      existingSessions.add(newSession);

      // Calculate total time across all sessions
      final totalTime = existingSessions.fold<int>(
        0,
        (sum, session) => sum + (session['durationMilliseconds'] as int? ?? 0),
      );

      // Update instance with the new session before completing
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(currentUserUid)
              .doc(updatedInstance.reference.id);

      // Only set currentValue to MS for time-based tracking.
      // For all non-time tasks, currentValue should NOT store time data.
      final Map<String, dynamic> updateData = {
        'timeLogSessions': existingSessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': newAccumulatedTime,
        'lastUpdated': DateTime.now(),
      };

      if (updatedInstance.templateTrackingType == 'time') {
        updateData['currentValue'] = newAccumulatedTime;
      } else if (updatedInstance.templateTrackingType == 'binary') {
        // For binary habits, ensure it's marked as 1 when completing
        updateData['currentValue'] = 1;
      }
      // For quantitative, we leave currentValue as is (user's count)

      await instanceRef.update(updateData);

      // Step 6: Complete with the determined accumulated time
      // completeInstance will broadcast optimistically
      await ActivityInstanceService.completeInstance(
        instanceId: widget.instance.reference.id,
        finalValue: updatedInstance.templateTrackingType == 'time'
            ? newAccumulatedTime
            : (updatedInstance.templateTrackingType == 'binary'
                ? 1
                : updatedInstance.currentValue),
        finalAccumulatedTime: newAccumulatedTime,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Task completed! Remaining time added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing task: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _showCustomTimeDialog() async {
    // Get current accumulated time
    final realTimeAccumulated =
        TimerLogicHelper.getRealTimeAccumulated(widget.instance);
    final currentHours = realTimeAccumulated ~/ 3600000;
    final currentMinutes = (realTimeAccumulated % 3600000) ~/ 60000;
    final target = widget.instance.templateTarget ?? 0;
    final targetHours = target ~/ 60;
    final targetMinutes = (target % 60).toInt();

    // Initialize controllers with current values
    final hoursController = TextEditingController(
        text: currentHours > 0 ? currentHours.toString() : '');
    final minutesController = TextEditingController(
        text: currentMinutes > 0 ? currentMinutes.toString() : '0');

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Custom Time'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (target > 0) ...[
              Text(
                'Target: ${targetHours > 0 ? '${targetHours}h ' : ''}${targetMinutes}m',
                style: FlutterFlowTheme.of(context).bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Current: ${_formatTimeFromMs(realTimeAccumulated)}',
              style: FlutterFlowTheme.of(context).bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: hoursController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final hours = int.tryParse(hoursController.text) ?? 0;
              final minutes = int.tryParse(minutesController.text) ?? 0;
              if (hours < 0 || minutes < 0 || minutes >= 60) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Invalid input. Hours must be >= 0, minutes must be 0-59')),
                );
                return;
              }
              Navigator.of(context).pop({'hours': hours, 'minutes': minutes});
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    hoursController.dispose();
    minutesController.dispose();

    if (result != null) {
      await _setCustomTime(result['hours'] ?? 0, result['minutes'] ?? 0);
    }
  }

  Future<void> _setCustomTime(int hours, int minutes) async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
    });
    try {
      // Step 1: Stop any active timer session first
      if (widget.instance.isTimeLogging &&
          widget.instance.currentSessionStartTime != null) {
        await TaskInstanceService.stopTimeLogging(
          activityInstanceRef: widget.instance.reference,
          markComplete: false, // Don't mark complete yet, just stop the session
        );
      }

      // Step 2: Get fresh instance data after stopping timer
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Step 3: Convert hours and minutes to milliseconds
      final customTimeMs = (hours * 3600000) + (minutes * 60000);

      // Step 4: Update accumulated time and current value
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(currentUserUid)
              .doc(widget.instance.reference.id);

      final Map<String, dynamic> updateData = {
        'accumulatedTime': customTimeMs,
        'totalTimeLogged': customTimeMs,
        'lastUpdated': DateTime.now(),
      };

      // Only set currentValue to MS for time-based tracking.
      // For all non-time tasks, currentValue should NOT store time data.
      if (updatedInstance.templateTrackingType == 'time') {
        updateData['currentValue'] = customTimeMs;
      }

      await instanceRef.update(updateData);

      // Step 5: Check if target is met and optionally complete
      final target = updatedInstance.templateTarget ?? 0;
      final targetMs = target * 60000;
      final shouldComplete = target > 0 && customTimeMs >= targetMs;

      if (shouldComplete && updatedInstance.status != 'completed') {
        await ActivityInstanceService.completeInstance(
          instanceId: widget.instance.reference.id,
          finalValue: updatedInstance.templateTrackingType == 'time'
              ? customTimeMs
              : (updatedInstance.templateTrackingType == 'binary'
                  ? 1
                  : updatedInstance.currentValue),
          finalAccumulatedTime: customTimeMs,
        );
      } else if (!shouldComplete &&
          (updatedInstance.status == 'completed' ||
              updatedInstance.status == 'skipped')) {
        // If custom time is less than target and was previously completed, uncomplete it
        // Check if instance has calendar logs before uncompleting
        bool deleteLogs = false;
        if (updatedInstance.timeLogSessions.isNotEmpty) {
          final userChoice = await _showUncompleteDialog();
          if (userChoice == null || userChoice == 'cancel') {
            // User cancelled, abort uncomplete
            // Revert the time update
            await instanceRef.update({
              'accumulatedTime': updatedInstance.accumulatedTime,
              'currentValue': updatedInstance.currentValue,
              'totalTimeLogged': updatedInstance.totalTimeLogged,
              'lastUpdated': DateTime.now(),
            });
            if (mounted) {
              setState(() {
                _isUpdating = false;
              });
            }
            return;
          }
          deleteLogs = userChoice == 'delete';
        }

        await ActivityInstanceService.uncompleteInstance(
          instanceId: widget.instance.reference.id,
          deleteLogs: deleteLogs,
        );
      }

      // Get the final updated instance data
      final finalInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );
      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(finalInstance);
      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(finalInstance);
      if (mounted) {
        final timeDisplay = hours > 0
            ? '${hours}h ${minutes}m'
            : minutes > 0
                ? '${minutes}m'
                : '0m';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Time set to $timeDisplay')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting custom time: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Handle skip for habits with partial progress
  Future<void> _handleHabitSkipRest() async {
    _applyOptimisticSkip();
    try {
      // Mark as skipped but preserve currentValue for points calculation
      await ActivityInstanceService.skipInstance(
        instanceId: widget.instance.reference.id,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habit skipped (progress preserved)')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error skipping habit: $e')),
        );
      }
    }
  }

  /// Show date picker for snooze
  Future<void> _handleSnooze() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // For both habits and recurring tasks, limit snooze date to window end date
      DateTime maxDate;
      if (widget.instance.windowEndDate != null) {
        maxDate = widget.instance.windowEndDate!;
      } else {
        // For one-time tasks, allow up to 1 year in the future
        maxDate = today.add(const Duration(days: 365));
      }
      final picked = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: maxDate,
      );
      if (picked != null) {
        _applyOptimisticSnooze(picked);
        await ActivityInstanceService.snoozeInstance(
          instanceId: widget.instance.reference.id,
          snoozeUntil: picked,
        );
        final label = DateFormat('EEE, MMM d').format(picked);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Snoozed until $label')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error snoozing: $e')),
        );
      }
    }
  }

  /// Snooze instance for today only (until tomorrow)
  Future<void> _handleSnoozeForToday() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      _applyOptimisticSnooze(tomorrow);
      await ActivityInstanceService.snoozeInstance(
        instanceId: widget.instance.reference.id,
        snoozeUntil: tomorrow,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snoozed until tomorrow')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error snoozing for today: $e')),
        );
      }
    }
  }

  /// Unsnooze instance
  Future<void> _handleBringBack() async {
    try {
      _applyOptimisticUnsnooze();
      await ActivityInstanceService.unsnoozeInstance(
        instanceId: widget.instance.reference.id,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brought back to queue')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error bringing back: $e')),
        );
      }
    }
  }

  /// Start timer from swipe action - navigate to timer page with pre-filled data
  Future<void> _startTimerFromSwipe(BuildContext context) async {
    try {
      // Navigate to timer page with task data pre-filled
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

/// Custom painter for creating a dotted vertical line (for Habits)
class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const double dashHeight = 3.5; // Slightly shorter dashes
    const double dashSpace = 5.5; // Increased spacing for more visible gaps
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(1.5, startY),
        Offset(1.5, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for creating a double vertical line (for Essentials)
class _DoubleLinePainter extends CustomPainter {
  final Color color;

  _DoubleLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    const double lineSpacing = 1.5; // Space between the two lines
    const double leftLineX = 0.5; // Left line position
    const double rightLineX =
        leftLineX + lineSpacing + 2.0; // Right line position

    // Draw two parallel vertical lines
    canvas.drawLine(
      Offset(leftLineX, 0),
      Offset(leftLineX, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(rightLineX, 0),
      Offset(rightLineX, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
