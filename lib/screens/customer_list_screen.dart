/// Customer list: the "key fields up front" screen.
/// Each row shows name, cell/WhatsApp, monthly installment, current due,
/// balance + a status dot. Tap for details, tap icons to call / WhatsApp.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/reminders.dart';
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
          ? const Center(
              child: Text(
                  'No customers yet.\nUse Import to scan your prints.',
                  textAlign: TextAlign.center))
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _row(context, list[i]),
            ),
    );
  }

  Widget _row(BuildContext context, Customer c) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(c).withValues(alpha: 0.2),
        child: Text(
          c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
          style: TextStyle(
              color: _statusColor(c), fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(c.name.isEmpty ? '(no name)' : c.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _statusColor(c).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_statusLabel(c),
                style: TextStyle(
                    color: _statusColor(c),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c.cell}  •  A/C ${c.accountNo}'),
          Text(
            'Qist: Rs ${c.monthlyInstallment.toStringAsFixed(0)}   '
            'Due: Rs ${c.currentDue.toStringAsFixed(0)}   '
            'Bal: Rs ${c.balance.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.blue),
            tooltip: 'Call',
            onPressed: () =>
                launchUrl(Uri.parse('tel:${c.cell}')),
          ),
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.green),
            tooltip: 'WhatsApp',
            onPressed: () async {
              final msg = await dueReminderMessageWithAccounts(c);
              openWhatsApp(c, msg);
            },
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(customer: c)),
      ),
    );
  }
}
