class Node {
  String ip;
  int port;
  String address;

  Node(this.ip, this.port) {
    address = "$ip:$port";
  }
}
