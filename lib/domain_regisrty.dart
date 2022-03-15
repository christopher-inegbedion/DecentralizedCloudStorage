import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:http/http.dart' as http;
import 'package:testwindowsapp/message_handler.dart';

class DomainRegistry {
  String ip;
  int port;
  static String _id;

  DomainRegistry(this.ip, this.port);

  static String generateNodeID(String addr) {
    List<int> bytes = utf8.encode(addr);
    Digest digest = sha256.convert(bytes);

    return digest.toString();
  }

  void generateID(BuildContext context) {
    List<int> bytes = utf8.encode("$ip:$port");
    Digest digest = sha256.convert(bytes);

    _id = digest.toString();
    saveID(_id, ip, port, context);
  }

  void saveID(String id, String ip, int port, BuildContext context) async {
    try {
await http.put(
        Uri.parse(
            "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/$_id/.json"),
        body: jsonEncode({
          "ip": await BlockchainServer.getIP(),
          "port": (await BlockchainServer.getPort()).toString()
        }));
    } catch (e){
      MessageHandler.showFailureMessage(context, "An error occured while saving your ID. Try again later");
    }
    
  }

  String getID() {
    return _id;
  }

  static Future<String> getNodeIP(String id) async {
    String ip;
    Response r = await http.put(
        Uri.parse(
            "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/$id/.json"),
        body: jsonEncode({
          "ip": await BlockchainServer.getIP(),
          "port": (await BlockchainServer.getPort()).toString()
        }));

    if (r.body != null) {
      ip = jsonDecode(r.body)["ip"];
    }

    return ip;
  }

  static Future<int> getNodePort(String id) async {
    int port;
    Response r = await http.get(Uri.parse(
        "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/$id/.json"));

    if (r.body != null) {
      port = int.parse(jsonDecode(r.body)["port"]);
    }

    return port;
  }
}
