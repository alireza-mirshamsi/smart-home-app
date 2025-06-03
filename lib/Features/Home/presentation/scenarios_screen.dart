import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Services/theme_provider.dart';

class ScenariosScreen extends StatelessWidget {
  const ScenariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سناریوها'),
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
                'مدیریت سناریوها',
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
              Expanded(
                child: Center(
                  child: Text(
                    'در حال حاضر هیچ سناریویی تعریف نشده است.',
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      color:
                          themeProvider.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Logic to add a new scenario
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ویژگی افزودن سناریو در حال توسعه است'),
            ),
          );
        },
        backgroundColor:
            themeProvider.isDarkMode ? Colors.yellow[700] : Colors.amber[700],
        child: const Icon(Icons.add),
      ),
    );
  }
}
