import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:habit_tracker/Helper/Firebase/firebase_setup.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/finalize_habit_data.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/app_state.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/engagement_tracker.dart';
import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/utils/sharedPreference.dart';
import 'package:habit_tracker/Screens/Authentication/authentication.dart';
import 'package:habit_tracker/Screens/Home/Home.dart';
import 'package:habit_tracker/Screens/Splash/splash.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'Helper/utils/flutter_flow_theme.dart';

SharedPref sharedPref = SharedPref();
LoginResponse users = LoginResponse();
// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only initialize Android-specific services when not running on web
  if (!kIsWeb) {
    await AndroidAlarmManager.initialize();
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FlutterFlowTheme.initialize();
  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();
  // Initialize notification service only on mobile platforms
  if (!kIsWeb) {
    await NotificationService.initialize();
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    userStream = habitTrackerFirebaseUserStream();
    userStream.listen((user) {
      if (user.uid != null && user.uid!.isNotEmpty) {
        finalizeActivityData(user.uid!);
        // Migration removed - all leaks plugged at source
        // Categories now always created with proper categoryType
      }
    });
    jwtTokenStream.listen((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
        onPrimary: isDark 
            ? const Color(0xFF181C1F) 
            : Colors.white,
        secondary: theme.secondary,
        onSecondary: isDark 
            ? const Color(0xFF181C1F) 
            : Colors.white,
        tertiary: theme.tertiary,
        onTertiary: isDark 
            ? const Color(0xFF181C1F) 
            : const Color(0xFF2C2C2C),
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
          foregroundColor: isDark 
              ? const Color(0xFF181C1F) 
              : Colors.white,
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
    );
  }
}
