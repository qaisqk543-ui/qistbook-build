/// Read-only mode (subscription expire): data sab DEKH sakte hain,
/// lekin koi update/edit NAHI. Central `canEdit` — har mutating
/// button/action isay check karta hai. Owner par kabhi read-only nahi.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/paywall_screen.dart';
import '../theme/app_theme.dart';
import 'subscription_service.dart';

class AccessControl extends ChangeNotifier {
  String? _uid;
  String? get uid => _uid;

  /// true = sirf dekh sakte hain, edit nahi.
  bool readOnly = true;

  bool get canEdit => !readOnly;

  Future<void> init(String uid) async {
    _uid = uid;
    await refresh();
  }

  /// Subscription status dobara check karo (start + resume par).
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) return;
    final active = await SubscriptionService.isActive(uid);
    final next = !active;
    if (next != readOnly) {
      readOnly = next;
      notifyListeners();
    }
  }
}

/// Mutating action se pehle call karo. Read-only me friendly dialog
/// "Subscription renew karwao" + Renew button (paywall khulta hai).
/// Returns true agar action jaari rakh sakte hain.
Future<bool> requireEdit(BuildContext context) async {
  final access = context.read<AccessControl>();
  if (access.canEdit) return true;
  final uid = access.uid;
  if (!context.mounted) return false;
  final renew = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Subscription khatam'),
      content: const Text(
        'Subscription renew karwao taake update kar sako. Abhi sirf dekh sakte hain.',
        style: AppText.body,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Baad me')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Renew karein')),
      ],
    ),
  );
  if (renew == true && uid != null) {
    final accessRef = context.read<AccessControl>();
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(
          uid: uid,
          onActivated: () async {
            await accessRef.refresh();
          },
        ),
      ),
    );
    return accessRef.canEdit;
  }
  return false;
}

/// Slim banner: Home/Outstanding/Voucher/Received appbars ke neeche.
/// Sirf read-only mode me dikhta hai.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessControl>();
    if (!access.readOnly) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.m, vertical: 10),
      color: AppColors.tintAmber,
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 26, color: AppColors.amber),
          const SizedBox(width: AppSpace.s),
          const Expanded(
            child: Text(
              '⚠️ Subscription khatam — sirf dekh sakte hain.',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink),
            ),
          ),
          TextButton(
            onPressed: () => requireEdit(context),
            child: const Text('Renew karein'),
          ),
        ],
      ),
    );
  }
}
