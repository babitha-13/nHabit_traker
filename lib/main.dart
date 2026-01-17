import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:habit_tracker/Helper/Firebase/firebase_setup.dart';
import 'package:habit_tracker/Helper/Helpers/login_response.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/Helpers/app_state.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/Engagement%20Notifications/engagement_tracker.dart';
import 'package:habit_tracker/Helper/Helpers/global_route_observer.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/timer_notification_service.dart';
import 'package:habit_tracker/Helper/Helpers/sharedPreference.dart';
import 'package:habit_tracker/Helper/Helpers/sound_helper.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/Screens/Authentication/authentication.dart';
import 'package:habit_tracker/Screens/Home/Home.dart';
import 'package:habit_tracker/Screens/Authentication/splash.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'Helper/Helpers/flutter_flow_theme.dart';
import 'Helper/Helpers/resource_tracker.dart';
import 'debug_log_stub.dart'
    if (dart.library.io) 'debug_log_io.dart'
    if (dart.library.html) 'debug_log_web.dart';

SharedPref sharedPref = SharedPref();
LoginResponse users = LoginResponse();
// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// #region agent log
void _logMainDebug(String location, Map<String, dynamic> data) {
  try {
    final logEntry = {
      'id': 'log_${DateTime.now().millisecondsSinceEpoch}_main',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': 'main.dart:$location',
      'message': data['event'] ?? 'debug',
      'data': data,
      'sessionId': 'debug-session',
      'runId': 'run1',
    };
    writeDebugLog(jsonEncode(logEntry));
  } catch (e) {
    // Silently fail to avoid breaking app
  }
}

