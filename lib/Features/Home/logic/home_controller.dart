import 'package:smart_home_app/Core/Services/serial_service.dart';
import 'package:smart_home_app/features/home/data/models/smart_device_model.dart';
import 'package:flutter_serial_communication/models/device_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeController {
  final SerialService _serialService;
  List<SmartDeviceModel> smartDevices = [
    SmartDeviceModel(name: "تاچ 1", iconPath: "assets/lightbulb.png"),
    SmartDeviceModel(name: "تاچ 2", iconPath: "assets/lightbulb.png"),
    SmartDeviceModel(name: "تاچ 3", iconPath: "assets/lightbulb.png"),
    SmartDeviceModel(name: "تاچ 4", iconPath: "assets/lightbulb.png"),
  ];
  Map<int, bool> buttonStates = {};
  int packetNumber = 0;
  List<DeviceInfo> connectedDevices = [];

  HomeController(this._serialService);

  Future<void> fetchConnectedDevices() async {
    connectedDevices = await _serialService.getAvailableDevices();
  }

  Future<void> connectToDevice(DeviceInfo device) async {
    await _serialService.connect(device, 115200);
  }

  void toggleDevice(int index, bool newValue) async {
    final device = smartDevices[index];
    final buttonNumber = index + 1;
    final currentState = buttonStates[buttonNumber] ?? false;
    final stateDigit = currentState ? "0" : "1"; // Toggle state

    String command =
        "#${stateDigit}A${buttonNumber}B6C7D2555957E${packetNumber}F\n";
    await _serialService.write(command);

    device.isOn = !currentState;
    buttonStates[buttonNumber] = !currentState;
    packetNumber++;

    await _saveRelayStatus(buttonNumber, device.isOn ? "ON" : "OFF");
  }

  Future<void> _saveRelayStatus(int relayNumber, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final statusList = prefs.getStringList('relayStatus') ?? [];
    final entry = "$relayNumber:$status";
    if (!statusList.contains(entry)) {
      statusList.add(entry);
      await prefs.setStringList('relayStatus', statusList);
    }
  }
}
