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
    NotificationCenter.post(instanceCreated, instance);
  }
  /// Broadcast when an instance is updated (completed, uncompleted, etc.)
  static void broadcastInstanceUpdated(ActivityInstanceRecord instance) {
    NotificationCenter.post(instanceUpdated, instance);
  }
  /// Broadcast when an instance is deleted
  static void broadcastInstanceDeleted(ActivityInstanceRecord instance) {
    NotificationCenter.post(instanceDeleted, instance);
  }
  /// Broadcast when progress needs to be recalculated
  static void broadcastProgressRecalculated() {
    NotificationCenter.post(progressRecalculated, null);
  }
}
