class Location {
  final String id; // شناسه یکتا برای مکان
  String name; // نام مکان (مثلاً آشپزخانه)

  Location({required this.id, required this.name});

  // تبدیل مکان به فرمت JSON برای ذخیره‌سازی
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  // ساخت مکان از داده‌های JSON
  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'],
      name: json['name'],
    );
  }
}
