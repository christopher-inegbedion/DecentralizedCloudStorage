import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/node.dart';
import 'package:testwindowsapp/server.dart';
import 'package:http/http.dart' as http;
import 'package:testwindowsapp/message_handler.dart';

class DomainRegistry {
  String ip;
  int port;
  static String _id;

  DomainRegistry(this.ip, this.port);

  ///This function generates a node ID given its address.
  ///
  ///In the form "ip:port" (e.g. "127.0.0.1:8000")
  static String generateNodeID(String addr) {
    List<int> bytes = utf8.encode(addr);
    Digest digest = sha256.convert(bytes);

    return digest.toString();
  }

  ///This function saves a node's it in the Domain Registry
  void generateAndSaveID(BuildContext context) {
    _id = generateNodeID("$ip:$port");
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
    } catch (e) {
      MessageHandler.showFailureMessage(
          context, "An error occured while saving your ID. Try again later");
    }
  }

  String getID() {
    return _id;
  }

  static Future<String> getNodeIP(String id) async {
    try {
      String ip;
      Response r = await http.get(
        Uri.parse(
            "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/$id/.json"),
      );

      if (r.body != null) {
        ip = jsonDecode(r.body)["ip"];
      }

      return ip;
    } catch (e) {
      return null;
    }
  }

  static Future<int> getNodePort(String id) async {
    try {
      int port;
      Response r = await http.get(Uri.parse(
          "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/$id/.json"));

      if (r.body != null) {
        port = int.parse(jsonDecode(r.body)["port"]);
      }

      return port;
    } catch (e) {
      return null;
    }
  }

  static Future<Set<String>> getNodesFromDatabase(int amount) async {
    Map all_nodes;
    Random _random = Random();

    Set<String> nodeIds = {};
    Response r = await http.get(Uri.parse(
        "https://shr-7dd12-default-rtdb.europe-west1.firebasedatabase.app/.json"));

    if (r.body != null) {
      all_nodes = jsonDecode(r.body);

      for (int i = 0; i < amount; i++) {
        nodeIds.add(all_nodes.keys
            .toList()[_random.nextInt(all_nodes.keys.toList().length)]);
      }
    }

    return nodeIds;
  }
}
