/// Manual subscription system (offline-capable).
///
/// Backend koi nahi — is liye TID claim + activation code + admin panel.
/// Play Store ke proper Google subscription baad me aayega, tab ye
/// server-side hoga.
///
/// - Paywall: login ke baad, subscription active na ho to lock (data delete NAHI hota).
/// - TID claim: user payment ka reference de → status "pending".
/// - Activation code: SHA256(appSecret + "QB" + YYYYMM) ke pehle 6 numeric
///   digits — REAL hash verification, koi fake check nahi.
/// - Admin: Qais apni device par admin PIN set kare → owner bypass + panel.
/// - Sab per-user shared_prefs keys me: sub_expiry, sub_status, pending_tid.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call_reminders.dart';
import 'error_log.dart';

class SubscriptionService {
  // NOTE (security): ye secret is scale par acceptable hai (manual offline
  // system). Play Store phase me activation server-side hogi aur ye secret
  // app se nikal diya jayega.
  static const appSecret = 'QistBook-2026-ManualSub-Secret';

  static const defaultFee = 500;

  // ---------------------------------------------------------- keys
  static String _k(String uid, String name) => '${name}_$uid';
  static const _ownerKey = 'is_owner';
  static const _adminPinKey = 'admin_pin_hash';
  static const _feeKey = 'pay_fee';
  static const _jazzKey = 'pay_jazzcash';
  static const _easyKey = 'pay_easypaisa';
  static const _bankKey = 'pay_bank';

  // ---------------------------------------------------------- activation code
  /// 6-digit numeric code = SHA256(appSecret + "QB" + YYYYMM) ke
  /// hex digest ke pehle 6 NUMERIC digits. Owner (Qais) isay
  /// WhatsApp/call par customer ko de.
  static String monthlyCode([DateTime? when]) {
    final d = when ?? DateTime.now();
    final yyyymm =
        '${d.year}${d.month.toString().padLeft(2, '0')}';
    final hex = sha256
        .convert(utf8.encode('$appSecret${'QB'}$yyyymm'))
        .toString();
    final digits = hex.replaceAll(RegExp(r'[^0-9]'), '');
    final six =
        digits.length >= 6 ? digits.substring(0, 6) : digits;
    return six.padRight(6, '0');
  }

  /// Current ya pichhle mahine ka code qabool (month-boundary safety).
  static bool verifyCode(String input) {
    final v = input.trim();
    if (v.length != 6 || int.tryParse(v) == null) return false;
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    return v == monthlyCode(now) || v == monthlyCode(prev);
  }

  // ---------------------------------------------------------- status
  static Future<bool> isOwner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ownerKey) ?? false;
  }

  static Future<DateTime?> expiryOf(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_k(uid, 'sub_expiry'));
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String> statusOf(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_k(uid, 'sub_status')) ?? '';
  }

  /// Active = owner bypass ya expiry abhi baqi.
  static Future<bool> isActive(String uid) async {
    if (await isOwner()) return true;
    final exp = await expiryOf(uid);
    return exp != null && exp.isAfter(DateTime.now());
  }

  static Future<int> daysLeft(String uid) async {
    final exp = await expiryOf(uid);
    if (exp == null) return 0;
    final d = exp.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  /// Device activate karo (admin ya code se). Expiry reminder bhi lagao.
  static Future<void> activate(String uid, int days) async {
    final prefs = await SharedPreferences.getInstance();
    final exp =
        DateTime.now().add(Duration(days: days));
    await prefs.setInt(
        _k(uid, 'sub_expiry'), exp.millisecondsSinceEpoch);
    await prefs.setString(_k(uid, 'sub_status'), 'active');
    await prefs.remove(_k(uid, 'pending_tid'));
    await _scheduleExpiryReminder(exp);
  }

  /// Expiry se 3 din pehle local notification.
  static Future<void> _scheduleExpiryReminder(
      DateTime expiry) async {
    try {
      final when =
          expiry.subtract(const Duration(days: 3));
      if (when.isAfter(DateTime.now())) {
        await CallReminderService.scheduleExpiryReminder(when);
      } else {
        await CallReminderService.cancelExpiryReminder();
      }
    } catch (e) {
      ErrorLog.log('Sub reminder', e);
    }
  }

  /// App start par: active ho aur 3 din ke andar expiry ho to reminder pakka karo.
  static Future<void> ensureExpiryReminder(String uid) async {
    try {
      if (await isOwner()) return;
      final exp = await expiryOf(uid);
      if (exp == null || !exp.isAfter(DateTime.now())) return;
      await _scheduleExpiryReminder(exp);
    } catch (e) {
      ErrorLog.log('Sub reminder', e);
    }
  }

  // ---------------------------------------------------------- TID claim
  static Future<void> claimTid(
      String uid, String tid, String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _k(uid, 'pending_tid'),
        jsonEncode({'tid': tid.trim(), 'date': date}));
    await prefs.setString(_k(uid, 'sub_status'), 'pending');
  }

  static Future<Map<String, String>?> pendingTid(
      String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(uid, 'pending_tid'));
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map;
      return {
        'tid': '${m['tid'] ?? ''}',
        'date': '${m['date'] ?? ''}'
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------- admin PIN
  static Future<bool> adminPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_adminPinKey) ?? '').isNotEmpty;
  }

  static String _adminHash(String pin) {
    final bytes = utf8.encode('qistbook-admin:$pin');
    return sha256.convert(bytes).toString();
  }

  /// Pehli dafa set → is device ko owner banao (Qais ko khud pay nahi).
  static Future<void> setAdminPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminPinKey, _adminHash(pin));
    await prefs.setBool(_ownerKey, true);
  }

  static Future<bool> verifyAdminPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_adminPinKey) ?? '';
    if (stored.isEmpty || pin.length < 4) return false;
    return stored == _adminHash(pin);
  }

  // ---------------------------------------------------------- payment settings
  static Future<int> fee() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_feeKey) ?? defaultFee;
  }

  static Future<Map<String, String>> paymentNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'JazzCash': prefs.getString(_jazzKey) ?? '',
      'Easypaisa': prefs.getString(_easyKey) ?? '',
      'Bank': prefs.getString(_bankKey) ?? '',
    };
  }

  static Future<void> savePaymentSettings(
      {required int feeAmount,
      required String jazzcash,
      required String easypaisa,
      required String bank}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_feeKey, feeAmount);
    await prefs.setString(_jazzKey, jazzcash.trim());
    await prefs.setString(_easyKey, easypaisa.trim());
    await prefs.setString(_bankKey, bank.trim());
  }
}
