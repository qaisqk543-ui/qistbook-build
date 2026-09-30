/// "Masla hal karein" (Troubleshooting) — Profile aur Support dono se reachable.
/// - Data refresh, cache clear, database check & repair
/// - Error history (aakhri 50), support ko report (WhatsApp)
/// - Danger zone: app reset (double confirm + backup mashwara)
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/access_control.dart';
import '../services/backup_service.dart';
import '../services/call_reminders.dart';
import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../services/reminders.dart';
import '../services/support_service.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'backup_screen.dart';
import 'self_repair_screen.dart';
import 'support_screen.dart';

class TroubleshootScreen extends StatefulWidget {
  /// App reset hone par login screen par wapas le jao.
  final VoidCallback onResetDone;
  const TroubleshootScreen({super.key, required this.onResetDone});

  @override
  State<TroubleshootScreen> createState() =>
      _TroubleshootScreenState();
}

class _TroubleshootScreenState extends State<TroubleshootScreen> {
  String get _uid => AuthScope.of(context).auth.currentUser!.id;
  bool _busy = false;

  Future<void> _refreshData() async {
    setState(() => _busy = true);
    try {
      final store =
          Provider.of<CustomerStore>(context, listen: false);
      await store.refreshData();
      final n = await store.maybeRollover();
      if (mounted) {
        showAppSnack(context,
            n > 0 ? 'Data refresh ho gaya ($n due update)' : 'Data refresh ho gaya — totals dobara calculate ho gaye');
      }
    } catch (e) {
      if (mounted) {
        await showFriendlyError(
            context, 'Data refresh nahi ho saka: $e',
            screen: 'Troubleshoot');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cache saaf karein?'),
        content: const Text(
          'Aarzi (temporary) files delete hongi. Apka customers ka data MEHFOOZ rahega, kuch nahi mitega.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, saaf karo')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await BackupService.clearCache();
      if (mounted) {
        showAppSnack(
            context, 'Cache saaf ho gaya ($n files)');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkDb() async {
    setState(() => _busy = true);
    try {
      final res = await BackupService.checkIntegrity(_uid);
      if (!mounted) return;
      if (res == 'ok') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Database theek hai'),
            content: const Text(
              'Check me koi kharabi nahi mili. Apka data mehfooz hai.',
              style: AppText.body,
            ),
            actions: [
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Shukriya')),
            ],
          ),
        );
      } else {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Database me kharabi!'),
            content: Text(
              'Check me masla mila:\n$res\n\nBackup se restore karna sab se mehfooz hal hai.',
              style: AppText.body,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Baad me')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Restore screen kholo')),
            ],
          ),
        );
        if (go == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BackupScreen(
                  onRestoreDone: widget.onResetDone),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showErrorHistory() {
    final entries = ErrorLog.entries;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error history'),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? const Text(
                  'Koi error record nahi — sab theek chal raha hai.',
                  style: AppText.body)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const Divider(),
                  itemBuilder: (_, i) {
                    final e = entries[
                        entries.length - 1 - i]; // newest first
                    return Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(fmtDayTime(e.time),
                            style: AppText.caption
                                .copyWith(fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(e.message,
                            style: AppText.body
                                .copyWith(fontSize: 16)),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Band karo')),
        ],
      ),
    );
  }

  Future<String> _phoneModel() async {
    try {
      final info = DeviceInfoPlugin();
      final a = await info.androidInfo;
      final model = '${a.manufacturer} ${a.model}'.trim();
      return model.isEmpty ? 'Unknown phone' : model;
    } catch (e) {
      ErrorLog.log('Troubleshoot device', e);
      return 'Unknown phone';
    }
  }

