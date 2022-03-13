import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:filesize/filesize.dart';
import 'package:pretty_json/pretty_json.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sn_progress_dialog/progress_dialog.dart';
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:testwindowsapp/domain_regisrty.dart';
import 'package:testwindowsapp/known_nodes.dart';
import 'package:testwindowsapp/message_handler.dart';
import 'package:testwindowsapp/node.dart';
import 'package:testwindowsapp/token.dart';
import 'package:testwindowsapp/token_view.dart';
import 'package:retrieval/trie.dart';
import 'constants.dart';
import 'user_session.dart';
import 'utils.dart';

final Token _token = Token.getInstance();
DomainRegistry _domainRegistry;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  UserSession.lockScreenSize();
  UserSession().getLastLoginTime();
  UserSession().logLoginTime();

  _token.deductTokens();
  _domainRegistry = DomainRegistry(
      await BlockchainServer.getIP(), await BlockchainServer.getPort());

  runApp(const MyApp());
}

Future<List<List<int>>> partitionFile(int partitions, int fileSizeBytes,
    List<int> fileBytes, bool encrypt) async {
  int chunkSize = fileSizeBytes ~/ partitions;
  int byteLastLocation = 0;
  List<List<int>> bytes = [];
  for (int i = 0; i < partitions; i++) {
    Map<String, dynamic> args = {
      "byteLastLocation": byteLastLocation,
      "fileSizeBytes": fileSizeBytes,
      "i": i,
      "partitions": partitions,
      "chunkSize": chunkSize,
      "fileBytes": fileBytes
    };
    List<int> encodedFile = [];
    List<int> fileByteData = await compute(_partitionFile, args);

    //create file partitions
    if (encrypt) {
      encodedFile = GZipCodec().encode(fileByteData);
    } else {
      encodedFile = fileByteData;
    }

    byteLastLocation += chunkSize;

    bytes.add(encodedFile);
  }

  return bytes;
}

