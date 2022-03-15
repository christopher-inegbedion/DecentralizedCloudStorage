import 'package:testwindowsapp/node.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'blockchain_server.dart';

class KnownNodes {
  static const int maximumKnownNodesAllowed = 10;
  static Set<Node> knownNodes = {};

  static Future addNode(String ip, int port, {bool fromServer = false}) async {
    String address = "$ip:$port";
    Node newNode = Node(ip, port);

    if (knownNodes.length == maximumKnownNodesAllowed) {
      throw Exception("Maximum known nodes capacity reached");
    }
      knownNodes.add(newNode);

    try {
      String myIP = await NetworkInfo().getWifiIP();
      int myPort = await BlockchainServer.getPort();

      if (!fromServer) {
        await Dio().post("http://$address/add_node",
            data: FormData.fromMap({
              "addingNodeIp": myIP,
              "addingNodePort": myPort,
              "addr": address,
            }));
      }

      for (Node node in knownNodes) {
        if (node.getNodeAddress() == "$ip:$port") {
          return;
        }
      }
      // print(knownNodes);
    } catch (e, stacktrace) {
      debugPrint(e.toString());
      debugPrint(stacktrace.toString());
    }


  }
}
