import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/services/local_storage_services.dart';

/// One-time migration: rename categoryType 'essential' → 'template' in Firestore
/// and set priority=0 on those records to preserve their no-points behavior.
/// Also cleans up orphan pending template instances accumulated during testing.
/// Gated by a SharedPreferences flag so it runs exactly once per device.
class EssentialToTemplateMigration {
  static const _migrationKey = 'migration_essential_to_template_v2_done';

  static Future<bool> _isDone() async {
    final value = await SharedPref().read(_migrationKey);
    return value == true;
  }

  static Future<void> _markDone() async {
    await SharedPref().save(_migrationKey, true);
  }

  static Future<void> runIfNeeded(String userId) async {
    if (userId.isEmpty) return;
    if (await _isDone()) return;

    try {
      final db = FirebaseFirestore.instance;

      // Migrate ActivityRecord templates
      final templateQuery = ActivityRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'essential');
      final templateDocs = await templateQuery.get();

      final batch = db.batch();
      for (final doc in templateDocs.docs) {
        batch.update(doc.reference, {
          'categoryType': 'template',
          'priority': 0,
        });
      }

      // Migrate ActivityInstanceRecord instances
      final instanceQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'essential');
      final instanceDocs = await instanceQuery.get();

      // Firestore batch limit is 500 — flush and restart if needed
      int opCount = templateDocs.docs.length;
      for (final doc in instanceDocs.docs) {
        if (opCount >= 490) {
          await batch.commit();
          opCount = 0;
        }
        batch.update(doc.reference, {
          'templateCategoryType': 'template',
          'templatePriority': 0,
        });
        opCount++;
      }

      await batch.commit();

      // Clean up orphan pending template instances (accumulated during testing).
      // Any pending template instance whose template no longer has a dueDate set,
      // or which is simply a leftover from prior test runs, is deactivated.
      await _cleanupOrphanPendingTemplateInstances(userId: userId);

      await _markDone();
    } catch (e) {
      // Migration failure is non-fatal: the app still handles both
      // 'essential' and 'template' values via backward-compat guards.
      print('EssentialToTemplateMigration: skipped due to error: $e');
    }
  }

  /// Deactivate all pending template/essential instances whose parent template
  /// no longer has a dueDate — these are testing orphans.
  static Future<void> _cleanupOrphanPendingTemplateInstances({
    required String userId,
  }) async {
    try {
      final db = FirebaseFirestore.instance;

      // Fetch all pending template instances
      final pendingQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('status', isEqualTo: 'pending')
          .where('templateCategoryType', whereIn: ['template', 'essential']);
      final pendingDocs = await pendingQuery.get();
      if (pendingDocs.docs.isEmpty) return;

      // Fetch all template ActivityRecords to check their current dueDate
      final templateIds = pendingDocs.docs
          .map((d) => (d.data() as Map<String, dynamic>)['templateId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .cast<String>();

      final Map<String, bool> templateHasDueDate = {};
      for (final templateId in templateIds) {
        try {
          final tDoc = await ActivityRecord.collectionForUser(userId)
              .doc(templateId)
              .get();
          if (tDoc.exists) {
            final data = tDoc.data() as Map<String, dynamic>?;
            templateHasDueDate[templateId] = data?['dueDate'] != null;
          } else {
            templateHasDueDate[templateId] = false;
          }
        } catch (_) {
          templateHasDueDate[templateId] = false;
        }
      }

      // Deactivate pending instances for templates with no current dueDate
      final batch = db.batch();
      int count = 0;
      for (final doc in pendingDocs.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final templateId = data['templateId'] as String? ?? '';
        final hasDue = templateHasDueDate[templateId] ?? false;
        if (!hasDue) {
          if (count >= 490) {
            await batch.commit();
            count = 0;
          }
          batch.update(doc.reference, {
            'isActive': false,
            'lastUpdated': DateTime.now(),
          });
          count++;
        }
      }
      if (count > 0) await batch.commit();
    } catch (e) {
      print('EssentialToTemplateMigration: orphan cleanup error: $e');
    }
  }
}
