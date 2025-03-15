import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/config/localization.dart';
import 'package:smart_home_app/Features/Home/smart_device_box.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class ManageDevice extends StatefulWidget {
  final String deviceId;

  const ManageDevice({super.key, required this.deviceId});

  @override
  State<ManageDevice> createState() => _ManageDeviceState();
}

class _ManageDeviceState extends State<ManageDevice> {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  Map<int, bool> buttonStates = {};
  final double horizontalPadding = 40;
  final double verticalPadding = 25;
  int packetNumber = 0;
  String receivedCommand = "";
  TextEditingController commandController = TextEditingController();
  List<int> receivedBytesBuffer = [];
  TextEditingController statusController = TextEditingController();
  List<String> receivedMessages = [];

  List mySmartDevices = [
    ["تاچ 1", "assets/lightbulb.png", false],
    ["تاچ 2", "assets/lightbulb.png", false],
    ["تاچ 3", "assets/lightbulb.png", false],
    ["تاچ 4", "assets/lightbulb.png", false],
  ];

  Future<void> _reconnectIfNeeded() async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      List<DeviceInfo> devices =
          await _flutterSerialCommunicationPlugin.getAvailableDevices();
      if (devices.isNotEmpty) {
        bool isConnectionSuccess = await _flutterSerialCommunicationPlugin
            .connect(devices.first, 115200);
        if (isConnectionSuccess) {
          connectionProvider.setConnectionStatus(true);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('اتصال به دستگاه ناموفق بود')));
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('هیچ دستگاهی یافت نشد')));
      }
    }
  }

  void powerSwitchChanged(bool value, int index) {
    setState(() {
      mySmartDevices[index][2] = value;
      buttonStates[index + 1] = value;
    });
  }

  String extractNumbersBetween(String input, String startChar, String endChar) {
    // ساخت الگوی عبارت منظم
    RegExp regExp = RegExp('$startChar(\\d+)$endChar');

    // جستجو برای تطابق
    Match? match = regExp.firstMatch(input);

    // اگر تطابق پیدا شد، اعداد را برگردان
    if (match != null) {
      return match.group(1)!;
    }

    return '';
  }

  void _processReceivedMessage(String message) {
    // تحلیل پیام دریافتی برای شناسایی کلید
    if (message.startsWith("#") && message.endsWith("F")) {
      RegExp regex = RegExp(r"#(\d)A(\d+)B");
      Match? match = regex.firstMatch(message);
      if (match != null) {
        String stateDigit = match.group(1)!; // وضعیت کلید (0 یا 1)
        int relayNumber = int.parse(match.group(2)!); // شماره کلید

        bool newState =
            stateDigit == "1"; // اگر 1 باشد روشن، در غیر این صورت خاموش

        setState(() {
          buttonStates[relayNumber] = newState; // به‌روزرسانی وضعیت کلید
          mySmartDevices[relayNumber - 1][2] =
              newState; // تغییر وضعیت در لیست دستگاه‌ها
        });

        // ذخیره‌سازی وضعیت جدید
        saveAllData();
      }
    }
  }

  Future<void> saveData(String relayNumber, String status) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // دریافت لیست وضعیت‌های ذخیره شده
    List<String>? statusList = prefs.getStringList('relayStatus');

    // اگر لیست وجود نداشته باشد، یک لیست جدید ایجاد کنید
    statusList ??= [];

    // بررسی آیا وضعیت این رله قبلاً ذخیره شده است یا خیر
    bool isExist = false;
    for (int i = 0; i < statusList.length; i++) {
      if (statusList[i].startsWith(relayNumber)) {
        // به‌روزرسانی وضعیت موجود
        statusList[i] = "$relayNumber:$status";
        isExist = true;
        break;
      }
    }

    if (!isExist) {
      statusList.add("$relayNumber:$status");
    }

    await prefs.setStringList('relayStatus', statusList);
  }

  Future<void> saveAllData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // ایجاد لیست از وضعیت کلیدها
    List<String> statusList =
        buttonStates.entries
            .map((entry) => '${entry.key}:${entry.value ? "ON" : "OFF"}')
            .toList();

    // ذخیره لیست در SharedPreferences با کلیدی که شامل deviceId است
    await prefs.setStringList('relayStatus_${widget.deviceId}', statusList);
  }

  Future<void> loadAllData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // خواندن لیست وضعیت‌ها از SharedPreferences با کلیدی که شامل deviceId است
    List<String>? statusList = prefs.getStringList(
      'relayStatus_${widget.deviceId}',
    );

    if (statusList != null) {
      // بازیابی وضعیت‌ها
      Map<int, bool> loadedStates = {};
      for (String status in statusList) {
        List<String> parts = status.split(':');
        if (parts.length == 2) {
          int relayNumber = int.parse(parts[0]);
          bool isOn = parts[1] == "ON";
          loadedStates[relayNumber] = isOn;
        }
      }

      setState(() {
        buttonStates = loadedStates;
        for (int i = 0; i < mySmartDevices.length; i++) {
          mySmartDevices[i][2] = buttonStates[i + 1] ?? false;
        }
      });
    }
  }

  void _toggleCommand(int buttonNumber, bool newValue) async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('دستگاه متصل نیست، لطفاً دوباره تلاش کنید')),
      );
      await _reconnectIfNeeded();
      return;
    }
    bool currentState = buttonStates[buttonNumber] ?? false;
    String stateDigit = currentState ? "0" : "1";
    String command =
        "#${stateDigit}A${buttonNumber}B6C7D${widget.deviceId}E${packetNumber}F\n";

    bool isMessageSent = await _flutterSerialCommunicationPlugin.write(
      Uint8List.fromList(command.codeUnits),
    );

    setState(() {
      // تغییر وضعیت دکمه
      buttonStates[buttonNumber] = !currentState;
      mySmartDevices[buttonNumber - 1][2] = !currentState;
      commandController.text = command; // نمایش دستور در TextField
    });

    debugPrint("Is Command Sent: $isMessageSent");
    await saveData(
      buttonNumber.toString(),
      currentState ? "OFF" : "ON",
    ); // ذخیره وضعیت

    await saveAllData();

    // افزایش شماره بسته برای دفعه بعد
    setState(() {
      packetNumber = Random().nextInt(10000);
    });
  }

  @override
  void initState() {
    super.initState();

    loadAllData();

    _reconnectIfNeeded();

    _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .listen((event) {
          receivedBytesBuffer.addAll(event); // Add incoming bytes to buffer

          // Check for end of message (e.g., #...F)
          int endIndex = -1;
          for (int i = 0; i < receivedBytesBuffer.length; i++) {
            if (receivedBytesBuffer[i] == 0x46) {
              // ASCII code for 'F'
              int startIndex = -1;
              for (int j = i - 1; j >= 0; j--) {
                if (receivedBytesBuffer[j] == 0x23) {
                  // ASCII code for '#'
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
              message = utf8.decode(completeMessageBytes); // Decode using UTF-8
            } catch (e) {
              message = "Error decoding: $e"; // Handle decoding errors
            }

            receivedBytesBuffer.removeRange(
              0,
              endIndex + 1,
            ); // Clear the processed message from buffer

            message = message.trim(); // Remove whitespace and line endings

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
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    // تنظیم نسبت عرض به ارتفاع
    double childAspectRatio = screenWidth > 600 ? 1 / 1.5 : 1 / 1.3;
    return MaterialApp(
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      home: Scaffold(
        appBar: AppBar(title: Text("مدیریت دستگاه ${widget.deviceId}")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                const SizedBox(height: 16.0),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 600 ? 50 : 25,
                    vertical: screenWidth > 600 ? 30 : 25,
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: mySmartDevices.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemBuilder: (context, index) {
                      return SmartDeviceBox(
                        key: Key(index.toString()),
                        smartDeviceName: mySmartDevices[index][0],
                        iconPath: mySmartDevices[index][1],
                        powerOn: buttonStates[index + 1] ?? false,
                        onChanged: (bool newValue) {
                          _toggleCommand(index + 1, newValue);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
