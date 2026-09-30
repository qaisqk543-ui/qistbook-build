/// Manual customer add (Customers tab "+").
/// COMPLETE data entry: sare maloomati + raqam wale fields aur guarantors
/// (naam, cell, address, CNIC) — Qais ki demand par.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../theme/app_theme.dart';

/// Guarantor ka form-state (4 fields).
class _GForm {
  final name = TextEditingController();
  final cell = TextEditingController();
  final address = TextEditingController();
  final cnic = TextEditingController();
  void dispose() {
    name.dispose();
    cell.dispose();
    address.dispose();
    cnic.dispose();
  }

  bool get isEmpty =>
      name.text.trim().isEmpty &&
      cell.text.trim().isEmpty &&
      address.text.trim().isEmpty &&
      cnic.text.trim().isEmpty;
}

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  // Bunyadi
  final _name = TextEditingController();
  final _acc = TextEditingController();
  final _father = TextEditingController();
  final _cell = TextEditingController();
  final _tel = TextEditingController();
  final _cnic = TextEditingController();
  // Pata
  final _resAddr = TextEditingController();
  final _offAddr = TextEditingController();
  final _occupation = TextEditingController();
  final _income = TextEditingController();
  bool _houseOwner = false;
  bool _married = false;
  // Product
  final _company = TextEditingController();
  final _item = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _price = TextEditingController();
  final _advance = TextEditingController();
  final _installment = TextEditingController();
  final _duration = TextEditingController();
  final _balance = TextEditingController();
  // Baqaya
  final _os = TextEditingController();
  final _paid = TextEditingController();
  final _due = TextEditingController();
  final _months = TextEditingController();
  final _accDate = TextEditingController();
  final _lastDate = TextEditingController();
  // Officers
  final _officer = TextEditingController();
  final _marketing = TextEditingController();
  final _verified = TextEditingController();
  final _delivered = TextEditingController();
  // Notes
  final _notes = TextEditingController();

  final _guarantors = <_GForm>[_GForm()];

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name, _acc, _father, _cell, _tel, _cnic,
      _resAddr, _offAddr, _occupation, _income,
      _company, _item, _model, _serial, _price, _advance,
      _installment, _duration, _balance,
      _os, _paid, _due, _months, _accDate, _lastDate,
      _officer, _marketing, _verified, _delivered, _notes,
    ]) {
      c.dispose();
    }
    for (final g in _guarantors) {
      g.dispose();
    }
    super.dispose();
  }

  double _dbl(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;
  int _int(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final gs = <Guarantor>[];
    for (final g in _guarantors) {
      if (g.isEmpty) continue;
      gs.add(Guarantor(
        name: g.name.text.trim(),
        phone: g.cell.text.trim(),
        address: g.address.text.trim(),
        cnic: g.cnic.text.trim(),
      ));
    }
    final err = await context.read<CustomerStore>().addCustomerManually(
          name: _name.text,
          accountNo: _acc.text,
          fatherName: _father.text,
          cell: _cell.text,
          tel: _tel.text,
          cnic: _cnic.text,
          resAddress: _resAddr.text,
          offAddress: _offAddr.text,
          occupation: _occupation.text,
          monthlyIncome: _dbl(_income),
          houseOwner: _houseOwner,
          married: _married,
          company: _company.text,
          item: _item.text,
          modelNo: _model.text,
          serialNo: _serial.text,
          price: _dbl(_price),
          advance: _dbl(_advance),
          monthlyInstallment: _dbl(_installment),
          durationMonths: _int(_duration),
          balance: _dbl(_balance),
          osAmount: _dbl(_os),
          paid: _dbl(_paid),
          currentDue: _dbl(_due),
          accountDate: _accDate.text,
          lastInstDate: _lastDate.text,
          monthsOverdue: _int(_months),
          officer: _officer.text,
          marketingOfficer: _marketing.text,
          verifiedBy: _verified.text,
          deliveredBy: _delivered.text,
          guarantors: gs,
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

  Widget _sec(String title) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.l, bottom: AppSpace.s),
        child: Text(title,
            style: AppText.title.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.bold)),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.m),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: maxLines,
          textCapitalization: keyboard == TextInputType.text
              ? TextCapitalization.words
              : TextCapitalization.none,
          style: AppText.body,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
          ),
        ),
      );

  Widget _guarantorCard(int i) {
    final g = _guarantors[i];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Guarantor ${i + 1}',
                    style: AppText.body
                        .copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_guarantors.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.dueRed),
                    tooltip: 'Guarantor hatao',
                    onPressed: () => setState(() {
                      _guarantors[i].dispose();
                      _guarantors.removeAt(i);
                    }),
                  ),
              ],
            ),
            _field(g.name, 'Naam', icon: Icons.person_rounded),
            _field(g.cell, 'Cell number',
                icon: Icons.smartphone_rounded,
                keyboard: TextInputType.phone),
            _field(g.address, 'Address',
                icon: Icons.home_rounded, maxLines: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s),
              child: TextField(
                controller: g.cnic,
                keyboardType: TextInputType.number,
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'CNIC',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Naya customer')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.l),
        children: [
          _sec('Bunyadi maloomat'),
          _field(_name, 'Naam *', icon: Icons.person_rounded),
          _field(_acc, 'A/C No. *', icon: Icons.numbers_rounded),
          _field(_father, 'Walid ka naam (S/O)',
              icon: Icons.family_restroom_rounded),
          _field(_cell, 'Cell / WhatsApp number',
              icon: Icons.smartphone_rounded,
              keyboard: TextInputType.phone),
          _field(_tel, 'Tel (ghar/dukaan)',
              icon: Icons.phone_rounded,
              keyboard: TextInputType.phone),
          _field(_cnic, 'CNIC',
              icon: Icons.badge_rounded,
              keyboard: TextInputType.number),
          _sec('Pata'),
          _field(_resAddr, 'Ghar ka address',
              icon: Icons.home_rounded, maxLines: 2),
          _field(_offAddr, 'Dukaan/office address',
              icon: Icons.work_rounded, maxLines: 2),
          _field(_occupation, 'Kaam (occupation)',
              icon: Icons.engineering_rounded),
          _field(_income, 'Monthly income (Rs)',
              icon: Icons.payments_rounded,
              keyboard: TextInputType.number),
          CheckboxListTile(
            value: _houseOwner,
            onChanged: (v) =>
                setState(() => _houseOwner = v ?? false),
            title: const Text('Apna ghar hai'),
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _married,
            onChanged: (v) => setState(() => _married = v ?? false),
            title: const Text('Shadi shuda'),
            contentPadding: EdgeInsets.zero,
          ),
          _sec('Product'),
          _field(_company, 'Company', icon: Icons.business_rounded),
          _field(_item, 'Item (MOBILE / LED ...)',
              icon: Icons.devices_rounded),
          _field(_model, 'Model No.', icon: Icons.tag_rounded),
          _field(_serial, 'Serial No.',
              icon: Icons.confirmation_number_rounded),
          _field(_price, 'Price (Rs)',
              icon: Icons.sell_rounded,
              keyboard: TextInputType.number),
          _field(_advance, 'Advance (Rs)',
              icon: Icons.savings_rounded,
              keyboard: TextInputType.number),
          _field(_installment, 'Monthly installment (Rs)',
              icon: Icons.calendar_month_rounded,
              keyboard: TextInputType.number),
          _field(_duration, 'Duration (mahine)',
              icon: Icons.timelapse_rounded,
              keyboard: TextInputType.number),
          _field(_balance, 'Balance (Rs)',
              icon: Icons.account_balance_wallet_rounded,
              keyboard: TextInputType.number),
          _sec('Baqaya'),
          _field(_os, 'OS Amount (Rs)',
              icon: Icons.pending_rounded,
              keyboard: TextInputType.number),
          _field(_paid, 'Paid (Rs)',
              icon: Icons.paid_rounded,
              keyboard: TextInputType.number),
          _field(_due, 'Current Due (Rs)',
              icon: Icons.warning_rounded,
              keyboard: TextInputType.number),
          _field(_months, 'Mahine baqaya',
              icon: Icons.date_range_rounded,
              keyboard: TextInputType.number),
          _field(_accDate, 'Account date (19-Jul-26)',
              icon: Icons.event_rounded),
          _field(_lastDate, 'Last inst. date (31-Aug-26)',
              icon: Icons.event_available_rounded),
          _sec('Officers'),
          _field(_officer, 'Recovery officer',
              icon: Icons.support_agent_rounded),
          _field(_marketing, 'Marketing officer',
              icon: Icons.campaign_rounded),
          _field(_verified, 'Verified by',
              icon: Icons.verified_rounded),
          _field(_delivered, 'Delivered by',
              icon: Icons.local_shipping_rounded),
          _sec('Guarantors'),
          for (var i = 0; i < _guarantors.length; i++)
            _guarantorCard(i),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Aur guarantor add karo'),
            onPressed: () =>
                setState(() => _guarantors.add(_GForm())),
          ),
          _sec('Notes'),
          _field(_notes, 'Notes',
              icon: Icons.note_rounded, maxLines: 3),
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
          const SizedBox(height: AppSpace.l),
        ],
      ),
    );
  }
}
