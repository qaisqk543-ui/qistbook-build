/// Invite link: shared_prefs me persisted ("invite_link").
/// Default khaali — pehli dafa Share par user se manga jata hai
/// (Play Store ya APK ka link).
library;

import 'package:shared_preferences/shared_preferences.dart';

class InviteService {
  static const key = 'invite_link';

  static const shareMessage =
      'QistBook app download karein — dukandaaron ke liye qiston ka asaan hisab:';

  static Future<String?> getLink() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(key) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> setLink(String link) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, link.trim());
  }

  static String fullMessage(String link) => '$shareMessage\n$link';
}
