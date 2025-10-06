import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class CategoryRecord extends FirestoreRecord {
  CategoryRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "weight" field.
  double? _weight;
  double get weight => _weight ?? 1.0;
  bool hasWeight() => _weight != null;

  // "color" field.
  String? _color;
  String get color => _color ?? '#2196F3';
  bool hasColor() => _color != null;

  // "isActive" field.
  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  // "createdTime" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "lastUpdated" field.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;

  // "userId" field.
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;

  // "categoryType" field.
  String? _categoryType;
  String get categoryType {
    if (_categoryType != null && _categoryType!.isNotEmpty) {
      return _categoryType!;
    }
    if (name == 'Inbox') {
      return 'task';
    }
    // Default to habit for backwards compatibility for other categories
    return 'habit';
  }

  bool hasCategoryType() => _categoryType != null;

  // "isSystemCategory" field.
  bool? _isSystemCategory;
  bool get isSystemCategory => _isSystemCategory ?? false;
  bool hasIsSystemCategory() => _isSystemCategory != null;

  void _initializeFields() {
    _uid = snapshotData['uid'] as String?;
    _name = snapshotData['name'] as String?;
    _description = snapshotData['description'] as String?;

    final rawWeight = snapshotData['weight'];
    if (rawWeight is int) {
      _weight = rawWeight.toDouble();
    } else if (rawWeight is double) {
      _weight = rawWeight;
    } else if (rawWeight is String) {
      _weight = double.tryParse(rawWeight);
    } else {
      _weight = null;
    }
    _color = snapshotData['color'] as String?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _userId = snapshotData['userId'] as String?;
    _categoryType = snapshotData['categoryType'] as String?;
    _isSystemCategory = snapshotData['isSystemCategory'] as bool?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('categories');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('categories');

  static Stream<CategoryRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => CategoryRecord.fromSnapshot(s));

  static Future<CategoryRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => CategoryRecord.fromSnapshot(s));

  static CategoryRecord fromSnapshot(DocumentSnapshot snapshot) =>
      CategoryRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static CategoryRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      CategoryRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'CategoryRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is CategoryRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createCategoryRecordData({
  String? uid,
  String? name,
  String? description,
  double? weight,
  String? color,
  bool? isActive,
  DateTime? createdTime,
  DateTime? lastUpdated,
  String? userId,
  required String categoryType, // REQUIRED - no categories without type!
  bool? isSystemCategory,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'uid': uid,
      'name': name,
      'description': description,
      'weight': weight,
      'color': color,
      'isActive': isActive,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'userId': userId,
      'categoryType': categoryType,
      'isSystemCategory': isSystemCategory,
    }.withoutNulls,
  );

  return firestoreData;
}

class CategoryRecordDocumentEquality implements Equality<CategoryRecord> {
  const CategoryRecordDocumentEquality();

  @override
  bool equals(CategoryRecord? e1, CategoryRecord? e2) {
    return e1?.uid == e2?.uid &&
        e1?.name == e2?.name &&
        e1?.description == e2?.description &&
        e1?.weight == e2?.weight &&
        e1?.color == e2?.color &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.userId == e2?.userId &&
        e1?.categoryType == e2?.categoryType &&
        e1?.isSystemCategory == e2?.isSystemCategory;
  }

  @override
  int hash(CategoryRecord? e) => const ListEquality().hash([
        e?.uid,
        e?.name,
        e?.description,
        e?.weight,
        e?.color,
        e?.isActive,
        e?.createdTime,
        e?.lastUpdated,
        e?.userId,
        e?.categoryType,
        e?.isSystemCategory,
      ]);

  @override
  bool isValidKey(Object? o) => o is CategoryRecord;
}
