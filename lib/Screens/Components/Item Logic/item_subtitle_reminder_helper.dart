import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/timer_logic_helper.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:intl/intl.dart';

class ItemSubtitleReminderHelper {

  // EXACT copy of your _formatTimeFromMs logic
  static String formatTimeFromMs(int milliseconds) {
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

  // EXACT copy of your _getTemplateTargetMinutes logic
  static int getTemplateTargetMinutes(ActivityInstanceRecord instance) {
    final targetValue = instance.templateTarget;
    if (targetValue == null) return 0;
    if (targetValue is num) return targetValue.toInt();
    if (targetValue is String) {
      return int.tryParse(targetValue) ?? 0;
    }
    return 0;
  }

  // EXACT copy of your _getProgressDisplayText logic
  static String getProgressDisplayText({
    required ActivityInstanceRecord instance,
    required num Function() currentProgressLocal,
    required String Function() getTimerDisplayWithSeconds,
  }) {
    switch (instance.templateTrackingType) {
      case 'binary':
        return '';
      case 'quantitative':
        final progress = currentProgressLocal();
        final target = instance.templateTarget;
        return '$progress/$target ${instance.templateUnit}';
      case 'time':
        final target = getTemplateTargetMinutes(instance);
        final currentTime = getTimerDisplayWithSeconds();
        if (instance.status == 'completed') {
          final targetFormatted = TimerLogicHelper.formatTargetTime(target);
          final actualTimeMs = TimerLogicHelper.getRealTimeAccumulated(instance);
          final targetTimeMs = target * 60000;
          final maxTimeMs = actualTimeMs > targetTimeMs ? actualTimeMs : targetTimeMs;
          final maxTimeFormatted = formatTimeFromMs(maxTimeMs);
          return '$maxTimeFormatted / $targetFormatted';
        }
        if (target == 0) {
          return '$currentTime / -';
        }
        final targetFormatted = TimerLogicHelper.formatTargetTime(target);
        return '$currentTime / $targetFormatted';
      default:
        return '';
    }
  }

  // EXACT copy of your _isQueuePageSubtitle logic
  static bool isQueuePageSubtitle(String subtitle, ActivityInstanceRecord instance) {
    final categoryName = instance.templateCategoryName;
    if (categoryName.isEmpty) return false;
    return subtitle.contains(' • $categoryName') ||
        subtitle.contains('$categoryName •') ||
        subtitle.startsWith('$categoryName ') ||
        subtitle == categoryName;
  }

  // EXACT copy of your _removeCategoryNameFromSubtitle logic
  static String removeCategoryNameFromSubtitle(String subtitle, ActivityInstanceRecord instance) {
    final categoryName = instance.templateCategoryName;
    if (categoryName.isEmpty) return subtitle;
    if (subtitle.startsWith('$categoryName ')) {
      final remaining = subtitle.substring(categoryName.length).trim();
      if (remaining.startsWith('@')) {
        return remaining;
      }
      return remaining.isEmpty ? '' : remaining;
    }
    if (subtitle == categoryName) {
      return '';
    }
    if (subtitle.contains(' • $categoryName • ')) {
      return subtitle.replaceAll(' • $categoryName • ', ' • ');
    }
    if (subtitle.contains(' • $categoryName')) {
      return subtitle.replaceAll(' • $categoryName', '');
    }
    if (subtitle.endsWith(' • $categoryName')) {
      return subtitle.substring(0, subtitle.length - categoryName.length - 3).trim();
    }
    return subtitle;
  }

  // EXACT copy of your _addDueTimeToSubtitle logic
  static String addDueTimeToSubtitle({
    required String subtitle,
    required ActivityInstanceRecord instance,
    required bool isEssential,
  }) {
    if (subtitle.contains('@')) {
      return subtitle; // Already has time, don't add
    }
    String? dueTimeStr;
    if (instance.hasDueTime()) {
      dueTimeStr = TimeUtils.formatTimeForDisplay(instance.dueTime);
    } else if (instance.hasTemplateDueTime()) {
      dueTimeStr =
          TimeUtils.formatTimeForDisplay(instance.templateDueTime);
    }

    final bool hasDueTime = dueTimeStr != null && dueTimeStr.isNotEmpty;
    final timeSuffix = hasDueTime ? ' @ $dueTimeStr' : '';
    if (instance.dueDate == null || isEssential) {
      return subtitle; // No due date, can't add time
    }
    final datePatterns = [
      RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\b', caseSensitive: false), // Matches "Dec 10" or "Dec 10, 2024"
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
    if (!hasDate && instance.dueDate != null) {
      final dueDate = instance.dueDate!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
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
      final dateEndIndex = subtitle.indexOf(' •');
      if (dateEndIndex > 0) {
        return '${subtitle.substring(0, dateEndIndex)}$timeSuffix${subtitle.substring(dateEndIndex)}';
      } else {
        return '$subtitle$timeSuffix';
      }
    }

    if (instance.dueDate != null && !hasDate) {
      final dueDate = instance.dueDate!;
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
        dateStr = DateFormat.MMMd().format(dueDate); // "Dec 10"
      }

      final dateWithOptionalTime = '$dateStr$timeSuffix';
      if (subtitle.isEmpty) {
        return dateWithOptionalTime;
      } else {
        return '$dateWithOptionalTime • $subtitle';
      }
    }

    return subtitle;
  }

  // EXACT copy of your _getEnhancedSubtitle logic
  static String getEnhancedSubtitle({
    required String? baseSubtitle,
    required String? page,
    required ActivityInstanceRecord instance,
    required num Function() currentProgressLocal,
    required String Function() getTimerDisplayWithSeconds,
    bool includeProgress = true,
  }) {
    final subtitle = baseSubtitle ?? '';
    final progressText = getProgressDisplayText(
      instance: instance,
      currentProgressLocal: currentProgressLocal,
      getTimerDisplayWithSeconds: getTimerDisplayWithSeconds,
    );
    String processedSubtitle = subtitle;
    if (page == 'queue' || isQueuePageSubtitle(subtitle, instance)) {
      processedSubtitle = removeCategoryNameFromSubtitle(subtitle, instance);
    }
    processedSubtitle = addDueTimeToSubtitle(
      subtitle: processedSubtitle,
      instance: instance,
      isEssential: instance.templateCategoryType == 'essential',
    );
    if (processedSubtitle.isEmpty && progressText.isEmpty) {
      return '';
    }
    if (processedSubtitle.isEmpty) {
      return includeProgress ? progressText : '';
    }
    if (progressText.isEmpty) {
      return processedSubtitle;
    }
    if (includeProgress) {
      return '$processedSubtitle • $progressText';
    } else {
      return processedSubtitle;
    }
  }

  // EXACT copy of your _checkForReminders logic
  static Future<void> checkForReminders({
    required ActivityInstanceRecord instance,
    required bool Function() isMounted,
    required void Function(VoidCallback) setState,
    required Function(bool) setHasReminders,
    required Function(String?) setReminderDisplayText,
  }) async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        if (isMounted()) {
          setState(() {
            setHasReminders(false);
          });
        }
        return;
      }

