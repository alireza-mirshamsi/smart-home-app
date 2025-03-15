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
import 'package:shamsi_date/shamsi_date.dart';

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
  late Timer _timer;
  String _currentTime = DateTime.now().toString().substring(11, 19);
  String _currentDate =
      Jalali.now().formatter.wN +
      '، ' +
      Jalali.now().day.toString() +
      ' ' +
      Jalali.now().formatter.mN +
      ' ' +
      Jalali.now().year.toString();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // اضافه کردن Observer
    _initializeSerialConnection();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now().toString().substring(11, 19);
        _currentDate =
            Jalali.now().formatter.wN +
            '، ' +
            Jalali.now().day.toString() +
            ' ' +
            Jalali.now().formatter.mN +
            ' ' +
            Jalali.now().year.toString();
      });
    });
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
    _timer.cancel();
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
    // اندازه صفحه برای طراحی واکنش‌گرا
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600; // تشخیص تبلت یا گوشی

    return MaterialApp(
      theme: _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
      locale: const Locale("fa", ""),
      localizationsDelegates: AppLocalization.localizationsDelegates,
      supportedLocales: AppLocalization.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            // پس‌زمینه با تم زرد
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: isTablet ? 2.5 : 1.5, // افزایش شعاع برای تبلت
                  stops: const [0.0, 0.5, 1.0], // نقاط توقف برای پخش بهتر
                  colors:
                      _isDarkMode
                          ? [
                            Colors.grey[900]!,
                            Colors.grey[800]!.withOpacity(
                              0.8,
                            ), // رنگ میانی برای عمق
                            Colors.grey[800]!.withOpacity(0.8), // پخش نرم‌تر
                          ]
                          : [
                            Colors.yellow[300]!.withOpacity(0.95),
                            Colors.yellow[100]!.withOpacity(
                              0.7,
                            ), // رنگ میانی برای تبلت
                            Colors.white.withOpacity(0.4), // پایان نرم‌تر
                          ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // هدر
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 24.0 : 16.0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Image.asset(
                          'assets/icons/icon.png',
                          width: isTablet ? 100 : 125,
                          height: isTablet ? 100 : 125,
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.settings,
                                color:
                                    _isDarkMode
                                        ? Colors.yellow[300]
                                        : Colors.yellow[800],
                                size: isTablet ? 28 : 24,
                              ),
                              onPressed: () {
                                // رفتن به صفحه تنظیمات
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                _isDarkMode
                                    ? Icons.light_mode
                                    : Icons.dark_mode,
                                color:
                                    _isDarkMode
                                        ? Colors.yellow[300]
                                        : Colors.yellow[800],
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
                                            style: TextStyle(
                                              fontSize: isTablet ? 16 : 14,
                                              color:
                                                  _isDarkMode
                                                      ? Colors.white
                                                      : Colors.black,
                                            ),
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
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 30.0 : 20.0,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: isTablet ? 20 : 10),
                            // ساعت و تاریخ
                            Container(
                              padding: EdgeInsets.all(
                                isTablet ? 24.0 : 16.0,
                              ), // کاهش padding برای تعادل
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode
                                        ? Colors.grey[850]
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(
                                  isTablet ? 20 : 16,
                                ), // گوشه‌های کمی کوچکتر
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(
                                      _isDarkMode ? 0.3 : 0.15,
                                    ),
                                    blurRadius: isTablet ? 12 : 8,
                                    offset: const Offset(0, 4),
                                    spreadRadius:
                                        1, // اضافه کردن spread برای سایه نرم‌تر
                                  ),
                                ],
                                border: Border.all(
                                  color: Colors.yellow[700]!,
                                  width:
                                      1.5, // ضخامت حاشیه کمی بیشتر برای جلوه بهتر
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors:
                                      _isDarkMode
                                          ? [
                                            Colors.grey[850]!,
                                            Colors.grey[900]!.withOpacity(0.9),
                                          ]
                                          : [
                                            Colors.white,
                                            Colors.yellow[50]!.withOpacity(0.5),
                                          ], // گرادیانت ظریف داخل کارت
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons
                                            .watch_later_rounded, // آیکون مدرن‌تر
                                        color:
                                            _isDarkMode
                                                ? Colors.yellow[300]
                                                : Colors.yellow[800],
                                        size:
                                            isTablet
                                                ? 36
                                                : 28, // اندازه آیکون متعادل‌تر
                                      ),
                                      SizedBox(width: isTablet ? 12 : 8),
                                      Text(
                                        _currentTime,
                                        style: TextStyle(
                                          fontSize:
                                              isTablet
                                                  ? 48
                                                  : 36, // کاهش اندازه فونت برای تبلت
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _isDarkMode
                                                  ? Colors.yellow[300]
                                                  : Colors.yellow[900],
                                          letterSpacing: 1.2,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withOpacity(
                                                0.2,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(1, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: isTablet ? 12 : 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          _isDarkMode
                                              ? Colors.grey[900]
                                              : Colors.yellow[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _currentDate,
                                      style: TextStyle(
                                        fontSize:
                                            isTablet
                                                ? 18
                                                : 14, // کاهش اندازه فونت تاریخ
                                        color:
                                            _isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isTablet ? 50 : 30),
                            // پیام خوش‌آمدگویی
                            Text(
                              'خوش آمدید به اسمارت‌هوم',
                              style: TextStyle(
                                fontSize: isTablet ? 36 : 28,
                                fontWeight: FontWeight.bold,
                                color:
                                    _isDarkMode
                                        ? Colors.grey[300]
                                        : Colors.grey[900],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 15 : 10),
                            Text(
                              'خانه هوشمند خود را به‌راحتی مدیریت کنید',
                              style: TextStyle(
                                fontSize: isTablet ? 18 : 14,
                                color:
                                    _isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isTablet ? 50 : 30),
                            // کارت وضعیت اتصال
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 25 : 20,
                                vertical: isTablet ? 15 : 12,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode
                                        ? Colors.grey[850]
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(
                                  isTablet ? 20 : 15,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: isTablet ? 10 : 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    connectionProvider.isConnected
                                        ? Icons.wifi
                                        : Icons.wifi_off,
                                    color:
                                        connectionProvider.isConnected
                                            ? Colors.green
                                            : Colors.red,
                                    size: isTablet ? 28 : 24,
                                  ),
                                  SizedBox(width: isTablet ? 12 : 10),
                                  Text(
                                    connectionProvider.isConnected
                                        ? 'متصل'
                                        : 'اتصال قطع است',
                                    style: TextStyle(
                                      fontSize: isTablet ? 20 : 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          connectionProvider.isConnected
                                              ? Colors.green
                                              : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isTablet ? 50 : 30),
                            // دکمه اصلی برای مدیریت دستگاه‌ها
                            ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LiveRoom(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 70 : 50,
                                  vertical: isTablet ? 20 : 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    isTablet ? 50 : 30,
                                  ),
                                ),
                                backgroundColor:
                                    _isDarkMode
                                        ? Colors.yellow[700]
                                        : Colors.grey[700],
                                elevation: isTablet ? 10 : 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'مدیریت دستگاه‌ها',
                                    style: TextStyle(
                                      fontSize: isTablet ? 24 : 18,
                                      color:
                                          _isDarkMode
                                              ? Colors.grey[900]
                                              : Colors.amber,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: isTablet ? 15 : 10),
                                  Container(
                                    padding: EdgeInsets.all(isTablet ? 8 : 6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          _isDarkMode
                                              ? Colors.grey[900]
                                              : Colors.amber,
                                    ),
                                    child: Icon(
                                      Icons.arrow_forward,
                                      size: isTablet ? 24 : 20,
                                      color:
                                          _isDarkMode
                                              ? Colors.yellow[700]
                                              : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isTablet ? 50 : 30),
                            // اطلاعات اضافی
                            Container(
                              padding: EdgeInsets.all(isTablet ? 15 : 12),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode
                                        ? Colors.grey[850]
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(
                                  isTablet ? 15 : 12,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: isTablet ? 10 : 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.devices,
                                    size: isTablet ? 24 : 20,
                                    color:
                                        _isDarkMode
                                            ? Colors.yellow[300]
                                            : Colors.yellow[800],
                                  ),
                                  SizedBox(width: isTablet ? 10 : 8),
                                  Text(
                                    'دستگاه‌های متصل: ${connectedDevices.length}',
                                    style: TextStyle(
                                      fontSize: isTablet ? 18 : 14,
                                      color:
                                          _isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: isTablet ? 30 : 20),
                          ],
                        ),
                      ),
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

  Widget _buildQuickActionCard(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isTablet ? 120 : 80,
        height: isTablet ? 120 : 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isDarkMode ? Colors.grey[800] : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: isTablet ? 8 : 6,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: isTablet ? 40 : 30,
              color: _isDarkMode ? Colors.yellow[300] : Colors.yellow[800],
            ),
            SizedBox(height: isTablet ? 8 : 4),
            Text(
              title,
              style: TextStyle(
                fontSize: isTablet ? 16 : 12,
                color: _isDarkMode ? Colors.white : Colors.black,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
