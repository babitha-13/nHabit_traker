import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';

/// Service for calculating fractional points and daily targets for habit tracking
class PointsService {
  /// Convert period type to number of days
  static int periodTypeToDays(String periodType) {
    switch (periodType.toLowerCase()) {
      case 'daily':
      case 'days':
        return 1;
      case 'weekly':
      case 'weeks':
        return 7;
      case 'monthly':
      case 'months':
        return 30;
      default:
        return 7; // Default to weekly
    }
  }

  /// Calculate the daily target points for a single habit instance
  /// Returns the expected daily points based on frequency and importance
  static double calculateDailyTarget(
    ActivityInstanceRecord instance,
    CategoryRecord category,
  ) {
    final categoryWeight = category.weight;
    final habitPriority = instance.templatePriority.toDouble();
    final fullWeight = categoryWeight * habitPriority;

    // Calculate daily frequency based on template configuration
    final dailyFrequency = _calculateDailyFrequency(instance);

    // DEBUG: Detailed logging for diagnosis
    print('=== DAILY TARGET CALCULATION DEBUG ===');
    print('Instance: ${instance.templateName}');
    print('Category weight: $categoryWeight');
    print('Template priority: $habitPriority');
    print('Full weight (category × priority): $fullWeight');
    print('Daily frequency: $dailyFrequency');
    print('Final daily target: ${dailyFrequency * fullWeight}');
    print('=====================================');

    return dailyFrequency * fullWeight;
  }

  /// Calculate daily target with template data (enhanced version)
  /// Use this when you have access to the template data
  static double calculateDailyTargetWithTemplate(
    ActivityInstanceRecord instance,
    CategoryRecord category,
    ActivityRecord template,
  ) {
    final categoryWeight = category.weight;
    final habitPriority = instance.templatePriority.toDouble();
    final fullWeight = categoryWeight * habitPriority;

    // Calculate daily frequency from template data
    final dailyFrequency = calculateDailyFrequencyFromTemplate(template);

    // DEBUG: Detailed logging for template-based calculation
    print('=== TEMPLATE-BASED DAILY TARGET DEBUG ===');
    print('Instance: ${instance.templateName}');
    print('Category weight: $categoryWeight');
    print('Template priority: $habitPriority');
    print('Full weight (category × priority): $fullWeight');
    print('Template frequency fields:');
    print('  - everyXValue: ${template.everyXValue}');
    print('  - everyXPeriodType: "${template.everyXPeriodType}"');
    print('  - timesPerPeriod: ${template.timesPerPeriod}');
    print('  - periodType: "${template.periodType}"');
    print('Daily frequency from template: $dailyFrequency');
    print('Final daily target: ${dailyFrequency * fullWeight}');
    print('==========================================');

    return dailyFrequency * fullWeight;
  }

  /// Calculate daily frequency for a habit instance
  /// Returns the expected daily frequency (e.g., 0.5 for every 2 days)
  static double _calculateDailyFrequency(ActivityInstanceRecord instance) {
    // DEBUG: Log frequency field values
    print('=== FREQUENCY CALCULATION DEBUG ===');
    print('Instance: ${instance.templateName}');
    print('templateEveryXValue: ${instance.templateEveryXValue}');
    print('templateEveryXPeriodType: "${instance.templateEveryXPeriodType}"');
    print('templateTimesPerPeriod: ${instance.templateTimesPerPeriod}');
    print('templatePeriodType: "${instance.templatePeriodType}"');

    // Handle "every X days/weeks" pattern
    if (instance.templateEveryXValue > 1 &&
        instance.templateEveryXPeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(instance.templateEveryXPeriodType);
      final frequency = (1.0 / instance.templateEveryXValue) *
          (periodDays / periodTypeToDays('daily'));
      print(
          'Using "every X" pattern: everyXValue=${instance.templateEveryXValue}, periodType=${instance.templateEveryXPeriodType}, periodDays=$periodDays');
      print('Calculated frequency: $frequency');
      print('=====================================');
      return frequency;
    }

    // Handle "times per period" pattern
    if (instance.templateTimesPerPeriod > 0 &&
        instance.templatePeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(instance.templatePeriodType);
      final frequency = (instance.templateTimesPerPeriod / periodDays);
      print(
          'Using "times per period" pattern: timesPerPeriod=${instance.templateTimesPerPeriod}, periodType=${instance.templatePeriodType}, periodDays=$periodDays');
      print('Calculated frequency: $frequency');
      print('=====================================');
      return frequency;
    }

    // Default: daily habit (1 time per day)
    print('Using default frequency: 1.0 (daily habit)');
    print('=====================================');
    return 1.0;
  }

