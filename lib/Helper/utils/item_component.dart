import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart'; // Keep for fetching template on edit
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Helper/utils/timer_logic_helper.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Edit%20Task/edit_task.dart';
import 'package:habit_tracker/Screens/createHabit/create_habit.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';

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
      this.page})
      : super(key: key);

  @override
  State<ItemComponent> createState() => _ItemComponentState();
}

class _ItemComponentState extends State<ItemComponent>
    with TickerProviderStateMixin {
  bool _isUpdating = false;
  Timer? _timer;
  num? _quantProgressOverride;
  bool? _timerStateOverride;

  @override
  void initState() {
    super.initState();
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

    // Reset timer state override when backend catches up
    if (widget.instance.templateTrackingType == 'time' &&
        _timerStateOverride != null) {
      if (widget.instance.isTimerActive == _timerStateOverride) {
        setState(() => _timerStateOverride = null);
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isCompleted {
    return widget.instance.status == 'completed';
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
    return widget.instance.isTimerActive;
  }

  num _currentProgressLocal() {
    // Use optimistic override if present
    if (widget.instance.templateTrackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      return _quantProgressOverride!;
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

  bool get _isFullyCompleted {
    return widget.instance.status == 'completed';
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
            onPressed: (context) {},
            backgroundColor: FlutterFlowTheme.of(context).primary,
            foregroundColor: Colors.white,
            icon: Icons.timer,
            label: 'Start Timer',
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            top: BorderSide(
              color: FlutterFlowTheme.of(context).surfaceBorderColor,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 6),
            IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: _leftStripeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  SizedBox(
                    width: 36,
                    child: Center(child: _buildLeftControlsCompact()),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Row(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Only show type icon if enabled
                            if (widget.showTypeIcon)
                              Icon(
                                widget.isHabit ? Icons.flag : Icons.assignment,
                                size: 16,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                            // Only show recurring icon if enabled and item is recurring
                            if (widget.showRecurringIcon && _isRecurringItem())
                              Icon(
                                Icons.repeat,
                                size: 16,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.instance.templateName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                        fontSize: 12,
                                      ),
                                ),
                              ]
                            ],
                          ),
                        ),
                        if (widget.instance.templateTrackingType !=
                            'binary') ...[
                          const SizedBox(width: 5),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context)
                                    .secondaryBackground,
                                border: Border.all(
                                  color: FlutterFlowTheme.of(context).alternate,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _getProgressDisplayText(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FlutterFlowTheme.of(context)
                                    .bodySmall
                                    .override(
                                      fontFamily: 'Readex Pro',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      lineHeight: 1.05,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 5),
                      _buildHabitPriorityStars(),
                      const SizedBox(width: 5),
                      Builder(
                        builder: (btnCtx) => GestureDetector(
                          onTap: () {
                            _showScheduleMenu(btnCtx);
                          },
                          child: const Icon(Icons.calendar_month, size: 20),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Builder(
                        builder: (btnCtx) => GestureDetector(
                          onTap: () {
                            _showHabitOverflowMenu(btnCtx);
                          },
                          child: const Icon(Icons.more_vert, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.instance.templateTrackingType != 'binary') ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Container(
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
              ),
            ] else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitPriorityStars() {
    final current = widget.instance.templatePriority;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            await _updateTemplatePriority(level);
          },
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

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Priority set to $newPriority star${newPriority > 1 ? 's' : ''}')),
      );

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating priority: $e')),
        );
      }
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
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      if (widget.showTaskEdit) {
        showDialog(
          context: context,
          builder: (_) => EditTask(
            task: template, // Pass the template here
            instance: widget.instance, // Pass the instance here
            categories: widget.categories ?? [],
            onSave: (updatedHabit) async {
              // Trigger refresh to show updated instances
              if (widget.onRefresh != null) {
                await widget.onRefresh!();
              }
            },
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => createActivityPage(habitToEdit: template),
          ),
        ).then((value) {
          if (value == true) {
            widget.onRefresh?.call();
          }
        });
      }
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
            // Call onInstanceDeleted for granular UI update
            widget.onInstanceDeleted?.call(widget.instance);

            // Broadcast the instance deletion event
            InstanceEvents.broadcastInstanceDeleted(widget.instance);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting activity: $e')),
            );
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
      if (isSnoozed) {
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
      if (isSnoozed) {
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
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      switch (action) {
        case 'skip':
          // Handle both regular skip and habit skip
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
          await ActivityInstanceService.rescheduleInstance(
            instanceId: widget.instance.reference.id,
            newDueDate: today,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled for today')),
          );
          break;

        case 'tomorrow':
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
          print(
              'DEBUG: Attempting to clear due date for instance: ${widget.instance.reference.id}');
          await ActivityInstanceService.removeDueDateFromInstance(
            instanceId: widget.instance.reference.id,
          );
          print('DEBUG: Due date cleared successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Due date cleared')),
          );
          break;

        case 'skip_rest':
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Color get _leftStripeColor {
    final hex = widget.categoryColorHex;
    if (hex != null && hex.isNotEmpty) {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return Colors.black;
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
        final target = widget.instance.templateTarget ?? 0;
        final targetFormatted = TimerLogicHelper.formatTargetTime(target);
        return '${_getTimerDisplayWithSeconds()} / $targetFormatted';
      default:
        return '';
    }
  }

  Widget _buildLeftControlsCompact() {
    // TODO: Phase 3 - Re-implement completion logic for each type
    switch (widget.instance.templateTrackingType) {
      case 'binary':
        return SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _isCompleted,
            onChanged: _isUpdating
                ? null
                : (value) async {
                    await _handleBinaryCompletion(value ?? false);
                  },
            activeColor: _impactLevelColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case 'quantitative':
        final current = _currentProgressLocal();
        final canDecrement = current > 0;
        return Builder(
          builder: (btnCtx) => GestureDetector(
            onLongPress: () => _showQuantControlsMenu(btnCtx, canDecrement),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).primaryText,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _isUpdating ? null : () => _updateProgress(1),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = _isTimerActiveLocal;
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive
                ? FlutterFlowTheme.of(context).error
                : FlutterFlowTheme.of(context).primaryText,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _isUpdating ? null : () => _toggleTimer(),
              onLongPress:
                  _isUpdating ? null : () => _showTimeControlsMenu(context),
              child: Icon(
                isActive ? Icons.stop : Icons.play_arrow,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _updateProgress(int delta) async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      final currentValue = _currentProgressLocal();
      final newValue = (currentValue + delta).clamp(0, double.infinity);

      // Set optimistic state immediately
      setState(() => _quantProgressOverride = newValue.toInt());

      await ActivityInstanceService.updateInstanceProgress(
        instanceId: widget.instance.reference.id,
        currentValue: newValue,
      );

      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      // Revert optimistic state on error
      setState(() => _quantProgressOverride = null);
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
  }

  Future<void> _handleBinaryCompletion(bool completed) async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      if (completed) {
        await ActivityInstanceService.completeInstance(
          instanceId: widget.instance.reference.id,
        );
      } else {
        await ActivityInstanceService.uncompleteInstance(
          instanceId: widget.instance.reference.id,
        );
      }

      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);

      // For habits, trigger a full refresh to fetch the newly generated instance
      if (widget.instance.templateCategoryType == 'habit' && completed) {
        widget.onRefresh?.call();
      }
    } catch (e) {
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

      // Set optimistic state immediately
      setState(() => _timerStateOverride = !wasActive);

      await ActivityInstanceService.toggleInstanceTimer(
        instanceId: widget.instance.reference.id,
      );

      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Integrate with TimerManager for floating timer
      if (!wasActive) {
        // Timer was started - add to TimerManager
        TimerManager().startInstance(updatedInstance);
      } else {
        // Timer was stopped - remove from TimerManager
        TimerManager().stopInstance(updatedInstance);

        // Only check completion if target is set and met
        if (TimerLogicHelper.hasMetTarget(updatedInstance)) {
          await _checkTimerCompletion(updatedInstance);
        }
      }

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      // Revert optimistic state on error
      setState(() => _timerStateOverride = null);
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

    // Only complete if target is met or exceeded
    if (accumulated >= target) {
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
        print('Error auto-completing timer task: $e');
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

    if (selected == 'inc') {
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
    final canMarkComplete = remainingMs > 0;

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
        PopupMenuItem<String>(
          value: 'complete',
          enabled: canMarkComplete,
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18),
              const SizedBox(width: 8),
              Text(
                  'Mark as Complete${canMarkComplete ? ' (+${_formatRemainingTime(remainingMs)})' : ''}')
            ],
          ),
        ),
      ],
    );

    if (selected == null) return;

    if (selected == 'reset') {
      await _resetTimer();
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

  Future<void> _resetTimer() async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      // Reset timer by updating the instance directly
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(currentUserUid)
              .doc(widget.instance.reference.id);
      await instanceRef.update({
        'accumulatedTime': 0,
        'isTimerActive': false,
        'timerStartTime': null,
        'lastUpdated': DateTime.now(),
      });

      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timer reset to 0')),
        );
      }
    } catch (e) {
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

  Future<void> _markTimerComplete() async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      // Calculate the remaining time needed to reach target
      final realTimeAccumulated =
          TimerLogicHelper.getRealTimeAccumulated(widget.instance);
      final target = widget.instance.templateTarget ?? 0;
      final targetMs = target * 60000; // Convert minutes to milliseconds
      final remainingMs = targetMs - realTimeAccumulated;

      // Add the remaining time to accumulated time
      final newAccumulatedTime = (realTimeAccumulated + remainingMs).toInt();

      // Complete the instance with the final accumulated time
      await ActivityInstanceService.completeInstance(
        instanceId: widget.instance.reference.id,
        finalAccumulatedTime: newAccumulatedTime,
      );

      // Get the updated instance data
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: widget.instance.reference.id,
      );

      // Call the instance update callback for real-time updates
      widget.onInstanceUpdated?.call(updatedInstance);

      // Broadcast the instance update event
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);

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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Handle skip for habits with partial progress
  Future<void> _handleHabitSkipRest() async {
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
}
