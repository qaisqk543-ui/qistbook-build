/// Reminders: SMS via system SMS app (intent) + one-tap WhatsApp.
/// Play-safe: SEND_SMS permission hata di — app khud SMS nahi bhejti.
/// SMS button dabane par phone ki SMS app khulti hai (message pre-filled),
/// user khud Send dabata hai. WhatsApp bhi one-tap hai.
library;

import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import 'payment_accounts.dart';

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

/// SMS reminder via system SMS app (Play-safe, koi permission nahi chahiye).
/// SMS app khulti hai message pre-filled ke sath — user Send dabata hai.
/// Hamesha true (app khul gayi) — bhejna user ke haath me hai.
Future<bool> sendSms(String phone, String message) async {
  await openSmsApp(phone, message);
  return true;
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
