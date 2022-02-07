import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:filesize/filesize.dart';
import 'package:easy_isolate/easy_isolate.dart' as ei;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
// import 'package:shelf_multipart/form_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sn_progress_dialog/progress_dialog.dart';
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:testwindowsapp/domain_regisrty.dart';
import 'package:testwindowsapp/message_handler.dart';
import 'package:testwindowsapp/token.dart';
import 'package:testwindowsapp/token_view.dart';
import 'package:window_size/window_size.dart';
import 'package:retrieval/trie.dart';

const String lastLoginTimeKey = "last_login_time";
const String storageLocationKey = "storage_location";
final downloadWorker = ei.Worker();
final serverWorker = ei.Worker();

void logLoginTime() async {
  DateTime time = DateTime.now();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  prefs.setInt(lastLoginTimeKey, time.millisecondsSinceEpoch);
}

void getLastLoginTime() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
}

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setWindowMinSize(const Size(800, 700));
    setWindowMaxSize(const Size(800, 700));
  }
  getLastLoginTime();
  logLoginTime();
  downloadWorker.init(mainMessageHandler, isolateMessageHandler);

  runApp(const MyApp());
}

/// Handle the messages coming from the isolate
void mainMessageHandler(dynamic data, SendPort isolateSendPort) {}

/// Handle the messages coming from the main
isolateMessageHandler(
    dynamic data, SendPort mainSendPort, ei.SendErrorFunction sendError) async {
  if (data is Map) {
    final args = data;

    downloadFileFromNode(args);
  }
}

List<int> _partitionFile(Map<String, dynamic> args) {
  int byteLastLocation = args["byteLastLocation"];
  File file = args["file"];
  int fileSizeBytes = args["fileSizeBytes"];
  int currentPartition = args["i"];
  int partitions = args["partitions"];
  int chunkSize = args["chunkSize"];
  List<int> fileBytes = args["fileBytes"];

  List<int> encodedFile;
  if (currentPartition == partitions - 1) {
    encodedFile = GZipCodec().encode((Uint8List.fromList(fileBytes))
        .getRange(byteLastLocation, fileSizeBytes)
        .toList());
  } else {
    encodedFile = GZipCodec().encode((Uint8List.fromList(fileBytes))
        .getRange(byteLastLocation, byteLastLocation + chunkSize)
        .toList());
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
    "http://$nodeAddr/upload",
    data: formData,
  );
}

