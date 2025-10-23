import 'package:firebase_core/firebase_core.dart';
import 'package:habit_tracker/Helper/Firebase/firebase_setup.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/finalize_habit_data.dart';
import 'package:habit_tracker/Helper/backend/background_scheduler.dart';
import 'package:habit_tracker/Helper/backend/goal_service.dart';
import 'package:habit_tracker/Helper/utils/notification_service.dart';
import 'package:habit_tracker/Helper/backend/reminder_scheduler.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/sharedPreference.dart';
import 'package:habit_tracker/Screens/Authentication/authentication.dart';
import 'package:habit_tracker/Screens/Home/Home.dart';
import 'package:habit_tracker/Screens/Splash/splash.dart';
import 'package:habit_tracker/Screens/Goals/goal_dialog.dart';
import 'package:habit_tracker/Screens/Goals/goal_onboarding_dialog.dart';
import 'package:habit_tracker/Helper/utils/app_state.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'Helper/utils/flutter_flow_theme.dart';
import 'Helper/utils/constants.dart';

SharedPref sharedPref = SharedPref();
LoginResponse users = LoginResponse();

// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FlutterFlowTheme.initialize();
  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();

  // Initialize background scheduler for day-end processing
  BackgroundScheduler.initialize();

  // Initialize notification service
  print('DEBUG: Starting notification service initialization...');
  await NotificationService.initialize();
  print('DEBUG: Notification service initialized');

  // Check permissions status first
  print('DEBUG: Checking permissions status...');
  final hasPermissions = await NotificationService.checkPermissions();
  print('DEBUG: Current permissions status: $hasPermissions');

  // Request notification permissions if not granted
  if (!hasPermissions) {
    print('DEBUG: Requesting notification permissions...');
    final permissionGranted = await NotificationService.requestPermissions();
    print('DEBUG: Permission request result: $permissionGranted');

    if (!permissionGranted) {
      print(
          'WARNING: Notification permissions not granted. Notifications may not work properly.');
    }
  } else {
    print('DEBUG: Notification permissions already granted');
  }

  // Schedule all pending reminders
  await ReminderScheduler.scheduleAllPendingReminders();

  // Check for expired snoozes and reschedule
  await ReminderScheduler.checkExpiredSnoozes();

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

class _MyAppState extends State<MyApp> {
  ThemeMode themeMode = FlutterFlowTheme.themeMode;
  late Stream<BaseAuthUser> userStream;
  Timer? _goalCheckTimer;
  bool _goalShownThisSession = false;

  @override
  void initState() {
    super.initState();
    userStream = habitTrackerFirebaseUserStream();

    userStream.listen((user) {
      if (user.uid != null && user.uid!.isNotEmpty) {
        finalizeActivityData(user.uid!);
        // Migration removed - all leaks plugged at source
        // Categories now always created with proper categoryType

        // Start goal checking timer for this user
        _startGoalCheckTimer(user.uid!);
      }
    });
    jwtTokenStream.listen((_) {});
  }

  void _startGoalCheckTimer(String userId) {
    // Check every 5 minutes for goal display conditions
    _goalCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!mounted || _goalShownThisSession) return;

      try {
        // First check if onboarding should be shown
        final shouldShowOnboarding =
            await GoalService.shouldShowOnboardingGoal(userId);
        if (shouldShowOnboarding && mounted) {
          _showOnboardingDialog();
          _goalShownThisSession = true;
          return;
        }

        // If no onboarding needed, check for regular goal display
        final shouldShow = await GoalService.shouldShowGoal(userId);
        if (shouldShow && mounted) {
          _showGoalDialog();
          _goalShownThisSession = true;
        }
      } catch (e) {
        print('Goal check timer error: $e');
      }
    });
  }

  void _showGoalDialog() {
    // Show goal dialog with a slight delay to ensure UI is ready
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalDialog(),
        );
      }
    });
  }

  void _showOnboardingDialog() {
    // Show onboarding dialog with a slight delay to ensure UI is ready
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const GoalOnboardingDialog(),
        );
      }
    });
  }

  @override
  void dispose() {
    _goalCheckTimer?.cancel();
    super.dispose();
  }

  void setThemeMode(ThemeMode mode) => safeSetState(() {
        themeMode = mode;
        FlutterFlowTheme.saveThemeMode(mode);
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Splash(),
      routes: <String, WidgetBuilder>{
        home: (BuildContext context) => const Home(),
        login: (BuildContext context) => const SignIn(),
      },
    );
  }
}
