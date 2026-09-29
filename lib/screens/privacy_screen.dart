/// Privacy Policy + Terms of Use (Profile se khulta hai).
/// Play Store publishing ke liye bhi zaroori hoga. Sachi baat: data sirf
/// phone me rehta hai; Firebase configure ho to per-user private sync.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Privacy & Terms'),
          bottom: const TabBar(
            labelStyle: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(fontSize: 16),
            tabs: [
              Tab(text: 'Privacy Policy'),
              Tab(text: 'Terms of Use'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DocView(sections: _privacy),
            _DocView(sections: _terms),
          ],
        ),
      ),
    );
  }
}

class _DocView extends StatelessWidget {
  final List<_Section> sections;
  const _DocView({required this.sections});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.l),
      itemCount: sections.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.m),
            child: Text('QistBook — aakhri update: September 2026',
                style: AppText.caption),
          );
        }
        final s = sections[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title, style: AppText.h2),
              const SizedBox(height: AppSpace.s),
              Text(s.body, style: AppText.body),
            ],
          ),
        );
      },
    );
  }
}

class _Section {
  final String title;
  final String body;
  const _Section(this.title, this.body);
}

const _privacy = [
  _Section(
    'Apka data kahan rehta hai?',
    'QistBook offline-first app hai. Apke customers, payments, vouchers aur settings ka data SIRF apke phone me save hota hai (phone ki local database me). Jab tak ap khud Firebase cloud sync configure na karein, apka data kisi server par upload NAHI hota.',
  ),
  _Section(
    'Cloud sync (optional)',
    'Agar Firebase configure ho to apka data apke private account me sync hota hai — sirf ap dekh sakte hain, koi aur nahi. Sync ke baghair app poori tarah kaam karti hai.',
  ),
  _Section(
    'Kya hum apka data bechte hain?',
    'Bilkul nahi. Hum apka data na bechte hain, na kisi teesre ko dete hain, na ads ke liye use karte hain. Apka business data apki amanat hai.',
  ),
  _Section(
    'Permissions kyun mangte hain?',
    '• Camera/Gallery: printed pages scan karne ke liye (import).\n• Phone/Call: customer ko call karne ke liye.\n• SMS: due reminders bhejne ke liye (sirf apke dabane par).\n• Notifications: call reminders aur monthly updates ke liye.\n• Storage: backup file save karne ke liye.\nYe permissions sirf in kaamon ke liye use hoti hain.',
  ),
  _Section(
    'Backup apki zimmedari',
    'Data phone me hai, is liye Profile → Backup se regular backup banao aur usay phone se bahar (WhatsApp/email) mehfooz rakho. Phone kho jaye to backup ke baghair data wapas nahi aa sakta.',
  ),
  _Section(
    'Data delete karna',
    'App uninstall karne se phone ka data mit jata hai. Profile → "Masla hal karein" → App reset se bhi data wipe ho jata hai. Firebase sync on ho to apne account se bhi delete kar sakte hain — support se rabta karein.',
  ),
];

const _terms = [
  _Section(
    'App kis liye hai?',
    'QistBook installment/qist wale business ka hisaab-kitab rakhne ke liye hai: customers, dues, payments, vouchers aur reminders. Ye accounting ya legal mashwara nahi deti.',
  ),
  _Section(
    'Apki zimmedari',
    '• Jo data import/scan karte hain uski durusti ap check karein — OCR me ghalti ho sakti hai.\n• Reminders bhejne se pehle customer ka number confirm karein.\n• Apna login password aur app PIN kisi ko na batayein.\n• Regular backup apki zimmedari hai.',
  ),
  _Section(
    'Koi guarantee nahi',
    'App "jaisi hai" di jati hai. Hum koshish karte hain ke data mehfooz rahe, lekin phone kharab hone, chori ya ghalti se delete hone par hum zimmedar nahi — is liye backup zaroori hai.',
  ),
  _Section(
    'Ghalat istemal mana hai',
    'App ko kisi ghalat, dhoke ya qanoon ke khilaf kaam ke liye use na karein. Aisa karne par apka account/service band ki ja sakti hai.',
  ),
  _Section(
    'Tabdeeli',
    'Ye terms waqt ke sath badal sakti hain. Ahem tabdeeli par app me ittila di jayegi.',
  ),
  _Section(
    'Rabta',
    'Koi sawal ho to Profile → Support se hum se rabta karein.',
  ),
];
