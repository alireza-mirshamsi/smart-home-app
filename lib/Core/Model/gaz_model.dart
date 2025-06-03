class GazModel {
  final String deviceId;
  String stateCode;
  String itemName;

  GazModel({
    required this.deviceId,
    required this.stateCode,
    required this.itemName,
  });

  // برای تبدیل به JSON و ذخیره در SharedPreferences
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'stateCode': stateCode,
    'itemName': itemName,
  };

  // برای بازیابی از JSON
  factory GazModel.fromJson(Map<String, dynamic> json) {
    return GazModel(
      deviceId: json['deviceId'],
      stateCode: json['stateCode'],
      itemName: json['itemName'],
    );
  }
}
