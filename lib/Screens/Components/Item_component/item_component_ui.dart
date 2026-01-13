import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/frequency_display_helper.dart';
import 'package:habit_tracker/Screens/Components/Background%20UI/item_painter.dart';

class ItemUIBuildingHelper {
  /// Check if an activity instance is recurring
  /// Habits are always recurring; tasks are recurring if they have frequency settings
  static bool isRecurringItem(ActivityInstanceRecord instance) {
    if (instance.templateCategoryType == 'habit') {
      return true; // Habits are always recurring
    } else {
      return instance.templateCategoryType == 'task' &&
          (instance.templateEveryXPeriodType.isNotEmpty ||
              instance.templatePeriodType.isNotEmpty);
    }
  }

  /// Get frequency display string for an activity instance
  /// Uses shared FrequencyDisplayHelper for consistent formatting
  static String getFrequencyDisplay(ActivityInstanceRecord instance) {
    return FrequencyDisplayHelper.formatFromInstance(instance);
  }

  /// Get the left stripe color based on category color hex or category type
  /// Returns the category color if provided, otherwise uses fallback colors
  static Color getLeftStripeColor({
    required String? categoryColorHex,
    required String categoryType,
  }) {
    if (categoryColorHex != null && categoryColorHex.isNotEmpty) {
      try {
        return Color(int.parse(categoryColorHex.replaceFirst('#', '0xFF')));
      } catch (_) {
        // Fall through to default colors if parsing fails
      }
    }
    if (categoryType == 'essential') {
      return const Color(0xFF9E9E9E); // Medium grey fallback
    }
    if (categoryType == 'task') {
      return const Color(0xFF2F4F4F); // Dark Slate Gray fallback
    }
    return Colors.black; // Default fallback for habits
  }

  /// Get the impact level color based on priority
  /// Priority 1 = accent3, Priority 2 = secondary, Priority 3 = primary
  static Color getImpactLevelColor({
    required FlutterFlowTheme theme,
    required int priority,
  }) {
    switch (priority) {
      case 1:
        return theme.accent3;
      case 2:
        return theme.secondary;
      case 3:
        return theme.primary;
      default:
        return theme.secondary;
    }
  }

  /// Build the left stripe widget based on category type
  /// Essential: double line, Habit: dotted line, Task: solid line
  static Widget buildLeftStripe({
    required ActivityInstanceRecord instance,
    required BuildContext context,
    required Color leftStripeColor,
  }) {
    final categoryType = instance.templateCategoryType;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : constraints.minHeight;

        if (categoryType == 'essential') {
          return SizedBox(
            width: 5, // Slightly wider to accommodate double lines
            height: height,
            child: CustomPaint(
              size: Size(5, height),
              painter: DoubleLinePainter(color: leftStripeColor),
            ),
          );
        } else if (categoryType == 'habit') {
          return SizedBox(
            width: 3,
            height: height,
            child: CustomPaint(
              size: Size(3, height),
              painter: DottedLinePainter(color: leftStripeColor),
            ),
          );
        } else {
          return Container(
            width: 4,
            decoration: BoxDecoration(
              color: leftStripeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }
      },
    );
  }

  /// Build priority stars widget for habits
  /// Allows toggling priority by tapping stars
  static Widget buildHabitPriorityStars({
    required ActivityInstanceRecord instance,
    required BuildContext context,
    required Future<void> Function(int) updateTemplatePriority,
  }) {
    final current = instance.templatePriority;
    final nextPriority = current >= 3 ? 1 : current + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async => updateTemplatePriority(nextPriority),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 16,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  /// Build compact left control widget (checkmark, increment, timer, etc.)
  /// Handles binary, quantitative, and time tracking types
  static Widget buildLeftControlsCompact({
    required BuildContext context,
    required ActivityInstanceRecord instance,
    required bool showQuickLogOnLeft,
    required VoidCallback? onQuickLog,
    required bool treatAsBinary,
    required bool isUpdating,
    required bool isCompleted,
    required Color impactLevelColor,
    required Color leftStripeColor,
    required num Function() currentProgressLocal,
    required bool isTimerActiveLocal,
    required int pendingQuantIncrement,
    required Future<void> Function(bool) handleBinaryCompletion,
    required Future<void> Function(int) updateProgress,
    required Future<void> Function(BuildContext, bool) showQuantControlsMenu,
    required Future<void> Function() toggleTimer,
    required Future<void> Function(BuildContext) showTimeControlsMenu,
  }) {
    if (showQuickLogOnLeft) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onQuickLog,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Icon(
              Icons.add_circle_outline,
              size: 24,
              color: FlutterFlowTheme.of(context).primary,
            ),
          ),
        ),
      );
    }
    final effectiveTrackingType =
        treatAsBinary ? 'binary' : instance.templateTrackingType;

    switch (effectiveTrackingType) {
      case 'binary':
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: isUpdating
                ? null
                : () async {
                    await handleBinaryCompletion(!isCompleted);
                  },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted ? impactLevelColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: isCompleted
                      ? null
                      : Border.all(
                          color: leftStripeColor,
                          width: 2,
                        ),
                ),
                child: isCompleted
                    ? const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
        );
      case 'quantitative':
        final current = currentProgressLocal();
        final canDecrement = current > 0;
        return Builder(
          builder: (btnCtx) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => updateProgress(1),
              onLongPress: () => showQuantControlsMenu(btnCtx, canDecrement),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: leftStripeColor,
                      width: 2,
                    ),
                  ),
                  child: Opacity(
                    opacity:
                        (isUpdating || pendingQuantIncrement > 0) ? 0.6 : 1.0,
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: leftStripeColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = isTimerActiveLocal;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: isUpdating ? null : () => toggleTimer(),
            onLongPress:
                isUpdating ? null : () => showTimeControlsMenu(context),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isActive
                      ? FlutterFlowTheme.of(context).error
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: isActive
                      ? null
                      : Border.all(
                          color: leftStripeColor,
                          width: 2,
                        ),
                ),
                child: Icon(
                  isActive ? Icons.stop : Icons.play_arrow,
                  size: 18,
                  color: isActive ? Colors.white : leftStripeColor,
                ),
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
