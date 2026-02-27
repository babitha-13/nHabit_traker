import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';

/// Service for batch reading Firestore documents
/// Reduces individual document reads by batching multiple reads together
class BatchReadService {
  // Firestore batch read limit is 10 documents per call
  static const int _batchSize = 10;

  /// Batch read multiple documents by their references
  /// Uses whereIn queries for same-collection reads (1 read operation per batch)
  /// Falls back to individual gets for mixed collections
  /// This reduces read operations significantly compared to individual gets
  static Future<List<DocumentSnapshot>> batchGetDocuments(
    List<DocumentReference> references,
  ) async {
    if (references.isEmpty) return [];

    final List<DocumentSnapshot> results = [];

    // Group references by collection path for efficient batch reads
    final Map<String, List<DocumentReference>> collectionGroups = {};
    for (final ref in references) {
      final collectionPath = ref.parent.path;
      collectionGroups.putIfAbsent(collectionPath, () => []).add(ref);
    }

    // Process each collection group
    for (final entry in collectionGroups.entries) {
      final collectionPath = entry.key;
      final refs = entry.value;
      final collectionRef =
          FirebaseFirestore.instance.collection(collectionPath);

      // Process in batches of 10 (Firestore whereIn limit)
      for (int i = 0; i < refs.length; i += _batchSize) {
        final batch = refs.skip(i).take(_batchSize).toList();
        try {
          // Use whereIn query for same-collection batch reads
          // This counts as 1 read operation per batch instead of N individual reads
          final documentIds = batch.map((ref) => ref.id).toList();
          final querySnapshot = await collectionRef
              .where(FieldPath.documentId, whereIn: documentIds)
              .get();

          // Create a map for quick lookup
          final snapshotMap = {
            for (final doc in querySnapshot.docs) doc.id: doc
          };

          // Add snapshots in the same order as requested references
          // Note: Non-existent documents won't be in query results, so we skip them
          // Callers should check snapshot.exists before using the data
          for (final ref in batch) {
            if (snapshotMap.containsKey(ref.id)) {
              results.add(snapshotMap[ref.id]!);
            }
            // Skip non-existent documents to avoid extra read operations
            // If callers need non-existent snapshots, they can check by ID separately
          }
        } catch (e) {
          // If batch query fails, try individual reads as fallback
          for (final ref in batch) {
            try {
              final snapshot = await ref.get();
              results.add(snapshot);
            } catch (_) {
              // Skip failed documents
            }
          }
        }
      }
    }

    return results;
  }

  /// Batch read templates by their IDs
  /// Checks cache first, then batch reads missing templates
  static Future<Map<String, ActivityRecord>> batchGetTemplates({
    required List<String> templateIds,
    required String userId,
    bool useCache = true,
  }) async {
    if (templateIds.isEmpty) return {};

    final cache = FirestoreCacheService();
    final Map<String, ActivityRecord> templates = {};
    final List<String> missingTemplateIds = [];

    // Check cache first
    if (useCache) {
      for (final templateId in templateIds) {
        final cached = cache.getCachedTemplate(templateId);
        if (cached != null) {
          templates[templateId] = cached;
        } else {
          missingTemplateIds.add(templateId);
        }
      }
    } else {
      missingTemplateIds.addAll(templateIds);
    }

    // Batch read missing templates
    if (missingTemplateIds.isNotEmpty) {
      final references = missingTemplateIds
          .map((id) => ActivityRecord.collectionForUser(userId).doc(id))
          .toList();

      final snapshots = await batchGetDocuments(references);
      for (final snapshot in snapshots) {
        if (snapshot.exists) {
          final template = ActivityRecord.fromSnapshot(snapshot);
          templates[snapshot.id] = template;
          // Cache the template
          cache.cacheTemplate(snapshot.id, template);
        }
      }
    }

    return templates;
  }

  /// Batch read categories by their IDs
  /// Checks cache first, then batch reads missing categories
  static Future<Map<String, CategoryRecord>> batchGetCategories({
    required List<String> categoryIds,
    required String userId,
    required String categoryType, // 'habit' or 'task'
    bool useCache = true,
  }) async {
    if (categoryIds.isEmpty) return {};

    final cache = FirestoreCacheService();
    final Map<String, CategoryRecord> categories = {};
    final List<String> missingCategoryIds = [];

    // Check cache first
    if (useCache) {
      final cachedCategories = categoryType == 'habit'
          ? cache.getCachedHabitCategories(userId: userId)
          : cache.getCachedTaskCategories(userId: userId);

      if (cachedCategories != null) {
        final cachedMap = {
          for (final cat in cachedCategories) cat.reference.id: cat
        };
        for (final categoryId in categoryIds) {
          if (cachedMap.containsKey(categoryId)) {
            categories[categoryId] = cachedMap[categoryId]!;
          } else {
            missingCategoryIds.add(categoryId);
          }
        }
      } else {
        missingCategoryIds.addAll(categoryIds);
      }
    } else {
      missingCategoryIds.addAll(categoryIds);
    }

    // Batch read missing categories
    if (missingCategoryIds.isNotEmpty) {
      final references = missingCategoryIds
          .map((id) => CategoryRecord.collectionForUser(userId).doc(id))
          .toList();

      final snapshots = await batchGetDocuments(references);
      for (final snapshot in snapshots) {
        if (snapshot.exists) {
          final category = CategoryRecord.fromSnapshot(snapshot);
          categories[snapshot.id] = category;
        }
      }
    }

    return categories;
  }

  /// Batch read any documents by their paths
  /// Generic utility for batch reading any Firestore documents
  static Future<Map<String, DocumentSnapshot>> batchGetByPaths(
    List<String> documentPaths,
  ) async {
    if (documentPaths.isEmpty) return {};

    final Map<String, DocumentSnapshot> results = {};
    final references = documentPaths
        .map((path) => FirebaseFirestore.instance.doc(path))
        .toList();

    final snapshots = await batchGetDocuments(references);
    for (final snapshot in snapshots) {
      results[snapshot.reference.path] = snapshot;
    }

    return results;
  }
}
