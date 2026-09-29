/// Local login / signup / forgot-password, fully on-device.
/// Users live in a small separate DB (app_users.db). Har user ka apna
/// data alag file me hota hai: qistbook_<uid>.db
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user.dart';

class AuthResult {
  final AppUser? user;
  final String? error; // Roman Urdu message
  const AuthResult.ok(this.user) : error = null;
  const AuthResult.fail(this.error) : user = null;
  bool get ok => user != null;
}

class AuthService {
  static const _sessionKey = 'session_uid';
  static const _legacyDbName = 'kistbook.db';

  Database? _db;
  String? _sessionUid;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'app_users.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE users(id TEXT PRIMARY KEY, data TEXT)');
      },
    );
    final prefs = await SharedPreferences.getInstance();
    _sessionUid = prefs.getString(_sessionKey);
    if (_sessionUid != null) {
      _currentUser = await _findById(_sessionUid!);
      if (_currentUser == null) {
        _sessionUid = null;
        await prefs.remove(_sessionKey);
      }
    }
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  String _uuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<List<AppUser>> _all() async {
    final rows = await _db!.query('users');
    return rows
        .map((r) => AppUser.fromMap(
            jsonDecode(r['data'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(AppUser u) async {
    await _db!.insert(
      'users',
      {'id': u.id, 'data': jsonEncode(u.toMap())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AppUser?> _findById(String id) async {
    final rows =
        await _db!.query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return AppUser.fromMap(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<AppUser?> findByIdentifier(String identifier) async {
    final key = identifier.trim().toLowerCase();
    for (final u in await _all()) {
      if (u.email.trim().toLowerCase() == key ||
          u.phone.replaceAll(RegExp(r'\D'), '') ==
              key.replaceAll(RegExp(r'\D'), '')) {
        return u;
      }
    }
    return null;
  }

  bool get hasAnyUser => _hasAnyUserCached;
  bool _hasAnyUserCached = false;

  Future<bool> checkHasAnyUser() async {
    final rows =
        await _db!.rawQuery('SELECT COUNT(*) AS n FROM users');
    _hasAnyUserCached = ((rows.first['n'] as int?) ?? 0) > 0;
    return _hasAnyUserCached;
  }

  /// Legacy (v1.0.7 tak) single DB: does it exist and have customers?
  Future<bool> legacyDbHasData() async {
    try {
      final dir = await getDatabasesPath();
      final file = File(p.join(dir, _legacyDbName));
      if (!await file.exists()) return false;
      final db = await openDatabase(file.path, readOnly: true);
      try {
        final rows =
            await db.rawQuery('SELECT COUNT(*) AS n FROM customers');
        return ((rows.first['n'] as int?) ?? 0) > 0;
      } finally {
        await db.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Adopt the legacy DB as this user's DB (rename file). Call right after
  /// first signup when legacy data was found. Old file must not be open.
  Future<void> adoptLegacyDb(String uid) async {
    final dir = await getDatabasesPath();
    final from = File(p.join(dir, _legacyDbName));
    final to = File(p.join(dir, 'qistbook_$uid.db'));
    if (await from.exists() && !await to.exists()) {
      await from.rename(to.path);
    }
  }

  static String userDbName(String uid) => 'qistbook_$uid.db';

  // ------------------------------------------------------------ validation

  static bool validEmail(String e) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

  static bool validPhone(String ph) {
    final d = ph.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 && d.length <= 13;
  }

  // ---------------------------------------------------------------- signup

  Future<AuthResult> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String confirm,
  }) async {
    name = name.trim();
    email = email.trim();
    phone = phone.trim();
    if (name.isEmpty) {
      return const AuthResult.fail('Apna naam likhen');
    }
    if (email.isEmpty && phone.isEmpty) {
      return const AuthResult.fail(
          'Email ya phone number — ek zaroor likhen');
    }
    if (email.isNotEmpty && !validEmail(email)) {
      return const AuthResult.fail('Email sahi nahi lag rahi');
    }
    if (phone.isNotEmpty && !validPhone(phone)) {
      return const AuthResult.fail('Phone number sahi nahi lag raha');
    }
    if (password.length < 4) {
      return const AuthResult.fail(
          'Password kam se kam 4 harf ka ho');
    }
    if (password != confirm) {
      return const AuthResult.fail(
          'Dono password ek jaise nahi hain');
    }
    if (email.isNotEmpty &&
        await findByIdentifier(email) != null) {
      return const AuthResult.fail(
          'Ye email pehle se istemal ho rahi hai');
    }
    if (phone.isNotEmpty &&
        await findByIdentifier(phone) != null) {
      return const AuthResult.fail(
          'Ye number pehle se istemal ho raha hai');
    }
    final id = _uuid();
    final user = AppUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      passwordHash: _hash(password, id),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _save(user);
    _hasAnyUserCached = true;
    await _setSession(user);
    return AuthResult.ok(user);
  }

  // ----------------------------------------------------------------- login

  Future<AuthResult> login(String identifier, String password) async {
    final user = await findByIdentifier(identifier);
    if (user == null) {
      return const AuthResult.fail(
          'Ye email/number registered nahi hai');
    }
    if (user.passwordHash != _hash(password, user.id)) {
      return const AuthResult.fail('Password ghalat hai');
    }
    await _setSession(user);
    return AuthResult.ok(user);
  }

  // -------------------------------------------------------- forgot password

  Future<AuthResult> resetPassword(
      String identifier, String password, String confirm) async {
    final user = await findByIdentifier(identifier);
    if (user == null) {
      return const AuthResult.fail(
          'Ye email/number registered nahi hai');
    }
    if (password.length < 4) {
      return const AuthResult.fail(
          'Password kam se kam 4 harf ka ho');
    }
    if (password != confirm) {
      return const AuthResult.fail(
          'Dono password ek jaise nahi hain');
    }
    final updated =
        user.copyWith(passwordHash: _hash(password, user.id));
    await _save(updated);
    if (_currentUser?.id == updated.id) _currentUser = updated;
    return AuthResult.ok(updated);
  }

  Future<void> updateProfile(AppUser updated) async {
    await _save(updated);
    if (_currentUser?.id == updated.id) _currentUser = updated;
  }

  Future<void> _setSession(AppUser user) async {
    _sessionUid = user.id;
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, user.id);
  }

  Future<void> logout() async {
    _sessionUid = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Refresh current user from DB (e.g. after profile edit elsewhere).
  Future<void> reloadCurrent() async {
    if (_sessionUid != null) {
      _currentUser = await _findById(_sessionUid!);
    }
  }
}
