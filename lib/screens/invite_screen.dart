/// Invite screen: dawati message preview + "Share karein" (share_plus)
/// + "Link copy karein" (clipboard). Link shared_prefs me persisted;
/// default khaali — pehli dafa friendly dialog se manga jata hai.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/error_log.dart';
import '../services/invite_service.dart';
import '../theme/app_theme.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  String? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await InviteService.getLink();
    if (mounted) {
      setState(() {
        _link = l;
        _loading = false;
      });
    }
  }

  /// Link set nahi to friendly dialog; set ho to link return.
  Future<String?> _ensureLink() async {
    if (_link != null && _link!.isNotEmpty) return _link;
    final ctrl = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: const Text('Invite link set karein'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Play Store ya APK ka link yahan lagao — yehi link doston ko jayega.',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.url,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Invite link (https://…)',
                  prefixIcon: Icon(Icons.link_rounded),
                ),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body.copyWith(
                          color: AppColors.dueRed)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (!v.startsWith('http://') &&
                    !v.startsWith('https://')) {
                  setD(() => err =
                      'Poora link likhen (https:// se shuru ho)');
                  return;
                }
                Navigator.pop(dctx, true);
              },
              child: const Text('Save karo'),
            ),
          ],
        ),
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return null;
    await InviteService.setLink(value);
    if (mounted) {
      setState(() => _link = value);
      showAppSnack(context, 'Invite link save ho gaya');
    }
    return value;
  }

  Future<void> _editLink() async {
    final ctrl = TextEditingController(text: _link ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Invite link badlo'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          style: AppText.body,
          decoration: const InputDecoration(
            labelText: 'Invite link (https://…)',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Save karo')),
        ],
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (value.isNotEmpty &&
        !value.startsWith('http://') &&
        !value.startsWith('https://')) {
      showAppSnack(context, 'Poora link likhen (https:// se shuru ho)');
      return;
    }
    await InviteService.setLink(value);
    setState(() => _link = value.isEmpty ? null : value);
    showAppSnack(context, 'Invite link badal diya');
  }

  Future<void> _share() async {
    final link = await _ensureLink();
    if (link == null || !mounted) return;
    try {
      await Share.share(InviteService.fullMessage(link),
          subject: 'QistBook');
    } catch (e) {
      ErrorLog.log('Invite share', e);
      if (mounted) showAppSnack(context, 'Share nahi ho saka');
    }
  }

  Future<void> _copy() async {
    final link = await _ensureLink();
    if (link == null || !mounted) return;
    await Clipboard.setData(
        ClipboardData(text: InviteService.fullMessage(link)));
    if (mounted) showAppSnack(context, 'Link copy ho gaya');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite karein')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.l),
              children: [
                Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      color: AppColors.tintAmber,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                        Icons.card_giftcard_rounded,
                        size: 54,
                        color: AppColors.amber),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                const Text(
                  'Doston ko QistBook ka tohfa den',
                  textAlign: TextAlign.center,
                  style: AppText.h2,
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Jo dukandaar qiston ka hisab rakhte hain, unhe ye app bhejo.',
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: AppColors.grey),
                ),
                const SizedBox(height: AppSpace.l),
                // Message preview card
                Card(
                  color: AppColors.tintTeal,
                  child: Padding(
                    padding:
                        const EdgeInsets.all(AppSpace.l),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                                Icons.format_quote_rounded,
                                size: 32,
                                color: AppColors.primary),
                            const SizedBox(width: AppSpace.s),
                            const Text('Message preview',
                                style: AppText.label),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s),
                        Text(
                          InviteService.shareMessage,
                          style: AppText.body,
                        ),
                        const SizedBox(height: AppSpace.s),
                        Text(
                          _link ?? '(link abhi set nahi hua)',
                          style: AppText.bodyBold.copyWith(
                            color: _link == null
                                ? AppColors.grey
                                : AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Link badlo'),
                    onPressed: _editLink,
                  ),
                ),
                const SizedBox(height: AppSpace.s),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.share_rounded,
                        size: 30),
                    label: const Text('Share karein'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 72),
                      textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _share,
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(
                        Icons.content_copy_rounded,
                        size: 28),
                    label:
                        const Text('Link copy karein'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 64),
                      textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _copy,
                  ),
                ),
              ],
            ),
    );
  }
}
