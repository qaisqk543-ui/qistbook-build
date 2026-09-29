/// Outstanding screen: ONLY the customers whose installments are pending.
/// - Upload a fresh outstanding report → paid-up names disappear until the
///   next month's list brings them back (if they still owe).
/// - Read-only: no manual edits; data changes only through imports.

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
  const OutstandingScreen({super.key});

  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen> {
  String _officer = 'All';

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
    return '$d-${months[t.month - 1]} ${h}:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final pending = store.customers
        .where((c) =>
            c.status != AccountStatus.cleared &&
            (c.currentDue > 0 || c.balance > 0))
        .toList();
    final officers = <String>[
      'All',
      ...store.byOfficer.keys,
    ];
    final list = _officer == 'All'
        ? pending
        : pending
            .where((c) =>
                (c.officer.isEmpty ? '—' : c.officer) == _officer)
            .toList();
    final totalOutstanding =
        list.fold(0.0, (s, c) => s + c.balance);
    final totalPayable =
        list.fold(0.0, (s, c) => s + c.currentDue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outstanding'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload outstanding report',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ImportScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.red.shade50,
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
                ? const Center(
                    child: Text(
                        'All clear! No pending installments.',
                        style: TextStyle(fontSize: 16)))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _row(context, list[i]),
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

  Widget _row(BuildContext context, Customer c) {
    return ListTile(
      title: Text(c.name.isEmpty ? '(no name)' : c.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${c.cell}  •  A/C ${c.accountNo}\nQist ${_rs(c.monthlyInstallment)}  •  Due ${_rs(c.currentDue)}  •  Last ${c.lastInstDate}'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              final ok =
                  await openWhatsApp(c, dueReminderMessage(c));
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(customer: c)),
      ),
    );
  }

  String _fmtTimeOfDay(TimeOfDay t) {
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
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
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name.isEmpty ? '(no name)' : c.name),
        content: Text(
            '${_fmtTimeOfDay(picked)} par call reminder lagana hai?'),
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
    final when =
        await CallReminderService.scheduleReminder(c, picked);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Reminder lag gaya: ${_fmtReminderTime(when)}')));
      setState(() {});
    }
  }
}
