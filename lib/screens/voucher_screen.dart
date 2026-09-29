/// Voucher tab: accounts grouped by A/C no. Row me customer name,
/// "N voucher" count, total vouchered amount, due + balance, Call +
/// WhatsApp + Collect. Tap → voucher detail (har entry ki date + amount).
/// "+" → Outstanding se select karke voucher add karo.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../services/reminders.dart';
import '../theme/app_theme.dart';
import 'collect_dialog.dart';
import 'customer_picker.dart';
import 'voucher_detail_screen.dart';

class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  Future<void> _refresh(CustomerStore store) async {
    await store.refreshData();
    final n = await store.maybeRollover();
    if (mounted) {
      showAppSnack(context,
          n > 0 ? 'Data refresh ho gaya ($n due update)' : 'Data refresh ho gaya');
    }
  }

  /// Voucher "+" → Outstanding customers pick karo → har ek ke liye
  /// amount (default due, editable) + date → entries banao.
  Future<void> _addTap(BuildContext context, CustomerStore store) async {
    if (!await requireEdit(context)) return;
    final picked = await pickCustomers(
      context,
      customers: store.outstanding,
      title: 'Voucher me dalne ke liye chuno',
      multi: true,
    );
    if (!context.mounted) return;
    if (picked.isEmpty) return;
    for (final c in picked) {
      if (!context.mounted) break;
      final entry = await _voucherEntryDialog(context, c);
      if (entry != null) {
        await store.addVoucherEntry(entry);
      }
    }
    if (context.mounted) {
      showAppSnack(
          context, '${picked.length} customer Voucher me daal diye');
    }
  }

  /// Har selected customer ke liye amount + date ka chhota dialog.
  Future<VoucherEntry?> _voucherEntryDialog(
      BuildContext context, Customer c) async {
    final amountCtrl =
        TextEditingController(text: c.currentDue.toStringAsFixed(0));
    DateTime vDate = DateTime.now();
    double amount = 0;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: Text(c.name.isEmpty ? '(no name)' : c.name),
          content: Column(
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
                  labelText: 'Voucher amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              Row(
                children: [
                  Expanded(
                      child: Text('Date: ${isoDate(vDate)}',
                          style: AppText.body)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: dctx,
                        initialDate: vDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setD(() => vDate = d);
                    },
                    child: const Text('Badlo'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body.copyWith(
                          color: AppColors.dueRed, fontSize: 16)),
                ),
            ],
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
                amount = v;
                Navigator.pop(dctx, true);
              },
              child: const Text('Add karo'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    if (ok != true) return null;
    return VoucherEntry(
      id: 'v${DateTime.now().millisecondsSinceEpoch}',
      accountNo: c.accountNo,
      customerName: c.name,
      phone: c.cell,
      amount: amount,
      date: isoDate(vDate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final groups = store.voucherGroups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _refresh(store),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Voucher add karo',
            onPressed: () => _addTap(context, store),
          ),
        ],
      ),
      body: Column(
        children: [
          const ReadOnlyBanner(),
          statHeader(
            tint: AppColors.tintAmber,
            stats: [
              StatItem('Total Vouchered', rs(store.totalVouchered),
                  AppColors.amber),
              StatItem('Accounts', '${groups.length}', AppColors.ink),
            ],
          ),
          Expanded(
            child: groups.isEmpty
                ? emptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Voucher khaali hai',
                    subtitle:
                        'Upar + dabao ya Outstanding me long-press karke customers yahan lao.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: AppSpace.m),
                    itemCount: groups.length,
                    itemBuilder: (context, i) =>
                        _groupRow(context, store, groups[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _groupRow(
      BuildContext context, CustomerStore store, VoucherGroup g) {
    final c = store.findByAccountNo(g.accountNo);
    final phone = g.phone.isNotEmpty ? g.phone : (c?.cell ?? '');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VoucherDetailScreen(group: g)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.customerName.isEmpty
                          ? '(no name)'
                          : g.customerName,
                      style: AppText.bodyBold,
                    ),
                    const SizedBox(height: 2),
                    Text('A/C ${g.accountNo}  •  $phone',
                        style:
                            AppText.caption.copyWith(fontSize: 15)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.tintAmber,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${g.count} voucher',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.amber)),
                        ),
                        const SizedBox(width: AppSpace.s),
                        Text(rs(g.total),
                            style: AppText.money(AppColors.amber)),
                      ],
                    ),
                    if (c != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('Due ',
                              style: AppText.label
                                  .copyWith(fontSize: 15)),
                          Text(rs(c.currentDue),
                              style: AppText.money(
                                  AppColors.dueRed,
                                  size: 20)),
                          const SizedBox(width: AppSpace.m),
                          Text('Balance ',
                              style: AppText.label
                                  .copyWith(fontSize: 15)),
                          Text(rs(c.balance),
                              style: AppText.money(AppColors.ink,
                                  size: 20)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c != null)
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton(
                        icon: const Icon(Icons.payments_rounded,
                            size: 30, color: AppColors.primary),
                        tooltip: 'Collect',
                        onPressed: () async {
                          if (await requireEdit(context)) {
                            showCollectDialog(
                                context, store, c);
                          }
                        },
                      ),
                    ),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton(
                      icon: const Icon(Icons.chat_rounded,
                          size: 30, color: AppColors.okGreen),
                      tooltip: 'WhatsApp',
                      onPressed: () async {
                        final cust = c ??
                            Customer(
                                accountNo: g.accountNo,
                                name: g.customerName,
                                cell: phone);
                        final msg =
                            await dueReminderMessageWithAccounts(cust);
                        final ok = await openWhatsApp(cust, msg);
                        if (!ok && context.mounted) {
                          showAppSnack(context,
                              'WhatsApp nahi khul saka');
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton(
                      icon: const Icon(Icons.call_rounded,
                          size: 30, color: Colors.blue),
                      tooltip: 'Call',
                      onPressed: () =>
                          launchUrl(Uri.parse('tel:$phone')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
