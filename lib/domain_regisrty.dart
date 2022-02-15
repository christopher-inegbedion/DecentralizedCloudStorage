import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/blockchain_server.dart';

class DomainRegistry {
  static String _id;

  DomainRegistry._();

  static void generateID() async {
    List<int> bytes = utf8.encode(
        "${await NetworkInfo().getWifiIP()}${await BlockchainServer.getPort()}");
    Digest digest = sha256.convert(bytes);

    _id = digest.toString();
  }

  static String getID() {
    return _id;
  }
}
