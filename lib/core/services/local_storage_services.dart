// ignore_for_file: file_names
import 'dart:async';
import 'dart:convert';
import 'package:habit_tracker/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';
class SharedPref {
  Future read(String key) async {
    final completer = Completer<dynamic>();
    SharedPreferences.getInstance().then((value) {
      if (value.containsKey(key)) {
        completer.complete(json.decode(value.getString(key) ?? ""));
      } else {
        completer.complete("");
      }
    });
    return completer.future;
  }
  save(String key,  value) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(key, json.encode(value));
  }
  Future remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove(key);
  }
  Future hasKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }
  Future saveValue(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(key, value);
  }
  Future readValue(String key) async {
    final completer = Completer<dynamic>();
    SharedPreferences.getInstance().then((value) {
      completer.complete(value.getString(key));
    });
    return completer.future;
  }
  Future<void> saveAuthData( user) async {
    await sharedPref.save(SharedPreference.name.sUserDetails, user);
  }
}
