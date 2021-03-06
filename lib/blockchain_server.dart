import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/known_nodes.dart';
import 'package:testwindowsapp/message_handler.dart';
import "package:upnp/router.dart" as router;
import 'package:upnp/upnp.dart' as upnp;
import 'main.dart';
import 'node.dart';

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
      final result = dio.Dio().get(addr);
      return (await result).data != null;
    } catch (_) {
      return false;
    }
  }

  static Future<int> getPort() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int port = prefs.getInt("port");

    if (port == null) {
      port = Random().nextInt(60000);
      prefs.setInt("port", port);
    }

    return port;
  }

  static Future<String> getIP() async {
    return await NetworkInfo().getWifiIP();
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

    ///Called by an external node to add this node as a known node. The external node is also
    ///added to the this node's known nodes list.
    app.post("/add_node", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String ip = parameters["addingNodeIp"];
      int port = int.parse(parameters["addingNodePort"]);

      KnownNodes.addNode(ip, port, fromServer: true);
      return Response.ok("done");
    });

    ///Called by an external node to send a shard to this device. This node also sends
    ///the shard to its known nodes if
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
            await dio.Dio().post(
              "http://${node.getNodeAddress()}/send_shard",
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

    app.post("/send_block", (Request request) async {
      final parameters = jsonDecode(await request.readAsString());

      Map<String, dynamic> block = jsonDecode(parameters["block"]);
      Block tempBlock;
      if (block["event"] == Block.uploadEvent) {
        tempBlock = Block.fromJsonUB(block);
      } else if (block["event"] == Block.deleteEvent) {
        tempBlock = Block.fromJsonDB(block);
      }

      var blocks = BlockChain.blocks;

      if (blocks
          .where((block) => block.timeCreated == tempBlock.timeCreated)
          .isEmpty) {
        state.getKnownNodes().forEach((node) {
          BlockChain.sendBlockchain(node.getNodeAddress(), tempBlock,
              fromServer: true);
        });

        BlockChain.addBlockToTempPool(tempBlock);

        if (!BlockChain.updatingBlockchain) {
          BlockChain.addBlockToBlockchain();
        }
        state.rfBChain();
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
        if (node.getNodeAddress() != sender) {
          nodes.add(node.getNodeAddress());
          nodesSendingTo.add(node);
        }
      }

      if (nodesSendingTo.isNotEmpty) {
        if (depth != 0) {
          for (var node in nodesSendingTo) {
            var r = await dio.Dio().post(
              "http://${node.getNodeAddress()}/send_known_nodes",
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
}
