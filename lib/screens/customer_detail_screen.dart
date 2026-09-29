/// Full customer file — mirrors the printed statement section by section.
/// Paisa/hisaab (import-only): sirf import se update hota hai.
/// Contacts + Notes: user khud add/edit kar sakta hai (har change save hota
/// hai aur cloud me sync hota hai jab Firebase laga ho).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/reminders.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Customer c;

  @override
  void initState() {
    super.initState();
    c = widget.customer;
  }

  String _rs(double v) =>
      'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  /// Har edit ke baad: local save + cloud sync (agar Firebase laga ho).
  Future<void> _persist() async {
    await context.read<CustomerStore>().saveCustomer(c);
    if (mounted) setState(() {});
  }

  /// Voucher customer ko wapas Outstanding me bhejo (ghalti se dala ho to).
  Future<void> _moveBackFromVoucher(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wapas Outstanding me?'),
        content: Text(
            '${c.name} Voucher se nikal kar wapas Outstanding me aa jayega.'),
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
    await context.read<CustomerStore>().setVoucher([c], false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Wapas Outstanding me bhej diya')));
      setState(() {});
    }
  }

  // ------------------------------------------------------------ edit dialogs

  Future<void> _editPhones() async {
    final cellCtl = TextEditingController(text: c.cell);
    final telCtl = TextEditingController(text: c.telRes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact numbers'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cellCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Cell / WhatsApp',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: telCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Tel (Res.)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      c.cell = cellCtl.text.trim();
      c.telRes = telCtl.text.trim();
      await _persist();
    }
  }

  Future<void> _contactDialog({int? index}) async {
    final existing = index != null ? c.extraContacts[index] : null;
    final labelCtl =
        TextEditingController(text: existing?.label ?? '');
    final phoneCtl =
        TextEditingController(text: existing?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            existing == null ? 'Naya contact add karo' : 'Contact edit karo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtl,
              decoration: const InputDecoration(
                labelText: 'Naam / rishta (jaise: Bhai, Dukaan)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && phoneCtl.text.trim().isNotEmpty) {
      final ec = ExtraContact(
          label: labelCtl.text.trim(), phone: phoneCtl.text.trim());
      if (index != null) {
        c.extraContacts[index] = ec;
      } else {
        c.extraContacts.add(ec);
      }
      await _persist();
    }
  }

  Future<void> _deleteContact(int index) async {
    c.extraContacts.removeAt(index);
    await _persist();
  }

  Future<void> _editNotes() async {
    final notesCtl = TextEditingController(text: c.notes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes / Remarks'),
        content: TextField(
          controller: notesCtl,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Additional information yahan likhen…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      c.notes = notesCtl.text.trim();
      await _persist();
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name.isEmpty ? 'Customer' : c.name),
        actions: [
          if (c.inVoucher)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Voucher se wapas Outstanding me',
              onPressed: () => _moveBackFromVoucher(context),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // -------------------------------------------------- header
          Card(
            color: Colors.teal.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name.isEmpty ? '(no name)' : c.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(
                            'A/C ${c.accountNo}  •  ${_rs(c.monthlyInstallment)}/month\nDue ${_rs(c.currentDue)}  •  Balance ${_rs(c.balance)}'),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.call,
                        color: Colors.blue, size: 30),
                    tooltip: 'Call ${c.cell}',
                    onPressed: () => dialNumber(c.cell),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat,
                        color: Colors.green, size: 30),
                    tooltip: 'WhatsApp ${c.cell}',
                    onPressed: () async {
                      final msg =
                          await dueReminderMessageWithAccounts(c);
                      openWhatsApp(c, msg);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _card('Account Information', [
            _kv('A/C No.', c.accountNo),
            _kv('Customer Code', c.customerCode),
            _kv('Process #', c.processNo),
            _kv('Pre. A/C No.', c.preAccountNo),
            _kv('A/C Date', c.accountDate),
            _kv('Due Date', c.dueDate),
            _kv('Due Amount', _rs(c.dueAmount)),
            _kv('A/C Balance', _rs(c.balance)),
            _kv('Fine Time', c.fineTime),
          ]),
          _card('Customer Information', [
            _kv('Name', c.name),
            _kv('S/O or W/O', c.fatherName),
            _kv('Tel (Res.)', c.telRes),
            _kv('Cell', c.cell),
            _kv('CNIC', c.cnic),
            _kv('House Owner', c.houseOwner ? 'Yes' : ''),
            _kv('Married', c.married ? 'Yes' : ''),
            _kv('Res. Address', c.resAddress),
            _kv('Office Address', c.offAddress),
            _kv('Occupation', c.occupation),
            _kv('Monthly Income',
                c.monthlyIncome > 0 ? _rs(c.monthlyIncome) : ''),
          ],
              action: IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Contact numbers edit karo',
                onPressed: _editPhones,
              )),
          _extraContactsCard(),
          _notesCard(),
          _card('Officers', [
            _kv('Marketing', c.marketingOfficer),
            _kv('Verified', c.verifiedBy),
            _kv('Delivered', c.deliveredBy),
            _kv('Recovery Officer', c.officer),
          ]),
          _card('Product & Plan Detail', [
            _kv('Company', c.company),
            _kv('Item', c.item),
            _kv('Model No.', c.modelNo),
            _kv('Serial No.', c.serialNo),
            _kv('Price', _rs(c.price)),
            _kv('Advance', _rs(c.advance)),
            _kv('Balance', _rs(c.balance)),
            _kv('Monthly Inst.', _rs(c.monthlyInstallment)),
            _kv('Duration',
                c.durationMonths > 0 ? '${c.durationMonths} months' : ''),
            _kv('Current Balance', _rs(c.balance)),
            _kv('Last Inst. Date', c.lastInstDate),
          ]),
          _guarantorsCard(),
          _card(
              'Installment Collection Detail',
              c.collections.isEmpty
                  ? [const Text('—', style: TextStyle(color: Colors.grey))]
                  : c.collections
                      .map((e) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title:
                                Text('${e.date} — ${_rs(e.collected)}'),
                            subtitle: Text(
                                'Receipt ${e.receiptNo} • Balance ${_rs(e.balance)}'),
                            trailing: Text(e.receivedBy),
                          ))
                      .toList()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.sms),
                  label: const Text('SMS reminder'),
                  onPressed: () => _sendSms(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  onPressed: () async {
                    final msg =
                        await dueReminderMessageWithAccounts(c);
                    openWhatsApp(c, msg);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _extraContactsCard() {
    return _card(
      'Additional Contacts',
      [
        if (c.extraContacts.isEmpty)
          const Text('Koi extra contact nahi — neeche button se add karen.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ...c.extraContacts.asMap().entries.map((entry) {
          final i = entry.key;
          final ec = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ec.label.isNotEmpty)
                        Text(ec.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      Text(ec.phone),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.call,
                      color: Colors.blue, size: 22),
                  tooltip: 'Call',
                  onPressed: () => dialNumber(ec.phone),
                ),
                IconButton(
                  icon: const Icon(Icons.chat,
                      color: Colors.green, size: 22),
                  tooltip: 'WhatsApp',
                  onPressed: () => openWhatsAppNumber(
                      ec.phone,
                      'Assalam o Alaikum${ec.label.isNotEmpty ? ' ${ec.label}' : ''}, '
                      'ALIF ELECTRONICS se ittila: '
                      '${c.name} ki qist pending hai. Shukriya.'),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Edit',
                  onPressed: () => _contactDialog(index: i),
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      color: Colors.red, size: 20),
                  tooltip: 'Delete',
                  onPressed: () => _deleteContact(i),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Naya contact add karo'),
          onPressed: () => _contactDialog(),
        ),
      ],
      action: null,
    );
  }

  Widget _notesCard() {
    return _card(
      'Notes / Remarks',
      [
        if (c.notes.isEmpty)
          const Text('Koi note nahi.',
              style: TextStyle(color: Colors.grey, fontSize: 13))
        else
          Text(c.notes),
      ],
      action: IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: 'Note add/edit karo',
        onPressed: _editNotes,
      ),
    );
  }

  Widget _guarantorsCard() {
    return _card(
        'Guarantors Information',
        c.guarantors.isEmpty
            ? [const Text('—', style: TextStyle(color: Colors.grey))]
            : c.guarantors.map((g) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(g.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (g.cnic.isNotEmpty)
                              Text('CNIC: ${g.cnic}'),
                            if (g.phone.isNotEmpty)
                              Text('Phone: ${g.phone}'),
                            if (g.address.isNotEmpty)
                              Text(g.address),
                          ],
                        ),
                      ),
                      if (g.phone.isNotEmpty) ...[
                        IconButton(
                          icon: const Icon(Icons.call,
                              color: Colors.blue),
                          tooltip: 'Call ${g.name}',
                          onPressed: () => dialNumber(g.phone),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat,
                              color: Colors.green),
                          tooltip: 'WhatsApp ${g.name}',
                          onPressed: () => openWhatsAppNumber(
                              g.phone,
                              'Assalam o Alaikum ${g.name}, '
                              'ALIF ELECTRONICS se ittila: '
                              '${c.name} ki qist pending hai. '
                              'Baraye meherbani tawajjo dein. Shukriya.'),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList());
  }

  Future<void> _sendSms(BuildContext context) async {
    final msg = await dueReminderMessageWithAccounts(c);
    final ok = await sendSms(c.cell, msg);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(ok ? 'SMS sent.' : 'SMS failed — check permission.')));
    }
  }

  Widget _card(String title, List<Widget> children,
      {Widget? action}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
                if (action != null) action,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    if (v.isEmpty || v == 'Rs 0') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child:
                  Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}
