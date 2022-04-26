import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:dio/dio.dart' as dio;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:testwindowsapp/blockchain/blockchain.dart';
import 'package:testwindowsapp/known_nodes.dart';
import 'package:testwindowsapp/message_handler.dart';
import "package:upnp/router.dart" as router;
import 'package:upnp/upnp.dart' as upnp;
import 'main.dart';
import 'node.dart';
import 'utils.dart';

class BlockchainServer {
  MyHomePageState state;
  BuildContext context;
  NetworkInfo _networkInfo;

  BlockchainServer(this.context, this.state) {
    _networkInfo = NetworkInfo();
    //  _port = Random().nextInt(60000);
  }

  static Future<bool> isNodeLive(String addr) async {
    try {
      final result = dio.Dio().get(addr + "/live_test");
      return (await result).data != null;
    } catch (_) {
      return false;
    }
  }

  static Future<int> getPort() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      int port = prefs.getInt("port");

      if (port == null) {
        port = Random().nextInt(60000);
        prefs.setInt("port", port);
      }

      return port ?? 1234;
    } catch (e) {
      return Random().nextInt(60000);
    }
  }

  static Future<String> getIP() async {
    String ip;
    try {
      ip = await NetworkInfo().getWifiIP();
    } catch (e) {
      ip = "localhost";
    }
    return ip;
  }

  static void startServer(BuildContext context, MyHomePageState state) async {
    var app = shelf_router.Router();

    if (await getIP() == null || await getPort() == null) {
      state.showServerStartErrorDialog(await getIP(), await getPort());
      throw Exception("An error occured starting the server");
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();

    String savePath = prefs.getString("storage_location");
    String shardDataDirPath = "$savePath/shard_data";

    app.get("/", (Request request) async {
      return Response.ok('hello-world');
    });

    app.get("/live_test", (Request request) async {
      return Response.ok("live");
    });

    ///Called by an external node to add this node as a known node. The external node is also
    ///added to the this node's known nodes list.
    app.post("/add_node", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String ip = parameters["addingNodeIp"];
      int port = int.parse(parameters["addingNodePort"]);

      KnownNodes.addNode(ip, port);
      return Response.ok("done");
    });

    ///Called by an external node to send a shard to this device.
    app.post('/send_shard', (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String fileName = parameters["fileName"];
      List<int> byteArray = List.from(json.decode(parameters["file"]));

      int depth = int.parse(parameters["depth"]) - 1;

      File file =
          await File("$shardDataDirPath/$fileName").create(recursive: true);
      file.writeAsBytes(byteArray).then((File f) async {
        if (depth != 0) {
          state.getKnownNodes().forEach((node) async {
            Map<String, dynamic> formMapData = {
              "depth": depth,
              "fileName": fileName,
              "file": dio.MultipartFile.fromBytes(
                  utf8.encode((await f.readAsBytes()).toString()))
            };

            dio.FormData formData = dio.FormData.fromMap(formMapData);
            String nodeAddr = getNodeAddress(node.ip, node.port);
            await dio.Dio().post(
              "http://$nodeAddr/send_shard",
              data: formData,
            );
          });
        }
      });

      (await File("$shardDataDirPath/$fileName").create(recursive: true))
          .writeAsBytes(byteArray);
      return Response.ok('hello-world');
    });

    ///Called by an external node to send a shard from this device to it.
    app.post("/send_file", (Request request) async {
      final Map<String, dynamic> parameters =
          jsonDecode(await request.readAsString());

      String fileName = parameters["fileName"];
      File requestingFile = File("$shardDataDirPath/$fileName");

      List<int> fileBytes = await requestingFile.readAsBytes();

      return Response.ok(fileBytes.toString());
    });

    ///Called by an external node to send a new block from its device to this.
    app.post("/send_block", (Request request) async {
      final parameters = jsonDecode(await request.readAsString());

      Map<String, dynamic> block = jsonDecode(parameters["block"]);
      Block tempBlock;

      //Convert the block to an upload/delete block
      if (block["event"] == Block.uploadEvent) {
        tempBlock = Block.fromJsonUB(block);
      } else if (block["event"] == Block.deleteEvent) {
        tempBlock = Block.fromJsonDB(block);
      }

      var blocks = BlockChain.blocks;

      //This prevents a block from being sent in an infinite loop between
      //two nodes who have each other as known nodes. If the block being
      //sent is already in the blockchain then the loop fails and the
      //function quits
      if (blocks
          .where((block) => block.timeCreated == tempBlock.timeCreated)
          .isEmpty) {

        //Send the block to this node's known nodes
        state.getKnownNodes().forEach((node) {
          String nodeAddr = getNodeAddress(node.ip, node.port);

          BlockChain.sendBlock(nodeAddr, tempBlock);
        });

        //The temporary block pool was created in situations where multiple blocks might be 
        //received at the same time
        BlockChain.addBlockToTempPool(tempBlock);

        //Even if a blockhain is update being updated a new temp. block has been added to the
        //temp. block pool, the new temp. block will still get added to the blockchain as, the
        //addBlockToBlockchain() function always checks if a there is a new block in the 
        //temp. block pool before ending.
        if (!BlockChain.updatingBlockchain) {
          BlockChain.addBlockToBlockchain();
        }
        
        state.refreshBlockchainAndState();
      }

      return Response.ok("done");
    });

    ///Called by an external node to send the compiled known nodes to the request originator node,
    ///or send the request to known nodes until the specified depth is 0
    app.post("/send_known_nodes", (Request request) async {
      final parameters = jsonDecode(await request.readAsString());

      int depth = int.parse(parameters["depth"]) - 1;
      Set<String> nodes = {...parameters["nodes"]};
      String sender = parameters["sender"];
      String origin = parameters["origin"];

      String myIP = await NetworkInfo().getWifiIP();
      int port = await getPort();

      List<Node> nodesSendingTo = [];
      for (var node in KnownNodes.knownNodes) {
        String nodeAddr = getNodeAddress(node.ip, node.port);
        if (nodeAddr != sender) {
          nodes.add(nodeAddr);
          nodesSendingTo.add(node);
        }
      }

      if (nodesSendingTo.isNotEmpty) {
        if (depth != 0) {
          for (var node in nodesSendingTo) {
            String nodeAddr = getNodeAddress(node.ip, node.port);

            var r = await dio.Dio().post(
              "http://$nodeAddr/send_known_nodes",
              data: {
                "depth": depth.toString(),
                "nodes": nodes.toList(),
                "origin": origin,
                "sender": "$myIP:$port"
              },
            );

            nodes.addAll(Set<String>.from(jsonDecode(r.data)));
          }
        }
      }

      return Response.ok(jsonEncode(nodes.toList()));
    });

    await io.serve(app, await getIP(), await getPort(), shared: true);
    MessageHandler.showSuccessMessage(context, "Server started");
    // mapPort();
  }

  void mapPort() async {
    await for (var router in router.Router.findAll()) {
      upnp.Service service;

      try {
        service = await router.device
            .getService("urn:upnp-org:serviceId:WANIPConn1")
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        MessageHandler.showFailureMessage(context,
            "Your router does not support port forwarding. Server offline");
      }

      if (service != null) {
        service.invokeAction("AddPortMapping", {
          "NewRemoteHost": "",
          "NewExternalPort": await getPort(),
          "NewProtocol": 'TCP',
          "NewInternalPort": await getPort(),
          "NewInternalClient": await _networkInfo.getWifiIP(),
          "NewEnabled": '1',
          "NewPortMappingDescription": 'Shr application server',
          "NewLeaseDuration": '0'
        }).then((value) {
          MessageHandler.showSuccessMessage(
              context, "Server port forwarded successfully");
        }).onError((error, stackTrace) {
          MessageHandler.showFailureMessage(
              context, "An error occured during port forwarding");
        });
      } else {
        MessageHandler.showFailureMessage(
            context, "Your router does not support port forwarding");
      }
    }
  }

  void unmapPort(int port) async {
    await for (var router in router.Router.findAll()) {
      upnp.Service service;

      try {
        service = await router.device
            .getService("urn:upnp-org:serviceId:WANIPConn1")
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        MessageHandler.showFailureMessage(
            context, "Your router does not support port forwarding");
      }

      if (service != null) {
        service.invokeAction("DeletePortMapping", {
          "NewRemoteHost": "",
          "NewExternalPort": port,
          "NewProtocol": 'TCP',
        }).then((value) {
          MessageHandler.showSuccessMessage(
              context, "Server port removed successfully");
        }).onError((error, stackTrace) {
          MessageHandler.showFailureMessage(
              context, "An error occured while removing external port");
        });
      } else {
        MessageHandler.showFailureMessage(
            context, "Your router does not support port forwarding");
      }
    }
  }

  static Future<Map<String, Set>> getBackupNodes(
      List<Node> nodesReceiving, int depth) async {
    String myAddress = await getMyAddress();
    Map<String, Set> backupNodes = {};

    for (int i = 0; i < nodesReceiving.length; i++) {
      Node node = KnownNodes.knownNodes.toList()[i];
      String nodeAddr = getNodeAddress(node.ip, node.port);

      var r = await dio.Dio().post(
        "http://${getNodeAddress(nodesReceiving[0].ip, nodesReceiving[0].port)}/send_known_nodes",
        data: {
          "depth": depth.toString(),
          "nodes": [],
          "origin": myAddress,
          "sender": myAddress
        },
      );

      backupNodes[i.toString()] = {...jsonDecode(r.data)};
      backupNodes[i.toString()].add(nodeAddr);
    }

    return backupNodes;
  }

  static void sendBlocksToKnownNodes(Block tempBlock) async {
    String myIP = await NetworkInfo().getWifiIP();

    Set<Node> nodesReceivingShard = {};
    int myPort = await BlockchainServer.getPort();

    Node self = Node(myIP, myPort);

    nodesReceivingShard.add(self);

    for (int i = 0; i < KnownNodes.knownNodes.length; i++) {
      Node node = KnownNodes.knownNodes.toList()[i];
      String nodeAddr = getNodeAddress(node.ip, node.port);

      if (nodeAddr != await getMyAddress()) {
        nodesReceivingShard.add(KnownNodes.knownNodes.toList()[i]);
      }
    }

    for (Node node in nodesReceivingShard) {
      String nodeAddr = getNodeAddress(node.ip, node.port);

      BlockChain.sendBlock(nodeAddr, tempBlock);
    }
  }
}
