/// Scheduled call reminders: pick a time on the Outstanding screen, get a
/// high-priority notification at that time, tap it and the app shows the
/// customer with SIM Call / WhatsApp / SMS / Delay actions.

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
    _ready = true;
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
    await init();
    final now = DateTime.now();
    var scheduled =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final tzScheduled = tz.TZDateTime.from(scheduled, tz.local);
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'QistBook call reminders',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Call reminder',
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
    await _saveReminder(c, scheduled);
    return scheduled;
  }

  static Future<void> cancelReminder(String accountNo) async {
    try {
      await _plugin.cancel(_notifId(accountNo));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadRaw(prefs);
    list.removeWhere((m) => m['accountNo'] == accountNo);
    await prefs.setString(_prefsKey, jsonEncode(list));
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
            await _done(context);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.chat, color: Colors.green),
          label: const Text('WhatsApp'),
          onPressed: () async {
            final ok =
                await openWhatsApp(c, dueReminderMessage(c));
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('WhatsApp nahi khul saka')),
              );
            }
            await _done(context);
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.sms),
          label: const Text('SMS'),
          onPressed: () async {
            final ok =
                await sendSms(c.cell, dueReminderMessage(c));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(ok
                        ? 'SMS bhej diya gaya'
                        : 'SMS nahi bheja ja saka — permission check karo')),
              );
            }
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
