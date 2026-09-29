/// Pure parsing logic for QistBook's two print formats.
/// No Flutter imports here — unit-testable, and mirrored by
/// tool/validate_parser.py for cross-checking against your real prints.
library;

import '../models/customer.dart';

/// One row of the OUTSTANDING report:
/// Sr# | A/CNo | Acc Date | Customer Name | Inquiry Officer | Cell# |
/// Item | Price | Balance | Installment | OS Amount | Paid |
/// Current Due | Last Inst. Date | Mos
class OutstandingRow {
  final String accountNo;
  final String accDate;
  final String name;
  final String officer;
  final String cell;
  final String item;
  final double price;
  final double balance;
  final double installment;
  final double osAmount;
  final double paid;
  final double currentDue;
  final String lastInstDate;

  OutstandingRow({
    required this.accountNo,
    this.accDate = '',
    this.name = '',
    this.officer = '',
    this.cell = '',
    this.item = '',
    this.price = 0,
    this.balance = 0,
    this.installment = 0,
    this.osAmount = 0,
    this.paid = 0,
    this.currentDue = 0,
    this.lastInstDate = '',
  });
}

double _toDouble(String s) =>
    double.tryParse(s.replaceAll(',', '').trim()) ?? 0;

final _cellRe = RegExp(r'03\d{9}');
final _dateRe = RegExp(r'\d{1,2}-[A-Za-z]{3}-\d{2,4}');

/// Parse a single OCR text line from the outstanding table.
/// Anchor-based: the cell number (03XXXXXXXXX) splits the row into
/// a left part (identity) and a right part (money columns).
OutstandingRow? parseOutstandingRow(String line) {
  final cellMatch = _cellRe.firstMatch(line);
  if (cellMatch == null) return null;
  final cell = cellMatch.group(0)!;

  final left = line.substring(0, cellMatch.start).trim();
  final right = line.substring(cellMatch.end).trim();

  // ---- left: "Sr# A/CNo AccDate Name... Officer"
  final leftTokens = left.split(RegExp(r'\s+'));
  if (leftTokens.length < 4) return null;
  // Sr# (leading int), A/CNo (5-6 digits), AccDate (date)
  final srOk = int.tryParse(leftTokens[0]) != null;
  final acNo = leftTokens.length > 1 ? leftTokens[1] : '';
  if (!srOk || !RegExp(r'^\d{5,6}$').hasMatch(acNo)) return null;
  String accDate = '';
  int nameStart = 2;
  for (var i = 2; i < leftTokens.length; i++) {
    if (_dateRe.hasMatch(leftTokens[i])) {
      accDate = leftTokens[i];
      nameStart = i + 1;
      break;
    }
  }
  final nameAndOfficer = leftTokens.sublist(nameStart).join(' ');
  // Officer is the trailing known officer name when present; otherwise the
  // whole tail is kept as the name and fixed on the review screen.
  String name = nameAndOfficer;
  String officer = '';
  for (final known in _knownOfficers) {
    if (nameAndOfficer.endsWith(known)) {
      officer = known;
      name = nameAndOfficer
          .substring(0, nameAndOfficer.length - known.length)
          .trim();
      break;
    }
  }

  // ---- right: "ITEM PRICE BALANCE INSTALLMENT OS PAID CURRENT_DUE LAST_DATE [Mos]"
  // Date at the end anchors the money columns.
  final dateMatch = _dateRe.firstMatch(right);
  if (dateMatch == null) return null;
  final lastInstDate = dateMatch.group(0)!;
  final beforeDate = right.substring(0, dateMatch.start).trim();
  final numTokens =
      beforeDate.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (numTokens.length < 7) return null;
  // Last 6 numeric tokens are the money columns; everything before is ITEM.
  final money = numTokens.sublist(numTokens.length - 6);
  if (money.any((t) => double.tryParse(t.replaceAll(',', '')) == null)) {
    return null;
  }
  final item = numTokens.sublist(0, numTokens.length - 6).join(' ');

  return OutstandingRow(
    accountNo: acNo,
    accDate: accDate,
    name: name,
    officer: officer,
    cell: cell,
    item: item,
    price: _toDouble(money[0]),
    balance: _toDouble(money[1]),
    installment: _toDouble(money[2]),
    osAmount: _toDouble(money[3]),
    paid: _toDouble(money[4]),
    currentDue: _toDouble(money[5]),
    lastInstDate: lastInstDate,
  );
}

