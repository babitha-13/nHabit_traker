// lib/app_state.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
class FFAppState extends ChangeNotifier {
  static FFAppState _instance = FFAppState._internal();
  factory FFAppState() {
    return _instance;
  }
  FFAppState._internal();
  static FFAppState get instance => _instance;
  static void reset() {
    _instance = FFAppState._internal();
  }
  Future initializePersistedState() async {
    prefs = await SharedPreferences.getInstance();
    _safeInit(() {
      _hasCompletedInitialSetup =
          prefs.getBool('ff_hasCompletedInitialSetup') ??
              _hasCompletedInitialSetup;
    });
    _safeInit(() {
      _todaysDate = prefs.containsKey('ff_todaysDate')
          ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt('ff_todaysDate')!)
          : _todaysDate; // Keeps initial null if not in prefs
    });
    _safeInit(() {
      _selectedCategories =
          prefs.getStringList('ff_selectedCategories') ?? _selectedCategories;
    });
    _safeInit(() {
      _defaultImpactLevel =
          prefs.getString('ff_defaultImpactLevel') ?? _defaultImpactLevel;
    });
    _safeInit(() {
      _showCompletedHabits =
          prefs.getBool('ff_showCompletedHabits') ?? _showCompletedHabits;
    });
  }
  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }
  late SharedPreferences prefs;
  // New flag to track if the user has completed the initial habit setup.
  bool _hasCompletedInitialSetup = false;
  bool get hasCompletedInitialSetup => _hasCompletedInitialSetup;
  set hasCompletedInitialSetup(bool value) {
    _hasCompletedInitialSetup = value;
    prefs.setBool('ff_hasCompletedInitialSetup', value);
  }
  /// For identifying the date on which the app is open, for displaying the days
  /// on the calendar.
  DateTime? _todaysDate;
  DateTime? get todaysDate => _todaysDate;
  set todaysDate(DateTime? value) {
    _todaysDate = value;
    if (value != null) {
      prefs.setInt('ff_todaysDate', value.millisecondsSinceEpoch);
    } else {
      prefs.remove('ff_todaysDate');
    }
  }
  // User's selected habit categories
  List<String> _selectedCategories = [
    'Health',
    'Career',
    'Mindfulness',
    'Personal'
  ];
  List<String> get selectedCategories => _selectedCategories;
  set selectedCategories(List<String> value) {
    _selectedCategories = value;
    prefs.setStringList('ff_selectedCategories', value);
  }
  void addCategory(String category) {
    if (!_selectedCategories.contains(category)) {
      _selectedCategories.add(category);
      prefs.setStringList('ff_selectedCategories', _selectedCategories);
    }
  }
  void removeCategory(String category) {
    _selectedCategories.remove(category);
    prefs.setStringList('ff_selectedCategories', _selectedCategories);
  }
  // Default impact level for new habits
  String _defaultImpactLevel = 'Medium';
  String get defaultImpactLevel => _defaultImpactLevel;
  set defaultImpactLevel(String value) {
    _defaultImpactLevel = value;
    prefs.setString('ff_defaultImpactLevel', value);
  }
  // Whether to show completed habits in the list
  bool _showCompletedHabits = true;
  bool get showCompletedHabits => _showCompletedHabits;
  set showCompletedHabits(bool value) {
    _showCompletedHabits = value;
    prefs.setBool('ff_showCompletedHabits', value);
  }
  // Current focus mode state
  bool _isInFocusMode = false;
  bool get isInFocusMode => _isInFocusMode;
  set isInFocusMode(bool value) {
    _isInFocusMode = value;
    notifyListeners();
  }
  // Current routine being followed in focus mode
  String? _currentRoutineId;
  String? get currentRoutineId => _currentRoutineId;
  set currentRoutineId(String? value) {
    _currentRoutineId = value;
    notifyListeners();
  }
}
void _safeInit(Function() initializeField) {
  try {
    initializeField();
  } catch (_) {
    // Handle initialization error, if necessary
    // For example, log the error: print('Error initializing field: $_');
  }
}
