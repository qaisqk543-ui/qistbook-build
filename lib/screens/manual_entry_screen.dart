/// Manual feeding — AAKHRI option.
/// Pehle PDF, phir scan; agar scan na ho ya koi masla aaye to yahan
/// haath se likh kar record update/create karen.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/parsers.dart';
import 'import_screen.dart' show DocType;

class ManualEntryScreen extends StatefulWidget {
  final DocType docType;

  /// Na parhi gayi line ko review screen se theek karne ke liye: andaza
  /// lagaya hua row pehle se bhar do.
  final OutstandingRow? prefill;

  /// true: store me save NA karo — row wapas do taake review list me jaye
  /// aur Confirm & Save par sab ke sath save ho.
  final bool returnRow;

  const ManualEntryScreen(
      {super.key, required this.docType, this.prefill, this.returnRow = false});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};

  TextEditingController _ctl(String key) =>
      _c.putIfAbsent(key, () => TextEditingController());

  String _rs(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null && widget.docType == DocType.outstanding) {
      _ctl('accountNo').text = p.accountNo;
      _ctl('name').text = p.name;
      _ctl('cell').text = p.cell;
      _ctl('item').text = p.item;
      _ctl('price').text = p.price > 0 ? _rs(p.price) : '';
      _ctl('balance').text = p.balance > 0 ? _rs(p.balance) : '';
      _ctl('installment').text = p.installment > 0 ? _rs(p.installment) : '';
      _ctl('osAmount').text = p.osAmount > 0 ? _rs(p.osAmount) : '';
      _ctl('paid').text = p.paid > 0 ? _rs(p.paid) : '';
      _ctl('currentDue').text = p.currentDue > 0 ? _rs(p.currentDue) : '';
      _ctl('lastInstDate').text = p.lastInstDate;
      _ctl('officer').text = p.officer;
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(String key) =>
      double.tryParse(_ctl(key).text.replaceAll(',', '').trim()) ?? 0;

  String _txt(String key) => _ctl(key).text.trim();

  @override
  Widget build(BuildContext context) {
    final isOutstanding = widget.docType == DocType.outstanding;
    return Scaffold(
      appBar: AppBar(
          title: Text(isOutstanding
              ? 'Manual: Outstanding entry'
              : 'Manual: Customer statement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.orange.shade50,
              child: Text(
                widget.returnRow
                    ? 'Neeche line ka data theek karen — Save dabane par ye wapas review list me ajayegi, phir Confirm & Save par sab ke sath save hogi.'
                    : 'Ye aakhri option hai — pehle PDF ya scan try karen. '
                        'A/C No. sahi likhen, usi se record match hoga.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (isOutstanding) ..._outstandingFields() else ..._statementFields(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(widget.returnRow ? 'Theek hai — list me dalo' : 'Save karo'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(14)),
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _outstandingFields() => [
        _field('accountNo', 'A/C No. *', required: true),
        _field('name', 'Customer ka naam'),
        _field('cell', 'Cell / WhatsApp number',
            keyboard: TextInputType.phone),
        _field('item', 'Item (jaise: LED TV)'),
        _field('price', 'Price (Rs)', numeric: true),
        _field('balance', 'Balance (Rs)', numeric: true),
        _field('installment', 'Monthly installment (Rs)', numeric: true),
        _field('osAmount', 'OS amount (Rs)', numeric: true),
        _field('paid', 'Paid (Rs)', numeric: true),
        _field('currentDue', 'Current due (Rs)', numeric: true),
        _field('lastInstDate', 'Last installment date'),
        _field('officer', 'Recovery officer'),
      ];

  List<Widget> _statementFields() => [
        _field('accountNo', 'A/C No. *', required: true),
        _section('Customer'),
        _field('name', 'Naam'),
        _field('fatherName', 'S/O ya W/O'),
        _field('cell', 'Cell number', keyboard: TextInputType.phone),
        _field('cnic', 'CNIC', keyboard: TextInputType.number),
        _field('resAddress', 'Ghar ka pata'),
        _section('Product & Plan'),
        _field('item', 'Item / Model'),
        _field('price', 'Price (Rs)', numeric: true),
        _field('advance', 'Advance (Rs)', numeric: true),
        _field('balance', 'Balance (Rs)', numeric: true),
        _field('monthlyInstallment', 'Monthly installment (Rs)',
            numeric: true),
        _field('durationMonths', 'Duration (months)', numeric: true),
        _section('Guarantor 1'),
        _field('g1name', 'Naam'),
        _field('g1phone', 'Phone', keyboard: TextInputType.phone),
        _field('g1cnic', 'CNIC', keyboard: TextInputType.number),
        _section('Guarantor 2'),
        _field('g2name', 'Naam'),
        _field('g2phone', 'Phone', keyboard: TextInputType.phone),
        _field('g2cnic', 'CNIC', keyboard: TextInputType.number),
      ];

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _field(String key, String label,
      {bool required = false,
      bool numeric = false,
      TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: _ctl(key),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboard ??
            (numeric ? TextInputType.number : TextInputType.text),
        validator: required
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'Zaroori hai' : null
            : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.docType == DocType.outstanding) {
      final row = OutstandingRow(
        accountNo: _txt('accountNo'),
        name: _txt('name'),
        cell: _txt('cell'),
        item: _txt('item'),
        price: _num('price'),
        balance: _num('balance'),
        installment: _num('installment'),
        osAmount: _num('osAmount'),
        paid: _num('paid'),
        currentDue: _num('currentDue'),
        lastInstDate: _txt('lastInstDate'),
        officer: _txt('officer'),
      );
      // Review se "theek karo": row wapas do, save Confirm & Save par hoga.
      if (widget.returnRow) {
        if (!mounted) return;
        Navigator.of(context).pop(row);
        return;
      }
      final store = context.read<CustomerStore>();
      final res = await store.applyOutstandingRow(row);
      await store.logImport({
        'type': 'manual-outstanding',
        'accountNo': row.accountNo,
        'result': res,
      });
      store.markUpdatedNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res == 'updated'
              ? 'Record update ho gaya.'
              : 'Naya record ban gaya.')));
    } else {
      final store = context.read<CustomerStore>();
      final c = Customer(accountNo: _txt('accountNo'))
        ..name = _txt('name')
        ..fatherName = _txt('fatherName')
        ..cell = _txt('cell')
        ..cnic = _txt('cnic')
        ..resAddress = _txt('resAddress')
        ..item = _txt('item')
        ..price = _num('price')
        ..advance = _num('advance')
        ..balance = _num('balance')
        ..monthlyInstallment = _num('monthlyInstallment')
        ..durationMonths = _num('durationMonths').toInt();
      final gs = <Guarantor>[];
      if (_txt('g1name').isNotEmpty || _txt('g1phone').isNotEmpty) {
        gs.add(Guarantor(
            name: _txt('g1name'),
            phone: _txt('g1phone'),
            cnic: _txt('g1cnic')));
      }
      if (_txt('g2name').isNotEmpty || _txt('g2phone').isNotEmpty) {
        gs.add(Guarantor(
            name: _txt('g2name'),
            phone: _txt('g2phone'),
            cnic: _txt('g2cnic')));
      }
      c.guarantors = gs;
      await store.saveCustomer(c);
      await store.logImport({
        'type': 'manual-statement',
        'accountNo': c.accountNo,
      });
      store.markUpdatedNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer save ho gaya.')));
    }
    if (mounted) Navigator.of(context).pop();
  }
}
