import 'dart:convert';

import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:intl/intl.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:network_info_plus/network_info_plus.dart';
// import 'package:shelf_multipart/form_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sn_progress_dialog/progress_dialog.dart';
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:testwindowsapp/message_handler.dart';
import 'package:window_size/window_size.dart';
import 'package:retrieval/trie.dart';

const String lastLoginTimeKey = "last_login_time";
const String storageLocationKey = "storage_location";

void logLoginTime() async {
  DateTime time = DateTime.now();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  print(time.millisecondsSinceEpoch);
  prefs.setInt(lastLoginTimeKey, time.millisecondsSinceEpoch);
}

void getLastLoginTime() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  print(prefs.getInt(lastLoginTimeKey));
  print(prefs.getString(storageLocationKey));
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
  runApp(const MyApp());
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
          textTheme: GoogleFonts.jetBrainsMonoTextTheme()),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePageState state = MyHomePageState();
  MyHomePage({Key key}) : super(key: key);

  @override
  State<MyHomePage> createState() => state;
}

class MyHomePageState extends State<MyHomePage> {
  GlobalKey<FormState> searchKey = GlobalKey();
  bool searchVisible = false;
  bool autoCompleteVisible = false;
  bool searchMode = false;
  Map<String, dynamic> fileNames = {};
  List<String> searchResults = [];
  List<String> knownNodes = [];
  final trie = Trie();

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

