import 'package:cloud_firestore/cloud_firestore.dart';

/// Schema for cumulative score history stored in a single document per user
/// Stores last 100 days of score history to reduce Firestore reads
/// Structure: { lastUpdated: Timestamp, scores: [{date, score, gain}, ...] }
class CumulativeScoreHistoryRecord {
  /// Get document reference for a specific user
  /// Single document per user storing last 100 days
  /// Path: users/{userId}/cumulative_score_history/history
  static DocumentReference getDocumentForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('cumulative_score_history')
          .doc('history');

  /// Get the document snapshot for a user
  static Future<DocumentSnapshot> getDocument(String userId) async {
    return await getDocumentForUser(userId).get();
  }

  /// Create or update the history document
  static Future<void> setDocument({
    required String userId,
    required List<Map<String, dynamic>> scores,
  }) async {
    final docRef = getDocumentForUser(userId);
    await docRef.set({
      'scores': scores,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Update the document with merge (preserves other fields if any)
  static Future<void> updateDocument({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    final docRef = getDocumentForUser(userId);
    await docRef.set({
      ...data,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
