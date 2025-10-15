import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/instance_date_calculator.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service to manage activity instances
/// Handles the creation, completion, and scheduling of recurring activities
/// Following Microsoft To-Do pattern: only show current instances, generate next on completion
class ActivityInstanceService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  // ==================== INSTANCE CREATION ====================

  /// Create a new activity instance from a template
  /// This is the core method for Phase 1 - instance creation
  static Future<DocumentReference> createActivityInstance({
    required String templateId,
    DateTime? dueDate,
    required ActivityRecord template,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    final now = DateService.currentDate;

    print(
        'ActivityInstanceService: Creating instance for template $templateId');
    print('ActivityInstanceService: User ID: $uid');
    print('ActivityInstanceService: Template name: ${template.name}');

    // Calculate initial due date using the helper
    final DateTime? initialDueDate = dueDate ??
        InstanceDateCalculator.calculateInitialDueDate(
          template: template,
          explicitDueDate: null,
        );
    print('ActivityInstanceService: Initial due date: $initialDueDate');

    // For habits, set belongsToDate to the normalized date
    final normalizedDate = initialDueDate != null
        ? DateTime(
            initialDueDate.year, initialDueDate.month, initialDueDate.day)
        : DateTime(now.year, now.month, now.day);

    // Calculate window fields for habits
    DateTime? windowEndDate;
    int? windowDuration;
    if (template.categoryType == 'habit') {
      windowDuration = _calculateWindowDuration(template);
      windowEndDate = normalizedDate.add(Duration(days: windowDuration - 1));
    }

    final instanceData = createActivityInstanceRecordData(
      templateId: templateId,
      dueDate: initialDueDate,
      status: 'pending',
      createdTime: now,
      lastUpdated: now,
      isActive: true,
      lastDayValue: 0, // Initialize for differential tracking
      // Cache template data for quick access (denormalized)
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: template.categoryType,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateTarget: template.target,
      templateUnit: template.unit,
      templateDescription: template.description,
      templateShowInFloatingTimer: template.showInFloatingTimer,
      templateEveryXValue: template.everyXValue,
      templateEveryXPeriodType: template.everyXPeriodType,
      templateTimesPerPeriod: template.timesPerPeriod,
      templatePeriodType: template.periodType,
      // Set habit-specific fields
      completionStatus: template.categoryType == 'habit' ? 'pending' : null,
      dayState: template.categoryType == 'habit' ? 'open' : null,
      belongsToDate: template.categoryType == 'habit' ? normalizedDate : null,
      windowEndDate: windowEndDate,
      windowDuration: windowDuration,
    );

    print(
        'ActivityInstanceService: Instance data prepared, adding to Firestore...');
    final result =
        await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);
    print('ActivityInstanceService: Instance created with ID: ${result.id}');

    return result;
  }

  // ==================== INSTANCE QUERYING ====================

  /// Get active task instances for the user
  /// This is the core method for Phase 2 - displaying instances
  /// It returns only the earliest pending instance for each task template
  static Future<List<ActivityInstanceRecord>> getActiveTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      print(
          'ActivityInstanceService: Getting active task instances for user $uid');

      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'task')
          .where('status', isEqualTo: 'pending');

      final result = await query.get();
      final allPendingInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      print(
          'ActivityInstanceService: Found ${allPendingInstances.length} total pending task instances.');

      // Group instances by templateId and keep only the one with the earliest due date
      final Map<String, ActivityInstanceRecord> earliestInstances = {};
      for (final instance in allPendingInstances) {
        final templateId = instance.templateId;
        if (!earliestInstances.containsKey(templateId)) {
          earliestInstances[templateId] = instance;
        } else {
          final existing = earliestInstances[templateId]!;
          // Handle null due dates: nulls go last
          if (existing.dueDate == null) {
            // Keep existing (null), unless new also has a date
            if (instance.dueDate != null) {
              earliestInstances[templateId] = instance;
            }
          } else if (instance.dueDate == null) {
            // Keep existing (has date)
            continue;
          } else {
            // Both have dates, compare normally
            if (instance.dueDate!.isBefore(existing.dueDate!)) {
              earliestInstances[templateId] = instance;
            }
          }
        }
      }

      final finalInstanceList = earliestInstances.values.toList();

      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      print(
          'ActivityInstanceService: Returning ${finalInstanceList.length} unique task instances.');

      return finalInstanceList;
    } catch (e) {
      print('Error getting active task instances: $e');
      return [];
    }
  }

  /// Get all task instances (active and completed) for Recent Completions
  static Future<List<ActivityInstanceRecord>> getAllTaskInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      print(
          'ActivityInstanceService: Getting all task instances for user $uid');

      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'task');

      final result = await query.get();
      final allInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      print(
          'ActivityInstanceService: Found ${allInstances.length} total task instances (all statuses)');

      // Group instances by templateId and keep only the one with the earliest due date
      final Map<String, ActivityInstanceRecord> earliestInstances = {};
      for (final instance in allInstances) {
        final templateId = instance.templateId;
        if (!earliestInstances.containsKey(templateId)) {
          earliestInstances[templateId] = instance;
        } else {
          final existing = earliestInstances[templateId]!;
          // Handle null due dates: nulls go last
          if (instance.dueDate == null && existing.dueDate == null) {
            // Both null, keep existing
            continue;
          } else if (instance.dueDate == null) {
            // New is null, keep existing
            continue;
          } else if (existing.dueDate == null) {
            // Existing is null, replace with new
            earliestInstances[templateId] = instance;
          } else {
            // Both have dates, compare
            if (instance.dueDate!.isBefore(existing.dueDate!)) {
              earliestInstances[templateId] = instance;
            }
          }
        }
      }

      final finalInstanceList = earliestInstances.values.toList();

      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      print(
          'ActivityInstanceService: Returning ${finalInstanceList.length} unique task instances (all statuses)');

      return finalInstanceList;
    } catch (e) {
      print('Error getting all task instances: $e');
      return [];
    }
  }

  /// Get active habit instances for the user
  static Future<List<ActivityInstanceRecord>> getActiveHabitInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      print(
          'ActivityInstanceService: Getting active habit instances for user $uid');
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateCategoryType', isEqualTo: 'habit')
          .where('status', isEqualTo: 'pending');

      final result = await query.get();
      final allPendingInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      print(
          'ActivityInstanceService: Found ${allPendingInstances.length} total pending habit instances.');

      // Group instances by templateId and keep only the one with the earliest due date
      final Map<String, ActivityInstanceRecord> earliestInstances = {};
      for (final instance in allPendingInstances) {
        final templateId = instance.templateId;
        if (!earliestInstances.containsKey(templateId)) {
          earliestInstances[templateId] = instance;
        } else {
          final existing = earliestInstances[templateId]!;
          // Handle null due dates: nulls go last
          if (existing.dueDate == null) {
            // Keep existing (null), unless new also has a date
            if (instance.dueDate != null) {
              earliestInstances[templateId] = instance;
            }
          } else if (instance.dueDate == null) {
            // Keep existing (has date)
            continue;
          } else {
            // Both have dates, compare normally
            if (instance.dueDate!.isBefore(existing.dueDate!)) {
              earliestInstances[templateId] = instance;
            }
          }
        }
      }

      final finalInstanceList = earliestInstances.values.toList();

      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      print(
          'ActivityInstanceService: Returning ${finalInstanceList.length} unique habit instances.');

      // Debug: Log each instance being returned
      for (final instance in finalInstanceList) {
        print(
            'ActivityInstanceService: Returning instance ${instance.templateName}');
        print('  - Instance ID: ${instance.reference.id}');
        print('  - Due Date: ${instance.dueDate}');
        print('  - Window End Date: ${instance.windowEndDate}');
        print('  - Current Value: ${instance.currentValue}');
        print('  - Status: ${instance.status}');
        print('  - Belongs To Date: ${instance.belongsToDate}');
      }

      return finalInstanceList;
    } catch (e) {
      print('Error getting active habit instances: $e');
      return [];
    }
  }

  /// Get all active instances for a user (tasks and habits)
  static Future<List<ActivityInstanceRecord>> getAllActiveInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      print(
          'ActivityInstanceService: Getting all active instances for user $uid');
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('status', isEqualTo: 'pending');

      final result = await query.get();
      final allPendingInstances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      print(
          'ActivityInstanceService: Found ${allPendingInstances.length} total pending instances.');

      // Group instances by templateId and keep only the one with the earliest due date
      final Map<String, ActivityInstanceRecord> earliestInstances = {};
      for (final instance in allPendingInstances) {
        final templateId = instance.templateId;
        if (!earliestInstances.containsKey(templateId)) {
          earliestInstances[templateId] = instance;
        } else {
          final existing = earliestInstances[templateId]!;
          // Handle null due dates: nulls go last
          if (existing.dueDate == null) {
            // Keep existing (null), unless new also has a date
            if (instance.dueDate != null) {
              earliestInstances[templateId] = instance;
            }
          } else if (instance.dueDate == null) {
            // Keep existing (has date)
            continue;
          } else {
            // Both have dates, compare normally
            if (instance.dueDate!.isBefore(existing.dueDate!)) {
              earliestInstances[templateId] = instance;
            }
          }
        }
      }

      final finalInstanceList = earliestInstances.values.toList();

      // Sort: instances with due dates first (oldest first), then nulls last
      finalInstanceList.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1; // a goes after b
        if (b.dueDate == null) return -1; // a goes before b
        return a.dueDate!.compareTo(b.dueDate!);
      });

      print(
          'ActivityInstanceService: Returning ${finalInstanceList.length} unique instances.');

      return finalInstanceList;
    } catch (e) {
      print('Error getting all active instances: $e');
      return [];
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Test method to manually create an instance (for debugging)
  static Future<void> testCreateInstance({
    required String templateId,
    String? userId,
  }) async {
    try {
      print('Testing instance creation for template: $templateId');

      // Get the template
      final uid = userId ?? _currentUserId;
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);

      print('Template found: ${template.name}');

      // Create instance
      final instanceRef = await createActivityInstance(
        templateId: templateId,
        template: template,
        userId: uid,
      );

      print('Instance created successfully: ${instanceRef.id}');
    } catch (e) {
      print('Test instance creation failed: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Get all instances for a specific template (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .orderBy('dueDate', descending: false);

      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      print('Error getting instances for template $templateId: $e');
      return [];
    }
  }

  /// Get all instances for a user (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getAllInstances({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .orderBy('dueDate', descending: false);

      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      print('Error getting all instances: $e');
      return [];
    }
  }

  /// Delete all instances for a template (cleanup utility)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();

      for (final doc in instances.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      print('Error deleting instances for template $templateId: $e');
      rethrow;
    }
  }

  /// Get updated instance data after changes
  static Future<ActivityInstanceRecord> getUpdatedInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      return ActivityInstanceRecord.fromSnapshot(instanceDoc);
    } catch (e) {
      print('Error getting updated instance: $e');
      rethrow;
    }
  }

  // ==================== INSTANCE COMPLETION ====================

  /// Complete an activity instance
  static Future<void> completeInstance({
    required String instanceId,
    dynamic finalValue,
    int? finalAccumulatedTime,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;

      // Update current instance as completed
      await instanceRef.update({
        'status': 'completed',
        'completedAt': now,
        'currentValue': finalValue ?? instance.currentValue,
        'accumulatedTime': finalAccumulatedTime ?? instance.accumulatedTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // For habits, generate next instance immediately using window system
      if (instance.templateCategoryType == 'habit') {
        await _generateNextHabitInstance(instance, uid);
      } else {
        // For tasks, use the existing recurring logic
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(instance.templateId);
        final templateDoc = await templateRef.get();

        if (templateDoc.exists) {
          final template = ActivityRecord.fromSnapshot(templateDoc);

          // Generate next instance if template is recurring and still active
          if (template.isRecurring && template.isActive) {
            final nextDueDate = _calculateNextDueDate(
              currentDueDate: instance.dueDate!,
              template: template,
            );

            if (nextDueDate != null) {
              await createActivityInstance(
                templateId: instance.templateId,
                dueDate: nextDueDate,
                template: template,
                userId: uid,
              );
            }
          }
        }
      }
    } catch (e) {
      print('Error completing activity instance: $e');
      rethrow;
    }
  }

  /// Uncomplete an activity instance (mark as pending)
  static Future<void> uncompleteInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      await instanceRef.update({
        'status': 'pending',
        'completedAt': null,
        'lastUpdated': DateService.currentDate,
      });
    } catch (e) {
      print('Error uncompleting activity instance: $e');
      rethrow;
    }
  }

  // ==================== INSTANCE PROGRESS ====================

  /// Update instance progress (for quantitative tracking)
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required dynamic currentValue,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;

      // For windowed habits, update lastDayValue to current value for next day's calculation
      final updateData = <String, dynamic>{
        'currentValue': currentValue,
        'lastUpdated': now,
      };

      // For windowed habits, update lastDayValue to track differential progress
      if (instance.templateCategoryType == 'habit' &&
          instance.windowDuration > 1) {
        updateData['lastDayValue'] = currentValue;
      }

      await instanceRef.update(updateData);

      // Check if target is reached and auto-complete
      if (instance.templateTrackingType == 'quantitative' &&
          instance.templateTarget != null) {
        final target = instance.templateTarget as num;
        final progress = currentValue is num ? currentValue : 0;

        if (progress >= target) {
          await completeInstance(
            instanceId: instanceId,
            finalValue: currentValue,
            userId: uid,
          );
        }
      }
    } catch (e) {
      print('Error updating instance progress: $e');
      rethrow;
    }
  }

  /// Snooze an instance until a specific date
  static Future<void> snoozeInstance({
    required String instanceId,
    required DateTime snoozeUntil,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);

      // Validate snooze date is not beyond window end
      if (instance.windowEndDate != null &&
          snoozeUntil.isAfter(instance.windowEndDate!)) {
        throw Exception('Cannot snooze beyond window end date');
      }

      await instanceRef.update({
        'snoozedUntil': snoozeUntil,
        'lastUpdated': DateService.currentDate,
      });

      print(
          'ActivityInstanceService: Snoozed instance ${instance.templateName} until $snoozeUntil');
    } catch (e) {
      print('Error snoozing instance: $e');
      rethrow;
    }
  }

  /// Unsnooze an instance (remove snooze)
  static Future<void> unsnoozeInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      await instanceRef.update({
        'snoozedUntil': null,
        'lastUpdated': DateService.currentDate,
      });

      print('ActivityInstanceService: Unsnoozed instance $instanceId');
    } catch (e) {
      print('Error unsnoozing instance: $e');
      rethrow;
    }
  }

  /// Toggle timer for time tracking
  static Future<void> toggleInstanceTimer({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;

      if (instance.isTimerActive && instance.timerStartTime != null) {
        // Stop timer - calculate elapsed time and add to accumulated
        final elapsed = now.difference(instance.timerStartTime!).inMilliseconds;
        final newAccumulated = instance.accumulatedTime + elapsed;

        final updateData = <String, dynamic>{
          'isTimerActive': false,
          'timerStartTime': null,
          'accumulatedTime': newAccumulated,
          'lastUpdated': now,
        };

        // For windowed habits, update lastDayValue to track differential progress
        if (instance.templateCategoryType == 'habit' &&
            instance.windowDuration > 1) {
          updateData['lastDayValue'] = newAccumulated;
        }

        await instanceRef.update(updateData);
      } else {
        // Start timer
        await instanceRef.update({
          'isTimerActive': true,
          'timerStartTime': now,
          'lastUpdated': now,
        });
      }
    } catch (e) {
      print('Error toggling instance timer: $e');
      rethrow;
    }
  }

  // ==================== INSTANCE SCHEDULING ====================

  /// Skip current instance and generate next if recurring
  static Future<void> skipInstance({
    required String instanceId,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      final now = DateService.currentDate;

      // Update current instance as skipped
      await instanceRef.update({
        'status': 'skipped',
        'skippedAt': now,
        'notes': notes ?? instance.notes,
        'lastUpdated': now,
      });

      // Get the template to check if it's recurring
      final templateRef =
          ActivityRecord.collectionForUser(uid).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (templateDoc.exists) {
        final template = ActivityRecord.fromSnapshot(templateDoc);

        // Generate next instance if template is recurring and still active
        if (template.isRecurring && template.isActive) {
          final nextDueDate = _calculateNextDueDate(
            currentDueDate: instance.dueDate!,
            template: template,
          );

          if (nextDueDate != null) {
            await createActivityInstance(
              templateId: instance.templateId,
              dueDate: nextDueDate,
              template: template,
              userId: uid,
            );
          }
        }
      }
    } catch (e) {
      print('Error skipping activity instance: $e');
      rethrow;
    }
  }

  /// Reschedule instance to a new due date
  static Future<void> rescheduleInstance({
    required String instanceId,
    required DateTime newDueDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      await instanceRef.update({
        'dueDate': newDueDate,
        'lastUpdated': DateService.currentDate,
      });
    } catch (e) {
      print('Error rescheduling activity instance: $e');
      rethrow;
    }
  }

  /// Remove due date from an activity instance
  static Future<void> removeDueDateFromInstance({
    required String instanceId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      print(
          'DEBUG: removeDueDateFromInstance called for instance: $instanceId');
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();

      if (!instanceDoc.exists) {
        throw Exception('Activity instance not found');
      }

      print('DEBUG: Updating instance to remove due date');
      await instanceRef.update({
        'dueDate': null,
        'lastUpdated': DateService.currentDate,
      });
      print('DEBUG: Instance updated successfully, due date removed');
    } catch (e) {
      print('Error removing due date from instance: $e');
      rethrow;
    }
  }

  /// Skip all instances until a specific date
  static Future<void> skipInstancesUntil({
    required String templateId,
    required DateTime untilDate,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;

    try {
      // Get all pending instances for this template before the until date
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .where('status', isEqualTo: 'pending')
          .where('dueDate', isLessThan: untilDate);

      final instances = await query.get();
      final now = DateService.currentDate;

      // Mark all instances before untilDate as skipped
      for (final doc in instances.docs) {
        await doc.reference.update({
          'status': 'skipped',
          'skippedAt': now,
          'lastUpdated': now,
        });
      }

      // Ensure there's a pending instance at or after untilDate
      final futureQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId)
          .where('status', isEqualTo: 'pending')
          .where('dueDate', isGreaterThanOrEqualTo: untilDate);

      final futureInstances = await futureQuery.get();

      if (futureInstances.docs.isEmpty) {
        // Create a new instance at untilDate
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(templateId);
        final templateDoc = await templateRef.get();

        if (templateDoc.exists) {
          final template = ActivityRecord.fromSnapshot(templateDoc);
          await createActivityInstance(
            templateId: templateId,
            dueDate: untilDate,
            template: template,
            userId: uid,
          );
        }
      }
    } catch (e) {
      print('Error skipping instances until date: $e');
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Calculate next due date based on template recurrence settings
  static DateTime? _calculateNextDueDate({
    required DateTime currentDueDate,
    required ActivityRecord template,
  }) {
    if (!template.isRecurring) return null;

    // Handle different frequency types
    switch (template.frequencyType) {
      case 'everyXPeriod':
        return _calculateEveryXPeriodNextDate(currentDueDate, template);
      case 'specificDays':
        return _calculateSpecificDaysNextDate(currentDueDate, template);
      case 'timesPerPeriod':
        return _calculateTimesPerPeriodNextDate(currentDueDate, template);
      default:
        return null;
    }
  }

  static DateTime? _calculateEveryXPeriodNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    final everyXValue = template.everyXValue;
    final periodType = template.everyXPeriodType;

    switch (periodType) {
      case 'days':
        return currentDueDate.add(Duration(days: everyXValue));
      case 'weeks':
        return currentDueDate.add(Duration(days: everyXValue * 7));
      case 'months':
        return DateTime(
          currentDueDate.year,
          currentDueDate.month + everyXValue,
          currentDueDate.day,
        );
      case 'year':
        return DateTime(
          currentDueDate.year + everyXValue,
          currentDueDate.month,
          currentDueDate.day,
        );
      default:
        return null;
    }
  }

  static DateTime? _calculateSpecificDaysNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    final specificDays = template.specificDays;
    if (specificDays.isEmpty) return null;

    // Find next occurrence of any of the specified days
    for (int i = 1; i <= 7; i++) {
      final candidate = currentDueDate.add(Duration(days: i));
      if (specificDays.contains(candidate.weekday)) {
        return candidate;
      }
    }
    return null;
  }

  static DateTime? _calculateTimesPerPeriodNextDate(
      DateTime currentDueDate, ActivityRecord template) {
    // For times per period, we need to find the next target date within the current period
    // If we're past the current period, move to the next period
    final periodType = template.periodType;
    final timesPerPeriod = template.timesPerPeriod;

    if (timesPerPeriod <= 0) return null;

    // Get the start of the current period
    DateTime periodStart;
    int periodLength;

    switch (periodType) {
      case 'days':
        periodStart = DateTime(
            currentDueDate.year, currentDueDate.month, currentDueDate.day);
        periodLength = 1;
        break;
      case 'weeks':
        // Find start of week (Sunday = 0)
        final daysSinceSunday = currentDueDate.weekday % 7;
        periodStart = DateTime(currentDueDate.year, currentDueDate.month,
            currentDueDate.day - daysSinceSunday);
        periodLength = 7;
        break;
      case 'months':
        periodStart = DateTime(currentDueDate.year, currentDueDate.month, 1);
        periodLength =
            DateTime(currentDueDate.year, currentDueDate.month + 1, 0).day;
        break;
      case 'year':
        periodStart = DateTime(currentDueDate.year, 1, 1);
        periodLength = 365;
        break;
      default:
        return null;
    }

    // Calculate target dates within the period
    final targetDates = <DateTime>[];
    for (int i = 0; i < timesPerPeriod; i++) {
      final progress = (i + 1) / timesPerPeriod; // 1/3, 2/3, 3/3
      final daysFromStart = (progress * periodLength).floor();
      final hoursFromStart = ((progress * periodLength) - daysFromStart) * 24;

      targetDates.add(DateTime(
        periodStart.year,
        periodStart.month,
        periodStart.day + daysFromStart,
        hoursFromStart.floor(),
        ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
      ));
    }

    // Find the next target date after current due date
    for (final targetDate in targetDates) {
      if (targetDate.isAfter(currentDueDate)) {
        return targetDate;
      }
    }

    // If we're past all targets in this period, move to next period
    DateTime nextPeriodStart;
    switch (periodType) {
      case 'days':
        nextPeriodStart = periodStart.add(const Duration(days: 1));
        break;
      case 'weeks':
        nextPeriodStart = periodStart.add(const Duration(days: 7));
        break;
      case 'months':
        nextPeriodStart = DateTime(periodStart.year, periodStart.month + 1, 1);
        break;
      case 'year':
        nextPeriodStart = DateTime(periodStart.year + 1, 1, 1);
        break;
      default:
        return null;
    }

    // Calculate first target date in next period
    final firstProgress = 1.0 / timesPerPeriod;
    final daysFromStart = (firstProgress * periodLength).floor();
    final hoursFromStart =
        ((firstProgress * periodLength) - daysFromStart) * 24;

    return DateTime(
      nextPeriodStart.year,
      nextPeriodStart.month,
      nextPeriodStart.day + daysFromStart,
      hoursFromStart.floor(),
      ((hoursFromStart - hoursFromStart.floor()) * 60).round(),
    );
  }

  /// Calculate window duration for a habit based on its frequency
  static int _calculateWindowDuration(ActivityRecord template) {
    switch (template.frequencyType) {
      case 'everyXPeriod':
        // "Every X days/weeks/months" → Window = X days
        final everyXValue = template.everyXValue;
        final periodType = template.everyXPeriodType;

        switch (periodType) {
          case 'days':
            return everyXValue;
          case 'weeks':
            return everyXValue * 7;
          case 'months':
            return everyXValue * 30; // Approximate
          case 'year':
            return everyXValue * 365; // Approximate
          default:
            return 1; // Default to daily
        }

      case 'timesPerPeriod':
        // "X times per period" → Window = periodDays / X (rounded)
        final timesPerPeriod = template.timesPerPeriod;
        final periodType = template.periodType;

        int periodDays;
        switch (periodType) {
          case 'days':
            periodDays = 1;
            break;
          case 'weeks':
            periodDays = 7;
            break;
          case 'months':
            periodDays = 30; // Approximate
            break;
          case 'year':
            periodDays = 365; // Approximate
            break;
          default:
            periodDays = 1;
        }

        return (periodDays / timesPerPeriod).round();

      case 'specificDays':
        // For specific days, use 1 day window (daily)
        return 1;

      default:
        return 1; // Default to daily
    }
  }

  /// Generate next habit instance using window system
  static Future<void> _generateNextHabitInstance(
    ActivityInstanceRecord instance,
    String userId,
  ) async {
    try {
      // Calculate next window start = current windowEndDate + 1
      final nextBelongsToDate =
          instance.windowEndDate!.add(const Duration(days: 1));
      final nextWindowEndDate =
          nextBelongsToDate.add(Duration(days: instance.windowDuration - 1));

      // Get template for next instance
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(instance.templateId);
      final templateDoc = await templateRef.get();

      if (!templateDoc.exists) {
        print(
            'ActivityInstanceService: Template not found for next habit instance');
        return;
      }

      final template = ActivityRecord.fromSnapshot(templateDoc);

      // Create next instance data
      final nextInstanceData = createActivityInstanceRecordData(
        templateId: instance.templateId,
        dueDate: nextBelongsToDate, // dueDate = start of window
        status: 'pending',
        createdTime: DateService.currentDate,
        lastUpdated: DateService.currentDate,
        isActive: true,
        lastDayValue: 0, // Initialize for differential tracking
        templateName: template.name,
        templateCategoryId: template.categoryId,
        templateCategoryName: template.categoryName,
        templateCategoryType: template.categoryType,
        templatePriority: template.priority,
        templateTrackingType: template.trackingType,
        templateTarget: template.target,
        templateUnit: template.unit,
        templateDescription: template.description,
        templateShowInFloatingTimer: template.showInFloatingTimer,
        templateEveryXValue: template.everyXValue,
        templateEveryXPeriodType: template.everyXPeriodType,
        templateTimesPerPeriod: template.timesPerPeriod,
        templatePeriodType: template.periodType,
        completionStatus: 'pending',
        dayState: 'open',
        belongsToDate: nextBelongsToDate,
        windowEndDate: nextWindowEndDate,
        windowDuration: instance.windowDuration,
      );

      // Add to Firestore
      await ActivityInstanceRecord.collectionForUser(userId)
          .add(nextInstanceData);

      print(
          'ActivityInstanceService: Generated next habit instance for ${instance.templateName} (${nextBelongsToDate} - ${nextWindowEndDate})');
    } catch (e) {
      print(
          'ActivityInstanceService: Error generating next habit instance: $e');
      // Don't rethrow - we don't want to fail the completion
    }
  }
}
