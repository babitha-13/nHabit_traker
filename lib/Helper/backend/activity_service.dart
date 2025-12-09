import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
class ActivityService {
  static Future<void> copyActivity(ActivityRecord activity) async {
    await createActivity(
      name: activity.name,
      categoryId: activity.categoryId,
      categoryName:
          activity.categoryName.isNotEmpty ? activity.categoryName : 'default',
      trackingType: activity.trackingType,
      target: activity.target,
      description:
          activity.description.isNotEmpty ? activity.description : null,
      categoryType: activity.categoryType,
    );
  }
  static Future<void> deleteActivity(DocumentReference activityRef) async {
    await deleteHabit(activityRef);
  }
  static Future<void> updateDueDate(
      DocumentReference activityRef, DateTime newDate) async {
    await activityRef.update({'dueDate': newDate});
  }
  static Future<void> skipUntil(
      DocumentReference activityRef, DateTime newDate) async {
    await updateHabit(habitRef: activityRef, snoozedUntil: newDate);
  }
  static Future<void> updatePriority(
      DocumentReference activityRef, int currentPriority) async {
    final next = currentPriority == 0 ? 1 : (currentPriority % 3) + 1;
    await updateHabit(
      habitRef: activityRef,
      priority: next,
    );
  }
  static Future<void> updateProgress(ActivityRecord activity, int delta) async {
    final currentProgress = HabitTrackingUtil.getCurrentProgress(activity) ?? 0;
    final current = (currentProgress is int)
        ? currentProgress
        : (currentProgress is double)
            ? currentProgress.round()
            : int.tryParse(currentProgress.toString()) ?? 0;
    int newProgress = current + delta;
    if (newProgress < 0) {
      newProgress = 0;
    }
    await HabitTrackingUtil.updateProgress(activity, newProgress);
  }
  static Future<void> toggleTimer(ActivityRecord activity) async {
    if (activity.isTimerActive) {
      await HabitTrackingUtil.stopTimer(activity);
    } else {
      await HabitTrackingUtil.startTimer(activity);
    }
  }
  static Future<void> toggleBinaryCompletion(ActivityRecord activity) async {
    if (HabitTrackingUtil.isCompletedToday(activity)) {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final List<DateTime> completedDates = List.from(activity.completedDates);
      completedDates.removeWhere((date) =>
          date.year == todayDate.year &&
          date.month == todayDate.month &&
          date.day == todayDate.day);
      await activity.reference.update({
        'status': 'incomplete',
        'completedDates': completedDates,
        'lastUpdated': DateTime.now(),
      });
    } else {
      await HabitTrackingUtil.markCompleted(activity);
    }
  }
  static Future<void> skipOccurrence(ActivityRecord activity) {
    return HabitTrackingUtil.addSkippedDate(activity, DateTime.now());
  }
}
