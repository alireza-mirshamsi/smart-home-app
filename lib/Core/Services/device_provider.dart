import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceProvider with ChangeNotifier {
  Map<String, List<Map<String, String>>> _devicesByItem = {};

  List<Map<String, String>> getDevices(String itemName) => _devicesByItem[itemName] ?? [];

  int getTotalDevices() => _devicesByItem.values.fold(0, (sum, list) => sum + list.length);

  void addDevice(Map<String, String> device, String itemName) {
    if (!_devicesByItem.containsKey(itemName)) {
      _devicesByItem[itemName] = [];
    }
    if (!_devicesByItem[itemName]!.any((d) => d["deviceId"] == device["deviceId"])) {
      _devicesByItem[itemName]!.add(device);
      _saveDevicesToPrefs(itemName);
      notifyListeners();
    }
  }

  Future<void> loadDevicesFromPrefs(String itemName) async {
    final prefs = await SharedPreferences.getInstance();
    final String? devicesString = prefs.getString('devices_$itemName');
    if (devicesString != null) {
      _devicesByItem[itemName] = List<Map<String, String>>.from(
        json.decode(devicesString).map((item) => Map<String, String>.from(item)),
      );
      notifyListeners();
    } else {
      _devicesByItem[itemName] = [];
    }
  }

  Future<void> _saveDevicesToPrefs(String itemName) async {
    final prefs = await SharedPreferences.getInstance();
    final String devicesString = json.encode(_devicesByItem[itemName]);
    await prefs.setString('devices_$itemName', devicesString);
  }
}