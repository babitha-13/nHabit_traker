class CalendarEventMetadata {
  final String instanceId;
  final int sessionIndex; // Index in timeLogSessions array
  final String activityName;
  final String activityType; // 'task', 'habit', 'essential'
  final String? templateId;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColorHex;

  CalendarEventMetadata({
    required this.instanceId,
    required this.sessionIndex,
    required this.activityName,
    required this.activityType,
    this.templateId,
    this.categoryId,
    this.categoryName,
    this.categoryColorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'instanceId': instanceId,
      'sessionIndex': sessionIndex,
      'activityName': activityName,
      'activityType': activityType,
      'templateId': templateId,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'categoryColorHex': categoryColorHex,
    };
  }

  static CalendarEventMetadata? fromMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return CalendarEventMetadata(
        instanceId: data['instanceId'] as String,
        sessionIndex: data['sessionIndex'] as int,
        activityName: data['activityName'] as String,
        activityType: data['activityType'] as String,
        templateId: data['templateId'] as String?,
        categoryId: data['categoryId'] as String?,
        categoryName: data['categoryName'] as String?,
        categoryColorHex: data['categoryColorHex'] as String?,
      );
    }
    return null;
  }
}