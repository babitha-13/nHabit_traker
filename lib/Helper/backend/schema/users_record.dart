import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
class UsersRecord extends FirestoreRecord {
  UsersRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }
  // "email" field.
  String? _email;
  String get email => _email ?? '';
  bool hasEmail() => _email != null;
  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;
  // "display_name" field.
  String? _displayName;
  String get displayName => _displayName ?? '';
  bool hasDisplayName() => _displayName != null;
  // "users" field.
  String? _users;
  String get users => _users ?? '';
  bool hasUsers() => _users != null;
  // "photo_url" field.
  String? _photoUrl;
  String get photoUrl => _photoUrl ?? '';
  bool hasPhotoUrl() => _photoUrl != null;
  // "created_time" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;
  // "phone_number" field.
  String? _phoneNumber;
  String get phoneNumber => _phoneNumber ?? '';
  bool hasPhoneNumber() => _phoneNumber != null;
  // "current_goal_id" field.
  String? _currentGoalId;
  String get currentGoalId => _currentGoalId ?? '';
  bool hasCurrentGoalId() => _currentGoalId != null;
  // "last_goal_shown_date" field.
  DateTime? _lastGoalShownDate;
  DateTime? get lastGoalShownDate => _lastGoalShownDate;
  bool hasLastGoalShownDate() => _lastGoalShownDate != null;
  // "goal_prompt_skipped" field.
  bool? _goalPromptSkipped;
  bool get goalPromptSkipped => _goalPromptSkipped ?? false;
  bool hasGoalPromptSkipped() => _goalPromptSkipped != null;
  // "goal_onboarding_completed" field.
  bool? _goalOnboardingCompleted;
  bool get goalOnboardingCompleted => _goalOnboardingCompleted ?? false;
  bool hasGoalOnboardingCompleted() => _goalOnboardingCompleted != null;
  // "morning_notification_time" field.
  String? _morningNotificationTime;
  String get morningNotificationTime => _morningNotificationTime ?? '';
  bool hasMorningNotificationTime() => _morningNotificationTime != null;
  // "evening_notification_time" field.
  String? _eveningNotificationTime;
  String get eveningNotificationTime => _eveningNotificationTime ?? '';
  bool hasEveningNotificationTime() => _eveningNotificationTime != null;
  // "notification_preferences" field.
  Map<String, dynamic>? _notificationPreferences;
  Map<String, dynamic> get notificationPreferences =>
      _notificationPreferences ?? {};
  bool hasNotificationPreferences() => _notificationPreferences != null;
  // "last_app_opened" field.
  DateTime? _lastAppOpened;
  DateTime? get lastAppOpened => _lastAppOpened;
  bool hasLastAppOpened() => _lastAppOpened != null;
  // "notification_onboarding_completed" field.
  bool? _notificationOnboardingCompleted;
  bool get notificationOnboardingCompleted =>
      _notificationOnboardingCompleted ?? false;
  bool hasNotificationOnboardingCompleted() =>
      _notificationOnboardingCompleted != null;
  // "timezone_offset" field - timezone offset in hours from UTC (e.g., 5.5 for IST, -5 for EST)
  double? _timezoneOffset;
  double? get timezoneOffset => _timezoneOffset;
  bool hasTimezoneOffset() => _timezoneOffset != null;
  void _initializeFields() {
    _email = snapshotData['email'] as String?;
    _uid = snapshotData['uid'] as String?;
    _displayName = snapshotData['display_name'] as String?;
    _users = snapshotData['users'] as String?;
    _photoUrl = snapshotData['photo_url'] as String?;
    _createdTime = snapshotData['created_time'] as DateTime?;
    _phoneNumber = snapshotData['phone_number'] as String?;
    _currentGoalId = snapshotData['current_goal_id'] as String?;
    _lastGoalShownDate = snapshotData['last_goal_shown_date'] as DateTime?;
    _goalPromptSkipped = snapshotData['goal_prompt_skipped'] as bool?;
    _goalOnboardingCompleted =
        snapshotData['goal_onboarding_completed'] as bool?;
    _morningNotificationTime =
        snapshotData['morning_notification_time'] as String?;
    _eveningNotificationTime =
        snapshotData['evening_notification_time'] as String?;
    _notificationPreferences =
        snapshotData['notification_preferences'] as Map<String, dynamic>?;
    _lastAppOpened = snapshotData['last_app_opened'] as DateTime?;
    _notificationOnboardingCompleted =
        snapshotData['notification_onboarding_completed'] as bool?;
    _timezoneOffset = (snapshotData['timezone_offset'] as num?)?.toDouble();
  }
  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('users');
  static Stream<UsersRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => UsersRecord.fromSnapshot(s));
  static Future<UsersRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => UsersRecord.fromSnapshot(s));
  static UsersRecord fromSnapshot(DocumentSnapshot snapshot) => UsersRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );
  static UsersRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      UsersRecord._(reference, mapFromFirestore(data));
  @override
  String toString() =>
      'UsersRecord(reference: ${reference.path}, data: $snapshotData)';
  @override
  int get hashCode => reference.path.hashCode;
  @override
  bool operator ==(other) =>
      other is UsersRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}
