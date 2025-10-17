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
        print('GoalService: User document not found for $userId');
        return null;
      }

      final userData = UsersRecord.fromSnapshot(userDoc);
      final goalId = userData.currentGoalId;

      if (goalId.isEmpty) {
        print('GoalService: No current goal ID for user $userId');
        return null;
      }

      // Get the goal document
      final goalDoc =
          await GoalRecord.collectionForUser(userId).doc(goalId).get();
      if (!goalDoc.exists) {
        print('GoalService: Goal document not found: $goalId');
        return null;
      }

      return GoalRecord.fromSnapshot(goalDoc);
    } catch (e) {
      print('GoalService: Error getting user goal: $e');
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

        print('GoalService: Updated existing goal for user $userId');
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

        print('GoalService: Created new goal for user $userId');
      }
    } catch (e) {
      print('GoalService: Error saving goal: $e');
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

      print('GoalService: shouldShowGoal check for $userId:');
      print('  - isFirstLoginToday: $isFirstLoginToday');
      print('  - isNearDayEnd: $isNearDayEnd');
      print('  - hasGoal: $hasGoal');
      print('  - shouldShow: $shouldShow');

      return shouldShow;
    } catch (e) {
      print('GoalService: Error checking if should show goal: $e');
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

      print('GoalService: Marked goal as shown for user $userId on $today');
    } catch (e) {
      print('GoalService: Error marking goal as shown: $e');
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
      print('GoalService: Error checking if user has goal: $e');
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

        print('GoalService: Deleted goal for user $userId');
      }
    } catch (e) {
      print('GoalService: Error deleting goal: $e');
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

      print('GoalService: shouldShowOnboardingGoal for $userId: true');
      return true;
    } catch (e) {
      print('GoalService: Error checking if should show onboarding goal: $e');
      return false;
    }
  }

  /// Mark onboarding as completed for user
  static Future<void> markOnboardingCompleted(String userId) async {
    try {
      await UsersRecord.collection.doc(userId).update({
        'goal_onboarding_completed': true,
      });

      print('GoalService: Marked onboarding as completed for user $userId');
    } catch (e) {
      print('GoalService: Error marking onboarding as completed: $e');
      rethrow;
    }
  }

  /// Mark onboarding as skipped for user
  static Future<void> markOnboardingSkipped(String userId) async {
    try {
      await UsersRecord.collection.doc(userId).update({
        'goal_prompt_skipped': true,
      });

      print('GoalService: Marked onboarding as skipped for user $userId');
    } catch (e) {
      print('GoalService: Error marking onboarding as skipped: $e');
      rethrow;
    }
  }
}
