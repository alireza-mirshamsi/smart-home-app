import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';
import 'package:smart_home_app/Core/config/app_theme.dart';
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
  List<Map<String, String>> devices = [];
  bool _isDarkMode = false; // متغیر برای تم تاریک/روشن

  @override
  void initState() {
    super.initState();
    Provider.of<DeviceProvider>(
      context,
      listen: false,
    ).loadDevicesFromPrefs(widget.itemName);
    _loadDevicesFromPrefs();
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
          ).setConnectionStatus(event);
        });
  }

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
    if (message.startsWith("#") &&
        message.contains("A") &&
        message.contains("B") &&
        message.contains("C")) {
      RegExp regex = RegExp(r"#(\d+)A(\d+)B6C");
      Match? match = regex.firstMatch(message);
      if (match != null) {
        String receivedDeviceId = match.group(1)!;
        String deviceTypeCode = match.group(2)!;

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
            Provider.of<DeviceProvider>(context, listen: false).addDevice({
              "name": "کلید چهار پل",
              "deviceId": receivedDeviceId,
              "image": "assets/4-pol.jpeg",
            }, widget.itemName);
          }
        });
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

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;
    final deviceProvider = Provider.of<DeviceProvider>(context);

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
              // هدر سفارشی
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
                          "${widget.itemName}",
                          style: TextStyle(
                            fontSize: isTablet ? 30 : 20,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 12),
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
              // محتوای اصلی
              Expanded(
                child:
                    deviceProvider.getDevices(widget.itemName).isEmpty
                        ? Center(
                          child: AnimatedOpacity(
                            opacity: 1.0,
                            duration: Duration(milliseconds: 500),
                            child: Container(
                              padding: EdgeInsets.all(24.0),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode
                                        ? Colors.grey[850]
                                        : Colors.grey[200],
                                borderRadius: BorderRadius.circular(16.0),
                                boxShadow: [
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
                                  Icon(
                                    Icons.device_unknown,
                                    size: 60,
                                    color:
                                        _isDarkMode
                                            ? Colors.yellow[300]
                                            : Colors.yellow[800],
                                  ),
                                  SizedBox(height: 16.0),
                                  Text(
                                    "هیچ دستگاهی یافت نشد",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          _isDarkMode
                                              ? Colors.yellow[300]
                                              : Colors.yellow[800],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 8.0),
                                  Text(
                                    "لطفاً دستگاه را متصل کنید یا دوباره تلاش کنید",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          _isDarkMode
                                              ? Colors.grey[500]
                                              : Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        : GridView.builder(
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _getCrossAxisCount(context),
                                crossAxisSpacing: 12.0,
                                mainAxisSpacing: 12.0,
                                childAspectRatio: 1.0,
                              ),
                          itemCount: deviceProvider.getDevices(widget.itemName).length,
                          itemBuilder: (context, index) {
                            final device = deviceProvider.getDevices(widget.itemName)[index];
                            return GestureDetector(
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
                              child: AnimatedContainer(
                                duration: Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  color:
                                      _isDarkMode
                                          ? Colors.grey[900]
                                          : Colors.white,
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          12.0,
                                        ),
                                        child: Image.asset(
                                          device["image"]!,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: EdgeInsets.all(8.0),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.black.withOpacity(0.7),
                                                Colors.transparent,
                                              ],
                                              begin: Alignment.bottomCenter,
                                              end: Alignment.topCenter,
                                            ),
                                            borderRadius: BorderRadius.vertical(
                                              bottom: Radius.circular(12.0),
                                            ),
                                          ),
                                          child: Text(
                                            device["name"]!,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                connectionProvider.isConnected
                                                    ? Colors.green
                                                    : Colors.red,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ), // فوتر
              Container(
                padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20.0),
                  ),
                  color: Colors.grey[200],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildButton(
                      context,
                      title: "فرستنده",
                      icon: Icons.send,
                      onPressed: _sendLearnCommand,
                      gradient: LinearGradient(
                        colors: [Colors.green[700]!, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    _buildButton(
                      context,
                      title: "گیرنده",
                      icon: Icons.call_received,
                      onPressed: _sendTransCommand,
                      gradient: LinearGradient(
                        colors: [Colors.blue[700]!, Colors.blue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 600)
      return 4;
    else if (screenWidth > 400)
      return 3;
    else
      return 2;
  }

  Widget _buildButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
    required LinearGradient gradient,
  }) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: Colors.white),
        label: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 6,
          backgroundColor: Colors.transparent,
          shadowColor: Colors.black26,
          foregroundColor: Colors.white.withOpacity(0.9),
        ).copyWith(
          backgroundColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (states.contains(MaterialState.pressed))
              return gradient.colors[1].withOpacity(0.8);
            return Colors.transparent;
          }),
        ),
      ),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: gradient.colors[1].withOpacity(0.4),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
    );
  }
}
