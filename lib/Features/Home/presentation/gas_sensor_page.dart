import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';
import 'package:smart_home_app/Core/Services/serial_service.dart';
import 'package:smart_home_app/Core/Services/theme_provider.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';

class GasSensorPage extends StatefulWidget {
  final String deviceId;
  final String itemName;

  const GasSensorPage({required this.deviceId, required this.itemName});

  @override
  _GasSensorPageState createState() => _GasSensorPageState();
}

class _GasSensorPageState extends State<GasSensorPage>
    with WidgetsBindingObserver {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  final SerialService _serialService = SerialService();
  StreamSubscription? _serialSubscription;
  List<String> receivedMessages = [];
  String _stateCode = 'در انتظار دریافت...';
  List<int> receivedBytesBuffer = [];

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
    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    await deviceProvider.loadButtonStatesFromPrefs(widget.deviceId);
    await deviceProvider.loadPacketNumbersFromPrefs(widget.deviceId);
    _setupSerialListener();
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

  void _processReceivedMessage(String message) {
    RegExp regex = RegExp(r"#(\d+)A(\d+)B(\d+)C(\d+)D(\d+)E(\d+)F");
    Match? match = regex.firstMatch(message);
    if (match != null) {
      String stateCode = match.group(1)!;
      String deviceInfo = match.group(3)!;
      String receivedDeviceId = match.group(4)!;

      debugPrint(
        "Parsed message: stateCode=$stateCode, deviceInfo=$deviceInfo, "
        "receivedDeviceId=$receivedDeviceId, widget.deviceId=${widget.deviceId}",
      );

      // Update state code if this is the correct gas sensor device
      if (deviceInfo == "12" && receivedDeviceId == widget.deviceId) {
        setState(() {
          _stateCode = stateCode;
        });
        debugPrint("State code updated: $_stateCode");
      } else {
        debugPrint(
          "Message ignored: deviceInfo=$deviceInfo, "
          "stateCode=$stateCode does not match widget.deviceId=${widget.deviceId}",
        );
      }
    } else {
      debugPrint("Message does not match regex: $message");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("Lifecycle State (GasSensorPage): $state");
    if (state == AppLifecycleState.resumed) {
      _setupSerialListener();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _serialSubscription?.cancel();
    }
  }

  @override
  void dispose() {
    _serialSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.itemName,
          style: TextStyle(
            fontSize: isTablet ? 28 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor:
            themeProvider.isDarkMode ? Colors.grey[900] : Colors.amber[700],
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color:
                  themeProvider.isDarkMode
                      ? Colors.grey[850]
                      : Colors.grey[200],
              borderRadius: BorderRadius.circular(16.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8.0,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/sensor-gaz.png',
                  width: isTablet ? 200 : 150,
                  height: isTablet ? 200 : 150,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 16.0),
                Text(
                  'سنسور گاز',
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.yellow[300]
                            : Colors.yellow[800],
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'شناسه دستگاه: ${widget.deviceId}',
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 16,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  'میزان گاز: $_stateCode',
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 16,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[700],
                  ),
                ),
                // const Text(
                //   'پیام‌های دریافتی:',
                //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                // ),
                // SizedBox(
                //   height: 100,
                //   child:
                //       receivedMessages.isEmpty
                //           ? const Text(
                //             "هیچ پیامی دریافت نشده است",
                //             style: TextStyle(
                //               fontSize: 16,
                //               color: Colors.black54,
                //             ),
                //           )
                //           : ListView.builder(
                //             itemCount: receivedMessages.length,
                //             itemBuilder: (context, index) {
                //               return Text(
                //                 receivedMessages[index],
                //                 style: const TextStyle(
                //                   fontSize: 16,
                //                   color: Colors.black54,
                //                   height: 1.5,
                //                 ),
                //               );
                //             },
                //           ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
