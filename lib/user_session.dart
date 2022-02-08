import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_size/window_size.dart';

import 'constants.dart';

class UserSession {

  static Future<bool> isUserNew() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(Constants.newUser) == null;
  }

  static Future saveNewUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool(Constants.newUser, true);
  }

  static void lockScreenSize() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      setWindowMinSize(const Size(800, 700));
      setWindowMaxSize(const Size(800, 700));
    }
  }

  void logLoginTime() async {
    DateTime time = DateTime.now();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt(Constants.lastLoginTimeKey, time.millisecondsSinceEpoch);
    Timer.periodic(const Duration(minutes: 1), (timer) {
      prefs.setInt(Constants.lastLoginTimeKey, time.millisecondsSinceEpoch);
    });
  }

  Future<int> getLastLoginTime() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(Constants.lastLoginTimeKey);
  }

  void saveTokens(double amount) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setDouble(Constants.tokenAmount, amount);
  }

  Future<double> getSavedTokenAmount(double amount) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(Constants.tokenAmount);
  }
}
