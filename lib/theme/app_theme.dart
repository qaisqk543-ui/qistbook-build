/// QistBook design system: premium + elderly-friendly.
///
/// Ek cohesive palette: deep teal primary, soft pastel tints (neon nahi),
/// near-black text on white. Bara type (18sp+ body), 8px spacing grid,
/// 18px card radii, 12px button radii, ≥48px touch targets, Material
/// rounded icons. Sab screens isi system se banti hain taake app ek jaisi,
/// mehngi-designed lage — aur 60+ umar ka banda bhi asani se parh sake.
library;

import 'package:flutter/material.dart';

class AppColors {
  // Primary — refined deep teal / emerald.
  static const Color primary = Color(0xFF0E7C6B);
  static const Color primaryDark = Color(0xFF095E52);
  static const Color primaryDeep = Color(0xFF073F37);

  // Neutrals.
  static const Color ink = Color(0xFF141818); // near-black text
  static const Color grey = Color(0xFF5B6161); // secondary text (min 14sp)
  static const Color background = Color(0xFFF7F8F8);
  static const Color surface = Colors.white;
  static const Color divider = Color(0xFFE3E6E6);

  // Semantic.
  static const Color dueRed = Color(0xFFB71C1C); // due amounts
  static const Color okGreen = Color(0xFF1B7A3D); // received amounts
  static const Color amber = Color(0xFF8A5A00); // dark amber on light tint

  // Soft pastel tints (cards / badges) — halke, neon nahi.
  static const Color tintTeal = Color(0xFFDFF0EC);
  static const Color tintAmber = Color(0xFFFFF4DB);
  static const Color tintGreen = Color(0xFFE4F3E5);
  static const Color tintBlue = Color(0xFFE5F0FC);
  static const Color tintRose = Color(0xFFFBE9E6);
  static const Color tintSlate = Color(0xFFECEFF1);
}

/// 8px grid spacing.
class AppSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

/// Corner radii.
class AppRadius {
  static const double card = 18;
  static const double button = 12;
  static const double dialog = 20;
  static const double chip = 24;
}

/// Typography — bara lekin well-set. Body ≥18sp, titles 20-22sp,
/// amounts bold tabular figures.
class AppText {
  static const TextStyle h1 = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.25,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.3,
  );
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.3,
  );
  static const TextStyle body = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
    height: 1.45,
  );
  static const TextStyle bodyBold = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.45,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.grey,
    height: 1.4,
  );
  static const TextStyle label = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.grey,
    height: 1.4,
  );

  /// Money amounts: bold, tabular figures, ≥20sp.
  static TextStyle money(Color color, {double size = 22}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.3,
      );

  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
}

/// App version — pubspec ke sath sync rakho.
const String kAppVersion = '1.0.16';

/// Rupees formatter: Rs 92,500
String rs(double v) =>
    'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

/// Friendly date: 30 Sep 2026
String fmtDay(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Friendly datetime: 30 Sep, 2:30 PM
String fmtDayTime(DateTime t) {
  var h = t.hour % 12;
  if (h == 0) h = 12;
  final m = t.minute.toString().padLeft(2, '0');
  final ap = t.hour < 12 ? 'AM' : 'PM';
  return '${fmtDay(t)}, $h:$m $ap';
}

/// ISO date: 2026-09-30
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Current month key: 2026-09
String monthKey([DateTime? d]) {
  final t = d ?? DateTime.now();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}';
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.3,
      ),
      iconTheme: IconThemeData(color: Colors.white, size: 28),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpace.m, vertical: AppSpace.s),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: AppText.button,
        minimumSize: const Size(64, 54),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppText.button,
        minimumSize: const Size(64, 54),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700),
        minimumSize: const Size(64, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(fontSize: 17),
      hintStyle:
          const TextStyle(fontSize: 17, color: AppColors.grey),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.dialog),
      ),
      titleTextStyle: AppText.h2,
      contentTextStyle: AppText.body,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF222828),
      contentTextStyle:
          const TextStyle(fontSize: 16, color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.tintTeal,
      iconTheme: WidgetStateProperty.all(
          const IconThemeData(size: 28)),
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ),
    dividerColor: AppColors.divider,
  );
}

/// Consistent snackbar.
void showAppSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg)),
  );
}

/// Friendly empty state: big soft icon + Roman Urdu text.
Widget emptyState({
  required IconData icon,
  required String title,
  String? subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              color: AppColors.tintTeal,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 56, color: AppColors.primaryDark),
          ),
          const SizedBox(height: AppSpace.m),
          Text(title,
              textAlign: TextAlign.center, style: AppText.title),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpace.s),
            Text(subtitle,
                textAlign: TextAlign.center, style: AppText.body),
          ],
        ],
      ),
    ),
  );
}

/// Section header card with 3 stat columns (Outstanding/Voucher pattern).
Widget statHeader({
  required Color tint,
  required List<StatItem> stats,
  String? footer,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpace.m),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    margin: const EdgeInsets.all(AppSpace.m),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: stats
              .map((s) => Expanded(
                    child: Column(
                      children: [
                        Text(s.label,
                            textAlign: TextAlign.center,
                            style: AppText.label),
                        const SizedBox(height: 4),
                        Text(s.value,
                            textAlign: TextAlign.center,
                            style: AppText.money(s.color)),
                      ],
                    ),
                  ))
              .toList(),
        ),
        if (footer != null) ...[
          const SizedBox(height: AppSpace.s),
          Text(footer, style: AppText.caption),
        ],
      ],
    ),
  );
}

class StatItem {
  final String label;
  final String value;
  final Color color;
  const StatItem(this.label, this.value, this.color);
}

/// One customer row — same pattern everywhere (name, details, amounts,
/// 4 big action buttons). Touch targets ≥48px, icons ≥28px.
Widget customerRow({
  required BuildContext context,
  required String name,
  required String line1,
  required String line2,
  required double due,
  required double balance,
  Widget? leading,
  required VoidCallback onCall,
  required VoidCallback onWhatsApp,
  required VoidCallback onReminder,
  required VoidCallback onCollect,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
  bool reminderOn = false,
}) {
  return Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: AppSpace.s),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? '(no name)' : name,
                    style: AppText.bodyBold,
                  ),
                  const SizedBox(height: 2),
                  Text(line1, style: AppText.caption.copyWith(fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(line2, style: AppText.caption.copyWith(fontSize: 15)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Due ',
                          style: AppText.label.copyWith(fontSize: 15)),
                      Text(rs(due),
                          style: AppText.money(AppColors.dueRed,
                              size: 20)),
                      const SizedBox(width: AppSpace.m),
                      Text('Balance ',
                          style: AppText.label.copyWith(fontSize: 15)),
                      Text(rs(balance),
                          style: AppText.money(AppColors.ink, size: 20)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _rowBtn(Icons.payments_rounded, AppColors.primary,
                    'Collect', onCollect),
                _rowBtn(Icons.alarm_add_rounded,
                    reminderOn ? Colors.orange : AppColors.grey,
                    'Reminder', onReminder),
                _rowBtn(Icons.chat_rounded, AppColors.okGreen,
                    'WhatsApp', onWhatsApp),
                _rowBtn(Icons.call_rounded, Colors.blue, 'Call',
                    onCall),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _rowBtn(
    IconData icon, Color color, String tip, VoidCallback onTap) {
  return SizedBox(
    width: 52,
    height: 52,
    child: IconButton(
      icon: Icon(icon, size: 30, color: color),
      tooltip: tip,
      onPressed: onTap,
    ),
  );
}
