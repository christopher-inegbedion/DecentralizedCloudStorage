import 'dart:convert';

import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// import 'package:shelf_multipart/form_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testwindowsapp/blockchain.dart';
import 'package:testwindowsapp/blockchain_server.dart';
import 'package:testwindowsapp/message_handler.dart';
import 'package:window_size/window_size.dart';
import 'package:retrieval/trie.dart';

void logLoginTime() async {
  DateTime time = DateTime.now();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  print(time.millisecondsSinceEpoch);
  prefs.setInt("last_login_time", time.millisecondsSinceEpoch);
}

void getLastLoginTime() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  print(prefs.getInt("last_login_time"));
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
    // setWindowMaxSize(size)
    // setWindowMaxSize(Size.infinite);
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
      title: 'Shr: Cloud sharing platform',
      theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: GoogleFonts.jetBrainsMonoTextTheme()),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  GlobalKey<FormState> searchKey = GlobalKey();
  bool searchVisible = false;
  bool autoCompleteVisible = false;
  bool searchMode = false;
  List<String> fileNames = [];
  List<String> searchResults = [];
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

  void partitionFile(PlatformFile file, FilePickerResult result) async {
    int partitions = 10;

    String fileExtension = file.extension;
    String fileName =
        file.name.substring(0, file.name.length - fileExtension.length);
    String filePath = (file.path).toString().substring(
        0, (file.path).toString().length - result.files.single.name.length);
    String filePathWithoutFileName =
        filePath.substring(0, filePath.length - file.name.length);

    final readFile = await File(file.path).open();

    int chunkSize = (await readFile.length()) ~/ partitions;

    int last_i = 0;
    List<List<int>> bytes = [];
    for (int i = 0; i < partitions; i++) {
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
    }
    BlockChain.createNewBlock(bytes, file, result, partitions);
    setState(() {});

    MessageHandler.showToast(context, "Partition success");
  }

  void combine() async {
    int parts = 10;
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

  void downloadFile(String fileName) async {
    Map<String, dynamic> blockData = getBlockchain()["blocks"][fileName];
    var formData = FormData.fromMap({"ip": "BlockchainServer(context).ip"});

    print("http://${blockData['shardHosts']["0"]}/download");
    await Dio().post("http://${blockData['shardHosts']["0"]}/download",
        data: formData);
  }

  Future<void> _showMyDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('AlertDialog Title'),
          content: SingleChildScrollView(
            child: ListBody(
              children: const <Widget>[
                Text('This is a demo alert dialog.'),
                Text('Would you like to approve of this message?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Approve'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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

  Map<String, String> _getFileDetails(PlatformFile file) {
    String fileExtension = file.extension;
    String fileName =
        file.name.substring(0, file.name.length - fileExtension.length);
    String filePath = file.path;
    String filePathWithoutFileName =
        filePath.substring(0, filePath.length - file.name.length);
    String filePathWithExtension = file.name;

    return {
      "fileExtension": fileExtension,
      "fileName": fileName,
      "filePath": filePath,
      "filePathWithoutFileName": filePathWithoutFileName,
      "filPathWithExtension": filePathWithExtension
    };
  }

  Future<File> selectFile() async {
    PlatformFile fileData = await _getPlatformFile();
    return File((fileData.path).toString());
  }

  void sendFile() async {
    PlatformFile _platformFile = await _getPlatformFile();
    String fileExtension = _platformFile.extension;
    String fileName = _platformFile.name
        .substring(0, _platformFile.name.length - fileExtension.length);

    String portNum = await showDialogInput();

    try {
      var formData = FormData.fromMap({
        "file": MultipartFile.fromBytes(utf8
            .encode((await File(_platformFile.path).readAsBytes()).toString()))
      });

      await Dio().post("http://localhost:$portNum/upload", data: formData);
    } catch (e, stacktrace) {
      MessageHandler.showFailureMessage(context, e.toString());
      print(e);
    }
  }

  Future<String> showDialogInput() {
    TextEditingController _textEditingController = TextEditingController();

    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Port number'),
            content: TextField(
              onChanged: (value) {},
              keyboardType: TextInputType.number,
              controller: _textEditingController,
              decoration: const InputDecoration(hintText: "Enter port number"),
            ),
            actions: <Widget>[
              FlatButton(
                color: Colors.green,
                textColor: Colors.white,
                child: const Text('OK'),
                onPressed: () {
                  Navigator.pop(context, _textEditingController.text);
                },
              ),
            ],
          );
        });
  }

  Map<String, dynamic> getBlockchain() {
    return BlockChain.toJson();
  }

  Widget displayBlockchainFiles() {
    return ListView.builder(
        shrinkWrap: true,
        itemCount: fileNames.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () {},
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(left: 20),
                    child: Text(
                      fileNames[index],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    )),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 20),
                    alignment: Alignment.centerRight,
                    // color: Colors.red,
                    child: IconButton(
                      splashRadius: 10,
                      icon: const Icon(
                        Icons.download,
                        size: 12,
                      ),
                      onPressed: () {},
                    ),
                  ),
                )
              ],
            ),
          );
        });
  }

  @override
  void initState() {
    super.initState();
    BlockchainServer(context).startServer();
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> blockchain = getBlockchain();
    fileNames.clear();

    blockchain["blocks"].forEach((key, value) {
      trie.insert(key);

      fileNames.add(key);
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
                  createTopNavBarButton(
                      "PARTITION", Icons.dashboard_customize_outlined,
                      () async {
                    FilePickerResult result =
                        await FilePicker.platform.pickFiles();

                    if (result != null) {
                      PlatformFile fileData = result.files.single;

                      File file = File((fileData.path).toString());
                      partitionFile(fileData, result);
                    } else {
                      // User canceled the picker
                    }
                  }),
                  createTopNavBarButton("COMBINE", Icons.view_in_ar, () {
                    combine();
                  }),
                  createTopNavBarButton("SEND FILE", Icons.send, () {
                    sendFile();
                  }),
                  SelectableText(
                      "port number: ${BlockchainServer.port.toString()}"),
                  Expanded(
                    child: Container(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: createTopNavBarButton(
                        "DOWNLOAD PROGRESS", Icons.download, () {}),
                  )
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
                                onTap: () {
                                  downloadFile(searchResults[index]);
                                },
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
