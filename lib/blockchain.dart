import 'dart:convert';

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testwindowsapp/domain_regisrty.dart';
import 'package:testwindowsapp/token.dart';
import 'package:http/http.dart' as http;

class BlockChain {
  BlockChain._();

  static List<Block> blocks = [Block.genesis()];
  static List<Block> _temporaryBlockPool = [];
  static bool updatingBlockchain = false;

  static Future<Block> createNewBlock(
      List<List<int>> shardByteHash,
      PlatformFile file,
      FilePickerResult result,
      List<String> knownNodes) async {
    String fileName = getFileName(file, result);
    String fileExtension = file.extension;
    int fileSizeBytes = file.size;
    double eventCost = Token.calculateFileCost(fileSizeBytes);
    Map<String, String> shardHosts = {};
    List<String> fileHashes = [];

    for (int i = 0; i < knownNodes.length; i++) {
      shardHosts["$i"] = knownNodes[i];
    }

    int timeCreated = DateTime.now().millisecondsSinceEpoch;
    String fileHost = DomainRegistry.id;
    String merkleHashSalt = Block.getRandString();
    String shardByteHashString = "";

    for (List<int> byteData in shardByteHash) {
      var digest = crypto.sha256.convert(GZipCodec().decode(byteData));

      shardByteHashString += digest.toString();
      fileHashes.add(shardByteHashString);
    }

    Block newBlock = Block(
        fileName,
        fileExtension,
        fileSizeBytes,
        knownNodes.length,
        eventCost,
        shardHosts,
        timeCreated,
        fileHost,
        fileHashes,
        merkleHashSalt,
        "",
        shardByteHashString);

    return newBlock;
  }

  static void sendBlockchain(String receipientAddr, Block newBlock) async {
    await http.post(Uri.parse("http://$receipientAddr/send_block"),
        headers: <String, String>{
          'ContentType': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(newBlock.toJson()));
  }

  static void addBlockToTempPool(Block tempBlock) {
    _temporaryBlockPool.add(tempBlock);
  }

  static void addBlockToBlockchain() async {
    List tmpCopy = _temporaryBlockPool;
    tmpCopy.sort((a, b) {
      int aTime = a.timeCreated;
      int bTime = b.timeCreated;

      return aTime.compareTo(bTime);
    });
    updatingBlockchain = true;
    for (Block block in _temporaryBlockPool) {
      block.prevBlockHash = blocks[blocks.length - 1].merkleTreeRootHash;
      block.merkleTreeRootHash = block.createBlockHash();
      blocks.add(block);
      _saveBlockchain();
    }

    _temporaryBlockPool.removeWhere((element) {
      return tmpCopy.contains(element);
    });

    if (_temporaryBlockPool.isNotEmpty) {
      addBlockToBlockchain();
    } else {
      updatingBlockchain = false;
    }
  }

  static Future<Map<String, dynamic>> loadBlockchain() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      if (prefs.getString("blockchain_data") != null) {
        Map<String, dynamic> blockchainData = Map<String, dynamic>.from(
            jsonDecode(prefs.getString("blockchain_data")));

        List<Block> i = [];
        Map<String, dynamic> blockData = blockchainData["blocks"];
        for (int k = 0; k < blockData.length; k++) {
          Block j = Block.fromJson(blockData[blockData.keys.elementAt(k)]);
          i.add(j);
        }

        blocks = i;
        return blockchainData;
      }
    } catch (e, trace) {
      debugPrint(trace.toString());
    }

    return BlockChain.toJson();
  }

  static void clearBlockchain() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove("blockchain_data");
  }

  static void _saveBlockchain() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString("blockchain_data", jsonEncode(BlockChain.toJson()));
    } catch (e, trace) {
      debugPrintStack(stackTrace: trace);
    }
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

class Block {
  String fileName;
  String fileExtension;
  int fileSizeBytes;
  int shardsCreated;
  //BlockEvent event;
  double eventCost;
  Map<String, String> shardHosts;
  int timeCreated;
  String fileHost;
  List<String> fileHashes = [];
  String salt;
  String prevBlockHash;
  String merkleTreeRootHash;

  String _shardByteHash;

  static const int saltLength = 10;

  Block(
      this.fileName,
      this.fileExtension,
      this.fileSizeBytes,
      this.shardsCreated,
      this.eventCost,
      this.shardHosts,
      this.timeCreated,
      this.fileHost,
      this.fileHashes,
      this.salt,
      this.prevBlockHash,
      this._shardByteHash);

  Block.genesis() {
    fileName = "genesis";
    fileExtension = "-";
    fileSizeBytes = 0;
    shardsCreated = 0;
    eventCost = 0;
    shardHosts = {};
    timeCreated = 0;
    fileHost = "-";
    fileHashes = [];
    salt = "salt";
    prevBlockHash = "-";
    _shardByteHash = "";

    merkleTreeRootHash = createBlockHash();
  }

  Block.fromJson(Map<String, dynamic> blockData) {
    fileName = blockData["fileName"];
    fileExtension = blockData["fileExtension"];
    fileSizeBytes = blockData["fileSizeBytes"];
    shardsCreated = blockData["shardsCreated"];
    eventCost = blockData["eventCost"];
    shardHosts = Map<String, String>.from(blockData["shardHosts"]);
    timeCreated = blockData["timeCreated"];
    fileHost = blockData["fileHost"];
    fileHashes = List<String>.from(blockData["fileHashes"]);
    salt = blockData["salt"];
    prevBlockHash = blockData["prevBlockHash"];
    _shardByteHash = blockData["shardByteHash"];
    merkleTreeRootHash = blockData["merkleRootHash"];
  }

  static Uint8List sha256(data) {
    return Uint8List.fromList(crypto.sha256.convert(data).bytes);
  }

  static String getRandString() {
    var random = Random.secure();
    var values = List<int>.generate(saltLength, (i) => random.nextInt(255));
    return base64UrlEncode(values);
  }

  String createBlockHash() {
    String blockHash = crypto.sha256
        .convert((_shardByteHash + salt + prevBlockHash).runes.toList())
        .toString();

    return blockHash;
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
      "fileHashes": fileHashes,
      "salt": salt,
      "merkleRootHash": merkleTreeRootHash,
      "prevBlockHash": prevBlockHash,
      "shardByteHash": _shardByteHash
    };
  }
}
