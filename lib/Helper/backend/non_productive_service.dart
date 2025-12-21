import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';

/// Service to manage non-productive items (sleep, travel, rest, etc.)
/// These items track time but don't earn points
class NonProductiveService {
  /// Get current user ID
  static String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Create a reusable non-productive template (e.g., "Sleep", "Travel")
  static Future<DocumentReference> createNonProductiveTemplate({
    required String name,
    String? description,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    String? userId,
    int? timeEstimateMinutes,
  }) async {
    final uid = userId ?? _currentUserId;
    final now = DateTime.now();
    final templateData = createActivityRecordData(
      name: name,
      categoryName: categoryName ?? 'Non-Productive',
      categoryType: 'non_productive',
      description: description,
      trackingType: trackingType ?? 'time', // Default to time tracking
      target: target,
      unit: unit,
      isActive: true,
      isRecurring: false, // Templates don't auto-generate instances
      createdTime: now,
      lastUpdated: now,
      userId: uid,
      priority: 1, // Default priority (won't affect points)
      timeEstimateMinutes: timeEstimateMinutes,
    );
    return await ActivityRecord.collectionForUser(uid).add(templateData);
  }

  /// Create a non-productive instance with time log on demand
  static Future<DocumentReference> createNonProductiveInstance({
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
    if (template.categoryType != 'non_productive') {
      throw Exception('Template is not a non-productive item');
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
          'completed', // Non-productive items are marked complete when logged
      completedAt: endTime,
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      isActive: true,
      notes: notes,
      // Cache template data
      templateName: template.name,
      templateCategoryId: template.categoryId,
      templateCategoryName: template.categoryName,
      templateCategoryType: 'non_productive',
      templatePriority: template.priority,
      templateTrackingType: 'time',
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
    return await ActivityInstanceRecord.collectionForUser(uid)
        .add(instanceData);
  }

  /// Get all non-productive templates for the user
  static Future<List<ActivityRecord>> getNonProductiveTemplates({
    String? userId,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final query = ActivityRecord.collectionForUser(uid)
          .where('categoryType', isEqualTo: 'non_productive')
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
      // Validate it's a non-productive instance
      if (instance.templateCategoryType != 'non_productive') {
        throw Exception('Instance is not a non-productive item');
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

  /// Delete a non-productive template
  static Future<void> deleteNonProductiveTemplate({
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
      if (template.categoryType != 'non_productive') {
        throw Exception('Template is not a non-productive item');
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

  /// Update a non-productive template
  static Future<void> updateNonProductiveTemplate({
    required String templateId,
    String? name,
    String? description,
    String? categoryName,
    String? trackingType,
    dynamic target,
    String? unit,
    String? userId,
    int? timeEstimateMinutes,
  }) async {
    final uid = userId ?? _currentUserId;
    try {
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final templateDoc = await templateRef.get();
      if (!templateDoc.exists) {
        throw Exception('Template not found');
      }
      final template = ActivityRecord.fromSnapshot(templateDoc);
      if (template.categoryType != 'non_productive') {
        throw Exception('Template is not a non-productive item');
      }
      final updateData = <String, dynamic>{
        'lastUpdated': DateTime.now(),
      };
      if (name != null) updateData['name'] = name;
      if (description != null) updateData['description'] = description;
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
      await templateRef.update(updateData);
    } catch (e) {
      rethrow;
    }
  }
}
