/// Manages global search state for the application
/// Allows communication between Home.dart (where search UI lives) and page widgets
class SearchStateManager {
  static final SearchStateManager _instance = SearchStateManager._internal();
  factory SearchStateManager() => _instance;
  SearchStateManager._internal();
  String _query = '';
  final List<Function(String)> _listeners = [];
  /// Update the current search query and notify all listeners
  void updateQuery(String query) {
    _query = query;
    for (var listener in _listeners) {
      listener(query);
    }
  }
  /// Add a listener to be notified when search query changes
  void addListener(Function(String) listener) {
    _listeners.add(listener);
  }
  /// Remove a listener from notifications
  void removeListener(Function(String) listener) {
    _listeners.remove(listener);
  }
  /// Get the current search query
  String get currentQuery => _query;
  /// Clear the current search query
  void clearQuery() {
    updateQuery('');
  }
  /// Check if search is currently active
  bool get isSearchActive => _query.isNotEmpty;
}
