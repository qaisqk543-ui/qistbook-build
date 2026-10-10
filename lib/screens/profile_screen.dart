/// Profile: photo, naam edit, email/phone (read-only), text-size setting,
/// Support, Invite, Backup, App Lock, Privacy/Terms, Help, Troubleshooting,
/// logout, app version. Home card + Home appbar icon se khulta hai.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/app_lock_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/error_log.dart';
import '../services/shop_profile.dart';
import '../theme/app_theme.dart';
import 'admin_screen.dart';
import 'app_lock_screen.dart';
import 'auth_screen.dart';
import 'backup_screen.dart';
import 'help_screen.dart';
import 'invite_screen.dart';
import 'privacy_screen.dart';
import 'support_screen.dart';
import 'troubleshoot_screen.dart';

class ProfileScreen extends StatefulWidget {
  /// Logout hone par (login screen par wapas jana hai).
  final VoidCallback onLoggedOut;
  const ProfileScreen({super.key, required this.onLoggedOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AuthService get _auth => AuthScope.of(context).auth;
  String get _uid => _auth.currentUser!.id;
  bool _pinOn = false;
  String _shopName = defaultShopName;

  @override
  void initState() {
    super.initState();
    _loadPin();
    _loadShopName();
  }

  Future<void> _loadShopName() async {
    final n = await loadShopName();
    if (mounted) setState(() => _shopName = n);
  }

  /// Dukaan ka naam badlo — WhatsApp/SMS auto-messages me wahi naam jayega.
  Future<void> _editShopName() async {
    final ctrl = TextEditingController(text: _shopName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dukaan ka naam'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.words,
              style: AppText.body,
              decoration: const InputDecoration(
                  labelText: 'Dukaan / shop ka naam'),
            ),
            const SizedBox(height: AppSpace.s),
            Text(
              'Ye naam WhatsApp aur SMS ke auto-message me aayega.',
              style:
                  AppText.caption.copyWith(color: AppColors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      showAppSnack(context, 'Naam khaali nahi ho sakta');
      return;
    }
    await saveShopName(name);
    if (mounted) {
      setState(() => _shopName = name);
      showAppSnack(context, 'Dukaan ka naam badal diya');
    }
  }

  Future<void> _loadPin() async {
    final on = await AppLockService.isEnabled(_uid);
    if (mounted) setState(() => _pinOn = on);
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dest = File(p.join(docs.path,
          'profile_${_auth.currentUser!.id}.jpg'));
      await File(picked.path).copy(dest.path);
      final user =
          _auth.currentUser!.copyWith(photoPath: dest.path);
      await _auth.updateProfile(user);
      if (mounted) {
        setState(() {});
        showAppSnack(context, 'Photo badal di');
      }
    } catch (e) {
      ErrorLog.log('Profile photo', e);
      if (mounted) showAppSnack(context, 'Photo save nahi ho saki');
    }
  }

  Future<void> _editName() async {
    final ctrl =
        TextEditingController(text: _auth.currentUser?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naam badlo'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.words,
          style: AppText.body,
          decoration:
              const InputDecoration(labelText: 'Apna naam'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    // Pehle text parho, phir dispose — warna naam ghaib ho jata hai.
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      showAppSnack(context, 'Naam khaali nahi ho sakta');
      return;
    }
    await _auth.updateProfile(_auth.currentUser!.copyWith(name: name));
    if (mounted) {
      setState(() {});
      showAppSnack(context, 'Naam badal diya');
    }
  }

  /// App Lock tile tap: off ho to set karo, on ho to change/remove.
  Future<void> _appLockTap() async {
    if (!_pinOn) {
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AppLockScreen(
            uid: _uid,
            mode: PinMode.set,
            onDone: (v) => Navigator.pop(context, v),
          ),
        ),
      );
      if (done == true && mounted) {
        setState(() => _pinOn = true);
        showAppSnack(context, 'App Lock lag gaya');
      }
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App Lock'),
        content: const Text('PIN badalna hai ya lock hatana hai?',
            style: AppText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Lock hatao',
                  style: TextStyle(color: AppColors.dueRed))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('PIN badlo')),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'change') {
      final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AppLockScreen(
            uid: _uid,
            mode: PinMode.change,
            onDone: (v) => Navigator.pop(context, v),
          ),
        ),
      );
      if (done == true && mounted) {
        showAppSnack(context, 'Naya PIN lag gaya');
      }
    } else if (action == 'remove') {
      // Pehle PIN verify, phir hatao.
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AppLockScreen(
            uid: _uid,
            mode: PinMode.verify,
            onDone: (v) => Navigator.pop(context, v),
          ),
        ),
      );
      if (verified == true) {
        await AppLockService.clearPin(_uid);
        if (mounted) {
          setState(() => _pinOn = false);
          showAppSnack(context, 'App Lock hata diya');
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text(
            'Apka data is phone me mehfooz rahega. Dobara login karke wapas aa sakte hain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, logout karo')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _auth.logout();
    widget.onLoggedOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final photoFile = (user?.photoPath ?? '').isNotEmpty
        ? File(user!.photoPath)
        : null;
    final hasPhoto =
        photoFile != null && photoFile.existsSync();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.l),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 64,
                  backgroundColor: AppColors.tintTeal,
                  backgroundImage:
                      hasPhoto ? FileImage(photoFile) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person_rounded,
                          size: 72,
                          color: AppColors.primaryDark),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _changePhoto,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.m),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(user?.name ?? '',
                      style: AppText.h1,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded,
                      color: AppColors.primary),
                  tooltip: 'Naam badlo',
                  onPressed: _editName,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.s),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.m,
                  vertical: AppSpace.s),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.tintAmber,
                    borderRadius:
                        BorderRadius.circular(16)),
                child: const Icon(Icons.store_rounded,
                    size: 30, color: AppColors.amber),
              ),
              title: const Text('Dukaan ka naam',
                  style: AppText.bodyBold),
              subtitle: Text(_shopName,
                  style:
                      AppText.body.copyWith(fontSize: 16)),
              trailing: const Icon(Icons.edit_rounded,
                  color: AppColors.primary),
              onTap: _editShopName,
            ),
          ),
          const SizedBox(height: AppSpace.m),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                children: [
                  _infoRow(Icons.email_rounded, 'Email',
                      user?.email ?? '—'),
                  const Divider(),
                  _infoRow(Icons.phone_rounded, 'Phone',
                      user?.phone ?? '—'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Text ka size', style: AppText.title),
                  const SizedBox(height: AppSpace.s),
                  Text(
                    'Kamzor nazar ke liye "Bara" chuno — sab kuch bara ho jayega.',
                    style: AppText.body
                        .copyWith(color: AppColors.grey),
                  ),
                  const SizedBox(height: AppSpace.m),
                  _TextSizeSetting(),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          _menuTile(
            Icons.headset_mic_rounded,
            AppColors.tintBlue,
            Colors.blue.shade800,
            'Support / Madad',
            'WhatsApp chat ya call karo',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupportScreen())),
          ),
          _menuTile(
            Icons.card_giftcard_rounded,
            AppColors.tintAmber,
            AppColors.amber,
            'Invite karein',
            'Doston ko app ka link bhejo',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const InviteScreen())),
          ),
          _menuTile(
            Icons.backup_rounded,
            AppColors.tintTeal,
            AppColors.primaryDark,
            'Backup & Restore',
            'Data mehfooz karo / wapas lao',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BackupScreen(
                        onRestoreDone:
                            widget.onLoggedOut))),
          ),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.m,
                  vertical: AppSpace.s),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: AppColors.tintSlate,
                    borderRadius:
                        BorderRadius.circular(16)),
                child: const Icon(Icons.lock_rounded,
                    size: 30,
                    color: AppColors.primaryDark),
              ),
              title: const Text('App Lock',
                  style: AppText.bodyBold),
              subtitle: Text(
                  _pinOn
                      ? 'On hai — khulne par PIN mangegi'
                      : 'Off hai — 4-digit PIN lagao',
                  style: AppText.body
                      .copyWith(fontSize: 16)),
              trailing: Switch(
                value: _pinOn,
                onChanged: (_) => _appLockTap(),
              ),
              onTap: _appLockTap,
            ),
          ),
          _menuTile(
            Icons.menu_book_rounded,
            AppColors.tintGreen,
            AppColors.okGreen,
            'App kaise use karein',
            'Asaan guide — 5 minute me seekho',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const HelpScreen())),
          ),
          _menuTile(
            Icons.handyman_rounded,
            AppColors.tintRose,
            AppColors.dueRed,
            'Masla hal karein',
            'Khud theek karo / troubleshooting',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TroubleshootScreen(
                        onResetDone:
                            widget.onLoggedOut))),
          ),
          _menuTile(
            Icons.privacy_tip_rounded,
            AppColors.tintSlate,
            AppColors.primaryDark,
            'Privacy Policy & Terms',
            'Apka data, apke huqooq',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const PrivacyScreen())),
          ),
          _menuTile(
            Icons.admin_panel_settings_rounded,
            AppColors.tintSlate,
            AppColors.primaryDeep,
            'Admin',
            'Activation code, payment settings',
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        AdminScreen(uid: _uid))),
          ),
          const SizedBox(height: AppSpace.m),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dueRed,
              side: const BorderSide(
                  color: AppColors.dueRed, width: 1.5),
            ),
            onPressed: _logout,
          ),
          const SizedBox(height: AppSpace.xl),
          Center(
            child: Text('QistBook v$kAppVersion',
                style:
                    AppText.caption.copyWith(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _menuTile(IconData icon, Color tint, Color color,
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
        subtitle: Text(sub,
            style: AppText.body.copyWith(fontSize: 16)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 32, color: AppColors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 28, color: AppColors.primary),
        const SizedBox(width: AppSpace.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.label),
              Text(value.isEmpty ? '—' : value,
                  style: AppText.body),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextSizeSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return SegmentedButton<double>(
      segments: const [
        ButtonSegment(
            value: 1.0,
            label: Text('Normal', style: TextStyle(fontSize: 17)),
            icon: Icon(Icons.text_fields_rounded)),
        ButtonSegment(
            value: 1.3,
            label: Text('Bara', style: TextStyle(fontSize: 17)),
            icon: Icon(Icons.text_increase_rounded)),
      ],
      selected: {settings.textScale},
      onSelectionChanged: (s) =>
          settings.setTextScale(s.first),
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(64, 54),
      ),
    );
  }
}