List<int> combineShards(List<List<int>> shards, bool decrypt) {
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

Future<File> saveFile(
    List<int> fileByteData, String savePath, bool decrypt) async {
  return (await File(savePath).writeAsBytes(fileByteData, mode: FileMode.write))
      .create(recursive: true);
}

List<int> _partitionFile(Map<String, dynamic> args) {
  int byteLastLocation = args["byteLastLocation"];
  int fileSizeBytes = args["fileSizeBytes"];
  int currentPartition = args["i"];
  int partitions = args["partitions"];
  int chunkSize = args["chunkSize"];
  List<int> fileBytes = args["fileBytes"];

  List<int> encodedFile;
  if (currentPartition == partitions - 1) {
    encodedFile = (Uint8List.fromList(fileBytes))
        .getRange(byteLastLocation, fileSizeBytes)
        .toList();
  } else {
    encodedFile = (Uint8List.fromList(fileBytes))
        .getRange(byteLastLocation, byteLastLocation + chunkSize)
        .toList();
  }

  return encodedFile;
}

void _sendShardToNode(Map<String, dynamic> args) async {
  String nodeAddr = args["receipientAddr"];
  String fileName = args["fileName"];
  List<int> fileByteData = args["fileByteData"];
  int depth = args["depth"];

  Map<String, dynamic> formMapData = {
    "depth": depth,
    "fileName": fileName,
    "file": MultipartFile.fromBytes(utf8.encode((fileByteData).toString()))
  };

  FormData formData = FormData.fromMap(formMapData);
  var result = await Dio().post(
    "http://$nodeAddr/send_shard",
    data: formData,
  );
}

List searchKeyword(String keyword, Trie trieData) {
  List searchResults = [];
  searchResults.addAll(trieData.find(keyword));

  return searchResults;
}

class MyApp extends StatelessWidget {
  const MyApp({Key key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shr: Cloud storage platform',
      theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: GoogleFonts.robotoMonoTextTheme()),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  GlobalKey<FormState> searchKey = GlobalKey();
  bool searchVisible = false;
  bool autoCompleteVisible = false;
  bool searchMode = false;
  Map<String, dynamic> fileHashes = {};
  List<int> filesDownloading = [];
  List<String> searchResults = [];
  BlockchainServer server;
  final trie = Trie();
  int depth = 2;

  void updateBlockchain() {}

  Widget createTopNavBarButton(String text, IconData btnIcon, Function action) {
    return Container(
      child: TextButton(
        onPressed: () {
          action();
        },
        child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
            padding:
                const EdgeInsets.only(left: 5, right: 5, top: 3, bottom: 3),
            child: Row(
              children: [
                Icon(
                  btnIcon,
                  size: 13,
                ),
                Container(
                    margin: const EdgeInsets.only(left: 5),
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 12),
                    )),
              ],
            )),
      ),
    );
  }

  void toggleDownloadProgressVisibility(int index) {
    setState(() {
      if (filesDownloading.contains(index)) {
        filesDownloading.remove(index);
      } else {
        filesDownloading.add(index);
      }
    });
  }

  Future<Map<String, Set>> getKnownNodesForNodes(
      List<Node> nodesReceiving) async {
    String myAddress = await Node.getMyAddress();
    Map<String, Set> backupNodes = {};

    for (int i = 0; i < nodesReceiving.length; i++) {
      var r = await Dio().post(
        "http://${nodesReceiving[0].getNodeAddress()}/send_known_nodes",
        data: {
          "depth": depth.toString(),
          "nodes": [],
          "origin": myAddress,
          "sender": myAddress
        },
      );

      backupNodes[i.toString()] = {...jsonDecode(r.data)};
      backupNodes[i.toString()]
          .add(KnownNodes.knownNodes.toList()[i].getNodeAddress());
    }

    return backupNodes;
  }

  List<Node> getNodesReceivingShard(int n) {
    Set<Node> tempList = {};
    tempList.addAll(KnownNodes.knownNodes);
    List<Node> selectedNodes = [];

    for (int i = 0; i < n; i++) {
      Node selected = tempList.elementAt(Random().nextInt(tempList.length));
      selectedNodes.add(selected);
      tempList.remove(selected);
    }

    return selectedNodes;
  }

  int _getNumberOfPartitionsForFile(int fileSizeBytes) {
    double fileSizeMBytes = fileSizeBytes / (1024 * 1024);
    if (fileSizeMBytes <= 200) {
      return 1;
    } else if (fileSizeMBytes > 1800) {
      return KnownNodes.maximumKnownNodesAllowed;
    } else {
      return (fileSizeMBytes / 200).floor();
    }
  }

  Future<bool> uploadFile() async {
    if (KnownNodes.knownNodes.isEmpty) {
      MessageHandler.showFailureMessage(context, "You have no known nodes");
      return false;
    }

    //select file
    FilePickerResult result = await FilePicker.platform.pickFiles();
    PlatformFile platformFile = result.files.single;
    File file = File((platformFile.path).toString());
    int depth = 2;

    final readFile = await File(file.path).open();
    int fileSizeBytes = await readFile.length();

    //calcualte how many partitions are required
    int partitions = _getNumberOfPartitionsForFile(fileSizeBytes);

    String fileExtension = platformFile.extension;
    String fileName = platformFile.name
        .substring(0, platformFile.name.length - (fileExtension.length + 1));
    String filePath = (platformFile.path).toString().substring(
        0,
        (platformFile.path).toString().length -
            result.files.single.name.length);

    List<List<int>> bytes = [];
    List<File> partitionFiles = [];

    bool canUpload = await showUploadDetailsDialog(fileName,
        Token.calculateFileCost(fileSizeBytes), fileSizeBytes, partitions);
    List<int> fileBytes = await File(file.path).readAsBytes();

    //verify that user can upload file
    if (canUpload) {
      bytes = await partitionFile(partitions, fileSizeBytes, fileBytes, true);

      for (int i = 0; i < bytes.length; i++) {
        File newFile = await File("$filePath$i").create();
        partitionFiles.add(await newFile.writeAsBytes(bytes[i]));
      }

      //Create list of nodes each shard can be sent to
      Map<String, Set> nodesReceiving =
          await getKnownNodesForNodes(getNodesReceivingShard(partitions));

      //send shard byte data to selected known nodes
      for (int i = 0; i < partitions; i++) {
        for (String receivingNodeAddr in nodesReceiving[i.toString()]) {
          sendShard(receivingNodeAddr, "$fileName-$i", depth,
                  f: partitionFiles[i])
              .catchError((e, st) {
            MessageHandler.showFailureMessage(context, e.toString());
            return;
          });
        }
      }

      Map<String, List> shardHosts = {};
      nodesReceiving.forEach((key, value) {
        shardHosts[key] = value.toList();
      });

      Block tempBlock =
          await BlockChain.createNewBlock(bytes, platformFile, result, shardHosts);

      //send the block to all known nodes
      _sendBlocksToKnownNodes(tempBlock);
    }

    return true;
  }

  void _sendBlocksToKnownNodes(Block tempBlock) async {
    String myIP = await NetworkInfo().getWifiIP();

    Set<Node> nodesReceivingShard = {};
    int myPort = await BlockchainServer.getPort();

    Node self = Node(myIP, myPort);

    nodesReceivingShard.add(self);

    for (int i = 0; i < KnownNodes.knownNodes.length; i++) {
      if ((KnownNodes.knownNodes.toList()[i]).getNodeAddress() !=
          self.getNodeAddress()) {
        nodesReceivingShard.add(KnownNodes.knownNodes.toList()[i]);
      }
    }

    for (Node node in nodesReceivingShard) {
      print(node.port);
      BlockChain.sendBlockchain(node.getNodeAddress(), tempBlock);
    }
  }

  void toggleSeachVisibility() {
    searchResults.clear();

    setState(() {
      searchVisible = !searchVisible;
      searchMode = !searchMode;
    });
  }

  bool verifyFileShard(List<String> fileHashes, List<int> byteData) {
    try {
      String hashByteData = createFileHash(byteData);

      return fileHashes.contains(hashByteData);
    } catch (e, trace) {
      return false;
    }
  }

  Future downloadFileFromBlockchain(
      String fileHash, String fileName, int index) async {
    Block block = Block.fromJsonUB((await getBlockchain())["blocks"][fileHash]);

    String fileExtension = block.fileExtension;
    Map<String, List<dynamic>> shardHosts = block.shardHosts;
    List<String> fileHashes = block.fileHashes;

    int shardsDownloaded = 0;
    bool badShard = false;
    List<List<int>> fileShardData = [];

    toggleDownloadProgressVisibility(index);
    await Future.forEach(shardHosts.keys, (key) async {
      await Future.forEach(shardHosts[key], (nodeAddr) async {
        bool error = false;

        try {
          Response<dynamic> response = await Dio().post(
              "http://$nodeAddr/send_file",
              data: {"fileName": "$fileName-$key"});
          List<int> byteArray = List<int>.from(json.decode(response.data));
          fileShardData.add(byteArray);

          return;
        } catch (e) {
          print(e);
        }

        return;
      });
    }).whenComplete(() async {
      for (int i = 0; i < fileShardData.length; i++) {
        var byteArray = fileShardData[i];
        if (!verifyFileShard(fileHashes, byteArray)) {
          MessageHandler.showFailureMessage(
              context, "Bad shard $fileName-$i");
          return;
        }
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      print("no things");

      String savePath = prefs.getString("storage_location");
      List<int> fileByteData = combineShards(fileShardData, true);
      saveFile(fileByteData, "$savePath/$fileName.$fileExtension", true)
          .whenComplete(() {
        shardsDownloaded += 1;
        MessageHandler.showSuccessMessage(context,
            "Shard $shardsDownloaded of ${shardHosts.length} downloaded");
      });

      toggleDownloadProgressVisibility(index);
    });

    // for (int i = 0; i < shardHosts.length; i++) {
    //   String key = shardHosts.keys.elementAt(i);
    //   List possibleNodes = shardHosts[key];

    //   for (String nodeAddr in possibleNodes) {
    //     bool error = false;

    //     Dio().post("http://$nodeAddr/send_file",
    //         data: {"fileName": "$fileName-$key"}).then((response) {
    //       List<int> byteArray = List<int>.from(json.decode(response.data));
    //       fileShardData.add(byteArray);
    //       print(byteArray);
    //     }).onError((error, stackTrace) {
    //       error = true;
    //     });

    //     if (!error) {
    //       break;
    //     }
    //   }
    // }
  }

  Future<PlatformFile> _getPlatformFile() async {
    FilePickerResult result = await FilePicker.platform.pickFiles();

    return result.files.single;
  }

  Future<File> selectFile() async {
    PlatformFile fileData = await _getPlatformFile();
    return File((fileData.path).toString());
  }

  Future sendShard(String receipientAddr, String fileName, int depth,
      {File f}) async {
    if (await BlockchainServer.isNodeLive("http://$receipientAddr")) {
      File file = f;

      if (file == null) {
        PlatformFile _platformFile = await _getPlatformFile();
        file = File(_platformFile.path);
      }

      try {
        ProgressDialog pd = ProgressDialog(context: context);
        pd.show(max: 100, msg: "Uploading shard to $receipientAddr...");
        Map<String, dynamic> args = {
          "receipientAddr": receipientAddr,
          "fileName": fileName,
          "fileByteData": await file.readAsBytes(),
          "depth": depth
        };
        compute(_sendShardToNode, args).whenComplete(() {
          pd.close();
        });

        MessageHandler.showSuccessMessage(
            context, "Node $receipientAddr has received a partition");
      } catch (e, stacktrace) {
        MessageHandler.showFailureMessage(context, e.toString());
        print(e);
      }
    } else {
      MessageHandler.showFailureMessage(
          context, "Node $receipientAddr is not live");
      throw Exception("Node $receipientAddr is not live");
    }
  }

  void hideDownloadProgress(int index) {
    setState(() {
      filesDownloading.remove(index);
    });
  }

  void deleteFile(String fileName, String fileHash) async {
    Block block = Block.fromJsonUB((await getBlockchain())["blocks"][fileHash]);

    if (block.fileHost != _domainRegistry.getID()) {
      throw Exception("Permission denied. File not uploaded by you");
    }

    String blockHash = block.merkleTreeRootHash;
    Block deleteBlock = BlockChain.createDeleteBlock(
        fileName, blockHash, block.shardByteHash, _domainRegistry.getID());

    _sendBlocksToKnownNodes(deleteBlock);
  }

  //Dialog methods
  Future showDownloadDetailsDialog(String fileName, double cost,
      int fileSizeBytes, int shardsCreated) async {
    double availableTokes = _token.availableTokens;
    bool canDownload = false;
    if (availableTokes >= cost) {
      canDownload = true;
    }

    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Download details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text("File name: "),
                    Flexible(
                        child: SelectableText(
                      fileName,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("File size: "),
                    Flexible(
                        child: SelectableText(
                      filesize(fileSizeBytes),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("Number of shards: "),
                    Flexible(
                        child: SelectableText(
                      shardsCreated.toString(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("Download cost: "),
                    Flexible(
                      child: SelectableText("${cost.toString()} token(s)",
                          style: TextStyle(
                              fontSize: 14,
                              color:
                                  canDownload ? Colors.grey[600] : Colors.red)),
                    )
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              FlatButton(
                  textColor: Colors.red,
                  child: const Text('cancel'),
                  onPressed: () {
                    Navigator.pop(context, false);
                  }),
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: canDownload
                    ? () {
                        _token.availableTokens = _token.availableTokens - cost;
                        Navigator.pop(context, true);
                      }
                    : null,
              ),
            ],
          );
        });
  }

  Future showUploadDetailsDialog(String fileName, double cost,
      int fileSizeBytes, int shardsCreated) async {
    double availableTokes = _token.availableTokens;
    bool canUpload = false;
    if (availableTokes >= cost) {
      canUpload = true;
    }
    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Upload details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text(fileData.toString()),
                Row(
                  children: [
                    const Text("File name: "),
                    Flexible(
                        child: SelectableText(
                      fileName,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("File size: "),
                    Flexible(
                        child: SelectableText(
                      filesize(fileSizeBytes),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("Number of shards: "),
                    Flexible(
                        child: SelectableText(
                      shardsCreated.toString(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("Upload cost: "),
                    Flexible(
                      child: SelectableText("${cost.toString()} token(s)",
                          style: TextStyle(
                              fontSize: 14,
                              color:
                                  canUpload ? Colors.grey[600] : Colors.red)),
                    )
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                  child:
                      const Text('cancel', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.pop(context, false);
                  }),
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: canUpload
                    ? () {
                        _token.availableTokens = _token.availableTokens - cost;
                        Navigator.pop(context, true);
                      }
                    : null,
              ),
            ],
          );
        });
  }

  Future showServerStartErrorDialog(String ip, int port) async {
    return showDialog(
        barrierDismissible: false,
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Server error',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    "An error occured starting the server. Please ensure you are connected to the internet, then restart the program.",
                    style: TextStyle(color: Colors.red[600])),
                const SizedBox(
                  height: 10,
                ),
                Row(
                  children: [
                    const Text("IP address: "),
                    Flexible(
                        child: SelectableText(
                      ip ?? "Unavailable",
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    const Text("Port number: "),
                    Flexible(
                        child: SelectableText(
                      port == null ? "Not available" : port.toString(),
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
              ],
            ),
          );
        });
  }

  void requestStorageLocationDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (await UserSession.isUserNew()) {
      String path = await FilePicker.platform.getDirectoryPath();

      if (path == null) {
        MessageHandler.showFailureMessage(
            context, "Storage location is required");
        requestStorageLocationDialog();
        return;
      }

      prefs.setString(Constants.storageLocationKey, path);
    }
  }

  Future<List> showAddNodeDialog() {
    TextEditingController _textIPController = TextEditingController();
    TextEditingController _textPortController = TextEditingController();

    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('New node'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) {},
                  keyboardType: TextInputType.number,
                  controller: _textIPController,
                  decoration:
                      const InputDecoration(hintText: "Enter IP address"),
                ),
                TextField(
                  onChanged: (value) {},
                  keyboardType: TextInputType.number,
                  controller: _textPortController,
                  decoration:
                      const InputDecoration(hintText: "Enter port number"),
                ),
              ],
            ),
            actions: <Widget>[
              FlatButton(
                // color: Colors.green,
                textColor: Colors.blue,
                child: const Text(
                  'Add self',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  ),
                ),
                onPressed: () async {
                  _textIPController.text = await NetworkInfo().getWifiIP();
                  _textPortController.text =
                      (await BlockchainServer.getPort()).toString();
                },
              ),
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context,
                      [_textIPController.text, _textPortController.text]);
                },
              ),
            ],
          );
        });
  }

  Future showKnownNodesDialog() {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Known nodes'),
            content: KnownNodes.knownNodes.isEmpty
                ? const Text("Such empty")
                : SizedBox(
                    height: 160,
                    width: 200,
                    child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: KnownNodes.knownNodes.length,
                        itemBuilder: (context, index) {
                          return Text(KnownNodes.knownNodes
                              .toList()[index]
                              .getNodeAddress());
                        }),
                  ),
            actions: <Widget>[
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        });
  }

  Future printBlockchainDialog(Map<String, dynamic> blockchain) async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            scrollable: true,
            content: SelectableText(prettyJson(blockchain, indent: 2),
                style: const TextStyle(fontSize: 12)),
            actions: <Widget>[
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        });
  }

  void showFileInfoDialog(String fileHash, String uploader) async {
    Map<String, dynamic> fileData = fileHashes[fileHash];
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'File details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text(fileData.toString()),
                Row(
                  children: [
                    const Flexible(child: Text("Block hash: ")),
                    Flexible(
                        child: SelectableText(
                      fileData["merkleRootHash"],
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text("Previous block hash: ",
                          style: TextStyle(color: Colors.grey[800])),
                    ),
                    Flexible(
                      child: SelectableText(fileData["prevBlockHash"],
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Text("Time created: "),
                    Flexible(
                      child: SelectableText(
                          convertTimestampToDate(fileData["timeCreated"]),
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Flexible(child: Text("File name: ")),
                    Flexible(
                      child: SelectableText(fileData["fileName"],
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Flexible(child: Text("File extension: ")),
                    Flexible(
                      child: SelectableText(fileData["fileExtension"],
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Flexible(child: Text("File size, in bytes: ")),
                    Flexible(
                      child: SelectableText(
                          fileData["fileSizeBytes"].toString(),
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Text("Shards created: "),
                    Flexible(
                      child: SelectableText(
                          fileData["shardsCreated"].toString(),
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Text("Event cost: "),
                    Flexible(
                      child: SelectableText(
                          "${fileData["eventCost"].toString()} token(s)",
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Text("Shard hosts: "),
                    Flexible(
                      child: Flexible(
                        child: SelectableText(fileData["shardHosts"].toString(),
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600])),
                      ),
                    )
                  ],
                ),
                Row(
                  children: [
                    const Text("File hashes: "),
                    Flexible(
                      child: SelectableText(fileData["fileHashes"].toString(),
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600])),
                    )
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        });
  }

  Future<Map<String, dynamic>> getBlockchain() async {
    return BlockChain.loadBlockchain();
  }

  Widget displayBlockchainFiles(Map<String, dynamic> blockchain) {
    _refreshBlockchain();

    if (fileHashes.isEmpty) {
      return Expanded(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            "No files",
            style: TextStyle(),
          ),
          Text(
            "Click 'Upload' to begin uploading files.",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ));
    }

    return ListView.builder(
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        itemCount: fileHashes.length,
        itemBuilder: (context, index) {
          Map<String, dynamic> block =
              fileHashes[fileHashes.keys.elementAt(index)];
          String fileName = block["fileName"];
          String fileHash = block["merkleRootHash"];
          int fileSizeBytes = block['fileSizeBytes'];
          int numberOfShards = block['shardsCreated'];
          bool canFileBeDeleted = block['fileHost'] == _domainRegistry.getID();

          return InkWell(
            onTap: () async {
              bool canDownload = await showDownloadDetailsDialog(
                  fileName,
                  Token.calculateFileCost(fileSizeBytes),
                  fileSizeBytes,
                  numberOfShards);

              if (canDownload) {
                Future.delayed(const Duration(seconds: 2));
                downloadFileFromBlockchain(fileHash, fileName, index);
              }
            },
            child: Column(
              children: [
                Wrap(
                  // crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(
                          top: 10,
                        ),
                        margin: const EdgeInsets.only(left: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                fileName,
                                style: const TextStyle(fontSize: 15),
                              ),
                              const Text(
                                " by ",
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              SizedBox(
                                width: 100,
                                child: GestureDetector(
                                  onTap: () {
                                    MessageHandler.showToast(
                                        context,
                                        fileHashes[fileHashes.keys
                                            .elementAt(index)]['fileHost']);
                                  },
                                  child: Text(
                                    fileHashes[fileHashes.keys.elementAt(index)]
                                        ['fileHost'],
                                    style: const TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                        overflow: TextOverflow.ellipsis,
                                        fontSize: 11),
                                  ),
                                ),
                              ),
                            ]),
                            Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 2),
                                  child: const Icon(Icons.access_time_rounded,
                                      color: Colors.grey, size: 12),
                                ),
                                Container(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    "Uploaded: ${convertTimestampToDate(fileHashes[fileHashes.keys.elementAt(index)]["timeCreated"])}",
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 1),
                                  child: const Icon(Icons.sd_card_outlined,
                                      color: Colors.grey, size: 12),
                                ),
                                Container(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    filesize(fileHashes[fileHashes.keys
                                        .elementAt(index)]["fileSizeBytes"]),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                              ],
                            )
                          ],
                        )),
                    Container(
                      margin: const EdgeInsets.only(right: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            splashRadius: 10,
                            icon: const Icon(
                              Icons.description_outlined,
                              size: 12,
                            ),
                            onPressed: () {
                              String fileHash =
                                  fileHashes.keys.elementAt(index);
                              String fileUploader =
                                  fileHashes[fileHashes.keys.elementAt(index)]
                                      ['fileHost'];
                              showFileInfoDialog(fileHash, fileUploader);
                            },
                          ),
                          Visibility(
                            visible: canFileBeDeleted,
                            child: IconButton(
                              splashRadius: 10,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 12,
                              ),
                              onPressed: () {
                                String fileName =
                                    fileHashes[fileHashes.keys.elementAt(index)]
                                        ["fileName"];
                                String fileHash =
                                    fileHashes.keys.elementAt(index);
                                deleteFile(fileName, fileHash);
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
                Visibility(
                    visible: filesDownloading.contains(index),
                    child: const LinearProgressIndicator())
              ],
            ),
          );
        });
  }

  void rfBChain() {
    setState(() {
      _refreshBlockchain();
    });
  }

  void _refreshBlockchain() async {
    List<String> deletedFileHashes = await getDeletedFiles();
    Map<String, dynamic> blockchain = await getBlockchain();
    fileHashes.clear();

    blockchain["blocks"].forEach((fileHash, key) {
      String fileName = blockchain["blocks"][fileHash]["fileName"];
      if (fileName != "genesis" &&
          key["event"] != Block.deleteEvent &&
          !deletedFileHashes.contains(key["merkleRootHash"])) {
        trie.insert(fileName);

        fileHashes[fileHash] = blockchain["blocks"][fileHash];
      }
    });
  }

  Future<List<String>> getDeletedFiles() async {
    List<String> filesDeleted = [];
    getBlockchain().whenComplete(() {
      List<Block> blocks = BlockChain.blocks;

      for (Block block in blocks) {
        if (block.event == Block.deleteEvent) {
          filesDeleted.add(block.blockFileHash);
        }
      }
    });

    return filesDeleted;
  }

  List<Node> getKnownNodes() {
    return KnownNodes.knownNodes.toList();
  }

  @override
  void initState() {
    super.initState();

    BlockchainServer.startServer(context, this);

    requestStorageLocationDialog();
    _domainRegistry.generateID();
    UserSession.saveNewUser();
    _refreshBlockchain();
  }

  @override
  Widget build(BuildContext context) {
    // _refreshBlockchain();
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                Container(
                  margin: EdgeInsets.only(top: 10, bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        createTopNavBarButton(
                            "SEARCH", Icons.search, toggleSeachVisibility),
                        createTopNavBarButton("UPLOAD", Icons.upload_file,
                            () async {
                          uploadFile();
                        }),
                        createTopNavBarButton("ADD NODE", Icons.person_add,
                            () async {
                          List result = await showAddNodeDialog();
                          String ip = result[0];
                          int port = int.parse(result[1]);

                          KnownNodes.addNode(ip, port).whenComplete(() {
                            MessageHandler.showSuccessMessage(
                                context, "Node $ip:$port has been added");
                          });
                        }),
                        createTopNavBarButton("VIEW KNOWN NODES", Icons.person,
                            () {
                          showKnownNodesDialog();
                        }),
                        FutureBuilder(
                            future: BlockchainServer.getPort(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                int port = snapshot.data;
                                return SelectableText(
                                    "port: ${port.toString()}");
                              } else {
                                return const CircularProgressIndicator();
                              }
                            }),
                        Container(width: 40),
                        Container(
                            margin: const EdgeInsets.only(right: 10),
                            child: AvailableTokensView(_token))
                      ],
                    ),
                  ),
                ),
                Container(height: 1, color: Colors.grey[100]),
                Stack(
                  children: [
                    Column(
                      children: [
                        SizedBox(
                          height: 40,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                                margin: const EdgeInsets.only(left: 20),
                                child: const Text(
                                  "Recently shared",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold),
                                )),
                          ),
                        ),
                        Container(height: 1, color: Colors.grey[100]),
                      ],
                    ),
                    Visibility(
                      visible: searchVisible,
                      child: Container(
                        width: double.maxFinite,
                        color: Colors.white,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                              margin: const EdgeInsets.only(left: 20),
                              child: Form(
                                key: searchKey,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.search,
                                      size: 11,
                                    ),
                                    Expanded(
                                      child: Container(
                                        alignment: Alignment.centerLeft,
                                        margin: const EdgeInsets.only(left: 10),
                                        child: TextFormField(
                                          onChanged: (value) {
                                            if (value.isEmpty) {
                                              setState(() {
                                                autoCompleteVisible = false;
                                              });
                                            } else {
                                              setState(() {
                                                searchResults =
                                                    searchKeyword(value, trie);
                                              });
                                              setState(() {
                                                if (searchResults.isNotEmpty) {
                                                  autoCompleteVisible = true;
                                                }
                                              });
                                            }
                                          },
                                          scrollPadding: EdgeInsets.zero,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              hintText: "Search"),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(
                                          left: 20, right: 20),
                                      child: IconButton(
                                        splashRadius: 3,
                                        icon: const Icon(
                                          Icons.close,
                                          size: 11,
                                        ),
                                        onPressed: () {
                                          toggleSeachVisibility();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ),
                      ),
                    ),
                    Visibility(
                      visible: searchVisible && autoCompleteVisible,
                      child: Container(
                        margin: const EdgeInsets.only(top: 43),
                        child: Column(
                          children: [
                            ListView.builder(
                                shrinkWrap: true,
                                itemCount: searchResults.length,
                                itemBuilder: (context, index) {
                                  String fileName = searchResults[index];
                                  String fileHash = searchResults[index];
                                  return InkWell(
                                    onTap: () {
                                      downloadFileFromBlockchain(
                                          fileHash, fileName, 0);
                                    },
                                    child: Row(
                                      children: [
                                        Container(
                                            padding: const EdgeInsets.only(
                                                top: 10, bottom: 10, left: 20),
                                            child: Text(fileName)),
                                        Expanded(child: Container()),
                                        Container(
                                            margin: const EdgeInsets.only(
                                                right: 10),
                                            child: const Text(
                                                "click to download",
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.green)))
                                      ],
                                    ),
                                  );
                                }),
                            Container(
                                alignment: Alignment.centerLeft,
                                margin:
                                    const EdgeInsets.only(left: 20, bottom: 5),
                                child: const Text("Search results",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 10))),
                            Container(height: 1, color: Colors.grey[100]),
                          ],
                        ),
                        // color: const Color(0xFFFFFDE7)
                      ),
                    ),
                    Container(height: 1, color: Colors.grey[100]),
                  ],
                ),
                FutureBuilder(
                    future: getBlockchain(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        Map<String, dynamic> data = snapshot.data;

                        return displayBlockchainFiles(data);
                      } else {
                        return const CircularProgressIndicator();
                      }
                    }),
                Container(height: 100),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(height: 1, color: Colors.grey[100]),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Container(
                          decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(2)),
                          margin: const EdgeInsets.only(bottom: 10, left: 10),
                          padding: const EdgeInsets.only(
                              left: 5, right: 5, top: 0, bottom: 3),
                          child: FutureBuilder(
                            future: NetworkInfo().getWifiIP(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return SelectableText(
                                  "User ID: ${_domainRegistry.getID()}",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[700]),
                                );
                              } else {
                                return const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator());
                              }
                            },
                          )),
                    ),
                    Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            color: Colors.white,
                            margin:
                                const EdgeInsets.only(bottom: 10, right: 10),
                            child: createTopNavBarButton(
                                "CLEAR BLOCKCHAIN", Icons.clear_all, () {
                              BlockChain.clearBlockchain();

                              rfBChain();
                            }),
                          ),
                          Container(
                            color: Colors.white,
                            margin:
                                const EdgeInsets.only(bottom: 10, right: 10),
                            child: createTopNavBarButton(
                                "VIEW BLOCKCHAIN", Icons.list, () async {
                              Map<String, dynamic> blockchain =
                                  await getBlockchain();

                              printBlockchainDialog(blockchain);
                            }),
                          ),
                        ])
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
