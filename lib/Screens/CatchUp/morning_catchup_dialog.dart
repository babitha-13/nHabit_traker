import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/morning_catchup_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
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
  // Optimistic UI tracking
  final Set<String> _optimisticProcessingIds = {};
  final Map<String, ActivityInstanceRecord> _optimisticSnapshots = {};
  int _reminderCount = 0;
  String _processingStatus = '';
  int _processedCount = 0;
  int _totalToProcess = 0;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _loadReminderCount();
    // Mark as shown immediately to prevent re-showing
    MorningCatchUpService.markDialogAsShown();
    _ensureRecordCreated();
    // Ensure instances exist when dialog opens (handles edge cases)
    _ensureInstancesExist();
  }

  Future<void> _ensureInstancesExist() async {
    try {
      await MorningCatchUpService.ensurePendingInstancesExist(currentUserUid);
      // Reload items after ensuring instances exist
      if (mounted) {
        await _loadItems();
      }
    } catch (e) {
      print('Error ensuring instances exist in dialog: $e');
    }
  }

  @override
  void dispose() {
    // Ensure state is saved even if dialog is force-closed
    try {
      // If items were processed, recalculate the record to ensure cumulative score is updated
      if (_processedItemIds.isNotEmpty) {
        MorningCatchUpService.recalculateDailyProgressRecordForDate(
          userId: currentUserUid,
          targetDate: DateService.yesterdayStart,
        ).catchError((e) => print('Error recalculating record in dispose: $e'));
      } else if (_items.isNotEmpty) {
        // If dialog is closed without action, ensure record exists
        MorningCatchUpService.createDailyProgressRecordForDate(
          userId: currentUserUid,
          targetDate: DateService.yesterdayStart,
        ).catchError((e) => print('Error in dispose: $e'));
      }
    } catch (e) {
      print('Error in dispose: $e');
    }
    super.dispose();
  }

  Future<void> _ensureRecordCreated() async {
    try {
      final yesterday = DateService.yesterdayStart;
      // Check if record exists, create if not
      await MorningCatchUpService.createDailyProgressRecordForDate(
        userId: currentUserUid,
        targetDate: yesterday,
      );
    } catch (e) {
      print('Error ensuring record creation: $e');
      // Don't block dialog if record creation fails
    }
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
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading items: $e')),
        );
      }
    }
  }

  /// Apply optimistic UI update - removes item from list immediately
  void _applyOptimisticState(ActivityInstanceRecord instance) {
    if (!mounted) return;

    // Save snapshot for potential rollback
    _optimisticSnapshots[instance.reference.id] = instance;

    setState(() {
      _optimisticProcessingIds.add(instance.reference.id);
      _processedItemIds.add(instance.reference.id);
    });
  }

  /// Revert optimistic UI update - restores item if backend operation failed
  void _revertOptimisticState(String instanceId) {
    if (!mounted) return;

    final originalInstance = _optimisticSnapshots[instanceId];
    if (originalInstance == null) return;

    setState(() {
      _optimisticProcessingIds.remove(instanceId);
      _processedItemIds.remove(instanceId);
      _optimisticSnapshots.remove(instanceId);

      // Restore item to list if it still exists and wasn't replaced
      final exists = _items.any((item) => item.reference.id == instanceId);
      if (!exists) {
        // Item was removed, try to restore from snapshot
        // Find insertion point (maintain order if possible)
        _items.add(originalInstance);
        // Sort by template name to maintain some order
        _items.sort((a, b) => a.templateName.compareTo(b.templateName));
      }
    });
  }

  /// Clear optimistic state after successful backend operation
  void _clearOptimisticState(String instanceId) {
    if (!mounted) return;

    setState(() {
      _optimisticProcessingIds.remove(instanceId);
      _optimisticSnapshots.remove(instanceId);
    });
  }

  /// Handle instance updates from ItemComponent
  /// This intercepts completions and skips to backdate them to yesterday
  /// Uses optimistic UI updates for instant feedback
  Future<void> _handleInstanceUpdated(
      ActivityInstanceRecord updatedInstance) async {
    final instanceId = updatedInstance.reference.id;

    // Prevent duplicate processing
    if (_processedItemIds.contains(instanceId) ||
        _optimisticProcessingIds.contains(instanceId)) {
      return;
    }

    // OPTIMISTIC UPDATE: Apply UI changes immediately
    _applyOptimisticState(updatedInstance);

    final yesterday = DateService.yesterdayStart;
    final yesterdayEnd =
        DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    final today = DateService.todayStart;

    // Process backend operations asynchronously
    try {
      // Check if item was just completed and needs backdating
      if (updatedInstance.status == 'completed' &&
          updatedInstance.completedAt != null) {
        final completedAt = updatedInstance.completedAt!;
        // If completed today, backdate to yesterday
        if (completedAt.isAfter(today)) {
          await ActivityInstanceService.completeInstanceWithBackdate(
            instanceId: instanceId,
            finalValue: updatedInstance.currentValue,
            completedAt: yesterdayEnd,
          );
        }
      }

      // Check if item was just skipped and needs backdating
      if (updatedInstance.status == 'skipped' &&
          updatedInstance.skippedAt != null) {
        final skippedAt = updatedInstance.skippedAt!;
        // If skipped today, backdate to yesterday
        if (skippedAt.isAfter(today)) {
          await ActivityInstanceService.skipInstance(
            instanceId: instanceId,
            skippedAt: yesterdayEnd,
          );
        }
      }

      // Reset reminder count when user completes/skips items
      await MorningCatchUpService.resetReminderCount();
      if (mounted) {
        await _loadReminderCount();
      }

      // Clear optimistic state now that backend operation succeeded
      _clearOptimisticState(instanceId);

      // Only reload if we need to check for new instances (e.g., habit completion may create new instance)
      // For most cases, optimistic removal is sufficient
      if (updatedInstance.templateCategoryType == 'habit' &&
          updatedInstance.status == 'completed') {
        // Habits may generate new instances, so reload
        await _loadItems();
      }

      // RECALCULATE daily progress record in background after user completes/skips items
      // This ensures cumulative score includes the user's updates
      // Run in background without blocking UI - fire and forget with error handling
      Future.delayed(const Duration(milliseconds: 300)).then((_) {
        // Background recalculation - don't await, let it run asynchronously
        MorningCatchUpService.recalculateDailyProgressRecordForDate(
          userId: currentUserUid,
          targetDate: yesterday,
        ).catchError((error) {
          // Silent error handling - recalculation failure shouldn't affect UI
          // The record will be recalculated when dialog closes anyway
          print('Background recalculation error (non-critical): $error');
        });
      });

      // Auto-close dialog if all items are processed
      if (mounted) {
        final remainingAfterUpdate = _items
            .where((item) =>
                !_processedItemIds.contains(item.reference.id) &&
                !_optimisticProcessingIds.contains(item.reference.id))
            .toList();
        if (remainingAfterUpdate.isEmpty) {
          // Wait a brief moment for any final state updates
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            final finalRemaining = _items
                .where((item) =>
                    !_processedItemIds.contains(item.reference.id) &&
                    !_optimisticProcessingIds.contains(item.reference.id))
                .toList();
            if (finalRemaining.isEmpty) {
              await MorningCatchUpService.markDialogAsShown();
              Navigator.of(context).pop();
            }
          }
        }
      }
    } catch (e) {
      // ROLLBACK: Revert optimistic update on error
      _revertOptimisticState(instanceId);

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
        .where((item) =>
            !_processedItemIds.contains(item.reference.id) &&
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
        await MorningCatchUpService.createDailyProgressRecordForDate(
          userId: currentUserUid,
          targetDate: DateService.yesterdayStart,
        );
      } catch (e) {
        print('Error creating record after cancel: $e');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _totalToProcess = remainingHabits.length;
      _processedCount = 0;
      _processingStatus = 'Preparing to skip habits...';
    });

    try {
      final yesterday = DateService.yesterdayStart;
      final yesterdayEnd =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);

      // Skip all remaining habits with progress updates
      for (int i = 0; i < remainingHabits.length; i++) {
        final item = remainingHabits[i];
        if (mounted) {
          setState(() {
            _processingStatus =
                'Skipping ${item.templateName} (${i + 1}/${remainingHabits.length})...';
          });
        }

        await ActivityInstanceService.skipInstance(
          instanceId: item.reference.id,
          skippedAt: yesterdayEnd,
        );
        _processedItemIds.add(item.reference.id);

        if (mounted) {
          setState(() {
            _processedCount = i + 1;
          });
        }
      }

      // Ensure all active habits have pending instances (fixes stuck instances issue)
      if (mounted) {
        setState(() {
          _processingStatus = 'Ensuring all habits have current instances...';
        });
      }
      await MorningCatchUpService.ensurePendingInstancesExist(currentUserUid);

      // Wait a moment to ensure all database updates are committed
      if (mounted) {
        setState(() {
          _processingStatus = 'Finalizing...';
        });
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // Reload items to reflect the new instances that were generated
      if (mounted) {
        setState(() {
          _processingStatus = 'Refreshing...';
        });
      }
      await _loadItems();

      // Broadcast progress recalculated to refresh other parts of UI
      InstanceEvents.broadcastProgressRecalculated();

      // Create daily progress record for yesterday using new method with full breakdown
      if (mounted) {
        setState(() {
          _processingStatus = 'Creating daily progress record...';
        });
      }
      await MorningCatchUpService.createDailyProgressRecordForDate(
        userId: currentUserUid,
        targetDate: yesterday,
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

        // Check if there are still remaining items after reload
        final updatedRemainingItems = _items
            .where((item) => !_processedItemIds.contains(item.reference.id))
            .toList();

        if (updatedRemainingItems.isEmpty) {
          // All items processed, close dialog
          Navigator.of(context).pop();
        } else {
          // Still have items, update UI to show them
          setState(() {
            _isProcessing = false;
            _processingStatus = '';
            _processedCount = 0;
            _totalToProcess = 0;
          });
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
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStatus = '';
          _processedCount = 0;
          _totalToProcess = 0;
        });
      }
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
        .where((item) =>
            !_processedItemIds.contains(item.reference.id) &&
            !_optimisticProcessingIds.contains(item.reference.id))
        .toList();

    final processingCount = _optimisticProcessingIds.length;

    return WillPopScope(
      onWillPop: () async {
        // Allow dismissal if all items are processed (including optimistic ones)
        if (remainingItems.isEmpty && processingCount == 0) {
          // Start recalculation in background before closing (non-blocking)
          if (_processedItemIds.isNotEmpty) {
            MorningCatchUpService.recalculateDailyProgressRecordForDate(
              userId: currentUserUid,
              targetDate: DateService.yesterdayStart,
            ).catchError((error) {
              // Silent error handling - recalculation failure shouldn't block dialog close
              print('Background recalculation error on close (non-critical): $error');
            });
          }
          await MorningCatchUpService.markDialogAsShown();
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
                        'You have incomplete items from yesterday. Review them and mark them individually as completed/skipped or reschedule them for later.',
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
              else if (_isProcessing)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          _processingStatus,
                          style: theme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        if (_totalToProcess > 0) ...[
                          const SizedBox(height: 16),
                          Text(
                            '${_processedCount} of ${_totalToProcess} completed',
                            style: theme.bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              color: theme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _totalToProcess > 0
                                ? _processedCount / _totalToProcess
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
                        onRefresh: _loadItems,
                        onInstanceUpdated: _handleInstanceUpdated,
                        onInstanceDeleted: (deletedInstance) {
                          // Optimistically remove deleted item immediately
                          _applyOptimisticState(deletedInstance);
                          // Clear optimistic state after a brief delay (item is already deleted)
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) {
                              _clearOptimisticState(
                                  deletedInstance.reference.id);
                              // Reload to ensure UI is in sync
                              _loadItems();
                            }
                          });
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
                    if (remainingItems.isEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            // Start recalculation in background before closing (non-blocking)
                            if (_processedItemIds.isNotEmpty) {
                              MorningCatchUpService.recalculateDailyProgressRecordForDate(
                                userId: currentUserUid,
                                targetDate: DateService.yesterdayStart,
                              ).catchError((error) {
                                // Silent error handling - recalculation failure shouldn't block dialog close
                                print('Background recalculation error on close (non-critical): $error');
                              });
                            }
                            await MorningCatchUpService.markDialogAsShown();
                            if (mounted) {
                              Navigator.of(context).pop();
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
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_isProcessing || processingCount > 0)
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
                      // Only show "Remind Me Later" if reminder count < 3
                      if (_reminderCount <
                          MorningCatchUpService.maxReminderCount)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: (_isProcessing || processingCount > 0)
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
