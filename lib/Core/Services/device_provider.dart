import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceProvider with ChangeNotifier {
  Map<String, List<Map<String, String>>> _devicesByItem = {};
  Map<String, Map<int, bool>> _buttonStates = {};
  Map<String, Map<int, int>> _lastPacketNumbers = {};

  List<Map<String, String>> getDevices(String itemName) =>
      _devicesByItem[itemName] ?? [];

  Map<int, bool> getButtonStates(String deviceId) =>
      _buttonStates[deviceId] ?? {};

  int getTotalDevices() =>
      _devicesByItem.values.fold(0, (sum, list) => sum + list.length);

  void syncStateFromMessage(String message, String deviceId) {
    try {
      RegExp regex = RegExp(r"#(\d)A(\d+)B(\d+)C(\d+)D([^E]+)E(\d+)F");
      Match? match = regex.firstMatch(message);

      if (match != null && match.group(4) == deviceId) {
        bool newState = match.group(1) == "1";
        int relayNumber = int.parse(match.group(2)!);
        updateButtonState(deviceId, relayNumber, newState);
      }
    } catch (e) {
      debugPrint("Error parsing message: $e");
    }
  }

  void addDevice(Map<String, String> device, String itemName) {
    if (!_devicesByItem.containsKey(itemName)) {
      _devicesByItem[itemName] = [];
    }
    if (!_devicesByItem[itemName]!.any(
      (d) => d["deviceId"] == device["deviceId"],
    )) {
      _devicesByItem[itemName]!.add(device);
      _saveDevicesToPrefs(itemName);
      notifyListeners();
    }
  }

  void updateButtonState(String deviceId, int relayNumber, bool state) {
    _buttonStates[deviceId] ??= {};
    _buttonStates[deviceId]![relayNumber] = state;
    _saveButtonStatesToPrefs(deviceId);
    notifyListeners();
  }

  int getLastPacketNumber(String deviceId, int relayNumber) {
    _lastPacketNumbers[deviceId] ??= {};
    return _lastPacketNumbers[deviceId]![relayNumber] ?? 0;
  }

  void updateLastPacketNumber(
    String deviceId,
    int relayNumber,
    int packetNumber,
  ) {
    _lastPacketNumbers[deviceId] ??= {};
    _lastPacketNumbers[deviceId]![relayNumber] = packetNumber;
    _savePacketNumbersToPrefs(deviceId);
    notifyListeners();
  }

  Future<void> loadDevicesFromPrefs(String itemName) async {
    final prefs = await SharedPreferences.getInstance();
    final String? devicesString = prefs.getString('devices_$itemName');
    if (devicesString != null) {
      _devicesByItem[itemName] = List<Map<String, String>>.from(
        json
            .decode(devicesString)
            .map((item) => Map<String, String>.from(item)),
      );
      notifyListeners();
    } else {
      _devicesByItem[itemName] = [];
    }
  }

  Future<void> loadButtonStatesFromPrefs(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? statusList = prefs.getString('relayStatus_$deviceId');
    if (statusList != null) {
      List<String> states = json.decode(statusList);
      _buttonStates[deviceId] = {
        for (var state in states)
          int.parse(state.split(':')[0]): state.split(':')[1] == "ON",
      };
      notifyListeners();
    }
  }

  Future<void> loadPacketNumbersFromPrefs(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? packetNumbersString = prefs.getString(
      'packetNumbers_$deviceId',
    );
    if (packetNumbersString != null) {
      final Map<String, dynamic> packetNumbersMap = json.decode(
        packetNumbersString,
      );
      _lastPacketNumbers[deviceId] = packetNumbersMap.map(
        (key, value) => MapEntry(int.parse(key), value as int),
      );
      notifyListeners();
    }
  }

  Future<void> _saveDevicesToPrefs(String itemName) async {
    final prefs = await SharedPreferences.getInstance();
    final String devicesString = json.encode(_devicesByItem[itemName]);
    await prefs.setString('devices_$itemName', devicesString);
  }

  Future<void> _saveButtonStatesToPrefs(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> statusList =
        _buttonStates[deviceId]!.entries
            .map((e) => '${e.key}:${e.value ? "ON" : "OFF"}')
            .toList();
    await prefs.setString('relayStatus_$deviceId', json.encode(statusList));
  }

  Future<void> _savePacketNumbersToPrefs(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final String packetNumbersString = json.encode(
      _lastPacketNumbers[deviceId],
    );
    await prefs.setString('packetNumbers_$deviceId', packetNumbersString);
  }

  Map<String, String> getDeviceById(String deviceId, String itemName) {
    final devices = getDevices(itemName);
    return devices.firstWhere(
      (device) => device["deviceId"] == deviceId,
      orElse: () => {},
    );
  }
}
