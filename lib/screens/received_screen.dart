/// Received screen: every received payment entry (full or partial).
/// Header: "Is Mah Received" (current month ka total — naya mahina 0 se
/// start hota hai) + total + count. List me saari history (newest first,
/// har entry ki date ke sath). Undo removes the entry and adds the amount
/// back to the customer's currentDue + balance.
/// "+" → Outstanding se customer chuno → payment dialog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../services/csv_export.dart';
import '../services/error_log.dart';
import '../theme/app_theme.dart';
import 'collect_dialog.dart';
import 'customer_detail_screen.dart';
import 'customer_picker.dart';

class ReceivedScreen extends StatefulWidget {
  const ReceivedScreen({super.key});

  @override
  State<ReceivedScreen> createState() => _ReceivedScreenState();
}

class _ReceivedScreenState extends State<ReceivedScreen> {
  String _query = '';

  /// Received "+" → Outstanding customer (single) → payment dialog.
  Future<void> _addTap(
      BuildContext context, CustomerStore store) async {
    if (!await requireEdit(context)) return;
    final picked = await pickCustomers(
      context,
      customers: store.outstanding,
      title: 'Payment kis se receive hui?',
      multi: false,
    );
    if (picked.isEmpty || !context.mounted) return;
    final c = store.findByAccountNo(picked.first.accountNo);
    if (c == null || !context.mounted) return;
    await showCollectDialog(context, store, c);
  }

  /// CSV export: filtered payments share karo.
  Future<void> _export(List<ReceivedPayment> list) async {
    if (list.isEmpty) {
      showAppSnack(context, 'Export ke liye koi data nahi');
      return;
    }
    final ok = await shareCsv(
      'received-${DateTime.now().millisecondsSinceEpoch}.csv',
      receivedCsv(list),
      text: 'QistBook Received — ${list.length} payments',
    );
    if (!ok && mounted) {
      await showFriendlyError(context, 'CSV share nahi ho saka.',
          screen: 'Received export');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final q = _query.trim().toLowerCase();
    final list = store.receivedPayments.where((p) {
      if (q.isEmpty) return true;
      if (p.customerName.toLowerCase().contains(q)) return true;
      if (p.accountNo.toLowerCase().contains(q)) return true;
      return false;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Received'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'CSV export / share',
            onPressed: () => _export(list),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Payment add karo',
            onPressed: () => _addTap(context, store),
          ),
        ],
      ),
      body: Column(
        children: [
          const ReadOnlyBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.m, AppSpace.s, AppSpace.m, 0),
            child: TextField(
              style: AppText.body,
              decoration: const InputDecoration(
                hintText: 'Search name, A/C no…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) =>
                  setState(() => _query = v),
            ),
          ),
          statHeader(
            tint: AppColors.tintGreen,
            stats: [
              StatItem('Is Mah Received', rs(store.monthlyReceived),
                  AppColors.okGreen),
              StatItem('Total', rs(store.totalReceived), AppColors.ink),
              StatItem('Count', '${list.length}', AppColors.ink),
            ],
          ),
          Expanded(
            child: list.isEmpty
                ? emptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'Abhi kuch receive nahi hua',
                    subtitle:
                        'Outstanding me Collect dabao ya upar + se payment add karo.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: AppSpace.m),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        _row(context, store, list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(
      BuildContext context, CustomerStore store, ReceivedPayment p) {
    final c = store.findByAccountNo(p.accountNo);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m, vertical: AppSpace.s),
        minVerticalPadding: 12,
        leading: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.tintGreen,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              size: 30, color: AppColors.okGreen),
        ),
        title: Text(
            p.customerName.isEmpty ? '(no name)' : p.customerName,
            style: AppText.bodyBold),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A/C ${p.accountNo}',
                style: AppText.caption.copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(rs(p.amount),
                    style: AppText.money(AppColors.okGreen,
                        size: 20)),
                const SizedBox(width: AppSpace.s),
                Text('${p.method}  •  ${p.date}',
                    style:
                        AppText.caption.copyWith(fontSize: 15)),
              ],
            ),
          ],
        ),
        trailing: SizedBox(
          width: 52,
          height: 52,
          child: IconButton(
            icon: const Icon(Icons.undo_rounded,
                size: 30, color: Colors.orange),
            tooltip: 'Undo — raqam wapas due me',
            onPressed: () async {
              if (!await requireEdit(context)) return;
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Undo payment?'),
                  content: Text(
                      '${rs(p.amount)} (${p.method}, ${p.date}) wapas due me add ho jayegi.'),
                  actions: [
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, false),
                        child: const Text('Nahi')),
                    TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, true),
                        child: const Text('Haan, undo karo')),
                  ],
                ),
              );
              if (confirm != true || !context.mounted) return;
              await store.undoPayment(p);
              if (context.mounted) {
                showAppSnack(context,
                    'Undo ho gaya — ${rs(p.amount)} wapas due me');
              }
            },
          ),
        ),
        onTap: c == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          CustomerDetailScreen(customer: c)),
                ),
      ),
    );
  }
}
