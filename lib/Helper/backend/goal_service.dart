import 'package:habit_tracker/Helper/backend/schema/goal_record.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';

/// Service for managing user goals and goal display logic
/// All business logic for goals is centralized here (#REFACTOR_NOW compliance)
class GoalService {
  /// Get the current active goal for a user
  static Future<GoalRecord?> getUserGoal(String userId) async {
    try {
      // First get the user's current goal ID
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return null;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      final goalId = userData.currentGoalId;
      if (goalId.isEmpty) {
        return null;
      }
      // Get the goal document
      final goalDoc =
          await GoalRecord.collectionForUser(userId).doc(goalId).get();
      if (!goalDoc.exists) {
        return null;
      }
      return GoalRecord.fromSnapshot(goalDoc);
    } catch (e) {
      return null;
    }
  }

  /// Save or update a goal for a user
  static Future<void> saveGoal(String userId, GoalRecord goal) async {
    try {
      final now = DateTime.now();
      // Check if user already has a goal
      final existingGoal = await getUserGoal(userId);
      if (existingGoal != null) {
        // Update existing goal
        final goalData = createGoalRecordData(
          whatToAchieve: goal.whatToAchieve,
          byWhen: goal.byWhen,
          why: goal.why,
          how: goal.how,
          thingsToAvoid: goal.thingsToAvoid,
          lastShownAt: goal.lastShownAt,
          createdAt: existingGoal.createdAt, // Keep original creation date
          lastUpdated: now,
          isActive: true,
        );
        await GoalRecord.collectionForUser(userId)
            .doc(existingGoal.reference.id)
            .update(goalData);
      } else {
        // Create new goal
        final goalData = createGoalRecordData(
          whatToAchieve: goal.whatToAchieve,
          byWhen: goal.byWhen,
          why: goal.why,
          how: goal.how,
          thingsToAvoid: goal.thingsToAvoid,
          lastShownAt: goal.lastShownAt,
          createdAt: now,
          lastUpdated: now,
          isActive: true,
        );
        final goalRef = GoalRecord.collectionForUser(userId).doc();
        await goalRef.set(goalData);
        // Update user's current goal ID
        await UsersRecord.collection.doc(userId).update({
          'current_goal_id': goalRef.id,
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Check if goal should be shown to user
  /// Returns true if:
  /// 1. First login of day (lastGoalShownDate != today)
  /// 2. Near day-end (within 1 hour before 2 AM)
  static Future<bool> shouldShowGoal(String userId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Get user's last goal shown date
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      final lastShownDate = userData.lastGoalShownDate;
      // Check if it's first login of day
      final isFirstLoginToday = lastShownDate == null ||
          DateTime(
                  lastShownDate.year, lastShownDate.month, lastShownDate.day) !=
              today;
      // Check if it's near day-end (between 1:00 AM - 2:00 AM)
      final isNearDayEnd = now.hour == 1; // Between 1:00 AM - 2:00 AM
      // Check if user has a goal
      final hasGoal = userData.currentGoalId.isNotEmpty;
      final shouldShow = hasGoal && (isFirstLoginToday || isNearDayEnd);
      return shouldShow;
    } catch (e) {
      return false;
    }
  }

  /// Check if goal should be shown from notification tap
  /// Returns true if:
  /// 1. First login of day (lastGoalShownDate != today)
  /// 2. User has a goal
  /// Note: Bypasses time-based checks since notification timing is handled externally
  static Future<bool> shouldShowGoalFromNotification(String userId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Get user's last goal shown date
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      final lastShownDate = userData.lastGoalShownDate;
      // Check if it's first login of day
      final isFirstLoginToday = lastShownDate == null ||
          DateTime(
                  lastShownDate.year, lastShownDate.month, lastShownDate.day) !=
              today;
      // Check if user has a goal
      final hasGoal = userData.currentGoalId.isNotEmpty;
      final shouldShow = hasGoal && isFirstLoginToday;
      return shouldShow;
    } catch (e) {
      return false;
    }
  }

  /// Mark goal as shown for today
  static Future<void> markGoalShown(String userId) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await UsersRecord.collection.doc(userId).update({
        'last_goal_shown_date': today,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Check if user has any goal set
  static Future<bool> hasGoal(String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      return userData.currentGoalId.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Delete user's current goal
  static Future<void> deleteGoal(String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      final goalId = userData.currentGoalId;
      if (goalId.isNotEmpty) {
        // Delete the goal document
        await GoalRecord.collectionForUser(userId).doc(goalId).delete();
        // Clear the current goal ID from user
        await UsersRecord.collection.doc(userId).update({
          'current_goal_id': null,
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Check if onboarding goal should be shown to user
  /// Returns true if: not skipped AND not completed AND no current goal
  static Future<bool> shouldShowOnboardingGoal(String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      // Check if user has skipped onboarding
      if (userData.goalPromptSkipped) {
        return false;
      }
      // Check if user has completed onboarding
      if (userData.goalOnboardingCompleted) {
        return false;
      }
      // Check if user already has a goal
      if (userData.currentGoalId.isNotEmpty) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mark onboarding as completed for user
  static Future<void> markOnboardingCompleted(String userId) async {
    try {
      await UsersRecord.collection.doc(userId).update({
        'goal_onboarding_completed': true,
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Mark onboarding as skipped for user
  static Future<void> markOnboardingSkipped(String userId) async {
    try {
      await UsersRecord.collection.doc(userId).update({
        'goal_prompt_skipped': true,
      });
    } catch (e) {
      rethrow;
    }
  }
}
