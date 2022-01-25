import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/cupertino.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/form_data.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:testwindowsapp/message_handler.dart';
import "package:upnp/router.dart" as router;
import 'package:upnp/upnp.dart' as upnp;
import 'main.dart';
import 'package:file_picker/file_picker.dart';

class BlockchainServer {
  MyHomePageState state;
  BuildContext context;
  NetworkInfo _networkInfo;
  static final port = Random().nextInt(60000);
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

  void startServer() async {
    var app = shelf_router.Router();
    ip = await NetworkInfo().getWifiIP();

    app.get("/", (Request request) async {
      return Response.ok('hello-world');
    });

    app.post("/add_node", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      String addr = parameters["addr"];
      print(addr);
      state.addNode(addr: addr);
      return Response.ok("done");
    });

    app.post('/upload', (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String savePath = prefs.getString("storage_location");
      String fileName = parameters["fileName"];
      List<int> byteArray = List.from(json.decode(parameters["file"]));
      File("$savePath/$fileName").writeAsBytes(byteArray);
      return Response.ok('hello-world');
    });

    app.post("/download", (Request request) async {
      final parameters = <String, String>{
        await for (final formData in request.multipartFormData)
          formData.name: await formData.part.readString(),
      };

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String savePath = prefs.getString("storage_location");
      MessageHandler.showSuccessMessage(
          context, "${parameters["ip"]} is requesting a file");
      File requestingFile = File("$savePath/${parameters['fileName']}");
      var formData = dio.FormData.fromMap({
        "fileName": parameters["fileName"],
        "fileExtension": parameters["fileExtension"],
        "file": dio.MultipartFile.fromBytes(
            utf8.encode((await requestingFile.readAsBytes()).toString()))
      });

      dio.Dio().post("http://${parameters["ip"]}:${parameters["port"]}/receive_file", data: formData);

      return Response.ok(
          GZipCodec().decode((await requestingFile.readAsBytes())).toString());
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

      File("$savePath/$fileName.$fileExtension")
          .writeAsBytes(GZipCodec().decode(byteArray), mode: FileMode.append);
      return Response.ok("done");
    });

    var server = await io.serve(app, ip, port);
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
          "NewExternalPort": port,
          "NewProtocol": 'TCP',
          "NewInternalPort": port,
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
