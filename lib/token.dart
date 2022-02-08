import 'dart:math';

class Token {
  double availableTokens;
  int lastLoginTime;

  final int m = 100;
  final int n = 0;
  final int timeToConsumeAvailStorage = 60 * 24;
  final int timeToConsumeShardDataStoredStorage = 60 * 24 * 7;

  Token() {
    availableTokens = 0;
  }

  void incrementTokens(int minsElapsed) {
    availableTokens =
        (double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3)) -
                availableTokens) +
            availableTokens;
  }

  void deductTokens(int minsElapsed) {
    availableTokens =
        double.parse(_tokenFormula(minsElapsed).toStringAsFixed(3)) -
            availableTokens;
  }

  static double calculateFileCost(int bytes) {
    return (9.31 * pow(10, -10)) * bytes;
  }

  double _tokenFormula(int minsElapsed) {
    double a = 10 - (timeToConsumeAvailStorage / 2);
    double b = 10 - (timeToConsumeShardDataStoredStorage / 2);
    double j = -((log((m / 1) - 1)) / a);
    double k = -((log((n / 1) - 1)) / b);

    double token = (m /
        (1 + pow(e, (-j * (minsElapsed - timeToConsumeAvailStorage / 2)))));
    return token;
  }
}
