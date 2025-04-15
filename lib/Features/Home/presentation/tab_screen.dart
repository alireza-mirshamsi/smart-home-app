import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';
import 'package:smart_home_app/Core/Services/serial_service.dart';
import 'package:smart_home_app/Core/Services/theme_provider.dart';
import 'package:smart_home_app/Features/Home/presentation/manage_device.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class TabScreen extends StatefulWidget {
  final String itemName;

  const TabScreen({required this.itemName});

  @override
  _TabScreenState createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> with WidgetsBindingObserver {
  final SerialService _serialService = SerialService();
  List<int> receivedBytesBuffer = [];
  List<String> receivedMessages = [];
  String deviceId = '';
  List<Map<String, String>> devices = [];
  bool _isLearning = false;
  StreamSubscription? _serialSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Provider.of<DeviceProvider>(
      context,
      listen: false,
    ).loadDevicesFromPrefs(widget.itemName);
    _loadDevicesFromPrefs();
    _checkAndConnectToDevice();
    _setupSerialListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("Lifecycle State (TabScreen): $state");
    if (state == AppLifecycleState.resumed) {
      _checkAndConnectToDevice();
      _setupSerialListener();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _serialSubscription?.cancel();
    }
  }

  void _setupSerialListener() {
    _serialSubscription?.cancel();
    _serialSubscription = _serialService.getSerialMessages().listen((event) {
      receivedBytesBuffer.addAll(event);
      int endIndex = receivedBytesBuffer.indexOf(0x46);
      if (endIndex != -1) {
        int startIndex = receivedBytesBuffer.lastIndexOf(0x23, endIndex);
        if (startIndex != -1) {
          String message =
              utf8
                  .decode(receivedBytesBuffer.sublist(startIndex, endIndex + 1))
                  .trim();
          receivedBytesBuffer.removeRange(0, endIndex + 1);
          debugPrint("پیام دریافتی (TabScreen): $message");
          setState(() {
            receivedMessages.add(message);
            _processReceivedMessage(message);
          });
        }
      }
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
    List<DeviceInfo> devices = await _serialService.getAvailableDevices();
    if (devices.isNotEmpty) {
      bool isConnectionSuccess = await _serialService.connect(
        devices.first,
        115200,
      );
      if (isConnectionSuccess) {
        Provider.of<ConnectionProvider>(
          context,
          listen: false,
        ).setConnectionStatus(true);
        debugPrint("اتصال به دستگاه ${devices.first.deviceName} برقرار شد");
      } else {
        debugPrint("اتصال به دستگاه ناموفق بود");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("اتصال به دستگاه ناموفق بود")),
        );
      }
    } else {
      debugPrint("هیچ دستگاهی یافت نشد");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("هیچ دستگاهی یافت نشد")));
    }
  }

  void _processReceivedMessage(String message) {
    RegExp regex = RegExp(r"#(\d+)A(\d+)B(\d+)C(\d+)D(\d+)E(\d+)F");
    Match? match = regex.firstMatch(message);
    if (match != null) {
      String stateCode = match.group(1)!;
      String buttonCode = match.group(2)!;
      String deviceInfo = match.group(3)!;
      String receivedDeviceId = match.group(4)!;

      if (_isLearning) {
        String deviceName;
        String deviceImage;
        int poleCount = 0;
        switch (deviceInfo) {
          case "64":
            deviceName = "کلید لمسی 4 پل";
            deviceImage = "assets/4-pol.png";
            poleCount = 4;
            break;
          case "63":
            deviceName = "کلید لمسی 3 پل";
            deviceImage = "assets/3-pol.png";
            poleCount = 3;
            break;
          case "62":
            deviceName = "کلید لمسی 2 پل";
            deviceImage = "assets/2-pol.png";
            poleCount = 2;
            break;
          case "61":
            deviceName = "کلید لمسی 1 پل";
            deviceImage = "assets/1-pol.png";
            poleCount = 1;
            break;
          default:
            deviceName = "دستگاه ناشناخته";
            deviceImage = "assets/1-pol.png";
            poleCount = 1;
            break;
        }

        setState(() {
          deviceId = receivedDeviceId;
          Provider.of<DeviceProvider>(context, listen: false).addDevice({
            "name": deviceName,
            "deviceId": receivedDeviceId,
            "image": deviceImage,
            "poleCount": poleCount.toString(),
            "deviceInfo": deviceInfo,
          }, widget.itemName);
          debugPrint("Device added: $deviceName with ID $receivedDeviceId");
        });
      } else {
        bool newState = stateCode == "1";
        int relayNumber = int.parse(buttonCode);
        Provider.of<DeviceProvider>(
          context,
          listen: false,
        ).updateButtonState(receivedDeviceId, relayNumber, newState);
        debugPrint(
          "وضعیت تاچ به‌روزرسانی شد: $receivedDeviceId, رله $relayNumber, حالت $newState",
        );
      }
    }
  }

  _sendLearnCommand() async {
    final connectionProvider = Provider.of<ConnectionProvider>(
      context,
      listen: false,
    );
    if (!connectionProvider.isConnected) {
      await _checkAndConnectToDevice();
      if (!connectionProvider.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("لطفاً ابتدا دستگاه را متصل کنید")),
        );
        return;
      }
    }

    String command = "LEARN\r";
    bool isMessageSent = await _serialService.write(command);
    debugPrint("Is LEARN Command Sent: $isMessageSent");
    if (!isMessageSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ارسال دستور LEARN ناموفق بود")),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("دستگاه در حال شناسایی...")));
      setState(() {
        _isLearning = true;
      });
      await Future.delayed(const Duration(seconds: 5), () {
        setState(() {
          _isLearning = false;
        });
        debugPrint("LEARN mode disabled");
      });
    }
  }

  _sendTransCommand() async {
    String command = "TRANS\r";
    bool isMessageSent = await _serialService.write(command);
    debugPrint("Is TRANS Command Sent: $isMessageSent");
  }

  void _toggleDarkMode() {
    Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
  }

  @override
  void dispose() {
    _serialSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = Provider.of<ConnectionProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final deviceProvider = Provider.of<DeviceProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors:
                      themeProvider.isDarkMode
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
                        widget.itemName,
                        style: TextStyle(
                          fontSize: isTablet ? 30 : 20,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                          themeProvider.isDarkMode
                              ? Icons.light_mode
                              : Icons.dark_mode,
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
                                      themeProvider.isDarkMode
                                          ? Icons.light_mode
                                          : Icons.dark_mode,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.yellow[300]
                                              : Colors.yellow[800],
                                    ),
                                    SizedBox(width: isTablet ? 10 : 8),
                                    Text(
                                      themeProvider.isDarkMode
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
            Expanded(
              child:
                  deviceProvider.getDevices(widget.itemName).isEmpty
                      ? Center(
                        child: AnimatedOpacity(
                          opacity: 1.0,
                          duration: const Duration(milliseconds: 500),
                          child: Container(
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
                                Icon(
                                  Icons.device_unknown,
                                  size: 60,
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.yellow[300]
                                          : Colors.yellow[800],
                                ),
                                const SizedBox(height: 16.0),
                                Text(
                                  "هیچ دستگاهی یافت نشد",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.yellow[300]
                                            : Colors.yellow[800],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8.0),
                                Text(
                                  "لطفاً دستگاه را متصل کنید یا دوباره تلاش کنید",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        themeProvider.isDarkMode
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
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _getCrossAxisCount(context),
                          crossAxisSpacing: 12.0,
                          mainAxisSpacing: 12.0,
                          childAspectRatio: 1.0,
                        ),
                        itemCount:
                            deviceProvider.getDevices(widget.itemName).length,
                        itemBuilder: (context, index) {
                          final device =
                              deviceProvider.getDevices(widget.itemName)[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ManageDevice(
                                        deviceId: device["deviceId"]!,
                                        deviceInfo: device["deviceInfo"]!,
                                        itemName: widget.itemName,
                                      ),
                                ),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                color:
                                    themeProvider.isDarkMode
                                        ? Colors.grey[900]
                                        : Colors.white,
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12.0),
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
                                        padding: const EdgeInsets.all(8.0),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.black.withOpacity(0.7),
                                              Colors.transparent,
                                            ],
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                bottom: Radius.circular(12.0),
                                              ),
                                        ),
                                        child: Text(
                                          device["name"]!,
                                          style: const TextStyle(
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
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 16.0,
                horizontal: 16.0,
              ),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
                color: Colors.grey,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildButton(
                    context,
                    title: "گیرنده با واسطه",
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
                    title: "فرستنده",
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
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: Colors.white),
        label: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}
