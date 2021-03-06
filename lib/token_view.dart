import 'dart:async';

import 'package:flutter/material.dart';
import 'package:testwindowsapp/token.dart';

import 'user_session.dart';

class AvailableTokensView extends StatefulWidget {
  Token token;

  AvailableTokensView(this.token);

  @override
  AvailableTokensViewState createState() => AvailableTokensViewState(token);
}

class AvailableTokensViewState extends State<AvailableTokensView> {
  Token token;

  AvailableTokensViewState(this.token);

  void _updateTokens() async {
    int minsElapsed = 0;
    if (mounted) {
      Timer.periodic(const Duration(seconds: 1), (timer) {
        minsElapsed += 10;
        setState(() {
          token.incrementTokens(minsElapsed);
        });
      });
    }
  }

  @override
  void initState() {
    super.initState();
    UserSession().getSavedTokenAmount().then((amount) {
      setState(() {
        token.availableTokens = amount;
      });
    }).whenComplete(() {
      _updateTokens();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          token.clearTokens();
        });
      },
      child: Container(
          decoration: BoxDecoration(
              color: Colors.green[400], borderRadius: BorderRadius.circular(3)),
          padding: const EdgeInsets.only(left: 7, right: 7, top: 3, bottom: 4),
          child: SelectableText(
            "${token.availableTokens} tokens",
            style: TextStyle(fontSize: 12, color: Colors.green[900]),
          )),
    );
  }
}
