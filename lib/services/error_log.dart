/// Rolling error log: aakhri 50 errors (waqt + screen + mukhtasar waja).
/// Troubleshooting screen me dikhta hai aur support report me attach hota hai.
/// Har async operation yahan log kare — UI par kabhi laal crash screen nahi,
/// sirf Roman Urdu friendly dialog/snackbar.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ErrorEntry {
  final DateTime time;
  final String screen;
  final String message;
  const ErrorEntry(this.time, this.screen, this.message);
}

class ErrorLog {
  static const int maxEntries = 50;
  static final List<ErrorEntry> _entries = [];

  static List<ErrorEntry> get entries => List.unmodifiable(_entries);

  static ErrorEntry? get last =>
      _entries.isEmpty ? null : _entries.last;

  /// Error log karo (screen ka naam + mukhtasar waja). Kabhi throw nahi karta.
  static void log(String screen, Object error) {
    try {
      final msg = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
      final short = msg.length > 220 ? '${msg.substring(0, 220)}…' : msg;
      _entries.add(ErrorEntry(DateTime.now(), screen, short));
      if (_entries.length > maxEntries) {
        _entries.removeRange(0, _entries.length - maxEntries);
      }
    } catch (_) {}
  }

  static void clear() {
    try {
      _entries.clear();
    } catch (_) {}
  }
}

/// Friendly Roman Urdu error dialog: "Kuch garbar hui" + waja +
/// "Dobara try karein" button. Koi bhi async failure yahi dikhaye.
Future<void> showFriendlyError(
  BuildContext context,
  String detail, {
  String screen = '',
  Future<void> Function()? onRetry,
}) async {
  if (screen.isNotEmpty) ErrorLog.log(screen, detail);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kuch garbar hui'),
      content: Text(
        detail.isEmpty
            ? 'Pata nahi kya hua, lekin kaam poora nahi ho saka.'
            : detail,
        style: AppText.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Theek hai'),
        ),
        if (onRetry != null)
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onRetry();
            },
            child: const Text('Dobara try karein'),
          ),
      ],
    ),
  );
}
