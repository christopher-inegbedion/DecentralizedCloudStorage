import 'package:testwindowsapp/server.dart';

class Node {
  String ip;
  int port;
  String addr;

  Node(this.ip, this.port) {
    addr = "$ip:$port";
  }

  Future<bool> isLive() async {
    try {
      return await BlockchainServer.isNodeLive(addr);
    } catch (_) {
      return false;
    }
  }
}
