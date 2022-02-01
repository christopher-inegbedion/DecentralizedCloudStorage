import 'dart:convert';

import 'package:crypto/crypto.dart';

class DomainRegistry {
  String id;

  DomainRegistry();

  String generateID(String ID, int port) {
    List<int> bytes = utf8.encode(ID + port.toString());
    Digest digest = sha256.convert(bytes);

    return digest.toString();
  }
}
