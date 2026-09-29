import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import 'firebase_service.dart';
import 'parsers.dart';

/// Local-first storage for Kist Book (sqflite) + ChangeNotifier store.
/// Firestore (per-user, private) is the source of truth and syncs across the
/// user's devices; sqflite is the offline cache.
///
/// READ-ONLY by design: customer records are never edited by hand in the UI.
/// They change only through statement/outstanding imports, matched by A/C No.
class CustomerStore extends ChangeNotifier {
  Database? _db;
  final List<Customer> _customers = [];
  String? _uid;

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

  Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'kistbook.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE customers(account_no TEXT PRIMARY KEY, data TEXT, updated_at INTEGER)');
      },
    );
    final rows = await _db!.query('customers');
    _customers.clear();
    for (final r in rows) {
      _customers.add(Customer.fromMap(
          jsonDecode(r['data'] as String) as Map<String, dynamic>));
    }
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

  /// Bind the store to a Firebase user: pull their private cloud data and
  /// merge it into the local cache (cloud wins on conflict — imports are the
  /// only writers, so conflicts are rare).
  Future<void> bindUser(String uid) async {
    if (_uid == uid) return;
    _uid = uid;
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
  /// Returns the number marked cleared.
  Future<int> markMissingAsCleared(Set<String> importedAccountNos) async {
    var n = 0;
    for (final c in _customers) {
      if (c.status != AccountStatus.cleared &&
          !importedAccountNos.contains(c.accountNo)) {
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
}
