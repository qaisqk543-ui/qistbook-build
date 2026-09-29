/// App Lock: optional 4-digit PIN (hashed, per-user shared_prefs me).
/// Enabled ho to login ke baad PIN manga jata hai.
/// PIN bhool jao to logout karke password se dobara login karo — wahi reset hai.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockService {
  static String _hashKey(String uid) => 'pin_hash_$uid';

  static String _hash(String uid, String pin) {
    final bytes = utf8.encode('qistbook-pin:$uid:$pin');
    return sha256.convert(bytes).toString();
  }

  /// PIN set hai? (set = enabled)
  static Future<bool> isEnabled(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_hashKey(uid)) ?? '').isNotEmpty;
  }

  static Future<void> setPin(String uid, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey(uid), _hash(uid, pin));
  }

  static Future<void> clearPin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey(uid));
  }

  static Future<bool> verify(String uid, String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_hashKey(uid)) ?? '';
    if (stored.isEmpty || pin.length != 4) return false;
    return stored == _hash(uid, pin);
  }
}
