import 'package:cloud_firestore/cloud_firestore.dart';

void logFirestoreQueryError(
  dynamic error, {
  required String queryDescription,
  required String collectionName,
  StackTrace? stackTrace,
}) {
  if (error == null) return;

  final errorMessage = error is FirebaseException
      ? (error.message ?? error.toString())
      : error.toString();
  final errorCode = error is FirebaseException ? error.code : null;

  print('');
  print('═══════════════════════════════════════════════════════════');
  print('❌ FIRESTORE QUERY ERROR');
  print('═══════════════════════════════════════════════════════════');
  print('Query: $queryDescription');
  print('Collection: $collectionName');
  if (errorCode != null) {
    print('Error code: $errorCode');
  }
  print('Message: $errorMessage');
  if (stackTrace != null) {
    print('Stack trace: $stackTrace');
  }
  print('═══════════════════════════════════════════════════════════');
  print('');

  logFirestoreIndexError(error, queryDescription, collectionName);
}

/// Helper function to detect and log Firestore missing index errors
/// Extracts the index creation link from error messages and logs it clearly
void logFirestoreIndexError(
  dynamic error,
  String queryDescription,
  String collectionName,
) {
  if (error == null) return;

  final errorString = error.toString();
  final errorMessage = error is Exception ? error.toString() : errorString;

  // Check if this is a missing index error
  final isIndexError = errorMessage.contains('index') ||
      errorMessage.contains('requires an index') ||
      errorMessage.contains('https://console.firebase.google.com');

  if (!isIndexError) return;

  // Extract the index creation URL from the error message
  String? indexUrl;
  final urlPattern = RegExp(r'https://console\.firebase\.google\.com[^\s\)]+');
  final match = urlPattern.firstMatch(errorMessage);
  if (match != null) {
    indexUrl = match.group(0);
  }

  // Log the error with clear formatting
  print('');
  print('═══════════════════════════════════════════════════════════');
  print('❌ FIRESTORE MISSING INDEX ERROR');
  print('═══════════════════════════════════════════════════════════');
  print('Query: $queryDescription');
  print('Collection: $collectionName');
  print('');
  if (indexUrl != null) {
    print('🔗 INDEX CREATION LINK:');
    print('   $indexUrl');
    print('');
    print('📋 INSTRUCTIONS:');
    print('   1. Click the link above to open Firebase Console');
    print('   2. Click "Create Index" button');
    print('   3. Wait for the index to build (may take a few minutes)');
    print('   4. The calendar page should work after the index is ready');
  } else {
    print('⚠️  Could not extract index creation link from error');
    print('   Check Firebase Console for missing indexes');
  }
  print('');
  print('Full error details:');
  print('   $errorMessage');
  print('═══════════════════════════════════════════════════════════');
  print('');
}
