/// Self Repair screen: "🛠️ Khud Theek Karo" dabane par automated
/// sequence chalta hai — har step Roman Urdu me live dikhta hai
/// (spinner → ✓ / 🔧 / ⚠ / ✗). Aakhir me summary card + support button.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../services/reminders.dart';
import '../services/self_repair.dart';
import '../services/support_service.dart';
import '../theme/app_theme.dart';
import 'backup_screen.dart';
import 'support_screen.dart';

class SelfRepairScreen extends StatefulWidget {
  final String uid;
  final VoidCallback onRestoreDone;
  const SelfRepairScreen(
      {super.key, required this.uid, required this.onRestoreDone});

  @override
  State<SelfRepairScreen> createState() => _SelfRepairScreenState();
}

class _SelfRepairScreenState extends State<SelfRepairScreen> {
  final List<RepairStep> _steps = [];
  bool _done = false;
  StreamSubscription<RepairStep>? _sub;

  @override
  void initState() {
    super.initState();
    final store = Provider.of<CustomerStore>(context, listen: false);
    _sub = SelfRepair.run(widget.uid, store).listen((s) {
      if (!mounted) return;
      setState(() {
        final i = _steps.indexWhere((e) => e.id == s.id);
        if (i == -1) {
          _steps.add(s);
        } else {
          _steps[i] = s;
        }
        if (s.status != RepairStatus.running &&
            s.status != RepairStatus.pending &&
            _steps.length == 7 &&
            _steps.every((e) =>
                e.status != RepairStatus.running &&
                e.status != RepairStatus.pending)) {
          _done = true;
        }
      });
    }, onDone: () {
      if (mounted) setState(() => _done = true);
    }, onError: (e) {
      ErrorLog.log('SelfRepair UI', e);
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _supportSend() async {
    var number = await SupportService.getNumber();
    if (!mounted) return;
    if (number == null || number.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SupportScreen()),
      );
      if (!mounted) return;
      number = await SupportService.getNumber();
      if (!mounted) return;
      if (number == null || number.isEmpty) {
        showAppSnack(
            context, 'Support number set kiye baghair report nahi bhej sakte');
        return;
      }
    }
    final msg = SelfRepair.summaryText(_steps);
    final ok = await openWhatsAppNumber(number, msg);
    if (!ok && mounted) {
      await showFriendlyError(context, 'WhatsApp nahi khul saka.',
          screen: 'SelfRepair');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixed = _steps.where((s) => s.status == RepairStatus.fixed).length;
    final bad = _steps
        .where((s) =>
            s.status == RepairStatus.fail || s.status == RepairStatus.warn)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Khud Theek Karo')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.l),
        children: [
          const Text(
            'App khud maslay dhoond kar theek kar rahi hai…',
            style: AppText.title,
          ),
          const SizedBox(height: AppSpace.m),
          ..._steps.map(_stepTile),
          if (_done) ...[
            const SizedBox(height: AppSpace.l),
            _summaryCard(fixed, bad),
          ],
          const SizedBox(height: AppSpace.l),
        ],
      ),
    );
  }

  Widget _stepTile(RepairStep s) {
    Widget icon;
    Color bg;
    switch (s.status) {
      case RepairStatus.running:
        icon = const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
        bg = AppColors.tintSlate;
        break;
      case RepairStatus.ok:
        icon = const Icon(Icons.check_circle_rounded,
            size: 34, color: AppColors.okGreen);
        bg = AppColors.tintGreen;
        break;
      case RepairStatus.fixed:
        icon = const Icon(Icons.handyman_rounded, size: 32, color: Colors.blue);
        bg = AppColors.tintBlue;
        break;
      case RepairStatus.warn:
        icon = const Icon(Icons.warning_amber_rounded,
            size: 34, color: AppColors.amber);
        bg = AppColors.tintAmber;
        break;
      case RepairStatus.fail:
        icon =
            const Icon(Icons.cancel_rounded, size: 34, color: AppColors.dueRed);
        bg = AppColors.tintRose;
        break;
      case RepairStatus.pending:
        icon = const Icon(Icons.hourglass_empty_rounded,
            size: 32, color: AppColors.grey);
        bg = AppColors.tintSlate;
        break;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(16)),
              child: Center(child: icon),
            ),
            const SizedBox(width: AppSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: AppText.bodyBold),
                  if (s.detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(s.detail,
                        style: AppText.body
                            .copyWith(fontSize: 16, color: AppColors.grey)),
                  ],
                  if (s.actionLabel != null &&
                      s.status != RepairStatus.running) ...[
                    const SizedBox(height: AppSpace.s),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.restore_rounded),
                      label: Text(s.actionLabel!),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dueRed),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              BackupScreen(onRestoreDone: widget.onRestoreDone),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int fixed, int bad) {
    final allOk = fixed == 0 && bad == 0;
    return Card(
      color: allOk ? AppColors.tintGreen : AppColors.tintAmber,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.l),
        child: Column(
          children: [
            Text(
              allOk ? '✅ Sab theek hai' : '🔧 $fixed maslay theek kar diye',
              style: AppText.h2,
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              allOk
                  ? 'Koi masla nahi mila. App bilkul theek chal rahi hai.'
                  : bad > 0
                      ? '$bad cheezain ab bhi tawajju mangti hain (upar dekho).'
                      : 'Baqi sab theek hai.',
              style: AppText.body,
            ),
            if (bad > 0) ...[
              const SizedBox(height: AppSpace.m),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_rounded, size: 28),
                  label: const Text('Support ko bhejo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.okGreen,
                    minimumSize: const Size(64, 64),
                    textStyle: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _supportSend,
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Band karo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