/// Officer names seen on your prints — extend as new ones appear.
/// (Used only to split "Customer Name + Officer" on one OCR line.)
const _knownOfficers = <String>[
  'Sajjad Ahmed',
  'M Asad',
  'Amjad Ali Rana',
  'Yasir islam',
  'Arslan Sulehri',
  'Ahsan Mehmood',
];

/// Parse many OCR lines; returns rows + the lines that failed (for review).
({List<OutstandingRow> rows, List<String> failed}) parseOutstandingLines(
    List<String> lines) {
  final rows = <OutstandingRow>[];
  final failed = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final row = parseOutstandingRow(line);
    if (row == null) {
      failed.add(line);
    } else {
      rows.add(row);
    }
  }
  return (rows: rows, failed: failed);
}

// ---------------------------------------------------------------------------
// Detail statement parser (one page per customer).
// Works on the full OCR text of the page: finds labeled fields.
// ---------------------------------------------------------------------------

String? _field(String text, String label) {
  // e.g. label "A/C No." -> matches "A/C No. : 001766"
  final pattern =
      RegExp('${RegExp.escape(label)}\\s*:?\\s*([^\\n]+)', caseSensitive: false);
  final m = pattern.firstMatch(text);
  if (m == null) return null;
  return m.group(1)!.split(RegExp(r'\s{2,}')).first.trim();
}

/// Build/update a Customer from a detail-statement page's OCR text.
/// [existing] is reused when the A/C No. matches a stored customer.
Customer parseStatementPage(String ocrText, {Customer? existing}) {
  final accountNo = _field(ocrText, 'A/C No.')?.replaceAll(RegExp(r'\D'), '') ?? '';
  final c = existing ?? Customer(accountNo: accountNo);
  if (accountNo.isNotEmpty) c.accountNo = accountNo;

  String? v(String label) => _field(ocrText, label);
  c.customerCode = v('Customer Code')?.replaceAll(RegExp(r'\D'), '') ?? c.customerCode;
  c.accountDate = v('A/C Date') ?? c.accountDate;
  c.dueDate = v('Due Date') ?? c.dueDate;
  final dueAmtM = RegExp(r'Due Amount\s*:?\s*([\d,]+)').firstMatch(ocrText);
  if (dueAmtM != null) c.dueAmount = _toDouble(dueAmtM.group(1)!);
  c.processNo =
      v('Process #')?.replaceAll(RegExp(r'\D'), '') ?? c.processNo;
  c.preAccountNo =
      v('Pre. A/C No.')?.replaceAll(RegExp(r'\D'), '') ?? c.preAccountNo;
  c.fineTime = v('Fine Time')?.split(RegExp(r'\s{2,}')).first.trim() ?? c.fineTime;
  c.name = v('Name')?.split(RegExp(r'\s{2,}')).first.trim() ?? c.name;

  final cellM = RegExp(r'Cell\s*:?\s*(03\d{9})').firstMatch(ocrText);
  if (cellM != null) c.cell = cellM.group(1)!;
  final cnicM = RegExp(r'CNIC\s*:?\s*([\d-]{13,15})').firstMatch(ocrText);
  if (cnicM != null) c.cnic = cnicM.group(1)!;

  c.resAddress = v('Res. Address') ?? c.resAddress;
  c.offAddress = v('Off. Address') ?? c.offAddress;
  c.occupation = v('Occupation') ?? c.occupation;
  final mi = RegExp(r'Monthly Income\s*:?\s*([\d,]+)').firstMatch(ocrText);
  if (mi != null) c.monthlyIncome = _toDouble(mi.group(1)!);
  final ho = v('House Owner');
  if (ho != null) c.houseOwner = ho.toLowerCase().startsWith('y');
  final mar = v('Married');
  if (mar != null) c.married = mar.toLowerCase().startsWith('y');
  c.marketingOfficer =
      v('Marketing')?.split(RegExp(r'\s{2,}')).first.trim() ??
          c.marketingOfficer;
  c.verifiedBy =
      v('Verified')?.split(RegExp(r'\s{2,}')).first.trim() ?? c.verifiedBy;
  c.deliveredBy =
      v('Delivered')?.split(RegExp(r'\s{2,}')).first.trim() ??
          c.deliveredBy;

  c.company = v('Company')?.split(RegExp(r'\s{2,}')).first.trim() ?? c.company;
  c.modelNo = v('Model No.') ?? c.modelNo;
  c.item = v('Item Name') ?? c.item;
  c.serialNo = v('Serial No') ?? c.serialNo;

  final priceM = RegExp(r'Price\s*\n?\s*([\d,]+)').firstMatch(ocrText);
  if (priceM != null) c.price = _toDouble(priceM.group(1)!);
  final advM = RegExp(r'Advance on Delivery\s*:?\s*([\d,]+)').firstMatch(ocrText);
  if (advM != null) c.advance = _toDouble(advM.group(1)!);
  final instM = RegExp(r'Monthly\.?\s*Inst\.?\s*:?\s*([\d,]+)').firstMatch(ocrText);
  if (instM != null) c.monthlyInstallment = _toDouble(instM.group(1)!);
  final durM = RegExp(r'Duration\s*:?\s*(\d+)').firstMatch(ocrText);
  if (durM != null) c.durationMonths = int.tryParse(durM.group(1)!) ?? c.durationMonths;
  final balM = RegExp(r'Current Balance\s*:?\s*([\d,]+)').firstMatch(ocrText);
  if (balM != null) c.balance = _toDouble(balM.group(1)!);

  // Guarantors table: rows look like "M Yousaf  34602-7391638-7  vill soli...  03243925005"
  c.guarantors = _parseGuarantors(ocrText);
  // Collection rows: "1  014046  6-Jun-24  37,950  3,450  0  0.00  34,500 ..."
  final newCollections = _parseCollections(ocrText);
  if (newCollections.isNotEmpty) c.collections = newCollections;

  c.needsDetail = false;
  c.status = c.balance > 0 ? AccountStatus.active : c.status;
  return c;
}

