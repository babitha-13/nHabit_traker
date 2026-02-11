import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Item_component/item_component_main.dart';
import 'package:habit_tracker/Screens/CatchUp/morning_catchup_logic.dart';
import 'package:intl/intl.dart';

/// Morning catch-up dialog for handling yesterday's incomplete items
/// UI-only component - business logic is in MorningCatchUpDialogLogic
class MorningCatchUpDialog extends StatefulWidget {
  const MorningCatchUpDialog({
    super.key,
    this.isDayTransition = false,
  });

  final bool isDayTransition;

  @override
  State<MorningCatchUpDialog> createState() => _MorningCatchUpDialogState();
}

class _MorningCatchUpDialogState extends State<MorningCatchUpDialog> {
  late final MorningCatchUpDialogLogic _logic;

  @override
  void initState() {
    super.initState();
    _logic = MorningCatchUpDialogLogic();
    _initializeDialog();
  }

  Future<void> _initializeDialog() async {
    try {
      await _logic.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Note: saveStateOnDispose is called explicitly in _closeDialogAndRefresh
    // and other close paths to ensure recalculation completes before showing toasts
    super.dispose();
  }

  /// Close dialog and trigger refresh of habit and queue pages
  /// Closes immediately, runs background operations after dismissal
  Future<void> _closeDialogAndRefresh() async {
    // Close dialog immediately - don't wait for background operations
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Run all background operations after dialog is dismissed
    // This allows user to continue using the app while these complete
    _runBackgroundOperations();
  }

  /// Run background operations after dialog closes
  /// Includes: ensuring instances exist, saving progress, showing toasts
  Future<void> _runBackgroundOperations() async {
    try {
      // Ensure all instances exist (background operation)
      await _logic.ensureInstancesExistInBackground();

      // Save state and recalculate progress (background operation)
      await _logic.saveStateOnDispose();

      // Prepare for close (triggers refresh notifications)
      await _logic.prepareForClose();

      // Show pending toasts after all background operations complete
      MorningCatchUpService.showPendingToasts();
    } catch (e) {
      // Silent error handling - background operations shouldn't affect user experience
      print('Error in background operations after dialog close: $e');
      // Still try to show toasts even if other operations failed
      MorningCatchUpService.showPendingToasts();
    }
  }

  /// Handle instance updates from ItemComponent
  Future<void> _handleInstanceUpdated(
      ActivityInstanceRecord updatedInstance) async {
    try {
      await _logic.handleInstanceUpdated(updatedInstance);
      // Always update UI after instance update (handles both progress and status changes)
      if (mounted) {
        setState(() {});
      }

      // Auto-close dialog if all items are processed
      if (mounted) {
        final shouldAutoClose = await _logic.checkAndAutoClose();
        if (shouldAutoClose) {
          // Close immediately, background operations run after
          await _closeDialogAndRefresh();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing item: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _skipAllRemaining() async {
    final remainingHabits = _logic.items
        .where((item) =>
            !_logic.processedItemIds.contains(item.reference.id) &&
            item.templateCategoryType == 'habit')
        .toList();

    if (remainingHabits.isEmpty) {
      // If no habits to skip, just close
      await _closeDialogAndRefresh();
      return;
    }

    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip All Remaining Habits'),
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

    if (shouldSkip != true) {
      // User canceled - still ensure record exists
      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        await MorningCatchUpService.createDailyProgressRecordForDate(
          userId: userId,
          targetDate: DateService.yesterdayStart,
        );
      } catch (e) {
        print('Error creating record after cancel: $e');
      }
      return;
    }

    if (!mounted) return;

    // Update UI to show processing state
    setState(() {});

    try {
      final result = await _logic.skipAllRemaining(
        onProgressUpdate: () {
          // Rebuild UI during processing to show progress updates
          if (mounted) {
            setState(() {});
          }
        },
      );

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${result.skippedCount} habit${result.skippedCount == 1 ? '' : 's'} marked as skipped'),
              backgroundColor: FlutterFlowTheme.of(context).success,
            ),
          );

          if (!result.hasRemainingItems) {
            // All items processed, close dialog immediately
            // Background operations will run after dismissal
            await _closeDialogAndRefresh();
          } else {
            // Still have items, update UI to show them
            setState(() {});
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Error skipping items: ${result.error ?? 'Unknown error'}'),
              backgroundColor: FlutterFlowTheme.of(context).error,
            ),
          );
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error skipping items: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _snoozeDialog() async {
    try {
      final result = await _logic.snoozeDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You\'ll be reminded on your next app open${result.newReminderCount >= MorningCatchUpService.maxReminderCount ? ' (${result.newReminderCount} of ${MorningCatchUpService.maxReminderCount} reminders)' : ''}'),
          ),
        );
        // Close immediately, background operations run after
        await _closeDialogAndRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error snoozing dialog: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    }
  }

