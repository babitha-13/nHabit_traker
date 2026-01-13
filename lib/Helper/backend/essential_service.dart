import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/activity_update_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic%20update.dart';

/// Service to manage Essential Activities (sleep, travel, rest, etc.)
/// These items track time but don't earn points
class essentialService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Create a reusable essential template (e.g., "Sleep", "Travel")
  static Future<DocumentReference> createessentialTemplate({
    required String name,
    String? description,
    String? categoryId,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    String? userId,
    int? timeEstimateMinutes,
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
      categoryType: 'essential',
      description: description,
      trackingType: trackingType ?? 'binary', // Default to binary tracking
      target: target,
      unit: unit,
      isActive: true,
      isRecurring: frequencyType != null && frequencyType.isNotEmpty,
      createdTime: now,
      lastUpdated: now,
      userId: uid,
      priority: 1, // Default priority (won't affect points)
      timeEstimateMinutes: timeEstimateMinutes,
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
        'categoryType': 'essential',
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
    // Get template to cache data
    final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
    final templateDoc = await templateRef.get();
    if (!templateDoc.exists) {
      throw Exception('Template not found');
    }
    final template = ActivityRecord.fromSnapshot(templateDoc);
    if (template.categoryType != 'essential') {
      throw Exception('Template is not a essential item');
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
      templateCategoryType: 'essential',
      templatePriority: template.priority,
      templateTrackingType: template.trackingType,
      templateDescription: template.description,
      // Time logging fields
      timeLogSessions: [timeLogSession],
      totalTimeLogged: totalTimeLogged,
      accumulatedTime: totalTimeLogged,
      // Inherit order from previous instance
      queueOrder: queueOrder,
      habitsOrder: habitsOrder,
      tasksOrder: tasksOrder,
    );

    // Create instance and get reference
    final instanceRef =
        await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);

    // Fetch the created instance and broadcast optimistic update
    final createdInstance =
        await ActivityInstanceRecord.getDocumentOnce(instanceRef);

    // Broadcast optimistic instance creation for immediate calendar update
    final operationId =
        'essential_create_${DateTime.now().millisecondsSinceEpoch}';
    InstanceEvents.broadcastInstanceCreatedOptimistic(
        createdInstance, operationId);

    // Also broadcast as updated since it's completed with time logs
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
        createdInstance, operationId);

    return instanceRef;
  }

  /// Get all essential templates for the user
  static Future<List<ActivityRecord>> getessentialTemplates({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityRecord.collectionForUser(uid)
          .where('categoryType', isEqualTo: 'essential')
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
    try {
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
      final instanceDoc = await instanceRef.get();
      if (!instanceDoc.exists) {
        throw Exception('Instance not found');
      }
      final instance = ActivityInstanceRecord.fromSnapshot(instanceDoc);
      // Validate it's a essential instance
      if (instance.templateCategoryType != 'essential') {
        throw Exception('Instance is not a essential item');
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
      // Update instance
      await instanceRef.update({
        'timeLogSessions': existingSessions,
        'totalTimeLogged': totalTime,
        'accumulatedTime': totalTime,
        'notes': notes ?? instance.notes,
        'lastUpdated': DateTime.now(),
        'status': 'completed',
        'completedAt': endTime,
      });
    } catch (e) {
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
      if (template.categoryType != 'essential') {
        throw Exception('Template is not a essential item');
      }
      // Soft delete: mark as inactive
      await templateRef.update({
        'isActive': false,
        'lastUpdated': DateTime.now(),
      });
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

  /// Update a essential template
  static Future<void> updateessentialTemplate({
    required String templateId,
    String? name,
    String? description,
    String? categoryId,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    String? userId,
    int? timeEstimateMinutes,
    String? dueTime,
    String? frequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    List<int>? specificDays,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      if (template.categoryType != 'essential') {
        throw Exception('Template is not a essential item');
      }
      final updateData = <String, dynamic>{
        'lastUpdated': DateTime.now(),
      };
      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
      if (categoryId != null) updateData['categoryId'] = categoryId;
      if (categoryName != null) updateData['categoryName'] = categoryName;
      if (trackingType != null) updateData['trackingType'] = trackingType;
      if (target != null) updateData['target'] = target;
      if (unit != null) updateData['unit'] = unit;
      // Only update timeEstimateMinutes if it's actually different from current value
      if (timeEstimateMinutes != template.timeEstimateMinutes) {
        updateData['timeEstimateMinutes'] = timeEstimateMinutes != null
            ? timeEstimateMinutes.clamp(1, 600)
            : null;
      }

      if (dueTime != null) updateData['dueTime'] = dueTime;
      if (frequencyType != null) {
        updateData['frequencyType'] = frequencyType;
        updateData['isRecurring'] = frequencyType.isNotEmpty;
      }
      if (everyXValue != null) updateData['everyXValue'] = everyXValue;
      if (everyXPeriodType != null)
        updateData['everyXPeriodType'] = everyXPeriodType;
      if (specificDays != null) updateData['specificDays'] = specificDays;

      await templateRef.update(updateData);

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
      if (updateData.containsKey('timeEstimateMinutes')) {
        instanceUpdates['templateTimeEstimateMinutes'] =
            updateData['timeEstimateMinutes'];
      }
      if (dueTime != null) instanceUpdates['templateDueTime'] = dueTime;
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
      ActivityTemplateEvents.broadcastTemplateUpdated(
        templateId: templateId,
        context: {
          'action': 'updated',
          'categoryType': 'essential',
          if (updateData.containsKey('dueTime')) 'hasDueTime': true,
          if (updateData.containsKey('timeEstimateMinutes'))
            'timeEstimateMinutes': updateData['timeEstimateMinutes'],
        },
      );
    } catch (e) {
      rethrow;
    }
  }
}
