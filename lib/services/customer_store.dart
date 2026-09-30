/// Local-first storage for QistBook (sqflite) + ChangeNotifier store.
///
/// PER-USER: har login user ka apna database file hota hai: qistbook_<uid>.db
/// Firestore (per-user, private) optional cloud sync hai; sqflite offline
/// cache + primary store hai.
///
/// Vouchers: entries-based (table `vouchers`) — ek customer ke kayi vouchers
/// ho sakte hain, har ek ki date + amount history me rehti hai. Vouchered
/// customers monthly rollover me FROZEN hote hain (unki due khud nahi badalti).
library;

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import '../theme/app_theme.dart' show monthKey, isoDate;
import 'auth_service.dart';
import 'error_log.dart';
import 'firebase_service.dart';
import 'parsers.dart';

/// Voucher group: ek account ki saari voucher entries (newest first).
class VoucherGroup {
  final String accountNo;
  final String customerName;
  final String phone;
  final List<VoucherEntry> entries;

  VoucherGroup({
    required this.accountNo,
    required this.customerName,
    required this.phone,
    required this.entries,
  });

  double get total => entries.fold(0.0, (s, e) => s + e.amount);
  int get count => entries.length;
}

class CustomerStore extends ChangeNotifier {
  Database? _db;
  final List<Customer> _customers = [];
  final List<ReceivedPayment> _payments = [];
  final List<VoucherEntry> _vouchers = [];
  String? _uid;
  String? get uid => _uid;

  /// Safe mode = asal data file khul nahi saki, app memory me kholi hai
  /// taake kaam ruke nahi. Banner me "Dobara koshish karein" hota hai.
  bool safeMode = false;

  /// When the data was last refreshed by an import (shown in the UI so the
  /// user can trust the numbers are current).
  DateTime? lastUpdatedAt;

  /// Data-saver: true = cloud sync SIRF WiFi par. Social/mobile package ka
  /// data nahi lagega. WhatsApp reminders phir bhi chalte hain (WhatsApp app
  /// ke through, jo social packages me free hota hai).
  bool wifiOnlySync = false;

