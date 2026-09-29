/// Received screen: every received payment entry (full or partial).
/// Undo removes the entry and adds the amount back to the customer's
/// currentDue + balance (they reappear in Outstanding / Voucher).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import 'customer_detail_screen.dart';

class ReceivedScreen extends StatefulWidget {
  const ReceivedScreen({super.key});

  @override
  State<ReceivedScreen> createState() => _ReceivedScreenState();
}

class _ReceivedScreenState extends State<ReceivedScreen> {
  String _rs(double v) =>
      'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final list = store.receivedPayments;
    final total = store.totalReceived;

    return Scaffold(
      appBar: AppBar(title: const Text('Received')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _head('Total Received', _rs(total)),
                _head('Count', '${list.length}'),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                        'Abhi kuch receive nahi hua.\nOutstanding me Collect dabao.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _row(context, store, list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _head(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _row(
      BuildContext context, CustomerStore store, ReceivedPayment p) {
    final c = store.findByAccountNo(p.accountNo);
    return ListTile(
      leading: const Icon(Icons.check_circle, color: Colors.green),
      title: Text(
          p.customerName.isEmpty ? '(no name)' : p.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          'A/C ${p.accountNo}\n${_rs(p.amount)}  •  ${p.method}  •  ${p.date}'),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.undo, color: Colors.orange),
        tooltip: 'Undo — raqam wapas due me',
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Undo payment?'),
              content: Text(
                  '${_rs(p.amount)} (${p.method}, ${p.date}) wapas due me add ho jayegi.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Nahi')),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Haan, undo karo')),
              ],
            ),
          );
          if (confirm != true || !context.mounted) return;
          await store.undoPayment(p);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Undo ho gaya — ${_rs(p.amount)} wapas due me')));
            setState(() {});
          }
        },
      ),
      onTap: c == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CustomerDetailScreen(customer: c)),
              ),
    );
  }
}
