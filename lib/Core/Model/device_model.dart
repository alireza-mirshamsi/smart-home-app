class Device {
  final String id; // شناسه یکتا برای دستگاه
  final String name; // نام دستگاه (مثلاً کلید یک پل)
  final String imagePath; // مسیر تصویر دستگاه
  final String locationId; // مکان مرتبط با دستگاه

  Device({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.locationId,
  });

  // تبدیل دستگاه به فرمت JSON برای ذخیره‌سازی
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imagePath': imagePath,
      'locationId': locationId,
    };
  }

  // ساخت دستگاه از داده‌های JSON
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'],
      name: json['name'],
      imagePath: json['imagePath'],
      locationId: json['locationId'],
    );
  }
}
