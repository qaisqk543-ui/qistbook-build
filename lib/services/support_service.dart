/// Support number: shared_prefs me persisted ("support_number").
/// Pehli dafa set nahi hota — button dabane par user se manga jata hai.
library;

import 'package:shared_preferences/shared_preferences.dart';

class SupportService {
  static const key = 'support_number';

  static Future<String?> getNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(key) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> setNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, number.trim());
  }

  /// WhatsApp ke liye international format (Pakistani numbers).
  static String toWaNumber(String phone) {
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('03') && d.length == 11) return '92${d.substring(1)}';
    return d;
  }
}
