import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Helper/Helpers/sharedPreference.dart';
import 'package:habit_tracker/main.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<StatefulWidget> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  final SharedPref sharedPref = SharedPref();

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    final value = await sharedPref.read(SharedPreference.name.sUserDetails);

    if (!mounted) return;

    if (value.isNotEmpty) {
      users = LoginResponse.fromJson(value);
      // Wait 3 seconds then navigate to home
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          Navigator.pushReplacementNamed(context, home);
        }
      });
    } else {
      // No user data, navigate to login immediately
      Navigator.pushReplacementNamed(context, login);
    }
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
      child: const Text(
        "Habit Tracker",
        style: TextStyle(
          decoration: TextDecoration.none,
          color: Colors.grey,
          fontSize: 30,
          fontWeight: FontWeight.bold,
          decorationColor: Colors.transparent,
        ),
      ),
    );
  }
}
