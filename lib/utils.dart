import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:testwindowsapp/token.dart';

import 'server.dart';

String convertTimestampToDate(int value) {
  var date = DateTime.fromMillisecondsSinceEpoch(value);
  var d12 = DateFormat('EEE, MM-dd-yyyy, hh:mm:ss a').format(date);
  return d12;
}

String createFileHash(List<int> byteData, {bool decrypt=true}) {
  try {
    List<int> data = decrypt ? GZipCodec().decode(byteData) : byteData;
    var digest = crypto.sha256.convert(data);
    return digest.toString();
  } catch (e, trace) {
    return "";
  }
}


 String getFileName(PlatformFile file, FilePickerResult result) {
    String fileExtension = file.extension;

    return file.name
        .substring(0, (file.name.length - 1) - fileExtension.length);
  }

String getNodeAddress(String ip, int port) {
  return "$ip:$port";
}


  Future<String> getMyAddress() async {
    String ip = await NetworkInfo().getWifiIP();
    int port = await BlockchainServer.getPort();

    return "$ip:$port";
  }
  
///Verifies whether the user can upload/download a file
bool canActionComplete(double tokenCost) {
  double availableTokes = Token.getInstance().availableTokens;
  return availableTokes >= tokenCost;
}
