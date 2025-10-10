import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Finalizes habit data for the current user
/// This function can be used to clean up old habit records,
/// update completion status, or perform other maintenance tasks
Future<void> finalizeActivityData(String userId) async {
  try {
    // Get current date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Get user's habit records from the user-specific subcollection
    final habitRecords = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('activities')
        .where('isActive', isEqualTo: true)
        .get();

    // Process each habit record
    for (final doc in habitRecords.docs) {
      final data = doc.data();
      final lastUpdated = data['lastUpdated'] as Timestamp?;

      // If habit hasn't been updated today, we could perform cleanup
      if (lastUpdated != null) {
        final lastUpdatedDate = lastUpdated.toDate();
        final lastUpdatedDay = DateTime(
            lastUpdatedDate.year, lastUpdatedDate.month, lastUpdatedDate.day);

        // If it's a new day, we could reset certain fields or perform maintenance
        if (lastUpdatedDay.isBefore(today)) {
          // Example: Reset daily completion status for certain habit types
          // This is just a placeholder - implement based on your specific needs
          await doc.reference.update({
            'lastUpdated': Timestamp.now(),
          });
        }
      }
    }
  } catch (e) {
    print('Error finalizing habit data: $e');
  }
}