  Future<void> _testNotification() async {
    setState(() => _busy = true);
    try {
      final ok = await CallReminderService.testNotification();
      if (!mounted) return;
      final hasPerm = await CallReminderService.hasNotificationPermission();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reminder test'),
          content: Text(
            ok
                ? 'Test notification bhej di!${hasPerm ? '' : '\n\n⚠️ Notification permission OFF hai — phone ki Settings > Apps > QistBook > Notifications me ON karo.'}\n\nAgar awaz nahi ayi to phone ka volume / silent mode check karo.'
                : 'Notification bhejne me masla aaya.\n\nPhone ki Settings > Apps > QistBook > Notifications me ijazat ON karo.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Theek hai'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    var number = await SupportService.getNumber();
    if (!mounted) return;
    if (number == null || number.isEmpty) {
      // Pehle Support screen kholo taake number set ho jaye, phir report bhejo.
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
    setState(() => _busy = true);
    try {
      final model = await _phoneModel();
      final last = ErrorLog.last;
      final msg = 'Assalam-o-Alaikum, mujhe QistBook me madad chahiye\n'
          'App version: $kAppVersion\n'
          'Phone: $model\n'
          'Aakhri error: ${last == null ? 'koi nahi' : '${fmtDayTime(last.time)} — ${last.message}'}';
      final ok = await openWhatsAppNumber(number, msg);
      if (!ok && mounted) {
        await showFriendlyError(
            context, 'WhatsApp nahi khul saka. Support number check karein.',
            screen: 'Troubleshoot report');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetApp() async {
    if (!await requireEdit(context)) return;
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App reset karein?'),
        content: const Text(
          'DANGER: Apka SAARA data (customers, payments, vouchers) is phone se MIT jayega!\n\nPehle Profile → Backup se backup zaroor banao.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi, rehne do')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dueRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aage barho')),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pakka? Aakhri warning'),
        content: const Text(
          'Ye aakhri mauqa hai. "Haan" dabate hi sab data delete ho jayega aur ap logout ho jayenge.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ruko, backup banana hai')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dueRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, sab delete karo')),
        ],
      ),
    );
    if (second != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final store =
          Provider.of<CustomerStore>(context, listen: false);
      await store.closeDb();
      await BackupService.wipeUserData(_uid);
      await AuthScope.of(context).auth.logout();
      if (mounted) widget.onResetDone();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showFriendlyError(
            context, 'Reset nahi ho saka: $e',
            screen: 'Troubleshoot reset');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: const Text('Masla hal karein')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding:
                  const EdgeInsets.all(AppSpace.l),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Text('🛠️',
                        style: TextStyle(fontSize: 34)),
                    label: const Text('Khud Theek Karo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primaryDark,
                      minimumSize:
                          const Size(64, 84),
                      textStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SelfRepairScreen(
                          uid: _uid,
                          onRestoreDone:
                              widget.onResetDone,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Ek dabao — app khud check karke maslay theek karegi.',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(
                      color: AppColors.grey),
                ),
                const SizedBox(height: AppSpace.l),
                const Text(
                  'Ya khud ye steps try karein',
                  style: AppText.title,
                ),
                const SizedBox(height: AppSpace.m),
                _tile(
                  Icons.refresh_rounded,
                  AppColors.tintTeal,
                  AppColors.primaryDark,
                  'Data refresh karein',
                  'DB se dobara load + totals recalculate',
                  _refreshData,
                ),
                _tile(
                  Icons.cleaning_services_rounded,
                  AppColors.tintBlue,
                  Colors.blue,
                  'Cache saaf karein',
                  'Aarzi files delete — data mehfooz rahega',
                  _clearCache,
                ),
                _tile(
                  Icons.health_and_safety_rounded,
                  AppColors.tintGreen,
                  AppColors.okGreen,
                  'Database check & repair',
                  'Data me kharabi check karo',
                  _checkDb,
                ),
                _tile(
                  Icons.history_rounded,
                  AppColors.tintAmber,
                  AppColors.amber,
                  'Error history',
                  'Aakhri masail ki list dekho',
                  _showErrorHistory,
                ),
                _tile(
                  Icons.report_rounded,
                  AppColors.tintTeal,
                  AppColors.primaryDark,
                  'Masla report karein',
                  'WhatsApp par support ko bhejo (auto-filled)',
                  _report,
                ),
                _tile(
                  Icons.notifications_active_rounded,
                  AppColors.tintGreen,
                  AppColors.okGreen,
                  'Reminder sound test',
                  'Notification bajao — awaz aa rahi hai?',
                  _testNotification,
                ),
                const SizedBox(height: AppSpace.l),
                const Text('Danger zone',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dueRed)),
                const SizedBox(height: AppSpace.s),
                Card(
                  color: const Color(0xFFFDECEA),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: AppSpace.m,
                            vertical: AppSpace.s),
                    leading: const Icon(
                        Icons.delete_forever_rounded,
                        size: 40,
                        color: AppColors.dueRed),
                    title: const Text('App reset karein',
                        style: AppText.bodyBold),
                    subtitle: const Text(
                        'Saara data delete + logout',
                        style: AppText.body),
                    trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 32,
                        color: AppColors.dueRed),
                    onTap: _resetApp,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(IconData icon, Color tint, Color color,
      String title, String sub, VoidCallback onTap) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m, vertical: AppSpace.s),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, size: 30, color: color),
        ),
        title: Text(title, style: AppText.bodyBold),
        subtitle:
            Text(sub, style: AppText.body.copyWith(fontSize: 16)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 32, color: AppColors.grey),
        onTap: onTap,
      ),
    );
  }
}
