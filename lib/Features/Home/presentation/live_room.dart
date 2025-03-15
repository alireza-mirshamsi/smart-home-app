import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Model/item_device_model.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/item_list_tile.dart';
import 'package:smart_home_app/Core/Services/storage_item.dart';
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

  @override
  void initState() {
    super.initState();

    // اتصال خودکار به دستگاه
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
          ).setConnectionStatus(event); // به‌روزرسانی وضعیت با Provider
        });

    _loadItems();
  }

  Future<void> _checkAndConnectToDevice() async {
    List<DeviceInfo> devices =
        await _flutterSerialCommunicationPlugin.getAvailableDevices();
    if (devices.isNotEmpty) {
      bool isConnectionSuccess = await _flutterSerialCommunicationPlugin
          .connect(
            devices.first, // اتصال به اولین دستگاه
            115200,
          );
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

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
    ); // دسترسی به Provider

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('محل نصب دستگاه'),
            Row(
              children: [
                Icon(
                  connectionProvider.isConnected ? Icons.wifi : Icons.wifi_off,
                  color:
                      connectionProvider.isConnected
                          ? Colors.green
                          : Colors.red,
                ),
                SizedBox(width: 8),
                Text(
                  connectionProvider.isConnected ? 'متصل' : 'قطع شده',
                  style: TextStyle(
                    color:
                        connectionProvider.isConnected
                            ? Colors.green
                            : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          return ItemListTile(
            itemName: _items[index].name,
            onDelete: () => _removeItem(index),
            onTap: () => _navigateToDetailScreen(_items[index].name),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        shape: CircleBorder(),
        onPressed: _showAddItemDialog,
        child: Icon(Icons.add),
        tooltip: 'اضافه کردن آیتم جدید',
      ),
    );
  }
}
