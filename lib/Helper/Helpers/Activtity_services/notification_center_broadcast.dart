import 'dart:convert';
import 'package:habit_tracker/debug_log_stub.dart'
    if (dart.library.io) 'package:habit_tracker/debug_log_io.dart'
    if (dart.library.html) 'package:habit_tracker/debug_log_web.dart';

/// Notifcation center for receiving broadcasts
///
class NotificationCenter {
  static final NotificationCenter _default = NotificationCenter();
  final Map<String, void Function(Object?)?> _observerMap = {};
  final _segmentKey = '-888-';
  static void reset() {
    final countBefore = NotificationCenter._default._observerMap.length;
    NotificationCenter._default._observerMap.clear();
    // #region agent log
    _logObserverChange('reset', null, null, countBefore, 0);
    // #endregion
  }

  static int observerCount() {
    return NotificationCenter._default._observerMap.length;
  }
  static void post(String? name, [Object? param]) {
    if (name == null) return;
    NotificationCenter._default._observerMap.forEach((key, value) {
      if (value == null) return;
      var keyList =
          key.toString().split(NotificationCenter._default._segmentKey);
      if (keyList.first == name) {
        value(param);
      }
    });
  }

  static void addObserver(Object? observer, String? name,
      [void Function(Object?)? block]) {
    if (observer != null && name != null && block != null) {
      final countBefore = NotificationCenter._default._observerMap.length;
      final key = name +
          NotificationCenter._default._segmentKey +
          observer.hashCode.toString();
      NotificationCenter._default._observerMap[key] = block;
      // #region agent log
      _logObserverChange('addObserver', observer, name, countBefore, NotificationCenter._default._observerMap.length);
      // #endregion
    }
  }

  static void removeObserver(Object observer, [String? name]) {
    final countBefore = NotificationCenter._default._observerMap.length;
    if (name != null) {
      final key = name +
          NotificationCenter._default._segmentKey +
          observer.hashCode.toString();
      NotificationCenter._default._observerMap.remove(key);
    } else {
      final keys = NotificationCenter._default._observerMap.keys;
      final List<String> keysToRemove = [];
      for (var key in keys) {
        final array = key.split(NotificationCenter._default._segmentKey);
        if (array.length == 2) {
          final hasCode = array[1];
          if (hasCode == observer.hashCode.toString()) {
            keysToRemove.add(key);
          }
        }
      }
      NotificationCenter._default._observerMap
          .removeWhere((key, value) => keysToRemove.contains(key));
    }
    // #region agent log
    _logObserverChange('removeObserver', observer, name, countBefore, NotificationCenter._default._observerMap.length);
    // #endregion
  }
  
  // #region agent log
  static void _logObserverChange(String action, Object? observer, String? name, int countBefore, int countAfter) {
    try {
      writeDebugLog(jsonEncode({
        'id': 'log_${DateTime.now().millisecondsSinceEpoch}_notificationCenter',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'location': 'notification_center_broadcast.dart:$action',
        'message': 'observer_$action',
        'data': {
          'hypothesisId': 'J',
          'event': 'observer_$action',
          'observerHash': observer?.hashCode,
          'observerType': observer?.runtimeType.toString(),
          'name': name,
          'countBefore': countBefore,
          'countAfter': countAfter,
        },
        'sessionId': 'debug-session',
        'runId': 'run1',
      }));
    } catch (e) {
      // Silently fail
    }
  }
  // #endregion
}