  void markUpdatedNow() {
    lastUpdatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> setWifiOnlySync(bool v) async {
    wifiOnlySync = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only_sync', v);
    notifyListeners();
  }

  /// Sync abhi ho sakta hai? Firebase laga ho + internet ho (+ wifi-only ho
  /// to sirf wifi). Offline ya social-package (mobile data) par false.
  Future<bool> _canSync() async {
    if (!FirebaseService.enabled) return false;
    try {
      final res = await Connectivity().checkConnectivity();
      if (res.contains(ConnectivityResult.none)) return false;
      if (wifiOnlySync &&
          !res.contains(ConnectivityResult.wifi) &&
          !res.contains(ConnectivityResult.ethernet)) {
        return false;
      }
      return true;
    } catch (_) {
      return true; // check na ho sake to koshish kar lo
    }
  }

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> get active =>
      _customers.where((c) => c.status != AccountStatus.cleared).toList();
  List<Customer> get overdue => _customers
      .where((c) =>
          c.status != AccountStatus.cleared && c.currentDue > 0)
      .toList();
  List<Customer> get cleared =>
      _customers.where((c) => c.status == AccountStatus.cleared).toList();

  /// Outstanding tab: pending dues. A customer stays here while currentDue
  /// > 0 — even Rs 1 left keeps them listed. Vouchered accounts (≥1 voucher
  /// entry) live in the Voucher tab instead.
  List<Customer> get outstanding => _customers
      .where((c) =>
          c.status != AccountStatus.cleared &&
          c.currentDue > 0 &&
          !hasVoucherEntries(c.accountNo))
      .toList();

  bool hasVoucherEntries(String accountNo) =>
      _vouchers.any((v) => v.accountNo == accountNo);

  /// Voucher tab: accounts grouped by A/C no, newest voucher first.
  List<VoucherGroup> get voucherGroups {
    final map = <String, List<VoucherEntry>>{};
    for (final v in _vouchers) {
      map.putIfAbsent(v.accountNo, () => []).add(v);
    }
    final groups = <VoucherGroup>[];
    for (final e in map.entries) {
      final c = findByAccountNo(e.key);
      final sorted = List<VoucherEntry>.from(e.value)
        ..sort((a, b) => b.date.compareTo(a.date));
      final first = sorted.first;
      groups.add(VoucherGroup(
        accountNo: e.key,
        customerName:
            first.customerName.isNotEmpty ? first.customerName : (c?.name ?? ''),
        phone: first.phone.isNotEmpty ? first.phone : (c?.cell ?? ''),
        entries: sorted,
      ));
    }
    groups.sort(
        (a, b) => b.entries.first.date.compareTo(a.entries.first.date));
    return groups;
  }

  int get voucherAccountCount => voucherGroups.length;

  double get totalVouchered =>
      _vouchers.fold(0.0, (s, v) => s + v.amount);

  /// All received payment entries (full + partial), newest first.
  List<ReceivedPayment> get receivedPayments =>
      List.unmodifiable(_payments);

  double get totalReceived =>
      _payments.fold(0.0, (s, p) => s + p.amount);

  /// "Is Mah Received" — sirf current month ki payments ka total.
  /// Naya mahina shuru hote hi ye 0 se start hota hai (list me history rehti hai).
  double get monthlyReceived {
    final mk = monthKey();
    return _payments
        .where((p) => p.month == mk)
        .fold(0.0, (s, p) => s + p.amount);
  }

  double get totalOutstanding =>
      active.fold(0, (s, c) => s + c.balance);
  double get totalDue => active.fold(0, (s, c) => s + c.currentDue);

  Map<String, List<Customer>> get byOfficer {
    final map = <String, List<Customer>>{};
    for (final c in active) {
      final key = c.officer.isEmpty ? '—' : c.officer;
      map.putIfAbsent(key, () => []).add(c);
    }
    return map;
  }

  /// Open (or create) this user's database.
  Future<void> init(String uid,
      {bool inMemory = false, void Function(String)? onStep}) async {
    _uid = uid;
    // inMemory = safe mode: asal file khul nahi saki to memory me kholo,
    // file ko haath lagaye baghair taake data mehfooz rahe.
    safeMode = inMemory;
    onStep?.call('Data file khol rahe hain…');
    final dbPath = inMemory
        ? inMemoryDatabasePath
        : p.join(await getDatabasesPath(), AuthService.userDbName(uid));
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE customers(account_no TEXT PRIMARY KEY, data TEXT, updated_at INTEGER)');
        await db.execute(
            'CREATE TABLE IF NOT EXISTS payments(id TEXT PRIMARY KEY, data TEXT)');
        await db.execute(
            'CREATE TABLE IF NOT EXISTS vouchers(id TEXT PRIMARY KEY, data TEXT)');
      },
      onUpgrade: (db, oldV, _) async {
        if (oldV < 2) {
          await db.execute(
              'CREATE TABLE IF NOT EXISTS vouchers(id TEXT PRIMARY KEY, data TEXT)');
        }
      },
    );
    onStep?.call('Data parh rahe hain…');
    await _loadAll();
    // Demo mode (no Firebase configured): seed the 5 real sample rows so the
    // UI can be checked immediately. Real Firebase setups start empty.
    if (_customers.isEmpty && !FirebaseService.enabled) {
      await _seedSampleData();
    }
    // Demo mode: one-time guarantor/collection enrichment for the samples —
    // also covers older installs that seeded before this existed.
    if (!FirebaseService.enabled) {
      await _enrichSampleDetails();
    }
    final prefs = await SharedPreferences.getInstance();
    wifiOnlySync = prefs.getBool('wifi_only_sync') ?? false;
    _sort();
    notifyListeners();
  }

  /// DB connection band karo (restore / reset se pehle zaroori).
  Future<void> closeDb() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
  }

  /// Safe mode se asal data file dobara kholne ki koshish.
  /// Kamyab ho to safeMode=false, na ho to wapas safe mode. Kabhi throw nahi karta.
  Future<bool> retryRealDb() async {
    final u = _uid;
    if (u == null) return false;
    try {
      await closeDb();
    } catch (_) {}
    try {
      await init(u).timeout(const Duration(seconds: 25));
      return !safeMode;
    } catch (e) {
      ErrorLog.log('SafeMode', e);
      try {
        await closeDb();
      } catch (_) {}
      try {
        await init(u, inMemory: true);
      } catch (_) {}
      return false;
    }
  }

  /// Load everything from the user's DB + run idempotent migrations.
  Future<void> _loadAll() async {
    final rows = await _db!.query('customers');
    _customers.clear();
    final rawMaps = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final m =
          jsonDecode(r['data'] as String) as Map<String, dynamic>;
      rawMaps[(r['account_no'] as String).toString()] = m;
      _customers.add(Customer.fromMap(m));
    }
    await _db!.execute(
        'CREATE TABLE IF NOT EXISTS payments(id TEXT PRIMARY KEY, data TEXT)');
    final prows = await _db!.query('payments');
    _payments.clear();
    for (final r in prows) {
      _payments.add(ReceivedPayment.fromMap(
          jsonDecode(r['data'] as String) as Map<String, dynamic>));
    }
    await _db!.execute(
        'CREATE TABLE IF NOT EXISTS vouchers(id TEXT PRIMARY KEY, data TEXT)');
    final vrows = await _db!.query('vouchers');
    _vouchers.clear();
    for (final r in vrows) {
      _vouchers.add(VoucherEntry.fromMap(
          jsonDecode(r['data'] as String) as Map<String, dynamic>));
    }
    // One-time migration: old "collectedLocally" flags (v1.0.6 and before)
    // become real payment entries so Received history is not lost.
    final migrated = <ReceivedPayment>[];
    for (final c in _customers) {
      if (c.collectedLocally) {
        final d = c.lastCollectedDate.isEmpty
            ? isoDate(DateTime.now())
            : c.lastCollectedDate;
        migrated.add(ReceivedPayment(
          id: '${c.accountNo}-migrated',
          accountNo: c.accountNo,
          customerName: c.name,
          amount: c.lastCollectedAmount,
          method: c.lastCollectedMethod.isEmpty
              ? 'Cash'
              : c.lastCollectedMethod,
          date: d,
          month: d.length >= 7 ? d.substring(0, 7) : monthKey(),
        ));
        c.collectedLocally = false;
        await _persistLocal(c);
      }
    }
    for (final p in migrated) {
      _payments.add(p);
      await _persistPayment(p);
    }
    // v1.0.7 migration: old inVoucher=true flag → one voucher entry
    // (amount = current due, date = today). Entries are the source of truth now.
    final today = isoDate(DateTime.now());
    for (final c in _customers) {
      final raw = rawMaps[c.accountNo];
      if (raw != null &&
          (raw['inVoucher'] == 1) &&
          !hasVoucherEntries(c.accountNo)) {
        final entry = VoucherEntry(
          id: '${c.accountNo}-voucher-migrated',
          accountNo: c.accountNo,
          customerName: c.name,
          phone: c.cell,
          amount: c.currentDue,
          date: today,
        );
        _vouchers.add(entry);
        await _persistVoucher(entry);
      }
    }
    _sort();
    _sortPayments();
    _sortVouchers();
  }

  /// Manual refresh: DB se dobara load + rollover check + totals recalc.
  Future<void> refreshData() async {
    await _loadAll();
    lastUpdatedAt = DateTime.now();
    notifyListeners();
  }

  // ------------------------------------------------------- monthly rollover

  /// Naya mahina (1st): har customer (balance > 0, vouchered NAHI) ki due
  /// dobara calculate hoti hai: currentDue + installment (balance se zyada nahi).
  /// Fully-paid-but-still-owing customers isi se Outstanding me wapas aate hain.
  /// Vouchered customers FROZEN hain — inki due khud se kabhi nahi badalti.
  /// Sirf ek dafa per month chalta hai (lastRolloverMonth guard).
  /// Returns: kitne customers ki due update hui.
  Future<int> maybeRollover() async {
    final prefs = await SharedPreferences.getInstance();
    final mk = monthKey();
    // Per-user guard: ek user ka rollover doosre user ko block na kare.
    final key = 'last_rollover_month_${_uid ?? 'noid'}';
    final last = prefs.getString(key);
    if (last == mk) return 0;
    if (last == null && DateTime.now().day != 1) {
      // Pehli dafa mid-month (upgrade/install): aaj 1st NAHI hai to due
      // mat barhao — sirf guard lagao taake agle mahine 1st ko chale.
      await prefs.setString(key, mk);
      return 0;
    }
    var n = 0;
    for (final c in _customers) {
      if (c.balance <= 0) continue;
      if (c.status == AccountStatus.cleared) continue;
      if (hasVoucherEntries(c.accountNo)) continue; // frozen
      final capped = (c.currentDue + c.monthlyInstallment) > c.balance
          ? c.balance
          : c.currentDue + c.monthlyInstallment;
      if ((capped - c.currentDue).abs() > 0.005) {
        c.currentDue = capped;
        if (c.currentDue > 0) c.status = AccountStatus.overdue;
        await _persistLocal(c);
        n++;
      }
    }
    await prefs.setString(key, mk);
    if (n > 0) {
      _sort();
      notifyListeners();
    }
    return n;
  }

  // --------------------------------------------------------------- vouchers

  void _sortVouchers() {
    _vouchers.sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _persistVoucher(VoucherEntry v) async {
    await _db?.insert(
      'vouchers',
      {'id': v.id, 'data': jsonEncode(v.toMap())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Voucher me naya entry add karo (ek customer ke kayi ho sakte hain).
  Future<void> addVoucherEntry(VoucherEntry v) async {
    _vouchers.add(v);
    await _persistVoucher(v);
    _sortVouchers();
    notifyListeners();
  }

  /// Ek voucher entry delete karo (confirm dialog UI me hota hai).
  Future<void> deleteVoucherEntry(String id) async {
    _vouchers.removeWhere((e) => e.id == id);
    await _db?.delete('vouchers', where: 'id = ?', whereArgs: [id]);
    _sortVouchers();
    notifyListeners();
  }

  /// "Voucher se wapas": is account ki saari entries hatao → customer
  /// Voucher tab se nikal kar (due > 0 ho to) Outstanding me wapas aayega.
  Future<void> clearVouchersFor(String accountNo) async {
    final ids = _vouchers
        .where((e) => e.accountNo == accountNo)
        .map((e) => e.id)
        .toList();
    _vouchers.removeWhere((e) => e.accountNo == accountNo);
    for (final id in ids) {
      await _db?.delete('vouchers', where: 'id = ?', whereArgs: [id]);
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- payments

  void _sortPayments() {
    _payments.sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _persistPayment(ReceivedPayment p) async {
    await _db?.insert(
      'payments',
      {
        'id': p.id,
        'data': jsonEncode(p.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Collect a (possibly partial) payment: records a ReceivedPayment entry
  /// and reduces the customer's currentDue + balance.
  /// The customer stays in Outstanding/Voucher while currentDue > 0 —
  /// only an exact 0 removes them from the list.
  /// Returns false when the amount is invalid (0 < amount <= currentDue).
  Future<bool> collectPayment(
    Customer c, {
    required double amount,
    required String method,
    required String date,
  }) async {
    if (amount <= 0 || amount > c.currentDue + 0.001) return false;
    final pay = amount > c.currentDue ? c.currentDue : amount;
    final entry = ReceivedPayment(
      id: '${c.accountNo}-${DateTime.now().millisecondsSinceEpoch}',
      accountNo: c.accountNo,
      customerName: c.name,
      amount: pay,
      method: method,
      date: date,
      month: date.length >= 7 ? date.substring(0, 7) : monthKey(),
    );
    _payments.add(entry);
    await _persistPayment(entry);
    c.currentDue = c.currentDue - pay;
    if (c.currentDue < 0.005) c.currentDue = 0;
    c.balance = c.balance - pay;
    if (c.balance < 0) c.balance = 0;
    c.lastCollectedAmount = pay;
    c.lastCollectedMethod = method;
    c.lastCollectedDate = date;
    await _persist(c);
    _sort();
    _sortPayments();
    notifyListeners();
    return true;
  }

  /// Undo one received payment: the entry is removed and the amount is
  /// added back to the customer's currentDue + balance. The customer
  /// automatically reappears in Outstanding (or stays in Voucher if entries exist).
  Future<void> undoPayment(ReceivedPayment p) async {
    _payments.removeWhere((e) => e.id == p.id);
    await _db?.delete('payments', where: 'id = ?', whereArgs: [p.id]);
    final c = findByAccountNo(p.accountNo);
    if (c != null) {
      c.currentDue = c.currentDue + p.amount;
      c.balance = c.balance + p.amount;
      await _persist(c);
    }
    _sort();
    _sortPayments();
    notifyListeners();
  }

  // ------------------------------------------------------- manual customer

  /// Haath se customer add karo (Customers tab "+"). Paisa wale fields
  /// import-only hain — yahan sirf contact/info fields.
  /// Returns: error string, ya null = success.
  Future<String?> addCustomerManually({
    required String name,
    required String cell,
    required String tel,
    required String accountNo,
    required String notes,
  }) async {
    name = name.trim();
    accountNo = accountNo.trim();
    if (name.isEmpty) return 'Naam likhen';
    if (accountNo.isEmpty) return 'A/C No. likhen';
    if (findByAccountNo(accountNo) != null) {
      return 'Ye A/C No. pehle se maujood hai';
    }
    final c = Customer(
      accountNo: accountNo,
      name: name,
      cell: cell.trim(),
      telRes: tel.trim(),
      notes: notes.trim(),
    );
    _customers.add(c);
    await _persist(c);
    _sort();
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------------ sync

  /// Bind the store to a Firebase user: pull their private cloud data and
  /// merge it into the local cache (cloud wins on conflict — imports are the
  /// only writers, so conflicts are rare).
  Future<void> bindUser(String uid) async {
    if (_uid == uid && _boundOnce) return;
    _boundOnce = true;
    if (!await _canSync()) return; // offline / data-saver: local hi kaafi
    try {
      final remote =
          await FirebaseService.instance.pullCustomers(uid);
      for (final m in remote) {
        final c = Customer.fromMap(m);
        final i =
            _customers.indexWhere((e) => e.accountNo == c.accountNo);
        if (i >= 0) {
          _customers[i] = c;
        } else {
          _customers.add(c);
        }
        await _persistLocal(c);
      }
      _sort();
      notifyListeners();
    } catch (_) {
      // Offline: keep working with the local cache.
    }
  }

  bool _boundOnce = false;

  Future<void> logImport(Map<String, dynamic> info) async {
    final uid = _uid;
    if (uid == null) return;
    if (!await _canSync()) return; // offline / data-saver: sirf local
    try {
      await FirebaseService.instance.logImport(uid, info);
    } catch (_) {}
  }

  void _sort() {
    _customers.sort((a, b) {
      // overdue first, then by due amount
      final ao = a.currentDue > 0 ? 0 : 1;
      final bo = b.currentDue > 0 ? 0 : 1;
      if (ao != bo) return ao - bo;
      return b.currentDue.compareTo(a.currentDue);
    });
  }

  Future<void> _persistLocal(Customer c) async {
    await _db?.insert(
      'customers',
      {
        'account_no': c.accountNo,
        'data': jsonEncode(c.toMap()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Local write + cloud push (sirf jab sync mumkin ho; offline sab local).
  Future<void> _persist(Customer c) async {
    await _persistLocal(c);
    final uid = _uid;
    if (uid == null) return;
    if (!await _canSync()) return;
    try {
      await FirebaseService.instance
          .pushCustomer(uid, c.accountNo, c.toMap());
    } catch (_) {}
  }

  Customer? findByAccountNo(String accountNo) {
    for (final c in _customers) {
      if (c.accountNo == accountNo) return c;
    }
    return null;
  }

  /// Apply one outstanding row: update the matched customer, or create a
  /// lightweight record (flagged needsDetail) when the A/C is new.
  /// Returns 'updated' | 'created'.
  Future<String> applyOutstandingRow(OutstandingRow row) async {
    final existing = findByAccountNo(row.accountNo);
    if (existing != null) {
      existing.balance = row.balance;
      existing.osAmount = row.osAmount;
      existing.paid = row.paid;
      existing.currentDue = row.currentDue;
      existing.lastInstDate = row.lastInstDate;
      existing.monthlyInstallment = row.installment;
      if (existing.name.isEmpty) existing.name = row.name;
      if (existing.cell.isEmpty) existing.cell = row.cell;
      if (existing.item.isEmpty) existing.item = row.item;
      if (existing.officer.isEmpty) existing.officer = row.officer;
      existing.status = row.currentDue > 0
          ? AccountStatus.overdue
          : AccountStatus.active;
      // Reconcile with local collection: fresh import shows nothing due
      // anymore → the locally-collected flag is no longer needed.
      if (existing.collectedLocally && row.currentDue == 0) {
        existing.collectedLocally = false;
      }
      await _persist(existing);
      _sort();
      notifyListeners();
      return 'updated';
    }
    final c = Customer(
      accountNo: row.accountNo,
      name: row.name,
      cell: row.cell,
      item: row.item,
      price: row.price,
      monthlyInstallment: row.installment,
      balance: row.balance,
      osAmount: row.osAmount,
      paid: row.paid,
      currentDue: row.currentDue,
      lastInstDate: row.lastInstDate,
      accountDate: row.accDate,
      officer: row.officer,
      status: row.currentDue > 0 ? AccountStatus.overdue : AccountStatus.active,
      needsDetail: true,
    );
    _customers.add(c);
    await _persist(c);
    _sort();
    notifyListeners();
    return 'created';
  }

  /// After an outstanding import, mark previously-active accounts that were
  /// NOT in the new list as cleared (their qist finished).
  /// Vouchered accounts are skipped (frozen — import unko nahi chhoota).
  /// Returns the number marked cleared.
  Future<int> markMissingAsCleared(Set<String> importedAccountNos) async {
    var n = 0;
    for (final c in _customers) {
      if (c.status != AccountStatus.cleared &&
          !importedAccountNos.contains(c.accountNo) &&
          !hasVoucherEntries(c.accountNo)) {
        c.status = AccountStatus.cleared;
        c.currentDue = 0;
        await _persist(c);
        n++;
      }
    }
    if (n > 0) {
      _sort();
      notifyListeners();
    }
    return n;
  }

  Future<void> saveCustomer(Customer c) async {
    final i = _customers.indexWhere((e) => e.accountNo == c.accountNo);
    if (i >= 0) {
      _customers[i] = c;
    } else {
      _customers.add(c);
    }
    await _persist(c);
    _sort();
    notifyListeners();
  }

  List<Customer> search(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return active;
    return active
        .where((c) =>
            c.name.toLowerCase().contains(query) ||
            c.accountNo.contains(query) ||
            c.cell.contains(query))
        .toList();
  }

  // ------------------------------------------------------------ sample data

  /// Sample rows transcribed from the real outstanding print — only for the
  /// offline demo build so screens can be checked without an import.
  Future<void> _seedSampleData() async {
    final samples = [
      OutstandingRow(
          accountNo: '003077',
          accDate: '19-Jul-26',
          name: 'Naeem Akhtar',
          officer: 'Sajjad Ahmed',
          cell: '03216512528',
          item: 'SOLAR+FAN',
          price: 285000,
          balance: 185000,
          installment: 46250,
          osAmount: 92500,
          paid: 0,
          currentDue: 92500,
          lastInstDate: '19-Jul-26'),
      OutstandingRow(
          accountNo: '002910',
          accDate: '16-Mar-26',
          name: 'Shahid nadeem Ahmed',
          officer: 'Sajjad Ahmed',
          cell: '03046856156',
          item: 'MOBILE',
          price: 174000,
          balance: 87000,
          installment: 14500,
          osAmount: 14500,
          paid: 8000,
          currentDue: 6500,
          lastInstDate: '29-Sep-26'),
      OutstandingRow(
          accountNo: '002847',
          accDate: '9-Feb-26',
          name: 'Adil Ali',
          officer: 'Sajjad Ahmed',
          cell: '03256266863',
          item: 'LED',
          price: 48000,
          balance: 20000,
          installment: 4000,
          osAmount: 4000,
          paid: 3000,
          currentDue: 1000,
          lastInstDate: '12-Sep-26'),
      OutstandingRow(
          accountNo: '002796',
          accDate: '9-Jan-26',
          name: 'Ikram',
          officer: 'Sajjad Ahmed',
          cell: '03152444967',
          item: 'MOBILE',
          price: 43800,
          balance: 14600,
          installment: 3650,
          osAmount: 3650,
          paid: 1850,
          currentDue: 1800,
          lastInstDate: '21-Sep-26'),
      OutstandingRow(
          accountNo: '002580',
          accDate: '19-Oct-25',
          name: 'M Afzal',
          officer: 'Sajjad Ahmed',
          cell: '03015215248',
          item: 'BIKE',
          price: 212000,
          balance: 27000,
          installment: 13500,
          osAmount: 13500,
          paid: 10000,
          currentDue: 3500,
          lastInstDate: '28-Sep-26'),
    ];
    for (final r in samples) {
      await applyOutstandingRow(r);
    }
    await _enrichSampleDetails();
    lastUpdatedAt = DateTime.now();
  }

  /// Demo-only: attach guarantors + installment-collection history to the
  /// sample customers so the detail screen shows real-looking data.
  /// - Runs only in demo mode (callers check !FirebaseService.enabled).
  /// - Only touches lightweight outstanding-only records (needsDetail) whose
  ///   guarantors/collections are still empty → real imported data is never
  ///   overwritten.
  /// - Runs once per install (SharedPreferences flag) so older demo
  ///   installs get it too.
  Future<void> _enrichSampleDetails() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('sample_enriched_v1') ?? false) return;

    final naeem = findByAccountNo('003077');
    if (naeem != null &&
        naeem.needsDetail &&
        naeem.guarantors.isEmpty &&
        naeem.collections.isEmpty) {
      naeem.guarantors.addAll([
        Guarantor(
            name: 'Rashid Mehmood',
            cnic: '35202-1234567-8',
            address: 'House 12, Street 4, Model Town, Lahore',
            phone: '03001234567'),
        Guarantor(
            name: 'Aslam Khan',
            cnic: '35202-7654321-9',
            address: 'Shop 8, Main Bazaar, Lahore',
            phone: '03219876543'),
      ]);
      naeem.collections.addAll([
        CollectionEntry(
            receiptNo: 'R-1001',
            date: '19-Jul-26',
            prevBalance: 285000,
            collected: 100000,
            balance: 185000,
            receivedBy: 'Sajjad Ahmed'),
        CollectionEntry(
            receiptNo: 'R-1042',
            date: '19-Aug-26',
            prevBalance: 185000,
            collected: 0,
            balance: 185000,
            receivedBy: 'Sajjad Ahmed'),
      ]);
      await saveCustomer(naeem);
    }

    final shahid = findByAccountNo('002910');
    if (shahid != null &&
        shahid.needsDetail &&
        shahid.guarantors.isEmpty &&
        shahid.collections.isEmpty) {
      shahid.guarantors.add(
        Guarantor(
            name: 'Bilal Hussain',
            cnic: '35202-1122334-5',
            address: 'House 45, Block C, DHA Phase 2, Lahore',
            phone: '03334445566'),
      );
      shahid.collections.addAll([
        CollectionEntry(
            receiptNo: 'R-2088',
            date: '16-Mar-26',
            prevBalance: 174000,
            collected: 50000,
            balance: 124000,
            receivedBy: 'Sajjad Ahmed'),
        CollectionEntry(
            receiptNo: 'R-2150',
            date: '29-Sep-26',
            prevBalance: 95000,
            collected: 8000,
            balance: 87000,
            receivedBy: 'Sajjad Ahmed'),
      ]);
      await saveCustomer(shahid);
    }

    await prefs.setBool('sample_enriched_v1', true);
  }
}
