/// Admin panel (Profile → Admin): admin PIN gate ke peeche.
/// - "Aaj ka activation code" (bara, copy) — Qais WhatsApp/call par de.
/// - Is device ko activate karo: 30 / 90 / 365 din.
/// - Payment settings editor: fee + JazzCash/Easypaisa/Bank numbers
///   (Qais khud add kare, developer ki zaroorat na ho).
/// - Pehli dafa admin PIN set → ye device owner (lifetime bypass).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/error_log.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  final String uid;
  const AdminScreen({super.key, required this.uid});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _authed = false;
  bool _needsSetup = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final set = await SubscriptionService.adminPinSet();
    if (mounted) {
      setState(() {
        _needsSetup = !set;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_authed
              ? _AdminPinGate(
                  setupMode: _needsSetup,
                  onDone: () => setState(() => _authed = true),
                )
              : _AdminPanel(uid: widget.uid),
    );
  }
}

/// 4-digit PIN gate: pehli dafa set (do dafa), baad me verify.
class _AdminPinGate extends StatefulWidget {
  final bool setupMode;
  final VoidCallback onDone;
  const _AdminPinGate({required this.setupMode, required this.onDone});

  @override
  State<_AdminPinGate> createState() => _AdminPinGateState();
}

class _AdminPinGateState extends State<_AdminPinGate> {
  String _pin = '';
  String? _first;
  String? _err;

  Future<void> _submit() async {
    if (widget.setupMode) {
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
        });
        return;
      }
      if (_pin != _first) {
        setState(() {
          _err = 'Dono PIN same nahi — dobara shuru karein';
          _first = null;
          _pin = '';
        });
        return;
      }
      await SubscriptionService.setAdminPin(_pin);
      if (mounted) {
        showAppSnack(
            context, 'Admin PIN lag gaya — ye device owner hai (lifetime)');
        widget.onDone();
      }
      return;
    }
    final ok = await SubscriptionService.verifyAdminPin(_pin);
    if (!mounted) return;
    if (ok) {
      widget.onDone();
    } else {
      setState(() {
        _err = 'Ghalat PIN';
        _pin = '';
      });
    }
  }

  void _key(String k) {
    setState(() {
      _err = null;
      if (k == 'back') {
        if (_pin.isNotEmpty) {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      } else if (_pin.length < 4) {
        _pin += k;
      }
    });
    if (_pin.length == 4) _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpace.l),
          const Icon(Icons.admin_panel_settings_rounded,
              size: 72, color: AppColors.primaryDark),
          const SizedBox(height: AppSpace.m),
          Text(
              widget.setupMode
                  ? 'Pehli dafa: Admin PIN banao'
                  : 'Admin PIN likhen',
              style: AppText.h2,
              textAlign: TextAlign.center),
          if (widget.setupMode) ...[
            const SizedBox(height: AppSpace.s),
            Text(
              'Ye PIN sirf Qais (owner) ke paas ho. Set karte hi ye device lifetime free ho jayegi.',
              style: AppText.body.copyWith(color: AppColors.grey),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpace.l),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              4,
              (i) => Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      i < _pin.length ? AppColors.primary : AppColors.divider,
                ),
              ),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: AppSpace.m),
            Text(_err!, style: AppText.body.copyWith(color: AppColors.dueRed)),
          ],
          if (widget.setupMode && _first != null) ...[
            const SizedBox(height: AppSpace.s),
            const Text('Dobara likhen', style: AppText.label),
          ],
          const Spacer(),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 12,
            itemBuilder: (ctx, i) {
              const keys = [
                '1',
                '2',
                '3',
                '4',
                '5',
                '6',
                '7',
                '8',
                '9',
                '',
                '0',
                'back'
              ];
              final k = keys[i];
              if (k.isEmpty) {
                return const SizedBox.shrink();
              }
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _key(k);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Center(
                    child: k == 'back'
                        ? const Icon(Icons.backspace_rounded,
                            size: 32, color: AppColors.grey)
                        : Text(k,
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w700)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpace.l),
        ],
      ),
    );
  }
}

class _AdminPanel extends StatefulWidget {
  final String uid;
  const _AdminPanel({required this.uid});

  @override
  State<_AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<_AdminPanel> {
  final _jazz = TextEditingController();
  final _easy = TextEditingController();
  final _bank = TextEditingController();
  final _feeCtrl = TextEditingController();
  String _expiryText = '';
  Map<String, String>? _pending;
  bool _owner = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _jazz.dispose();
    _easy.dispose();
    _bank.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final nums = await SubscriptionService.paymentNumbers();
    final fee = await SubscriptionService.fee();
    final exp = await SubscriptionService.expiryOf(widget.uid);
    final pending = await SubscriptionService.pendingTid(widget.uid);
    final owner = await SubscriptionService.isOwner();
    if (mounted) {
      setState(() {
        _jazz.text = nums['JazzCash'] ?? '';
        _easy.text = nums['Easypaisa'] ?? '';
        _bank.text = nums['Bank'] ?? '';
        _feeCtrl.text = '$fee';
        _pending = pending;
        _owner = owner;
        _expiryText = exp == null
            ? 'Kabhi activate nahi hui'
            : exp.isAfter(DateTime.now())
                ? '${fmtDay(exp)} tak active'
                : '${fmtDay(exp)} ko KHATAM ho gayi';
      });
    }
  }