  /// Calculate daily frequency from template data
  /// This method can be used when template data is available
  static double calculateDailyFrequencyFromTemplate(ActivityRecord template) {
    // DEBUG: Log template frequency calculation
    print('=== TEMPLATE FREQUENCY CALCULATION DEBUG ===');
    print('Template: ${template.name}');
    print('everyXValue: ${template.everyXValue}');
    print('everyXPeriodType: "${template.everyXPeriodType}"');
    print('timesPerPeriod: ${template.timesPerPeriod}');
    print('periodType: "${template.periodType}"');

    // Handle "every X days" pattern
    if (template.everyXValue > 1 && template.everyXPeriodType.isNotEmpty) {
      final periodDays = periodTypeToDays(template.everyXPeriodType);
      final frequency = (1.0 / template.everyXValue) *
          (periodDays / periodTypeToDays('daily'));
      print(
          'Using template "every X" pattern: everyXValue=${template.everyXValue}, periodType=${template.everyXPeriodType}, periodDays=$periodDays');
      print('Calculated frequency: $frequency');
      print('==========================================');
      return frequency;
    }

    // Handle "times per period" pattern
    if (template.timesPerPeriod > 0 && template.periodType.isNotEmpty) {
      final periodDays = periodTypeToDays(template.periodType);
      final frequency = (template.timesPerPeriod / periodDays);
      print(
          'Using template "times per period" pattern: timesPerPeriod=${template.timesPerPeriod}, periodType=${template.periodType}, periodDays=$periodDays');
      print('Calculated frequency: $frequency');
      print('==========================================');
      return frequency;
    }

    // Default: daily habit (1 time per day)
    print('Using template default frequency: 1.0 (daily habit)');
    print('==========================================');
    return 1.0;
  }

  /// Calculate points earned for a single habit instance
  /// Returns fractional points based on completion percentage
  static double calculatePointsEarned(
    ActivityInstanceRecord instance,
    CategoryRecord category,
  ) {
    final categoryWeight = category.weight;
    final habitPriority = instance.templatePriority.toDouble();
    final fullWeight = categoryWeight * habitPriority;

    switch (instance.templateTrackingType) {
      case 'binary':
        // Binary habits: full points if completed, 0 if not
        return instance.status == 'completed' ? fullWeight : 0.0;

      case 'quantitative':
        // Quantitative habits: points based on progress percentage
        if (instance.status == 'completed') {
          return fullWeight;
        }

        final currentValue = _getCurrentValue(instance);
        final target = _getTargetValue(instance);

        if (target <= 0) return 0.0;

        // For windowed habits, use differential progress (today's contribution)
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          final lastDayValue = _getLastDayValue(instance);
          final todayContribution = currentValue - lastDayValue;
          final dailyTarget =
              target / instance.windowDuration; // Daily target within window

          if (dailyTarget <= 0) return 0.0;

          final dailyProgressFraction =
              (todayContribution / dailyTarget).clamp(0.0, 1.0);
          return dailyProgressFraction * fullWeight;
        }

        // For non-windowed habits, use total progress
        final completionFraction = (currentValue / target).clamp(0.0, 1.0);
        return completionFraction * fullWeight;

      case 'time':
        // Time-based habits: points based on accumulated time vs target
        if (instance.status == 'completed') {
          return fullWeight;
        }

        final accumulatedTime = instance.accumulatedTime;
        final targetMinutes = _getTargetValue(instance);
        final targetMs =
            targetMinutes * 60000; // Convert minutes to milliseconds

        if (targetMs <= 0) return 0.0;

        // For windowed habits, use differential progress (today's contribution)
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          final lastDayValue = _getLastDayValue(instance);
          final todayContribution = accumulatedTime - lastDayValue;
          final dailyTargetMs =
              targetMs / instance.windowDuration; // Daily target within window

          if (dailyTargetMs <= 0) return 0.0;

          final dailyProgressFraction =
              (todayContribution / dailyTargetMs).clamp(0.0, 1.0);
          return dailyProgressFraction * fullWeight;
        }

        // For non-windowed habits, use total progress
        final completionFraction = (accumulatedTime / targetMs).clamp(0.0, 1.0);
        return completionFraction * fullWeight;

