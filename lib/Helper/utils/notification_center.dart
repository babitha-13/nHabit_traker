class NotificationCenter {
  static final NotificationCenter _default = NotificationCenter();
  final _observerMap = {};
  final _segmentKey = '-888-';
  static void post(String? name, [Object? param]) {
    if (name != null) {
      NotificationCenter._default._observerMap.forEach((key, value) {
        var keyList= key.toString().split("-888-");
        if(keyList.first == name){
          value(param);
        }
      });
    } else {
    }
  }
  static void addObserver(Object? observer, String? name, [void Function(Object param)? block]) {
    if (observer != null && name != null) {
      final key = name +
          NotificationCenter._default._segmentKey +
          observer.hashCode.toString();
      NotificationCenter._default._observerMap[key] = block;
    }
  }
  static void removeObserver(Object observer, [String? name]) {
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
      NotificationCenter._default._observerMap.removeWhere((key, value) => keysToRemove.contains(key));
    }
  }
}