  Future<void> _activate(int days) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activate karein?'),
        content: Text(
            'Is device ki subscription $days din ke liye active ho jayegi.',
            style: AppText.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, activate karo')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SubscriptionService.activate(widget.uid, days);
      await _load();
      if (mounted) {
        showAppSnack(context, '$days din ke liye activate ho gaya');
      }
    } catch (e) {
      ErrorLog.log('Admin activate', e);
      if (mounted) {
        showAppSnack(context, 'Activate nahi ho saka');
      }
    }
  }

  Future<void> _saveSettings() async {
    final fee =
        int.tryParse(_feeCtrl.text.trim()) ?? SubscriptionService.defaultFee;
    if (fee <= 0) {
      showAppSnack(context, 'Fee sahi likhen');
      return;
    }
    await SubscriptionService.savePaymentSettings(
      feeAmount: fee,
      jazzcash: _jazz.text,
      easypaisa: _easy.text,
      bank: _bank.text,
    );
    if (mounted) {
      showAppSnack(context, 'Payment settings save ho gayi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = SubscriptionService.monthlyCode();
    return ListView(
      padding: const EdgeInsets.all(AppSpace.l),
      children: [
        if (_owner)
          const Card(
            color: AppColors.tintGreen,
            child: Padding(
              padding: EdgeInsets.all(AppSpace.m),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded,
                      size: 32, color: AppColors.okGreen),
                  SizedBox(width: AppSpace.s),
                  Expanded(
                    child: Text(
                        'Owner device — lifetime free, kabhi lock nahi hogi.',
                        style: AppText.bodyBold),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.m),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    size: 36, color: AppColors.amber),
                const SizedBox(width: AppSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Is device ki subscription',
                          style: AppText.label),
                      Text(_expiryText, style: AppText.bodyBold),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s),
        // Activation code
        Card(
          color: AppColors.tintTeal,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.l),
            child: Column(
              children: [
                const Text('Aaj ka activation code', style: AppText.title),
                const SizedBox(height: AppSpace.s),
                Text(
                  code,
                  style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10,
                      color: AppColors.primaryDeep),
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Ye code WhatsApp/call par customer ko batao — wo "Mere paas activation code hai" me likhega.',
                  style: AppText.body.copyWith(color: AppColors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.m),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy_rounded),
                  label: const Text('Copy karo'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      showAppSnack(context, 'Code copy ho gaya');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.s),
        // Activate device
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Is device ko activate karo', style: AppText.title),
                const SizedBox(height: AppSpace.m),
                Row(
                  children: [30, 90, 365]
                      .map((d) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: ElevatedButton(
                                onPressed: () => _activate(d),
                                child: Text('$d din',
                                    style: const TextStyle(fontSize: 17)),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        if (_pending != null) ...[
          const SizedBox(height: AppSpace.s),
          Card(
            color: AppColors.tintAmber,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pending TID claim', style: AppText.title),
                  const SizedBox(height: 4),
                  Text(
                    'TID: ${_pending!['tid']}\nDate: ${_pending!['date']}\n\nPayment confirm ho to upar se device activate kar do ya code de do.',
                    style: AppText.body,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.s),
        // Payment settings
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payment settings', style: AppText.title),
                const SizedBox(height: AppSpace.s),
                const Text(
                    'Yehi numbers customers ko paywall par nazar aayenge.',
                    style: AppText.body),
                const SizedBox(height: AppSpace.m),
                TextField(
                  controller: _feeCtrl,
                  keyboardType: TextInputType.number,
                  style: AppText.body,
                  decoration: const InputDecoration(
                    labelText: 'Monthly fee (Rs)',
                    prefixIcon: Icon(Icons.payments_rounded),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                TextField(
                  controller: _jazz,
                  keyboardType: TextInputType.phone,
                  style: AppText.body,
                  decoration: const InputDecoration(
                    labelText: 'JazzCash number',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                TextField(
                  controller: _easy,
                  keyboardType: TextInputType.phone,
                  style: AppText.body,
                  decoration: const InputDecoration(
                    labelText: 'Easypaisa number',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                TextField(
                  controller: _bank,
                  style: AppText.body,
                  decoration: const InputDecoration(
                    labelText: 'Bank account',
                    prefixIcon: Icon(Icons.account_balance_rounded),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save karo'),
                    onPressed: _saveSettings,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.l),
      ],
    );
  }
}