  Future<void> _reloadItems() async {
    try {
      await _logic.loadItems();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final yesterday = DateService.yesterdayStart;
    final yesterdayLabel = DateFormat('EEEE, MMM d').format(yesterday);
    final yesterdayEnd = DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
      23,
      59,
      59,
    );

    final remainingItems = _logic.getRemainingItems();
    final processingCount = _logic.getProcessingCount();

    return WillPopScope(
      onWillPop: () async {
        // Allow dismissal if all items are processed (including optimistic ones)
        if (_logic.canCloseDialog()) {
          // Mark dialog as shown immediately
          await MorningCatchUpService.markDialogAsShown();
          // Return true to allow dismissal - background operations will run after
          // Schedule background operations to run after dialog closes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _runBackgroundOperations();
          });
          return true;
        }
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
                        widget.isDayTransition
                            ? 'A new day just started. Please review yesterday\'s items and update anything you missed.'
                            : 'You have incomplete items from yesterday. Review them and mark them individually as completed/skipped or reschedule them for later.',
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
              if (_logic.isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_logic.isProcessing)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _logic.processingStatus,
                          style: theme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        if (_logic.totalToProcess > 0) ...[
                          const SizedBox(height: 16),
                          Text(
                            '${_logic.processedCount} of ${_logic.totalToProcess} completed',
                            style: theme.bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              color: theme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _logic.totalToProcess > 0
                                ? _logic.processedCount / _logic.totalToProcess
                                : 0,
                            backgroundColor: theme.alternate,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(theme.primary),
                          ),
                        ],
                      ],
                    ),
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
                        onRefresh: _reloadItems,
                        onInstanceUpdated: _handleInstanceUpdated,
                        onInstanceDeleted: (deletedInstance) {
                          // Optimistically remove deleted item immediately
                          _logic.handleInstanceDeleted(deletedInstance);
                          setState(() {});
                          // Clear optimistic state after a brief delay (item is already deleted)
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              _logic.clearOptimisticState(
                                  deletedInstance.reference.id);
                              // Reload to ensure UI is in sync
                              _reloadItems();
                            }
                          });
                        },
                        onHabitUpdated: (_) {},
                        onHabitDeleted: (_) async => _reloadItems(),
                        isHabit: isHabit,
                        showTypeIcon: true,
                        showRecurringIcon: true,
                        showCompleted: false,
                        page: 'catchup',
                        progressReferenceTime: yesterdayEnd,
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
                    // Show processing status if items are syncing
                    if (processingCount > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.primary.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Syncing $processingCount item${processingCount == 1 ? '' : 's'}...',
                              style: theme.bodySmall.override(
                                fontFamily: 'Readex Pro',
                                color: theme.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (remainingItems.isEmpty && !_logic.isLoading)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            // Mark dialog as shown immediately
                            await MorningCatchUpService.markDialogAsShown();
                            if (mounted) {
                              // Close immediately, background operations run after
                              await _closeDialogAndRefresh();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Close'),
                        ),
                      )
                    else if (!_logic.isLoading) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_logic.isProcessing || processingCount > 0)
                                  ? null
                                  : _skipAllRemaining,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Skip All Remaining'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Only show "Remind Me Later" if reminder count is below the limit
                      if (_logic.reminderCount <
                          MorningCatchUpService.maxReminderCount)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed:
                                (_logic.isProcessing || processingCount > 0)
                                    ? null
                                    : _snoozeDialog,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Remind Me Later'),
                          ),
                        ),
                    ],
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
