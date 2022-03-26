import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'message_handler.dart';

class FileHandler {
  Future<String> selectSavePath(BuildContext context) async {
    String fileAddress = await FilePicker.platform.saveFile(
        dialogTitle: 'Download location',
        fileName: 'output-file.sh',
        lockParentWindow: true);

    if (fileAddress == null) {
      MessageHandler.showToast(context, "Save operation cancelled");
      return null;
    }

    return fileAddress;
  }

  static Future<bool> saveFile(
      List<int> fileByteData, String savePath, bool decrypt) async {
    try {
      (await File(savePath).writeAsBytes(fileByteData, mode: FileMode.write))
          .create(recursive: true);
      return true;
    } catch (e) {
      return false;
    }
  }


  static Future<PlatformFile> getPlatformFile() async {
    FilePickerResult result = await FilePicker.platform.pickFiles();

    return result.files.single;
  }
}