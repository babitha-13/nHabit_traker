import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';

/// Centralized instance event management
/// Provides constants and helper methods for broadcasting instance changes
class InstanceEvents {
  // Event constants
  static const String instanceCreated = 'instanceCreated';
  static const String instanceUpdated = 'instanceUpdated';
  static const String instanceDeleted = 'instanceDeleted';
  static const String progressRecalculated = 'progressRecalculated';

  /// Broadcast when a new instance is created
  static void broadcastInstanceCreated(ActivityInstanceRecord instance) {
    print(
        'InstanceEvents: Broadcasting instanceCreated for ${instance.templateName}');
    NotificationCenter.post(instanceCreated, instance);
  }

  /// Broadcast when an instance is updated (completed, uncompleted, etc.)
  static void broadcastInstanceUpdated(ActivityInstanceRecord instance) {
    print(
        'InstanceEvents: Broadcasting instanceUpdated for ${instance.templateName}');
    NotificationCenter.post(instanceUpdated, instance);
  }

  /// Broadcast when an instance is deleted
  static void broadcastInstanceDeleted(ActivityInstanceRecord instance) {
    print(
        'InstanceEvents: Broadcasting instanceDeleted for ${instance.templateName}');
    NotificationCenter.post(instanceDeleted, instance);
  }

  /// Broadcast when progress needs to be recalculated
  static void broadcastProgressRecalculated() {
    print('InstanceEvents: Broadcasting progressRecalculated');
    NotificationCenter.post(progressRecalculated, null);
  }
}
