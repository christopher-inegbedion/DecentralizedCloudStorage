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

  Future<double> incrementTokens(int minsElapsed) async {
    double val = (double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3)) -
            availableTokens) +
        availableTokens;

    if (val >= await UserSession().getSavedTokenAmount()) {
      availableTokens =
          (double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3)) -
                  availableTokens) +
              availableTokens;
    } else {
      availableTokens = await UserSession().getSavedTokenAmount();
    }

    UserSession().saveTokens(availableTokens);

    return val;
  }

  Future deductTokens() async {
    DateTime lastLoginTime = DateTime.fromMillisecondsSinceEpoch(
        await UserSession().getLastLoginTime());
    DateTime currentLoginTime = DateTime.now();

    Duration diff = currentLoginTime.difference(lastLoginTime);
    int minsElapsed = diff.inMinutes;

    availableTokens = availableTokens -
        double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3));
    if (availableTokens < 0) {
      availableTokens = 0;
    }
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
