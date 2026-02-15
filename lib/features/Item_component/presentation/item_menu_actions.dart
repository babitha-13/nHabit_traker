import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/recurrence_calculator.dart';

class ItemMenuLogicHelper {
  // Utility to match your original _isSameDay
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _clampDateToRange(
    DateTime value,
    DateTime min,
    DateTime max,
  ) {
    final v = _dateOnly(value);
    final lo = _dateOnly(min);
    final hi = _dateOnly(max);
    if (v.isBefore(lo)) return lo;
    if (v.isAfter(hi)) return hi;
    return v;
  }

  static Future<void> updateTemplatePriority({
    required int newPriority,
    required ActivityInstanceRecord instance,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required BuildContext context,
  }) async {
    final previousInstance = instance;
    final optimisticInstance =
        InstanceEvents.createOptimisticPropertyUpdateInstance(
      previousInstance,
      {'templatePriority': newPriority},
    );
    onInstanceUpdated(optimisticInstance);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      await templateRef
          .update({'priority': newPriority, 'lastUpdated': DateTime.now()});
      final instanceRef = ActivityInstanceRecord.collectionForUser(uid)
          .doc(instance.reference.id);
      await instanceRef.update(
          {'templatePriority': newPriority, 'lastUpdated': DateTime.now()});
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id);
      onInstanceUpdated(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      onInstanceUpdated(previousInstance);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating priority: $e')));
      }
    }
  }

  static Future<void> showScheduleMenu({
    required BuildContext context,
    required BuildContext anchorContext,
    required ActivityInstanceRecord instance,
    required bool isRecurringItem,
    required num currentProgressLocal,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required Future<String?> Function() showUncompleteDialog,
  }) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);

    final isHabit = instance.templateCategoryType == 'habit';
    final isRecurringTask =
        instance.templateCategoryType == 'task' && isRecurringItem;
    final isSnoozed = instance.snoozedUntil != null &&
        DateTime.now().isBefore(instance.snoozedUntil!);
    final menuItems = <PopupMenuEntry<String>>[];

    if (isHabit) {
      final isSkipped = instance.status == 'skipped';
      if (isSkipped) {
        menuItems.add(const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12))));
      } else if (isSnoozed) {
        menuItems.add(const PopupMenuItem<String>(
            value: 'bring_back',
            height: 32,
            child: Text('Unsnooze', style: TextStyle(fontSize: 12))));
      } else {
        final hasProgress = currentProgressLocal > 0;
        if (hasProgress) {
          menuItems.add(const PopupMenuItem<String>(
              value: 'skip_rest',
              height: 32,
              child: Text('Skip the rest', style: TextStyle(fontSize: 12))));
        } else {
          menuItems.add(const PopupMenuItem<String>(
              value: 'skip',
              height: 32,
              child: Text('Skip', style: TextStyle(fontSize: 12))));
        }
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final isLastDay = instance.windowEndDate != null &&
            DateTime(instance.windowEndDate!.year,
                    instance.windowEndDate!.month, instance.windowEndDate!.day)
                .isAtSameMomentAs(today);
        if (!isLastDay) {
          menuItems.add(const PopupMenuItem<String>(
              value: 'snooze_today',
              height: 32,
              child: Text('Snooze for today', style: TextStyle(fontSize: 12))));
        }
        menuItems.add(const PopupMenuItem<String>(
            value: 'snooze',
            height: 32,
            child: Text('Snooze until...', style: TextStyle(fontSize: 12))));
      }
    } else if (isRecurringTask) {
      final isSkipped = instance.status == 'skipped';
      if (isSkipped) {
        menuItems.add(const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12))));
      } else if (isSnoozed) {
        menuItems.add(const PopupMenuItem<String>(
            value: 'bring_back',
            height: 32,
            child: Text('Unsnooze', style: TextStyle(fontSize: 12))));
      } else {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final missingInstancesCount =
            ActivityInstanceService.calculateMissingInstancesFromInstance(
                instance: instance, today: today);
        final recurringTaskOptions = <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
              value: 'skip',
              height: 32,
              child:
                  Text('Skip this occurrence', style: TextStyle(fontSize: 12))),
        ];

        // Fetch template to check recurrence constraints
        bool canReschedule = false;
        ActivityRecord? template;
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            final templateDoc = await ActivityRecord.collectionForUser(uid)
                .doc(instance.templateId)
                .get();
            if (templateDoc.exists) {
              template = ActivityRecord.fromSnapshot(templateDoc);
              // Check if frequency is not daily (approximate check for "less than or equal to once in 2 days")
              // We treat "Daily" as everyXPeriod 'days' with value 1, OR specificDays with all days selected.
              bool isDaily = false;
              if (template.frequencyType == 'everyXPeriod' &&
                  template.periodType == 'days' &&
                  template.everyXValue == 1) {
                isDaily = true;
              } else if (template.frequencyType == 'specificDays' &&
                  template.specificDays.length >= 7) {
                isDaily = true;
              }
              canReschedule = !isDaily;
            }
          }
        } catch (e) {
          // If fetch fails, default to strict (false) or loose? Default to false for safety.
        }

        if (canReschedule) {
          final currentDueDate = instance.dueDate;
          // Reuse the logic from non-recurring block, but we need to duplicate the menu items creation
          // because the list order matters (Standard options first)

          final tomorrow = today.add(const Duration(days: 1));
          final isDueToday =
              currentDueDate != null && isSameDay(currentDueDate, today);
          final isDueTomorrow =
              currentDueDate != null && isSameDay(currentDueDate, tomorrow);

          // Insert at beginning
          if (!isDueToday) {
            recurringTaskOptions.insert(
                0,
                const PopupMenuItem<String>(
                    value: 'today',
                    height: 32,
                    child: Text('Schedule for today',
                        style: TextStyle(fontSize: 12))));
          }
          if (!isDueTomorrow) {
            int index = (!isDueToday) ? 1 : 0;
            recurringTaskOptions.insert(
                index,
                const PopupMenuItem<String>(
                    value: 'tomorrow',
                    height: 32,
                    child: Text('Schedule for tomorrow',
                        style: TextStyle(fontSize: 12))));
          }
          // Add pick date option
          int index = (!isDueToday ? 1 : 0) + (!isDueTomorrow ? 1 : 0);
          recurringTaskOptions.insert(
              index,
              const PopupMenuItem<String>(
                  value: 'pick_date',
                  height: 32,
                  child: Text('Pick due date...',
                      style: TextStyle(fontSize: 12))));
          recurringTaskOptions.insert(
              index + 1, const PopupMenuDivider(height: 6));
        }

        if (missingInstancesCount >= 2) {
          recurringTaskOptions.add(const PopupMenuItem<String>(
              value: 'skip_until_today',
              height: 32,
              child: Text('Skip all past occurrences',
                  style: TextStyle(fontSize: 12))));
        }
        recurringTaskOptions.addAll([
          const PopupMenuItem<String>(
              value: 'skip_until',
              height: 32,
              child: Text('Skip until...', style: TextStyle(fontSize: 12))),
        ]);
        menuItems.addAll(recurringTaskOptions);
      }
    } else {
      final isSkipped = instance.status == 'skipped';
      if (isSkipped) {
        menuItems.add(const PopupMenuItem<String>(
            value: 'unskip',
            height: 32,
            child: Text('Unskip', style: TextStyle(fontSize: 12))));
      } else {
        final currentDueDate = instance.dueDate;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final isDueToday =
            currentDueDate != null && isSameDay(currentDueDate, today);
        final isDueTomorrow =
            currentDueDate != null && isSameDay(currentDueDate, tomorrow);
        if (!isDueToday) {
          menuItems.add(const PopupMenuItem<String>(
              value: 'today',
              height: 32,
              child:
                  Text('Schedule for today', style: TextStyle(fontSize: 12))));
        }
        if (!isDueTomorrow) {
          menuItems.add(const PopupMenuItem<String>(
              value: 'tomorrow',
              height: 32,
              child: Text('Schedule for tomorrow',
                  style: TextStyle(fontSize: 12))));
        }
        menuItems.add(const PopupMenuItem<String>(
            value: 'pick_date',
            height: 32,
            child: Text('Pick due date...', style: TextStyle(fontSize: 12))));
        if (currentDueDate != null) {
          menuItems.addAll([
            const PopupMenuDivider(height: 6),
            const PopupMenuItem<String>(
                value: 'clear_due_date',
                height: 32,
                child: Text('Clear due date', style: TextStyle(fontSize: 12))),
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
          overlay.size.height - position.dy),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: FlutterFlowTheme.of(context).alternate)),
      items: menuItems,
    );
    if (selected != null) {
      await handleScheduleAction(
        action: selected,
        context: context,
        instance: instance,
        onInstanceUpdated: onInstanceUpdated,
        onRefresh: onRefresh,
        showUncompleteDialog: showUncompleteDialog,
      );
    }
  }

  // EXACT copy of your _handleScheduleAction logic
  static Future<void> handleScheduleAction({
    required String action,
    required BuildContext context,
    required ActivityInstanceRecord instance,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Future<void> Function()? onRefresh,
    required Future<String?> Function() showUncompleteDialog,
  }) async {
    final previousInstance = instance;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      switch (action) {
        case 'unskip':
          onInstanceUpdated(
              InstanceEvents.createOptimisticUncompletedInstance(instance));
          await _handleUnskip(context, instance, showUncompleteDialog);
          break;
        case 'skip':
          onInstanceUpdated(
              InstanceEvents.createOptimisticSkippedInstance(instance));
          await ActivityInstanceService.skipInstance(
              instanceId: instance.reference.id);

          break;
        case 'skip_until_today':
          onInstanceUpdated(
              InstanceEvents.createOptimisticSkippedInstance(instance));
          await ActivityInstanceService.skipInstancesUntil(
              templateId: instance.templateId, untilDate: today);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Skipped all past occurrences')));
          break;
        case 'skip_until':
          final picked = await showDatePicker(
              context: context,
              initialDate: tomorrow,
              firstDate: today,
              lastDate: today.add(const Duration(days: 365 * 5)));
          if (picked != null) {
            onInstanceUpdated(
                InstanceEvents.createOptimisticSkippedInstance(instance));
            await ActivityInstanceService.skipInstancesUntil(
                templateId: instance.templateId, untilDate: picked);
          }
          break;
        case 'today':
          onInstanceUpdated(InstanceEvents.createOptimisticRescheduledInstance(
              instance,
              newDueDate: today,
              newDueTime: instance.dueTime));
          await ActivityInstanceService.rescheduleInstance(
              instanceId: instance.reference.id, newDueDate: today);
          break;
        case 'tomorrow':
          onInstanceUpdated(InstanceEvents.createOptimisticRescheduledInstance(
              instance,
              newDueDate: tomorrow,
              newDueTime: instance.dueTime));
          await ActivityInstanceService.rescheduleInstance(
              instanceId: instance.reference.id, newDueDate: tomorrow);
          break;
        case 'pick_date':
          DateTime lastDate = today.add(const Duration(days: 365 * 5));

          // For recurring tasks, limit the max date to be before the next occurrence
          if (instance.templateCategoryType == 'task' &&
              instance.templateIsRecurring) {
            try {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                final templateDoc = await ActivityRecord.collectionForUser(uid)
                    .doc(instance.templateId)
                    .get();
                if (templateDoc.exists) {
                  final template = ActivityRecord.fromSnapshot(templateDoc);
                  // Calculate next due date from ORIGINAL due date (or current if original not set)
                  final anchorDate =
                      instance.originalDueDate ?? instance.dueDate ?? today;
                  final nextDate = RecurrenceCalculator.calculateNextDueDate(
                    currentDueDate: anchorDate,
                    template: template,
                  );
                  if (nextDate != null) {
                    // Max date is the day before the next occurrence
                    final calculatedMax =
                        nextDate.subtract(const Duration(days: 1));
                    // Ensure it's not in the past relative to today
                    if (calculatedMax.isAfter(today)) {
                      lastDate = calculatedMax;
                    } else {
                      // If next valid date is tomorrow, and max is today, we can only pick today.
                      // If next valid is today (overlap), max is yesterday (invalid).
                      // Fallback to today or strict handling.
                      lastDate = today;
                    }
                  }
                }
              }
            } catch (e) {
              // Ignore error, use default max
            }
          }

          final firstDate = today;
          final safeLastDate =
              lastDate.isBefore(firstDate) ? firstDate : lastDate;
          final rawInitial = instance.dueDate ?? tomorrow;
          final initialDate =
              _clampDateToRange(rawInitial, firstDate, safeLastDate);
          final picked = await showDatePicker(
            context: context,
            initialDate: initialDate,
            firstDate: firstDate,
            lastDate: safeLastDate,
          );
          if (picked != null) {
            onInstanceUpdated(
                InstanceEvents.createOptimisticRescheduledInstance(instance,
                    newDueDate: picked, newDueTime: instance.dueTime));
            await ActivityInstanceService.rescheduleInstance(
                instanceId: instance.reference.id, newDueDate: picked);
          }
          break;
        case 'clear_due_date':
          onInstanceUpdated(
              InstanceEvents.createOptimisticPropertyUpdateInstance(
                  instance, {'dueDate': null, 'dueTime': null}));
          await ActivityInstanceService.removeDueDateFromInstance(
              instanceId: instance.reference.id);
          break;
        case 'skip_rest':
          onInstanceUpdated(
              InstanceEvents.createOptimisticSkippedInstance(instance));
          await _handleHabitSkipRest(context, instance);
          break;
        case 'snooze_today':
          await _handleSnoozeForToday(context, instance, onInstanceUpdated);
          break;
        case 'snooze':
          await _handleSnooze(context, instance, onInstanceUpdated);
          break;
        case 'bring_back':
          await _handleBringBack(context, instance, onInstanceUpdated);
          break;
      }
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
          instanceId: instance.reference.id);
      onInstanceUpdated(updatedInstance);
      InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      onInstanceUpdated(previousInstance);
      if (onRefresh != null) await onRefresh();
    }
  }

  // --- Internal Exact Handlers ---

  static Future<void> _handleUnskip(
      BuildContext context,
      ActivityInstanceRecord instance,
      Future<String?> Function() showUncompleteDialog) async {
    try {
      bool deleteLogs = false;
      if (instance.timeLogSessions.isNotEmpty) {
        final userChoice = await showUncompleteDialog();
        if (userChoice == null || userChoice == 'cancel') return;
        deleteLogs = userChoice == 'delete';
      }
      await ActivityInstanceService.uncompleteInstance(
          instanceId: instance.reference.id, deleteLogs: deleteLogs);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error unskipping: $e')));
      }
    }
  }

  static Future<void> _handleHabitSkipRest(
      BuildContext context, ActivityInstanceRecord instance) async {
    try {
      await ActivityInstanceService.skipInstance(
          instanceId: instance.reference.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error skipping habit: $e')));
      }
    }
  }

  static Future<void> _handleSnooze(
      BuildContext context,
      ActivityInstanceRecord instance,
      Function(ActivityInstanceRecord) onUpdate) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime maxDate =
          instance.windowEndDate ?? today.add(const Duration(days: 365));
      final picked = await showDatePicker(
          context: context,
          initialDate: today.add(const Duration(days: 1)),
          firstDate: today,
          lastDate: maxDate);
      if (picked != null) {
        onUpdate(InstanceEvents.createOptimisticSnoozedInstance(instance,
            snoozedUntil: picked));
        await ActivityInstanceService.snoozeInstance(
            instanceId: instance.reference.id, snoozeUntil: picked);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error snoozing: $e')));
      }
    }
  }

  static Future<void> _handleSnoozeForToday(
      BuildContext context,
      ActivityInstanceRecord instance,
      Function(ActivityInstanceRecord) onUpdate) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      onUpdate(InstanceEvents.createOptimisticSnoozedInstance(instance,
          snoozedUntil: tomorrow));
      await ActivityInstanceService.snoozeInstance(
          instanceId: instance.reference.id, snoozeUntil: tomorrow);
      // Do not show snackbar on success, only on failure.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error snoozing for today: $e')));
      }
    }
  }

  static Future<void> _handleBringBack(
      BuildContext context,
      ActivityInstanceRecord instance,
      Function(ActivityInstanceRecord) onUpdate) async {
    try {
      onUpdate(InstanceEvents.createOptimisticUnsnoozedInstance(instance));
      await ActivityInstanceService.unsnoozeInstance(
          instanceId: instance.reference.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error unsnoozing: $e')));
      }
    }
  }
}
