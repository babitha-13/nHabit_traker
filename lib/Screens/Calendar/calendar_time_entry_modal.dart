import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/Screens/Shared/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

/// Helper class for calendar modal dialogs
class CalendarModals {
  /// Show manual entry dialog
  static void showManualEntryDialog({
    required BuildContext context,
    required DateTime selectedDate,
    DateTime? startTime,
    DateTime? endTime,
    required Function(DateTime start, DateTime end, String type, Color? color)
        onPreviewChange,
    required VoidCallback onSave,
    required VoidCallback onRemovePreview,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return ManualTimeLogModal(
          selectedDate: selectedDate,
          initialStartTime: startTime,
          initialEndTime: endTime,
          onPreviewChange: onPreviewChange,
          onSave: onSave,
        );
      },
    ).whenComplete(() {
      onRemovePreview();
    });
  }

  /// Show edit entry dialog
  static Future<void> showEditEntryDialog({
    required BuildContext context,
    required CalendarEventMetadata metadata,
    required DateTime selectedDate,
    required Function(DateTime start, DateTime end, String type, Color? color)
        onPreviewChange,
    required VoidCallback onSave,
    required VoidCallback onRemovePreview,
  }) async {
    try {
      final instance = await ActivityInstanceRecord.getDocumentOnce(
        ActivityInstanceRecord.collectionForUser(currentUserUid)
            .doc(metadata.instanceId),
      );

      if (instance.timeLogSessions.isEmpty ||
          metadata.sessionIndex >= instance.timeLogSessions.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session not found')),
        );
        return;
      }

      final session = instance.timeLogSessions[metadata.sessionIndex];
      final sessionStart = session['startTime'] as DateTime;
      final sessionEnd = session['endTime'] as DateTime?;

      if (sessionEnd == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session is not completed')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return ManualTimeLogModal(
            selectedDate: selectedDate,
            initialStartTime: sessionStart,
            initialEndTime: sessionEnd,
            onPreviewChange: onPreviewChange,
            onSave: onSave,
            editMetadata: metadata,
          );
        },
      ).whenComplete(() {
        onRemovePreview();
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading session: $e')),
        );
      }
    }
  }

  /// Handle preview change with scroll adjustment
  static void handlePreviewChange({
    required DateTime start,
    required DateTime end,
    required String type,
    Color? color,
    required DateTime selectedDate,
    required int defaultDurationMinutes,
    required EventController plannedEventController,
    required GlobalKey<DayViewState> dayViewKey,
    required double currentScrollOffset,
    required double Function() calculateHeightPerMinute,
    required BuildContext context,
  }) {
    final selectedDateStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      0,
      0,
      0,
    );
    final selectedDateEnd = selectedDateStart.add(const Duration(days: 1));
    var validStartTime = start;
    var validEndTime = end;

    if (validStartTime.isBefore(selectedDateStart)) {
      validStartTime = selectedDateStart;
    } else if (validStartTime.isAfter(selectedDateEnd) ||
        validStartTime.isAtSameMomentAs(selectedDateEnd)) {
      validStartTime = selectedDateEnd.subtract(const Duration(seconds: 1));
    }
    if (validEndTime.isAfter(selectedDateEnd)) {
      validEndTime = selectedDateEnd.subtract(const Duration(seconds: 1));
    }
    if (validEndTime.isBefore(validStartTime) ||
        validEndTime.isAtSameMomentAs(validStartTime)) {
      validEndTime =
          validStartTime.add(Duration(minutes: defaultDurationMinutes));
    }
    final startDateOnly = DateTime(
      validStartTime.year,
      validStartTime.month,
      validStartTime.day,
    );
    final selectedDateOnly = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    if (!startDateOnly.isAtSameMomentAs(selectedDateOnly)) {
      return;
    }
    Color previewColor = color ?? Colors.grey.withOpacity(0.5);
    String title = "New Entry";
    if (type == 'habit') title = "New Habit";
    if (type == 'task') title = "New Task";
    if (type == 'essential') title = "essential";

    final previewEvent = CalendarEventData(
      date: selectedDate,
      startTime: validStartTime,
      endTime: validEndTime,
      title: title,
      description: "Preview",
      color: previewColor,
      event: "preview_id",
    );
    plannedEventController.add(previewEvent);

    if (dayViewKey.currentState != null) {
      final minutesFromMidnight = start.hour * 60 + start.minute;
      final eventY = minutesFromMidnight * calculateHeightPerMinute();
      final viewportHeight = MediaQuery.of(context).size.height;
      final bottomSheetHeight = viewportHeight * 0.5;
      final visibleBottom =
          currentScrollOffset + (viewportHeight - bottomSheetHeight);
      if (eventY > visibleBottom - 50) {
        final targetOffset = math.max(0.0, eventY - (viewportHeight * 0.2));
        final state = dayViewKey.currentState as dynamic;
        try {
          if (state.mounted) {
            state.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        } catch (e) {
          try {
            if (state.scrollController != null) {
              state.scrollController.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          } catch (e2) {}
        }
      }
    }
  }

  /// Remove preview event
  static void removePreviewEvent(EventController plannedEventController) {
    plannedEventController.removeWhere((e) => e.event == "preview_id");
  }
}
