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
import 'package:testwindowsapp/blockchain/blockchain.dart';
import 'package:testwindowsapp/server.dart';
import 'package:testwindowsapp/domain_regisrty.dart';
import 'package:testwindowsapp/known_nodes.dart';
import 'package:testwindowsapp/message_handler.dart';
import 'package:testwindowsapp/node.dart';
import 'package:testwindowsapp/token.dart';
import 'package:testwindowsapp/token_view.dart';
import 'package:retrieval/trie.dart';
import 'constants.dart';
import 'file_combiner.dart';
import 'file_handler.dart';
import 'file_partitioner.dart';
import 'user_session.dart';
import 'utils.dart';

final Token _token = Token.getInstance();
DomainRegistry _domainRegistry;
String ip;
int port;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ip = await BlockchainServer.getIP();
  port = await BlockchainServer.getPort();

  UserSession.lockScreenSize();
  UserSession().getLastLoginTime();
  UserSession().logLoginTime();

  _token.deductTokens();

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
        "hash":
            "644cec9e0d3a8356689118c10364afc359bb5c1d4a7818acea545b4b85c3b146",
        "prevBlockHash":
            "8062d40935e0c4cc1ff94735417620dea098c90af96a72de271b84e5fdde1040"
      }
    }
  };

  runApp(const MyApp());
}

///Verify the hash of a file
bool verifyFileShard(List<String> fileHashes, List<int> shard) {
  try {
    String hashByteData = createFileHash(shard);

    return fileHashes.contains(hashByteData);
  } catch (e, trace) {
    return false;
  }
}

///This function contains functionality that would cause UI freezes
///and so is run with the compute method in a seperate Isolate
///
///Sends shard data to a node
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
  await Dio().post(
    "http://$nodeAddr/send_shard",
    data: formData,
  );
}

