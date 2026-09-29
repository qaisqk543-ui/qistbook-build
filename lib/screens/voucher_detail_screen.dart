/// Voucher detail: customer header + har voucher entry ki date + amount
/// ("12 Sep 2026 ko Rs 50,000 ka voucher"). Per-entry delete (confirm),
/// aur "Voucher se wapas" (saari entries hatao → Voucher tab se nikal jata hai).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../theme/app_theme.dart';
import 'customer_detail_screen.dart';

class VoucherDetailScreen extends StatelessWidget {
  final VoucherGroup group;
  const VoucherDetailScreen({super.key, required this.group});

  Future<void> _deleteEntry(
      BuildContext context, CustomerStore store, String id) async {
    if (!await requireEdit(context)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voucher entry delete karo?'),
        content: const Text('Ye entry history se nikal jayegi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, delete karo')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await store.deleteVoucherEntry(id);
    if (context.mounted) {
      showAppSnack(context, 'Voucher entry delete ho gayi');
      Navigator.pop(context); // group refresh ke liye wapas
    }
  }

  Future<void> _moveBack(BuildContext context, CustomerStore store) async {
    if (!await requireEdit(context)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voucher se wapas?'),
        content: Text(
            '${group.customerName} ki saari (${group.count}) voucher entries khatam ho jayengi, aur wo Outstanding me wapas aa jayega.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, wapas bhejo')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await store.clearVouchersFor(group.accountNo);
    if (context.mounted) {
      showAppSnack(context, 'Wapas Outstanding me bhej diya');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    // Fresh group (entries delete hone par update hota rahe).
    final fresh = store.voucherGroups
        .where((g) => g.accountNo == group.accountNo)
        .toList();
    final g = fresh.isEmpty ? null : fresh.first;
    final c = store.findByAccountNo(group.accountNo);

    return Scaffold(
      appBar: AppBar(
        title: Text(group.customerName.isEmpty
            ? 'Voucher'
            : group.customerName),
      ),
      body: g == null
          ? emptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Koi voucher entry nahi',
              subtitle: 'Saari entries delete ho gayi hain.',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpace.m),
              children: [
                Card(
                  color: AppColors.tintAmber,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            g.customerName.isEmpty
                                ? '(no name)'
                                : g.customerName,
                            style: AppText.h2),
                        const SizedBox(height: 4),
                        Text('A/C ${g.accountNo}  •  ${g.phone}',
                            style: AppText.body),
                        const SizedBox(height: AppSpace.s),
                        Row(
                          children: [
                            Text('${g.count} voucher',
                                style: AppText.bodyBold),
                            const SizedBox(width: AppSpace.m),
                            Text(rs(g.total),
                                style: AppText.money(
                                    AppColors.amber)),
                          ],
                        ),
                        if (c != null) ...[
                          const SizedBox(height: AppSpace.s),
                          Row(
                            children: [
                              Text('Due ',
                                  style: AppText.label
                                      .copyWith(fontSize: 16)),
                              Text(rs(c.currentDue),
                                  style: AppText.money(
                                      AppColors.dueRed)),
                              const SizedBox(width: AppSpace.m),
                              Text('Balance ',
                                  style: AppText.label
                                      .copyWith(fontSize: 16)),
                              Text(rs(c.balance),
                                  style: AppText.money(
                                      AppColors.ink)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.s),
                ...g.entries.map((e) => Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.m,
                            vertical: AppSpace.s),
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.tintAmber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.receipt_rounded,
                              size: 30,
                              color: AppColors.amber),
                        ),
                        title: Text(
                          '${fmtDay(DateTime.parse(e.date))} ko ${rs(e.amount)} ka voucher',
                          style: AppText.bodyBold.copyWith(fontSize: 17),
                        ),
                        subtitle: Text(e.date,
                            style: AppText.caption
                                .copyWith(fontSize: 15)),
                        trailing: SizedBox(
                          width: 52,
                          height: 52,
                          child: IconButton(
                            icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 28,
                                color: AppColors.dueRed),
                            tooltip: 'Delete',
                            onPressed: () =>
                                _deleteEntry(context, store, e.id),
                          ),
                        ),
                      ),
                    )),
                const SizedBox(height: AppSpace.m),
                OutlinedButton.icon(
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Voucher se wapas'),
                  onPressed: () => _moveBack(context, store),
                ),
                if (c != null) ...[
                  const SizedBox(height: AppSpace.s),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_rounded),
                    label: const Text('Customer detail kholo'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              CustomerDetailScreen(customer: c)),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.l),
              ],
            ),
    );
  }
}
