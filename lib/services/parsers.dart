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
  final int months;

  /// Column parser sets these: was the "Due = OS - Paid" maths check run,
  /// and did it pass? [flagReason] batata hai kya ghalat laga.
  final bool mathChecked;
  final bool verified;
  final String flagReason;

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
    this.months = 0,
    this.mathChecked = false,
    this.verified = true,
    this.flagReason = '',
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
  // Pehle strict parser try karo.
  final strict = _parseOutstandingRowStrict(line);
  if (strict != null) return strict;
  // Strict fail ho to lenient fallback.
  return _parseOutstandingRowLenient(line);
}

/// Strict parser (original logic).
OutstandingRow? _parseOutstandingRowStrict(String line) {
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

/// Lenient fallback: jab strict format match na ho.
/// Koi bhi line jis me A/C No (5-6 digits) + kuch numbers hon.
/// Cell optional, date optional — jo mile le lo.
OutstandingRow? _parseOutstandingRowLenient(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  // Header/footer lines skip karo.
  final lower = trimmed.toLowerCase();
  const skipWords = [
    'account', 'customer', 'balance', 'installment', 'officer',
    'total', 'page', 'print', 'date', 'report', 'outstanding',
    'sr#', 'sr #', 'a/c',
  ];
  for (final w in skipWords) {
    if (lower == w || lower.startsWith('$w ') || lower.endsWith(' $w')) {
      // Poori line sirf header hai to skip — lekin agar numbers bhi hain to rakho.
      if (!RegExp(r'\d{5,}').hasMatch(trimmed)) return null;
    }
  }

  // A/C No dhoondo: 5-6 digits ka number.
  final acMatch = RegExp(r'\b\d{5,6}\b').firstMatch(trimmed);
  if (acMatch == null) return null;
  final acNo = acMatch.group(0)!;

  // Cell dhoondo (optional).
  final cellMatch = _cellRe.firstMatch(trimmed);
  final cell = cellMatch?.group(0) ?? '';

  // Dates dhoondo.
  final dates = _dateRe.allMatches(trimmed).map((m) => m.group(0)!).toList();

  // Saare numbers nikalo (commas hata kar).
  final numRe = RegExp(r'[\d,]+\.?\d*');
  final allNums = numRe
      .allMatches(trimmed)
      .map((m) => m.group(0)!.replaceAll(',', ''))
      .where((s) => s.isNotEmpty && double.tryParse(s) != null)
      .toList();

  // A/C No aur cell ko numbers se hatao (wo identity hain, paise nahi).
  final moneyNums = <double>[];
  for (final n in allNums) {
    if (n == acNo) continue;
    if (n == cell) continue;
    // Sr# (chhota number shuru me) skip — lekin paise bhi chhote ho sakte hain.
    final v = double.tryParse(n) ?? 0;
    moneyNums.add(v);
  }
  // Kam se kam 2 money numbers hone chahiye (warna ye data row nahi).
  if (moneyNums.length < 2) return null;

  // Naam: A/C No se pehle/wale text me se — numbers aur dates hata kar.
  var namePart = trimmed.substring(0, acMatch.start).trim();
  // Agar A/C No shuru me hai to uske baad wala text dekho.
  if (namePart.isEmpty || RegExp(r'^\d+$').hasMatch(namePart)) {
    namePart = trimmed.substring(acMatch.end).trim();
  }
  // Cell, dates, aur numbers hatao.
  if (cell.isNotEmpty) namePart = namePart.replaceAll(cell, ' ');
  for (final d in dates) {
    namePart = namePart.replaceAll(d, ' ');
  }
  namePart = namePart.replaceAll(RegExp(r'\b\d[\d,]*\.?\d*\b'), ' ');
  namePart = namePart.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Officer alag karo agar maloom ho.
  var officer = '';
  var name = namePart;
  for (final known in _knownOfficers) {
    if (namePart.endsWith(known)) {
      officer = known;
      name = namePart.substring(0, namePart.length - known.length).trim();
      break;
    }
  }
  if (name.isEmpty) name = 'A/C $acNo';

  // Money columns: aakhir se — currentDue, balance, installment.
  // Lenient: jo mile usay best guess se lagao.
  double pick(int fromEnd) {
    if (moneyNums.length >= fromEnd) {
      return moneyNums[moneyNums.length - fromEnd];
    }
    return 0;
  }

  return OutstandingRow(
    accountNo: acNo,
    accDate: dates.isNotEmpty ? dates.first : '',
    name: name,
    officer: officer,
    cell: cell,
    item: '',
    price: pick(6),
    balance: pick(5),
    installment: pick(4),
    osAmount: pick(3),
    paid: pick(2),
    currentDue: pick(1),
    lastInstDate: dates.length > 1 ? dates.last : (dates.isNotEmpty ? dates.first : ''),
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
// Column-aware outstanding report parser.
//
// Purana line-based parser har OCR line ko alag tokta tha — table ke columns
// ka pata nahi chalta tha. Ye parser pehle TABLE HEADER dhoondta hai
// (Sr# | A/CNo | Acc Date | ...), header lafzon ki x-position se har column
// ki had (boundary) banata hai, phir har data line ke lafzon ko unki
// x-position ke hisab se SAHI column me daalta hai (column-wise parhna).
//
// Phir har row ka hisab cross-check hota hai:
//    Current Due  ==  OS Amount − Paid
// aur har recovery officer ke group ka total milaya jata hai:
//    sum(rows' Due)  ==  group header ka Due total
// ---------------------------------------------------------------------------

/// OCR ka ek lafz + uski position (ML Kit element boundingBox se aati hai).
class OcrWord {
  final String text;
  final double left;
  final double right;
  final double top;
  const OcrWord(this.text,
      {required this.left, required this.right, required this.top});
  double get cx => (left + right) / 2;
}

/// OCR ki ek line = lafzon ki tartib-war list.
class OcrLine {
  final List<OcrWord> words;
  const OcrLine(this.words);
  String get text => words.map((w) => w.text).join(' ');
}

/// Officer group ka hisab-check: group header ka total vs parhi gayi rows.
class OfficerGroupCheck {
  final String officer;
  final int rowCount;
  final double expectedDue;
  final double parsedDue;
  OfficerGroupCheck({
    required this.officer,
    required this.rowCount,
    required this.expectedDue,
    required this.parsedDue,
  });
  bool get hasTotal => expectedDue > 0;
  bool get matches =>
      !hasTotal ||
      (expectedDue - parsedDue).abs() <=
          (expectedDue * 0.01).clamp(10.0, 500.0);
}

/// Poori report ka nateeja.
class OutstandingReport {
  final List<OutstandingRow> rows;
  final List<String> failed;
  final List<OfficerGroupCheck> groups;
  final double pageTotalDue;
  final double parsedTotalDue;
  OutstandingReport({
    required this.rows,
    required this.failed,
    required this.groups,
    this.pageTotalDue = 0,
    this.parsedTotalDue = 0,
  });
  bool get totalMatches =>
      pageTotalDue <= 0 ||
      (pageTotalDue - parsedTotalDue).abs() <=
          (pageTotalDue * 0.01).clamp(10.0, 500.0);
  int get flaggedCount => rows.where((r) => !r.verified).length;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

/// Header ke ek lafz ko column key me badlo. [afterLast] batata hai ke
/// "Last" wala header pehle aa chuka (taake "Inst." ghalat column na pakre).
String? _headerKey(String word, bool afterLast) {
  final n = _norm(word);
  if (n.isEmpty) return null;
  if (n.contains('acno')) return 'accountNo';
  if (n == 'sr') return 'sr';
  if (n == 'acc') return 'accDate';
  if (n.contains('customer')) return 'name';
  if (n.contains('inquiry')) return 'officer';
  if (n == 'cell') return 'cell';
  if (n == 'item') return 'item';
  if (n == 'price') return 'price';
  if (n == 'balance') return 'balance';
  // "Last" ke baad aane wale "Inst."/"Date" usi column ka hissa hain.
  if (n == 'last') return 'lastInstDate';
  if (n == 'install' || n == 'instal' || n == 'ment') {
    return afterLast ? null : 'installment';
  }
  if (n == 'inst' || n == 'date') {
    return null; // position se qareebi column me jayega
  }
  if (n == 'os') return 'osAmount';
  if (n == 'paid') return 'paid';
  if (n == 'current' || n == 'due') return 'currentDue';
  if (n == 'mo' || n.startsWith('month') || n == 'mos' || n == 'hs') {
    return 'months';
  }
  if (n.contains('officer')) return 'officer';
  return null;
}

class _ColBound {
  final String key;
  final double x0;
  final double x1;
  _ColBound(this.key, this.x0, this.x1);
  bool contains(double x) => x >= x0 && x < x1;
}

/// Ek page ki header lines se column boundaries banao.
/// Null = is page par header nahi mila.
List<_ColBound>? _detectColumns(List<OcrLine> page) {
  // Header jaisi lines: kam az kam 3 maloom column lafz hon.
  final headerWords = <OcrWord>[];
  for (final line in page) {
    var hits = 0;
    var afterLast = false;
    for (final w in line.words) {
      final k = _headerKey(w.text, afterLast);
      if (k != null) {
        hits++;
        if (k == 'lastInstDate') afterLast = true;
      }
    }
    if (hits >= 3) headerWords.addAll(line.words);
  }
  if (headerWords.isEmpty) return null;

  // Har lafz ko key do (x-tartib me, "Last" context ke sath).
  final keyed = <MapEntry<String, OcrWord>>[];
  var afterLast = false;
  final sorted = List<OcrWord>.of(headerWords)
    ..sort((a, b) => a.cx.compareTo(b.cx));
  for (final w in sorted) {
    final k = _headerKey(w.text, afterLast);
    if (k == null) continue;
    if (k == 'lastInstDate') afterLast = true;
    // Ek key sirf ek baar — dohra lafz (jaise "Date") pehli position rakhe.
    if (keyed.any((e) => e.key == k)) continue;
    keyed.add(MapEntry(k, w));
  }
  if (keyed.length < 5) return null; // header adhoora — fallback behtar
  keyed.sort((a, b) => a.value.cx.compareTo(b.value.cx));

  // Boundaries: aas-paas ke header lafzon ke darmiyan midpoint.
  final bounds = <_ColBound>[];
  for (var i = 0; i < keyed.length; i++) {
    final cx = keyed[i].value.cx;
    final x0 = i == 0
        ? 0.0
        : (keyed[i - 1].value.cx + cx) / 2;
    final x1 = i == keyed.length - 1
        ? double.infinity
        : (cx + keyed[i + 1].value.cx) / 2;
    bounds.add(_ColBound(keyed[i].key, x0, x1));
  }
  return bounds;
}

/// Data line ke lafzon ko columns me baanto: key → merged text.
Map<String, String> _assignColumns(OcrLine line, List<_ColBound> bounds) {
  final parts = <String, List<String>>{};
  for (final w in line.words) {
    var key = 'unknown';
    for (final b in bounds) {
      if (b.contains(w.cx)) {
        key = b.key;
        break;
      }
    }
    (parts[key] ??= []).add(w.text);
  }
  return {for (final e in parts.entries) e.key: e.value.join(' ')};
}

double _num(String s) =>
    double.tryParse(s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.]'), '')) ??
    0;

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Header ki agli line me bacha-khucha tukra ("Date", "hs", "Amount" jaisa)
/// — ye data nahi, skip karo.
bool _isHeaderFragment(OcrLine line) {
  if (line.words.isEmpty) return false;
  const frags = {
    'date', 'inst', 'inst.', 'hs', 'mos', 'mo', 'month', 'months',
    'amount', 'due', 'no', '#', 'sr', 'a/c', 'a/cno', 'acc', 'cell',
    'cell#', 'name', 'customer', 'price', 'balance', 'install', 'instal',
    'installment', 'ment', 'os', 'paid', 'current', 'last', 'officer',
    'inquiry', 'item',
  };
  for (final w in line.words) {
    final n = _norm(w.text);
    if (!frags.contains(n) && _headerKey(w.text, false) == null) {
      return false;
    }
  }
  // Poori line sirf header lafzon ki hai aur A/C number bhi nahi.
  final digits = _digits(line.text);
  if (RegExp(r'\d{5,}').hasMatch(digits)) return false;
  return true;
}

/// Column-wise parse: pages (har page = OcrLine list).
/// Header na mile to purane line-parser par fallback.
OutstandingReport parseOutstandingReport(List<List<OcrLine>> pages) {
  final rows = <OutstandingRow>[];
  final failed = <String>[];
  final groupRows = <String, List<double>>{};
  final groupNames = <String, String>{};
  final groupOrder = <String>[];
  final rowGroups = <String>[]; // har row kis group section ki hai
  var currentGroup = '';
  double pageTotalDue = 0;
  OutstandingRow? prevRow;

  for (final page in pages) {
    final bounds = _detectColumns(page);
    if (bounds == null) {
      // Fallback: purana line-based parser.
      final fb = parseOutstandingLines(page.map((l) => l.text).toList());
      for (final r in fb.rows) {
        rows.add(OutstandingRow(
          accountNo: r.accountNo,
          accDate: r.accDate,
          name: r.name,
          officer: currentGroup.isNotEmpty ? currentGroup : r.officer,
          cell: r.cell,
          item: r.item,
          price: r.price,
          balance: r.balance,
          installment: r.installment,
          osAmount: r.osAmount,
          paid: r.paid,
          currentDue: r.currentDue,
          lastInstDate: r.lastInstDate,
        ));
        rowGroups.add(currentGroup);
      }
      failed.addAll(fb.failed);
      continue;
    }

    // Header se PEHLE ki lines (title, address, print-date) — ye data nahi,
    // inhe "failed" me dalna shor hai. Pehli header line dhoondo.
    var firstHeaderIdx = page.length;
    for (var i = 0; i < page.length; i++) {
      var hits = 0;
      for (final w in page[i].words) {
        if (_headerKey(w.text, false) != null) hits++;
      }
      if (hits >= 3) {
        firstHeaderIdx = i;
        break;
      }
    }

    for (var li = 0; li < page.length; li++) {
      final line = page[li];
      final text = line.text.trim();
      if (text.isEmpty) continue;
      // Title/address header se pehle — khamoshi se skip.
      if (li < firstHeaderIdx) continue;
      final cols = _assignColumns(line, bounds);

      // Header line khud skip.
      var headerHits = 0;
      for (final w in line.words) {
        if (_headerKey(w.text, false) != null) headerHits++;
      }
      if (headerHits >= 3) continue;
      // Header ka bacha-khucha tukra (agli line me "Date"/"hs" jaisa) skip.
      if (_isHeaderFragment(line)) continue;

      final acNo = _digits(cols['accountNo'] ?? '');
      final isAcNo = RegExp(r'^\d{5,6}$').hasMatch(acNo);

      // "Total :" wali aakhri line.
      final firstWord = line.words.isNotEmpty
          ? _norm(line.words.first.text)
          : '';
      if (firstWord == 'total') {
        final due = _num(cols['currentDue'] ?? '');
        if (due > 0) pageTotalDue = due;
        continue;
      }

      final price = _num(cols['price'] ?? '');
      final balance = _num(cols['balance'] ?? '');
      final installment = _num(cols['installment'] ?? '');
      final os = _num(cols['osAmount'] ?? '');
      final paid = _num(cols['paid'] ?? '');
      final due = _num(cols['currentDue'] ?? '');

      if (!isAcNo) {
        // Group header row? (officer ka naam + 3 totals, price/installment 0)
        // Naam poori line se nikalo (column-split "Faiz Rasool" ko "Faiz"
        // na banaye) — sirf hindse hatayen.
        final lineName = text
            .replaceAll(RegExp(r'\d[\d,]*'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final hasTotals = (os > 0 || paid > 0 || due > 0) &&
            price == 0 &&
            installment == 0 &&
            balance == 0;
        if (hasTotals &&
            lineName.isNotEmpty &&
            !RegExp(r'\d{5,}').hasMatch(cols['accountNo'] ?? '')) {
          final gname = lineName;
          if (gname.isNotEmpty) {
            currentGroup = gname;
            if (!groupOrder.contains(gname)) groupOrder.add(gname);
            groupNames[gname] = gname;
            groupRows[gname] = [os, paid, due];
            prevRow = null;
            continue;
          }
        }
        // Naam agli line me wrap hua? (pichli row ke naam se joro)
        final nameBit = (cols['name'] ?? '').trim();
        if (prevRow != null &&
            nameBit.isNotEmpty &&
            os == 0 && paid == 0 && due == 0 && price == 0) {
          prevRow = OutstandingRow(
            accountNo: prevRow.accountNo,
            accDate: prevRow.accDate,
            name: '${prevRow.name} $nameBit'.trim(),
            officer: prevRow.officer,
            cell: prevRow.cell,
            item: prevRow.item.isEmpty ? (cols['item'] ?? '').trim() : prevRow.item,
            price: prevRow.price,
            balance: prevRow.balance,
            installment: prevRow.installment,
            osAmount: prevRow.osAmount,
            paid: prevRow.paid,
            currentDue: prevRow.currentDue,
            lastInstDate: prevRow.lastInstDate,
            months: prevRow.months,
            mathChecked: prevRow.mathChecked,
            verified: prevRow.verified,
            flagReason: prevRow.flagReason,
          );
          rows[rows.length - 1] = prevRow;
          continue;
        }
        failed.add(text);
        prevRow = null;
        continue;
      }

      // ---- data row ----
      final cellM = _cellRe.firstMatch(cols['cell'] ?? '');
      final dateM = _dateRe.firstMatch(cols['lastInstDate'] ?? '');
      final accDateM = _dateRe.firstMatch(cols['accDate'] ?? '');
      final monthsM = RegExp(r'\d+').firstMatch(cols['months'] ?? '');

      // Hisab check: Current Due == OS Amount − Paid
      final expected = os - paid;
      final tol = (expected.abs() * 0.01).clamp(2.0, 200.0);
      final dueOk = (due - expected).abs() <= tol;
      var verified = true;
      var reason = '';
      if (!dueOk) {
        verified = false;
        reason =
            'Hisab nahi mila: OS ${_fmt(os)} − Paid ${_fmt(paid)} = ${_fmt(expected)}, Due likha ${_fmt(due)}';
      }
      final row = OutstandingRow(
        accountNo: acNo,
        accDate: accDateM?.group(0) ?? (cols['accDate'] ?? '').trim(),
        name: (cols['name'] ?? '').trim(),
        officer: (cols['officer'] ?? '').trim().isNotEmpty
            ? (cols['officer'] ?? '').trim()
            : currentGroup,
        cell: cellM?.group(0) ?? _digits(cols['cell'] ?? ''),
        item: (cols['item'] ?? '').trim(),
        price: price,
        balance: balance,
        installment: installment,
        osAmount: os,
        paid: paid,
        currentDue: due,
        lastInstDate:
            dateM?.group(0) ?? (cols['lastInstDate'] ?? '').trim(),
        months: monthsM != null ? int.parse(monthsM.group(0)!) : 0,
        mathChecked: true,
        verified: verified,
        flagReason: reason,
      );
      rows.add(row);
      rowGroups.add(currentGroup);
      prevRow = row;
    }
  }

  // Group reconciliation — section ke hisab se (rows apne group header ke
  // neeche wali hain, officer column se match nahi).
  final groups = <OfficerGroupCheck>[];
  for (final g in groupOrder) {
    final totals = groupRows[g] ?? [0.0, 0.0, 0.0];
    var parsedDue = 0.0;
    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      if (rowGroups[i] == g) {
        parsedDue += rows[i].currentDue;
        count++;
      }
    }
    groups.add(OfficerGroupCheck(
      officer: g,
      rowCount: count,
      expectedDue: totals[2],
      parsedDue: parsedDue,
    ));
  }
  final parsedTotalDue = rows.fold(0.0, (s, r) => s + r.currentDue);

  return OutstandingReport(
    rows: rows,
    failed: failed,
    groups: groups,
    pageTotalDue: pageTotalDue,
    parsedTotalDue: parsedTotalDue,
  );
}

String _fmt(double v) {
  final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  // hazaar separator
  final parts = s.split('.');
  final buf = StringBuffer();
  final digits = parts[0].split('').reversed.toList();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final int_ = buf.toString().split('').reversed.join('');
  return parts.length > 1 ? '$int_.${parts[1]}' : int_;
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
