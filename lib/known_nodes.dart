import 'package:testwindowsapp/constants.dart';
import 'package:testwindowsapp/node.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/utils.dart';

import 'server.dart';

class KnownNodes {
  static Set<Node> knownNodes = {};

  //Add a new node to the list of known nodes
  static Future addNode(String ip, int port) async {
    Node newNode = Node(ip, port);

    if (knownNodes.length == Constants.maxNumOfKnownNodes) {
      throw Exception("Maximum known nodes capacity reached");
    }

    try {      //This prevents the same node from being added multiple times
      for (Node node in knownNodes) {
        if (getNodeAddress(node.ip, node.port) == "$ip:$port") {
          return;
        }
      }

      knownNodes.add(newNode);
    } catch (e, stacktrace) {
      debugPrint(e.toString());
      debugPrint(stacktrace.toString());
    }


  }
}
