import 'dart:convert';

import 'package:convert/convert.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dart_merkle_lib/dart_merkle_lib.dart';
import 'package:dart_merkle_lib/src/fast_root.dart';
import 'package:dart_merkle_lib/src/proof.dart';
import 'package:file_picker/file_picker.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/blockchain_server.dart';

class BlockChain {
  BlockChain._();

  static List<_Block> blocks = [_Block.genesis()];

  static void createNewBlock(List<List<int>> shardByteData, PlatformFile file,
      FilePickerResult result, List<String> knownNodes) async {
    String fileName = getFileName(file, result);
    String fileExtension = file.extension;
    int fileSizeBytes = file.size;
    double eventCost = 2;
    Map<String, String> shardHosts = {};

    for (int i = 0; i < knownNodes.length; i++) {
      shardHosts["$i"] = knownNodes[i];
    }

    int timeCreated = DateTime.now().millisecondsSinceEpoch;
    String fileHost =
        "${await NetworkInfo().getWifiIP()}:${BlockchainServer.port}";
    String merkleHashSalt = _Block.getRandString();
    String prevBlockHash = blocks[blocks.length - 1].merkleTreeRootHash;

    _Block newBlock = _Block(
        fileName,
        fileExtension,
        fileSizeBytes,
        knownNodes.length,
        eventCost,
        shardHosts,
        timeCreated,
        fileHost,
        merkleHashSalt,
        prevBlockHash,
        shardByteData);

    blocks.add(newBlock);
  }

  static String getFileName(PlatformFile file, FilePickerResult result) {
    String fileExtension = file.extension;

    return file.name
        .substring(0, (file.name.length - 1) - fileExtension.length);
  }

  static Map<String, dynamic> toJson() {
    Map<String, dynamic> blocksJson = {};
    for (var block in blocks) {
      blocksJson[block.toJson()["fileName"]] = block.toJson();
    }

    return {
      "blocks": blocksJson,
    };
  }
}

class _Block {
  String fileName;
  String fileExtension;
  int fileSizeBytes;
  int shardsCreated;
  //BlockEvent event;
  double eventCost;
  Map<String, String> shardHosts;
  int timeCreated;
  String fileHost;
  String salt;
  String prevBlockHash;
  String merkleTreeRootHash;

  List<List<int>> _shardByteData;

  static const int saltLength = 10;

  void init() {
    merkleTreeRootHash = createBlockHash(_shardByteData, salt, prevBlockHash);
  }

  _Block(
      this.fileName,
      this.fileExtension,
      this.fileSizeBytes,
      this.shardsCreated,
      this.eventCost,
      this.shardHosts,
      this.timeCreated,
      this.fileHost,
      this.salt,
      this.prevBlockHash,
      this._shardByteData) {
    init();
  }

  _Block.genesis() {
    fileName = "genesis";
    fileExtension = "";
    fileSizeBytes = 0;
    shardsCreated = 0;
    eventCost = 0;
    shardHosts = {};
    timeCreated = 0;
    fileHost = "";
    salt = getRandString();
    prevBlockHash = "";
    _shardByteData = [];

    init();
  }

  static Uint8List sha256(data) {
    return Uint8List.fromList(crypto.sha256.convert(data).bytes);
  }

  static String getRandString() {
    var random = Random.secure();
    var values = List<int>.generate(saltLength, (i) => random.nextInt(255));
    return base64UrlEncode(values);
  }

  static String createBlockHash(
      List<List<int>> shardByteData, String salt, String prevHash) {
    List<String> hashedData = [];

    if (shardByteData.isNotEmpty) {
      for (List<int> byteData in shardByteData) {
        var digest = crypto.sha256.convert(GZipCodec().decode(byteData));
        hashedData.add(digest.toString());
      }

      List<Uint8List> hashedByteData =
          hashedData.map((e) => Uint8List.fromList(hex.decode(e))).toList();
      Uint8List root = fastRoot(hashedByteData, sha256);
      String merkleRoot = hex.encode(root);
      String merkleRootAndKey = crypto.sha256
          .convert((merkleRoot + salt + prevHash).runes.toList())
          .toString();

      return merkleRootAndKey;
    }

    return crypto.sha256.convert((salt).runes.toList()).toString();
  }

  Map<String, dynamic> toJson() {
    return {
      "fileName": fileName,
      "fileExtension": fileExtension,
      "fileSizeBytes": fileSizeBytes,
      "shardsCreated": shardsCreated,
      "eventCost": eventCost,
      "shardHosts": shardHosts,
      "timeCreated": timeCreated,
      "fileHost": fileHost,
      "salt": salt,
      "merkleRootHash": merkleTreeRootHash,
      "prevBlockHash": prevBlockHash,
    };
  }
}
