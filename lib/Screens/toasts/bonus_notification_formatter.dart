import 'package:habit_tracker/Screens/toasts/score_bonus_toast_service.dart';

/// Helper to format and display bonus/penalty notifications from score data
/// Separates UI formatting concerns from backend calculation logic
class BonusNotificationFormatter {
  /// Format and show bonus notifications from cumulative score data
  /// Takes structured data from score calculation services and formats it for display
  static void showBonusNotifications(Map<String, dynamic> scoreData) {
    final notifications = _formatNotifications(scoreData);
    if (notifications.isNotEmpty) {
      ScoreBonusToastService.showMultipleNotifications(notifications);
    }
  }

  /// Format structured score data into notification messages
  /// Returns list of notification maps with 'message', 'points', and 'type'
  static List<Map<String, dynamic>> _formatNotifications(
    Map<String, dynamic> scoreData,
  ) {
    final notifications = <Map<String, dynamic>>[];

    // Consistency bonus notification
    final consistencyBonus = scoreData['consistencyBonus'] ?? 0.0;
    if (consistencyBonus >= 5.0) {
      notifications.add({
        'message':
            'Consistency Bonus! You completed more than 80% for the last 7 days, so you get 5 extra points',
        'points': 5.0,
        'type': 'bonus',
      });
    } else if (consistencyBonus >= 2.0) {
      notifications.add({
        'message':
            'Partial Consistency Bonus! You completed more than 80% for 5-6 days, so you get 2 extra points',
        'points': 2.0,
        'type': 'bonus',
      });
    }

    // Recovery bonus notification
    final recoveryBonus = scoreData['recoveryBonus'] ?? 0.0;
    if (recoveryBonus > 0) {
      final consecutiveDays = scoreData['consecutiveLowDays'] ?? 0;
      notifications.add({
        'message':
            'Recovery Bonus! You\'re back on track after ${consecutiveDays} day${consecutiveDays == 1 ? '' : 's'} of low completion, so you get ${recoveryBonus.toStringAsFixed(1)} extra points',
        'points': recoveryBonus,
        'type': 'bonus',
      });
    }

    // Combined penalty notification (with diminishing returns)
    final penalty = scoreData['decayPenalty'] ?? 0.0;
    if (penalty > 0) {
      final consecutiveDays = scoreData['consecutiveLowDays'] ?? 0;
      notifications.add({
        'message':
            'Low Completion Penalty: Yesterday\'s completion was below 50% (day ${consecutiveDays} of low completion), so you lose ${penalty.toStringAsFixed(1)} points',
        'points': -penalty,
        'type': 'penalty',
      });
    }

    // Category neglect penalty notification
    final categoryPenalty = scoreData['categoryNeglectPenalty'] ?? 0.0;
    if (categoryPenalty > 0) {
      const categoryNeglectPenalty = 0.4; // From ScoreFormulas constant
      final ignoredCategories =
          (categoryPenalty / categoryNeglectPenalty).round();
      notifications.add({
        'message':
            'Category Neglect Penalty: You ignored ${ignoredCategories} habit categor${ignoredCategories == 1 ? 'y' : 'ies'} today, so you lose ${categoryPenalty.toStringAsFixed(1)} points',
        'points': -categoryPenalty,
        'type': 'penalty',
      });
    }

    return notifications;
  }
}
