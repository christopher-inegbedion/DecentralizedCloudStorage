// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retrieval/trie.dart';
import 'package:testwindowsapp/blockchain.dart';

import 'package:testwindowsapp/main.dart';

void main() {

  //Test name format
  //methodTesting(optional)_whatIsBeingTested_whatShouldBeReturned

  TestWidgetsFlutterBinding.ensureInitialized();

  //change this directory to a path on your system
  String savePath = "/Users/chrisinegbedion/Desktop";

  group("TC-FR-02", () {
    test('searchKeyword_FileWithKeywordInNameAvailable_ReturnSearchResults',
        () {
      final trie = Trie();
      trie.insert("File A");
      trie.insert("File AA");
      trie.insert("File AAB");
      trie.insert("File B");
      trie.insert("File C");
      trie.insert("File D");

      List results = searchKeyword("File A", trie);

      expect(results, ["File A", "File AA", "File AAB"]);
    });

    test("searchKeyword_NoFileWithKeywordInNameAvailable_ReturnEmptyResults",
        () {
      final trie = Trie();
      trie.insert("File A");
      trie.insert("File AA");
      trie.insert("File AAB");
      trie.insert("File B");
      trie.insert("File C");
      trie.insert("File D");

      List results = searchKeyword("File Z", trie);

      expect(results, []);
    });
  });

  group("TC-FR-03", () {
    test(
        "combineShards_shardDataBeingCombinedIntoOrigirnalData_ReturnOriginalData",
        () async {
      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> shards =
          await partitionFile(partitions, byteData.length, byteData, false);

      List<int> fileData = combineShards(shards, false);
      expect(testData, const Utf8Decoder().convert(fileData));

      File savedFile = await saveFile(fileData, "$savePath/test_file", false);

      File file = File("$savePath/test_file");
      expect(await file.readAsBytes(), await savedFile.readAsBytes());
    });
  });

  group("TC-FR-04", () {
    test("partitionFile_dataBeingPartitionedIntoShards_ReturnListOfIntLists",
        () async {
      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> ptions =
          await partitionFile(partitions, byteData.length, byteData, false);

      expect(partitions, ptions.length);

      expect([
        [102],
        [102],
        [102],
        [102],
        [102],
        [102],
        [102],
        [102]
      ], ptions);
    });
  });

//   group("TC-FR-05", () {
//     fail("Not implemented");
//   });

  group("TC-FR-06", () {
    test("partitionFile_dataBeingPartitionedIntoShards_ReturnListOfIntLists",
        () async {
      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> ptions =
          await partitionFile(partitions, byteData.length, byteData, false);

      expect([
        [102],
        [102],
        [102],
        [102],
        [102],
        [102],
        [102],
        [102]
      ], ptions);
    });
  });

//   group("TC-FR-06", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-07", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-08", () {
//     fail("Not implemented");
//   });

  group("TC-FR-09", () {
    test("blockchainArrayShouldExist_ReturnTrueIfArrayExists", () {
      expect(BlockChain.blocks.length, 1); 
    });
  });

//   group("TC-FR-10", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-11", () {
//     fail("Not implemented");
//   });
//   group("TC-FR-11", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-12", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-13", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-14", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-15", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-16", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-17", () {
//     fail("Not implemented");
//   });

//   group("TC-FR-18", () {
//     fail("Not implemented");
//   });

  group("TC-FR-19", () {
    test("generateID_")
  });

//   group("TC-FR-20", () {
//     fail("Not implemented");
//   });
// }
}
