import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class ItemManagementHelper {
  static Future<void> copyHabit({
    required ActivityInstanceRecord instance,
    required BuildContext context,
    required Function(bool) setUpdating,
    required Future<void> Function()? onRefresh,
  }) async {
    try {
      setUpdating(true);
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(instance.templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      final newTemplateName = 'Copy of ${template.name}';
      final newTemplateRef = await createActivity(
        name: newTemplateName,
        categoryId: template.categoryId,
        categoryName: template.categoryName,
        trackingType: template.trackingType,
        target: template.target,
        description: template.description,
        categoryType: template.categoryType,
        priority: template.priority,
        unit: template.unit,
        isRecurring: template.isRecurring,
        frequencyType: template.frequencyType,
        specificDays: template.specificDays,
        startDate: template.startDate,
        dueDate: template.dueDate,
      );
      final newTemplate = await ActivityRecord.getDocumentOnce(newTemplateRef);
      await ActivityInstanceService.createActivityInstance(
        templateId: newTemplateRef.id,
        template: newTemplate,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Task "$newTemplateName" created successfully')),
        );
        if (onRefresh != null) await onRefresh();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error copying task: $e')));
      }
    } finally {
      setUpdating(false);
    }
  }

  static Future<void> showHabitOverflowMenu({
    required BuildContext context,
    required BuildContext anchorContext,
    required ActivityInstanceRecord instance,
    required List<CategoryRecord> categories,
    required Function(ActivityInstanceRecord) onInstanceDeleted,
    required Function(ActivityInstanceRecord) onInstanceUpdated,
    required Function(bool) setUpdating,
    required Future<void> Function()? onRefresh,
    required Function(int?) onEstimateUpdate,
    required Future<void> Function()
        editActivity, // ADD THIS - callback for edit
    required num? Function(int?)
        normalizeTimeEstimate, // ADD THIS - callback for normalize
    required bool Function() isMounted, // ADD THIS - callback for mounted check
  }) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: const [
        PopupMenuItem<String>(
            value: 'edit',
            height: 32,
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'copy',
            height: 32,
            child: Text('Duplicate', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    final uid = await waitForCurrentUserUid();
    if (uid.isEmpty) return;
    final templateRef =
        ActivityRecord.collectionForUser(uid).doc(instance.templateId);

    if (selected == 'edit') {
      await editActivity(); // CALL THE CALLBACK
    } else if (selected == 'copy') {
      await copyHabit(
          instance: instance,
          context: context,
          setUpdating: setUpdating,
          onRefresh: onRefresh);
    } else if (selected == 'delete') {
      // Check if it's a recurring activity
      // We need the template to check recurring status reliably
      // instance.templateIsRecurring might be available, but let's be safe.
      // However, instance.templateIsRecurring is usually populated from template.
      final isRecurring = instance.templateIsRecurring;

      if (!isRecurring) {
        print('ItemManagementHelper: DELETING ONE-TIME TASK');
        print('ItemManagementHelper: instance.id: ${instance.reference.id}');
        print('ItemManagementHelper: templateId: ${instance.templateId}');
        // One-time task: Immediate delete, no confirmation (per requirement)
        final deletedInstance = instance;
        onInstanceDeleted(deletedInstance);
        InstanceEvents.broadcastInstanceDeleted(deletedInstance);
        try {
          // Delete template and instance
          print(
              'ItemManagementHelper: Calling deleteHabit(templateRef) for ${templateRef.id}');
          await deleteHabit(templateRef);
          // Also delete the specific instance (though deleteHabit might do it if cascaded,
          // let's be explicit for the instance)
          print(
              'ItemManagementHelper: Calling ActivityInstanceService.deleteInstancesForTemplate');
          await ActivityInstanceService.deleteInstancesForTemplate(
              templateId: instance.templateId);
          print(
              'ItemManagementHelper: Deletion completed successfully for one-time task');
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Activity deleted')),
            );
          }
        } catch (e) {
          print('ItemManagementHelper: Error deleting one-time activity: $e');
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting activity: $e')),
            );
          }
          if (onRefresh != null) {
            await onRefresh();
          }
        }
      } else {
        // Recurring activity: Show warning
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Activity'),
            content: Text(
                'Delete "${instance.templateName}"? This will delete the activity and all future instances. History will remain unaffected. This cannot be undone.'),
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
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (shouldDelete == true) {
          print('ItemManagementHelper: DELETING RECURRING TASK');
          print('ItemManagementHelper: instance.id: ${instance.reference.id}');
          print('ItemManagementHelper: templateId: ${instance.templateId}');
          final deletedInstance = instance;
          onInstanceDeleted(deletedInstance);
          InstanceEvents.broadcastInstanceDeleted(deletedInstance);

          try {
            // IMPORTANT: Mark the template inactive FIRST before deleting instances.
            // The Cloud Function `ensurePendingInstancesExist` queries templates where
            // isActive==true. If we delete instances first but the template is still active,
            // the Cloud Function can race in and regenerate the very instances we just deleted.

            // 1. Stop the template first (set isActive=false and endDate)
            // End date should be the day BEFORE the deleteStartDate
            final deleteStartDate =
                instance.dueDate ?? instance.createdTime ?? DateTime.now();
            final newEndDate =
                deleteStartDate.subtract(const Duration(days: 1));
            print(
                'ItemManagementHelper: Marking template inactive first: ${templateRef.id}, endDate: $newEndDate');
            await templateRef.update({
              'endDate': newEndDate,
              'isActive': false,
              'lastUpdated': DateTime.now(),
            });

            // 2. Now delete future instances (template is already inactive so Cloud
            //    Functions won't recreate them during the deletion window).
            print(
                'ItemManagementHelper: Calling deleteFutureInstances from date: $deleteStartDate');
            await ActivityInstanceService.deleteFutureInstances(
                templateId: instance.templateId, fromDate: deleteStartDate);

            print(
                'ItemManagementHelper: Deletion completed successfully for recurring task');
            if (isMounted()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Activity ended and future instances deleted')),
              );
            }
          } catch (e) {
            print(
                'ItemManagementHelper: Error deleting recurring activity: $e');
            if (isMounted()) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error deleting activity: $e')),
              );
            }
            if (onRefresh != null) {
              await onRefresh();
            }
          }
        }
      }
    }
  }
}
