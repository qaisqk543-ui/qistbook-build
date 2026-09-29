/// Home: greeting + big soft-tint cards (elderly-friendly navigation).
/// Har card ≥96px tall, 40px icon, 18-20px bold label. Outstanding/Voucher
/// par count badges. Tab wale cards tab switch karte hain, baqi push hote hain.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'import_screen.dart';
import 'invite_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';

class HomeScreen extends StatelessWidget {
  /// Tab switch karne ke liye (0=Home, 1=Outstanding, 2=Voucher, 3=Received, 4=Customers).
  final ValueChanged<int> onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final user = AuthScope.of(context).auth.currentUser;
    final name = (user?.name ?? '').trim();

    final cards = <_HomeCard>[
      _HomeCard(
        label: 'Outstanding',
        icon: Icons.warning_amber_rounded,
        tint: AppColors.tintRose,
        iconColor: AppColors.dueRed,
        badge: '${store.outstanding.length}',
        onTap: () => onNavigate(1),
      ),
      _HomeCard(
        label: 'Voucher',
        icon: Icons.receipt_long_rounded,
        tint: AppColors.tintAmber,
        iconColor: AppColors.amber,
        badge: '${store.voucherAccountCount}',
        onTap: () => onNavigate(2),
      ),
      _HomeCard(
        label: 'Received',
        icon: Icons.task_alt_rounded,
        tint: AppColors.tintGreen,
        iconColor: AppColors.okGreen,
        badge: rs(store.monthlyReceived),
        badgeSmall: true,
        onTap: () => onNavigate(3),
      ),
      _HomeCard(
        label: 'Customers',
        icon: Icons.people_rounded,
        tint: AppColors.tintBlue,
        iconColor: Colors.blue.shade800,
        badge: '${store.active.length}',
        onTap: () => onNavigate(4),
      ),
      _HomeCard(
        label: 'Import',
        icon: Icons.document_scanner_rounded,
        tint: AppColors.tintTeal,
        iconColor: AppColors.primaryDark,
        onTap: () async {
          if (!await requireEdit(context)) return;
          if (context.mounted) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ImportScreen()));
          }
        },
      ),
      _HomeCard(
        label: 'Dashboard',
        icon: Icons.dashboard_rounded,
        tint: AppColors.tintSlate,
        iconColor: AppColors.primaryDark,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const DashboardScreen())),
      ),
      _HomeCard(
        label: 'Profile',
        icon: Icons.person_rounded,
        tint: AppColors.tintTeal,
        iconColor: AppColors.primaryDark,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ProfileScreen(
                    onLoggedOut: () => onNavigate(-1)))),
      ),
      _HomeCard(
        label: 'Support',
        icon: Icons.headset_mic_rounded,
        tint: AppColors.tintBlue,
        iconColor: Colors.blue.shade800,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => const SupportScreen())),
      ),
      _HomeCard(
        label: 'Invite karein',
        icon: Icons.card_giftcard_rounded,
        tint: AppColors.tintAmber,
        iconColor: AppColors.amber,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => const InviteScreen())),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('QistBook'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_rounded),
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                        onLoggedOut: () => onNavigate(-1)))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.m),
        children: [
          const ReadOnlyBanner(),
          const SizedBox(height: AppSpace.s),
          Text(
            'Assalam-o-Alaikum${name.isEmpty ? '' : ', $name'}',
            style: AppText.h1,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(fmtDay(DateTime.now()),
              style: AppText.body.copyWith(color: AppColors.grey)),
          const SizedBox(height: AppSpace.l),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpace.m,
              crossAxisSpacing: AppSpace.m,
              childAspectRatio: 1.35,
            ),
            itemCount: cards.length,
            itemBuilder: (context, i) => _card(context, cards[i]),
          ),
          const SizedBox(height: AppSpace.l),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, _HomeCard c) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: c.onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(AppSpace.m),
        decoration: BoxDecoration(
          color: c.tint,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(c.icon, size: 44, color: c.iconColor),
                if (c.badge != null)
                  Positioned(
                    right: -14,
                    top: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        c.badge!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: c.badgeSmall ? 13 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s),
            Text(c.label,
                textAlign: TextAlign.center, style: AppText.title),
          ],
        ),
      ),
    );
  }
}

class _HomeCard {
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String? badge;
  final bool badgeSmall;
  final VoidCallback onTap;

  _HomeCard({
    required this.label,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.onTap,
    this.badge,
    this.badgeSmall = false,
  });
}