List<Guarantor> _parseGuarantors(String text) {
  final out = <Guarantor>[];
  final section =
      RegExp(r'Guarantors Information\s*:?([\s\S]*?)Installment Collection',
              caseSensitive: false)
          .firstMatch(text);
  final body = section?.group(1) ?? text;
  for (final line in body.split('\n')) {
    final l = line.trim();
    if (l.isEmpty || l.startsWith('Customer Name') || l.startsWith('CNIC')) {
      continue;
    }
    final phoneM = RegExp(r'03\d{9}').firstMatch(l);
    final cnicM = RegExp(r'\d{5}-\d{7}-\d').firstMatch(l);
    if (phoneM == null && cnicM == null) continue;
    // Name = text before the first CNIC/phone/double-space
    var name = l;
    final cut = RegExp(r'\d{5}-\d{7}-\d|03\d{9}|\s{2,}').firstMatch(l);
    if (cut != null) name = l.substring(0, cut.start).trim();
    if (name.isEmpty) continue;
    out.add(Guarantor(
      name: name,
      cnic: cnicM?.group(0) ?? '',
      phone: phoneM?.group(0) ?? '',
    ));
  }
  return out;
}

List<CollectionEntry> _parseCollections(String text) {
  final out = <CollectionEntry>[];
  final section = RegExp(
          r'Installment Collection Detail\s*:?([\s\S]*)$',
          caseSensitive: false)
      .firstMatch(text);
  final body = section?.group(1) ?? '';
  for (final line in body.split('\n')) {
    // "1  014046  6-Jun-24  37,950  3,450  0  0.00  34,500  0  Nothing  M Asad"
    final m = RegExp(
      r'^\s*(\d+)\s+(\d{4,6})\s+(\d{1,2}-[A-Za-z]{3}-\d{2,4})\s+'
      r'([\d,]+)\s+([\d,]+)\s+(\d+)\s+([\d.]+)\s+([\d,]+)',
    ).firstMatch(line);
    if (m == null) continue;
    out.add(CollectionEntry(
      receiptNo: m.group(2)!,
      date: m.group(3)!,
      prevBalance: _toDouble(m.group(4)!),
      collected: _toDouble(m.group(5)!),
      balance: _toDouble(m.group(8)!),
      receivedBy: line.split(RegExp(r'\s{2,}')).last.trim(),
    ));
  }
  return out;
}