// #endregion

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reset hot reload flag on hot restart (main() is called)
  _MyAppState._hasResetOnHotReload = false;
  // #region agent log
  _logMainDebug('main', {
    'hypothesisId': 'A',
    'event': 'main_start',
    'observerCount_before': NotificationCenter.observerCount()
  });
  // #endregion
  // Ensure stale observers/optimistic ops/caches are cleared on hot restart.
  NotificationCenter.reset();
  // Reset FirestoreCacheService listeners flag so it can set up listeners again
  FirestoreCacheService.resetListenersSetup();
  // Reset resource tracker
  ResourceTracker.reset();
  // #region agent log
  _logMainDebug('main', {
    'hypothesisId': 'A',
    'event': 'notificationCenter_reset',
    'observerCount_after': NotificationCenter.observerCount(),
    'resources': ResourceTracker.getCounts()
  });
  // #endregion
  OptimisticOperationTracker.clearAll();
  // Start periodic cleanup for optimistic operations
  OptimisticOperationTracker.startPeriodicCleanup();
  FirestoreCacheService().invalidateAllCache();
  // #region agent log
  _logMainDebug('main', {
    'hypothesisId': 'D',
    'event': 'cache_invalidated',
    'cache': FirestoreCacheService().debugCounts(),
    'observerCount': NotificationCenter.observerCount(),
    'resources': ResourceTracker.getCounts()
  });
  // #endregion
  // Only initialize Android-specific services when not running on web
  if (!kIsWeb) {
    await AndroidAlarmManager.initialize();
  }

  // Initialize Firebase with error handling for hot restart
  // On restart, Firebase may already be initialized from a previous session
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    // Check if Firebase is actually available despite the initialization error
    // This happens on hot restart when Firebase was already initialized
    try {
      Firebase.app(); // Will throw if not initialized
      print('Firebase already initialized (hot restart)');
    } catch (_) {
      // Firebase really isn't initialized - this is a real error
      print('Firebase initialization failed: $e');
      rethrow;
    }
  }

  await FlutterFlowTheme.initialize();
  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();

  // Initialize sound helper with error handling for hot restart
  try {
    await SoundHelper().initialize();
  } catch (e) {
    print('Sound helper init warning: $e');
  }
  // Initialize notification service only on mobile platforms
  if (!kIsWeb) {
    await NotificationService.initialize();
    // Initialize timer notification service
    await TimerNotificationService.initialize();
    // Check permissions status first
    final hasPermissions = await NotificationService.checkPermissions();
    // Request notification permissions if not granted
    if (!hasPermissions) {
      final permissionGranted = await NotificationService.requestPermissions();
      if (!permissionGranted) {}
    } else {}
  }
  // Note: Task/habit reminders are scheduled in Home.dart after user authentication
  // to ensure currentUserUid is available
  runApp(ChangeNotifierProvider(
    create: (context) => appState,
    child: const MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  // This widget is the root of your application.
  @override
  State<MyApp> createState() => _MyAppState();
  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode themeMode = FlutterFlowTheme.themeMode;
  late Stream<BaseAuthUser> userStream;
  StreamSubscription<BaseAuthUser>? _userStreamSub;
  StreamSubscription? _jwtStreamSub;
  Timer? _diagnosticTimer;
  // Static flag to track if we've already reset observers on hot reload
  // This prevents multiple resets when multiple widgets call initState()
  static bool _hasResetOnHotReload = false;

  @override
  void initState() {
    super.initState();
    // CRITICAL: Reset observers on hot reload (when initState is called but main() wasn't)
    // On hot reload, main() is NOT called, so observers accumulate
    // Check if observers exist AND we haven't already reset (indicating a hot reload scenario)
    final observerCountBefore = NotificationCenter.observerCount();
    if (observerCountBefore > 6 && !_hasResetOnHotReload) {
      // More than just FirestoreCacheService observers - likely a hot reload
      // Set flag to prevent multiple resets
      _hasResetOnHotReload = true;
      // #region agent log
      _logDebug('initState', {
        'hypothesisId': 'K',
        'event': 'hot_reload_detected',
        'observerCount_before': observerCountBefore
      });
      // #endregion
      NotificationCenter.reset();
      FirestoreCacheService.resetListenersSetup();
      FirestoreCacheService().ensureListenersSetup();
      ResourceTracker.reset();
      // #region agent log
      _logDebug('initState', {
        'hypothesisId': 'K',
        'event': 'observers_reset_on_hot_reload',
        'observerCount_after': NotificationCenter.observerCount()
      });
      // #endregion
    }
    // #region agent log
    _logDebug('initState', {
      'hypothesisId': 'B',
      'event': 'initState_called',
      'instanceHash': hashCode,
      'hasUserSub_before': _userStreamSub != null,
      'hasJwtSub_before': _jwtStreamSub != null
    });
    // #endregion
    // CRITICAL FIX: Cancel existing subscriptions before creating new ones
    // This prevents memory leaks on hot restart where dispose() is not called
    _userStreamSub?.cancel();
    _jwtStreamSub?.cancel();
    // #region agent log
    _logDebug(
        'initState', {'hypothesisId': 'B', 'event': 'old_streams_cancelled'});
    // #endregion
    WidgetsBinding.instance.addObserver(this);
    ResourceTracker.incrementWidgetsBindingObserver();
    // #region agent log
    _logDebug('initState', {
      'hypothesisId': 'C',
      'event': 'observer_added',
      'observerCount': NotificationCenter.observerCount(),
      'resources': ResourceTracker.getCounts()
    });
    // #endregion
    userStream = habitTrackerFirebaseUserStream();
    _userStreamSub = userStream.listen((user) {
      // User authentication state changes handled here
      // Categories are created on signup and on-demand when needed
    });
    // #region agent log
    _logDebug('initState', {
      'hypothesisId': 'B',
      'event': 'userStream_subscribed',
      'hasSub': _userStreamSub != null
    });
    // #endregion
    _jwtStreamSub = jwtTokenStream.listen((_) {});
    // #region agent log
    _logDebug('initState', {
      'hypothesisId': 'B',
      'event': 'jwtStream_subscribed',
      'hasSub': _jwtStreamSub != null,
      'observerCount': NotificationCenter.observerCount(),
      'cache': FirestoreCacheService().debugCounts()
    });
    // #endregion
    // Diagnostic timer to track resource accumulation
    _diagnosticTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // Only check if widget is still mounted to prevent disposed view errors
      if (mounted) {
        // CRITICAL: Check for observer accumulation and reset if detected
        // This handles cases where hot reload doesn't trigger initState() detection
        final observerCount = NotificationCenter.observerCount();
        if (observerCount > 50) {
          // Excessive observer count indicates a leak
          // Log it but DO NOT RESET - resetting breaks active pages
          print('WARNING: Excessive observers detected ($observerCount)');
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // #region agent log
    _logDebug('didChangeDependencies', {
      'hypothesisId': 'M',
      'event': 'didChangeDependencies_called',
      'instanceHash': hashCode,
      'observerCount': NotificationCenter.observerCount(),
      'resources': ResourceTracker.getCounts()
    });
    // #endregion
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // #region agent log
    _logDebug('didUpdateWidget', {
      'hypothesisId': 'M',
      'event': 'didUpdateWidget_called',
      'instanceHash': hashCode,
      'observerCount': NotificationCenter.observerCount(),
      'resources': ResourceTracker.getCounts()
    });
    // #endregion
  }

  @override
  void dispose() {
    // #region agent log
    _logDebug('dispose', {
      'hypothesisId': 'B',
      'event': 'dispose_called',
      'instanceHash': hashCode,
      'hasUserSub': _userStreamSub != null,
      'hasJwtSub': _jwtStreamSub != null,
      'observerCount': NotificationCenter.observerCount(),
      'resources_before': ResourceTracker.getCounts()
    });
    // #endregion
    WidgetsBinding.instance.removeObserver(this);
    ResourceTracker.decrementWidgetsBindingObserver();
    _userStreamSub?.cancel();
    _jwtStreamSub?.cancel();
    // #region agent log
    _logDebug('dispose', {
      'hypothesisId': 'B',
      'event': 'streams_cancelled',
      'observerCount': NotificationCenter.observerCount()
    });
    // #endregion
    _diagnosticTimer?.cancel();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload hook for diagnostics and cleanup on web.
    // #region agent log
    _logDebug('reassemble', {
      'hypothesisId': 'A',
      'event': 'reassemble_start',
      'instanceHash': hashCode,
      'observerCount_before': NotificationCenter.observerCount(),
      'cache_before': FirestoreCacheService().debugCounts(),
      'hasUserSub': _userStreamSub != null,
      'hasJwtSub': _jwtStreamSub != null
    });
    // #endregion

    // Cancel existing timer to prevent disposed view errors
    _diagnosticTimer?.cancel();

    /*
    NotificationCenter.reset();
    // Reset FirestoreCacheService listeners flag so it can set up listeners again
    FirestoreCacheService.resetListenersSetup();
    FirestoreCacheService().ensureListenersSetup();
    ResourceTracker.reset();
    // #region agent log
    _logDebug('reassemble', {
      'hypothesisId': 'A',
      'event': 'notificationCenter_reset',
      'observerCount_after': NotificationCenter.observerCount(),
      'resources': ResourceTracker.getCounts()
    });
    // #endregion
    OptimisticOperationTracker.clearAll();
    FirestoreCacheService().invalidateAllCache();
    // #region agent log
    _logDebug('reassemble', {
      'hypothesisId': 'D',
      'event': 'cache_invalidated',
      'cache_after': FirestoreCacheService().debugCounts(),
      'observerCount': NotificationCenter.observerCount(),
      'resources': ResourceTracker.getCounts()
    });
    // #endregion
    */

    // Diagnostic timer to track resource accumulation
    _diagnosticTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        // Check for observer accumulation
        final observerCount = NotificationCenter.observerCount();
        if (observerCount > 50) {
          print('WARNING: Excessive observers detected ($observerCount)');
        }
      }
    });
  }

  // #region agent log
  void _logDebug(String location, Map<String, dynamic> data) {
    try {
      final logEntry = {
        'id': 'log_${DateTime.now().millisecondsSinceEpoch}_${hashCode}',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'location': 'main.dart:$location',
        'message': data['event'] ?? 'debug',
        'data': data,
        'sessionId': 'debug-session',
        'runId': 'run1',
      };
      writeDebugLog(jsonEncode(logEntry));
    } catch (e) {
      // Silently fail to avoid breaking app
    }
  }
  // #endregion

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Record app opened when app resumes
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        EngagementTracker.recordAppOpened(userId);
      }
    }
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });
  ThemeData _buildThemeData(FlutterFlowTheme theme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: theme.primary,
        onPrimary: isDark ? const Color(0xFF181C1F) : Colors.white,
        secondary: theme.secondary,
        onSecondary: isDark ? const Color(0xFF181C1F) : Colors.white,
        tertiary: theme.tertiary,
        onTertiary: isDark ? const Color(0xFF181C1F) : const Color(0xFF2C2C2C),
        error: theme.error,
        onError: Colors.white,
        surface: theme.secondaryBackground,
        onSurface: theme.primaryText,
        background: theme.primaryBackground,
        onBackground: theme.primaryText,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: theme.primary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: isDark ? const Color(0xFF181C1F) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.primary,
          side: BorderSide(color: theme.surfaceBorderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = LightModeTheme();
    final darkTheme = DarkModeTheme();

    return MaterialApp(
      title: 'Habit Tracker',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: _buildThemeData(lightTheme, Brightness.light),
      darkTheme: _buildThemeData(darkTheme, Brightness.dark),
      themeMode: themeMode,
      home: const Splash(),
      routes: <String, WidgetBuilder>{
        home: (BuildContext context) => const Home(),
        login: (BuildContext context) => const SignIn(),
      },
      navigatorObservers: [globalRouteObserver],
    );
  }
}
