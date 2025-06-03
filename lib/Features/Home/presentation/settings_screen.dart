import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Services/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات'),
        backgroundColor:
            themeProvider.isDarkMode ? Colors.grey[900] : Colors.amber[700],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تنظیمات برنامه',
                style: TextStyle(
                  fontSize: isTablet ? 28 : 24,
                  fontWeight: FontWeight.bold,
                  color:
                      themeProvider.isDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color:
                      themeProvider.isDarkMode
                          ? Colors.yellow[300]
                          : Colors.yellow[800],
                ),
                title: Text(
                  'حالت تاریک',
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 16,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[900],
                  ),
                ),
                trailing: Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (value) {
                    themeProvider.toggleTheme();
                  },
                  activeColor: Colors.yellow[700],
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  Icons.language,
                  color:
                      themeProvider.isDarkMode
                          ? Colors.yellow[300]
                          : Colors.yellow[800],
                ),
                title: Text(
                  'زبان',
                  style: TextStyle(
                    fontSize: isTablet ? 18 : 16,
                    color:
                        themeProvider.isDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[900],
                  ),
                ),
                subtitle: const Text('فارسی'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
