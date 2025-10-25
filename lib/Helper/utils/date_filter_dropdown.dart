import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
enum DateFilterType {
  today,
  tomorrow,
  week,
  later,
}
class DateFilterDropdown extends StatelessWidget {
  final DateFilterType selectedFilter;
  final Function(DateFilterType) onChanged;
  final bool showSortIcon;
  const DateFilterDropdown({
    super.key,
    required this.selectedFilter,
    required this.onChanged,
    this.showSortIcon = true,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Only show text (no dropdown on tap)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            _getDisplayText(),
            style: theme.titleMedium.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
        if (showSortIcon) ...[
          const SizedBox(width: 8),
          Builder(
            builder: (iconContext) {
              return IconButton(
                icon: Icon(
                  Icons.sort,
                  color: theme.secondaryText,
                ),
                onPressed: () => _showFilterMenu(iconContext),
                tooltip: 'Filter options',
              );
            },
          ),
        ],
      ],
    );
  }
  String _getDisplayText() {
    final now = DateTime.now();
    switch (selectedFilter) {
      case DateFilterType.today:
        return DateFormat('EEEE, MMMM d, y').format(now);
      case DateFilterType.tomorrow:
        final tomorrow = now.add(const Duration(days: 1));
        return DateFormat('EEEE, MMMM d, y').format(tomorrow);
      case DateFilterType.week:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(startOfWeek)} - ${DateFormat('MMM d, y').format(endOfWeek)}';
      case DateFilterType.later:
        return 'Later';
    }
  }
  void _showFilterMenu(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<DateFilterType>(
      context: context,
      position: position, // menu appears near icon
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      color: theme.secondaryBackground,
      elevation: 8,
      items: [
        _buildMenuItem(DateFilterType.today, 'Today', Icons.today, theme),
        _buildMenuItem(
            DateFilterType.tomorrow, 'Tomorrow', Icons.schedule, theme),
        _buildMenuItem(
            DateFilterType.week, 'This Week', Icons.date_range, theme),
        _buildMenuItem(DateFilterType.later, 'Later', Icons.schedule, theme),
      ],
    ).then((value) {
      if (value != null) onChanged(value);
    });
  }
  PopupMenuItem<DateFilterType> _buildMenuItem(DateFilterType value,
      String label, IconData icon, FlutterFlowTheme theme) {
    return PopupMenuItem<DateFilterType>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.bodyMedium,
          ),
          if (selectedFilter == value) ...[
            const Spacer(),
            Icon(
              Icons.check,
              size: 16,
              color: theme.primary,
            ),
          ],
        ],
      ),
    );
  }
}
// Helper class for filtering logic
class DateFilterHelper {
  static bool isItemInFilter(dynamic item, DateFilterType filterType) {
    if (item is! ActivityRecord) return false;
    final today = DateService.todayStart;
    switch (filterType) {
      case DateFilterType.today:
        return _isItemForToday(item, today);
      case DateFilterType.tomorrow:
        return _isItemForTomorrow(item, today);
      case DateFilterType.week:
        return _isItemForThisWeek(item, today);
      case DateFilterType.later:
        return _isItemForLater(item, today);
    }
  }
  static bool isInstanceInFilter(
      ActivityInstanceRecord instance, DateFilterType filterType) {
    final today = DateService.todayStart;
    switch (filterType) {
      case DateFilterType.today:
        return _isInstanceForToday(instance, today);
      case DateFilterType.tomorrow:
        return _isInstanceForTomorrow(instance, today);
      case DateFilterType.week:
        return _isInstanceForThisWeek(instance, today);
      case DateFilterType.later:
        return _isInstanceForLater(instance, today);
    }
  }
  static bool _isInstanceForToday(
      ActivityInstanceRecord instance, DateTime today) {
    // Instances with null dueDate (recurring habits) are considered "today" items
    if (instance.dueDate == null) return true;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    // Include today AND overdue items (items before today should still show)
    return dueDate.isBefore(today) || dueDate == today;
  }
  static bool _isInstanceForTomorrow(
      ActivityInstanceRecord instance, DateTime today) {
    if (instance.dueDate == null) return false;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    final tomorrow = today.add(const Duration(days: 1));
    return dueDate == tomorrow;
  }
  static bool _isInstanceForThisWeek(
      ActivityInstanceRecord instance, DateTime today) {
    // Instances with null dueDate (recurring habits) are included in weekly view
    if (instance.dueDate == null) return true;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    // Include items through end of week, plus overdue items (anything on or before end of week)
    return !dueDate.isAfter(endOfWeek);
  }
  static bool _isInstanceForLater(
      ActivityInstanceRecord instance, DateTime today) {
    if (instance.dueDate == null) return true; // No due date means later
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    final endOfWeek = today
        .subtract(Duration(days: today.weekday - 1))
        .add(const Duration(days: 6));
    return dueDate.isAfter(endOfWeek);
  }
  static bool _isItemForToday(ActivityRecord item, DateTime today) {
    if (item.dueDate == null) return false;
    final dueDate =
        DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day);
    return dueDate == today;
  }
  static bool _isItemForTomorrow(ActivityRecord item, DateTime today) {
    if (item.dueDate == null) return false;
    final dueDate =
        DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day);
    final tomorrow = today.add(const Duration(days: 1));
    return dueDate == tomorrow;
  }
  static bool _isItemForThisWeek(ActivityRecord item, DateTime today) {
    if (item.dueDate == null) return false;
    final dueDate =
        DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return !dueDate.isBefore(startOfWeek) && !dueDate.isAfter(endOfWeek);
  }
  static bool _isItemForLater(ActivityRecord item, DateTime today) {
    if (item.dueDate == null) return true; // No due date means later
    final dueDate =
        DateTime(item.dueDate!.year, item.dueDate!.month, item.dueDate!.day);
    final endOfWeek = today
        .subtract(Duration(days: today.weekday - 1))
        .add(const Duration(days: 6));
    return dueDate.isAfter(endOfWeek);
  }
}
