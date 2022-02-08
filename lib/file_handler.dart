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
}