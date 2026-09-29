/// Help: "App kaise use karein" — short numbered steps with icons,
/// simple Roman Urdu. Profile se khulta hai.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App kaise use karein')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.l),
        children: [
          const Text(
            'QistBook 5 minute me seekhen',
            style: AppText.h1,
          ),
          const SizedBox(height: AppSpace.s),
          Text(
            'Neeche har kaam ke asaan steps hain.',
            style:
                AppText.body.copyWith(color: AppColors.grey),
          ),
          const SizedBox(height: AppSpace.l),
          ..._steps.map(_stepCard),
          const SizedBox(height: AppSpace.l),
        ],
      ),
    );
  }

  Widget _stepCard(_Step s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: s.tint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(s.icon,
                      size: 30, color: s.color),
                ),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: Text(s.title, style: AppText.title),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.m),
            ...s.points.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(
                      bottom: AppSpace.s),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.only(top: 2),
                        decoration:
                            const BoxDecoration(
                          color: AppColors.tintTeal,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('${e.key + 1}',
                              style: AppText.bodyBold.copyWith(
                                  color: AppColors
                                      .primaryDark)),
                        ),
                      ),
                      const SizedBox(width: AppSpace.s),
                      Expanded(
                        child: Text(e.value,
                            style: AppText.body),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final Color tint;
  final Color color;
  final String title;
  final List<String> points;
  const _Step(this.icon, this.tint, this.color, this.title,
      this.points);
}

const _steps = [
  _Step(
    Icons.document_scanner_rounded,
    AppColors.tintTeal,
    AppColors.primaryDark,
    'Data import kaise karein',
    [
      'Home → Import dabao.',
      'Outstanding Report ya Customer Statement chuno.',
      'PDF upload karo (sab se asaan) ya camera se page scan karo.',
      'App khud data parhegi — review karke Confirm dabao.',
      'Scan me ghalti ho to manual entry se theek kar lo.',
    ],
  ),
  _Step(
    Icons.payments_rounded,
    AppColors.tintGreen,
    AppColors.okGreen,
    'Payment kaise record karein',
    [
      'Outstanding me customer ke samne Collect (note wala) button dabao.',
      'Mili hui raqam, tareeqa (Cash/JazzCash…) aur date likho.',
      'Due aur balance khud kam ho jayenge.',
      'Received tab me saari payments nazar aayengi; ghalti ho to Undo dabao.',
    ],
  ),
  _Step(
    Icons.receipt_long_rounded,
    AppColors.tintAmber,
    AppColors.amber,
    'Voucher kya hai',
    [
      'Voucher = wo hisaab jo abhi "pending case" hai (court/office).',
      'Outstanding me customer par long-press karo → Voucher me bhejo.',
      'Voucher wale customers ki due khud nahi badhti (frozen).',
      'Masla hal ho jaye to Voucher detail me "Wapas Outstanding" dabao.',
    ],
  ),
  _Step(
    Icons.alarm_add_rounded,
    AppColors.tintRose,
    AppColors.dueRed,
    'Reminder kaise lagayein',
    [
      'Customer row me ghari (alarm) wala button dabao.',
      'Pehle date, phir time chuno.',
      'Waqt par notification aayegi — Call, WhatsApp ya SMS kar lo.',
    ],
  ),
  _Step(
    Icons.backup_rounded,
    AppColors.tintBlue,
    Colors.blue,
    'Backup kyun zaroori hai',
    [
      'Apka saara data SIRF is phone me hai.',
      'Profile → Backup → "Backup banao" dabao.',
      'File ko WhatsApp par khud ko bhej kar mehfooz rakho.',
      'Phone kho/gum ho jaye to isi file se sab wapas aa jata hai.',
    ],
  ),
  _Step(
    Icons.lock_rounded,
    AppColors.tintSlate,
    AppColors.primaryDark,
    'App Lock (PIN)',
    [
      'Profile → App Lock on karo, 4-digit PIN banao.',
      'Ab app khulne par PIN mangegi — koi aur nahi dekh sakega.',
      'PIN bhool jao to logout karke password se dobara login karo.',
    ],
  ),
];
