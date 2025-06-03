import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:smart_home_app/Core/Services/connection_provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';
import 'package:smart_home_app/Core/Services/theme_provider.dart';
import 'package:smart_home_app/Features/Home/presentation/live_room.dart';
import 'package:smart_home_app/Features/Home/presentation/settings_screen.dart';
import 'package:smart_home_app/Features/Home/presentation/scenarios_screen.dart';
import 'package:shamsi_date/shamsi_date.dart';

// Callback function for foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SerialTaskHandler());
}

class SerialTaskHandler extends TaskHandler {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  StreamSubscription? _messageSubscription;
  List<int> receivedBytesBuffer = [];
  bool isConnected = false;

  Future<void> _initializeSerialConnection() async {
    await _checkAndConnectToDevice();

    _messageSubscription?.cancel();
    _messageSubscription = _flutterSerialCommunicationPlugin
        .getSerialMessageListener()
        .receiveBroadcastStream()
        .listen(
          (event) {
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
                _processReceivedMessage(message);
                // Send data to main isolate
                FlutterForegroundTask.sendDataToMain({'message': message});
              }
            }
          },
          onError: (error) {
            print("Error in message stream (SerialTaskHandler): $error");
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
        isConnected = true;
        FlutterForegroundTask.sendDataToMain({'isConnected': true});
        print("Connected to device: ${devices.first.deviceName}");
      } else {
        isConnected = false;
        FlutterForegroundTask.sendDataToMain({'isConnected': false});
        print("Failed to connect to device (SerialTaskHandler)");
      }
    } else {
      isConnected = false;
      FlutterForegroundTask.sendDataToMain({'isConnected': false});
      print("No devices found (SerialTaskHandler)");
    }
  }

  void _processReceivedMessage(String message) {
    RegExp regex = RegExp(r"#(\d)A(\d+)B(\d+)C(\d+)D(\d+)E(\d+)F");
    Match? match = regex.firstMatch(message);
    if (match != null) {
      bool newState = match.group(1) == "1";
      int relayNumber = int.parse(match.group(2)!);
      String receivedDeviceId = match.group(4)!;
      FlutterForegroundTask.sendDataToMain({
        'deviceUpdate': {
          'deviceId': receivedDeviceId,
          'relayNumber': relayNumber,
          'newState': newState,
        },
      });
      print(
        "Updated touch state (SerialTaskHandler): $receivedDeviceId, relay $relayNumber, state $newState",
      );
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    await _initializeSerialConnection();
    // Update notification
    FlutterForegroundTask.updateService(
      notificationTitle: 'Smart Home Service',
      notificationText: 'Serial communication is running',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!isConnected) {
      _initializeSerialConnection();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('onDestroy(isTimeout: $isTimeout)');
    _messageSubscription?.cancel();
    await _flutterSerialCommunicationPlugin.disconnect();
  }

  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed: $id');
  }

  @override
  void onNotificationPressed() {
    print('onNotificationPressed');
    FlutterForegroundTask.launchApp();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _flutterSerialCommunicationPlugin = FlutterSerialCommunication();
  List<DeviceInfo> connectedDevices = [];
  List<String> receivedMessages = [];
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
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeForegroundTask();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
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
      }
    });
    Provider.of<DeviceProvider>(
      context,
      listen: false,
    ).loadDevicesFromPrefs('default_item');
  }

  Future<void> _requestPermissions() async {
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  void _initializeForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'smart_home_service',
        channelName: 'Smart Home Service Notification',
        channelDescription:
            'This notification appears when the smart home service is running.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    _requestPermissions();
    _startService();
  }

  Future<ServiceRequestResult> _startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    } else {
      return FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Smart Home Service is running',
        notificationText: 'Tap to return to the app',
        notificationIcon: null,
        callback: startCallback,
      );
    }
  }

  Future<ServiceRequestResult> _stopService() {
    return FlutterForegroundTask.stopService();
  }

  void _onReceiveTaskData(Object data) {
    print('onReceiveTaskData: $data');
    if (data is Map) {
      if (data.containsKey('isConnected')) {
        Provider.of<ConnectionProvider>(
          context,
          listen: false,
        ).setConnectionStatus(data['isConnected']);
      }
      if (data.containsKey('message')) {
        setState(() {
          receivedMessages.add(data['message']);
        });
      }
      if (data.containsKey('deviceUpdate')) {
        var update = data['deviceUpdate'];
        Provider.of<DeviceProvider>(context, listen: false).updateButtonState(
          update['deviceId'],
          update['relayNumber'],
          update['newState'],
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint("Lifecycle State (HomeScreen): $state");
    if (state == AppLifecycleState.resumed) {
      _startService();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Service continues running in the background
    }
  }

  void _toggleDarkMode() {
    Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
  }

  Future<void> _getAllConnectedDevicesButtonPressed() async {
    List<DeviceInfo> newConnectedDevices =
        await _flutterSerialCommunicationPlugin.getAvailableDevices();
    setState(() {
      connectedDevices = newConnectedDevices;
    });
    _showConnectedDevicesSheet();
  }

  Future<void> _connectButtonPressed(DeviceInfo deviceInfo) async {
    bool isConnectionSuccess = await _flutterSerialCommunicationPlugin.connect(
      deviceInfo,
      115200,
    );
    debugPrint("Is Connection Success (HomeScreen): $isConnectionSuccess");
    if (isConnectionSuccess) {
      Provider.of<ConnectionProvider>(
        context,
        listen: false,
      ).setConnectionStatus(true);
    }
  }

  Future<void> _disconnectButtonPressed() async {
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
                        fontFamily: 'iransans',
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _getSelectedScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeScreen();
      case 1:
        return const LiveRoom(itemName: 'default_item');
      case 2:
        return const SettingsScreen();
      case 3:
        return const ScenariosScreen();
      default:
        return _buildHomeScreen();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _buildHomeScreen() {
    final connectionProvider = Provider.of<ConnectionProvider>(context);
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 24.0 : 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset(
                  'assets/icons/icon.png',
                  width: isTablet ? 80 : 120,
                  height: isTablet ? 80 : 120,
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.yellow[300]
                                : Colors.yellow[800],
                        size: isTablet ? 28 : 24,
                      ),
                      onPressed: () => _onItemTapped(2),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        themeProvider.isDarkMode
                            ? Icons.light_mode
                            : Icons.dark_mode,
                        color:
                            themeProvider.isDarkMode
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
                                    style: TextStyle(
                                      fontSize: isTablet ? 16 : 14,
                                      color:
                                          themeProvider.isDarkMode
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
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 30.0 : 20.0),
              child:
                  isTablet
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: screenWidth * 0.35,
                                height: screenHeight * 0.35,
                                padding: EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[850]
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors:
                                        themeProvider.isDarkMode
                                            ? [
                                              Colors.grey[850]!,
                                              Colors.grey[900]!.withOpacity(
                                                0.8,
                                              ),
                                            ]
                                            : [
                                              Colors.white,
                                              Colors.yellow[100]!.withOpacity(
                                                0.7,
                                              ),
                                            ],
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.watch_later_rounded,
                                          color:
                                              themeProvider.isDarkMode
                                                  ? Colors.yellow[300]
                                                  : Colors.yellow[800],
                                          size: 32,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          _currentTime,
                                          style: TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.w800,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.yellow[300]
                                                    : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          color:
                                              themeProvider.isDarkMode
                                                  ? Colors.yellow[300]
                                                  : Colors.yellow[800],
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          _currentDate,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.grey[400]
                                                    : Colors.grey[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20),
                              Column(
                                children: [
                                  Text(
                                    'خوش آمدید به اسمارت‌هوم',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.grey[300]
                                              : Colors.grey[900],
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'خانه هوشمند خود را به‌راحتی مدیریت کنید',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[850]
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
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
                                      size: 24,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      connectionProvider.isConnected
                                          ? 'متصل'
                                          : 'اتصال قطع است',
                                      style: TextStyle(
                                        fontSize: 18,
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
                              SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: () => _onItemTapped(1),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 40,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  backgroundColor:
                                      themeProvider.isDarkMode
                                          ? Colors.yellow[700]
                                          : Colors.grey[700],
                                  elevation: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'مدیریت دستگاه‌ها',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.grey[900]
                                                : Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.grey[900]
                                                : Colors.amber,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward,
                                        size: 20,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.yellow[700]
                                                : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20),
                              Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[850]
                                          : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.devices,
                                      size: 20,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.yellow[300]
                                              : Colors.yellow[800],
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'دستگاه‌های متصل: ${deviceProvider.getTotalDevices()}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                      : Column(
                        children: [
                          SizedBox(height: 10),
                          Container(
                            constraints: BoxConstraints(
                              maxWidth: double.infinity,
                            ),
                            padding: EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors:
                                    themeProvider.isDarkMode
                                        ? [
                                          Colors.grey[850]!,
                                          Colors.grey[900]!.withOpacity(0.8),
                                        ]
                                        : [
                                          Colors.white,
                                          Colors.yellow[100]!.withOpacity(0.7),
                                        ],
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.watch_later_rounded,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.yellow[300]
                                              : Colors.yellow[800],
                                      size: 28,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      _currentTime,
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.yellow[300]
                                                : Colors.yellow[900],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      color:
                                          themeProvider.isDarkMode
                                              ? Colors.yellow[300]
                                              : Colors.yellow[800],
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      _currentDate,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            themeProvider.isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey[800],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 25),
                          Text(
                            'خوش آمدید به اسمارت‌هوم',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[300]
                                      : Colors.grey[900],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'خانه هوشمند خود را به‌راحتی مدیریت کنید',
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 25),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
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
                                  size: 24,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  connectionProvider.isConnected
                                      ? 'متصل'
                                      : 'اتصال قطع است',
                                  style: TextStyle(
                                    fontSize: 16,
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
                          SizedBox(height: 25),
                          ElevatedButton(
                            onPressed: () => _onItemTapped(1),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: 40,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              backgroundColor:
                                  themeProvider.isDarkMode
                                      ? Colors.yellow[700]
                                      : Colors.grey[700],
                              elevation: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'مدیریت دستگاه‌ها',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.grey[900]
                                            : Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Container(
                                  padding: EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.grey[900]
                                            : Colors.amber,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward,
                                    size: 20,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.yellow[700]
                                            : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  themeProvider.isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.devices,
                                  size: 20,
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.yellow[300]
                                          : Colors.yellow[800],
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'دستگاه‌های متصل: ${deviceProvider.getTotalDevices()}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.grey[400]
                                            : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: Scaffold(
        body: _getSelectedScreen(),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'خانه'),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices),
              label: 'اتاق کنترل',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'تنظیمات',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.rule), label: 'سناریوها'),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}
