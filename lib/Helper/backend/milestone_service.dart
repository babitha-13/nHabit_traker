/// Service for managing milestone achievements and progress tracking
class MilestoneService {
  // Milestone thresholds in ascending order
  static const List<int> milestones = [50, 100, 200, 500, 1000, 2000, 5000];

  /// Get the next milestone above the current score
  /// Returns null if all milestones are achieved
  static int? getNextMilestone(double currentScore) {
    for (final milestone in milestones) {
      if (currentScore < milestone) {
        return milestone;
      }
    }
    return null; // All milestones achieved
  }

  /// Get progress percentage to next milestone (0.0 to 1.0)
  /// Returns 1.0 if all milestones achieved
  static double getProgressToNextMilestone(double currentScore) {
    final nextMilestone = getNextMilestone(currentScore);
    if (nextMilestone == null) return 1.0;

    // Find previous milestone (or 0 if before first milestone)
    int previousMilestone = 0;
    for (int i = milestones.length - 1; i >= 0; i--) {
      if (milestones[i] < currentScore) {
        previousMilestone = milestones[i];
        break;
      }
    }

    final range = nextMilestone - previousMilestone;
    final progress = currentScore - previousMilestone;
    return (progress / range).clamp(0.0, 1.0);
  }

  /// Check if a specific milestone is achieved (using bitmask)
  static bool isMilestoneAchieved(int achievedMilestones, int milestoneIndex) {
    if (milestoneIndex < 0 || milestoneIndex >= milestones.length) return false;
    return (achievedMilestones & (1 << milestoneIndex)) != 0;
  }

  /// Set a milestone as achieved (update bitmask)
  static int setMilestoneAchieved(int achievedMilestones, int milestoneIndex) {
    if (milestoneIndex < 0 || milestoneIndex >= milestones.length) {
      return achievedMilestones;
    }
    return achievedMilestones | (1 << milestoneIndex);
  }

  /// Get list of newly achieved milestones between old and new score
  /// Returns list of milestone values (not indices)
  static List<int> getNewMilestones(
    double oldScore,
    double newScore,
    int achievedMilestones,
  ) {
    final newMilestones = <int>[];

    for (int i = 0; i < milestones.length; i++) {
      final milestone = milestones[i];

      // Check if milestone was just crossed
      if (oldScore < milestone && newScore >= milestone) {
        // Check if not already marked as achieved
        if (!isMilestoneAchieved(achievedMilestones, i)) {
          newMilestones.add(milestone);
        }
      }
    }

    return newMilestones;
  }

  /// Get achievement message for a milestone
  static String getMilestoneMessage(int milestoneValue) {
    switch (milestoneValue) {
      case 50:
        return "First Milestone! You've reached 50 points! 🎉";
      case 100:
        return "Century Club! 100 points achieved! 🏆";
      case 200:
        return "Double Century! 200 points unlocked! ⭐";
      case 500:
        return "Half Grand! 500 points milestone! 🌟";
      case 1000:
        return "Grand Master! 1000 points achieved! 👑";
      case 2000:
        return "Elite Status! 2000 points milestone! 💎";
      case 5000:
        return "Legendary! 5000 points unlocked! 🏅";
      default:
        return "Milestone Achieved! $milestoneValue points! 🎊";
    }
  }

  /// Get all achieved milestones from bitmask
  static List<int> getAchievedMilestones(int achievedMilestones) {
    final achieved = <int>[];
    for (int i = 0; i < milestones.length; i++) {
      if (isMilestoneAchieved(achievedMilestones, i)) {
        achieved.add(milestones[i]);
      }
    }
    return achieved;
  }

  /// Check if milestone is a major milestone (1000+ points)
  static bool isMajorMilestone(int milestoneValue) {
    return milestoneValue >= 1000;
  }
}

