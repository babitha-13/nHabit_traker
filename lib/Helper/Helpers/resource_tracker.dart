/// Global resource tracker to detect memory leaks on hot reload
class ResourceTracker {
  static int _activeFirestoreListeners = 0;
  static int _activeTimers = 0;
  static int _activePostFrameCallbacks = 0;
  static int _activeWidgetsBindingObservers = 0;
  
  static void incrementFirestoreListener() {
    _activeFirestoreListeners++;
  }
  
  static void decrementFirestoreListener() {
    _activeFirestoreListeners = (_activeFirestoreListeners > 0) ? _activeFirestoreListeners - 1 : 0;
  }
  
  static void incrementTimer() {
    _activeTimers++;
  }
  
  static void decrementTimer() {
    _activeTimers = (_activeTimers > 0) ? _activeTimers - 1 : 0;
  }
  
  static void incrementPostFrameCallback() {
    _activePostFrameCallbacks++;
  }
  
  static void decrementPostFrameCallback() {
    _activePostFrameCallbacks = (_activePostFrameCallbacks > 0) ? _activePostFrameCallbacks - 1 : 0;
  }
  
  static void incrementWidgetsBindingObserver() {
    _activeWidgetsBindingObservers++;
  }
  
  static void decrementWidgetsBindingObserver() {
    _activeWidgetsBindingObservers = (_activeWidgetsBindingObservers > 0) ? _activeWidgetsBindingObservers - 1 : 0;
  }
  
  static Map<String, int> getCounts() {
    return {
      'firestoreListeners': _activeFirestoreListeners,
      'timers': _activeTimers,
      'postFrameCallbacks': _activePostFrameCallbacks,
      'widgetsBindingObservers': _activeWidgetsBindingObservers,
    };
  }
  
  static void reset() {
    _activeFirestoreListeners = 0;
    _activeTimers = 0;
    _activePostFrameCallbacks = 0;
    _activeWidgetsBindingObservers = 0;
  }
}
