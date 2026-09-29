/// App-wide settings: text size (Normal / Bara) for elderly-friendly UI.
/// Persisted in SharedPreferences, applied via MediaQuery textScaler.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  static const _key = 'text_scale';

  /// 1.0 = Normal, 1.3 = Bara (elderly-friendly).
  double textScale = 1.0;

  bool get isLarge => textScale > 1.1;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    textScale = prefs.getDouble(_key) ?? 1.0;
    notifyListeners();
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, v);
    notifyListeners();
  }
}
