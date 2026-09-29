/// Paywall / Renew screen: subscription khatam ho to "Renew karein"
/// yahin se hota hai — wahi payment numbers + TID + activation code flow.
/// Full block NAHI: read-only mode me data nazar aata rehta hai.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/error_log.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

class PaywallScreen extends StatefulWidget {
  final String uid;

  /// Activate hone par chalta hai (banner/state refresh ke liye).
  final Future<void> Function() onActivated;
  const PaywallScreen({
    super.key,
    required this.uid,
    required this.onActivated,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _fee = SubscriptionService.defaultFee;
  Map<String, String> _numbers = {};
  Map<String, String>? _pending;
  bool _busy = false;
  String? _expiredNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fee = await SubscriptionService.fee();
    final nums = await SubscriptionService.paymentNumbers();
    final pending = await SubscriptionService.pendingTid(widget.uid);
    final exp = await SubscriptionService.expiryOf(widget.uid);
    final wasTrial =
        await SubscriptionService.trialWasUsed(widget.uid);
    final status =
        await SubscriptionService.statusOf(widget.uid);
    if (mounted) {
      setState(() {
        _fee = fee;
        _numbers = nums;
        _pending = pending;
        _expiredNote = (exp != null && exp.isBefore(DateTime.now()))
            ? (wasTrial && status == 'trial'
                ? 'Aap ka 30 din ka free trial khatam ho gaya — subscription lein taake kaam jari rahe.'
                : 'Apki subscription ${fmtDay(exp)} ko khatam ho gayi thi.')
            : null;
      });
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showAppSnack(context, '$label copy ho gaya');
  }

  Future<void> _claimTid() async {
    final tidCtrl = TextEditingController();
    var date = DateTime.now();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: const Text('Payment ki detail'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tidCtrl,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'TID / Reference number',
                  prefixIcon: Icon(Icons.confirmation_number_rounded),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              Row(
                children: [
                  Expanded(
                      child:
                          Text('Date: ${fmtDay(date)}', style: AppText.body)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: dctx,
                        initialDate: date,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 60)),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setD(() => date = d);
                    },
                    child: const Text('Badlo'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body.copyWith(color: AppColors.dueRed)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (tidCtrl.text.trim().isEmpty) {
                  setD(() => err = 'TID / reference likhna zaroori hai');
                  return;
                }
                Navigator.pop(dctx, true);
              },
              child: const Text('Bhej do'),
            ),
          ],
        ),
      ),
    );
    final tid = tidCtrl.text.trim();
    tidCtrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await SubscriptionService.claimTid(widget.uid, tid, fmtDay(date));
      await _load();
      if (mounted) {
        showAppSnack(context, 'TID mil gaya — tasdeeq ka intezar karein');
      }
    } catch (e) {
      ErrorLog.log('Paywall TID', e);
      if (mounted) showAppSnack(context, 'Koshish nakaam hui');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _codeDialog() async {
    final ctrl = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: const Text('Activation code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '6-digit code yahan likhen (WhatsApp/call par mila hoga).',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '••••••',
                  counterText: '',
                ),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body.copyWith(color: AppColors.dueRed)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (!SubscriptionService.verifyCode(ctrl.text)) {
                  setD(() => err = 'Ghalat code — dobara check karein');
                  return;
                }
                Navigator.pop(dctx, true);
              },
              child: const Text('Activate karo'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await SubscriptionService.activate(widget.uid, 30);
      if (mounted) {
        showAppSnack(context, 'Mubarak! 30 din ke liye activate ho gaya');
        await widget.onActivated();
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNumbers = _numbers.values.any((v) => v.trim().isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: const Text('QistBook Premium'),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpace.l),
              children: [
                // Premium card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpace.l),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDeep, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.workspace_premium_rounded,
                          size: 64, color: Colors.amber),
                      const SizedBox(height: AppSpace.s),
                      const Text('QistBook Premium',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Rs $_fee / mahina',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: AppSpace.s),
                      const Text(
                        'Subscription khatam ho to app sirf dekhne ke liye rehti hai. Renew karwao taake payment, import aur edits dobara chalen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (_expiredNote != null) ...[
                  const SizedBox(height: AppSpace.m),
                  Card(
                    color: AppColors.tintRose,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.m),
                      child: Text(_expiredNote!, style: AppText.body),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.l),
                const Text('Payment kaise karein', style: AppText.h2),
                const SizedBox(height: AppSpace.s),
                ...[
                  'Neeche diye gaye number par Rs $_fee bhejo',
                  'TID / Reference number note karo',
                  'Neeche "Maine payment kar di" dabao aur TID likho',
                  'Tasdeeq ke baad activation code milega',
                ].asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: AppColors.tintTeal,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                                child: Text('${e.key + 1}',
                                    style: AppText.bodyBold.copyWith(
                                        color: AppColors.primaryDark))),
                          ),
                          const SizedBox(width: AppSpace.s),
                          Expanded(child: Text(e.value, style: AppText.body)),
                        ],
                      ),
                    )),
                const SizedBox(height: AppSpace.m),
                const Text('Payment numbers', style: AppText.title),
                const SizedBox(height: AppSpace.s),
                if (!hasNumbers)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpace.m),
                      child: Text(
                        'Payment numbers jald aa rahe hain.',
                        style: AppText.body,
                      ),
                    ),
                  )
                else
                  ..._numbers.entries
                      .where((e) => e.value.trim().isNotEmpty)
                      .map((e) => Card(
                            child: ListTile(
                              leading: const Icon(
                                  Icons.account_balance_wallet_rounded,
                                  size: 34,
                                  color: AppColors.primary),
                              title: Text(e.key, style: AppText.bodyBold),
                              subtitle: Text(e.value, style: AppText.body),
                              trailing: IconButton(
                                icon: const Icon(Icons.content_copy_rounded,
                                    size: 28, color: AppColors.primary),
                                tooltip: 'Copy',
                                onPressed: () => _copy(e.key, e.value),
                              ),
                            ),
                          )),
                const SizedBox(height: AppSpace.l),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payments_rounded, size: 30),
                    label: const Text('Maine payment kar di'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 70),
                      textStyle: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    onPressed: _claimTid,
                  ),
                ),
                if (_pending != null) ...[
                  const SizedBox(height: AppSpace.m),
                  Card(
                    color: AppColors.tintAmber,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tasdeeq ka intezar hai',
                              style: AppText.bodyBold),
                          const SizedBox(height: 4),
                          Text(
                            'TID: ${_pending!['tid']} (${_pending!['date']})\nJaisay hi payment confirm hogi, activation code mil jayega.',
                            style: AppText.body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.m),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.key_rounded),
                    label: const Text('Mere paas activation code hai'),
                    onPressed: _codeDialog,
                  ),
                ),
                const SizedBox(height: AppSpace.l),
              ],
            ),
    );
  }
}
