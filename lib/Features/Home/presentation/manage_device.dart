import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Model/shedule_model.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';
import 'package:smart_home_app/Core/Services/serial_service.dart';
import 'package:smart_home_app/Core/Widget/schedule_settings.dart';
import 'package:smart_home_app/Features/Home/smart_device_box.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';

class ManageDevice extends StatefulWidget {
  final String deviceId;
  final String deviceInfo;
  final String itemName;

  const ManageDevice({
    super.key,
    required this.deviceId,
    required this.deviceInfo,
    required this.itemName,
  });

  @override
  State<ManageDevice> createState() => _ManageDeviceState();
}

class _ManageDeviceState extends State<ManageDevice>
    with WidgetsBindingObserver {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  final SerialService _serialService = SerialService();
  Map<int, ScheduleModel> relaySchedules = {};
  final double horizontalPadding = 40;
  final double verticalPadding = 25;
  List<int> receivedBytesBuffer = [];
  List<String> receivedMessages = [];
  List<String> sentMessages = [];
  List mySmartDevices = [];
  StreamSubscription? _serialSubscription;
  bool _isSending = false; // برای جلوگیری از ارسال همزمان دستورات

  @override
  void initState() {
    super.initState();
    // Listener for receiving messages
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
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await loadSchedules();
    await _reconnectIfNeeded();
    _startScheduleChecker();

    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    await deviceProvider.loadButtonStatesFromPrefs(widget.deviceId);
    await deviceProvider.loadPacketNumbersFromPrefs(widget.deviceId);
    _updateSmartDevices(deviceProvider);
    _setupSerialListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("Lifecycle State (ManageDevice): $state");
    if (state == AppLifecycleState.resumed) {
      _reconnectIfNeeded();
      _setupSerialListener();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _serialSubscription?.cancel();
    }
  }

  void _updateSmartDevices(DeviceProvider deviceProvider) {
    final device = deviceProvider.getDeviceById(
      widget.deviceId,
      widget.itemName,
    );
    if (device.isNotEmpty) {
      int poleCount = int.parse(device["poleCount"] ?? "1");
      setState(() {
        mySmartDevices = List.generate(
          poleCount,
          (index) => [
            "تاچ ${index + 1}",
            "assets/lightbulb.png",
            deviceProvider.getButtonStates(widget.deviceId)[index + 1] ?? false,
          ],
        );
      });
    }
  }

  void _setupSerialListener() {
    _serialSubscription?.cancel();
    _serialSubscription = _serialService.getSerialMessages().listen(
      (event) {
        receivedBytesBuffer.addAll(event);
        while (true) {
          int endIndex = receivedBytesBuffer.indexOf(0x46); // 'F'
          if (endIndex == -1) break;
          int startIndex = receivedBytesBuffer.lastIndexOf(
            0x23,
            endIndex,
          ); // '#'
          if (startIndex == -1) break;

          try {
            String message =
                utf8
                    .decode(
                      receivedBytesBuffer.sublist(startIndex, endIndex + 1),
                    )
                    .trim();
            receivedBytesBuffer.removeRange(0, endIndex + 1);
            debugPrint("پیام دریافتی (ManageDevice): $message");
            setState(() {
              receivedMessages.add(message);
              if (receivedMessages.length > 10) {
                receivedMessages.removeAt(0);
              }
              _processReceivedMessage(message);
            });
          } catch (e) {
            debugPrint("خطا در رمزگشایی پیام: $e");
            receivedBytesBuffer.removeRange(0, endIndex + 1);
          }
        }
      },
      onError: (error) {
        debugPrint("خطا در دریافت پیام سریال: $error");
      },
    );
  }

  Future<void> _reconnectIfNeeded() async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      List<DeviceInfo> devices = await _serialService.getAvailableDevices();
      if (devices.isNotEmpty) {
        bool success = await _serialService.connect(devices.first, 115200);
        connectionProvider.setConnectionStatus(success);
        debugPrint("وضعیت اتصال (ManageDevice): $success");
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اتصال به دستگاه ناموفق بود')),
          );
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('هیچ دستگاهی یافت نشد')));
      }
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

  Future<void> _toggleCommand(int buttonNumber, bool newValue) async {
    if (_isSending) {
      debugPrint("ارسال دستور در حال انجام است، لطفاً منتظر بمانید...");
      return;
    }

    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('دستگاه متصل نیست')));
      await _reconnectIfNeeded();
      if (!connectionProvider.isConnected) {
        debugPrint("اتصال برقرار نشد، ارسال دستور لغو شد.");
        return;
      }
    }

    _isSending = true;
    try {
      final deviceProvider = Provider.of<DeviceProvider>(
        context,
        listen: false,
      );
      int lastPacketNumber = deviceProvider.getLastPacketNumber(
        widget.deviceId,
        buttonNumber,
      );
      int newPacketNumber = (lastPacketNumber + 1) % 10000;

      String stateDigit = newValue ? "1" : "0";
      String command =
          "#${stateDigit}A${buttonNumber}B7C7D${widget.deviceId}E${newPacketNumber}F\n";
      debugPrint("دستور ارسالی (ManageDevice): $command");

      bool sent = await _serialService
          .write(command)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint("مهلت زمانی ارسال دستور به پایان رسید.");
              return false;
            },
          );

      if (sent) {
        debugPrint("دستور با موفقیت ارسال شد (ManageDevice)");
        deviceProvider.updateLastPacketNumber(
          widget.deviceId,
          buttonNumber,
          newPacketNumber,
        );
        setState(() {
          sentMessages.add(command.trim());
          if (sentMessages.length > 10) {
            sentMessages.removeAt(0);
          }
          deviceProvider.updateButtonState(
            widget.deviceId,
            buttonNumber,
            newValue,
          );
          mySmartDevices[buttonNumber - 1][2] = newValue;
          if (relaySchedules.containsKey(buttonNumber)) {
            if (newValue && relaySchedules[buttonNumber]!.onTime != null) {
              relaySchedules[buttonNumber]!.onTriggered = true;
            } else if (!newValue &&
                relaySchedules[buttonNumber]!.offTime != null) {
              relaySchedules[buttonNumber]!.offTriggered = true;
            }
          }
        });
        await saveSchedules();
      } else {
        debugPrint("خطا در ارسال دستور (ManageDevice)");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('خطا در ارسال دستور')));
      }
    } catch (e) {
      debugPrint("خطای غیرمنتظره در ارسال دستور: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطای غیرمنتظره: $e')));
    } finally {
      _isSending = false;
    }
  }

  void _processReceivedMessage(String message) {
    RegExp regex = RegExp(r"#(\d)A(\d+)B(\d+)C(\d+)D([^E]+)E(\d+)F");
    Match? match = regex.firstMatch(message);
    if (match != null && match.group(4) == widget.deviceId) {
      bool newState = match.group(1) == "1";
      int relayNumber = int.parse(match.group(2)!);
      debugPrint(
        "پیام پردازش شد (ManageDevice): رله $relayNumber به $newState تغییر کرد",
      );
      Provider.of<DeviceProvider>(
        context,
        listen: false,
      ).updateButtonState(widget.deviceId, relayNumber, newState);
      setState(() {
        mySmartDevices[relayNumber - 1][2] = newState;
      });
    } else {
      debugPrint("پیام با الگو یا deviceId مطابقت ندارد: $message");
    }
  }

  void _startScheduleChecker() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _checkSchedules();
        _startScheduleChecker();
      }
    });
  }

  void _checkSchedules() {
    final now = TimeOfDay.now();
    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    relaySchedules.forEach((relay, schedule) {
      if (schedule.onTime != null &&
          now.hour == schedule.onTime!.hour &&
          now.minute == schedule.onTime!.minute &&
          !schedule.onTriggered) {
        if (!(deviceProvider.getButtonStates(widget.deviceId)[relay] ??
            false)) {
          _toggleCommand(relay, true);
        }
        setState(() {
          schedule.onTriggered = true;
        });
        saveSchedules();
      } else if (schedule.onTime != null &&
          (now.hour != schedule.onTime!.hour ||
              now.minute != schedule.onTime!.minute)) {
        if (schedule.onTriggered) {
          setState(() {
            schedule.onTriggered = false;
          });
          saveSchedules();
        }
      }

      if (schedule.offTime != null &&
          now.hour == schedule.offTime!.hour &&
          now.minute == schedule.offTime!.minute &&
          !schedule.offTriggered) {
        if (deviceProvider.getButtonStates(widget.deviceId)[relay] ?? false) {
          _toggleCommand(relay, false);
        }
        setState(() {
          schedule.offTriggered = true;
        });
        saveSchedules();
      } else if (schedule.offTime != null &&
          (now.hour != schedule.offTime!.hour ||
              now.minute != schedule.offTime!.minute)) {
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
                                            .onTriggered = false;
                                      });
                                      setState(() {});
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
                                            .offTriggered = false;
                                      });
                                      setState(() {});
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
                                      relaySchedules[relayNumber]!.onTriggered =
                                          false;
                                      relaySchedules[relayNumber]!
                                          .offTriggered = false;
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

  @override
  void dispose() {
    _serialSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    _updateSmartDevices(deviceProvider);

    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    double childAspectRatio = screenWidth > 600 ? 1 / 1.5 : 1 / 1.3;

    final device = deviceProvider.getDeviceById(
      widget.deviceId,
      widget.itemName,
    );
    int poleCount =
        device.isNotEmpty ? int.parse(device["poleCount"] ?? "1") : 0;

    if (poleCount == 0) {
      return Scaffold(
        appBar: AppBar(
          title: Text("مدیریت دستگاه ${widget.deviceId}"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text("دستگاهی برای نمایش وجود ندارد")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("مدیریت دستگاه ${widget.deviceId}"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
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
                    key: Key('${widget.deviceId}_${index + 1}'),
                    smartDeviceName: mySmartDevices[index][0],
                    iconPath: mySmartDevices[index][1],
                    powerOn: mySmartDevices[index][2],
                    onChanged: (value) => _toggleCommand(index + 1, value),
                    relayNumber: index + 1,
                    deviceId: widget.deviceId,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // نمایش پیام‌های دریافتی
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "پیام‌های دریافتی:",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child:
                        receivedMessages.isEmpty
                            ? const Text(
                              "هیچ پیامی دریافت نشده است",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            )
                            : ListView.builder(
                              itemCount: receivedMessages.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  receivedMessages[index],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                    height: 1.5,
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // نمایش پیام‌های ارسالی
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "پیام‌های ارسالی:",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child:
                        sentMessages.isEmpty
                            ? const Text(
                              "هیچ پیامی ارسال نشده است",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            )
                            : ListView.builder(
                              itemCount: sentMessages.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  sentMessages[index],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black54,
                                    height: 1.5,
                                  ),
                                );
                              },
                            ),
                  ),
                ],
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
    );
  }
}
