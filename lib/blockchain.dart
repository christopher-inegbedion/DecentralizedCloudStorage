import 'dart:convert';

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:testwindowsapp/domain_regisrty.dart';
import 'package:testwindowsapp/node.dart';
import 'package:testwindowsapp/token.dart';
import 'package:http/http.dart' as http;

import 'utils.dart';

class BlockChain {
  BlockChain._();

  static List<Block> blocks = [Block.genesis()];
  static List<Block> _temporaryBlockPool = [];
  static bool updatingBlockchain = false;

  static Future<Block> createNewBlock(
      List<List<int>> shardByteHash,
      PlatformFile file,
      FilePickerResult result,
      Map<String, List> shardHosts) async {
    DomainRegistry _domainRegistry = DomainRegistry(
        await BlockchainServer.getIP(), await BlockchainServer.getPort());
    String fileName = getFileName(file, result);
    String fileExtension = file.extension;
    int fileSizeBytes = file.size;
    double eventCost = Token.calculateFileCost(fileSizeBytes);
    List<String> fileHashes = [];

    int timeCreated = DateTime.now().millisecondsSinceEpoch;
    String fileHost = _domainRegistry.getID();
    String merkleHashSalt = Block.getRandString();
    String shardByteHashString = "";

    for (List<int> byteData in shardByteHash) {
      String hashByteData = createFileHash(byteData);

      shardByteHashString += hashByteData;
      fileHashes.add(hashByteData);
    }

    //convert shard hosts ip to port
    Map<String, List> hosts = _convertShardHostsIpToId(shardHosts);

    Block newBlock = Block.upload(
        fileName,
        fileExtension,
        fileSizeBytes,
        shardByteHashString,
        shardHosts.length,
        Block.uploadEvent,
        eventCost,
        hosts,
        timeCreated,
        fileHost,
        fileHashes,
        merkleHashSalt,
        "");

    return newBlock;
  }

  static Block createDeleteBlock(String fileName, String blockHash,
      String shardByteHash, String fileHost) {
    Block newDeleteBlock = Block.delete(
        fileName + "-deleted",
        blockHash,
        shardByteHash,
        DateTime.now().millisecondsSinceEpoch,
        Block.deleteEvent,
        fileHost,
        Block.getRandString(),
        "");

    return newDeleteBlock;
  }

  static void sendBlockchain(String receipientAddr, Block newBlock,
      {bool fromServer = false}) async {
    String ip = await BlockchainServer.getIP();
    int port = await BlockchainServer.getPort();
    await http.post(Uri.parse("http://$receipientAddr/send_block"),
        headers: <String, String>{
          'ContentType': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          "block": newBlock.event == Block.uploadEvent
              ? jsonEncode(newBlock.toUploadBlockJson())
              : jsonEncode(newBlock.toDeleteBlockJson()),
        }));
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
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (prefs.getString("blockchain_data") != null) {
      Map<String, dynamic> blockchainData = Map<String, dynamic>.from(
          jsonDecode(prefs.getString("blockchain_data")));

      List<Block> i = [];
      Map<String, dynamic> blockData = blockchainData["blocks"];
      for (int k = 0; k < blockData.length; k++) {
        Map<String, dynamic> block = blockData[blockData.keys.elementAt(k)];
        if (block["event"] == Block.uploadEvent) {
          Block j = Block.fromJsonUB(block);
          i.add(j);
        } else if (block["event"] == Block.deleteEvent) {
          Block j = Block.fromJsonDB(block);
          i.add(j);
        }
      }

      blocks = i;
      return blockchainData;
    } else {
      blocks = [Block.genesis()];
      return toJson();
    }
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
    for (Block block in blocks) {
      if (block.event == Block.uploadEvent) {
        blocksJson[block.toUploadBlockJson()["merkleRootHash"]] =
            block.toUploadBlockJson();
      } else if (block.event == Block.deleteEvent) {
        blocksJson[block.toDeleteBlockJson()["merkleRootHash"]] =
            block.toDeleteBlockJson();
      }
    }

