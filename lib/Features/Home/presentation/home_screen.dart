import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/config/app_theme.dart';
import 'package:smart_home_app/Core/config/localization.dart';
import 'package:smart_home_app/Features/Home/presentation/live_room.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  List<DeviceInfo> connectedDevices = [];
  List<String> receivedMessages = [];
  TextEditingController messageController = TextEditingController();
  List<int> receivedBytesBuffer = [];
  String receivedCommand = "";
  TextEditingController commandController = TextEditingController();
  Map<int, bool> buttonStates = {};
  TextEditingController statusController = TextEditingController();
  bool _isDarkMode = false;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // اضافه کردن Observer
    _initializeSerialConnection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // بررسی و بازگردانی اتصال هنگام بازگشت به صفحه
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      _initializeSerialConnection();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // وقتی برنامه از پس‌زمینه به پیش‌زمینه برمی‌گردد
      _initializeSerialConnection();
    } else if (state == AppLifecycleState.paused) {
      // وقتی برنامه به پس‌زمینه می‌رود
      _cleanup();
    }
  }

  void _initializeSerialConnection() async {
    // لغو listenerهای قبلی اگر وجود داشته باشند
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();

    await _checkAndConnectToDevice();

    _messageSubscription = _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .listen(
          (event) {
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
          },
          onError: (error) {
            debugPrint("Error in message stream: $error");
          },
        );

    _connectionSubscription = _flutterSerialCommunicationPlugin
        .getDeviceConnectionListener()
        .receiveBroadcastStream()
        .listen(
          (event) {
            Provider.of<ConnectionProvider>(
              context,
              listen: false,
            ).setConnectionStatus(event);
          },
          onError: (error) {
            debugPrint("Error in connection stream: $error");
          },
        );
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
        setState(() {
          connectedDevices = devices;
        });
      } else {
        debugPrint("Failed to connect to device");
      }
    } else {
      debugPrint("No devices found");
    }
  }

  void _cleanup() {
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _flutterSerialCommunicationPlugin.disconnect();
  }

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  _getAllConnectedDevicesButtonPressed() async {
    List<DeviceInfo> newConnectedDevices =
        await _flutterSerialCommunicationPlugin.getAvailableDevices();
    setState(() {
      connectedDevices = newConnectedDevices;
    });
    _showConnectedDevicesSheet();
  }

  _connectButtonPressed(DeviceInfo deviceInfo) async {
    bool isConnectionSuccess = await _flutterSerialCommunicationPlugin.connect(
      deviceInfo,
      115200,
    );
    debugPrint("Is Connection Success: $isConnectionSuccess");
    if (isConnectionSuccess) {
      Provider.of<ConnectionProvider>(
        context,
        listen: false,
      ).setConnectionStatus(true);
    }
  }

  _disconnectButtonPressed() async {
    await _flutterSerialCommunicationPlugin.disconnect();
    Provider.of<ConnectionProvider>(
      context,
      listen: false,
    ).setConnectionStatus(false);
    setState(() {
      receivedMessages.clear();
    });
  }

  void _showConnectedDevicesSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "دستگاه‌های متصل",
                style: TextStyle(
                  fontSize: 20,
                  fontFamily: 'iransans',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16.0),
              connectedDevices.isEmpty
                  ? const Center(
                    child: Text(
                      "هیچ دستگاهی یافت نشد!",
                      style: TextStyle(
                        fontFamily: 'iransan',
                        fontSize: 18,
                        color: Colors.red,
                      ),
                    ),
                  )
                  : ListView.builder(
                    shrinkWrap: true,
                    itemCount: connectedDevices.length,
                    itemBuilder: (context, index) {
                      final device = connectedDevices[index];
                      return ListTile(
                        title: Text(device.productName),
                        subtitle: Text("Vendor ID: ${device.vendorId}"),
                        trailing: ElevatedButton(
                          onPressed: () {
                            _connectButtonPressed(device);
                            Navigator.pop(context);
                          },
                          child: const Text("اتصال"),
                        ),
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }

  String extractNumbersBetween(String input, String startChar, String endChar) {
    RegExp regExp = RegExp('$startChar(\\d+)$endChar');
    Match? match = regExp.firstMatch(input);
    return match != null ? match.group(1)! : '';
  }

  void _processReceivedMessage(String message) {
    if (message.startsWith("#") && message.endsWith("F")) {
      setState(() {
        receivedCommand = message;
      });

      String id = message.substring(1, 2);
      String relayNumber = message.substring(3, 4);
      String deviceType = message.substring(5, 6);
      String sourceId = extractNumbersBetween(message, 'C', 'D');
      String destinationId = extractNumbersBetween(message, 'D', 'E');
      String packetNumber = extractNumbersBetween(message, 'E', 'F');

      String powerStatus = (id == "1") ? "ON" : "OFF";
      int buttonNumber = int.parse(relayNumber);
      setState(() {
        buttonStates[buttonNumber] = (id == "1");
      });

      String status = """
    Power Status: $powerStatus
    Relay Number: $relayNumber
    Device Type: $deviceType
    Source ID: $sourceId
    Destination ID: $destinationId
    Packet Number: $packetNumber
    """;
      setState(() {
        statusController.text = status;
      });
    } else {
      setState(() {
        statusController.text = "Invalid message format!";
      });
    }
  }

  @override
  void dispose() {
    _cleanup();
    WidgetsBinding.instance.removeObserver(this); // حذف Observer
    messageController.dispose();
    commandController.dispose();
    statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);

    return MaterialApp(
      theme: _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      home: Scaffold(
        appBar: AppBar(
          toolbarHeight: 100,
          title: IconButton(
            icon: Image.asset('assets/icons/icon.png', width: 120, height: 120),
            onPressed: () {},
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (String value) {
                if (value == 'toggle_theme') {
                  _toggleDarkMode();
                }
              },
              itemBuilder:
                  (BuildContext context) => [
                    PopupMenuItem<String>(
                      value: 'toggle_theme',
                      child: Row(
                        children: [
                          Icon(
                            _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                            color: _isDarkMode ? Colors.amber : Colors.black,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isDarkMode ? 'حالت روشن' : 'حالت تاریک',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ],
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    const SizedBox(width: 8),
                    Text(
                      connectionProvider.isConnected
                          ? "وضعیت اتصال: روشن"
                          : "وضعیت اتصال: خاموش",
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            connectionProvider.isConnected
                                ? Colors.green
                                : Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(24),
                    backgroundColor:
                        connectionProvider.isConnected
                            ? Colors.red
                            : Colors.blue,
                  ),
                  onPressed:
                      connectionProvider.isConnected
                          ? _disconnectButtonPressed
                          : _getAllConnectedDevicesButtonPressed,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        connectionProvider.isConnected
                            ? Icons.link_off
                            : Icons.link,
                        size: 32,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        connectionProvider.isConnected ? "قطع اتصال" : "اتصال",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => LiveRoom()),
                    );
                  },
                  child: Text('برو به Liveroom'),
                ),
                if (connectionProvider.isConnected) ...[
                  ElevatedButton(onPressed: () {}, child: const Text("save")),
                  const Text(
                    "Command to send:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    controller: commandController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Command will be displayed here",
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _disconnectButtonPressed,
                    child: const Text("Disconnect"),
                  ),
                  const SizedBox(height: 16.0),
                  const Text(
                    "Status:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextField(
                    controller: statusController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Status will be displayed here",
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 16.0),
                  const Text(
                    "Received Messages:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: ListView.builder(
                      itemCount: receivedMessages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: SelectableText(
                            receivedMessages[index],
                            style: const TextStyle(fontSize: 14.0),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
