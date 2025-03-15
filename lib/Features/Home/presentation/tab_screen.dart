import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/config/localization.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:smart_home_app/Features/Home/presentation/manage_device.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class TabScreen extends StatefulWidget {
  final String itemName;

  TabScreen({required this.itemName});

  @override
  _TabScreenState createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  List<int> receivedBytesBuffer = [];
  List<String> receivedMessages = [];
  String deviceId = '';

  // لیست دستگاه‌ها برای itemName خاص
  List<Map<String, String>> devices = [];

  @override
  void initState() {
    super.initState();

    // بارگذاری لیست دستگاه‌ها از SharedPreferences برای itemName خاص
    _loadDevicesFromPrefs();

    // اتصال خودکار به دستگاه و دریافت پیام‌ها
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
              debugPrint("خطا در رمزگشایی پیام: $e");
              return;
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
  }

  // بارگذاری دستگاه‌ها از SharedPreferences برای itemName خاص
  Future<void> _loadDevicesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? devicesString = prefs.getString('devices_${widget.itemName}');
    if (devicesString != null) {
      setState(() {
        devices = List<Map<String, String>>.from(
          json
              .decode(devicesString)
              .map((item) => Map<String, String>.from(item)),
        );
      });
    }
  }

  // ذخیره دستگاه‌ها در SharedPreferences برای itemName خاص
  Future<void> _saveDevicesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String devicesString = json.encode(devices);
    await prefs.setString('devices_${widget.itemName}', devicesString);
    debugPrint("Devices saved for ${widget.itemName}: $devicesString");
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
    if (message.startsWith("#") &&
        message.contains("A") &&
        message.contains("B") &&
        message.contains("C")) {
      RegExp regex = RegExp(r"#(\d+)A(\d+)B6C");
      Match? match = regex.firstMatch(message);
      if (match != null) {
        String receivedDeviceId = match.group(1)!; // عدد بین # و A
        String deviceTypeCode = match.group(2)!; // عدد بین A و B

        if (receivedDeviceId.isEmpty ||
            !regex.hasMatch(message) ||
            receivedDeviceId == "0" ||
            receivedDeviceId == "1") {
          debugPrint("deviceId خالی است یا پیام با فرمت تطابق ندارد: $message");
          return;
        }

        setState(() {
          deviceId = receivedDeviceId;

          if (deviceTypeCode == "1" && message.contains("B6C")) {
            int deviceIndex = devices.indexWhere(
              (d) => d["deviceId"] == receivedDeviceId,
            );
            if (deviceIndex == -1) {
              // اضافه کردن دستگاه جدید فقط برای itemName فعلی
              devices.add({
                "name": "کلید چهار پل",
                "deviceId": receivedDeviceId,
                "image": "assets/4-pol.jpeg",
              });
              _saveDevicesToPrefs();
              debugPrint(
                "دستگاه جدید اضافه شد برای ${widget.itemName}: $receivedDeviceId",
              );
            } else {
              debugPrint(
                "دستگاه از قبل وجود دارد: ${devices[deviceIndex]["name"]}",
              );
            }
          } else {
            debugPrint(
              "نوع دستگاه پشتیبانی نمی‌شود یا فرمت نادرست است: $message",
            );
          }
        });

        debugPrint("Device ID: $receivedDeviceId");
        debugPrint("Device Type Code: $deviceTypeCode");
      } else {
        debugPrint("فرمت پیام دریافتی نادرست است: $message");
      }
    } else {
      debugPrint("پیام دریافتی ناقص است: $message");
    }
  }

  _sendLearnCommand() async {
    String command = "LEARN\r";
    bool isMessageSent = await _flutterSerialCommunicationPlugin.write(
      Uint8List.fromList(command.codeUnits),
    );
    debugPrint("Is LEARN Command Sent: $isMessageSent");
    if (!isMessageSent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("ارسال دستور LEARN ناموفق بود")));
    }
  }

  _sendTransCommand() async {
    String command = "TRANS\r";
    bool isMessageSent = await _flutterSerialCommunicationPlugin.write(
      Uint8List.fromList(command.codeUnits),
    );
    debugPrint("Is TRANS Command Sent: $isMessageSent");
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);

    return MaterialApp(
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      home: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("انتخاب دستگاه در ${widget.itemName}"),
              Row(
                children: [
                  Icon(
                    connectionProvider.isConnected
                        ? Icons.wifi
                        : Icons.wifi_off,
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
        body: Column(
          children: [
            Expanded(
              child:
                  devices.isEmpty
                      ? Center(child: Text("هیچ دستگاهی یافت نشد"))
                      : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => ManageDevice(
                                          deviceId: device["deviceId"]!,
                                        ),
                                  ),
                                );
                              },
                              child: Card(
                                elevation: 5,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15.0),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.all(5.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(15.0),
                                          topRight: Radius.circular(15.0),
                                        ),
                                        child: Image.asset(
                                          device["image"]!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                        device["name"]!,
                                        style: TextStyle(fontSize: 16.0),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
            ),
            Container(
              padding: EdgeInsets.all(16.0),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _sendLearnCommand,
                    child: const Text("LEARN"),
                  ),
                  ElevatedButton(
                    onPressed: _sendTransCommand,
                    child: const Text("TRANS"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
