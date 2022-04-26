import 'dart:io';
import 'dart:typed_data';

class FilePartioner {
  ///Partition a file into ``numOfpartitions`` partitions
  static Future<List<List<int>>> partitionFile(int numOfpartitions,
      int fileSizeBytes, List<int> fileBytes, bool encrypt) async {
    int shardSize = fileSizeBytes ~/ numOfpartitions;

    //Cap the each shard to 200mb (excluding the last shard)
    if (shardSize > 200000000) {
      shardSize = 200000000;
    }
    
    int byteLastLocation = 0;
    List<List<int>> bytes = [];
    for (int i = 0; i < numOfpartitions; i++) {
      List<int> fileByteData;

      //The size of the last shard is different from the others
      //as it is possible that the remaining portions of the file
      //are either larger, the same size, or
      //smaller in size than the other shards.
      if (i == numOfpartitions - 1) {
        fileByteData = (Uint8List.fromList(fileBytes))
            .getRange(byteLastLocation, fileSizeBytes)
            .toList();
      } else {
        fileByteData = (Uint8List.fromList(fileBytes))
            .getRange(byteLastLocation, byteLastLocation + shardSize)
            .toList();
      }

      //Using the GZip format both obfuscates the shard's contents
      //and reduces its size
      if (encrypt) {
        bytes.add(GZipCodec().encode(fileByteData));
      } else {
        bytes.add(fileByteData);
      }

      byteLastLocation += shardSize;
    }

    return bytes;
  }
}