    return {
      "blocks": blocksJson,
    };
  }

  static Map<String, List> _convertShardHostsIpToId(
      Map<String, List> shardHosts) {
    Map<String, List> newList = {};

    shardHosts.forEach((key, value) {
      newList[key] = [];

      value.forEach((addr) {
        newList[key].add(DomainRegistry.generateNodeID(addr));
      });
    });

    return newList;
  }
}

class Block {
  static const String deleteEvent = "delete";
  static const String uploadEvent = "upload";

  String blockFileHash;
  String fileName;
  String fileExtension;
  String shardByteHash;
  int fileSizeBytes;
  int shardsCreated;
  String event;
  double eventCost;
  Map<String, List> shardHosts;
  int timeCreated;
  String fileHost;
  List<String> fileHashes = [];
  String salt;
  String prevBlockHash;
  String merkleTreeRootHash;

  static const int saltLength = 10;

  Block._();

  Block.upload(
      this.fileName,
      this.fileExtension,
      this.fileSizeBytes,
      this.shardByteHash,
      this.shardsCreated,
      this.event,
      this.eventCost,
      this.shardHosts,
      this.timeCreated,
      this.fileHost,
      this.fileHashes,
      this.salt,
      this.prevBlockHash);

  Block.delete(
      this.fileName,
      this.blockFileHash,
      this.shardByteHash,
      this.timeCreated,
      this.event,
      this.fileHost,
      this.salt,
      this.prevBlockHash);

  Block.genesis() {
    fileName = "genesis";
    fileExtension = "-";
    fileSizeBytes = 0;
    shardByteHash = "";
    shardsCreated = 0;
    eventCost = 0;
    shardHosts = {};
    timeCreated = 0;
    fileHost = "-";
    fileHashes = [];
    salt = "salt";
    prevBlockHash = "-";

    merkleTreeRootHash = createBlockHash();
  }

  Block.fromJsonUB(Map<String, dynamic> blockData) {
    fileName = blockData["fileName"];
    fileExtension = blockData["fileExtension"];
    fileSizeBytes = blockData["fileSizeBytes"];
    shardByteHash = blockData["shardByteHash"];
    shardsCreated = blockData["shardsCreated"];
    event = blockData["event"];
    eventCost = blockData["eventCost"];
    shardHosts = Map<String, List>.from(blockData["shardHosts"]);
    timeCreated = blockData["timeCreated"];
    fileHost = blockData["fileHost"];
    fileHashes = List<String>.from(blockData["fileHashes"]);
    salt = blockData["salt"];
    prevBlockHash = blockData["prevBlockHash"];
    merkleTreeRootHash = blockData["merkleRootHash"];
  }

  Block.fromJsonDB(Map<String, dynamic> blockData) {
    fileName = blockData["fileName"];
    blockFileHash = blockData["blockHash"];
    shardByteHash = blockData["shardByteHash"];
    timeCreated = blockData["timeCreated"];
    event = blockData["event"];
    fileHost = blockData["fileHost"];
    salt = blockData["salt"];
    prevBlockHash = blockData["prevBlockHash"];
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
        .convert((shardByteHash + salt + prevBlockHash).runes.toList())
        .toString();

    return blockHash;
  }

  Map<String, dynamic> toUploadBlockJson() {
    return {
      "fileName": fileName,
      "fileExtension": fileExtension,
      "fileSizeBytes": fileSizeBytes,
      "shardByteHash": shardByteHash,
      "shardsCreated": shardsCreated,
      "event": event,
      "eventCost": eventCost,
      "shardHosts": shardHosts,
      "timeCreated": timeCreated,
      "fileHost": fileHost,
      "fileHashes": fileHashes,
      "salt": salt,
      "merkleRootHash": merkleTreeRootHash,
      "prevBlockHash": prevBlockHash,
    };
  }

  Map<String, dynamic> toDeleteBlockJson() {
    return {
      "fileName": fileName,
      "blockHash": blockFileHash,
      "shardByteHash": shardByteHash,
      "timeCreated": timeCreated,
      "event": event,
      "fileHost": fileHost,
      "salt": salt,
      "merkleRootHash": merkleTreeRootHash,
      "prevBlockHash": prevBlockHash
    };
  }
}
