import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Model/item_device_model.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/item_list_tile.dart';
import 'package:smart_home_app/Core/Services/storage_item.dart';
import 'package:smart_home_app/Core/config/app_theme.dart';
import 'package:smart_home_app/Core/config/localization.dart';
import 'package:smart_home_app/Features/Home/presentation/tab_screen.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class LiveRoom extends StatefulWidget {
  @override
  _LiveRoomState createState() => _LiveRoomState();
}

class _LiveRoomState extends State<LiveRoom> {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  List<int> receivedBytesBuffer = [];
  List<String> receivedMessages = [];
  String deviceId = '';
  final SharedPreferencesService _prefsService = SharedPreferencesService();
  final TextEditingController _textController = TextEditingController();
  List<ItemDeviceModel> _items = [];
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _checkAndConnectToDevice();

    _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .listen((event) {
          receivedBytesBuffer.addAll(event);
          int endIndex = -1;
          for (int i = 0; i < receivedBytesBuffer.length; i++) {
            if (receivedBytesBuffer[i] == 0x46) {
              int startIndex = -1;
              for (int j = i - 1; j >= 0; j--) {
                if (receivedBytesBuffer[j] == 0x23) {
                  startIndex = j;
                  endIndex = i;
                  break;
                }
              }
              if (startIndex != -1) break;
            }
          }

          if (endIndex != -1) {
            List<int> completeMessageBytes = receivedBytesBuffer.sublist(
              0,
              endIndex + 1,
            );
            String message;
            try {
              message = utf8.decode(completeMessageBytes);
            } catch (e) {
              message = "Error decoding: $e";
            }
            receivedBytesBuffer.removeRange(0, endIndex + 1);
            message = message.trim();

            setState(() {
              receivedMessages.add(message);
              _processReceivedMessage(message);
            });
            debugPrint("Received From Native: $message");
          }
        });

    _flutterSerialCommunicationPlugin
        .getDeviceConnectionListener()
        .receiveBroadcastStream()
        .listen((event) {
          Provider.of<ConnectionProvider>(
            context,
            listen: false,
          ).setConnectionStatus(event);
        });

    _loadItems();
  }

  Future<void> _checkAndConnectToDevice() async {
    List<DeviceInfo> devices =
        await _flutterSerialCommunicationPlugin.getAvailableDevices();
    if (devices.isNotEmpty) {
      bool isConnectionSuccess = await _flutterSerialCommunicationPlugin
          .connect(devices.first, 115200);
      if (isConnectionSuccess) {
        Provider.of<ConnectionProvider>(
          context,
          listen: false,
        ).setConnectionStatus(true);
      }
    }
  }

  void _processReceivedMessage(String message) {
    if (message.startsWith("#") && message.endsWith("F")) {
      RegExp regex = RegExp(r"#(\d)A(\d+)B6C7D(\d+)E\d+F");
      Match? match = regex.firstMatch(message);
      if (match != null) {
        String receivedDeviceId = match.group(3)!;
        setState(() {
          deviceId = receivedDeviceId;
        });
      }
    }
  }

  Future<void> _loadItems() async {
    List<String> itemsJson = await _prefsService.loadItems();
    setState(() {
      _items = itemsJson.map((item) => ItemDeviceModel(item)).toList();
    });
  }

  Future<void> _saveItems() async {
    List<String> itemsJson = _items.map((item) => item.name).toList();
    await _prefsService.saveItems(itemsJson);
  }

  void _addItem(String name) {
    setState(() {
      _items.add(ItemDeviceModel(name));
    });
    _saveItems();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    _saveItems();
  }

  void _navigateToDetailScreen(String itemName) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TabScreen(itemName: itemName)),
    );
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('اضافه کردن آیتم جدید'),
          content: TextField(
            controller: _textController,
            decoration: InputDecoration(hintText: 'نام آیتم را وارد کنید'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('لغو'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_textController.text.isNotEmpty) {
                  _addItem(_textController.text);
                  _textController.clear();
                  Navigator.of(context).pop();
                }
              },
              child: Text('اضافه کردن'),
            ),
          ],
        );
      },
    );
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);
    final bool isTablet = MediaQuery.of(context).size.width > 600;

    return MaterialApp(
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Enhanced Custom Header
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors:
                        _isDarkMode
                            ? [Colors.grey[900]!, Colors.grey[800]!]
                            : [Colors.amber[700]!, Colors.amber[400]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24.0 : 16.0,
                  vertical: 16.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          "محل نصب دستگاه",
                          style: TextStyle(
                            fontSize: isTablet ? 30 : 20,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 12),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                connectionProvider.isConnected
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  connectionProvider.isConnected
                                      ? Colors.green
                                      : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                connectionProvider.isConnected
                                    ? Icons.check_circle
                                    : Icons.error,
                                size: isTablet ? 20 : 16,
                                color:
                                    connectionProvider.isConnected
                                        ? Colors.green
                                        : Colors.red,
                              ),
                              SizedBox(width: 4),
                              Text(
                                connectionProvider.isConnected
                                    ? 'متصل'
                                    : 'قطع شده',
                                style: TextStyle(
                                  fontSize: isTablet ? 16 : 14,
                                  color:
                                      connectionProvider.isConnected
                                          ? Colors.green
                                          : Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: Colors.grey[800],
                            size: isTablet ? 28 : 24,
                          ),
                          onPressed: () {},
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                            color: Colors.white,
                            size: isTablet ? 28 : 24,
                          ),
                          onSelected: (String value) {
                            if (value == 'toggle_theme') _toggleDarkMode();
                          },
                          itemBuilder:
                              (BuildContext context) => [
                                PopupMenuItem<String>(
                                  value: 'toggle_theme',
                                  child: Row(
                                    children: [
                                      Icon(
                                        _isDarkMode
                                            ? Icons.light_mode
                                            : Icons.dark_mode,
                                        color:
                                            _isDarkMode
                                                ? Colors.yellow[300]
                                                : Colors.yellow[800],
                                      ),
                                      SizedBox(width: isTablet ? 10 : 8),
                                      Text(
                                        _isDarkMode
                                            ? 'حالت روشن'
                                            : 'حالت تاریک',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Enhanced ListView with Cards
              Expanded(
                child: Container(
                  color: _isDarkMode ? Colors.grey[850] : Colors.grey[100],
                  child: ListView.builder(
                    padding: EdgeInsets.all(isTablet ? 16.0 : 8.0),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return Card(
                        elevation: 2,
                        margin: EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: _isDarkMode ? Colors.grey[800] : Colors.white,
                        child: ItemListTile(
                          itemName: _items[index].name,
                          onDelete: () => _removeItem(index),
                          onTap:
                              () => _navigateToDetailScreen(_items[index].name),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.amber,
          shape: CircleBorder(),
          onPressed: _showAddItemDialog,
          child: Icon(Icons.add, size: 28),
          tooltip: 'اضافه کردن آیتم جدید',
          elevation: 6,
        ),
      ),
    );
  }
}
