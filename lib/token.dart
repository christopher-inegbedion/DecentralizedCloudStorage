import 'dart:math';

import 'package:testwindowsapp/user_session.dart';

class Token {
  static Token _instance;
  double availableTokens;
  int lastLoginTime;

  final int m = 100;
  final int n = 0;
  final int timeToConsumeAvailStorage = 60 * 24;
  final int timeToConsumeShardDataStoredStorage = 60 * 24 * 7;

  Token._() {
    availableTokens = 0;
  }

  static Token getInstance() {
    _instance ??= Token._();

    return _instance;
  }

  void clearTokens() {
    availableTokens = 0;
    UserSession().saveTokens(availableTokens);
  }

  ///This function sets the tokens a user had according to
  ///the amount of minutes they have spent on the app.
  Future<double> incrementTokens(int minsElapsed) async {
    //Calculate the amount of tokens the user is due given the number of minutes elapsed
    double val = (double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3))) +
        availableTokens;

    //Subtract 'val' from the vurrent tokens available to the user
    availableTokens =
        val;

    //Save the user's tokens
    // UserSession().saveTokens(availableTokens);

    return val;
  }
  
  ///This function deducts an amount of tokens equivalent to the
  ///amount of time spent offline from the amount of tokens the user
  ///has available.
  Future deductTokens() async {
    //Retrieve both the last login time and the current login time
    DateTime lastLoginTime = DateTime.fromMillisecondsSinceEpoch(
        await UserSession().getLastLoginTime());
    DateTime currentLoginTime = DateTime.now();

    //Calculate how many minutes the user was offline for
    Duration diff = currentLoginTime.difference(lastLoginTime);
    int minsElapsed = diff.inMinutes;

    //Deduct the user's tokens
    availableTokens = availableTokens -
        double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3));
    if (availableTokens < 0) {
      availableTokens = 0;
    }

    //Save the user's tokens
    UserSession().saveTokens(availableTokens);
  }

  static double calculateFileCost(int bytes) {
    return (9.31 * pow(10, -10)) * bytes;
  }

  double _tokenFormula(int minsElapsed) {
    double a = 50 - (timeToConsumeAvailStorage / 2);
    double b = 50 - (timeToConsumeShardDataStoredStorage / 2);
    double j = -((log((m / 1) - 1)) / a);
    double k = -((log((n / 1) - 1)) / b);

    double token = (m /
        (1 + pow(e, (-j * (minsElapsed - timeToConsumeAvailStorage / 2)))));
    return token;
  }
}
