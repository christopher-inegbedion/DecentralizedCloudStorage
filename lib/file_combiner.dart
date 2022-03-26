import 'dart:io';

class FileCombiner {

static List<int> combineShards(List<List<int>> shards, bool decrypt) {
    List<int> fileData = [];

    shards.forEach((data) {
      if (decrypt) {
        fileData.addAll(GZipCodec().decode(data));
      } else {
        fileData.addAll(data);
      }
    });

    return fileData;
  }
}