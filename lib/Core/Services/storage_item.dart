import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  static const String _itemsKey = 'items';

  Future<List<String>> loadItems() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? itemsJson = prefs.getStringList(_itemsKey);

    // اگر داده‌ای وجود نداشت، آیتم‌های پیش‌فرض را برگردان
    if (itemsJson == null || itemsJson.isEmpty) {
      itemsJson = ['آشپزخانه', 'پذیرایی', 'سرویس بهداشتی'];
      await prefs.setStringList(_itemsKey, itemsJson); // ذخیره آیتم‌های پیش‌فرض
    }

    return itemsJson;
  }

  Future<void> saveItems(List<String> items) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_itemsKey, items);
  }
}
