/// Outstanding screen: ONLY the customers whose installments are pending.
/// - Upload a fresh outstanding report → paid-up names disappear until the
///   next month's list brings them back (if they still owe).
/// - Collect opens the shared amount + method + date dialog; partial payments
///   reduce the due — the customer stays listed while currentDue > 0.
/// - Long-press rows to multi-select and add voucher ENTRIES (amount + date).
/// - Refresh button: manual data refresh + monthly rollover check.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../services/call_reminders.dart';
import '../services/access_control.dart';
import '../services/customer_store.dart';
import '../services/csv_export.dart';
import '../services/error_log.dart';
import '../services/reminders.dart';
import '../theme/app_theme.dart';
import 'collect_dialog.dart';
import 'customer_detail_screen.dart';
import 'import_screen.dart';

class OutstandingScreen extends StatefulWidget {
  const OutstandingScreen({super.key});

  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen> {
  String _officer = 'All';
  String _query = '';
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _refresh(CustomerStore store) async {
    await store.refreshData();
    final n = await store.maybeRollover();
    if (mounted) {
      showAppSnack(context,
          n > 0 ? 'Data refresh ho gaya ($n due update)' : 'Data refresh ho gaya');
    }
  }

  /// CSV export: filtered list share karo (WhatsApp / email…).
  Future<void> _export(List<Customer> list) async {
    if (list.isEmpty) {
      showAppSnack(context, 'Export ke liye koi data nahi');
      return;
    }
    final ok = await shareCsv(
      'outstanding-${DateTime.now().millisecondsSinceEpoch}.csv',
      outstandingCsv(list),
      text: 'QistBook Outstanding — ${list.length} customers',
    );
    if (!ok && mounted) {
      await showFriendlyError(context, 'CSV share nahi ho saka.',
          screen: 'Outstanding export');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CustomerStore>();
    final base = store.outstanding;
    final officers = <String>[
      'All',
      ...{for (final c in base) c.officer.isEmpty ? '—' : c.officer},
    ];
    final q = _query.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final list = (_officer == 'All'
            ? base
            : base
                .where((c) =>
                    (c.officer.isEmpty ? '—' : c.officer) == _officer)
                .toList())
        .where((c) {
      if (q.isEmpty) return true;
      if (c.name.toLowerCase().contains(q)) return true;
      if (c.accountNo.toLowerCase().contains(q)) return true;
      if (qDigits.isNotEmpty &&
          c.cell.replaceAll(RegExp(r'\D'), '').contains(qDigits)) {
        return true;
      }
      return false;
    }).toList();
    final totalOutstanding =
        list.fold(0.0, (s, c) => s + c.balance);
    final totalPayable =
        list.fold(0.0, (s, c) => s + c.currentDue);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '${_selected.length} selected' : 'Outstanding'),
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Voucher me dalo',
                  onPressed: () => _moveToVoucher(context, store),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel',
                  onPressed: () =>
                      setState(() => _selected.clear()),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  onPressed: () => _refresh(store),
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'CSV export / share',
                  onPressed: () => _export(list),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Import se data add karo',
                  onPressed: () async {
                    if (!await requireEdit(context)) {
                      return;
                    }
                    if (context.mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ImportScreen()));
                    }
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          const ReadOnlyBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.m, AppSpace.s, AppSpace.m, 0),
            child: TextField(
              style: AppText.body,
              decoration: const InputDecoration(
                hintText: 'Search name, A/C no, phone…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) =>
                  setState(() => _query = v),
            ),
          ),
          statHeader(
            tint: AppColors.tintRose,
            stats: [
              StatItem('Total Outstanding', rs(totalOutstanding),
                  AppColors.dueRed),
              StatItem(
                  'Is Mah (Payable)', rs(totalPayable), AppColors.ink),
              StatItem('Pending', '${list.length}', AppColors.ink),
            ],
            footer: store.lastUpdatedAt != null
                ? 'Last updated: ${fmtDayTime(store.lastUpdatedAt!)}'
                : null,
          ),
          if (officers.length > 2)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8),
                children: officers
                    .map((o) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: ChoiceChip(
                            label: Text(o,
                                style: const TextStyle(
                                    fontSize: 16)),
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
                ? emptyState(
                    icon: Icons.check_circle_rounded,
                    title: 'All clear!',
                    subtitle:
                        'Koi pending qist nahi hai. Naya mahina ya nayi import par yahan nazar aayenge.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                        bottom: AppSpace.m),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        _row(context, store, list[i]),
                  ),
          ),
        ],
      ),
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

  /// Multi-select → har customer ke liye amount + date → voucher entries.
  Future<void> _moveToVoucher(
      BuildContext context, CustomerStore store) async {
    if (!await requireEdit(context)) return;
    final moving = store.outstanding
        .where((c) => _selected.contains(c.accountNo))
        .toList();
    if (moving.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voucher me dalo?'),
        content: Text(
            '${moving.length} customer Voucher me chale jayenge (Outstanding se nikal jayenge). Har ek ki amount + date puchi jayegi.'),
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
    for (final c in moving) {
      if (!context.mounted) break;
      final entry = await _voucherEntryDialog(context, c);
      if (entry != null) {
        await store.addVoucherEntry(entry);
      }
    }
    if (context.mounted) {
      showAppSnack(
          context, '${moving.length} customer Voucher me daal diye');
      setState(() => _selected.clear());
    }
  }

  /// Ek customer ke liye voucher amount + date dialog.
  Future<VoucherEntry?> _voucherEntryDialog(
      BuildContext context, Customer c) async {
    final amountCtrl =
        TextEditingController(text: c.currentDue.toStringAsFixed(0));
    DateTime vDate = DateTime.now();
    double amount = 0;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: Text(c.name.isEmpty ? '(no name)' : c.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A/C ${c.accountNo}  •  Due ${rs(c.currentDue)}',
                  style: AppText.body),
              const SizedBox(height: AppSpace.m),
              TextField(
                controller: amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: AppText.body,
                decoration: const InputDecoration(
                  labelText: 'Voucher amount (Rs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              Row(
                children: [
                  Expanded(
                      child: Text('Date: ${isoDate(vDate)}',
                          style: AppText.body)),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: dctx,
                        initialDate: vDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setD(() => vDate = d);
                    },
                    child: const Text('Badlo'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s),
                  child: Text(err!,
                      style: AppText.body.copyWith(
                          color: AppColors.dueRed, fontSize: 16)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = double.tryParse(amountCtrl.text
                        .replaceAll(',', '')
                        .trim()) ??
                    0;
                if (v <= 0) {
                  setD(() => err = 'Raqam 0 se zyada likhen');
                  return;
                }
                amount = v;
                Navigator.pop(dctx, true);
              },
              child: const Text('Add karo'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    if (ok != true) return null;
    return VoucherEntry(
      id: 'v${DateTime.now().millisecondsSinceEpoch}',
      accountNo: c.accountNo,
      customerName: c.name,
      phone: c.cell,
      amount: amount,
      date: isoDate(vDate),
    );
  }

  Widget _row(
      BuildContext context, CustomerStore store, Customer c) {
    final selected = _selected.contains(c.accountNo);
    return FutureBuilder<bool>(
      future: CallReminderService.hasReminder(c.accountNo),
      builder: (context, snap) {
        final has = snap.data == true;
        return customerRow(
          context: context,
          name: c.name,
          line1: 'A/C ${c.accountNo}  •  ${c.cell}',
          line2:
              'Qist ${rs(c.monthlyInstallment)}  •  Last ${c.lastInstDate}',
          due: c.currentDue,
          balance: c.balance,
          reminderOn: has,
          leading: _selecting
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelect(c),
                )
              : null,
          onCall: () => launchUrl(Uri.parse('tel:${c.cell}')),
          onWhatsApp: () async {
            final msg = await dueReminderMessageWithAccounts(c);
            final ok = await openWhatsApp(c, msg);
            if (!ok && context.mounted) {
              showAppSnack(context, 'WhatsApp nahi khul saka');
            }
          },
          onReminder: () async {
            if (await requireEdit(context)) {
              _reminderTap(context, c);
            }
          },
          onCollect: () async {
            if (await requireEdit(context)) {
              showCollectDialog(context, store, c);
            }
          },
          onTap: _selecting
              ? () => _toggleSelect(c)
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            CustomerDetailScreen(customer: c)),
                  ),
          onLongPress: () async {
            if (await requireEdit(context)) {
              setState(() => _selected.add(c.accountNo));
            }
          },
        );
      },
    );
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
              'Reminder laga hai: ${fmtDayTime(existing)}.\nBadalna ya khatam karna hai?'),
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
          showAppSnack(context, 'Reminder khatam kar diya');
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
        showAppSnack(context,
            'Ye waqt guzar chuka hai — aage ki date/time chuno');
      }
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name.isEmpty ? '(no name)' : c.name),
        content: Text(
            '${fmtDayTime(when)} par call reminder lagana hai?'),
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
        showAppSnack(context,
            'Ye waqt guzar chuka hai — aage ki date/time chuno');
      } else {
        showAppSnack(
            context, 'Reminder lag gaya: ${fmtDayTime(scheduled)}');
        setState(() {});
      }
    }
  }
}
