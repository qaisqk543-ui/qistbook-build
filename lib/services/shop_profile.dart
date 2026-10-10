/// Dukaan ka naam (shop name) — QistBook ab kisi bhi dukaan ke liye use ho sakta hai.
/// Profile screen se badla jata hai; WhatsApp/SMS auto-messages me wahi naam jata hai.
/// SharedPreferences me save hota hai — offline, sirf is phone par.
library;

import 'package:shared_preferences/shared_preferences.dart';

const _kShopName = 'shop_name';

/// Default: Qais ki dukaan. Pehli dafa yahi aayega;
/// koi aur dukaan wala apna naam likh lega.
const defaultShopName = 'Alif Electronics, Kingra';

Future<String> loadShopName() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(_kShopName)?.trim() ?? '';
  return name.isEmpty ? defaultShopName : name;
}

Future<void> saveShopName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  final clean = name.trim();
  await prefs.setString(
      _kShopName, clean.isEmpty ? defaultShopName : clean);
}
