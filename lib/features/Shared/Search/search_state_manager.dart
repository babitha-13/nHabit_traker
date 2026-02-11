import 'dart:async';

/// Manages global search state for the application
/// Allows communication between Home.dart (where search UI lives) and page widgets
class SearchStateManager {
  static final SearchStateManager _instance = SearchStateManager._internal();
  factory SearchStateManager() => _instance;
  SearchStateManager._internal();
  String _query = '';
  String _pendingQuery = ''; // Query waiting to be debounced
  bool _isSearchOpen = false;
  final List<Function(String)> _listeners = [];
  final List<Function(bool)> _searchOpenListeners = [];
  Timer? _debounceTimer;

  /// Update the current search query with debouncing (400ms delay)
  /// This reduces unnecessary filtering operations while user is typing
  void updateQuery(String query) {
    _pendingQuery = query;
    // Cancel previous timer if exists
    _debounceTimer?.cancel();
    // Create new timer to debounce the update
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (_query != _pendingQuery) {
        _query = _pendingQuery;
        for (var listener in _listeners) {
          listener(_query);
        }
      }
    });
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

  /// Clear the current search query (immediate, no debounce)
  void clearQuery() {
    _debounceTimer?.cancel();
    _query = '';
    _pendingQuery = '';
    for (var listener in _listeners) {
      listener(_query);
    }
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