  void partitionFile() async {
    // print(await BlockchainServer.isNodeLive("http://localhost:44876"));

    if (knownNodes.isEmpty) {
      MessageHandler.showFailureMessage(context, "You have no known nodes");
      return;
    }

    FilePickerResult result = await FilePicker.platform.pickFiles();

    PlatformFile platformFile = result.files.single;

    File file = File((platformFile.path).toString());

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

    final readFile = await File(file.path).open();

    int chunkSize = (await readFile.length()) ~/ partitions;

    int last_i = 0;
    List<List<int>> bytes = [];
    List<File> partitionFiles = [];
    for (int i = 0; i < partitions; i++) {
      print(last_i);
      List<int> encodedFile;
      if (i == partitions - 1) {
        encodedFile = GZipCodec().encode(
            (Uint8List.fromList(await File(file.path).readAsBytes()))
                .getRange(last_i, await readFile.length())
                .toList());
      } else {
        encodedFile = GZipCodec().encode(
            (Uint8List.fromList(await File(file.path).readAsBytes()))
                .getRange(last_i, last_i + chunkSize)
                .toList());
      }
      File newFile = await File("$filePath$i").create();
      await newFile.writeAsBytes(encodedFile);
      last_i += chunkSize;
      bytes.add(encodedFile);
      partitionFiles.add(newFile);
    }

    bool errorOccured = false;
    for (int i = 0; i < knownNodes.length; i++) {
      String receivingNodeAddr = knownNodes[i];
      sendFile(receivingNodeAddr, fileName, f: partitionFiles[i])
          .catchError((e, st) {
        errorOccured = true;
        MessageHandler.showFailureMessage(context, e.toString());
        return;
      });
    }

    if (!errorOccured) {
      setState(() {
        BlockChain.createNewBlock(bytes, platformFile, result, knownNodes);
        Map<String, dynamic> blockchain = getBlockchain();
        blockchain["blocks"].forEach((key, value) {
          trie.insert(key);

          fileNames[key] = blockchain["blocks"][key];
        });

        MessageHandler.showToast(context, "Partition success");
      });
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

  void downloadFileFromBlockchain(String fileName) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String savePath = prefs.getString("storage_location");

    Map<String, dynamic> blocks = getBlockchain()["blocks"];

    List<int> fileBytes = [];
    String fileExtension = blocks[fileName]["fileExtension"];
    Map<String, dynamic> shardHosts = blocks[fileName]["shardHosts"];
    var formData = FormData.fromMap({
      "ip": await NetworkInfo().getWifiIP(),
      "fileName": fileName,
      "fileExtension": fileExtension,
    });

    shardHosts.forEach((key, value) {
      Dio().post("http://$value/download", data: formData);
    });

    MessageHandler.showSuccessMessage(
        context, "File now available at: $savePath");
  }

  void requestStorageLocationDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (prefs.getString(storageLocationKey) == null) {
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

  Future sendFile(String receipientAddr, String fileName, {File f}) async {
    if (await BlockchainServer.isNodeLive("http://$receipientAddr")) {
      File file = f;

      if (file == null) {
        PlatformFile _platformFile = await _getPlatformFile();
        file = File(_platformFile.path);
      }

      try {
        var formData = FormData.fromMap({
          "fileName": fileName,
          "file": MultipartFile.fromBytes(
              utf8.encode((await file.readAsBytes()).toString()))
        });

        ProgressDialog pd = ProgressDialog(context: context);
        pd.show(max: 100, msg: 'File uploading...');

        await Dio().post(
          "http://$receipientAddr/upload",
          data: formData,
          onSendProgress: (count, total) {
            print((count / total) * 100);
            pd.update(value: ((count / total) * 100).toInt());
          },
        );
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

  Map<String, dynamic> getBlockchain() {
    return BlockChain.toJson();
  }

  String _convertTimestampToDate(int value) {
    var date = DateTime.fromMillisecondsSinceEpoch(value);
    var d12 = DateFormat('MM-dd-yyyy, hh:mm a').format(date);
    return d12;
  }

  Widget displayBlockchainFiles() {
    return ListView.builder(
        shrinkWrap: true,
        itemCount: fileNames.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () {
              downloadFileFromBlockchain(fileNames.keys.elementAt(index));
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    margin: const EdgeInsets.only(left: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileNames.keys.elementAt(index),
                          style: const TextStyle(fontSize: 15),
                        ),
                        Text(
                          "Uploaded: ${_convertTimestampToDate(fileNames[fileNames.keys.elementAt(index)]["timeCreated"])}",
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    )),
                // Expanded(
                //   child: Container(
                //     margin: const EdgeInsets.only(right: 20),
                //     alignment: Alignment.centerRight,
                //     // color: Colors.red,
                //     child: IconButton(
                //       splashRadius: 10,
                //       icon: const Icon(
                //         Icons.download,
                //         size: 12,
                //       ),
                //       onPressed: () {},
                //     ),
                //   ),
                // )
              ],
            ),
          );
        });
  }

  void addNode({String addr}) async {
    String address = addr;

    if (address == null) {
      try {
        List result = await showAddNodeDialog();
        String ipAddress = result[0];
        String portNumber = result[1];
        address = "$ipAddress:$portNumber";
        await Dio().get("http://$address/add_node",
            queryParameters: {"addr": address});
      } catch (e, stacktrace) {
        MessageHandler.showFailureMessage(context, e.toString());
      }
    }

    knownNodes.add(address);
    MessageHandler.showSuccessMessage(context, "$address is now a known node");
  }

  @override
  void initState() {
    super.initState();
    BlockchainServer(context).startServer();
    requestStorageLocationDialog();
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> blockchain = getBlockchain();
    fileNames.clear();

    blockchain["blocks"].forEach((key, value) {
      trie.insert(key);

      fileNames[key] = blockchain["blocks"][key];
    });

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
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
                    partitionFile();
                  }),
                  // createTopNavBarButton("COMBINE", Icons.view_in_ar, () {
                  //   combine();
                  // }),
                  // createTopNavBarButton("SEND FILE", Icons.send, () {
                  //   sendFile();
                  // }),
                  createTopNavBarButton("ADD NODE", Icons.person_add, () {
                    addNode();
                  }),
                  // SelectableText("ip: ${BlockchainServer.ip}"),
                  SelectableText("port: ${BlockchainServer.port.toString()}"),
                  Expanded(
                    child: Container(),
                  ),
                  // Align(
                  //   alignment: Alignment.centerRight,
                  //   child: createTopNavBarButton(
                  //       "DOWNLOAD PROGRESS", Icons.download, () {}),
                  // )
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
                                  fontSize: 12, fontWeight: FontWeight.bold),
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
                                onTap: () {},
                                child: Row(
                                  children: [
                                    Container(
                                        padding: const EdgeInsets.only(
                                            top: 10, bottom: 10, left: 20),
                                        child: Text(searchResults[index])),
                                    Expanded(child: Container()),
                                    Container(
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        child: const Text("click to download",
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.green)))
                                  ],
                                ),
                              );
                            }),
                        Container(
                            alignment: Alignment.centerLeft,
                            margin: EdgeInsets.only(left: 20, bottom: 5),
                            child: Text("Search results",
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
            fileNames.isNotEmpty
                ? displayBlockchainFiles()
                : Expanded(
                    child: Container(child: Center(child: Text("No files"))))
          ],
        ),
      ),
    );
  }
}
