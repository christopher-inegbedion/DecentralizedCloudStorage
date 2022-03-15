import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/cupertino.dart';

import 'package:intl/intl.dart';

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
