/// CSV export: Outstanding / Received ka data CSV banake share_plus se share
/// (WhatsApp, email, Drive…). Excel me seedha khulta hai.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/customer.dart';
import 'error_log.dart';

String _esc(String s) {
  final v = s.replaceAll('"', '""');
  return '"$v"';
}

String _cell(String v) => _esc(v);

/// Outstanding CSV: A/C No, Name, Phone, Installment, Due, Balance.
String outstandingCsv(List<Customer> list) {
  final sb = StringBuffer();
  sb.writeln('A/C No,Name,Phone,Installment,Due,Balance');
  for (final c in list) {
    sb.writeln([
      _cell(c.accountNo),
      _cell(c.name),
      _cell(c.cell),
      c.monthlyInstallment.toStringAsFixed(0),
      c.currentDue.toStringAsFixed(0),
      c.balance.toStringAsFixed(0),
    ].join(','));
  }
  return sb.toString();
}

/// Received CSV: A/C No, Name, Amount, Method, Date.
String receivedCsv(List<ReceivedPayment> list) {
  final sb = StringBuffer();
  sb.writeln('A/C No,Name,Amount,Method,Date');
  for (final r in list) {
    sb.writeln([
      _cell(r.accountNo),
      _cell(r.customerName),
      r.amount.toStringAsFixed(0),
      _cell(r.method),
      _cell(r.date),
    ].join(','));
  }
  return sb.toString();
}

/// CSV file banao (temp dir) aur share sheet kholo. Returns false agar fail.
Future<bool> shareCsv(String filename, String csv,
    {String text = ''}) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, filename));
    await f.writeAsString(csv);
    await Share.shareXFiles([XFile(f.path)],
        text: text.isEmpty ? filename : text);
    return true;
  } catch (e) {
    ErrorLog.log('CSV export', e);
    return false;
  }
}
