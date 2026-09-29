/// Reusable customer picker: searchable list with checkboxes.
/// single-select ya multi-select. Voucher "+" aur Received "+" me istemal hota hai.
library;

import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../theme/app_theme.dart';

/// Shows the picker dialog. Returns the selected customers (empty = cancel).
Future<List<Customer>> pickCustomers(
  BuildContext context, {
  required List<Customer> customers,
  required String title,
  bool multi = true,
}) async {
  final sel = await showDialog<Set<String>>(
    context: context,
    builder: (ctx) => _PickerDialog(
      customers: customers,
      title: title,
      multi: multi,
    ),
  );
  if (sel == null || sel.isEmpty) return [];
  return customers.where((c) => sel.contains(c.accountNo)).toList();
}

class _PickerDialog extends StatefulWidget {
  final List<Customer> customers;
  final String title;
  final bool multi;
  const _PickerDialog(
      {required this.customers, required this.title, required this.multi});

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  String _query = '';
  final Set<String> _sel = {};

  List<Customer> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.customers;
    return widget.customers
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.accountNo.contains(q) ||
            c.cell.contains(q))
        .toList();
  }

  void _toggle(String acc) {
    setState(() {
      if (widget.multi) {
        if (_sel.contains(acc)) {
          _sel.remove(acc);
        } else {
          _sel.add(acc);
        }
      } else {
        _sel
          ..clear()
          ..add(acc);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog)),
      insetPadding: const EdgeInsets.all(AppSpace.m),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.l, AppSpace.l, AppSpace.l, AppSpace.s),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: AppText.h2)),
                  if (_sel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${_sel.length}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.l),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search naam, A/C, phone…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: AppSpace.s),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('Koi customer nahi mila',
                          style: AppText.body))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        final s = _sel.contains(c.accountNo);
                        return ListTile(
                          minVerticalPadding: 12,
                          leading: Checkbox(
                            value: s,
                            onChanged: (_) =>
                                _toggle(c.accountNo),
                          ),
                          title: Text(
                              c.name.isEmpty
                                  ? '(no name)'
                                  : c.name,
                              style: AppText.bodyBold),
                          subtitle: Text(
                            'A/C ${c.accountNo}  •  Due ${rs(c.currentDue)}',
                            style: AppText.caption
                                .copyWith(fontSize: 15),
                          ),
                          selected: s,
                          onTap: () => _toggle(c.accountNo),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.m),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.m),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _sel.isEmpty
                          ? null
                          : () => Navigator.pop(context, _sel),
                      child: Text(
                          widget.multi ? 'OK (${_sel.length})' : 'OK'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
