/// Manages global search state for the application
/// Allows communication between Home.dart (where search UI lives) and page widgets
class SearchStateManager {
  static final SearchStateManager _instance = SearchStateManager._internal();
  factory SearchStateManager() => _instance;
  SearchStateManager._internal();
  String _query = '';
  bool _isSearchOpen = false;
  final List<Function(String)> _listeners = [];
  final List<Function(bool)> _searchOpenListeners = [];

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

  /// Check if search is currently active (query has characters)
  bool get isSearchActive => _query.isNotEmpty;

  /// Tracks whether the search UI is currently visible
  bool get isSearchOpen => _isSearchOpen;

  /// Update the visibility state and notify listeners
  void setSearchOpen(bool isOpen) {
    if (_isSearchOpen == isOpen) return;
    _isSearchOpen = isOpen;
    for (var listener in _searchOpenListeners) {
      listener(isOpen);
    }
  }

  /// Add a listener for visibility changes
  void addSearchOpenListener(Function(bool) listener) {
    _searchOpenListeners.add(listener);
  }

  /// Remove a visibility listener
  void removeSearchOpenListener(Function(bool) listener) {
    _searchOpenListeners.remove(listener);
  }
}
