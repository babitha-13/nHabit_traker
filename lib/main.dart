import 'package:firebase_core/firebase_core.dart';
import 'package:habit_tracker/Helper/Firebase/firebase_setup.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/finalize_habit_data.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/utils/sharedPreference.dart';
import 'package:habit_tracker/Screens/Authentication/authentication.dart';
import 'package:habit_tracker/Screens/Home/Home.dart';
import 'package:habit_tracker/Screens/Splash/splash.dart';
import 'package:habit_tracker/Helper/utils/app_state.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'Helper/utils/flutter_flow_theme.dart';
import 'Helper/utils/constants.dart';

SharedPref sharedPref = SharedPref();
LoginResponse users = LoginResponse();
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FlutterFlowTheme.initialize();
  final appState = FFAppState(); // Initialize FFAppState
  await appState.initializePersistedState();
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

  @override
  void initState() {
    super.initState();
    userStream = habitTrackerFirebaseUserStream();
    userStream.listen((user) {
      if (user.uid != null && user.uid!.isNotEmpty) {
        finalizeHabitData(user.uid!);
      }
    });
    jwtTokenStream.listen((_) {});
  }

  @override
  void dispose() {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Splash(),
      routes: <String, WidgetBuilder>{
        home: (BuildContext context) => const Home(),
        login: (BuildContext context) => const SignIn(),
      },
    );  }
}
