import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Model/shedule_model.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Widget/schedule_settings.dart';
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
  Map<int, ScheduleModel> relaySchedules = {};
  final double horizontalPadding = 40;
  final double verticalPadding = 25;
  int packetNumber = 0;
  TextEditingController commandController = TextEditingController();
  List<int> receivedBytesBuffer = [];
  List<String> receivedMessages = [];

  List mySmartDevices = [
    ["تاچ 1", "assets/lightbulb.png", false],
    ["تاچ 2", "assets/lightbulb.png", false],
    ["تاچ 3", "assets/lightbulb.png", false],
    ["تاچ 4", "assets/lightbulb.png", false],
  ];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await loadAllData();
    await loadSchedules();
    _reconnectIfNeeded();
    _setupSerialListeners();
    _startScheduleChecker();
  }

  // Connection Handling
  Future<void> _reconnectIfNeeded() async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      List<DeviceInfo> devices =
          await _flutterSerialCommunicationPlugin.getAvailableDevices();
      if (devices.isNotEmpty) {
        bool success = await _flutterSerialCommunicationPlugin.connect(
          devices.first,
          115200,
        );
        connectionProvider.setConnectionStatus(success);
        if (!success) {
          _showSnackBar('اتصال به دستگاه ناموفق بود');
        }
      } else {
        _showSnackBar('هیچ دستگاهی یافت نشد');
      }
    }
  }

  // Data Persistence
  Future<void> saveAllData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> statusList =
        buttonStates.entries
            .map((e) => '${e.key}:${e.value ? "ON" : "OFF"}')
            .toList();
    await prefs.setStringList('relayStatus_${widget.deviceId}', statusList);
  }

  Future<void> loadAllData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? statusList = prefs.getStringList(
      'relayStatus_${widget.deviceId}',
    );
    if (statusList != null) {
      Map<int, bool> loadedStates = {};
      for (String status in statusList) {
        var parts = status.split(':');
        loadedStates[int.parse(parts[0])] = parts[1] == "ON";
      }
      setState(() {
        buttonStates = loadedStates;
        for (int i = 0; i < mySmartDevices.length; i++) {
          mySmartDevices[i][2] = buttonStates[i + 1] ?? false;
        }
      });
    }
  }

  Future<void> saveSchedules() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> scheduleMap = relaySchedules.map(
      (key, value) => MapEntry(key.toString(), value.toJson()),
    );
    await prefs.setString(
      'schedules_${widget.deviceId}',
      jsonEncode(scheduleMap),
    );
  }

  Future<void> loadSchedules() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? scheduleJson = prefs.getString('schedules_${widget.deviceId}');
    if (scheduleJson != null) {
      Map<String, dynamic> scheduleMap = jsonDecode(scheduleJson);
      setState(() {
        relaySchedules = scheduleMap.map(
          (key, value) =>
              MapEntry(int.parse(key), ScheduleModel.fromJson(value)),
        );
      });
    }
  }

  // Device Control
  void _toggleCommand(int buttonNumber, bool newValue) async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      _showSnackBar('دستگاه متصل نیست');
      await _reconnectIfNeeded();
      return;
    }
    String stateDigit = newValue ? "1" : "0";
    String command =
        "#${stateDigit}A${buttonNumber}B6C7D${widget.deviceId}E${packetNumber}F\n";
    bool sent = await _flutterSerialCommunicationPlugin.write(
      Uint8List.fromList(command.codeUnits),
    );
    if (sent) {
      setState(() {
        buttonStates[buttonNumber] = newValue;
        mySmartDevices[buttonNumber - 1][2] = newValue;
        commandController.text = command;
        packetNumber = Random().nextInt(10000);

        // ریست پرچم‌ها در صورت تغییر دستی
        if (relaySchedules.containsKey(buttonNumber)) {
          if (newValue && relaySchedules[buttonNumber]!.onTime != null) {
            relaySchedules[buttonNumber]!.onTriggered =
                true; // جلوگیری از اجرای دوباره
          } else if (!newValue &&
              relaySchedules[buttonNumber]!.offTime != null) {
            relaySchedules[buttonNumber]!.offTriggered =
                true; // جلوگیری از اجرای دوباره
          }
        }
      });
      await saveAllData();
      await saveSchedules(); // ذخیره تغییرات پرچم‌ها
    }
  }

  void _processReceivedMessage(String message) {
    RegExp regex = RegExp(r"#(\d)A(\d+)B6C(\d+)D7E\d+F");
    Match? match = regex.firstMatch(message);
    if (match != null && match.group(3) == widget.deviceId) {
      bool newState = match.group(1) == "1";
      int relayNumber = int.parse(match.group(2)!);
      setState(() {
        buttonStates[relayNumber] = newState;
        mySmartDevices[relayNumber - 1][2] = newState;
      });
      saveAllData();
    }
  }

  // Serial Communication
  void _setupSerialListeners() {
    _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .listen((event) {
          receivedBytesBuffer.addAll(event);
          int endIndex = receivedBytesBuffer.indexOf(0x46);
          if (endIndex != -1) {
            int startIndex = receivedBytesBuffer.lastIndexOf(0x23, endIndex);
            if (startIndex != -1) {
              String message =
                  utf8
                      .decode(
                        receivedBytesBuffer.sublist(startIndex, endIndex + 1),
                      )
                      .trim();
              receivedBytesBuffer.removeRange(0, endIndex + 1);
              setState(() {
                receivedMessages.add(message);
                _processReceivedMessage(message);
              });
            }
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

  // Schedule Management
  void _startScheduleChecker() {
    Future.delayed(Duration(seconds: 1), () {
      _checkSchedules();
      _startScheduleChecker();
    });
  }

  void _checkSchedules() {
    final now = TimeOfDay.now();
    relaySchedules.forEach((relay, schedule) {
      // بررسی زمان روشن شدن
      if (schedule.onTime != null &&
          now.hour == schedule.onTime!.hour &&
          now.minute == schedule.onTime!.minute &&
          !schedule.onTriggered) {
        // فقط اگر هنوز اجرا نشده باشد
        if (!(buttonStates[relay] ?? false)) {
          // اگر دستگاه خاموش است
          _toggleCommand(relay, true);
        }
        setState(() {
          schedule.onTriggered = true; // علامت‌گذاری به‌عنوان اجرا شده
        });
        saveSchedules();
      } else if (schedule.onTime != null &&
          (now.hour != schedule.onTime!.hour ||
              now.minute != schedule.onTime!.minute)) {
        // ریست پرچم وقتی زمان تغییر کرد
        if (schedule.onTriggered) {
          setState(() {
            schedule.onTriggered = false;
          });
          saveSchedules();
        }
      }

      // بررسی زمان خاموش شدن
      if (schedule.offTime != null &&
          now.hour == schedule.offTime!.hour &&
          now.minute == schedule.offTime!.minute &&
          !schedule.offTriggered) {
        // فقط اگر هنوز اجرا نشده باشد
        if (buttonStates[relay] ?? false) {
          // اگر دستگاه روشن است
          _toggleCommand(relay, false);
        }
        setState(() {
          schedule.offTriggered = true; // علامت‌گذاری به‌عنوان اجرا شده
        });
        saveSchedules();
      } else if (schedule.offTime != null &&
          (now.hour != schedule.offTime!.hour ||
              now.minute != schedule.offTime!.minute)) {
        // ریست پرچم وقتی زمان تغییر کرد
        if (schedule.offTriggered) {
          setState(() {
            schedule.offTriggered = false;
          });
          saveSchedules();
        }
      }
    });
  }

  void _showScheduleBottomSheet(int relayNumber) {
    relaySchedules[relayNumber] ??= ScheduleModel();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      backgroundColor: Colors.white,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.2,
            maxChildSize: 0.6,
            expand: false,
            builder:
                (context, scrollController) => StatefulBuilder(
                  builder: (
                    BuildContext context,
                    StateSetter bottomSheetSetState,
                  ) {
                    return SingleChildScrollView(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 40,
                              height: 5,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            Text(
                              "زمان‌بندی ${mySmartDevices[relayNumber - 1][0]}",
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildModernTimeBox(
                                  context,
                                  "روشن",
                                  relaySchedules[relayNumber]!.onTime,
                                  () async {
                                    TimeOfDay? picked = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.now(),
                                      builder:
                                          (context, child) => MediaQuery(
                                            data: MediaQuery.of(
                                              context,
                                            ).copyWith(
                                              alwaysUse24HourFormat: true,
                                            ),
                                            child: child!,
                                          ),
                                    );
                                    if (picked != null) {
                                      bottomSheetSetState(() {
                                        relaySchedules[relayNumber]!.onTime =
                                            picked;
                                        relaySchedules[relayNumber]!
                                            .onTriggered = false; // ریست پرچم
                                      });
                                      setState(() {}); // به‌روزرسانی UI اصلی
                                      await saveSchedules();
                                    }
                                  },
                                  Colors.green,
                                ),
                                _buildModernTimeBox(
                                  context,
                                  "خاموش",
                                  relaySchedules[relayNumber]!.offTime,
                                  () async {
                                    TimeOfDay? picked = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.now(),
                                      builder:
                                          (context, child) => MediaQuery(
                                            data: MediaQuery.of(
                                              context,
                                            ).copyWith(
                                              alwaysUse24HourFormat: true,
                                            ),
                                            child: child!,
                                          ),
                                    );
                                    if (picked != null) {
                                      bottomSheetSetState(() {
                                        relaySchedules[relayNumber]!.offTime =
                                            picked;
                                        relaySchedules[relayNumber]!
                                            .offTriggered = false; // ریست پرچم
                                      });
                                      setState(() {}); // به‌روزرسانی UI اصلی
                                      await saveSchedules();
                                    }
                                  },
                                  Colors.red,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      relaySchedules[relayNumber]!.onTime =
                                          null;
                                      relaySchedules[relayNumber]!.offTime =
                                          null;
                                    });
                                    saveSchedules();
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  label: const Text("پاک کردن"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade50,
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 20),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey.shade50,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 30,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    "بستن",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
    );
  }

  Widget _buildModernTimeBox(
    BuildContext context,
    String label,
    TimeOfDay? time,
    VoidCallback onTap,
    Color color,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              time?.format(context) ?? "--:--",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.amber[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    double childAspectRatio = screenWidth > 600 ? 1 / 1.5 : 1 / 1.3;

    return MaterialApp(
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      home: Scaffold(
        appBar: AppBar(title: Text("مدیریت دستگاه ${widget.deviceId}")),
        body: Padding(
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
                      onChanged: (value) => _toggleCommand(index + 1, value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ScheduleSettings(
                smartDevices: mySmartDevices,
                relaySchedules: relaySchedules,
                onScheduleTap: _showScheduleBottomSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
