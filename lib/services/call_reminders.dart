/// Scheduled call reminders: pick a time on the Outstanding screen, get a
/// high-priority notification at that time, tap it and the app shows the
/// customer with SIM Call / WhatsApp / SMS / Delay actions.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/customer.dart';
import 'reminders.dart';

/// Global navigator key so the reminder tap handler can show dialogs from
/// anywhere. Set on MaterialApp in main.dart.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class CallReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Find a customer by A/C number. Wired up in main.dart after the store
  /// is initialized.
  static Customer? Function(String accountNo)? lookupCustomer;

  static const _channelId = 'call_reminders';
  static const _channelName = 'Call Reminders';
  static const _prefsKey = 'call_reminders';

  static int _notifId(String accountNo) =>
      accountNo.hashCode & 0x7fffffff;

  static Future<void> init() async {
    if (_ready) return;
    // Notifications must NEVER crash app launch — any failure here is
    // swallowed so the app always opens.
    try {
      await _initUnsafe();
    } catch (_) {}
    _ready = true;
  }

  static Future<void> _initUnsafe() async {
    tzdata.initializeTimeZones();
    // Device wall-clock zone for scheduling (Pakistan).
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
        android: androidInit, iOS: darwinInit, macOS: darwinInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  /// Call after init + runApp when the app may have been launched by tapping
  /// a reminder notification (cold start).
  static Future<void> handleLaunchFromNotification() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        _showForAccount(payload);
      }
    } catch (_) {}
  }

  static void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _showForAccount(payload);
    }
  }

  /// Show the reminder dialog for an A/C number, retrying briefly until the
  /// navigator is ready (cold-start case).
  static Future<void> _showForAccount(String accountNo) async {
    for (var i = 0; i < 12; i++) {
      final lookup = lookupCustomer;
      final ctx = appNavigatorKey.currentContext;
      if (lookup != null && ctx != null) {
        final c = lookup(accountNo);
        if (c == null) return;
        // The reminder fired → it is consumed; remove the stored entry so
        // the alarm icon resets. (Re-schedule from the list if needed.)
        await cancelReminder(accountNo);
        if (ctx.mounted) {
          showDialog(
            context: ctx,
            builder: (_) => ReminderDialog(customer: c),
          );
        }
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Schedule a call reminder for the next occurrence of [time]
  /// (today if still ahead, otherwise tomorrow). Returns the actual time.
  static Future<DateTime> scheduleReminder(
      Customer c, TimeOfDay time) async {
    final now = DateTime.now();
    var scheduled =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return (await scheduleReminderAt(c, scheduled)) ?? scheduled;
  }

  /// Schedule a call reminder at an exact [when] (Asia/Karachi wall clock).
  /// Returns null (and schedules nothing) when [when] is not in the future.
  static Future<DateTime?> scheduleReminderAt(
      Customer c, DateTime when) async {
    await init();
    if (!when.isAfter(DateTime.now())) return null;
    final tzScheduled = tz.TZDateTime.from(when, tz.local);
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'QistBook call reminders',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Call reminder',
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      _notifId(c.accountNo),
      'Call Reminder',
      '${c.name} ko call ka time ho gaya — Due Rs ${c.currentDue.toStringAsFixed(0)}',
      tzScheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: c.accountNo,
    );
    await _saveReminder(c, when);
    return when;
  }

  /// Monthly rollover notification: "Naya mahina shuru — N customers ki
  /// due update ho gayi". Kabhi throw nahi karta.
  static Future<void> notifyRollover(int n) async {
    if (n <= 0) return;
    try {
      await init();
      const androidDetails = AndroidNotificationDetails(
        'qistbook_updates',
        'QistBook Updates',
        channelDescription: 'Monthly updates aur ahem ittila',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        9001,
        'Naya mahina shuru',
        '$n customers ki due update ho gayi — Outstanding check karein.',
        details,
      );
    } catch (_) {}
  }

  /// Subscription expiry se 3 din pehle ki notification (id 9002).
  static Future<void> scheduleExpiryReminder(
      DateTime when) async {
    try {
      await init();
      const androidDetails = AndroidNotificationDetails(
        'qistbook_updates',
        'QistBook Updates',
        channelDescription: 'Monthly updates aur ahem ittila',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details =
          NotificationDetails(android: androidDetails);
      await _plugin.zonedSchedule(
        9002,
        'Subscription khatam hone wali hai',
        'QistBook subscription 3 din me khatam — renew karwa lein taake kaam ruke nahi.',
        tz.TZDateTime.from(when, tz.local),
        details,
        androidScheduleMode:
            AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static Future<void> cancelExpiryReminder() async {
    try {
      await _plugin.cancel(9002);
    } catch (_) {}
  }

  /// Free trial khatam hone se 1 din pehle ki notification (id 9003).
  static Future<void> scheduleTrialReminder(
      DateTime when) async {
    try {
      await init();
      const androidDetails = AndroidNotificationDetails(
        'qistbook_updates',
        'QistBook Updates',
        channelDescription: 'Monthly updates aur ahem ittila',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details =
          NotificationDetails(android: androidDetails);
      await _plugin.zonedSchedule(
        9003,
        'Free trial kal khatam ho raha hai',
        'QistBook ka 30 din ka free trial kal khatam — subscription lein taake kaam ruke nahi.',
        tz.TZDateTime.from(when, tz.local),
        details,
        androidScheduleMode:
            AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {}
  }

  static Future<void> cancelReminder(String accountNo) async {    try {
      await _plugin.cancel(_notifId(accountNo));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    list.removeWhere((m) => m['accountNo'] == accountNo);
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  /// Test notification — foran bajao taake pata chale sound aa rahi hai.
  /// Returns true agar notification dikhi.
  static Future<bool> testNotification() async {
    try {
      await init();
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'QistBook call reminders',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Test',
        playSound: true,
        enableVibration: true,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        9999,
        'QistBook Test',
        'Agar ye awaz ke sath aya to reminders kaam karenge! 🔊',
        details,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Check karo ke notification permission mili hui hai ya nahi.
  static Future<bool> hasNotificationPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.areNotificationsEnabled();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True if a future reminder is stored for this account.
  static Future<bool> hasReminder(String accountNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    return list.any((m) =>
        m['accountNo'] == accountNo &&
        (m['timeMillis'] as int) > now);
  }

  static Future<DateTime?> getReminderTime(String accountNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    for (final m in list) {
      if (m['accountNo'] == accountNo) {
        return DateTime.fromMillisecondsSinceEpoch(
            m['timeMillis'] as int);
      }
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _loadRaw(
      SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveReminder(
      Customer c, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    list.removeWhere((m) => m['accountNo'] == c.accountNo);
    list.add({
      'accountNo': c.accountNo,
      'name': c.name,
      'timeMillis': when.millisecondsSinceEpoch,
    });
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  /// Self Repair: saved reminders me se jo guzar gaye unhe saaf karo,
  /// aur jo scheduled hone chahiye thay lekin notification ghaib hai
  /// (system ne maar di) unhe dobara schedule karo.
  /// Returns {'rescheduled': x, 'cleaned': y}.
  static Future<Map<String, int>> verifyReminders() async {
    var rescheduled = 0;
    var cleaned = 0;
    try {
      await init();
      final prefs = await SharedPreferences.getInstance();
      final list = await _loadRaw(prefs);
      if (list.isEmpty) return {'rescheduled': 0, 'cleaned': 0};
      final pending = await _plugin.pendingNotificationRequests();
      final pendingIds = pending.map((e) => e.id).toSet();
      final now = DateTime.now().millisecondsSinceEpoch;
      final kept = <Map<String, dynamic>>[];
      for (final m in list) {
        final t = (m['timeMillis'] as int?) ?? 0;
        final acct = (m['accountNo'] as String?) ?? '';
        if (t <= now || acct.isEmpty) {
          cleaned++; // waqt guzar gaya / invalid — list se hatao
          continue;
        }
        kept.add(m);
        if (!pendingIds.contains(_notifId(acct))) {
          final c = lookupCustomer?.call(acct);
          if (c != null) {
            try {
              await scheduleReminderAt(
                  c, DateTime.fromMillisecondsSinceEpoch(t));
              rescheduled++;
            } catch (_) {}
          }
        }
      }
      await prefs.setString(_prefsKey, jsonEncode(kept));
    } catch (_) {}
    return {'rescheduled': rescheduled, 'cleaned': cleaned};
  }
}

/// Dialog shown when a call reminder fires (notification tap).
/// Actions: SIM Call, WhatsApp, SMS, Delay (reminder off).
class ReminderDialog extends StatelessWidget {
  final Customer customer;
  const ReminderDialog({super.key, required this.customer});

  String _rs(double v) =>
      'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  Future<void> _done(BuildContext context) async {
    await CallReminderService.cancelReminder(customer.accountNo);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return AlertDialog(
      title: const Text('Call Reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text('A/C ${c.accountNo}  •  ${c.cell}'),
          const SizedBox(height: 8),
          Text('Due: ${_rs(c.currentDue)}',
              style:
                  const TextStyle(fontSize: 16, color: Colors.red)),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.call),
          label: const Text('SIM Call'),
          onPressed: () async {
            await dialNumber(c.cell);
            if (!context.mounted) return;
            await _done(context);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.chat, color: Colors.green),
          label: const Text('WhatsApp'),
          onPressed: () async {
            final msg = await dueReminderMessageWithAccounts(c);
            final ok = await openWhatsApp(c, msg);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('WhatsApp nahi khul saka')),
              );
            }
            if (!context.mounted) return;
            await _done(context);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.sms),
          label: const Text('SMS'),
          onPressed: () async {
            final msg = await dueReminderMessageWithAccounts(c);
            final ok = await sendSms(c.cell, msg);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(ok
                        ? 'SMS bhej diya gaya'
                        : 'SMS nahi bheja ja saka — permission check karo')),
              );
            }
            if (!context.mounted) return;
            await _done(context);
          },
        ),
        TextButton(
          child: const Text('Delay'),
          onPressed: () => _done(context),
        ),
      ],
    );
  }
}
