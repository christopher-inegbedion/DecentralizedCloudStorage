import 'package:convert/convert.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dart_merkle_lib/dart_merkle_lib.dart';
import 'package:dart_merkle_lib/src/fast_root.dart';
import 'package:dart_merkle_lib/src/proof.dart';

class BlockChain {
  List<Block> blocks = [];
}

class Block {
  String fileName;
  int fileSizeBytes;
  int shardsCreated;
  //BlockEvent event;
  double eventCost;
  Map<String, String> shardHosts;
  int timeCreated;
  String fileHost;
  String merkleTreeRootHash;
  String prevBlockHash;

  Block();

  // Block(
  //     this.fileName,
  //     this.fileSizeBytes,
  //     this.shardsCreated,
  //     this.eventCost,
  //     this.shardHosts,
  //     this.timeCreated,
  //     this.fileHost,
  //     this.merkleTreeRootHash,
  //     this.prevBlockHash);
  Uint8List sha256(data) {
    return Uint8List.fromList(crypto.sha256.convert(data).bytes);
  }

  List<Uint8List> createBlockHash(List<List<int>> shardByteData) {
    int key = Random().nextInt(1000000000);
    List<String> hashedData = [];

    for (List<int> byteData in shardByteData) {
      var digest = crypto.sha256.convert(GZipCodec().decode(byteData));
      hashedData.add(digest.toString());
    }

    List<Uint8List> hashedByteData =
        hashedData.map((e) => Uint8List.fromList(hex.decode(e))).toList();
    Uint8List root = fastRoot(hashedByteData, sha256);
    String merkleRoot = hex.encode(root);
    String merkleRootAndKey = crypto.sha256
        .convert((merkleRoot + key.toString()).runes.toList())
        .toString();
    print(merkleRootAndKey);

    return hashedByteData;
  }
}
