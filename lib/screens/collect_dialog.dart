/// Shared Collect dialog: amount + method + date.
/// Partial payments due + balance kam karti hain; customer due=0 par hi
/// list se nikalta hai. Outstanding aur Voucher dono yahin se kholte hain.
library;

import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../theme/app_theme.dart';

const _methods = ['Cash', 'JazzCash', 'Easypaisa', 'Bank'];

/// Shows the dialog and records the payment. Returns true if recorded.
Future<bool> showCollectDialog(
    BuildContext context, CustomerStore store, Customer c) async {
  final amountCtrl = TextEditingController(
      text: c.currentDue > 0
          ? c.currentDue.toStringAsFixed(0)
          : c.monthlyInstallment.toStringAsFixed(0));
  String method = 'Cash';
  DateTime payDate = DateTime.now();
  String? err;
  double amount = 0;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setD) => AlertDialog(
        title: Text(c.name.isEmpty ? '(no name)' : c.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A/C ${c.accountNo}  •  Due ${rs(c.currentDue)}',
                  style: AppText.body),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Received amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              DropdownButtonFormField<String>(
                initialValue: method,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                items: _methods
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setD(() => method = v ?? 'Cash'),
              ),
              const SizedBox(height: AppSpace.m),
              Row(
                children: [
                  Expanded(
                      child: Text('Date: ${isoDate(payDate)}',
                          style: AppText.body)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: dctx,
                        initialDate: payDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (d != null) setD(() => payDate = d);
                    },
                    child: const Text('Badlo'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body
                          .copyWith(color: AppColors.dueRed, fontSize: 16)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(amountCtrl.text
                      .replaceAll(',', '')
                      .trim()) ??
                  0;
              if (v <= 0) {
                setD(() => err = 'Raqam 0 se zyada likhen');
                return;
              }
              if (v > c.currentDue + 0.001) {
                setD(() => err =
                    'Raqam due (${rs(c.currentDue)}) se zyada nahi ho sakti');
                return;
              }
              amount = v;
              Navigator.pop(dctx, true);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
  amountCtrl.dispose();
  if (confirm != true || !context.mounted) return false;
  bool ok = false;
  try {
    ok = await store.collectPayment(c,
        amount: amount, method: method, date: isoDate(payDate));
  } catch (e) {
    ErrorLog.log('Collect', e);
    if (context.mounted) {
      await showFriendlyError(
          context, 'Payment save nahi ho saki: $e',
          screen: 'Collect',
          onRetry: () => showCollectDialog(context, store, c));
    }
    return false;
  }
  if (context.mounted) {
    showAppSnack(
        context,
        ok
            ? '${rs(amount)} received ($method) — Baqi due: ${rs(c.currentDue)}'
            : 'Raqam ghalat hai — dobara koshish karen');
  }
  return ok;
}
