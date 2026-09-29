/// Outstanding screen: ONLY the customers whose installments are pending.
/// - Upload a fresh outstanding report → paid-up names disappear until the
///   next month's list brings them back (if they still owe).
/// - Collect opens amount + method + date dialog; partial payments reduce
///   the due — the customer stays listed while currentDue > 0.
/// - Long-press rows to multi-select and move customers into the Voucher
///   category.
/// Reused for the Voucher tab via [voucherMode] (same pattern, voucher
/// customers only, no multi-select).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../services/call_reminders.dart';
import '../services/customer_store.dart';
import '../services/reminders.dart';
import 'customer_detail_screen.dart';
import 'import_screen.dart';

class OutstandingScreen extends StatefulWidget {
  final bool voucherMode;
  const OutstandingScreen({super.key, this.voucherMode = false});

  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen> {
  String _officer = 'All';
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  String _rs(double v) =>
      'Rs ${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  String _fmtTime(DateTime t) {
    final d = t.day.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$d-${months[t.month - 1]} $h:$m $ap';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final base =
        widget.voucherMode ? store.voucherList : store.outstanding;
    final officers = <String>[
      'All',
      ...{for (final c in base) c.officer.isEmpty ? '—' : c.officer},
    ];
    final list = _officer == 'All'
        ? base
        : base
            .where((c) =>
                (c.officer.isEmpty ? '—' : c.officer) == _officer)
            .toList();
    final totalOutstanding =
        list.fold(0.0, (s, c) => s + c.balance);
    final totalPayable =
        list.fold(0.0, (s, c) => s + c.currentDue);
    final title = widget.voucherMode ? 'Voucher' : 'Outstanding';

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selecting ? '${_selected.length} selected' : title),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Voucher me dalo',
                  onPressed: () => _moveToVoucher(context, store),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed: () =>
                      setState(() => _selected.clear()),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: 'Upload outstanding report',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const ImportScreen())),
                ),
              ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: widget.voucherMode
                ? Colors.amber.shade50
                : Colors.red.shade50,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,
                  children: [
                    _head('Total Outstanding',
                        _rs(totalOutstanding)),
                    _head('Is Mah (Payable)',
                        _rs(totalPayable)),
                    _head('Pending', '${list.length}'),
                  ],
                ),
                if (store.lastUpdatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Last updated: ${_fmtTime(store.lastUpdatedAt!)}',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (officers.length > 2)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8),
                children: officers
                    .map((o) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: ChoiceChip(
                            label: Text(o),
                            selected: _officer == o,
                            onSelected: (_) =>
                                setState(() => _officer = o),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                        widget.voucherMode
                            ? 'Voucher khaali hai.\nOutstanding me long-press karke customers yahan lao.'
                            : 'All clear! No pending installments.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16)))
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

  void _toggleSelect(Customer c) {
    setState(() {
      if (_selected.contains(c.accountNo)) {
        _selected.remove(c.accountNo);
      } else {
        _selected.add(c.accountNo);
      }
    });
  }

  Future<void> _moveToVoucher(
      BuildContext context, CustomerStore store) async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voucher me dalo?'),
        content: Text(
            '$count customer Voucher category me chale jayenge (Outstanding se nikal jayenge).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nahi')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, dalo')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final moving = store.outstanding
        .where((c) => _selected.contains(c.accountNo))
        .toList();
    await store.setVoucher(moving, true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count customer Voucher me daal diye')));
      setState(() => _selected.clear());
    }
  }

  Widget _row(
      BuildContext context, CustomerStore store, Customer c) {
    final selected = _selected.contains(c.accountNo);
    return ListTile(
      leading: _selecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelect(c),
            )
          : null,
      selected: selected,
      title: Text(c.name.isEmpty ? '(no name)' : c.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${c.cell}  •  A/C ${c.accountNo}\nQist ${_rs(c.monthlyInstallment)}  •  Due ${_rs(c.currentDue)}  •  Last ${c.lastInstDate}'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.payments, color: Colors.teal),
            tooltip: 'Collect',
            onPressed: () => _collectTap(context, store, c),
          ),
          FutureBuilder<bool>(
            future: CallReminderService.hasReminder(c.accountNo),
            builder: (context, snap) {
              final has = snap.data == true;
              return IconButton(
                icon: Icon(Icons.alarm_add,
                    color: has ? Colors.orange : Colors.grey),
                tooltip: has
                    ? 'Reminder laga hai — badlo/khatam karo'
                    : 'Call reminder lagao',
                onPressed: () => _reminderTap(context, c),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.green),
            tooltip: 'WhatsApp reminder',
            onPressed: () async {
              final msg = await dueReminderMessageWithAccounts(c);
              final ok = await openWhatsApp(c, msg);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('WhatsApp nahi khul saka')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.blue),
            tooltip: 'Call',
            onPressed: () =>
                launchUrl(Uri.parse('tel:${c.cell}')),
          ),
        ],
      ),
      onLongPress: widget.voucherMode
          ? null
          : () => setState(() => _selected.add(c.accountNo)),
      onTap: _selecting
          ? () => _toggleSelect(c)
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        CustomerDetailScreen(customer: c)),
              ),
    );
  }

  String _fmtReminderTime(DateTime t) {
    final d = t.day.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$d-${months[t.month - 1]} $h:$m $ap';
  }

  /// Alarm icon tap: set / change / cancel a call reminder for [c].
  /// Date picker first, then time picker; past datetimes are rejected.
  Future<void> _reminderTap(BuildContext context, Customer c) async {
    final existing =
        await CallReminderService.getReminderTime(c.accountNo);
    if (existing != null && context.mounted) {
      final action = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(c.name.isEmpty ? '(no name)' : c.name),
          content: Text(
              'Reminder laga hai: ${_fmtReminderTime(existing)}.\nBadalna ya khatam karna hai?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Khatam karo')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'change'),
                child: const Text('Time badlo')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Rehne do')),
          ],
        ),
      );
      if (action == 'cancel') {
        await CallReminderService.cancelReminder(c.accountNo);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Reminder khatam kar diya')));
          setState(() {});
        }
        return;
      }
      if (action != 'change') return;
    }
    if (!context.mounted) return;
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Reminder ki date chuno',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Reminder ka time chuno',
    );
    if (time == null || !context.mounted) return;
    final when = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Ye waqt guzar chuka hai — aage ki date/time chuno')),
        );
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name.isEmpty ? '(no name)' : c.name),
        content: Text(
            '${_fmtReminderTime(when)} par call reminder lagana hai?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Nahi')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Haan, lagao')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final scheduled =
        await CallReminderService.scheduleReminderAt(c, when);
    if (context.mounted) {
      if (scheduled == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Ye waqt guzar chuka hai — aage ki date/time chuno')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Reminder lag gaya: ${_fmtReminderTime(scheduled)}')));
        setState(() {});
      }
    }
  }

  /// Collect button tap: amount + method + date dialog, then record the
  /// payment. Partial payments just reduce the due; the customer leaves
  /// the list only when the due reaches exactly 0.
  Future<void> _collectTap(
      BuildContext context, CustomerStore store, Customer c) async {
    final amountCtrl = TextEditingController(
        text: c.currentDue > 0
            ? c.currentDue.toStringAsFixed(0)
            : c.monthlyInstallment.toStringAsFixed(0));
    String method = 'Cash';
    DateTime payDate = DateTime.now();
    String? err;
    const methods = ['Cash', 'JazzCash', 'Easypaisa', 'Bank'];
    double amount = 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: Text(c.name.isEmpty ? '(no name)' : c.name),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'A/C ${c.accountNo}  •  Due ${_rs(c.currentDue)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Received amount (Rs)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    border: OutlineInputBorder(),
                  ),
                  items: methods
                      .map((m) => DropdownMenuItem(
                          value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setD(() => method = v ?? 'Cash'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child:
                            Text('Date: ${_fmtDate(payDate)}')),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: dctx,
                          initialDate: payDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                              const Duration(days: 365)),
                        );
                        if (d != null) {
                          setD(() => payDate = d);
                        }
                      },
                      child: const Text('Badlo'),
                    ),
                  ],
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final v = double.tryParse(amountCtrl.text
                        .replaceAll(',', '')
                        .trim()) ??
                    0;
                if (v <= 0) {
                  setD(() => err = 'Raqam 0 se zyada likho');
                  return;
                }
                if (v > c.currentDue + 0.001) {
                  setD(() => err =
                      'Raqam due (${_rs(c.currentDue)}) se zyada nahi ho sakti');
                  return;
                }
                amount = v;
                Navigator.pop(dctx, true);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !context.mounted) return;
    final ok = await store.collectPayment(c,
        amount: amount, method: method, date: _fmtDate(payDate));
    if (context.mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${_rs(amount)} received ($method) — Baqi due: ${_rs(c.currentDue)}')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Raqam ghalat hai — dobara koshish karo')));
      }
      setState(() {});
    }
  }
}