      default:
        return 0.0;
    }
  }

  /// Calculate total daily target for all habit instances
  static double calculateTotalDailyTarget(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
  ) {
    double totalTarget = 0.0;

    print(
        'PointsService: Calculating daily target for ${instances.length} instances');
    print(
        'PointsService: Available categories: ${categories.map((c) => '${c.name}(${c.reference.id})').join(', ')}');

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      print(
          'PointsService: Processing ${instance.templateName} with category ID: "${instance.templateCategoryId}"');

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) {
        print(
            'PointsService: No category found for ${instance.templateName} (ID: "${instance.templateCategoryId}")');
        continue;
      }

      final target = calculateDailyTarget(instance, category);
      totalTarget += target;
      print('PointsService: ${instance.templateName} daily target: $target');
    }

    print('PointsService: Total daily target: $totalTarget');
    return totalTarget;
  }

  /// Calculate total daily target with template data (enhanced version)
  /// Use this when you have access to template data for accurate frequency calculation
  static Future<double> calculateTotalDailyTargetWithTemplates(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
    String userId,
  ) async {
    double totalTarget = 0.0;

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) continue;

      try {
        // Fetch template data for accurate frequency calculation
        final templateRef =
            ActivityRecord.collectionForUser(userId).doc(instance.templateId);
        final template = await ActivityRecord.getDocumentOnce(templateRef);

        totalTarget +=
            calculateDailyTargetWithTemplate(instance, category, template);
      } catch (e) {
        // Fallback to basic calculation if template fetch fails
        totalTarget += calculateDailyTarget(instance, category);
      }
    }

    return totalTarget;
  }

  /// Calculate total points earned for all habit instances
  static double calculateTotalPointsEarned(
    List<ActivityInstanceRecord> instances,
    List<CategoryRecord> categories,
  ) {
    double totalPoints = 0.0;

    print(
        'PointsService: Calculating total points for ${instances.length} instances');

    for (final instance in instances) {
      if (instance.templateCategoryType != 'habit') continue;

      final category = _findCategoryForInstance(instance, categories);
      if (category == null) {
        print('PointsService: No category found for ${instance.templateName}');
        continue;
      }

      final points = calculatePointsEarned(instance, category);
      totalPoints += points;
      print('PointsService: ${instance.templateName} earned $points points');
    }

    print('PointsService: Total points earned: $totalPoints');
    return totalPoints;
  }

  /// Calculate daily performance percentage
  /// Returns percentage (0-100+) of daily target achieved
  static double calculateDailyPerformancePercent(
    double pointsEarned,
    double totalTarget,
  ) {
    if (totalTarget <= 0) return 0.0;

    final percentage = (pointsEarned / totalTarget) * 100.0;
    return percentage.clamp(
        0.0, double.infinity); // Allow >100% for overachievement
  }

  /// Helper method to get current value from instance
  static double _getCurrentValue(ActivityInstanceRecord instance) {
    final value = instance.currentValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get target value from instance
  static double _getTargetValue(ActivityInstanceRecord instance) {
    final target = instance.templateTarget;
    if (target is num) return target.toDouble();
    if (target is String) return double.tryParse(target) ?? 0.0;
    return 0.0;
  }

  /// Helper method to get last day value from instance (for differential progress)
  static double _getLastDayValue(ActivityInstanceRecord instance) {
    final value = instance.lastDayValue;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to find category for an instance
  static CategoryRecord? _findCategoryForInstance(
    ActivityInstanceRecord instance,
    List<CategoryRecord> categories,
  ) {
    try {
      // First try to find by category ID
      if (instance.templateCategoryId.isNotEmpty) {
        return categories.firstWhere(
          (cat) => cat.reference.id == instance.templateCategoryId,
        );
      }

      // Fallback: try to find by category name
      if (instance.templateCategoryName.isNotEmpty) {
        return categories.firstWhere(
          (cat) => cat.name == instance.templateCategoryName,
        );
      }

      return null;
    } catch (e) {
      print(
          'PointsService: Error finding category for ${instance.templateName}: $e');
      return null;
    }
  }
}

/// Example calculations for fractional point system:
/// 
/// Example 1: "Exercise" habit
/// - Frequency: Every 2 days
/// - Category weight: 2.0 (medium priority)
/// - Habit priority: 3 (high priority)
/// - Daily target = (1/2) * 2.0 * 3 = 3.0 points per day
/// 
/// Example 2: "Read" habit  
/// - Frequency: 3 times per week
/// - Category weight: 1.5 (low priority)
/// - Habit priority: 2 (medium priority)
/// - Daily target = (3/7) * 1.5 * 2 = 1.29 points per day
/// 
/// Example 3: "Meditate" habit
/// - Frequency: Daily (1 time per day)
/// - Category weight: 3.0 (high priority)
/// - Habit priority: 1 (low priority)
/// - Daily target = 1.0 * 3.0 * 1 = 3.0 points per day
