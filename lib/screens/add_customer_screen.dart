/// Manual customer add (Customers tab "+").
/// Sirf contact/info fields — paisa wale fields import-only hain (Qais ka rule).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/customer_store.dart';
import '../theme/app_theme.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _name = TextEditingController();
  final _cell = TextEditingController();
  final _tel = TextEditingController();
  final _acc = TextEditingController();
  final _notes = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _cell.dispose();
    _tel.dispose();
    _acc.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<CustomerStore>().addCustomerManually(
          name: _name.text,
          cell: _cell.text,
          tel: _tel.text,
          accountNo: _acc.text,
          notes: _notes.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
    } else {
      showAppSnack(context, 'Customer add ho gaya');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Naya customer')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.l),
        children: [
          Text(
            'Sirf maloomat likhen — qist/raqam import se aayegi.',
            style: AppText.body.copyWith(color: AppColors.grey),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: AppText.body,
            decoration: const InputDecoration(
              labelText: 'Naam *',
              prefixIcon: Icon(Icons.person_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _acc,
            style: AppText.body,
            decoration: const InputDecoration(
              labelText: 'A/C No. *',
              prefixIcon: Icon(Icons.numbers_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _cell,
            keyboardType: TextInputType.phone,
            style: AppText.body,
            decoration: const InputDecoration(
              labelText: 'Cell / WhatsApp number',
              prefixIcon: Icon(Icons.smartphone_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _tel,
            keyboardType: TextInputType.phone,
            style: AppText.body,
            decoration: const InputDecoration(
              labelText: 'Tel (ghar/dukaan)',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _notes,
            maxLines: 3,
            style: AppText.body,
            decoration: const InputDecoration(
              labelText: 'Notes',
              prefixIcon: Icon(Icons.note_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.m),
            Container(
              padding: const EdgeInsets.all(AppSpace.m),
              decoration: BoxDecoration(
                color: AppColors.tintRose,
                borderRadius:
                    BorderRadius.circular(AppRadius.button),
              ),
              child: Text(_error!,
                  style: AppText.body.copyWith(
                      color: AppColors.dueRed, fontSize: 16)),
            ),
          ],
          const SizedBox(height: AppSpace.l),
          ElevatedButton.icon(
            icon: const Icon(Icons.save_rounded),
            label: _busy
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3))
                : const Text('Save karo'),
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
