import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/morning_catchup_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/historical_edit_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:intl/intl.dart';

/// Morning catch-up dialog for handling yesterday's incomplete items
class MorningCatchUpDialog extends StatefulWidget {
  const MorningCatchUpDialog({super.key});

  @override
  State<MorningCatchUpDialog> createState() => _MorningCatchUpDialogState();
}

class _MorningCatchUpDialogState extends State<MorningCatchUpDialog> {
  bool _isLoading = true;
  bool _isProcessing = false;
  List<ActivityInstanceRecord> _items = [];
  final Set<String> _processedItemIds = {};
  int _reminderCount = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadReminderCount();
  }

  Future<void> _loadReminderCount() async {
    final count = await MorningCatchUpService.getReminderCount();
    if (mounted) {
      setState(() {
        _reminderCount = count;
      });
    }
  }

  Future<void> _loadItems() async {
    try {
      final userId = currentUserUid;
      final items =
          await MorningCatchUpService.getIncompleteItemsFromYesterday(userId);
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  /// Handle instance updates from ItemComponent
  /// This intercepts completions and skips to backdate them to yesterday
  Future<void> _handleInstanceUpdated(
      ActivityInstanceRecord updatedInstance) async {
    if (_processedItemIds.contains(updatedInstance.reference.id)) return;

    final yesterday = DateService.yesterdayStart;
    final yesterdayEnd =
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final today = DateService.todayStart;
    bool needsRecalculation = false;

    try {
      // Check if item was just completed and needs backdating
      if (updatedInstance.status == 'completed' &&
          updatedInstance.completedAt != null) {
        final completedAt = updatedInstance.completedAt!;
        // If completed today, backdate to yesterday
        if (completedAt.isAfter(today)) {
          needsRecalculation = true;

          await ActivityInstanceService.completeInstanceWithBackdate(
            instanceId: updatedInstance.reference.id,
            finalValue: updatedInstance.currentValue,
            completedAt: yesterdayEnd,
          );
        } else {
          // Already backdated or completed yesterday, just mark as processed
          needsRecalculation = true;
        }
      }

      // Check if item was just skipped and needs backdating
      if (updatedInstance.status == 'skipped' &&
          updatedInstance.skippedAt != null) {
        final skippedAt = updatedInstance.skippedAt!;
        // If skipped today, backdate to yesterday
        if (skippedAt.isAfter(today)) {
          needsRecalculation = true;

          await ActivityInstanceService.skipInstance(
            instanceId: updatedInstance.reference.id,
            skippedAt: yesterdayEnd,
          );
        } else {
          // Already backdated or skipped yesterday, just mark as processed
          needsRecalculation = true;
        }
      }

      // If item was snoozed, just mark as processed (no backdating needed)
      if (updatedInstance.status == 'snoozed') {
        needsRecalculation =
            false; // Snooze doesn't affect yesterday's progress
      }

      // Recalculate yesterday's progress if needed
      if (needsRecalculation) {
        await HistoricalEditService.recalculateDailyProgress(
          userId: currentUserUid,
          date: yesterday,
        );
      }

      // Mark as processed
      setState(() {
        _processedItemIds.add(updatedInstance.reference.id);
      });

      // Reset reminder count when user completes/skips items
      await MorningCatchUpService.resetReminderCount();
      await _loadReminderCount();

      // Reload items to get updated instances
      await _loadItems();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing item: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    }
  }

  Future<void> _skipAllRemaining() async {
    final remainingHabits = _items
        .where((item) => !_processedItemIds.contains(item.reference.id) && 
            item.templateCategoryType == 'habit')
        .toList();

    if (remainingHabits.isEmpty) {
      // If no habits to skip, just close or notify user
      Navigator.of(context).pop();
      return;
    }

    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip All Remaining?'),
        content: Text(
          'This will mark ${remainingHabits.length} habit${remainingHabits.length == 1 ? '' : 's'} as skipped for yesterday. Tasks will remain pending.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: FlutterFlowTheme.of(context).error,
            ),
            child: const Text('Skip All'),
          ),
        ],
      ),
    );

    if (shouldSkip != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final yesterday = DateService.yesterdayStart;
      final yesterdayEnd =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);

      // Skip all remaining habits
      for (final item in remainingHabits) {
        await ActivityInstanceService.skipInstance(
          instanceId: item.reference.id,
          skippedAt: yesterdayEnd,
        );
        _processedItemIds.add(item.reference.id);
      }

      // Wait a moment to ensure all database updates are committed
      await Future.delayed(const Duration(milliseconds: 500));

      // Recalculate yesterday's progress once
      await HistoricalEditService.recalculateDailyProgress(
        userId: currentUserUid,
        date: yesterday,
      );

      // Reset reminder count when user skips all items
      await MorningCatchUpService.resetReminderCount();
      await MorningCatchUpService.markDialogAsShown();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${remainingHabits.length} habit${remainingHabits.length == 1 ? '' : 's'} marked as skipped'),
            backgroundColor: FlutterFlowTheme.of(context).success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error skipping items: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _snoozeDialog() async {
    final reminderCount = await MorningCatchUpService.getReminderCount();
    await MorningCatchUpService.snoozeDialog();
    await MorningCatchUpService.markDialogAsShown();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'You\'ll be reminded on your next app open${reminderCount >= 2 ? ' (${reminderCount + 1} of ${MorningCatchUpService.maxReminderCount} reminders)' : ''}'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final yesterday = DateService.yesterdayStart;
    final yesterdayLabel = DateFormat('EEEE, MMM d').format(yesterday);

    final remainingItems = _items
        .where((item) => !_processedItemIds.contains(item.reference.id))
        .toList();

    return WillPopScope(
      onWillPop: () async {
        // Prevent dismissing - user must choose skip or remind me later
        return false;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catch Up on Yesterday',
                      style: theme.headlineMedium.override(
                        fontFamily: 'Outfit',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      yesterdayLabel,
                      style: theme.bodyMedium.override(
                        fontFamily: 'Readex Pro',
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'You have incomplete habits from yesterday. If you completed them but forgot to mark them, mark them as complete. Otherwise, use skip or snooze to handle them. Incomplete tasks will remain pending.',
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (remainingItems.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 64,
                          color: theme.success,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'All items processed!',
                          style: theme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ve handled all incomplete items',
                          style: theme.bodyMedium.override(
                            fontFamily: 'Readex Pro',
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: remainingItems.length,
                    itemBuilder: (context, index) {
                      final item = remainingItems[index];
                      final isHabit = item.templateCategoryType == 'habit';
                      return ItemComponent(
                        key: Key(item.reference.id),
                        instance: item,
                        categoryColorHex: item.templateCategoryColor,
                        onRefresh: _loadItems,
                        onInstanceUpdated: _handleInstanceUpdated,
                        onInstanceDeleted: (deletedInstance) {
                          setState(() {
                            _processedItemIds.add(deletedInstance.reference.id);
                          });
                          _loadItems();
                        },
                        onHabitUpdated: (_) {},
                        onHabitDeleted: (_) async => _loadItems(),
                        isHabit: isHabit,
                        showTypeIcon: true,
                        showRecurringIcon: true,
                        showCompleted: false,
                        page: 'catchup',
                      );
                    },
                  ),
                ),

              // Footer buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  border: Border(
                    top: BorderSide(
                      color: theme.alternate,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (remainingItems.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _skipAllRemaining,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Skip All Remaining'),
                        ),
                      ),
                    if (remainingItems.isNotEmpty) const SizedBox(height: 8),
                    // Only show "Remind Me Later" if reminder count < 3
                    if (_reminderCount < MorningCatchUpService.maxReminderCount)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isProcessing ? null : _snoozeDialog,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Remind Me Later'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
