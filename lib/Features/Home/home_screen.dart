import 'package:flutter/material.dart';
import 'package:smart_home_app/Features/Home/smart_device_box.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final double horizontalPadding = 40;
  final double verticalPadding = 25;

  List mySmartDevices = [
    ["کلید 1", "assets/lightbulb.png", true],
    ["کلید 2", "assets/lightbulb.png", false],
    ["کلید 3", "assets/lightbulb.png", false],
    ["کلید 4", "assets/lightbulb.png", false],
  ];

  // power button switched
  void powerSwitchChanged(bool value, int index) {
    setState(() {
      mySmartDevices[index][2] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    // تنظیم نسبت عرض به ارتفاع
    double childAspectRatio = screenWidth > 600 ? 1 / 1.5 : 1 / 1.3;

    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mySmartDevices.length,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 600 ? 50 : 25,
                    vertical: screenWidth > 600 ? 30 : 0,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    return SmartDeviceBox(
                      key: Key(index.toString()),
                      smartDeviceName: mySmartDevices[index][0],
                      iconPath: mySmartDevices[index][1],
                      powerOn: mySmartDevices[index][2],
                      onChanged: (value) => powerSwitchChanged(value, index),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
