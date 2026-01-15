import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Helper/Helpers/milestone_service.dart';

class MilestoneToastService {
  /// Show milestone celebration toast
  static void showMilestoneAchievement(int milestoneValue) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final message = MilestoneService.getMilestoneMessage(milestoneValue);
    final isMajor = MilestoneService.isMajorMilestone(milestoneValue);

    // Use gold color for major milestones (1000+), silver/blue for others
    final backgroundColor =
        isMajor ? Colors.amber.shade700 : Colors.blue.shade700;

    final icon = isMajor ? Icons.emoji_events : Icons.star;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Milestone Achieved!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You\'ve earned $milestoneValue points!',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Show multiple milestone achievements with delay
  static void showMultipleMilestones(List<int> milestoneValues) {
    for (int i = 0; i < milestoneValues.length; i++) {
      Future.delayed(
        Duration(milliseconds: i * 600),
        () {
          showMilestoneAchievement(milestoneValues[i]);
        },
      );
    }
  }
}
