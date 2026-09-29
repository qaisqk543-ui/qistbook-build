/// Payment accounts storage (JazzCash / Easypaisa / Bank).
/// SharedPreferences me JSON list — offline, sirf is phone par.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_account.dart';

const _kAccounts = 'payment_accounts';

Future<List<PaymentAccount>> loadAccounts() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kAccounts);
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) =>
            PaymentAccount.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveAccounts(List<PaymentAccount> accounts) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      _kAccounts, jsonEncode(accounts.map((a) => a.toMap()).toList()));
}

Future<void> addAccount(PaymentAccount account) async {
  final list = await loadAccounts();
  list.add(account);
  await saveAccounts(list);
}

Future<void> deleteAccount(String id) async {
  final list = await loadAccounts();
  list.removeWhere((a) => a.id == id);
  await saveAccounts(list);
}
