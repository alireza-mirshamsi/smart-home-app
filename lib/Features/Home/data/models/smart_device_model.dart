class SmartDeviceModel {
  final String name;
  final String iconPath;
  bool isOn;

  SmartDeviceModel({
    required this.name,
    required this.iconPath,
    this.isOn = false,
  });
}
