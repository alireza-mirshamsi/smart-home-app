import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:flutter_serial_communication/flutter_serial_communication.dart';

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
            while (true) {
              int endIndex = receivedBytesBuffer.indexOf(0x46);
              if (endIndex == -1) break;
              int startIndex = receivedBytesBuffer.lastIndexOf(0x23, endIndex);
              if (startIndex == -1) break;

              try {
                String message =
                    utf8
                        .decode(
                          receivedBytesBuffer.sublist(startIndex, endIndex + 1),
                        )
                        .trim();
                receivedBytesBuffer.removeRange(0, endIndex + 1);
                _processReceivedMessage(message);
                // Send data to main isolate
                FlutterForegroundTask.sendDataToMain({
                  'message': message,
                  'isConnected': isConnected,
                });
              } catch (e) {
                print("Error decoding message (SerialTaskHandler): $e");
                receivedBytesBuffer.removeRange(0, endIndex + 1);
              }
            }
          },
          onError: (error) {
            print("Error in message stream (SerialTaskHandler): $error");
            isConnected = false;
            FlutterForegroundTask.sendDataToMain({'isConnected': false});
          },
        );
  }

  Future<void> _checkAndConnectToDevice() async {
    List<DeviceInfo> devices =
        await _flutterSerialCommunicationPlugin.getAvailableDevices();
    if (devices.isNotEmpty && !isConnected) {
      bool isConnectionSuccess = await _flutterSerialCommunicationPlugin
          .connect(devices.first, 115200);
      isConnected = isConnectionSuccess;
      print(
        "Connection attempt (SerialTaskHandler): ${isConnectionSuccess ? 'Success' : 'Failed'}",
      );
      FlutterForegroundTask.sendDataToMain({
        'isConnected': isConnectionSuccess,
      });
    } else if (devices.isEmpty) {
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
      // Update DeviceProvider in background
      _updateDeviceState(receivedDeviceId, relayNumber, newState);
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

  Future<void> _updateDeviceState(
    String deviceId,
    int relayNumber,
    bool state,
  ) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? statusListJson = prefs.getString('relayStatus_$deviceId');
    Map<int, bool> buttonStates = {};

    if (statusListJson != null) {
      List<String> statusList = json.decode(statusListJson);
      buttonStates = {
        for (var state in statusList)
          int.parse(state.split(':')[0]): state.split(':')[1] == "ON",
      };
    }

    buttonStates[relayNumber] = state;

    List<String> updatedStatusList =
        buttonStates.entries
            .map((e) => '${e.key}:${e.value ? "ON" : "OFF"}')
            .toList();
    await prefs.setString(
      'relayStatus_$deviceId',
      json.encode(updatedStatusList),
    );
    print(
      "Saved button state to SharedPreferences: $deviceId, relay $relayNumber, state $state",
    );
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    await _initializeSerialConnection();
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
    isConnected = false;
  }

  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
    if (data is Map && data.containsKey('command')) {
      _handleCommand(data['command']);
    }
  }

  Future<void> _handleCommand(Map command) async {
    if (command['type'] == 'toggle') {
      String deviceId = command['deviceId'];
      int relayNumber = command['relayNumber'];
      bool newState = command['newState'];
      int packetNumber = command['packetNumber'];

      String stateDigit = newState ? "1" : "0";
      String cmd =
          "#${stateDigit}A${relayNumber}B7C7D${deviceId}E${packetNumber}F\n";
      bool sent = await _flutterSerialCommunicationPlugin.write(
        Uint8List.fromList(cmd.codeUnits),
      );
      if (sent) {
        print("Command sent (SerialTaskHandler): $cmd");
        _updateDeviceState(deviceId, relayNumber, newState);
      } else {
        print("Failed to send command (SerialTaskHandler): $cmd");
      }
    }
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
