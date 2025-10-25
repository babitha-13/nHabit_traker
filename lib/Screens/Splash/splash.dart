import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/sharedPreference.dart';
import 'package:habit_tracker/main.dart';
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<StatefulWidget> createState() => _SplashState();
}
class _SplashState extends State<Splash> {
  final SharedPref sharedPref = SharedPref();
  String appVersion = "";
  @override
  void initState() {
    super.initState();
    sharedPref.read(SharedPreference.name.sUserDetails).then((value1) {
      if (mounted) {
        if (value1 != "") {
          users = LoginResponse.fromJson(value1);
          startTime();
        } else {
          Navigator.pushReplacementNamed(context, login);
        }
      }
    });
  }
  startTime() async {
    var duration = const Duration(seconds: 3);
    return Timer(duration, navigationPage);
  }
  Future<void> navigationPage() async {
    sharedPref.read(SharedPreference.name.sUserDetails).then((value1) {
      if (mounted) {
        if (value1 != "") {
          users = LoginResponse.fromJson(value1);
          Navigator.pushReplacementNamed(context, home);
        } else {
          Navigator.pushReplacementNamed(context, login);
        }
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            "Habit Tracker",
            style: TextStyle(
              decoration: TextDecoration.none,
              color: Colors.grey,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              decorationColor: Colors.transparent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            " $appVersion",
            style: const TextStyle(
              color: Colors.white,
              decoration: TextDecoration.none,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              decorationColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}
