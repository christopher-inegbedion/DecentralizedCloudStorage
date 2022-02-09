import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/blockchain_server.dart';

class Node {
  String ip;
  int port;
  String address;

  Node(this.ip, this.port) {
    address = "$ip:$port";
  }

  static Future<String> getMyAddress() async {
    String ip = await NetworkInfo().getWifiIP();
    int port = await BlockchainServer.getPort();

    return "$ip:$port";
  }
}
