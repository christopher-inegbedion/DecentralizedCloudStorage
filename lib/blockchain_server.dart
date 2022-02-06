import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
import 'package:testwindowsapp/message_handler.dart';
import "package:upnp/router.dart" as router;
import 'package:upnp/upnp.dart' as upnp;
import 'main.dart';

class BlockchainServer {
  MyHomePageState state;
  BuildContext context;
  NetworkInfo _networkInfo;
  static int _port;
  static String ip;

  BlockchainServer(this.context, this.state) {
    _networkInfo = NetworkInfo();
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
    _port = prefs.getInt("port");

    if (_port == null) {
      _port = Random().nextInt(60000);
      prefs.setInt("port", _port);
    }

    return _port;
  }

  static void _uploadFileToNode(Map args) async {
    String fileName = args["fileName"];
    String fileExtension = args["fileExtension"];
    List<int> fileBytes = args["fileBytes"];
    String nodeAddr = args["addr"];
    int index = args["depth"];

    var formData = dio.FormData.fromMap({
      "fileName": fileName,
      "fileExtension": fileExtension,
      "index": index,
      "file": dio.MultipartFile.fromBytes(utf8.encode(fileBytes.toString()))
    });

    await dio.Dio().post("http://$nodeAddr/receive_file", data: formData);
  }

  static void _writeReceivedFile(Map<String, dynamic> args) async {
    String savePath = args["savePath"];
    List<int> byteData = args["byteData"];

    await File(savePath)
        .writeAsBytes(GZipCodec().decode(byteData), mode: FileMode.append);
  }

  static void startServer(BuildContext context, MyHomePageState state) async {
    var app = shelf_router.Router();
    ip = await NetworkInfo().getWifiIP();
    _port = await getPort();

    if (ip == null || _port == null) {
      throw Exception("An error occured starting the server");
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();

    String savePath = prefs.getString("storage_location");
    String shardDataDirPath = "$savePath/shard_data";

    app.get("/", (Request request) async {
      return Response.ok('hello-world');
    });

    app.post("/add_node", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String addr = parameters["sendingNodeAddr"];

      state.addNode(addr: addr);
      return Response.ok("done");
    });

    app.post('/upload', (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String fileName = parameters["fileName"];
      List<int> byteArray = List.from(json.decode(parameters["file"]));
      int depth = int.parse(parameters["depth"]) - 1;

      File file =
          await File("$shardDataDirPath/$fileName").create(recursive: true);
      await file.writeAsBytes(byteArray);

      if (depth != 0) {
        print("depth $depth");
        state.getKnownNodes().forEach((node) async {
          print(node);
          Map<String, dynamic> formMapData = {
            "depth": depth,
            "fileName": fileName,
            "file": dio.MultipartFile.fromBytes(utf8.encode((file).toString()))
          };

          dio.FormData formData = dio.FormData.fromMap(formMapData);
          var result = await dio.Dio().post(
            "http://$node/upload",
            data: formData,
          );
        });
      } else {
        print("depth done");
      }

      (await File("$shardDataDirPath/$fileName").create(recursive: true))
          .writeAsBytes(byteArray);
      return Response.ok('hello-world');
    });

    app.post("/download", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      File requestingFile = File("$shardDataDirPath/${parameters['fileName']}");

      Map args = {
        "fileName": parameters["fileName"],
        "fileExtension": parameters["fileExtension"],
        "fileBytes": await requestingFile.readAsBytes(),
        "addr": "${parameters["ip"]}:${parameters["port"]}",
        "depth": int.parse(parameters["depth"])
      };

      compute(_uploadFileToNode, args).whenComplete(() {
        state.hideDownloadProgress(int.parse(parameters["index"]));

        MessageHandler.showSuccessMessage(context, "File now available");
      });

      return Response.ok("done");
    });

    app.post("/receive_file", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String savePath = prefs.getString("storage_location");
      String fileName = parameters["fileName"];
      String fileExtension = parameters["fileExtension"];
      List<int> byteArray = List.from(json.decode(parameters["file"]));

      int newIndex = int.parse(parameters["index"]) - 1;

      Map<String, dynamic> args = {
        "savePath": "$savePath/$fileName.$fileExtension",
        "byteData": byteArray
      };
      compute(_writeReceivedFile, args).whenComplete(() {
        if (newIndex != 0) {
          List<String> knownNodes = state.getKnownNodes();
          knownNodes.forEach((node) async {
            dio.FormData formData = dio.FormData.fromMap({
              "ip": await NetworkInfo().getWifiIP(),
              "port": await BlockchainServer.getPort(),
              "fileName": fileName,
              "fileExtension": fileExtension,
              "index": -1,
              "depth": newIndex,
            });

            await dio.Dio().post("http://$node/download", data: formData);
          });
        }
        print("file received");
      });

      return Response.ok("done");
    });

    app.post("/send_block", (Request request) async {
      final parameters = jsonDecode(await request.readAsString());

      Map<String, dynamic> block = parameters;
      Block tempBlock = Block.fromJson(block);
      BlockChain.addBlockToTempPool(tempBlock);

      if (!BlockChain.updatingBlockchain) {
        print("blockchain not updating");
        BlockChain.addBlockToBlockchain();
      }

      state.refreshBlockchain();

      return Response.ok("done");
    });

    await io.serve(app, ip, _port, shared: true);
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
          "NewExternalPort": _port,
          "NewProtocol": 'TCP',
          "NewInternalPort": _port,
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
