/// Dashboard: total outstanding, total due, cleared count,
/// and per-officer breakdown (matches the grouped sections on your print).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/customer_store.dart';
import '../services/firebase_service.dart';
import 'payment_accounts_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  String _rs(double v) =>
      'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final officers = store.byOfficer.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () =>
                FirebaseService.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                  child: _stat('Outstanding', _rs(store.totalOutstanding),
                      Colors.orange)),
              const SizedBox(width: 12),
              Expanded(
                  child: _stat(
                      'Due now', _rs(store.totalDue), Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _stat('Active', '${store.active.length}',
                      Colors.blue)),
              const SizedBox(width: 12),
              Expanded(
                  child: _stat('Overdue', '${store.overdue.length}',
                      Colors.red)),
              const SizedBox(width: 12),
              Expanded(
                  child: _stat('Cleared', '${store.cleared.length}',
                      Colors.green)),
            ],
          ),
          const SizedBox(height: 20),
          const Text('By recovery officer',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (officers.isEmpty)
            const Text('No data yet — import your outstanding report.')
          else
            ...officers.map((e) {
              final due =
                  e.value.fold(0.0, (s, c) => s + c.currentDue);
              return Card(
                child: ListTile(
                  title: Text(e.key),
                  subtitle: Text(
                      '${e.value.length} customers • Due ${_rs(due)}'),
                ),
              );
            }),
          const SizedBox(height: 20),
          const Text('Payments',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet,
                  color: Colors.teal),
              title: const Text('Payment Accounts'),
              subtitle: const Text(
                  'JazzCash / Easypaisa / Bank — reminders me khud share honge'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const PaymentAccountsScreen())),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Internet / Data',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Sync sirf WiFi par karo'),
                  subtitle: const Text(
                      'Social/mobile package ka data bachega. WhatsApp reminders phir bhi chalenge.'),
                  value: store.wifiOnlySync,
                  onChanged: (v) => store.setWifiOnlySync(v),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Ye app Udhar Book ki tarah offline poori chalti hai — '
                    'bina internet ke sab kuch dekhen, scan karen, edit karen. '
                    'Jab internet milega to data khud sync ho jayega.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
