/// Support screen: bara WhatsApp "Chat Support" button + "Call Support"
/// button + support number display (edit icon se change ho sake).
/// Number shared_prefs ("support_number") me persisted hai. Pehli dafa
/// set nahi hoga → button dabane par friendly dialog khulta hai.
library;

import 'package:flutter/material.dart';

import '../services/error_log.dart';
import '../services/reminders.dart';
import '../services/support_service.dart';
import '../theme/app_theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  String? _number;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await SupportService.getNumber();
    if (mounted) {
      setState(() {
        _number = n;
        _loading = false;
      });
    }
  }

  /// Number set nahi to friendly dialog; set ho to number return.
  Future<String?> _ensureNumber() async {
    if (_number != null && _number!.isNotEmpty) return _number;
    final ctrl = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: const Text('Support number set karein'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jis number par madad chahiye wo yahan likhen. Ye number isi phone me save rahega.',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Support ka mobile number',
                  hintText: '03XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone_rounded),
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
                if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                  setD(() =>
                      err = 'Poora mobile number likhen (kam az kam 10 digits)');
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
    await SupportService.setNumber(value);
    if (mounted) {
      setState(() => _number = value);
      showAppSnack(context, 'Support number save ho gaya');
    }
    return value;
  }

  Future<void> _editNumber() async {
    final ctrl = TextEditingController(text: _number ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Support number badlo'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          style: AppText.body,
          decoration: const InputDecoration(
            labelText: 'Support ka mobile number',
            prefixIcon: Icon(Icons.phone_rounded),
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
    if (value.replaceAll(RegExp(r'\D'), '').length < 10) {
      showAppSnack(context, 'Poora mobile number likhen');
      return;
    }
    await SupportService.setNumber(value);
    setState(() => _number = value);
    showAppSnack(context, 'Support number badal diya');
  }

  Future<void> _chatTap() async {
    final n = await _ensureNumber();
    if (n == null || !mounted) return;
    const msg =
        'Assalam-o-Alaikum, mujhe QistBook me madad chahiye';
    final ok = await openWhatsAppNumber(n, msg);
    if (!ok && mounted) {
      ErrorLog.log('Support chat', 'WhatsApp nahi khul saka: $n');
      showAppSnack(context,
          'WhatsApp nahi khul saka — number check karein');
    }
  }

  Future<void> _callTap() async {
    final n = await _ensureNumber();
    if (n == null || !mounted) return;
    final ok = await dialNumber(n);
    if (!ok && mounted) {
      ErrorLog.log('Support call', 'Dialer nahi khul saka: $n');
      showAppSnack(context, 'Dialer nahi khul saka');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support / Madad')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.l),
              children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: AppColors.tintTeal,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                        Icons.headset_mic_rounded,
                        size: 60,
                        color: AppColors.primaryDark),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                const Text(
                  'Koi masla ho to hum se rabta karein',
                  textAlign: TextAlign.center,
                  style: AppText.title,
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Neeche button dabao — WhatsApp chat khul jayegi ya call lag jayegi.',
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: AppColors.grey),
                ),
                const SizedBox(height: AppSpace.l),
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.m,
                        vertical: AppSpace.s),
                    leading: const Icon(Icons.support_agent_rounded,
                        size: 40, color: AppColors.primary),
                    title: const Text('Support number',
                        style: AppText.label),
                    subtitle: Text(
                      _number ?? 'Abhi set nahi hua',
                      style: AppText.bodyBold,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_rounded,
                          size: 30, color: AppColors.primary),
                      tooltip: 'Number badlo',
                      onPressed: _editNumber,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.l),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat_rounded, size: 30),
                    label: const Text('Chat Support'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.okGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(64, 72),
                      textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _chatTap,
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.call_rounded, size: 30),
                    label: const Text('Call Support'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 72),
                      textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _callTap,
                  ),
                ),
                const SizedBox(height: AppSpace.l),
                Text(
                  'Support ka waqt: subah 9 se raat 9 (peer se hafta).',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(fontSize: 15),
                ),
              ],
            ),
    );
  }
}
