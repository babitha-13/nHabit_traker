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
        // One-time task: Immediate delete, no confirmation (per requirement)
        final deletedInstance = instance;
        onInstanceDeleted(deletedInstance);
        InstanceEvents.broadcastInstanceDeleted(deletedInstance);
        try {
          // Delete template and instance
          await deleteHabit(templateRef);
          // Also delete the specific instance (though deleteHabit might do it if cascaded,
          // let's be explicit for the instance)
          await ActivityInstanceService.deleteInstancesForTemplate(
              templateId: instance.templateId);
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Activity deleted')),
            );
          }
        } catch (e) {
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
          final deletedInstance = instance;
          onInstanceDeleted(deletedInstance);
          InstanceEvents.broadcastInstanceDeleted(deletedInstance);

          try {
            // 1. Delete future instances (including today's if that's the one selected)
            // The requirement says: "All instance from the date of the instance on which the delete was clicked on should be deleted."
            // So we use instance.dueDate (or createdTime if null/habit logic specific)
            // For tasks/habits in lists, they usually have a dueDate or are associated with a date.
            // If instance.dueDate is null, fall back to today? Or createdTime?
            // Most listed items have a date context.
            final deleteStartDate = instance.dueDate ?? DateTime.now();

            await ActivityInstanceService.deleteFutureInstances(
                templateId: instance.templateId, fromDate: deleteStartDate);

            // 2. Stop the template (set endDate)
            // End date should be the day BEFORE the deleteStartDate
            final newEndDate =
                deleteStartDate.subtract(const Duration(days: 1));
            await templateRef.update({
              'endDate': newEndDate,
              'lastUpdated': DateTime.now(),
              // Optionally set isActive to false if newEndDate is in past
              'isActive':
                  false, // Effectively stops it showing up in "Active" lists
            });

            if (isMounted()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Activity ended and future instances deleted')),
              );
            }
          } catch (e) {
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