      final templateRef = ActivityRecord.collectionForUser(userId)
          .doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (!templateDoc.exists) {
        if (isMounted()) {
          setState(() {
            setHasReminders(false);
          });
        }
        return;
      }

      final template = ActivityRecord.fromSnapshot(templateDoc);

      final hasDueTime = instance.hasDueTime() || instance.hasTemplateDueTime();

      bool hasReminders = false;
      String? reminderDisplayText;
      if (template.hasReminders()) {
        final reminders = ReminderConfigList.fromMapList(template.reminders);
        hasReminders = reminders.any((reminder) => reminder.enabled);
        if (hasReminders) {
          final List<String> reminderTexts = [];
          final fixedTimeReminders = reminders.where((r) => r.enabled && r.fixedTimeMinutes != null).toList();
          if (fixedTimeReminders.isNotEmpty) {
            final times = fixedTimeReminders.map((r) => TimeUtils.formatTimeOfDayForDisplay(r.time)).toList();
            reminderTexts.addAll(times);
          }
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

      if (isMounted()) {
        setState(() {
          setHasReminders(hasReminders);
          setReminderDisplayText(reminderDisplayText);
        });
      }
    } catch (e) {
      if (isMounted()) {
        setState(() {
          setHasReminders(false);
        });
      }
    }
  }
}