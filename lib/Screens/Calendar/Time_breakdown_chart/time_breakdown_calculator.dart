import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';
import 'package:habit_tracker/Screens/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/Screens/Calendar/Time_breakdown_chart/time_breakdown_chart.dart';

/// Utility class for calculating time breakdown from calendar events
class CalendarTimeBreakdownCalculator {
  /// Calculate time breakdown from completed events
  static TimeBreakdownData calculateTimeBreakdown(
    List<CalendarEventData> completedEvents,
  ) {
    double habitMinutes = 0.0;
    double taskMinutes = 0.0;
    double essentialMinutes = 0.0;
    final habitCategoryTimeMap = <String, double>{};
    final habitCategoryColorMap = <String, String>{};
    final taskCategoryTimeMap = <String, double>{};
    final taskCategoryColorMap = <String, String>{};
    final essentialActivityTimeMap = <String, double>{};
    final essentialActivityColorMap = <String, String>{};

    for (final event in completedEvents) {
      if (event.startTime == null || event.endTime == null) continue;
      final metadata = CalendarEventMetadata.fromMap(event.event);
      if (metadata == null) continue;
      final duration = event.endTime!.difference(event.startTime!);
      final minutes = duration.inMinutes.toDouble();

      if (metadata.activityType == 'habit') {
        habitMinutes += minutes;
      } else if (metadata.activityType == 'task') {
        taskMinutes += minutes;
      } else if (metadata.activityType == 'essential') {
        essentialMinutes += minutes;
      }

      if (metadata.activityType == 'habit' || metadata.activityType == 'task') {
        final categoryKey = metadata.categoryName?.isNotEmpty == true
            ? metadata.categoryName!
            : (metadata.categoryId?.isNotEmpty == true
                ? metadata.categoryId!
                : 'Uncategorized');
        String? colorHex = metadata.categoryColorHex;
        if (metadata.activityType == 'habit') {
          habitCategoryTimeMap[categoryKey] =
              (habitCategoryTimeMap[categoryKey] ?? 0.0) + minutes;
          if (colorHex != null && colorHex.isNotEmpty) {
            habitCategoryColorMap[categoryKey] = colorHex;
          } else if (!habitCategoryColorMap.containsKey(categoryKey)) {
            habitCategoryColorMap[categoryKey] = '#C57B57'; // Copper default
          }
        } else {
          taskCategoryTimeMap[categoryKey] =
              (taskCategoryTimeMap[categoryKey] ?? 0.0) + minutes;
          if (colorHex != null && colorHex.isNotEmpty) {
            taskCategoryColorMap[categoryKey] = colorHex;
          } else if (!taskCategoryColorMap.containsKey(categoryKey)) {
            taskCategoryColorMap[categoryKey] =
                '#1A1A1A'; // Dark charcoal default
          }
        }
      } else if (metadata.activityType == 'essential') {
        final activityKey = metadata.activityName.isNotEmpty
            ? metadata.activityName
            : 'Unnamed Essential';
        essentialActivityTimeMap[activityKey] =
            (essentialActivityTimeMap[activityKey] ?? 0.0) + minutes;
        String? colorHex = metadata.categoryColorHex;
        if (colorHex != null && colorHex.isNotEmpty) {
          essentialActivityColorMap[activityKey] = colorHex;
        } else if (!essentialActivityColorMap.containsKey(activityKey)) {
          essentialActivityColorMap[activityKey] = '#9E9E9E'; // Grey default
        }
      }
    }

    final subcategories = <String, List<PieChartSegment>>{};
    final habitSubcategories = <PieChartSegment>[];
    final habitCategoryKeys = habitCategoryTimeMap.keys.toList()..sort();
    for (final categoryKey in habitCategoryKeys) {
      final minutes = habitCategoryTimeMap[categoryKey]!;
      if (minutes > 0) {
        final colorHex = habitCategoryColorMap[categoryKey] ?? '#C57B57';
        Color categoryColor;
        try {
          categoryColor = fromCssColor(colorHex);
        } catch (e) {
          categoryColor = const Color(0xFFC57B57); // Copper fallback
        }
        habitSubcategories.add(PieChartSegment(
          label: categoryKey,
          value: minutes,
          color: categoryColor,
          category: 'habit',
        ));
      }
    }
    if (habitSubcategories.isNotEmpty) {
      subcategories['habit'] = habitSubcategories;
    }

    final taskSubcategories = <PieChartSegment>[];
    final taskCategoryKeys = taskCategoryTimeMap.keys.toList()..sort();
    for (final categoryKey in taskCategoryKeys) {
      final minutes = taskCategoryTimeMap[categoryKey]!;
      if (minutes > 0) {
        final colorHex = taskCategoryColorMap[categoryKey] ?? '#1A1A1A';
        Color categoryColor;
        try {
          categoryColor = fromCssColor(colorHex);
        } catch (e) {
          categoryColor = const Color(0xFF1A1A1A); // Fallback
        }
        taskSubcategories.add(PieChartSegment(
          label: categoryKey,
          value: minutes,
          color: categoryColor,
          category: 'task',
        ));
      }
    }
    if (taskSubcategories.isNotEmpty) {
      subcategories['task'] = taskSubcategories;
    }

    final essentialSubcategories = <PieChartSegment>[];
    final essentialActivityKeys = essentialActivityTimeMap.keys.toList()
      ..sort();
    for (final activityKey in essentialActivityKeys) {
      final minutes = essentialActivityTimeMap[activityKey]!;
      if (minutes > 0) {
        final colorHex = essentialActivityColorMap[activityKey] ?? '#9E9E9E';
        Color activityColor;
        try {
          activityColor = fromCssColor(colorHex);
        } catch (e) {
          activityColor = Colors.grey; // Fallback
        }
        essentialSubcategories.add(PieChartSegment(
          label: activityKey,
          value: minutes,
          color: activityColor,
          category: 'essential',
        ));
      }
    }
    if (essentialSubcategories.isNotEmpty) {
      subcategories['essential'] = essentialSubcategories;
    } else {
      subcategories['essential'] = [];
    }

    final segments = <PieChartSegment>[];
    segments.addAll(habitSubcategories);
    segments.addAll(taskSubcategories);
    segments.addAll(essentialSubcategories);
    final totalLogged = habitMinutes + taskMinutes + essentialMinutes;
    final unloggedMinutes = (24 * 60) - totalLogged;

    if (unloggedMinutes > 0) {
      segments.add(PieChartSegment(
        label: 'Unlogged',
        value: unloggedMinutes,
        color: Colors.grey.shade300,
        category: 'unlogged',
      ));
    }

    return TimeBreakdownData(
      habitMinutes: habitMinutes,
      taskMinutes: taskMinutes,
      essentialMinutes: essentialMinutes,
      segments: segments,
      subcategories: subcategories,
    );
  }
}
