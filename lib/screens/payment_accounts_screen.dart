/// Payment Accounts: JazzCash / Easypaisa / Bank accounts.
/// Ye numbers auto-sent SMS aur WhatsApp reminders me share hote hain.
library;

import 'package:flutter/material.dart';

import '../models/payment_account.dart';
import '../services/payment_accounts.dart';

class PaymentAccountsScreen extends StatefulWidget {
  const PaymentAccountsScreen({super.key});

  @override
  State<PaymentAccountsScreen> createState() =>
      _PaymentAccountsScreenState();
}

class _PaymentAccountsScreenState
    extends State<PaymentAccountsScreen> {
  List<PaymentAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await loadAccounts();
    if (mounted) {
      setState(() {
        _accounts = list;
        _loading = false;
      });
    }
  }

  Future<void> _addDialog() async {
    final titleCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    String type = 'JazzCash';
    const types = ['JazzCash', 'Easypaisa', 'Bank'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: const Text('Account add karo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: types
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setD(() => type = v ?? 'JazzCash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title (account holder ka naam)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: numberCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Account / mobile number',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (numberCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Number zaroori hai')));
      }
      return;
    }
    await addAccount(PaymentAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      title: titleCtrl.text.trim(),
      number: numberCtrl.text.trim(),
    ));
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account add ho gaya')));
    }
  }

  Future<void> _delete(String id) async {
    await deleteAccount(id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Accounts')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDialog,
        tooltip: 'Account add karo',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Koi account nahi.\n+ button se JazzCash / Easypaisa / Bank account add karo.\nYe numbers SMS aur WhatsApp reminders me khud share honge.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _accounts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = _accounts[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          a.type == 'Bank'
                              ? Icons.account_balance
                              : Icons.smartphone,
                          color: Colors.teal,
                        ),
                        title: Text(
                            '${a.type}${a.title.isNotEmpty ? ' (${a.title})' : ''}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(a.number),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red),
                          tooltip: 'Delete',
                          onPressed: () => _delete(a.id),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
