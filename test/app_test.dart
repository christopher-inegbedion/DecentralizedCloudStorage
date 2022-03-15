import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_json/pretty_json.dart';
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/main.dart' as app;
import 'package:testwindowsapp/main.dart';
import 'package:testwindowsapp/token.dart';
import 'package:testwindowsapp/utils.dart';

void main() {
  // TestWidgetsFlutterBinding.ensureInitialized();

  const Map<String, dynamic> data = {
    "blocks": {
      "644cec9e0d3a8356689118c10364afc359bb5c1d4a7818acea545b4b85c3b146": {
        "fileName": "buffalo",
        "fileExtension": "py",
        "fileSizeBytes": 708,
        "shardByteHash":
            "18dc54b865ee708d70457ab81c7ac02499191360559ebcdf141c5f24e8f353c3",
        "shardsCreated": 1,
        "event": "upload",
        "eventCost": 6.59148e-7,
        "shardHosts": {
          "0": [
            "3558ff052c1848e3e9c03f5d00dec23159dfbc81ccf88753ac513f3c2945e087"
          ]
        },
        "timeCreated": 1647257861818,
        "fileHost":
            "3558ff052c1848e3e9c03f5d00dec23159dfbc81ccf88753ac513f3c2945e087",
        "fileHashes": [
          "18dc54b865ee708d70457ab81c7ac02499191360559ebcdf141c5f24e8f353c3"
        ],
        "salt": "V1KqKKmS7gPzxQ==",
        "merkleRootHash":
            "644cec9e0d3a8356689118c10364afc359bb5c1d4a7818acea545b4b85c3b146",
        "prevBlockHash":
            "8062d40935e0c4cc1ff94735417620dea098c90af96a72de271b84e5fdde1040"
      }
    }
  };

  group("Sprint 1", () {
    testWidgets("Search for keyword", (WidgetTester tester) async {
      await tester.pumpWidget(const app.MyApp(
        blockchainData: data,
      ));
      // await tester.pump();
      await tester.tap(find.byKey(const ValueKey("Search button")));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey("Search field")), "b");
      await tester.pump();

      final fileFinder = find.text("buffalo");

      expect(fileFinder, findsNWidgets(2));
    });

    testWidgets("Viewing a file's download details",
        (WidgetTester tester) async {
      await tester.pumpWidget(const app.MyApp(
        blockchainData: data,
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("Search button")));
      await tester.pump();
      final buffaloFile = find.byKey(const ValueKey("file_0"));

      // await tester.scrollUntilVisible(fileName, 1);
      await tester.tap(buffaloFile);
      await tester.pump();
      final fileNameFinder =
          find.byKey(const ValueKey("buffalo_download_descrtiption_name"));

      expect(fileNameFinder, findsOneWidget);
    });

    testWidgets("Uploading a file with no known nodes",
        (WidgetTester tester) async {
      await tester.pumpWidget(const app.MyApp());
      await tester.tap(find.byKey(const ValueKey("upload_node_btn")));
      await tester.pump();
      final errorMessage = find.text("You have no known nodes");
      expect(errorMessage, findsOneWidget);
    });

    testWidgets("Adding a node", (WidgetTester tester) async {
      String ip = "192.168.0.1";
      int port = 1234;

      await tester.pumpWidget(const app.MyApp(
        blockchainData: data,
      ));
      await tester.tap(find.byKey(const ValueKey("add_node_btn")));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey("enter_ip_textfield")), ip);
      await tester.enterText(
          find.byKey(const ValueKey("enter_port_textfield")), port.toString());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("confirm_add_node_btn")));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("view_known_nodes_btn")));
      await tester.pump();
      final newKnownNodeFinder = find.byKey(const ValueKey('known_node_0'));

      expect(newKnownNodeFinder, findsOneWidget);
    });

    testWidgets("Uploading a file with known nodes",
        (WidgetTester tester) async {
      //The flutter framework does not provide a mechanism to detect when the app window loses focus due to
      //the presence of the file picker, which is needed to perform this test
    });

    testWidgets("VIEW BLOCKCHAIN button is clicked", (WidgetTester tester) async {
    await tester.pumpWidget(const app.MyApp(
      blockchainData: data,
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("Search button")));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("view_blockchain_btn")));
    await tester.pump();
    final blockchainTextFinder = find.text(prettyJson(data));

    expect(blockchainTextFinder, findsOneWidget);
  });

    testWidgets("Delete button visible for only files uploaded by node",
        (WidgetTester tester) async {
      await tester.pumpWidget(const app.MyApp(
        blockchainData: data,
      ));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey("Search button")));
      final findDeleteBtnFinder = find.byKey(const ValueKey("delete_file_0"));

      expect(findDeleteBtnFinder, findsNothing);
    });

    testWidgets("User ID is visible", (WidgetTester tester) async {
      await tester.pumpWidget(const app.MyApp(
        blockchainData: data,
      ));
      await tester.pump();

      final userIDFinder = find.byKey(const ValueKey("user_id"));
      expect(userIDFinder, findsOneWidget);
    });
  });

  group("Sprint 2", () {
    test("Token formula is functional", () async {
      Token token = Token.getInstance();

      double tokensExpected = await token.incrementTokens(10);
      expect(tokensExpected, 0.762);

      double tokensExpected2 = await token.incrementTokens(20);
      expect(tokensExpected2, 0.816);

      double tokensExpected3 = await token.incrementTokens(50);
      expect(tokensExpected3, 1);
    });

    test("A user has downloaded/uploaded a file", () async {
      //Uploading a file
      //The flutter framework does not provide a mechanism to control the file manager so as to be
      //able to choose a file to upload

      //Downloading a file
      //Downloading a file would require at least 2 instances of the application running, which is
      //not possible as of the time at which this test was written (14/03/2022)
    });
  });

  group("Sprint 3", () {
    test("Combining shards into their original file", () async {
      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> shards =
          await partitionFile(partitions, byteData.length, byteData, false);

      List<int> fileData = combineShards(shards, false);
      expect(fileData, byteData);
    });

    test("Partitioning a file into shards", () async {
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

    test("Shard verification", () async {
      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> ptions =
          await partitionFile(partitions, byteData.length, byteData, false);

      List<String> fileHashes = [];
      ptions.forEach((shard) {
        fileHashes.add(createFileHash(shard, decrypt: false));
      });

      ptions[0][0] = 5;
      bool isShardValid = app.verifyFileShard(fileHashes, ptions[0]);
      print(GZipCodec().decode([100]));

      expect(isShardValid, false);
    });

    test("Creating a new block", () async {
      Map<String, dynamic> dataToCompare = {
        "fileName": "File name",
        "fileExtension": ".test",
        "fileSizeBytes": 1234,
        "shardByteHash":
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "shardsCreated": 1,
        "event": "upload",
        "eventCost": 0.0000011488540000000001,
        "shardHosts": {
          "0": [
            "c0365b5a3867cc382f6854fdc4f6f10c7857275c8b1e525beb8c399f80949be5",
            "a0fa7aed11f846f75b113e58d522ebf657be31469a124f9ee2e9109867400abf"
          ]
        },
        "timeCreated": 1647293137374,
        "fileHost": null,
        "fileHashes": [
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        ],
        "salt": "HPqJUfaiiL5LBQ==",
        "merkleRootHash": null,
        "prevBlockHash": ""
      };

      String testData = "ffffffff";
      List<int> byteData = utf8.encode(testData);
      int partitions = 8;

      List<List<int>> ptions =
          await partitionFile(partitions, byteData.length, byteData, false);

      List<String> fileHashes = [];
      ptions.forEach((shard) {
        fileHashes.add(createFileHash(shard, decrypt: false));
      });
 
      String fileExtension = ".test";
      String fileName = "File name";
      int fileSizeBytes = 1234;
      Map<String, List<dynamic>> shardHosts = {
        "0": ["host1", "host2"]
      };

      Block block = await BlockChain.createUploadBlock(
          ptions, fileExtension, fileName, fileSizeBytes, shardHosts);
          
      expect(block.fileName, fileName);
      expect(block.fileExtension, fileExtension);
      expect(block.fileSizeBytes, fileSizeBytes);
    });
  });
}
