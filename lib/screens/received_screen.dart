/// Received screen: customers whose installment was marked as collected
/// locally (moved out of Outstanding). Undo sends them back.

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
    final list = store.customers
        .where((c) => c.collectedLocally)
        .toList();
    final total =
        list.fold(0.0, (s, c) => s + c.lastCollectedAmount);

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
      BuildContext context, CustomerStore store, Customer c) {
    return ListTile(
      leading: const Icon(Icons.check_circle, color: Colors.green),
      title: Text(c.name.isEmpty ? '(no name)' : c.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${c.cell}  •  A/C ${c.accountNo}\n${_rs(c.lastCollectedAmount)}  •  ${c.lastCollectedMethod}  •  ${c.lastCollectedDate}'),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.undo, color: Colors.orange),
        tooltip: 'Wapas Outstanding me',
        onPressed: () async {
          await store.undoCollected(c);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Wapas Outstanding me bhej diya')));
            setState(() {});
          }
        },
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(customer: c)),
      ),
    );
  }
}
