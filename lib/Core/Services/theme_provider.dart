import 'package:flutter/material.dart';
import 'package:smart_home_app/Core/config/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  ThemeData get currentTheme =>
      _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners(); // اطلاع‌رسانی به همه ویجت‌هایی که به این Provider گوش می‌دهند
  }
}
