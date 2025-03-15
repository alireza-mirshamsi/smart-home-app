// lib/core/providers/connection_provider.dart
import 'package:flutter/material.dart';

class ConnectionProvider with ChangeNotifier {
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  void setConnectionStatus(bool status) {
    _isConnected = status;
    notifyListeners();
  }
}