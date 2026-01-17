import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'firebase_auth_manager.dart';
import 'firebase_user_provider.dart';
import 'package:habit_tracker/debug_log_stub.dart'
    if (dart.library.io) 'package:habit_tracker/debug_log_io.dart'
    if (dart.library.html) 'package:habit_tracker/debug_log_web.dart';
export 'firebase_auth_manager.dart';

// #region agent log
void _logAuthDebug(String location, Map<String, dynamic> data) {
  try {
    final logEntry = {
      'id': 'log_${DateTime.now().millisecondsSinceEpoch}_auth',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': 'auth_util.dart:$location',
      'message': data['event'] ?? 'debug',
      'data': data,
      'sessionId': 'debug-session',
      'runId': 'run2',
    };
    writeDebugLog(jsonEncode(logEntry));
  } catch (_) {
    // Silently fail
  }
}
// #endregion

final _authManager = FirebaseAuthManager();
FirebaseAuthManager get authManager => _authManager;
String get currentUserEmail =>
    currentUserDocument?.email ?? currentUser?.email ?? '';
String get currentUserUid => currentUser?.uid ?? '';
String get currentUserDisplayName =>
    currentUserDocument?.displayName ?? currentUser?.displayName ?? '';
String get currentUserPhoto =>
    currentUserDocument?.photoUrl ?? currentUser?.photoUrl ?? '';
String get currentPhoneNumber =>
    currentUserDocument?.phoneNumber ?? currentUser?.phoneNumber ?? '';
String get currentJwtToken => _currentJwtToken ?? '';
bool get currentUserEmailVerified => currentUser?.emailVerified ?? false;

/// Create a Stream that listens to the current user's JWT Token, since Firebase
/// generates a new token every hour.
String? _currentJwtToken;
final jwtTokenStream = FirebaseAuth.instance
    .idTokenChanges()
    .map((user) async => _currentJwtToken = await user?.getIdToken())
    .asBroadcastStream();
DocumentReference? get currentUserReference =>
    loggedIn ? UsersRecord.collection.doc(currentUser!.uid) : null;
UsersRecord? currentUserDocument;
final authenticatedUserStream = FirebaseAuth.instance
    .authStateChanges()
    .map<String>((user) => user?.uid ?? '')
    .asyncExpand(
      (uid) => uid.isEmpty
          ? Stream.value(null)
          : UsersRecord.getDocument(UsersRecord.collection.doc(uid))
              .handleError((e) {
              // #region agent log
              _logAuthDebug('authenticatedUserStream', {
                'hypothesisId': 'N',
                'event': 'user_doc_error',
                'errorType': e.runtimeType.toString(),
              });
              // #endregion
            }),
    )
    .map((user) {
  currentUserDocument = user;
  // #region agent log
  _logAuthDebug('authenticatedUserStream', {
    'hypothesisId': 'N',
    'event': 'user_doc_update',
    'hasUserDoc': currentUserDocument != null,
  });
  // #endregion
  return currentUserDocument;
}).asBroadcastStream();
// Stream for habit tracker app using HabitTrackerFirebaseUser
Stream<BaseAuthUser> habitTrackerFirebaseUserStream() =>
    FirebaseAuth.instance.authStateChanges().map<BaseAuthUser>(
      (user) {
        currentUser = HabitTrackerFirebaseUser(user);
        // #region agent log
        _logAuthDebug('habitTrackerFirebaseUserStream', {
          'hypothesisId': 'N',
          'event': 'auth_state_change',
          'userIsNull': user == null,
          'uidLength': user?.uid.length ?? 0,
        });
        // #endregion
        return currentUser!;
      },
    );
// Pushes photo url updates to Firestore on auth state change.
void onUserUpdated(User? user) {
  if (user == null) {
    return;
  }
  final photoUrl = user.photoURL;
  if (photoUrl != null) {
    UsersRecord.collection.doc(user.uid).update({'photoUrl': photoUrl});
  }
}

class AuthUserStreamWidget extends StatelessWidget {
  const AuthUserStreamWidget({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: authenticatedUserStream,
        builder: (context, _) => builder(context),
      );
}
