import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_home_app/Core/Services/device_provider.dart';

class SmartDeviceBox extends StatefulWidget {
  final String smartDeviceName;
  final String iconPath;
  final bool powerOn;
  final void Function(bool)? onChanged;
  final int relayNumber;
  final String deviceId;

  const SmartDeviceBox({
    super.key,
    required this.smartDeviceName,
    required this.iconPath,
    required this.powerOn,
    required this.onChanged,
    required this.relayNumber,
    required this.deviceId,
  });

  @override
  State<SmartDeviceBox> createState() => _SmartDeviceBoxState();
}

class _SmartDeviceBoxState extends State<SmartDeviceBox> {
  // Memoize the decoration to avoid rebuilding it unnecessarily
  BoxDecoration? _cachedDecoration;
  bool _lastState = false;

  @override
  void initState() {
    super.initState();
    _lastState = widget.powerOn;
    _updateDecoration(_lastState);
  }

  @override
  void didUpdateWidget(SmartDeviceBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.powerOn != _lastState) {
      _lastState = widget.powerOn;
      _updateDecoration(_lastState);
    }
  }

  void _updateDecoration(bool currentState) {
    _cachedDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: currentState 
          ? Colors.grey[900] 
          : const Color.fromARGB(44, 164, 167, 189),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Using Consumer to optimize rebuilds - only rebuilds when the specific device state changes
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        final currentState = deviceProvider.getButtonStates(widget.deviceId)[widget.relayNumber] ?? false;
        
        // Update decoration if state changed
        if (currentState != _lastState) {
          _lastState = currentState;
          _updateDecoration(currentState);
        }

        return Padding(
          padding: const EdgeInsets.all(15.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: _cachedDecoration,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // icon
                  Image.asset(
                    widget.iconPath,
                    height: 65,
                    color: currentState ? Colors.green : Colors.red,
                  ),

                  // smart device name + switch
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20.0),
                          child: Text(
                            widget.smartDeviceName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: currentState ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                      CupertinoSwitch(
                        value: currentState,
                        onChanged: widget.onChanged,
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Clean up any resources if needed
    super.dispose();
  }
}