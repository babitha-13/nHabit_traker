import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_main.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:intl/intl.dart';

class TaskSectionsUIHelper {
  static List<Widget> buildSections({
    required BuildContext context,
    required Map<String, List<dynamic>> bucketedItems,
    required Set<String> expandedSections,
    required Map<String, GlobalKey> sectionKeys,
    required int completionTimeFrame,
    required String? categoryName,
    required List<CategoryRecord> categories,
    required Function(String) onSectionToggle,
    required Function(dynamic, String) buildItemTile,
    required Function(List<dynamic>) applySort,
    required Function(ActivityInstanceRecord) getCategoryColor,
    required Function(ActivityInstanceRecord, String) getSubtitle,
    required Future<void> Function() loadData,
    required Function(ActivityInstanceRecord) updateInstanceInLocalState,
    required Function(ActivityInstanceRecord) removeInstanceFromLocalState,
    required Function(int, int, String) handleReorder,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final order = [
      'Overdue',
      'Today',
      'Tomorrow',
      'This Week',
      'Later',
      'No due date',
      'Recent Completions',
    ];
    final widgets = <Widget>[];
    for (final key in order) {
      final items = List<dynamic>.from(bucketedItems[key]!);
      final visibleItems = items.where((item) {
        if (item is ActivityInstanceRecord) {
          if (key == 'Recent Completions') {
            return true;
          }
          return !isTaskCompleted(item);
        }
        return true;
      }).toList();
      if (visibleItems.isEmpty) continue;
      applySort(visibleItems);
      final isExpanded = expandedSections.contains(key);
      if (!sectionKeys.containsKey(key)) {
        sectionKeys[key] = GlobalKey();
      }
      widgets.add(
        SliverToBoxAdapter(
          child: buildSectionHeader(
            context: context,
            title: key,
            count: visibleItems.length,
            isExpanded: isExpanded,
            headerKey: sectionKeys[key]!,
            completionTimeFrame: completionTimeFrame,
            onTap: () => onSectionToggle(key),
          ),
        ),
      );
      if (isExpanded) {
        widgets.add(
          SliverReorderableList(
            itemBuilder: (context, index) {
              final item = visibleItems[index];
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${item.reference.id}_drag'),
                child: buildItemTile(item, key),
              );
            },
            itemCount: visibleItems.length,
            onReorder: (oldIndex, newIndex) =>
                handleReorder(oldIndex, newIndex, key),
          ),
        );
        if (key == 'Recent Completions') {
          widgets.add(
            SliverToBoxAdapter(
              child: buildShowOlderButtons(
                context: context,
                completionTimeFrame: completionTimeFrame,
                onTimeFrameChanged: (newFrame) {
                  // Handled by parent
                },
                onCacheInvalidate: () {
                  // Handled by parent
                },
                setState: (callback) {
                  // Handled by parent
                },
              ),
            ),
          );
        }
        widgets.add(
          const SliverToBoxAdapter(
            child: SizedBox(height: 8),
          ),
        );
      }
    }
    if (widgets.isEmpty) {
      widgets.add(SliverFillRemaining(
        child: Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(
            child: Text(
              'No tasks yet',
              style: theme.bodyLarge,
            ),
          ),
        ),
      ));
    }
    widgets.add(
      SliverPadding(
        padding: const EdgeInsets.only(bottom: 120),
      ),
    );
    return widgets;
  }

  static Widget buildSectionHeader({
    required BuildContext context,
    required String title,
    required int count,
    required bool isExpanded,
    required GlobalKey headerKey,
    required int completionTimeFrame,
    required Function() onTap,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      key: headerKey,
      margin: EdgeInsets.fromLTRB(16, 8, 16, isExpanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, isExpanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isExpanded
              ? const Radius.circular(12)
              : const Radius.circular(16),
          bottomRight: isExpanded
              ? const Radius.circular(12)
              : const Radius.circular(16),
        ),
        boxShadow: isExpanded ? [] : theme.neumorphicShadowsRaised,
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  title == 'Recent Completions'
                      ? 'Recent Completions (${completionTimeFrame == 2 ? '2 days' : completionTimeFrame == 7 ? '7 days' : '30 days'}) ($count)'
                      : '$title ($count)',
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildItemTile({
    required dynamic item,
    required String bucketKey,
    required ActivityInstanceRecord instance,
    required List<CategoryRecord> categories,
    required String? categoryName,
    required Function(ActivityInstanceRecord) getCategoryColor,
    required Function(ActivityInstanceRecord, String) getSubtitle,
    required Future<void> Function() loadData,
    required Function(ActivityInstanceRecord) updateInstanceInLocalState,
    required Function(ActivityInstanceRecord) removeInstanceFromLocalState,
  }) {
    if (item is ActivityInstanceRecord) {
      return buildTaskTile(
        instance: item,
        bucketKey: bucketKey,
        categories: categories,
        categoryName: categoryName,
        getCategoryColor: getCategoryColor,
        getSubtitle: getSubtitle,
        loadData: loadData,
        updateInstanceInLocalState: updateInstanceInLocalState,
        removeInstanceFromLocalState: removeInstanceFromLocalState,
      );
    }
    return const SizedBox.shrink();
  }

  static Widget buildTaskTile({
    required ActivityInstanceRecord instance,
    required String bucketKey,
    required List<CategoryRecord> categories,
    required String? categoryName,
    required Function(ActivityInstanceRecord) getCategoryColor,
    required Function(ActivityInstanceRecord, String) getSubtitle,
    required Future<void> Function() loadData,
    required Function(ActivityInstanceRecord) updateInstanceInLocalState,
    required Function(ActivityInstanceRecord) removeInstanceFromLocalState,
  }) {
    return ItemComponent(
      page: "task",
      subtitle: getSubtitle(instance, bucketKey),
      showCalendar: true,
      showTaskEdit: true,
      key: Key(instance.reference.id),
      instance: instance,
      categories: categories,
      categoryColorHex: getCategoryColor(instance),
      onRefresh: loadData,
      onInstanceUpdated: updateInstanceInLocalState,
      onInstanceDeleted: removeInstanceFromLocalState,
      showTypeIcon: false,
      showRecurringIcon: instance.status != 'completed',
      showCompleted: bucketKey == 'Recent Completions' ? true : null,
      showExpandedCategoryName: categoryName == null,
    );
  }

  static String getSubtitle({
    required ActivityInstanceRecord instance,
    required String bucketKey,
  }) {
    if (bucketKey == 'Recent Completions') {
      final completedAt = instance.completedAt!;
      final completedStr =
          isSameDay(completedAt, DateTime.now()) ? 'Today' : 'Yesterday';
      final due = instance.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return 'Completed $completedStr • Due: $dueStr$timeStr';
    }
    if (bucketKey == 'Today' || bucketKey == 'Tomorrow') {
      if (instance.hasDueTime()) {
        return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
      }
      return '';
    }
    final dueDate = instance.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      final timeStr = instance.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
          : '';
      return '$formattedDate$timeStr';
    }
    if (instance.hasDueTime()) {
      return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
    }
    return '';
  }

  static String getCategoryColor({
    required ActivityInstanceRecord instance,
    required List<CategoryRecord> categories,
  }) {
    try {
      final category =
          categories.firstWhere((c) => c.name == instance.templateCategoryName);
      return category.color;
    } catch (e) {
      return '#000000';
    }
  }

  static Widget buildShowOlderButtons({
    required BuildContext context,
    required int completionTimeFrame,
    required Function(int) onTimeFrameChanged,
    required Function() onCacheInvalidate,
    required StateSetter setState,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Show fewer button (when not at minimum)
          if (completionTimeFrame > 2) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  onTimeFrameChanged(completionTimeFrame == 30 ? 7 : 2);
                  // Invalidate cache when completion time frame changes
                  onCacheInvalidate();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.alternate,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 16,
                      color: theme.secondaryText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show fewer (${completionTimeFrame == 30 ? '7 days' : '2 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Show older button (when not at maximum)
          if (completionTimeFrame < 30) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  onTimeFrameChanged(completionTimeFrame == 2 ? 7 : 30);
                  // Invalidate cache when completion time frame changes
                  onCacheInvalidate();
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 16,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Show older (${completionTimeFrame == 2 ? '7 days' : '30 days'})',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool isTaskCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed';
  }

  static void applySort({
    required List<dynamic> items,
    required String sortMode,
  }) {
    if (sortMode != 'importance') return;
    int cmpTask(ActivityInstanceRecord a, ActivityInstanceRecord b) {
      final ap = a.templatePriority;
      final bp = b.templatePriority;
      if (bp != ap) return bp.compareTo(ap);
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.templateName
          .toLowerCase()
          .compareTo(b.templateName.toLowerCase());
    }

    items.sort((x, y) {
      final xt = x is ActivityInstanceRecord;
      final yt = y is ActivityInstanceRecord;
      if (xt && yt) return cmpTask(x, y);
      if (xt && !yt) return -1;
      if (!xt && yt) return 1;
      return 0;
    });
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
