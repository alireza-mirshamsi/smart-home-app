import 'package:flutter/material.dart';
import 'package:smart_home_app/core/services/serial_service.dart';
import 'package:flutter_serial_communication/models/device_info.dart';

class ConnectionProvider with ChangeNotifier {
  bool _isConnected = false;
  final SerialService _serialService = SerialService();

  bool get isConnected => _isConnected;

  ConnectionProvider() {
    _initialize();
  }

  void _initialize() {
    _serialService.getConnectionStatus().listen((status) {
      _isConnected = status;
      notifyListeners();
    });
    _connectToDevice();
  }

  Future<void> _connectToDevice() async {
    List<DeviceInfo> devices = await _serialService.getAvailableDevices();
    if (devices.isNotEmpty && !_isConnected) {
      bool success = await _serialService.connect(devices.first, 115200);
      if (success) {
        _isConnected = true;
        notifyListeners();
      }
    }
  }

  void setConnectionStatus(bool status) {
    _isConnected = status;
    notifyListeners();
  }
}
