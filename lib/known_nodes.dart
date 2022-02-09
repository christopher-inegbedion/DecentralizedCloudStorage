import 'package:testwindowsapp/node.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'blockchain_server.dart';

class KnownNodes {
  static List<Node> knownNodes = [];

  static Future addNode(String ip, int port, {bool fromServer=false}) async {
    String address = "$ip:$port";
    Node newNode = Node(ip, port);

    try {
      String myIP = await NetworkInfo().getWifiIP();
      int myPort = await BlockchainServer.getPort();

      if (!fromServer) {
        // await Dio().post("http://$address/add_node",
        //   data: FormData.fromMap({
        //     "addingNodeIp": myIP,
        //     "addingNodePort": myPort,
        //     "addr": address,
        //   }));
      }
      
      knownNodes.add(newNode);
    } catch (e, stacktrace) {
      debugPrint(e.toString());
      debugPrint(stacktrace.toString());
    }
  }
}
