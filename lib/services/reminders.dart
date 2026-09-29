/// Reminders: SMS sent directly from the phone (Android) + one-tap WhatsApp.
/// WhatsApp has no free auto-send API — fully automatic sending would violate
/// WhatsApp's terms and risk a number ban. So WhatsApp is "one tap":
/// the chat opens with the message pre-filled, the user presses send.
library;

import 'package:telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import 'payment_accounts.dart';

final _telephony = Telephony.instance;

String dueReminderMessage(Customer c, {bool urdu = true}) {
  final due = c.currentDue.toStringAsFixed(0);
  final inst = c.monthlyInstallment.toStringAsFixed(0);
  if (urdu) {
    return 'Assalam o Alaikum ${c.name}, ALIF ELECTRONICS se ittila di jati '
        'hai ke aap ki is mah ki qist Rs $inst me se Rs $due baqi hai. '
        'Baraye meherbani jald ada karen. Shukriya.';
  }
  return 'Assalam o Alaikum ${c.name}, this is ALIF ELECTRONICS. '
      'Your installment of Rs $inst has Rs $due pending. '
      'Please pay at your earliest. Thank you.';
}

String paidConfirmationMessage(Customer c, double amount) {
  return 'Assalam o Alaikum ${c.name}, Rs ${amount.toStringAsFixed(0)} '
      'ki adayegi moosool ho gayi hai. Shukriya — ALIF ELECTRONICS.';
}

/// Saved payment accounts as shareable lines, e.g.
/// "JazzCash (ALIF ELECTRONICS) - 03001234567".
/// Empty string when no accounts are saved.
Future<String> paymentAccountsText() async {
  final accounts = await loadAccounts();
  if (accounts.isEmpty) return '';
  return accounts
      .map((a) => '${a.type} (${a.title}) - ${a.number}')
      .join('\n');
}

/// Due reminder + payment accounts (auto-shared in SMS/WhatsApp).
Future<String> dueReminderMessageWithAccounts(Customer c) async {
  final base = dueReminderMessage(c);
  final acc = await paymentAccountsText();
  if (acc.isEmpty) return base;
  return '$base\n\nAdaigi ke liye:\n$acc';
}

/// Sends an SMS straight from the device. Returns true on success.
/// Requires SEND_SMS permission (Android). On iOS this path is unavailable —
/// call [openSmsApp] instead.
Future<bool> sendSms(String phone, String message) async {
  try {
    final granted =
        await _telephony.requestPhoneAndSmsPermissions ?? false;
    if (!granted) return false;
    await _telephony.sendSms(to: phone, message: message);
    return true;
  } catch (_) {
    return false;
  }
}

/// Opens the SMS app with a pre-filled message (iOS-safe fallback).
Future<void> openSmsApp(String phone, String message) async {
  final uri = Uri.parse(
      'sms:$phone?body=${Uri.encodeComponent(message)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

/// One-tap WhatsApp: opens the chat with the message pre-filled.
Future<bool> openWhatsApp(Customer c, String message) =>
    openWhatsAppNumber(c.cell, message);

/// Convert any Pakistani mobile number to WhatsApp's international format.
String toWhatsAppNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('03') && d.length == 11) return '92${d.substring(1)}';
  if (d.startsWith('923') && d.length == 12) return d;
  return d;
}

/// Open a WhatsApp chat with any phone number + pre-filled message.
/// Tries the native WhatsApp app first (needs <queries> entries for
/// com.whatsapp / com.whatsapp.w4b on Android 11+), then falls back to
/// the wa.me browser link.
Future<bool> openWhatsAppNumber(String phone, String message) async {
  final number = toWhatsAppNumber(phone);
  if (number.isEmpty) return false;
  final text = Uri.encodeComponent(message);
  final appUri = Uri.parse('whatsapp://send?phone=$number&text=$text');
  try {
    if (await canLaunchUrl(appUri)) {
      return await launchUrl(appUri,
          mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
  final webUri = Uri.parse('https://wa.me/$number?text=$text');
  try {
    return await launchUrl(webUri,
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Direct dial any phone number.
Future<bool> dialNumber(String phone) async {
  final uri = Uri.parse('tel:${phone.replaceAll(RegExp(r'\D'), '')}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
    return true;
  }
  return false;
}