Map<String, dynamic> createUsersRecordData({
  String? email,
  String? uid,
  String? displayName,
  String? users,
  String? photoUrl,
  DateTime? createdTime,
  String? phoneNumber,
  String? currentGoalId,
  DateTime? lastGoalShownDate,
  bool? goalPromptSkipped,
  bool? goalOnboardingCompleted,
  String? morningNotificationTime,
  String? eveningNotificationTime,
  Map<String, dynamic>? notificationPreferences,
  DateTime? lastAppOpened,
  bool? notificationOnboardingCompleted,
  double? timezoneOffset,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'email': email,
      'uid': uid,
      'display_name': displayName,
      'users': users,
      'photo_url': photoUrl,
      'created_time': createdTime,
      'phone_number': phoneNumber,
      'current_goal_id': currentGoalId,
      'last_goal_shown_date': lastGoalShownDate,
      'goal_prompt_skipped': goalPromptSkipped,
      'goal_onboarding_completed': goalOnboardingCompleted,
      'morning_notification_time': morningNotificationTime,
      'evening_notification_time': eveningNotificationTime,
      'notification_preferences': notificationPreferences,
      'last_app_opened': lastAppOpened,
      'notification_onboarding_completed': notificationOnboardingCompleted,
      'timezone_offset': timezoneOffset,
    }.withoutNulls,
  );
  return firestoreData;
}
class UsersRecordDocumentEquality implements Equality<UsersRecord> {
  const UsersRecordDocumentEquality();
  @override
  bool equals(UsersRecord? e1, UsersRecord? e2) {
    return e1?.email == e2?.email &&
        e1?.uid == e2?.uid &&
        e1?.displayName == e2?.displayName &&
        e1?.users == e2?.users &&
        e1?.photoUrl == e2?.photoUrl &&
        e1?.createdTime == e2?.createdTime &&
        e1?.phoneNumber == e2?.phoneNumber &&
        e1?.currentGoalId == e2?.currentGoalId &&
        e1?.lastGoalShownDate == e2?.lastGoalShownDate &&
        e1?.goalPromptSkipped == e2?.goalPromptSkipped &&
        e1?.goalOnboardingCompleted == e2?.goalOnboardingCompleted &&
        e1?.morningNotificationTime == e2?.morningNotificationTime &&
        e1?.eveningNotificationTime == e2?.eveningNotificationTime &&
        e1?.notificationPreferences == e2?.notificationPreferences &&
        e1?.lastAppOpened == e2?.lastAppOpened &&
        e1?.notificationOnboardingCompleted == e2?.notificationOnboardingCompleted &&
        e1?.timezoneOffset == e2?.timezoneOffset;
  }
  @override
  int hash(UsersRecord? e) => const ListEquality().hash([
        e?.email,
        e?.uid,
        e?.displayName,
        e?.users,
        e?.photoUrl,
        e?.createdTime,
        e?.phoneNumber,
        e?.currentGoalId,
        e?.lastGoalShownDate,
        e?.goalPromptSkipped,
        e?.goalOnboardingCompleted,
        e?.morningNotificationTime,
        e?.eveningNotificationTime,
        e?.notificationPreferences,
        e?.lastAppOpened,
        e?.notificationOnboardingCompleted,
        e?.timezoneOffset,
      ]);
  @override
  bool isValidKey(Object? o) => o is UsersRecord;
}
