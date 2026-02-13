import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:habit_tracker/Helper/Firebase/firebase_setup.dart';
import 'package:habit_tracker/services/login_response.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/services/app_state.dart';
import 'package:habit_tracker/core/constants.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/engagement_tracker.dart';
import 'package:habit_tracker/services/global_route_observer.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/features/Timer/Helpers/timer_notification_service.dart';
import 'package:habit_tracker/core/services/local_storage_services.dart';
import 'package:habit_tracker/services/sound_helper.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/features/Authentication/authentication.dart';
import 'package:habit_tracker/features/Home/presentation/home_screen.dart';
import 'package:habit_tracker/features/Authentication/splash.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'core/flutter_flow_theme.dart';
import 'services/resource_tracker.dart';

SharedPref sharedPref = SharedPref();
LoginResponse users = LoginResponse();
// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const bool _useFirebaseFunctionsEmulator =
    bool.fromEnvironment('USE_FIREBASE_FUNCTIONS_EMULATOR', defaultValue: false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reset hot reload flag on hot restart (main() is called)
  _MyAppState._hasResetOnHotReload = false;
  // Ensure stale observers/optimistic ops/caches are cleared on hot restart.
  NotificationCenter.reset();
  // Reset FirestoreCacheService listeners flag so it can set up listeners again
  FirestoreCacheService.resetListenersSetup();
  // Reset resource tracker
  ResourceTracker.reset();
  OptimisticOperationTracker.clearAll();
  // Start periodic cleanup for optimistic operations
  OptimisticOperationTracker.startPeriodicCleanup();
  FirestoreCacheService().invalidateAllCache();
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

  if (kDebugMode && _useFirebaseFunctionsEmulator) {
    final host = kIsWeb
        ? 'localhost'
        : (defaultTargetPlatform == TargetPlatform.android
            ? '10.0.2.2'
            : '127.0.0.1');
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    print('Firebase Functions emulator enabled at $host:5001');
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
      NotificationCenter.reset();
      FirestoreCacheService.resetListenersSetup();
      FirestoreCacheService().ensureListenersSetup();
      ResourceTracker.reset();
    }
    // CRITICAL FIX: Cancel existing subscriptions before creating new ones
    // This prevents memory leaks on hot restart where dispose() is not called
    _userStreamSub?.cancel();
    _jwtStreamSub?.cancel();
    WidgetsBinding.instance.addObserver(this);
    ResourceTracker.incrementWidgetsBindingObserver();
    userStream = habitTrackerFirebaseUserStream();
    _userStreamSub = userStream.listen((user) {
      // User authentication state changes handled here
      // Categories are created on signup and on-demand when needed
    });
    _jwtStreamSub = jwtTokenStream.listen((_) {});
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
  }

  @override
  void didUpdateWidget(covariant MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ResourceTracker.decrementWidgetsBindingObserver();
    _userStreamSub?.cancel();
    _jwtStreamSub?.cancel();
    _diagnosticTimer?.cancel();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload hook for diagnostics and cleanup on web.
    // Cancel existing timer to prevent disposed view errors
    _diagnosticTimer?.cancel();

    /*
    NotificationCenter.reset();
    // Reset FirestoreCacheService listeners flag so it can set up listeners again
    FirestoreCacheService.resetListenersSetup();
    FirestoreCacheService().ensureListenersSetup();
    ResourceTracker.reset();
    OptimisticOperationTracker.clearAll();
    FirestoreCacheService().invalidateAllCache();
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
