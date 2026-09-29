/// Customer list: the "key fields up front" screen.
/// Each row shows name, cell/WhatsApp, monthly installment, current due,
/// balance + a status dot. Tap for details, tap icons to call / WhatsApp.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../services/reminders.dart';
import '../theme/app_theme.dart';
import 'add_customer_screen.dart';
import 'customer_detail_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  String _query = '';

  Color _statusColor(Customer c) {
    if (c.status == AccountStatus.cleared) return Colors.green;
    if (c.currentDue > 0) return Colors.red;
    return Colors.amber;
  }

  String _statusLabel(Customer c) {
    if (c.status == AccountStatus.cleared) return 'Clear';
    if (c.currentDue > 0) return 'Due';
    return 'OK';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final list = store.search(_query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Naya customer add karo',
            onPressed: () async {
              if (!await requireEdit(context)) return;
              if (context.mounted) {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const AddCustomerScreen()));
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name, A/C no, phone…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: list.isEmpty
          ? emptyState(
              icon: Icons.people_rounded,
              title: 'Koi customer nahi',
              subtitle:
                  'Upar + se haath se add karo, ya Home → Import se scan karo.',
            )
          : ListView.builder(
              padding:
                  const EdgeInsets.only(bottom: AppSpace.m),
              itemCount: list.length,
              itemBuilder: (context, i) => _row(context, list[i]),
            ),
    );
  }

  Widget _row(BuildContext context, Customer c) {
    final sc = _statusColor(c);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.m, vertical: AppSpace.s),
        minVerticalPadding: 12,
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: sc.withValues(alpha: 0.15),
          child: Text(
            c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
            style: TextStyle(
                color: sc,
                fontWeight: FontWeight.w800,
                fontSize: 24),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(c.name.isEmpty ? '(no name)' : c.name,
                  style: AppText.bodyBold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sc.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_statusLabel(c),
                  style: TextStyle(
                      color: sc,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.cell}  •  A/C ${c.accountNo}',
                style: AppText.caption.copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Wrap(
              spacing: AppSpace.s,
              children: [
                Text('Qist ${rs(c.monthlyInstallment)}',
                    style: AppText.body.copyWith(fontSize: 16)),
                Text('Due ${rs(c.currentDue)}',
                    style: AppText.money(AppColors.dueRed, size: 18)),
                Text('Bal ${rs(c.balance)}',
                    style: AppText.body.copyWith(fontSize: 16)),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton(
                icon: const Icon(Icons.call_rounded,
                    color: Colors.blue, size: 30),
                tooltip: 'Call',
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${c.cell}')),
              ),
            ),
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton(
                icon: const Icon(Icons.chat_rounded,
                    color: AppColors.okGreen, size: 30),
                tooltip: 'WhatsApp',
                onPressed: () async {
                  final msg =
                      await dueReminderMessageWithAccounts(c);
                  openWhatsApp(c, msg);
                },
              ),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(customer: c)),
        ),
    ));
  }
}
