/// Backup & Restore screen (Profile → Backup).
/// "Backup banao" → copy Downloads me + share option.
/// "Restore" → file chuno → validate → counts ke sath confirm → replace →
/// data wahin reload + success dialog (reset flows me login par wapas).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/access_control.dart';
import '../services/backup_service.dart';
import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';

class BackupScreen extends StatefulWidget {
  /// Sirf reset/repair flows ke liye: restore ke baad login par wapas jao.
  /// Aam user flow (Profile) me false — data WAHIN reload hota hai aur
  /// user ko customers ki tadaad ke sath success dikhta hai (v1.0.38:
  /// Qais ki shikayat thi "restore click karo to home khul jata hai,
  /// data restore nahi hota" — purana login-bounce hi wo confusion tha).
  final VoidCallback onRestoreDone;
  final bool bounceToLogin;
  const BackupScreen(
      {super.key, required this.onRestoreDone, this.bounceToLogin = false});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String get _uid => AuthScope.of(context).auth.currentUser!.id;

  DateTime? _last;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final t = await BackupService.lastBackupAt(_uid);
    if (mounted) setState(() => _last = t);
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final path = await BackupService.makeBackup(_uid);
      if (!mounted) return;
      if (path == null) {
        await showFriendlyError(context,
            'Backup nahi ban saka. Storage ki ijazat check karein ya dobara koshish karein.',
            screen: 'Backup');
        return;
      }
      await _loadLast();
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup ban gaya'),
          content: Text(
            'File save ho gayi:\n${path.split('/').last}\n\nIsay WhatsApp/email par khud ko bhej len taake phone kho jaye to data mehfooz rahe.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bas ho gaya')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Share karo')),
          ],
        ),
      );
      if (share == true) {
        await BackupService.shareBackup(path);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (!await requireEdit(context)) return;
    final file = await BackupService.pickBackupFile();
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final valid = await BackupService.isValidBackup(file);
      if (!mounted) return;
      if (!valid) {
        await showFriendlyError(context,
            'Ye file asli QistBook backup nahi lagti (kharab ya ghalat file). Doosri file chuno.',
            screen: 'Restore');
        return;
      }
      // Pehle se batao: is file me kitne customers hain aur abhi kitne
      // mitenge — andhe me restore nahi hoga.
      final incoming = await BackupService.countCustomers(file);
      if (!mounted) return;
      final store = Provider.of<CustomerStore>(context, listen: false);
      final current = store.customers.length;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore karein?'),
          content: Text(
            'Is file me ${incoming ?? '?'} customers ka data hai.\n'
            'Abhi app me $current customers hain — wo HATA kar file wala data aa jayega.\n\n'
            'Pehle "Backup banao" se current data mehfooz kar len.',
            style: AppText.body,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Nahi')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dueRed),
                child: const Text('Haan, restore karo')),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final ok = await BackupService.restoreFrom(_uid, file);
      if (!mounted) return;
      if (!ok) {
        await showFriendlyError(
            context, 'Restore nahi ho saka. File dobara check karein.',
            screen: 'Restore');
        return;
      }
      if (widget.bounceToLogin) {
        // Reset/repair flow: purana rawaiya — login se dobara shuru.
        showAppSnack(context, 'Restore ho gaya — dobara login karein');
        widget.onRestoreDone();
        return;
      }
      // Aam flow (v1.0.38): data WAHIN reload karo — login bounce khatam.
      // User ko tadaad ke sath pakka saboot mile ke data aa gaya hai.
      await store.init(_uid);
      if (!mounted) return;
      final loaded = store.customers.length;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore ho gaya ✓'),
          content: Text(
            '$loaded customers ab app me aa gaye hain.\n'
            'Outstanding list khol kar dekho — data wahan hoga.',
            style: AppText.body,
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Theek hai')),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.l),
              children: [
                Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: const BoxDecoration(
                      color: AppColors.tintBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                        Icons.cloud_upload_rounded,
                        size: 54,
                        color: Colors.blue),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                const Text(
                  'Apka data = apki rozi',
                  textAlign: TextAlign.center,
                  style: AppText.h2,
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Phone kho jaye ya kharab ho jaye to backup se sab wapas aa jata hai. Hafte me ek dafa backup zaroor banao.',
                  textAlign: TextAlign.center,
                  style: AppText.body
                      .copyWith(color: AppColors.grey),
                ),
                const SizedBox(height: AppSpace.l),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history_rounded,
                        size: 36, color: AppColors.primary),
                    title: const Text('Aakhri backup',
                        style: AppText.label),
                    subtitle: Text(
                      _last == null
                          ? 'Abhi tak koi backup nahi banaya'
                          : fmtDayTime(_last!),
                      style: AppText.bodyBold,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.backup_rounded,
                        size: 30),
                    label: const Text('Backup banao'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 68),
                      textStyle: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _backup,
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore_rounded,
                        size: 30),
                    label: const Text('Restore karo'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 68),
                      textStyle: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800),
                    ),
                    onPressed: _restore,
                  ),
                ),
                const SizedBox(height: AppSpace.l),
                Card(
                  color: AppColors.tintAmber,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpace.m),
                    child: Text(
                      'Ehtiyat: Restore se current data mit jata hai. Pehle "Backup banao" dabao, phir restore karo.',
                      style: AppText.body,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