Future downloadFileFromNode(Map<String, dynamic> args) async {
  FormData formData = FormData.fromMap(args["form"]);
  Map<String, dynamic> shardHosts = args["shardHosts"];

  shardHosts.forEach((key, addr) async {
    Response response =
        await Dio().post("http://$addr/download", data: formData);
    if (response.data == "done") {
      print("good");
    }
  });

  print("done");
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
  Map<String, dynamic> fileNames = {};
  List<int> filesDownloading = [];
  List<String> searchResults = [];
  List<String> knownNodes = [];
  BlockchainServer server;
  final trie = Trie();
  Token _token = Token();

  Future<bool> isUserNew() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool("is_user_new") == null;
  }

  Future saveNewUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool("is_user_new", true);
  }

  Widget createTopNavBarButton(String text, IconData btnIcon, Function action) {
    return TextButton(
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

  Future<bool> uploadFile() async {
    if (knownNodes.isEmpty) {
      MessageHandler.showFailureMessage(context, "You have no known nodes");
      return false;
    }

    FilePickerResult result = await FilePicker.platform.pickFiles();
    PlatformFile platformFile = result.files.single;
    File file = File((platformFile.path).toString());
    int depth = 2;

    final readFile = await File(file.path).open();
    int fileSizeBytes = await readFile.length();

    int partitions = knownNodes.length;

    String fileExtension = platformFile.extension;
    String fileName = platformFile.name
        .substring(0, platformFile.name.length - (fileExtension.length + 1));
    String filePath = (platformFile.path).toString().substring(
        0,
        (platformFile.path).toString().length -
            result.files.single.name.length);
    String filePathWithoutFileName =
        filePath.substring(0, filePath.length - platformFile.name.length);
    String myIP = await NetworkInfo().getWifiIP();

    List<List<int>> bytes = [];
    List<File> partitionFiles = [];
    int chunkSize = fileSizeBytes ~/ partitions;

    bool canUpload = await showUploadDetailsDialog(fileName,
        Token.calculateFileCost(fileSizeBytes), fileSizeBytes, partitions);

    if (canUpload) {
      ProgressDialog pd = ProgressDialog(context: context);

      int byteLastLocation = 0;
      for (int i = 0; i < partitions; i++) {
        pd.show(
            max: 100,
            msg: 'Creating shard $i of $partitions...',
            barrierColor: Colors.grey);

        List<int> fileBytes = await File(file.path).readAsBytes();
        Map<String, dynamic> args = {
          "byteLastLocation": byteLastLocation,
          "file": file,
          "fileSizeBytes": fileSizeBytes,
          "i": i,
          "partitions": partitions,
          "chunkSize": chunkSize,
          "fileBytes": fileBytes
        };
        List<int> encodedFile = await compute(_partitionFile, args);
        byteLastLocation += chunkSize;
        File newFile = await File("$filePath$i").create();
        await newFile.writeAsBytes(encodedFile);
        partitionFiles.add(newFile);

        bytes.add(encodedFile);
      }

      pd.close();

      for (int i = 0; i < knownNodes.length; i++) {
        String receivingNodeAddr = knownNodes[i];
        sendShard(receivingNodeAddr, fileName, depth, f: partitionFiles[i])
            .catchError((e, st) {
          MessageHandler.showFailureMessage(context, e.toString());
          return;
        });
      }

      Block tempBlock = await BlockChain.createNewBlock(
          bytes, platformFile, result, knownNodes);

      _sendBlocksToKnownNodes(myIP, tempBlock);
    }

    return true;
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

  Future showServerStartError(String ip, int port) async {
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
                SizedBox(
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

  void _sendBlocksToKnownNodes(String myIP, Block tempBlock) async {
    Set<String> nodesReceivingShard = {};
    int myPort = await BlockchainServer.getPort();

    nodesReceivingShard.add("$myIP:$myPort");

    for (int i = 0; i < knownNodes.length; i++) {
      nodesReceivingShard.add(knownNodes[i]);
    }

    for (var addr in nodesReceivingShard) {
      BlockChain.sendBlockchain(addr, tempBlock);
    }
  }

  void combine() async {
    int parts = knownNodes.length;
    String selectedDirectory = await FilePicker.platform.getDirectoryPath();

    String fileAddress = await selectSavePath(context);

    File createdFile = File(fileAddress);
    List<int> shardData = [];
    for (int i = 0; i < parts; i++) {
      for (var shardByteData in (GZipCodec()
          .decode(await File("$selectedDirectory/$i").readAsBytes()))) {
        shardData.add(shardByteData);
      }
    }
    createdFile.writeAsBytes(shardData, mode: FileMode.writeOnlyAppend);

    MessageHandler.showToast(context, "Combine success");
  }

  void toggleSeachVisibility() {
    searchResults.clear();

    setState(() {
      searchVisible = !searchVisible;
      searchMode = !searchMode;
    });
  }

  void searchKeyword(String keyword) {
    searchResults.clear();
    setState(() {
      searchResults.addAll(trie.find(keyword));
    });
  }

  void downloadFileFromBlockchain(String fileName, int index) async {
    int backupDepth = 2;
    Map<String, dynamic> blocks = (await getBlockchain())["blocks"];

    String fileExtension = blocks[fileName]["fileExtension"];
    Map<String, dynamic> shardHosts = blocks[fileName]["shardHosts"];

    Map<String, dynamic> args = {
      "shardHosts": shardHosts,
      "form": {
        "ip": await NetworkInfo().getWifiIP(),
        "port": await BlockchainServer.getPort(),
        "fileName": fileName,
        "fileExtension": fileExtension,
        "index": index,
      }
    };

    downloadFileFromNode(args);
  }

  void requestStorageLocationDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (await isUserNew()) {
      String path = await FilePicker.platform.getDirectoryPath();

      if (path == null) {
        MessageHandler.showFailureMessage(
            context, "Storage location is required");
        requestStorageLocationDialog();
        return;
      }

      prefs.setString(storageLocationKey, path);
    }
  }

  Future<PlatformFile> _getPlatformFile() async {
    FilePickerResult result = await FilePicker.platform.pickFiles();

    if (result != null) {
      PlatformFile fileData = result.files.single;
      return fileData;
    } else {
      return null;
    }
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
        pd.show(
            max: 100,
            msg: "Uploading shard to $receipientAddr...",
            barrierColor: Colors.grey);
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

  Future<Map<String, dynamic>> getBlockchain() async {
    return BlockChain.loadBlockchain();
  }

  String _convertTimestampToDate(int value) {
    var date = DateTime.fromMillisecondsSinceEpoch(value);
    var d12 = DateFormat('EEE, MM-dd-yyyy, hh:mm:ss a').format(date);
    return d12;
  }

  Widget displayBlockchainFiles(Map<String, dynamic> blockchain) {
    fileNames.clear();

    blockchain["blocks"].forEach((fileName, value) {
      if (fileName != "genesis") {
        trie.insert(fileName);

        fileNames[fileName] = blockchain["blocks"][fileName];
      }
    });

    if (fileNames.isEmpty) {
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
        shrinkWrap: true,
        itemCount: fileNames.length,
        itemBuilder: (context, index) {
          String fileName = fileNames.keys.elementAt(index);
          int fileSizeBytes =
              fileNames[fileNames.keys.elementAt(index)]['fileSizeBytes'];
          int numberOfShards =
              fileNames[fileNames.keys.elementAt(index)]['shardsCreated'];

          return InkWell(
            onTap: () async {
              bool canDownload = await showDownloadDetailsDialog(
                  fileName,
                  Token.calculateFileCost(fileSizeBytes),
                  fileSizeBytes,
                  numberOfShards);

              if (canDownload) {
                setState(() {
                  filesDownloading.add(index);
                });
                downloadFileFromBlockchain(
                    fileNames.keys.elementAt(index), index);
              }
            },
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(top: 10, bottom: 10),
                        margin: const EdgeInsets.only(left: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                fileNames.keys.elementAt(index),
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
                                        fileNames[fileNames.keys
                                            .elementAt(index)]['fileHost']);
                                  },
                                  child: Text(
                                    fileNames[fileNames.keys.elementAt(index)]
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
                                  margin: EdgeInsets.only(right: 2),
                                  child: Icon(Icons.access_time_rounded,
                                      color: Colors.grey, size: 12),
                                ),
                                Container(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    "Uploaded: ${_convertTimestampToDate(fileNames[fileNames.keys.elementAt(index)]["timeCreated"])}",
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                                Container(
                                  margin: EdgeInsets.only(left: 10, right: 1),
                                  child: Icon(Icons.sd_card_outlined,
                                      color: Colors.grey, size: 12),
                                ),
                                Container(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    filesize(fileNames[fileNames.keys
                                        .elementAt(index)]["fileSizeBytes"]),
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 20),
                        alignment: Alignment.centerRight,
                        // color: Colors.red,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              splashRadius: 10,
                              icon: const Icon(
                                Icons.description,
                                size: 12,
                              ),
                              onPressed: () {
                                String fileName =
                                    fileNames.keys.elementAt(index);
                                String fileUploader =
                                    fileNames[fileNames.keys.elementAt(index)]
                                        ['fileHost'];
                                showFileInfoDialog(fileName, fileUploader);
                              },
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
                Visibility(
                    visible: filesDownloading.contains(index),
                    child: LinearProgressIndicator())
              ],
            ),
          );
        });
  }

  void showFileInfoDialog(String fileName, String uploader) async {
    Map<String, dynamic> fileData = fileNames[fileName];
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'File details',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text(fileData.toString()),
                Row(
                  children: [
                    const Text("Block hash: "),
                    Flexible(
                        child: SelectableText(
                      fileData["merkleRootHash"],
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ))
                  ],
                ),
                Row(
                  children: [
                    Text("Previous block hash: ",
                        style: TextStyle(color: Colors.grey[800])),
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
                    SelectableText(
                        _convertTimestampToDate(fileData["timeCreated"]),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("File name: "),
                    SelectableText(fileData["fileName"],
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("File extension: "),
                    SelectableText(fileData["fileExtension"],
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("File size, in bytes: "),
                    SelectableText(fileData["fileSizeBytes"].toString(),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("Shards created: "),
                    SelectableText(fileData["shardsCreated"].toString(),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("Event cost: "),
                    SelectableText(
                        "${fileData["eventCost"].toString()} token(s)",
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                  ],
                ),
                Row(
                  children: [
                    const Text("Shard hosts: "),
                    SelectableText(fileData["shardHosts"].toString(),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]))
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

  void refreshBlockchain() async {
    Map<String, dynamic> blockchain = await getBlockchain();
    fileNames.clear();
    setState(() {
      blockchain["blocks"].forEach((fileName, value) {
        if (fileName != "genesis") {
          trie.insert(fileName);

          fileNames[fileName] = blockchain["blocks"][fileName];
        }
      });
    });
  }

  List<String> getKnownNodes() {
    return knownNodes;
  }

  void addNode({String addr}) async {
    String address = addr;

    if (address == null) {
      try {
        List result = await showAddNodeDialog();

        if (result.isEmpty) {
          throw Exception();
        }

        String ipAddress = result[0];
        String portNumber = result[1];

        String myIP = await NetworkInfo().getWifiIP();
        int myPort = await BlockchainServer.getPort();

        address = "$ipAddress:$portNumber";
        await Dio().post("http://$address/add_node",
            data: FormData.fromMap({
              "sendingNodeAddr": "$myIP:$myPort",
              "addr": address,
            }));
        knownNodes.add(address);
        MessageHandler.showSuccessMessage(
            context, "$address is now a known node");
      } catch (e, stacktrace) {
        MessageHandler.showFailureMessage(context, "An error occured");
        debugPrint(stacktrace.toString());
      }
    } else {
      knownNodes.add(address);
      MessageHandler.showSuccessMessage(
          context, "$address is now a known node");
    }
  }

  @override
  void initState() {
    super.initState();

    BlockchainServer.startServer(context, this);

    requestStorageLocationDialog();
    DomainRegistry.generateID();
    saveNewUser();
  }

  @override
  Widget build(BuildContext context) {
    getBlockchain().then((blockchain) {
      fileNames.clear();

      blockchain["blocks"].forEach((fileName, value) {
        if (fileName != "genesis") {
          trie.insert(fileName);

          fileNames[fileName] = blockchain["blocks"][fileName];
        }
      });
    });
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: 50,
                  width: double.maxFinite,
                  child: Center(
                      child: Row(
                    children: [
                      createTopNavBarButton(
                          "SEARCH", Icons.search, toggleSeachVisibility),
                      createTopNavBarButton("UPLOAD", Icons.upload_file, () {
                        uploadFile();
                      }),
                      createTopNavBarButton("ADD NODE", Icons.person_add, () {
                        addNode();
                      }),
                      FutureBuilder(
                          future: BlockchainServer.getPort(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              int port = snapshot.data;
                              return SelectableText("port: ${port.toString()}");
                            } else {
                              return CircularProgressIndicator();
                            }
                          }),
                      Expanded(
                        child: Container(),
                      ),
                      Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                              margin: EdgeInsets.only(right: 10),
                              child: AvailableTokensView(_token)))
                    ],
                  )),
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
                                              searchKeyword(value);
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
                                  return InkWell(
                                    onTap: () {
                                      downloadFileFromBlockchain(
                                          searchResults[index], 0);
                                    },
                                    child: Row(
                                      children: [
                                        Container(
                                            padding: const EdgeInsets.only(
                                                top: 10, bottom: 10, left: 20),
                                            child: Text(searchResults[index])),
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
                  ],
                ),
                FutureBuilder(
                    future: getBlockchain(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        Map<String, dynamic> data = snapshot.data;

                        return displayBlockchainFiles(data);
                      } else {
                        return CircularProgressIndicator();
                      }
                    })
              ],
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
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
                              "User ID: ${DomainRegistry.id}",
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
                  Container(
                    margin: const EdgeInsets.only(bottom: 10, right: 10),
                    child: createTopNavBarButton(
                        "CLEAR BLOCKCHAIN", Icons.clear_all, () {
                      BlockChain.clearBlockchain();

                      refreshBlockchain();
                    }),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
