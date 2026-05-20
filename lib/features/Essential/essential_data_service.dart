import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/services/Activtity/activity_update_broadcast.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';

/// Service to manage Essential Activities (sleep, travel, rest, etc.)
/// These items track time but don't earn points
class essentialService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Create a reusable template (e.g., "Sleep", "Laundry")
  static Future<DocumentReference> createessentialTemplate({
    required String name,
    String? description,
    String? categoryId,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    String? userId,
    int? priority,
    int? timeEstimateMinutes,
    DateTime? dueDate,
    String? dueTime,
    String? frequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    List<int>? specificDays,
  }) async {
    final uid = userId ?? _currentUserId;
    final now = DateTime.now();
    // If categoryId is not provided, get or create default "Others" category
    String finalCategoryId = categoryId ?? '';
    String finalCategoryName = categoryName ?? 'Others';
    if (finalCategoryId.isEmpty) {
      try {
        final defaultCategory =
            await getOrCreateEssentialDefaultCategory(userId: uid);
        finalCategoryId = defaultCategory.reference.id;
        finalCategoryName = defaultCategory.name;
      } catch (e) {
        // If default category creation fails, continue with empty categoryId
        // The template will still be created but without a category
      }
    }
    final templateData = createActivityRecordData(
      name: name,
      categoryId: finalCategoryId.isNotEmpty ? finalCategoryId : null,
      categoryName: finalCategoryName,
      categoryType: 'template',
      description: description,
      trackingType: trackingType ?? 'binary',
      target: target,
      unit: unit,
      isActive: true,
      isRecurring: frequencyType != null && frequencyType.isNotEmpty,
      createdTime: now,
      lastUpdated: now,
      userId: uid,
      priority: priority ?? 1,
      timeEstimateMinutes: timeEstimateMinutes,
      dueDate: dueDate,
      dueTime: dueTime,
      frequencyType: frequencyType,
      everyXValue: everyXValue,
      everyXPeriodType: everyXPeriodType,
      specificDays: specificDays,
    );
    final docRef =
        await ActivityRecord.collectionForUser(uid).add(templateData);
    ActivityTemplateEvents.broadcastTemplateUpdated(
      templateId: docRef.id,
      context: {
        'action': 'created',
        'categoryType': 'template',
        'hasDueTime': dueTime != null && dueTime.isNotEmpty,
        if (timeEstimateMinutes != null)
          'timeEstimateMinutes': timeEstimateMinutes,
      },
    );
    return docRef;
  }

  /// Create a essential instance with time log on demand
  static Future<DocumentReference> createessentialInstance({
    required String templateId,
    required DateTime startTime,
    required DateTime endTime,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    // Get template - check cache first, then Firestore
    final cache = FirestoreCacheService();
    ActivityRecord? template = cache.getCachedTemplate(templateId);
    if (template == null) {
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      template = ActivityRecord.fromSnapshot(templateDoc);
      cache.cacheTemplate(templateId, template);
    }
    if (template.categoryType != 'template' &&
        template.categoryType != 'essential') {
      throw Exception('Template is not a template item');
    }
    // Calculate duration
    final duration = endTime.difference(startTime);
    // Create time log session
    final timeLogSession = {
      'startTime': startTime,
      'endTime': endTime,
      'durationMilliseconds': duration.inMilliseconds,
    };
    // Calculate total time (for this instance, it's just this session)
    final totalTimeLogged = duration.inMilliseconds;
    // Inherit order from previous instance of the same template
    int? queueOrder;
    int? habitsOrder;
    int? tasksOrder;
    try {
      queueOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'queue', uid);
      habitsOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'habits', uid);
      tasksOrder = await InstanceOrderService.getOrderFromPreviousInstance(
          templateId, 'tasks', uid);
    } catch (e) {
      // If order lookup fails, continue with null values (will use default sorting)
    }
    String? templateCategoryColor;
    if (template.categoryId.isNotEmpty) {
      try {
        final categoryDoc = await CategoryRecord.collectionForUser(uid)
            .doc(template.categoryId)
            .get();
        if (categoryDoc.exists) {
          final category = CategoryRecord.fromSnapshot(categoryDoc);
          templateCategoryColor = category.color;
        }
      } catch (e) {
        // If category lookup fails, continue without color fallback.
      }
    }
    // Normalize to start-of-day so queries by belongsToDate find this instance.
    final belongsToDate =
        DateTime(startTime.year, startTime.month, startTime.day);

    final instanceData = createActivityInstanceRecordData(
      templateId: templateId,
      status:
          'completed', // Essential Activities are marked complete when logged
      completedAt: endTime,
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      isActive: true,
      notes: notes,
      // Cache template data
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: template.categoryType, // 'template' or 'essential' (legacy)
      templateCategoryColor: templateCategoryColor,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateDescription: template.description,
      templateIsRecurring: template.isRecurring,
      // Time logging fields
      timeLogSessions: [timeLogSession],
      totalTimeLogged: totalTimeLogged,
      accumulatedTime: totalTimeLogged,
      // Anchor to the day the session started so the instance shows up on the
      // correct day in the routine and essential-today queries.
      belongsToDate: belongsToDate,
      // Inherit order from previous instance
      queueOrder: queueOrder,
      habitsOrder: habitsOrder,
      tasksOrder: tasksOrder,
    );

    // Create instance and get reference
    final instanceRef =
        await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);

    // Fetch the created instance and broadcast immediate updates.
    final createdInstance =
        await ActivityInstanceRecord.getDocumentOnce(instanceRef);
    cache.cacheInstance(createdInstance);

    // Broadcast as concrete events (not optimistic): backend write is complete.
    InstanceEvents.broadcastInstanceCreated(createdInstance);
    InstanceEvents.broadcastInstanceUpdated(createdInstance);

    return instanceRef;
  }

  /// Get all templates for the user (includes legacy 'essential' records)
  static Future<List<ActivityRecord>> getessentialTemplates({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityRecord.collectionForUser(uid)
          .where('categoryType', whereIn: ['template', 'essential'])
          .where('isActive', isEqualTo: true);
      final result = await query.get();
      return result.docs
          .map((doc) => ActivityRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Add or update time log session for an existing instance
  static Future<void> logTimeForInstance({
    required String instanceId,
    required DateTime startTime,
    required DateTime endTime,
    String? notes,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    String? operationId;
    try {
      final cache = FirestoreCacheService();
      // Check cache first
      ActivityInstanceRecord? instance =
          cache.getCachedInstanceById(instanceId);
      if (instance == null) {
        final instanceRef =
            ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
        final instanceDoc = await instanceRef.get();
        if (!instanceDoc.exists) {
          throw Exception('Instance not found');
        }
        instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
        cache.cacheInstance(instance);
      }
      // Validate it's a template instance (accepts legacy 'essential' too)
      if (instance.templateCategoryType != 'template' &&
          instance.templateCategoryType != 'essential') {
        throw Exception('Instance is not a template item');
      }
      // Calculate duration
      final duration = endTime.difference(startTime);
      // Create new session
      final newSession = {
        'startTime': startTime,
        'endTime': endTime,
        'durationMilliseconds': duration.inMilliseconds,
      };
      // Get existing sessions and add new one
      final existingSessions =
          List<Map<String, dynamic>>.from(instance.timeLogSessions);
      existingSessions.add(newSession);
      // Calculate total time across all sessions
      final totalTime = existingSessions.fold<int>(
          0, (sum, session) => sum + (session['durationMilliseconds'] as int));

      // Use optimistic + reconciled lifecycle so calendar updates match other pages.
      operationId = OptimisticOperationTracker.generateOperationId();
      final optimisticInstance =
          InstanceEvents.createOptimisticCompletedInstance(
        instance,
        finalAccumulatedTime: totalTime,
        completedAt: endTime,
        timeLogSessions: existingSessions,
        totalTimeLogged: totalTime,
      );
      OptimisticOperationTracker.trackOperation(
        operationId,
        instanceId: instance.reference.id,
        operationType: 'progress',
        optimisticInstance: optimisticInstance,
        originalInstance: instance,
      );
      InstanceEvents.broadcastInstanceUpdatedOptimistic(
        optimisticInstance,
        operationId,
      );

      // Update instance in backend
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      await instanceRef.update({
        'timeLogSessions': existingSessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': totalTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': DateTime.now(),
        'status': 'completed',
        'completedAt': endTime,
      });
      final updatedSnapshot = await instanceRef.get();
      if (!updatedSnapshot.exists) {
        throw Exception('Instance not found after update');
      }
      final updatedInstance =
          ActivityInstanceRecord.fromSnapshot(updatedSnapshot);
      cache.cacheInstance(updatedInstance);
      OptimisticOperationTracker.reconcileOperation(
        operationId,
        updatedInstance,
      );
    } catch (e) {
      if (operationId != null) {
        OptimisticOperationTracker.rollbackOperation(operationId);
      }
      rethrow;
    }
  }

  /// Delete a essential template
  static Future<void> deleteessentialTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      if (template.categoryType != 'template' &&
          template.categoryType != 'essential') {
        throw Exception('Template is not a template item');
      }
      // Soft delete: mark as inactive
      await templateRef.update({
        'isActive': false,
        'lastUpdated': DateTime.now(),
      });
      // Invalidate template cache
      final cache = FirestoreCacheService();
      cache.invalidateTemplateCache(templateId);
      // Optionally: mark all instances as inactive
      final instancesQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await instancesQuery.get();
      for (final doc in instances.docs) {
        await doc.reference.update({
          'isActive': false,
          'lastUpdated': DateTime.now(),
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Update a template
  static Future<void> updateessentialTemplate({
    required String templateId,
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    int? priority,
    String? userId,
    int? timeEstimateMinutes,
    DateTime? dueDate,
    String? dueTime,
    String? frequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    List<int>? specificDays,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      // Check cache first
      final cache = FirestoreCacheService();
      ActivityRecord? template = cache.getCachedTemplate(templateId);
      if (template == null) {
        final templateRef =
            ActivityRecord.collectionForUser(uid).doc(templateId);
        final templateDoc = await templateRef.get();
        if (!templateDoc.exists) {
          throw Exception('Template not found');
        }
        template = ActivityRecord.fromSnapshot(templateDoc);
        cache.cacheTemplate(templateId, template);
      }
      if (template.categoryType != 'template' &&
          template.categoryType != 'essential') {
        throw Exception('Template is not a template item');
      }
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final updateData = <String, dynamic>{
        'lastUpdated': DateTime.now(),
      };
      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (categoryId != null) updateData['categoryId'] = categoryId;
      if (categoryName != null) updateData['categoryName'] = categoryName;
      if (trackingType != null) updateData['trackingType'] = trackingType;
      if (target != null) updateData['target'] = target;
      if (priority != null) updateData['priority'] = priority;
      if (unit != null) updateData['unit'] = unit;
      // Only update timeEstimateMinutes if it's actually different from current value
      if (timeEstimateMinutes != template.timeEstimateMinutes) {
        updateData['timeEstimateMinutes'] = timeEstimateMinutes != null
            ? timeEstimateMinutes.clamp(1, 600)
            : null;
      }

      // Persist dueDate and dueTime clears as null (required when user removes them).
      if (dueDate != template.dueDate) {
        updateData['dueDate'] = dueDate;
      }
      if (dueTime != template.dueTime) {
        updateData['dueTime'] = dueTime;
      }
      if (frequencyType != null) {
        updateData['frequencyType'] = frequencyType;
        updateData['isRecurring'] = frequencyType.isNotEmpty;
      }
      if (everyXValue != null) updateData['everyXValue'] = everyXValue;
      if (everyXPeriodType != null)
        updateData['everyXPeriodType'] = everyXPeriodType;
      if (specificDays != null) updateData['specificDays'] = specificDays;

      await templateRef.update(updateData);

      // Invalidate template cache
      cache.invalidateTemplateCache(templateId);

      // Cascade updates to instances
      final instanceUpdates = <String, dynamic>{};
      if (name != null) instanceUpdates['templateName'] = name;
      if (description != null)
        instanceUpdates['templateDescription'] = description;
      if (categoryId != null)
        instanceUpdates['templateCategoryId'] = categoryId;
      if (categoryName != null)
        instanceUpdates['templateCategoryName'] = categoryName;
      if (trackingType != null)
        instanceUpdates['templateTrackingType'] = trackingType;
      if (target != null) instanceUpdates['templateTarget'] = target;
      if (unit != null) instanceUpdates['templateUnit'] = unit;
      if (priority != null) instanceUpdates['templatePriority'] = priority;
      if (updateData.containsKey('timeEstimateMinutes')) {
        instanceUpdates['templateTimeEstimateMinutes'] =
            updateData['timeEstimateMinutes'];
      }
      if (updateData.containsKey('dueTime')) {
        instanceUpdates['templateDueTime'] = updateData['dueTime'];
      }
      if (frequencyType != null) {
        instanceUpdates['templateFrequencyType'] = frequencyType;
        instanceUpdates['templateIsRecurring'] = frequencyType.isNotEmpty;
      }
      if (everyXValue != null)
        instanceUpdates['templateEveryXValue'] = everyXValue;
      if (everyXPeriodType != null)
        instanceUpdates['templateEveryXPeriodType'] = everyXPeriodType;

      if (instanceUpdates.isNotEmpty) {
        await ActivityInstanceService.updateActivityInstancesCascade(
          templateId: templateId,
          updates: instanceUpdates,
          updateHistorical:
              false, // essential usually doesn't need historical updates
        );
      }
      // Invalidate template cache
      cache.invalidateTemplateCache(templateId);

      ActivityTemplateEvents.broadcastTemplateUpdated(
        templateId: templateId,
        context: {
          'action': 'updated',
          'categoryType': 'template',
          if (updateData.containsKey('dueTime'))
            'hasDueTime': updateData['dueTime'] != null,
          if (updateData.containsKey('timeEstimateMinutes'))
            'timeEstimateMinutes': updateData['timeEstimateMinutes'],
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  // ── Pending instance management for scheduled template executions ──────────

  /// Deactivate any existing pending instances for this template.
  /// Called before creating a new pending instance (due date changed/removed).
  static Future<void> _deactivatePendingInstances({
    required String templateId,
    required String userId,
  }) async {
    try {
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateId', isEqualTo: templateId)
          .where('status', isEqualTo: 'pending');
      final docs = await query.get();
      if (docs.docs.isEmpty) return;

      final now = DateTime.now();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs.docs) {
        batch.update(doc.reference, {
          'isActive': false,
          'lastUpdated': now,
        });
      }
      await batch.commit();

      // Broadcast each deactivated instance so the queue page removes it
      // immediately without waiting for a Firestore listener round-trip.
      for (final doc in docs.docs) {
        final data = Map<String, dynamic>.from(doc.data() as Map)
          ..['isActive'] = false
          ..['lastUpdated'] = now;
        final updated =
            ActivityInstanceRecord.getDocumentFromData(data, doc.reference);
        InstanceEvents.broadcastInstanceUpdated(updated);
      }
    } catch (_) {}
  }

  /// Create a pending instance for a template scheduled for [dueDate].
  static Future<void> _createPendingTemplateInstance({
    required String templateId,
    required ActivityRecord template,
    required DateTime dueDate,
    required String userId,
  }) async {
    final belongsToDate = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final now = DateTime.now();

    String? templateCategoryColor;
    if (template.categoryId.isNotEmpty) {
      try {
        final catDoc = await CategoryRecord.collectionForUser(userId)
            .doc(template.categoryId)
            .get();
        if (catDoc.exists) {
          templateCategoryColor = CategoryRecord.fromSnapshot(catDoc).color;
        }
      } catch (_) {}
    }

    final instanceData = createActivityInstanceRecordData(
      templateId: templateId,
      status: 'pending',
      createdTime: now,
      lastUpdated: now,
      isActive: true,
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: template.categoryType,
      templateCategoryColor: templateCategoryColor,
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateDescription: template.description,
      templateIsRecurring: false,
      templateTimeEstimateMinutes: template.timeEstimateMinutes,
      templateDueTime: template.hasDueTime() ? template.dueTime : null,
      dueDate: dueDate,
      belongsToDate: belongsToDate,
      timeLogSessions: [],
      totalTimeLogged: 0,
    );

    final ref = await ActivityInstanceRecord.collectionForUser(userId)
        .add(instanceData);
    final created = await ActivityInstanceRecord.getDocumentOnce(ref);
    InstanceEvents.broadcastInstanceCreated(created);
  }

  /// Reconcile pending instances when a template's due date changes.
  /// Deactivates old pending instances and creates a new one if [newDueDate] is set.
  static Future<void> managePendingInstanceForDueDate({
    required String templateId,
    required DateTime? newDueDate,
    required String userId,
  }) async {
    await _deactivatePendingInstances(templateId: templateId, userId: userId);
    if (newDueDate == null) return;
    try {
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) return;
      final template = ActivityRecord.fromSnapshot(templateDoc);
      await _createPendingTemplateInstance(
        templateId: templateId,
        template: template,
        dueDate: newDueDate,
        userId: userId,
      );
    } catch (_) {}
  }
}