List<String> searchKeyword(String keyword, Trie trieData) {
  List<String> searchResults = [];
  searchResults.addAll(trieData.find(keyword));

  return searchResults;
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic> blockchainData;
  const MyApp({Key key, this.blockchainData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shr: Cloud storage platform',
      theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: GoogleFonts.robotoMonoTextTheme()),
      home: MyHomePage(
        blockchainData: blockchainData,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final Map<String, dynamic> blockchainData;
  const MyHomePage({Key key, this.blockchainData}) : super(key: key);

  @override
  State<MyHomePage> createState() =>
      MyHomePageState(blockchainData: blockchainData);
}

class MyHomePageState extends State<MyHomePage> {
  final Map<String, dynamic> blockchainData;
  MyHomePageState({this.blockchainData}) {
    if (this.blockchainData != null) {
      BlockChain.loadBlockchain(data: blockchainData);
    }
  }

  GlobalKey<FormState> searchKey = GlobalKey();
  bool searchVisible = false;
  bool autoCompleteVisible = false;
  Map<String, dynamic> fileHashes = {};
  List<int> filesDownloading = [];
  List<String> searchResults = [];
  BlockchainServer server;
  final trie = Trie();
  int depth = 2;
  bool usingID = false;

  Widget createTopNavBarButton(String text, IconData btnIcon, Function action,
      {Key key}) {
    return TextButton(
      key: key,
      onPressed: () {
        action();
      },
      child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)),
          padding: const EdgeInsets.only(left: 5, right: 5, top: 3, bottom: 3),
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
    int maximumShardSizeExceptLastShard =
        200; //All shards except the last shard are capped at 200MB
    double fileSizeMBytes = fileSizeBytes / (1024 * 1024);
    if (fileSizeMBytes <= maximumShardSizeExceptLastShard) {
      return 1;
    } else if (fileSizeMBytes > 1800) {
      return Constants.maxNumOfKnownNodes;
    } else {
      return (fileSizeMBytes / maximumShardSizeExceptLastShard).floor();
    }
  }

  List<Node> getLiveKnownNodes() {
    List<Node> liveNodes = [];
    KnownNodes.knownNodes.forEach((node) async {
      if (await node.isLive()) {
        liveNodes.add(node);
      }
    });

    return liveNodes;
  }

  ///Upload a file to the network.
  Future<bool> uploadFile() async {
    if (KnownNodes.knownNodes.isEmpty) {
      MessageHandler.showFailureMessage(context, "You have no known nodes");
      return false;
    }
    int depth = 2;

    //select file
    FilePickerResult result =
        await FilePicker.platform.pickFiles(); //Starts the file selecter dialog
    PlatformFile platformFile = result.files.single; //The file selected
    File file = File(
        (platformFile.path).toString()); //The file selected as a File object

    //Open the file for reading
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
      bytes = await FilePartioner.partitionFile(
          partitions, fileSizeBytes, fileBytes, true);

      for (int i = 0; i < bytes.length; i++) {
        File newFile = await File("$filePath$i").create();
        partitionFiles.add(await newFile.writeAsBytes(bytes[i]));
      }

      //Create list of nodes each shard can be sent to
      Map<String, Set> nodesReceivingShard =
          await BlockchainServer.getBackupNodes(
              getNodesReceivingShard(partitions), depth);

      //get the nodes that are online
      List<Node> liveNodes = getLiveKnownNodes();

      if (partitions > liveNodes.length) {
        MessageHandler.showFailureMessage(
            context, "Not enough known nodes are online");
        return false;
      }

      //send shard byte data to selected known nodes
      for (int i = 0; i < partitions; i++) {
        for (String receivingNodeAddr in nodesReceivingShard[i.toString()]) {
          _sendShard(
                  receivingNodeAddr, "$fileName-$i", depth, partitionFiles[i])
              .catchError((e, st) {
            MessageHandler.showFailureMessage(context, e.toString());
            return;
          });
        }
      }

      Map<String, List> shardHosts = {};
      nodesReceivingShard.forEach((key, value) {
        shardHosts[key] = value.toList();
      });

      Block tempBlock = await BlockChain.createUploadBlock(
          bytes,
          platformFile.extension,
          getFileName(platformFile, result),
          platformFile.size,
          shardHosts);

      //send the block to all known nodes
      BlockchainServer.sendBlocksToKnownNodes(tempBlock);
    }

    return true;
  }

  void toggleSeachVisibility() {
    searchResults.clear();

    setState(() {
      searchVisible = !searchVisible;
    });
  }

  Future downloadFileFromBlockchain(
      String fileHash, String fileName, int index) async {
    Block block = Block.fromJsonUB(
        (await BlockChain.loadBlockchain())["blocks"][fileHash]);

    String fileExtension = block.fileExtension;
    Map<String, List<dynamic>> shardHosts = block.shardHosts;
    List<String> fileHashes = block.fileHashes;

    int shardsDownloaded = 0;
    List<List<int>> fileShardData = [];

    toggleDownloadProgressVisibility(index);
    await Future.forEach(shardHosts.keys, (key) async {
      await Future.forEach(shardHosts[key], (nodeAddr) async {
        try {
          Response<dynamic> response = await Dio().post(
              "http://$nodeAddr/send_file",
              data: {"fileName": "$fileName-$key"});
          List<int> byteArray = List<int>.from(json.decode(response.data));

          //If a shard has been verified continue to the next shard, else download
          //the shard from the next node hosting the shard
          if (verifyFileShard(fileHashes, byteArray)) {
            fileShardData.add(byteArray);
            return;
          } else {
            MessageHandler.showFailureMessage(
                context, "Bad shard from ${shardHosts[key]}");
          }

          return;
        } catch (e) {
          print(e);
        }

        return;
      });
    }).whenComplete(() async {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      String savePath = prefs.getString("storage_location");
      List<int> fileByteData = FileCombiner.combineShards(fileShardData, true);
      FileHandler.saveFile(
              fileByteData, "$savePath/$fileName.$fileExtension", true)
          .whenComplete(() {
        shardsDownloaded += 1;
        MessageHandler.showSuccessMessage(context,
            "Shard $shardsDownloaded of ${shardHosts.length} downloaded");
      }).onError((error, stackTrace) {
        MessageHandler.showSuccessMessage(
            context, "An error occured downloading a shard");

        return true;
      });

      toggleDownloadProgressVisibility(index);
    });
  }

  ///Send a file ``f`` to a node at ``receipientAddr``
  Future _sendShard(
      String receipientAddr, String fileName, int depth, File f) async {
    //The node has to be live to be able to receive a shard
    if (await BlockchainServer.isNodeLive("http://$receipientAddr")) {
      try {
        //Displays a visual progress update to the user
        ProgressDialog pd = ProgressDialog(context: context);
        pd.show(max: 100, msg: "Uploading shard to $receipientAddr...");

        //The compute function can only use primitives to pass data to a function
        //Hence why a Map is used to send the argument data to the method.
        Map<String, dynamic> args = {
          "receipientAddr": receipientAddr,
          "fileName": fileName,
          "fileByteData": await f.readAsBytes(),
          "depth": depth
        };

        //Enable the network functionality to be run on a seperate Isolate
        //to minimize jank (unresponsive UI)
        compute(_sendShardToNode, args).whenComplete(() {
          pd.close();
        });

        //Display a message when the partition has been sent successfully
        MessageHandler.showSuccessMessage(
            context, "Node $receipientAddr has received a partition");
      } catch (e, stacktrace) {
        MessageHandler.showFailureMessage(context, "An error occured");
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
    print(fileName);
    print(fileHash);
    print(await BlockChain.loadBlockchain());
    Block block = blockchainData == null
        ? Block.fromJsonUB(
            (await BlockChain.loadBlockchain())["blocks"][fileHash])
        : Block.fromJsonUB(blockchainData["blocks"][fileHash]);

    if (block.fileHost != _domainRegistry.getID()) {
      throw Exception("Permission denied. File not uploaded by you");
    }

    //This is the hash of the block for the upload file about to be deleted.
    String blockFileHash = block.hash;

    Block tempBlock = BlockChain.createDeleteBlock(
        fileName, blockFileHash, block.shardByteHash, _domainRegistry.getID());

    BlockchainServer.sendBlocksToKnownNodes(tempBlock);
  }

  void addKnownNode(String ip, int port) {
    KnownNodes.addNode(ip, port).whenComplete(() {
      MessageHandler.showSuccessMessage(
          context, "Node $ip:$port has been added");
    });
  }

  void initKnownNodes() async {
    Set<String> nodesFromDB =
        await DomainRegistry.getNodesFromDatabase(Constants.maxNumOfKnownNodes);
    nodesFromDB.forEach((element) async {
      String ip = await DomainRegistry.getNodeIP(element);
      int port = await DomainRegistry.getNodePort(element);

      addKnownNode(ip, port);
    });
  }

  //Dialog methods
  Future showDownloadDetailsDialog(String fileName, double cost,
      int fileSizeBytes, int shardsCreated) async {
    bool canDownload = canActionComplete(cost);

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
                    Text("File name: ",
                        key:
                            ValueKey("${fileName}_download_descrtiption_name")),
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
    bool canUpload = canActionComplete(cost);

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

  Future showAddNodeDialog() {
    TextEditingController _textIDController = TextEditingController();
    TextEditingController _textIPController = TextEditingController();
    TextEditingController _textPortController = TextEditingController();
    String nodeErrorMsg = "";

    return showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('New node'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: !usingID
                    ? [
                        TextField(
                          key: const ValueKey("enter_ip_textfield"),
                          onChanged: (value) {},
                          keyboardType: TextInputType.number,
                          controller: _textIPController,
                          decoration: const InputDecoration(
                              hintText: "Enter IP address"),
                        ),
                        TextField(
                          key: const ValueKey("enter_port_textfield"),
                          onChanged: (value) {},
                          keyboardType: TextInputType.number,
                          controller: _textPortController,
                          decoration: const InputDecoration(
                              hintText: "Enter port number"),
                        ),
                      ]
                    : [
                        TextField(
                          key: const ValueKey("enter_id_textfield"),
                          onChanged: (value) {},
                          controller: _textIDController,
                          decoration:
                              const InputDecoration(hintText: "Enter ID"),
                        ),
                        Container(
                            child: Text(nodeErrorMsg,
                                style:
                                    TextStyle(color: Colors.red, fontSize: 12)),
                            margin: EdgeInsets.only(top: 10))
                      ],
              ),
              actions: <Widget>[
                FlatButton(
                  key: ValueKey(usingID ? "using_id_btn" : "using_port_btn"),
                  // color: Colors.green,
                  textColor: Colors.blue,
                  child: Text(
                    usingID ? 'Use IP/port' : "Use ID",
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      usingID = !usingID;
                    });
                  },
                ),
                FlatButton(
                  key: const ValueKey("add_self_btn"),
                  // color: Colors.green,
                  textColor: Colors.blue,
                  child: const Text(
                    'Add self',
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  onPressed: () async {
                    if (usingID) {
                      _textIDController.text = _domainRegistry.getID();
                    } else {
                      _textIPController.text = await NetworkInfo().getWifiIP();
                      _textPortController.text =
                          (await BlockchainServer.getPort()).toString();
                    }
                  },
                ),
                FlatButton(
                  key: const ValueKey("confirm_add_node_btn"),
                  color: Colors.green,
                  textColor: Colors.white,
                  child: const Text('OK'),
                  onPressed: () async {
                    if (!usingID) {
                      addKnownNode(_textIPController.text,
                          int.parse(_textPortController.text));
                      Navigator.pop(context);
                    } else {
                      String nodeip = await DomainRegistry.getNodeIP(
                          _textIDController.text);
                      int nodeport = await DomainRegistry.getNodePort(
                          _textIDController.text);

                      setState(() {
                        if (nodeip == null || nodeport == null) {
                          nodeErrorMsg = "The node could not be found";
                        } else {
                          nodeErrorMsg = "$nodeip:$nodeport";

                          addKnownNode(_textIPController.text,
                              int.parse(_textPortController.text));
                          Navigator.pop(context);
                        }
                      });
                    }
                  },
                ),
              ],
            );
          });
        });
  }

  Future showKnownNodesDialog() {
    return showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Known nodes'),
                content: KnownNodes.knownNodes.isEmpty
                    ? const Text("Such empty")
                    : SizedBox(
                        height: 160,
                        width: 400,
                        child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: KnownNodes.knownNodes.length,
                            itemBuilder: (context, index) {
                              Node node = KnownNodes.knownNodes.toList()[index];
                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(getNodeAddress(node.ip, node.port),
                                      key: ValueKey("known_node_$index")),
                                  TextButton(
                                      onPressed: () {
                                        print(KnownNodes.knownNodes);
                                        setState(() {
                                          KnownNodes.knownNodes
                                              .removeWhere((n) {
                                            return node.addr ==
                                                getNodeAddress(n.ip, n.port);
                                          });
                                        });
                                        print(KnownNodes.knownNodes);
                                      },
                                      child: Text("Remove"))
                                ],
                              );
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
            },
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
                key: const ValueKey("blockchain_text"),
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

    //convert file hosts IP/ports to ID
    Map fileHosts = fileData["shardHosts"];
    Map<String, List> formattedFileHosts = {};
    fileHosts.forEach((key, value) {
      List hosts = value;
      for (String addr in hosts) {
        if (formattedFileHosts[key] == null) {
          formattedFileHosts[key] = [];
        }
        formattedFileHosts[key].add(DomainRegistry.generateNodeID(addr));
      }
    });

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
                      fileData["hash"],
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
                        child: SelectableText(formattedFileHosts.toString(),
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

  ///

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
        key: const ValueKey("available_files_list"),
        physics: const BouncingScrollPhysics(),
        shrinkWrap: true,
        itemCount: fileHashes.length,
        itemBuilder: (context, index) {
          Map<String, dynamic> block =
              fileHashes[fileHashes.keys.elementAt(index)];
          String fileName = block["fileName"];
          String fileHash = block["hash"];
          int fileSizeBytes = block['fileSizeBytes'];
          int numberOfShards = block['shardsCreated'];
          bool canFileBeDeleted = block['fileHost'] == _domainRegistry.getID();

          return InkWell(
            key: Key("file_$index"),
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
                              key: ValueKey("delete_file_$index"),
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

  void refreshBlockchainAndState() {
    setState(() {
      _refreshBlockchain();
    });
  }

  void _refreshBlockchain() async {
    List<String> deletedFileHashes;
    Map<String, dynamic> blockchain;

    if (blockchainData != null) {
      deletedFileHashes = await getDeletedFiles(blockchainData: blockchainData);
      blockchain = blockchainData;
    } else {
      deletedFileHashes = await getDeletedFiles();
      blockchain = await BlockChain.loadBlockchain();
    }

    fileHashes.clear();

    blockchain["blocks"].forEach((fileHash, key) {
      String fileName = blockchain["blocks"][fileHash]["fileName"];
      if (fileName != "genesis" &&
          key["event"] != Block.deleteEvent &&
          !deletedFileHashes.contains(key["hash"])) {
        trie.insert(fileName);

        fileHashes[fileHash] = blockchain["blocks"][fileHash];
      }
    });
  }

  Future<List<String>> getDeletedFiles(
      {Map<String, dynamic> blockchainData}) async {
    List<String> filesDeleted = [];
    BlockChain.loadBlockchain().whenComplete(() {
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
    initKnownNodes();
    BlockchainServer.startServer(context, this);

    _domainRegistry = DomainRegistry(ip, port);

    requestStorageLocationDialog();
    _domainRegistry.generateAndSaveID(context);
    UserSession.saveNewUser();
    _refreshBlockchain();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        createTopNavBarButton(
                            "SEARCH", Icons.search, toggleSeachVisibility,
                            key: const ValueKey("Search button")),
                        createTopNavBarButton("UPLOAD", Icons.upload_file,
                            () async {
                          uploadFile();
                        }, key: const ValueKey("upload_node_btn")),
                        createTopNavBarButton("ADD NODE", Icons.person_add,
                            () async {
                          List result = await showAddNodeDialog();
                          String ip = result[0];
                          int port = int.parse(result[1]);

                          KnownNodes.addNode(ip, port).whenComplete(() {
                            MessageHandler.showSuccessMessage(
                                context, "Node $ip:$port has been added");
                          });
                        }, key: const ValueKey("add_node_btn")),
                        createTopNavBarButton("VIEW KNOWN NODES", Icons.person,
                            () {
                          showKnownNodesDialog();
                        }, key: const ValueKey("view_known_nodes_btn")),
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
                                          key: const ValueKey("Search field"),
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
                blockchainData == null
                    ? FutureBuilder(
                        future: BlockChain.loadBlockchain(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            Map<String, dynamic> data = snapshot.data;

                            return displayBlockchainFiles(data);
                          } else {
                            return const CircularProgressIndicator();
                          }
                        })
                    : displayBlockchainFiles(blockchainData),
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
                          key: const ValueKey("user_id"),
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
                              }
                              if (snapshot.hasError) {
                                return Text(
                                    "An error occured while generating your ID. Please try again later",
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.red[700]));
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

                              refreshBlockchainAndState();
                            }),
                          ),
                          Container(
                            color: Colors.white,
                            margin:
                                const EdgeInsets.only(bottom: 10, right: 10),
                            child: createTopNavBarButton(
                                "VIEW BLOCKCHAIN", Icons.list, () async {
                              Map<String, dynamic> blockchain = await BlockChain.loadBlockchain();

                              printBlockchainDialog(blockchain);
                            }, key: const ValueKey("view_blockchain_btn")),
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
