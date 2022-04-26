import 'dart:io';

class FileCombiner {
  
  ///Combine file shards ``shards`` into the original file and return its byte data
  static List<int> combineShards(List<List<int>> shards, bool decrypt) {
    List<int> fileData = [];

    for (List<int> data in shards) {
      if (decrypt) {
        fileData.addAll(GZipCodec().decode(data));
      } else {
        fileData.addAll(data);
      }
    }

    return fileData;
  }
}
