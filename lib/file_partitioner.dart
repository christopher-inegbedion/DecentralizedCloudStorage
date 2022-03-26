import 'dart:io';
import 'dart:typed_data';


class FilePartioner {
  static Future<List<List<int>>> partitionFile(int numOfpartitions,
      int fileSizeBytes, List<int> fileBytes, bool encrypt) async {
    int chunkSize = fileSizeBytes ~/ numOfpartitions;
    int byteLastLocation = 0;
    List<List<int>> bytes = [];
    for (int i = 0; i < numOfpartitions; i++) {
      List<int> fileByteData;

      if (i == numOfpartitions - 1) {
        fileByteData = (Uint8List.fromList(fileBytes))
            .getRange(byteLastLocation, fileSizeBytes)
            .toList();
      } else {
        fileByteData = (Uint8List.fromList(fileBytes))
            .getRange(byteLastLocation, byteLastLocation + chunkSize)
            .toList();
      }

      //create file partitions
      if (encrypt) {
        bytes.add(GZipCodec().encode(fileByteData));
      } else {
        bytes.add(fileByteData);
      }

      byteLastLocation += chunkSize;
    }

    return bytes;
  }
}
